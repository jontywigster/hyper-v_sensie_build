#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string] $sourceVmName,
  [Parameter(mandatory=$true)]
  [string] $cloneVmName
)

$ErrorActionPreference = 'Stop'

#will (try to) overwrite clone target
if (Get-VM -Name $cloneVmName -ErrorAction SilentlyContinue) {
  & .\scripts\removeVM.ps1 $cloneVmName
}

$cloneFolder= Join-Path ((Get-VMHost).VirtualMachinePath) $cloneVmName
if (Test-Path -Path $cloneFolder -PathType Container) {
    Remove-Item -Path $cloneFolder -Recurse -Force
} 


Write-Host "export source vm"
Export-VM $sourceVmName -Path $cloneFolder
$cloneVMCX = (Get-ChildItem "$cloneFolder\$sourceVmName" -Filter *.vmcx -Recurse | Select-Object -First 1).Fullname

$cloneConfig = @{
  Path = $cloneVMCX;
  SnapshotFilePath = Join-Path $cloneFolder "Snapshots";
  VhdDestinationPath = Join-Path $cloneFolder "Virtual Hard Disks";
  VirtualMachinePath = $cloneFolder;
}

& .\scripts\removeVM.ps1 $cloneVmName


Write-Host "import"
$cloneVm = Import-VM -Copy -GenerateNewID @cloneConfig 
$cloneVm | Rename-VM -NewName $cloneVmName

# remove export
$exportPath = "$cloneFolder\$SourceVMName"
if (Test-Path $exportPath) {
    Remove-Item -Path $exportPath -Recurse -Force
}

return $cloneVm
 