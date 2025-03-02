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

$ErrorActionPreference = 'Stop'
$VerbosePreference = "SilentlyContinue"

# Get default Virtual Machine path (requires admin rights)
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
  New-Object System.Management.Automation.Host.ChoiceDescription "25sc", "Enter 25sc for Windows 2025_Standard_Core"
  New-Object System.Management.Automation.Host.ChoiceDescription "25dc", "Enter 25dc for Windows 2025_DC_Core"
  New-Object System.Management.Automation.Host.ChoiceDescription "25s", "Enter 25s for Windows 2025_Standard"
  New-Object System.Management.Automation.Host.ChoiceDescription "25d", "Enter 25d for Windows 2025_DC"
)


do {
  $msg = "Choose OS"
  $options = [System.Management.Automation.Host.ChoiceDescription[]]$aOS
  $prompt = $host.ui.PromptForChoice($msg, "", $options, -1)
  $os = $options[$prompt].Label -replace "^&\d+\s", ""
  $windows = $options[$prompt].HelpMessage -match "Windows"

  $confirmation = Read-Host "$os selected. Continue? (y or empty /n) n will prompt again"
} while ($confirmation -ne "y" -and $confirmation -ne "")

Write-Host "os is $os"

function promptInstallDocker {
  $msg = "Install Docker?"
  $y = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes/Enter", "Y - install Docker"
  $n = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "N - do not install Docker"
  
  $options = [System.Management.Automation.Host.ChoiceDescription[]]($y, $n)
  $prompt = $host.ui.PromptForChoice($msg, "", $options, 0)

  switch ($prompt) {
    0 { return "docker" }
    1 { return "nodocker" }
  }
}
if (!$windows) {
  $bInstallDocker = promptInstallDocker
}

#ensure image downloaded, and converted to vhdx
$sourceVHDX = & .\scripts\downloadImage.ps1 -os $os -windows $windows

$defaultHostname = If ($windows) { $options[$prompt].Label } Else { $(Split-Path -Path $sourceVHDX -Leaf).Replace("-source.vhdx", "").Replace(".", "") }
$hostname = & .\scripts\PromptHostname.ps1 -defaultHostname $defaultHostname

if ($windows) {
  $adminPwd = Read-Host "Enter Windows admin pwd"
}

$vmFolder = Join-Path $hostVMFolder $hostname
& .\scripts\createVM.ps1 -vmName $hostname -vmFolder "$vmFolder"  -vhdx "$sourceVHDX" -notes "created $(Get-Date -Format "dd/MM/yyyy")" -bStartVM $false -bWindows $windows
$vhdx = $(Get-VMHardDiskDrive -VMName $hostname).Path

if ($windows) {
  & .\scripts\injectWinUnattend.ps1 -vhdx $vhdx -os $os -hostname $hostname -adminPwd $adminPwd
}
else {
  $mntID = [System.Guid]::NewGuid().ToString()
  Write-Host "Mounting $vhdx to /mnt/wsl/$mntID"
  $mntCmd = wsl --mount --vhd "$vhdx" -p ($os -like "alma*" ? 4:1) --name "$mntID"
  if ($LASTEXITCODE -ne 0) {
    throw "$mntCmd"
  }
  $mntCmd
  
  &".\scripts\wslSeedCloudInit.ps1" -mntID $mntID -hostname $hostname -os $os -buildType $bInstallDocker
  
  #Write-Host "Entering image chrooted to /mnt/wsl/$mntID. ctrl+d to exit" -f Green
  #wsl -u root chroot /mnt/wsl/$mntID
  write-host "will unmount - "
  write-host "wsl --unmount \\?\$vhdx"
  wsl --unmount \\?\$vhdx
}


Start-VM -Name $hostname
if (!$windows) {
  #call hvc explicitly so window is closed automatically
  wt --title "sensie-build_$hostname" hvc.exe serial $hostname
}

& .\scripts\pollBuildProgress.ps1 -vmName $hostname -windows $windows
& .\scripts\shutdownVM.ps1 -vmName $hostname
Set-VM -CheckpointType Production -Name $hostname
Checkpoint-VM -SnapshotName "sensie build snap before first boot" -Name $hostname

$startVm = Read-Host "Connect to VM $($hostname)? (y/n)"
if ($startVm -eq 'y' -or [string]::IsNullOrEmpty($startVm)) {
  Start-VM -Name $hostname
  wt --title "sensie-build_$hostname" hvc.exe serial $hostname
  #Start-Process "vmconnect" "localhost", "$hostname"
}
