# Rollout a VM from image, join domain and an AVD host pool

if ((Test-Path -Path "ITPC-WVD-Image-Processing.ps1") -eq $false) {
    Write-Warning "Please navigate to the script path containing the ITPC-... file"
    break
}

Connect-AzAccount -TenantId "c79b2f74-6012-46c3-ad68-326cca9c012e"
Get-AzSubscription | Where-Object {$_.Id -ne "05b51e73-212a-4ad7-826c-2e8f68396e06"} | Select-AzSubscription

####### Change the following lines ##########

# My 2-digit number:
$myId         = "14"
$ImageName    = "T-AVD-14-A_2023-07-17_12-58"

$ImageRg      = "avd-templates-$($myId)"

$HostPoolName = "hp-lab-windows11Pooled"
$HostPoolRg   = "avd-resources-$($myId)"

$HostName     = "AVD-A-$($myId)-01"
$HostRg       = "avd-vms-$($myId)"

# Id of the target subnet
$SubNetId="/subscriptions/$((Get-AzSubscription| Where-Object {$_.Id -ne "05b51e73-212a-4ad7-826c-2e8f68396e06"}).Id)/resourceGroups/avd-networking/providers/Microsoft.Network/virtualNetworks/avd-networking/subnets/default"

$DomainJoinUserName     = "svc-add-host@avdlab.local"
$DomainJoinUserPassword = "T@chMent0r2023---!"
$DomainFqdn             = "avdlab.local"
$DomainJoinOU           = "OU=$($myId),OU=Hosts,OU=AVD,OU=Azure,OU=Systems,OU=Lab,DC=avdlab,DC=local"
#############################################


# get location
$vnet=Get-AzVirtualNetwork -ResourceGroupName $SubNetId.Split("/")[4] -Name $SubNetId.Split("/")[8]
$location=$vnet.Location

# New nic for the host
$nic = New-AzNetworkInterface -Name $HostName -ResourceGroupName $HostRg -Location $location -SubnetId $SubNetId

# Local credentials
$psc = New-Object System.Management.Automation.PSCredential("vmAdmin", (ConvertTo-SecureString "SuperTemoSecr@t" -AsPlainText -Force))

# Create VM
$diskSource = Get-AzImage -ResourceGroupName $ImageRg -ImageName $ImageName
$vmConfig = New-AzVMConfig -VMName $HostName -VMSize Standard_D2as_v5
$vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $diskSource.Id
$vmConfig=Set-AzVMOperatingSystem -VM $vmConfig -ComputerName $HostName -Windows  -EnableAutoUpdate -Credential $psc
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
New-AzVM -VM $vmConfig  -ResourceGroupName $HostRg -Location $location


# Get host pool token (note: can fail if no token exist right now)
$token=(Get-AzWvdRegistrationInfo -HostPoolName $HostPoolName -ResourceGroupName $HostPoolRg).Token

# Configure parameter for the magic script: domain join, ....
$param = @{"-Mode" = "JoinDomain";"DomainJoinUserName" = $DomainJoinUserName; "DomainJoinUserPassword" = $DomainJoinUserPassword; "DomainFqdn" = $DomainFqdn; "DomainJoinOU" = $DomainJoinOU; "WvdRegistrationKey" = $token}

# Run the script on VM
Invoke-AzVMRunCommand -ResourceGroupName $HostRg -Name $HostName -CommandId "RunPowerShellScript" -ScriptPath "ITPC-WVD-Image-Processing.ps1" -Parameter $param



