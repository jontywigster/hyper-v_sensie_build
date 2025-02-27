<#
remove existing cloud init stuff
add ds nocloud, pointing to own http server
#>

[CmdletBinding()]
param(
  [Parameter(mandatory = $true)]
  [string] $mntID,
  [Parameter(mandatory = $true)]
  [string] $hostname,
  [Parameter(mandatory = $true)]
  [string] $os,
  [Parameter(mandatory = $true)]
  [string] $buildType
)

$ErrorActionPreference = 'Stop'

$mntPath = "/mnt/wsl/$mntID"

Write-Host "seed cloud-init"

#clean any exiting cloud-init files
wsl -u root -- rm -fv $mntPath/etc/cloud/cloud.cfg.d/*.cfg

#add config files
$parentDirectory = Split-Path -Path $PSScriptRoot -Parent
$ciCfgPath = (Join-Path $parentDirectory "cloud_init_cfg")
$ciCfgPath = wsl -u root -- wslpath -a "$ciCfgPath"
wsl -u root -- cp -r "$ciCfgPath/." $mntPath/etc/cloud/cloud.cfg.d/

#create seed dir
$vmSeedPath = "$mntPath/var/lib/cloud/seed/nocloud"
wsl -u root -- bash -c "if [ ! -d '$vmSeedPath' ]; then mkdir -p '$vmSeedPath'; fi"
#ensure seed dir is empty
wsl -u root -- rm -rfv $mntPath/var/lib/cloud/seed/nocloud/*

$localSeedPath = (Join-Path $parentDirectory "cloud_init_seed")
$localSeedPath = wsl -u root -- wslpath -a "$localSeedPath"

wsl -u root -- cp -r "$localSeedPath/." "$vmSeedPath"

$sedCommand = 's/{hostname}/' + $hostname + '/g'
wsl -u root -- sed -i -e $sedCommand $vmSeedPath/*

$packagesPerOS = . .\scripts\packages_per_os.ps1
$osPackages = $packagesPerOS[$os]
$osPackagesString = [string]::Join("`n  - ", $osPackages)
$osPackagesString = "  - " + $osPackagesString + "`n"
$osPackagesString = $osPackagesString -replace '/', '\/' -replace '&', '\\&' -replace '\n', '\\n' -replace '\r', '\\r'
$sedCommand = 's/{packagesPerOS}/' + $osPackagesString + '/g'
wsl -u root -- sed -i -e $sedCommand --posix $vmSeedPath/user-data

wsl -u root -- sed -i -e "s/{buildType}/$buildType/g" $vmSeedPath/user-data
wsl -u root -- sed -i -e "s/{hostname}/$hostname/g" $vmSeedPath/user-data

