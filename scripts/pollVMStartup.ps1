#requires -Modules Hyper-V
## #requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string] $vmName
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

write-host "wait for vm to boot"
do {
  #get heartbeat status
  $heartbeat = (Get-VMIntegrationService -VMName $vmName | Where-Object Name -eq "Heartbeat").PrimaryStatusDescription

  if ($heartbeat -ne "OK") {
      Write-host "." -NoNewline
      Start-Sleep -Seconds 2
  }
} while ($heartbeat -ne "OK")

return $true
