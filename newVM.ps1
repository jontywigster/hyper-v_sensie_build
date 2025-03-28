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

#prompt for role
function promptSelectRole {
  $roles = @{
    1 = "docker"
    2 = "podman"
    3 = "none"
  }

  $msg = "Add role?"
  $options = @()
  foreach ($key in ($roles.Keys | Sort-Object)) {
    $roleDescription = "&$key - $($roles[$key])"
    $options += New-Object System.Management.Automation.Host.ChoiceDescription $roleDescription, "Select $($roles[$key])"
  }

  $prompt = $host.ui.PromptForChoice($msg, "", $options, 0)
  return $roles[$prompt + 1]
}

if (!$windows) {
  $role = promptSelectRole
}

#ensure image downloaded, and converted to vhdx
$sourceVHDX = & .\scripts\downloadImage.ps1 -os $os -windows $windows

$defaultHostname = If ($windows) { $options[$prompt].Label } Else { $(Split-Path -Path $sourceVHDX -Leaf).Replace("-source.vhdx", "").Replace(".", "") }
$hostname = & .\scripts\PromptHostname.ps1 -defaultHostname $defaultHostname

if ($windows) {
  $adminPwd = Read-Host "Enter Windows admin pwd"
}

#prompt for vswitch
$vSwitches = Get-VMSwitch | Select-Object -ExpandProperty Name
if ($vSwitches -isnot [System.Array]) { $vSwitches = @($vSwitches) }
$vSwitch = $null

for ($i = 0; $i -lt $vSwitches.Count; $i++) { Write-Host "$($i + 1): $($vSwitches[$i])" }

do {
  $selection = Read-Host "Enter vswitch number / Enter for $($vSwitches[0])"
  
  if (-not [string]::IsNullOrWhiteSpace($selection)) {
    if ($selection -as [int]) {
      $index = [int]$selection - 1
      if ($index -ge 0 -and $index -lt $vSwitches.Count) {
        $vSwitch = $vSwitches[$index]
      }
    }
  }
  else {
    #default to first entry if enter pressed
    $vSwitch = $vSwitches[0]
  }
  
  if ($null -eq $vSwitch) { Write-Host "Invalid selection, enter again" }
} while ($null -eq $vSwitch)


# Prompt the user to set a trunk port by specifying a native VLAN, or choose no trunk
$nativeVlan = Read-Host "Enter trunk port native vlan id / Enter or n for no trunk"

if (-not [string]::IsNullOrWhiteSpace($nativeVlan) -and $nativeVlan -ne "n") {
  # Trunk native VLAN ID provided, prompt for AllowedVlanIdList
  $allowedVlanIdList = Read-Host "Enter AllowedVlanIdList (e.g., 1-100), or Enter for all 1-4094)"

  # If AllowedVlanIdList is empty, set a default range
  $allowedVlanIdList = if ([string]::IsNullOrWhiteSpace($allowedVlanIdList)) { "1-4094" } else { $allowedVlanIdList }
}
else {
  #no trunk, prompt for vlan
  $vlan = Read-Host "Enter access port vlan id / Enter for none"
  $vlan = if ([string]::IsNullOrWhiteSpace($vlan)) { "" } else { $vlan }
}


#create vm
$vmFolder = Join-Path $hostVMFolder $hostname
& .\scripts\createVM.ps1 -vmName $hostname -vmFolder "$vmFolder"  -vhdx "$sourceVHDX" -vSwitch $vSwitch -vlan $vlan -nativeVlan $nativeVlan -allowedVlanIdList $allowedVlanIdList -notes "created $(Get-Date -Format "dd/MM/yyyy")" -bStartVM $false -bWindows $windows
$vhdx = $(Get-VMHardDiskDrive -VMName $hostname).Path

if ($windows) {
  & .\scripts\injectWinUnattend.ps1 -vhdx $vhdx -os $os -hostname $hostname -adminPwd $adminPwd
}
else {
  & ".\scripts\wslSeedCloudInit.ps1" -hostname $hostname -os $os -role $role
}

Start-VM -Name $hostname

if ($windows) {
  $buildResult = & .\scripts\pollBuildProgressKVP.ps1 -vmName $hostname -windows $true
} else {
  $buildResult = & .\scripts\watchConsole.ps1 -vmName $hostname
}

#h-v LIS not available on some distros until reboot
if ($os -in @("alma")) {
  & .\scripts\rebootGuestAndWaitForBoot.ps1 -vmName $hostname
}

#ipv6 local net not up right now, will use ipv6 address instead when available
$guestIpAddress = $null
do {
  $allAdaptersIpAddresses = (Get-VMNetworkAdapter -VMName $hostname).IPAddresses
  if ($allAdaptersIpAddresses) {
      $guestIpAddress = $allAdaptersIpAddresses | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
  }
  Start-Sleep -Seconds 1
} while (-not $guestIpAddress)

& .\scripts\mailBuildResult.ps1 -vmName $hostname -buildResult $buildResult -guestIpAddress $guestIpAddress

Set-VM -CheckpointType Production -Name $hostname
Checkpoint-VM -SnapshotName "sensie build snap" -Name $hostname

$connectVM = Read-Host "Connect to VM $($hostname)? Enter or y /n"
if ($connectVM -eq 'y' -or [string]::IsNullOrEmpty($connectVM)) {
  if ($windows) { 
    Start-Process "vmconnect" "localhost", "$hostname" 
  } 
  else { 
    wt --title "$hostname" ssh.exe -i "$HOME\.ssh\wigster" wigster@$guestIpAddress
  }
}
else {
  Stop-VM -name $hostname
}