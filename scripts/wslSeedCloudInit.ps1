<#
remove existing cloud init stuff
add ds nocloud, pointing to own http server
#>

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string] $mntID,
  [Parameter(mandatory=$true)]
  [string] $hostname,
  [Parameter(mandatory=$true)]
  [string] $os,
  [Parameter(mandatory=$true)]
  [string] $ansiblePlay
)

$ErrorActionPreference = 'Stop'

$mntPath="/mnt/wsl/$mntID"

Write-Host "seed cloud-init"

#delete existing files
wsl -u root -- rm -fv $mntPath/etc/cloud/cloud.cfg.d/*.cfg
wsl -u root -- rm -rfv $mntPath/var/lib/cloud/seed/nocloud

$parentDirectory = Split-Path -Path $PSScriptRoot -Parent
$localSeedPath=(Join-Path $parentDirectory "cloud_init_seed")
$localSeedPath=wsl -u root -- wslpath -a "$localSeedPath"

$cloudInitSeedPath=$mntPath+'/var/lib/cloud/seed/nocloud/'

wsl -u root -- mkdir -p "$cloudInitSeedPath"
wsl -u root -- cp -r "$localSeedPath/." "$cloudInitSeedPath"

$sedCommand='s/{hostname}/'+$hostname+'/g'
wsl -u root -- sed -i -e $sedCommand $cloudInitSeedPath/*

$sedCommand='s/{os}/'+$os+'/g'
wsl -u root -- sed -i -e $sedCommand $cloudInitSeedPath/*

$sedCommand='s/{ansiblePlay}/'+$ansiblePlay+'/g'
wsl -u root -- sed -i -e $sedCommand $cloudInitSeedPath/*
