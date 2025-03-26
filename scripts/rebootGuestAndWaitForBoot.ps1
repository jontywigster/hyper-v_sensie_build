#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)]
    [string] $vmName
)

Write-Host "restart $vmName"
#restart VM
Restart-VM -Name $vmName -Force

Write-Host "wait for $vmName to start"
#wait VM to come back online
do {
    Start-Sleep -Seconds 5
    $vmStatus = (Get-VM -Name $vmName).State
    Write-Host "$vmName $vmStatus"
} until ($vmStatus -eq "Running")
