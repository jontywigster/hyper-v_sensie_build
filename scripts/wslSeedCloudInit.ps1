<#
remove existing cloud init stuff
add ds nocloud, pointing to own http server
#>

[CmdletBinding()]
param(
  [Parameter(mandatory = $true)]
  [string] $hostname,
  [Parameter(mandatory = $true)]
  [string] $os,
  [Parameter(mandatory = $true)]
  [string] $role
)

$ErrorActionPreference = 'Stop'

$parentDirectory = Split-Path -Path $PSScriptRoot -Parent
$ciCfgPath = (Join-Path $parentDirectory "cloud_init_cfg")
$ciCfgPath = wsl bash -c "wslpath -a -u '$ciCfgPath'"

$mntID = [System.Guid]::NewGuid().ToString()
Write-Host "Mounting $vhdx to /mnt/wsl/$mntID"
$mntCmd = wsl --mount --vhd "$vhdx" -p ($os -like "alma*" ? 4:1) --name "$mntID"
if ($LASTEXITCODE -ne 0) {
  throw "$mntCmd"
}
$mntCmd

$mntPath = "/mnt/wsl/$mntID"

Write-Host "seed cloud-init"

#clean any exiting cloud-init files
wsl -u root -- rm -fv $mntPath/etc/cloud/cloud.cfg.d/*.cfg

#add config files

wsl -u root -- cp -r "$ciCfgPath/." $mntPath/etc/cloud/cloud.cfg.d/

#create seed dir
$vmSeedPath = "$mntPath/var/lib/cloud/seed/nocloud"
wsl -u root -- bash -c "if [ ! -d '$vmSeedPath' ]; then mkdir -p '$vmSeedPath'; fi"
#ensure seed dir is empty
wsl -u root -- rm -rfv $mntPath/var/lib/cloud/seed/nocloud/*

$localSeedPath = (Join-Path $parentDirectory "cloud_init_seed")
$localSeedPath = wsl bash -c "wslpath -a -u '$localSeedPath'"

wsl -u root -- cp -r "$localSeedPath/." "$vmSeedPath"

$sedCommand = 's/{hostname}/' + $hostname + '/g'
wsl -u root -- sed -i -e $sedCommand $vmSeedPath/*

$packagesPerOS = . .\scripts\packagesPerOS.ps1
$osPackages = $packagesPerOS[$os]

if ($osPackages.Count -gt 0) {
  $osPackagesString = [string]::Join("`n  - ", $osPackages)
  $osPackagesString = "  - " + $osPackagesString + "`n"
  $osPackagesString = $osPackagesString -replace '/', '\/' -replace '&', '\\&' -replace '\n', '\\n' -replace '\r', '\\r'
  $sedCommand = 's/{packagesPerOS}/' + $osPackagesString + '/g'
} else {
  $sedCommand = 's/{packagesPerOS}//g'
}

wsl -u root -- sed -i -e $sedCommand --posix $vmSeedPath/user-data

wsl -u root -- sed -i -e "s/{role}/$role/g" $vmSeedPath/user-data
wsl -u root -- sed -i -e "s/{hostname}/$hostname/g" $vmSeedPath/user-data
wsl -u root -- sed -i -e "s/{os}/$os/g" $vmSeedPath/user-data

#Write-Host "Entering image chrooted to /mnt/wsl/$mntID. ctrl+d to exit" -f Green
wsl -u root chroot /mnt/wsl/$mntID

write-host "will unmount - "
write-host "wsl --unmount \\?\$vhdx"
wsl --unmount \\?\$vhdx
