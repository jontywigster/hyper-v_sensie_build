#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory = $true)]
  [string] $vmName,
  [switch[]] $windows
)

$verbosePref=(Get-Variable -Name VerbosePreference).Value

Import-Module Hyper-V
Write-Host "Waiting for build to start"

function prettyPrint($buildStatus) {
  switch ($buildStatus) {
       "no gei" {$pretty="Waiting for OS"; Break }
       "base" {$pretty="Ansible build"; Break }
       "circ" {$pretty="cloud-init started"; Break }
       "dock" {$pretty="Docker install"; Break }
       "done" {$pretty="done"; Break }
       "inan" {$pretty="cloud-init runcmd"; Break }
       "pull" {$pretty="call ansible-pull"; Break }
       "rebo" {$pretty="rebooted"; Break }
  }
  return $pretty
}

if ($windows) {
  $buildStatus = getWindowsKVPBuildStatus 
} else {
  $buildStatus = getKVPBuildStatus
}

$previousStatus = $buildStatus

while ($buildStatus -ne "done") {
    Start-Sleep -Seconds 3

    $buildStatus = ($windows) ? $(getWindowsKVPBuildStatus) : $(prettyPrint(getKVPBuildStatus))

    if ($null -eq $buildStatus) {
        Write-Host -NoNewline "."
    } else {
        if ($buildStatus -eq $previousStatus) {
            Write-Host -NoNewline "."
        } else {
            Write-Host "`r`n$($buildStatus)"
            $previousStatus = $buildStatus
        }
    }
}

$VerbosePreference = $verbosePref
