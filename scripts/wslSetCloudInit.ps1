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

# default error action
$ErrorActionPreference = 'Stop'

$mntPath="/mnt/wsl/$mntID"

#delete existing files
wsl -u root -- rm -fv $mntPath/etc/cloud/cloud.cfg.d/*.cfg

#add config files
$parentDirectory = Split-Path -Path $PSScriptRoot -Parent
$logCfgDPath=(Join-Path $parentDirectory "cloud_init_cfg")

#convert windows path to linux
$logCfgDPath=wsl -u root -- wslpath -a "$logCfgDPath"
wsl -u root -- cp -r "$logCfgDPath/." $mntPath/etc/cloud/cloud.cfg.d/

Write-Verbose "adjust c-i datasource"

$sedCommand='s/{hostname}/'+$hostname+'/g'
wsl -u root -- sed -i -e $sedCommand $mntPath/etc/cloud/cloud.cfg.d/10_sensie_ds.cfg

$sedCommand='s/{os}/'+$os+'/g'
wsl -u root -- sed -i -e $sedCommand $mntPath/etc/cloud/cloud.cfg.d/10_sensie_ds.cfg


$sedCommand='s/{ansiblePlay}/'+$ansiblePlay+'/g'
wsl -u root -- sed -i -e $sedCommand $mntPath/etc/cloud/cloud.cfg.d/10_sensie_ds.cfg






