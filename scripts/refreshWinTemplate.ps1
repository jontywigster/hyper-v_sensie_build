<#
To speed up Windows builds, first create a template VM, to be cloned later
#>

#requires -Modules Hyper-V
## #requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)]
    [string] $sourceVHDX, 
    [Parameter(mandatory = $true)]
    [string] $edition,
    [Parameter(mandatory = $true)]
    [string] $vSwitch
    )

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

$hostVMFolder = (Get-VMHost).VirtualMachinePath
if (-not $hostVMFolder) { throw"Couldn't get VirtualMachinePath from Get-VMHost" }

$vmStoragePath = (Get-VMHost).VirtualHardDiskPath
if (-not $vmStoragePath) { throw "Couldn't get VMStoragePath from Get-VMHost, quitting" }

$vmName = ($edition + "-template").Trim()
$vmFolder = Join-Path $vmStoragePath $vmName

if (!(test-path $vmFolder)) { mkdir -Path $vmFolder | out-null }

#if template VM exists, prompt if it should be recreated
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if ($vm) {
    $prompt = "Template VM $vmName " + $(if ($vm.Notes) { "exists, $($vm.Notes)" } else { "exists" }) + ". Refresh? y / Enter or n"
    $refresh = Read-Host "$prompt"
    if ($refresh -eq 'y') {
        & .\scripts\removeVM.ps1 -vmName $vmName
    }
    else { return $vm }
} 

$vm = & .\scripts\createVM.ps1 -vmName $vmName -vmFolder "$vmFolder" -vhdx "$sourceVHDX" -vSwitch "$vSwitch" -notes ("created:" + (Get-Date -Format "dd/MM/yy")) -bWindows $true -bStartVM $false
. .\scripts\getEnvVars.ps1

$templateVHDX= Join-Path $vmFolder $(Split-Path $sourceVHDX -Leaf)
& .\scripts\injectWinUnattend.ps1 -vhdx "$templateVHDX" -os $edition -hostname $vmName -adminPwd "$WIN_TEMPLATE_ADMIN_PWD"

Start-VM -Name $vmName | out-null
Start-Process "vmconnect" "localhost", $vmName
& .\scripts\pollVMStartup.ps1 -vmName $vmName
& .\scripts\pollBuildProgressKVP.ps1 -vmName $vmName -windows $true

#close template vm window
& .\scripts\closeWindow.ps1 -windowTitleToMatch $($vm.Name  + " * Virtual Machine Connection")

Save-VM -Name $vmName

return $vm