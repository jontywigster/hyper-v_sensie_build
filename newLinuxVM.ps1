<#
Based on
https://github.com/schtritoff/hyperv-vm-provisioning
Cheers
#>

#requires -Modules Hyper-V

$adminCheck = [Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())
if ( !($adminCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
  $path = "'" + $PSScriptRoot + "'"
  $scriptName = ".\" + $MyInvocation.MyCommand.Name
  Start-Process Powershell.exe -ArgumentList "-ExecutionPolicy bypass", "-command", "cd", "$path; $scriptName"  -Verb RunAs
  exit
}

# default error action
$ErrorActionPreference = 'Stop'
$VerbosePreference = "SilentlyContinue"

# Get default Virtual Machine path (requires administrative privileges)
$hostVMFolder = (Get-VMHost).VirtualMachinePath
if (-not $hostVMFolder) {
  throw "Couldn't get VirtualMachinePath from Get-VMHost"
}

#prompt for os
$aOS = @(
  New-Object System.Management.Automation.Host.ChoiceDescription "&1 alma", "Enter 1 for alma"
  New-Object System.Management.Automation.Host.ChoiceDescription "&2 debian", "Enter 2 for debian"
  New-Object System.Management.Automation.Host.ChoiceDescription "&3 debianAz", "Enter 3 for debian azure image"
  New-Object System.Management.Automation.Host.ChoiceDescription "&4 ubuntu", "Enter 4 for ubuntu"
  New-Object System.Management.Automation.Host.ChoiceDescription "&5 ubuntuAz", "Enter 5 for ubuntu azure image"
)

$msg = "Choose OS"
$options = [System.Management.Automation.Host.ChoiceDescription[]]$aOS
$prompt = $host.ui.PromptForChoice($msg, "", $options, -1)
$os = $options[$prompt].Label -replace "^&\d+\s", ""
function promptInstallDocker {

  $y = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes/Enter", "Y - install Docker"
  $n = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "N - do not install Docker"
  $msg = "Install Docker?"

  $options = [System.Management.Automation.Host.ChoiceDescription[]]($y, $n)
  $prompt = $host.ui.PromptForChoice($msg, "", $options, 0)

  switch ($prompt) {
    0 { return $true }
    1 { return $false }
  }
}

$bInstallDocker = promptInstallDocker

#ensure template refreshed
$templateVm = & .\scripts\refreshLinuxTemplate.ps1 -os $os -bDocker $bInstallDocker
$defaultHostname = $templateVm.VMName.Replace("-template", "").replace(".", "")
. .\scripts\PromptHostname.ps1 -defaultHostname $defaultHostname
$hostname = promptHostname -defaultHostname $defaultHostname

if (Get-VM -VMName "$hostname" -ErrorAction 'SilentlyContinue') {
  #new vm might be being rebuilt so is already open. Close it, if so
  & .\scripts\closeWindow.ps1 -windowTitleToMatch $($hostname + " * Virtual Machine Connection")
  & .\scripts\removeVM.ps1 $hostname
}

#ensure vm dir exists and is empty
$vmFolder = Join-Path $hostVMFolder $hostname
if (Test-Path $vmFolder) { Remove-Item -LiteralPath "$vmFolder" -Force -Recurse }
New-Item -Path $vmFolder -ItemType Directory  > $null

Write-Output "clone template vm"

& .\scripts\cloneVm.ps1 -sourceVmName $templateVm.Name -cloneVmName $hostname

#ask cloud-init to rename host
$vhdx = (Get-VMHardDiskDrive -VMName $hostname).Path
& .\scripts\wslCloudInitRenameHost.ps1 -vhdx "$vhdx" -hostname $hostname -os $os

Start-VM $hostname
& .\scripts\pollBuildProgress.ps1 -vmName $hostname
Write-Output "$hostname rename done"

& .\scripts\shutdownVM.ps1 -vmName $hostname

Set-VM -CheckpointType Production -Name $hostname
Checkpoint-VM -SnapshotName "sensie build snap before first boot" -Name $hostname

$startVm = Read-Host "Connect to VM $($hostname)? (y/n)"

if ($startVm -eq 'y' -or [string]::IsNullOrEmpty($startVm)) {
  Start-VM -Name $hostname
  Start-Process "vmconnect" "localhost", "$hostname"
}
