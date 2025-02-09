<#
remove existing cloud init stuff
add ds nocloud, pointing to own http server
#>

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string] $vhdx,
  [Parameter(mandatory=$true)]
  [string] $hostname,
  [Parameter(mandatory=$true)]
  [string] $os
)

$ErrorActionPreference = 'Stop'

$mntID=[System.Guid]::NewGuid().ToString()
$mntCmd = wsl --mount --vhd "$vhdx" -p ($os -like "alma*" ? 4:1) --name "$mntID"
if ($LASTEXITCODE -ne 0) {
    throw "$mntCmd"
}

$mntPath="/mnt/wsl/$mntID"

Write-Verbose "seed cloud-init"

#delete existing files
wsl -u root -- bash -c "printf 'sensie_build%0500drena%02044d'  | tr '0' '\0' > $mntPath/var/lib/hyperv/.kvp_pool_1"
wsl -u root -- bash -c "find $mntPath/etc/cloud/cloud.cfg.d/ -type f -name '*.cfg' ! -name '*logging*' -exec rm -f {} \;"
wsl -u root -- rm -rfv $mntPath/var/log/cloud-init*
wsl -u root -- rm -rfv $mntPath/var/lib/cloud/seed/nocloud

$parentDirectory = Split-Path -Path $PSScriptRoot -Parent
$localSeedPath=(Join-Path $parentDirectory "cloud_init_rename")
$localSeedPath=wsl -u root -- wslpath -a "$localSeedPath"

$cloudInitSeedPath=$mntPath+'/var/lib/cloud/seed/nocloud/'
wsl -u root -- mkdir -p "$cloudInitSeedPath"
wsl -u root -- cp -r "$localSeedPath/." "$cloudInitSeedPath"

$sedCommand='s/{hostname}/'+$hostname+'/g'
wsl -u root -- sed -i -e $sedCommand $cloudInitSeedPath/*

$sedCommand='s/{os}/'+$os+'/g'
wsl -u root -- sed -i -e $sedCommand $cloudInitSeedPath/*

write-host "will unmount - "
write-host "wsl --unmount \\?\$vhdx"
wsl --unmount \\?\$vhdx




