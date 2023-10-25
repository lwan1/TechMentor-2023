# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"


# Variables
$WorkspaceId   = ""
$WorkspaceKey  = ""



$LogTypeName="AvdBehind"
$TimeStampField="TimeStamp"





# Modules
if (-not (Get-Module -Name Az.DesktopVirtualization -ListAvailable)) {
    Import-Module -Name Az.DesktopVirtualization
}


# Functions
# Source: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}
# Source: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api
Function Post-OMSData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature -customerId $customerId -sharedKey $sharedKey -date $rfc1123date -contentLength $contentLength -method $method -contentType $contentType -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }
    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode
}



# Main
$pools=Get-AzWvdHostPool
$now=(Get-Date).ToString("o")

Write-Host "Starting iteration at $now"
Write-Host "Get $($pools.Count) host pools"


$pools | ForEach {
    $hostPoolName=$_.Name
    Write-Host "`nWorking on pool $hostPoolName"
    $rg=$_.Id.Split("/")[4]
    $sessionHosts=Get-AzWvdSessionHost -HostPoolName $_.Name -ResourceGroupName $rg
    $sessionHosts | Add-Member -MemberType NoteProperty -Name "TimeStamp" -Value $now
    Write-Host "Number of session hosts: $($sessionHosts.Count)"

    # Send to log analytics
    if ($sessionHosts.Count -gt 0) {
        $response=Post-OMSData -customerId $WorkspaceId -sharedKey $WorkspaceKey -body ([System.Text.Encoding]::UTF8.GetBytes(($sessionHosts | ConvertTo-Csv|ConvertFrom-Csv|ConvertTo-Json -Depth 5))) -logType $LogTypeName
        Write-Host "Data uploaded to $WorkspaceId. Response code: ",$response
    }

}