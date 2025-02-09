#requires -Modules Hyper-V
## #requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string] $vmId,
  [datetime]$startDT

)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

#set default value if startDT not supplied 
if (-not $PSBoundParameters.ContainsKey('startDT')) { $startDT = (Get-Date) }

$LogName = 'Microsoft-Windows-Hyper-V-Worker-Admin'
$eventIDs = @(18500,18601,18502)
$eventIDsString = $eventIDs -join " or EventID="
$vmId=$vmId.ToUpper()

$query = @"
<QueryList>
  <Query Id="0" Path="$LogName">
    <Select Path="$LogName"> 
    *[UserData[VmlEventLog[(VmId='$vmId')]]] 
    and 
    *[System[TimeCreated[@SystemTime>='$($startDT.ToUniversalTime().ToString("o"))']]] 
    and 
    *[System[(EventID=$eventIDsString)]]
    </Select>
  </Query>
</QueryList>
"@

# Monitor the event logs for the specified event IDs and VM name using FilterXML
$buildStatus = "Waiting for VM to boot"
$previousStatus = ""
$finalStatus = "*successfully booted an operating system*"

Write-Host "`n$buildStatus"

while ($true) {
  $events = Get-WinEvent -FilterXML $query -ErrorAction SilentlyContinue
  foreach ($event in $events) {
    #Write-Host "$($event.Message)"
    $trimMessage = $event.Message.Split("(")[0]
    #$buildStatus = "$($event.TimeCreated): $trimMessage"
    $buildStatus = "$trimMessage"

    if ($buildStatus -ne $previousStatus) {
      Write-Host "$buildStatus"
      if ($buildStatus -like $finalStatus) { return "" }
      $previousStatus = $buildStatus
    }
    else {
      Write-Host -NoNewline "."
    }
  }

  Start-Sleep -Seconds 5
}

return ""
