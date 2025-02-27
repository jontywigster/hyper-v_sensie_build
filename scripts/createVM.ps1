<#
based on
https://github.com/schtritoff/hyperv-vm-provisioning
#>

#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
  [int] $vmGeneration = 2,
  [int] $vmProcessorCount = 4,
  [bool] $vmDynamicMemoryEnabled = $true,
  [uint64] $vmMemoryStartupBytes = 2048MB,
  [uint64] $vmMinimumBytes = 1024MB,
  [uint64] $vmMaximumBytes = 8192MB,
  [uint64] $VHDSizeBytes = 40GB,
  [string] $VirtualSwitchName = "ext wifi",
  [switch] $DisableVMMacAddressSpoofing,
  [string] $NetInterface = "eth0",
  #new vm params
  [Parameter(mandatory=$true)]
  [string] $vmName,
  [Parameter(mandatory=$true)]
  [string] $vmFolder,
  [Parameter(mandatory=$true)]
  [string] $vhdx,
  [switch] $bCheckpoints,
  [bool] $bSecureBoot,
  [string] $notes,
  [bool] $bWindows,
  [bool] $bStartVM
)

$ErrorActionPreference = 'Stop'

if(!($PSBoundParameters.ContainsKey('bSecureBoot'))) {$bSecureBoot = $true}
if(!($PSBoundParameters.ContainsKey('bWindows'))) {$bWindows = $false}
if(!($PSBoundParameters.ContainsKey('bStartVM'))) {$bStartVM = $true}

#delete the VM if it exists
& .\scripts\closeWindow.ps1 -windowTitleToMatch $($vmName + " * Virtual Machine Connection")
& .\scripts\removeVM.ps1 $vmName

#ensure vm dir exists and is empty
if (Test-Path $vmFolder) { Remove-Item -LiteralPath "$vmFolder" -Force -Recurse }
New-Item -Path $vmFolder -ItemType Directory  > $null

Write-host "copying source vhdx to vm folder"
$vhdx=& .\scripts\copyFileWithProgress.ps1 -sourcePath "$vhdx" -destinationPath "$vmFolder"


Write-Host "creating VM $vmName"
$vm = new-vm -Name $vmName -MemoryStartupBytes $vmMemoryStartupBytes `
  -Path "$vmFolder" -VHDPath "$vhdx" -Generation $vmGeneration `
  -BootDevice VHD
if($PSBoundParameters.ContainsKey('notes')) {$vm | set-vm -Notes $notes}
$vm | Set-VMProcessor -Count $vmProcessorCount

Write-Verbose "Enable dynamic memory"
if ($vmDynamicMemoryEnabled) {
  $vm | Set-VMMemory -DynamicMemoryEnabled $vmDynamicMemoryEnabled -MaximumBytes $vmMaximumBytes -MinimumBytes $vmMinimumBytes
} else {
  $vm | Set-VMMemory -DynamicMemoryEnabled $vmDynamicMemoryEnabled
}

Write-Verbose "Add nic"
if ([string]::IsNullOrEmpty($virtualSwitchName)) {
  throw "vswitch not specified, please use parameter -virtualSwitchName 'Switch Name'."
} else {
  #Get-VMNetworkAdapter -VMName $vmName | Connect-VMNetworkAdapter -SwitchName "$virtualSwitchName"
  $vm | Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName "$virtualSwitchName"
}

#will default to enabling spoofing as I might use macvlans
if (!$DisableVMMacAddressSpoofing) {  
  Write-Verbose "Enable mac spoofing"
  $vm | Set-VMNetworkAdapter -MacAddressSpoofing On
}

#guest will default to 'Microsoft Windows' template so don't set for windows
if ($vmGeneration -eq 2 -and $bSecureBoot -and !$bWindows) {
  Write-Host "Set secureboot to MicrosoftUEFICertificateAuthority"
  $vm | Set-VMFirmware -EnableSecureBoot On -SecureBootTemplateId ([guid]'272e7447-90a4-4563-a4b9-8e4ab00526ce')
}

# enable enhanced session mode if gen 2
if (($vmGeneration -eq 2) -and ($(Get-VMHost).EnableEnhancedSessionMode)) {
  Write-Verbose "Enable enhanced session mode"
  $vm |  Set-VM -EnhancedSessionTransportType HvSocket
}

# Enable copy/paste over vmbus
$vm | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService

# redirect com port for VM serial output
Write-Verbose "Add com port - "
Write-Verbose "\\.\pipe\$vmName-com1"
$vm | Set-VMComPort -Path \\.\pipe\$vmName-com1 -Number 1

if ($bCheckpoints) {
  #set prod checkpoints, will fall back to standard if not supported in guest 
  $vm | Set-VM -CheckpointType Production

  #Write-Host "Creating checkpoint before first boot"
  $vm | Checkpoint-VM -SnapshotName "sensie build snap before first boot"
} else {
  $vm | Set-VM -AutomaticCheckpointsEnabled $false
}

if ($bStartVM) {
  Write-Host "Starting VM"
  Start-VM $vmName
}

return $vm
 