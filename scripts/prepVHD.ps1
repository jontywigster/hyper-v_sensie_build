<#
Convert vhd to vhdx, resize
#>

#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
[Parameter(mandatory=$true)]  
  [string] $sourceVHD
)

$ErrorActionPreference = 'Stop'

#if vhd(x) is sparse can't do any conversions. Copy to inflate it
if ( ((Get-ItemProperty -Path "$sourceVHD").Attributes -band [System.IO.FileAttributes]::SparseFile) -eq [System.IO.FileAttributes]::SparseFile ) {
  $inflatedImage=("$sourceVHD" + ".inflated") 
  Write-Host 'inflate sparse vhd'
  Copy-Item "$sourceVHD" -Destination "$inflatedImage"
  Remove-Item -Path "$sourceVHD"
  Rename-Item -Path "$inflatedImage" -NewName "$sourceVHD"
}

#if .vhd, convert to vhdx
if ([System.IO.Path]::GetExtension("$sourceVHD") -ieq ".vhd") {
  Write-Host 'convert vhd to vhdx'
  $vhdx=("$sourceVHD" + "x")
  if (Test-Path "$vhdx" -ErrorAction SilentlyContinue) { 
    Remove-Item "$vhdx" -Force
  }
  Convert-VHD -Path "$sourceVHD" -DestinationPath $vhdx -VHDType Dynamic -BlockSizeBytes 1MB
  $sourceVHD=$vhdx
  Remove-Variable vhdx
}

#adjust block size and disk type, if needed
$vhdProps=Get-VHD -Path "$sourceVHD"
if ( ($vhdProps.BlockSize -ne 1048576) -or ($vhdProps.VhdType -ne "Dynamic")) {
  Write-Host 'ensure vhdx dynamic, set block size'
  $adjustedVhdx=("$sourceVHD" + ".adjust.vhdx")
  Convert-VHD -Path "$sourceVHD" -DestinationPath $adjustedVhdx -VHDType Dynamic -BlockSizeBytes 1MB
  Remove-Item -Path "$sourceVHD"
  Rename-Item -Path "$adjustedVhdx" -NewName "$sourceVHD"
  Remove-Variable adjustedVhdx
}

#resize to 50 gigs if smaller
$vhdxMaxSize=(Get-VHD -Path "$sourceVHD").size/1GB
if ($vhdxMaxSize -lt 50) {
  Write-Host 'resize vhdx to 50 gigs'
  Resize-VHD -Path $sourceVHD -SizeBytes 50GB
}

#optimize
Write-Host "optimise vhdx"
Mount-VHD -Path $sourceVHD -ReadOnly -ErrorAction Stop
Optimize-VHD -Path $sourceVHD -Mode Full -ErrorAction Continue
Dismount-VHD -Path $sourceVHD

return $sourceVHD

