# Create a custom image from a golden master (without destroying the master)

if ((Test-Path -Path "ITPC-WVD-Image-Processing.ps1") -eq $false) {
    Write-Warning "Please navigate to the script path containing the ITPC-... file"
    break
}

Connect-AzAccount -TenantId "c79b2f74-6012-46c3-ad68-326cca9c012e"
Get-AzSubscription | Where-Object {$_.Id -ne "05b51e73-212a-4ad7-826c-2e8f68396e06"} | Select-AzSubscription


####### Change the following lines ##########
$MasterVmName = "T-AVD-14-A"
$MasterVmRg   = "avd-templates-14"
#############################################


$timeStampString=(Get-Date).ToString("yyyy-MM-dd_HH-mm")
$TempVmName="TEMP-VM-$($MasterVmName)_$timeStampString"
$ImageName="$($MasterVmName)_$timeStampString"


# Get Master
$MasterVm = Get-AzVm -ResourceGroupName $MasterVmRg -Name $MasterVmName

# Get location
$location = $MasterVm.Location
$location

# Get network configuration
$MasterNet = Get-AzNetworkInterface -ResourceId $MasterVm.NetworkProfile.NetworkInterfaces[0].Id
$MasterNet.IpConfigurations[0].Subnet.Id

# New nic for the TempVm
$TempNic = New-AzNetworkInterface -Name $TempVmName -ResourceGroupName $MasterVmRg -Location $location -SubnetId $MasterNet.IpConfigurations[0].Subnet.Id

# New Snapshot from master os disk
$snapShotConfig =  New-AzSnapshotConfig -SourceUri $MasterVm.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy
$snapShot = New-AzSnapshot -Snapshot $snapShotConfig -SnapshotName $TempVmName -ResourceGroupName $MasterVmRg 

# New disk for TempVm
$diskConfig = New-AzDiskConfig -Location $location -SourceResourceId $snapShot.Id -CreateOption Copy -SkuName Standard_LRS
$disk = New-AzDisk -Disk $diskConfig -ResourceGroupName $MasterVmRg -DiskName "$TempVmName-disk0"

# Local credentials
$psc = New-Object System.Management.Automation.PSCredential("vmAdmin", (ConvertTo-SecureString  "SuperTemoSecr@t1234567@TechMent0r" -AsPlainText -Force))


# Create TempVm
$VmConfig = New-AzVMConfig -VMName $TempVmName -VMSize $MasterVm.HardwareProfile.VmSize
$VmConfig = Add-AzVMNetworkInterface -VM $VmConfig -Id $TempNic.Id
$vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
$VmConfig = Set-AzVMOSDisk -VM $VmConfig -ManagedDiskId $disk.Id -CreateOption Attach -Windows

New-AzVm -VM $VmConfig -ResourceGroupName $MasterVmRg -Location $location

# Run special script on VM
Invoke-AzVMRunCommand -ResourceGroupName $MasterVmRg -Name $TempVmName -CommandId "RunPowerShellScript" -ScriptPath "ITPC-WVD-Image-Processing.ps1" -Parameter @{"-Mode" = "Generalize"}

# Wait for VM
do {
	Write-Host("Waiting for shutdown")
	Start-Sleep 15
} while ((Get-AzVm -ResourceGroupName $MasterVmRg -VMName $TempVmName -Status).Statuses[1].Code -ne "PowerState/stopped")

# Generalize and grab image
$MasterVmStatus = Get-AzVm -ResourceGroupName $MasterVmRg -Name $MasterVmName -Status
Set-AzVM -ResourceGroupName $MasterVmRg -Name $TempVmName -Generalized
$TempVm=Get-AzVM -ResourceGroupName $MasterVmRg -Name $TempVmName 
$newImageConfig = New-AzImageConfig -Location $location -SourceVirtualMachineId $TempVm.Id -HyperVGeneration $MasterVmStatus.HyperVGeneration
New-AzImage -Image $newImageConfig -ImageName $ImageName -ResourceGroupName $MasterVmRg

# Clean-up
$TempVm | Remove-AzVM -Force
$disk | Remove-AzDisk -Force
$TempNic | Remove-AzNetworkinterface -Force
$snapShot | Remove-AzSnapshot -Force