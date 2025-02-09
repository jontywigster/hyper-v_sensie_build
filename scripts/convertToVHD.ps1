<#
convert .img or .raw to vhd
#>

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string] $ImageCachePath,
[Parameter(mandatory=$true)]  
  [string] $extractedImage,
  [Parameter(mandatory=$true)]  
    [string] $qemuImgPath
)

# default error action
$ErrorActionPreference = 'Stop'

$vhd=Join-Path $ImageCachePath ((Get-ChildItem $extractedImage).basename + ".vhd")

if (!(test-path $vhd)) {
  Write-Host "qemu-img convert $extractedImage to vhd"
  if ($extractedImage -like "*.raw") {$f="raw"} else {$f="qcow2"}
  Write-Verbose "$qemuImgPath convert -f $f $extractedImage -O vpc $vhd"
  & $qemuImgPath convert -f $f "$extractedImage" -O vpc "$vhd"
}

return $vhd

