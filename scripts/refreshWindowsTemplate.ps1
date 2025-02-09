<#
Instead of installing an OS (albeit possibly a cloud-init image), whenever
a new VM should be built, first create a template.. 
If a new VM is to be created, if the template exists, clone it 
#>

#requires -Modules Hyper-V
## #requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string] $edition,
  [Parameter(mandatory=$true)]
  [string] $winName
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

$hostVMFolder = (Get-VMHost).VirtualMachinePath
if (-not $hostVMFolder) {throw"Couldn't get VirtualMachinePath from Get-VMHost"}

$vmStoragePath = (Get-VMHost).VirtualHardDiskPath
if (-not $vmStoragePath) { throw "Couldn't get VMStoragePath from Get-VMHost, quitting" }

$vmName=$edition + "-template"
$vmFolder=Join-Path $vmStoragePath $vmName
$templateVHDX=Join-Path $vmFolder ($vmName + ".vhdx")

if (!(test-path $vmFolder)) {mkdir -Path $vmFolder | out-null}

#if template VM exists, prompt if it should be recreated
$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if ($vm) {
  $prompt= "Template VM $vmName " + $(if ($vm.Notes){ "exists, $($vm.Notes)" } else { "exists" }) + ". Refresh? (y or n)"
  $refresh = Read-Host "$prompt"
  if ($refresh -eq 'y') {
    & .\scripts\removeVM.ps1 $vmName
  }
  else { return $vm }
} 

Remove-Item -Path "$templateVHDX" -ErrorAction SilentlyContinue
New-VHD -Path "$templateVHDX" -SizeBytes 60GB -Dynamic > $null 2>&1

$build=$(ssh administrator@wds.baltsch.com D:\get_build_from_image_description.ps1 -imageName "$winName")

$vm=& .\scripts\createVM.ps1 -vmName $vmName -vmFolder "$vmFolder" -vhdx "$templateVHDX" -notes ("created:" + (Get-Date -Format "dd/MM/yy") + " $build") -bWindows $true -bStartVM $false

#start VM temporarily to get mac address
Start-VM -Name $vmName
$vmId = $vm.Id

#wait for mac address
$macAddress = "000000000000"
#write-host "wait for mac address"
while ($macAddress -eq "000000000000") {
    Start-Sleep -Seconds 1  # Wait for 1 second before checking again
    $networkAdapter = Get-VMNetworkAdapter -VMName $vmName
    $macAddress = $networkAdapter.MacAddress
}

Stop-VM -Name $vmName -TurnOff

Write-host "got MAC address $macAddress for $vmName ID:$vmId"

$sshResult = $(ssh administrator@wds.baltsch.com D:\prestage_sensie_build.ps1 -hostname "$vmName" -edition $winName -ID "$macAddress")
if ($LASTEXITCODE -ne 0) { throw "Couldn't prestage build via SSH: $sshResult" }

$startDT = Get-Date
Start-VM -Name $vmName #> $null 2>&1
Start-Process "vmconnect" "localhost","$vmName"
& .\scripts\pollVMStartup.ps1 -vmId $vmId -startDT $startDT
& .\scripts\pollBuildProgress.ps1 -vmName $vmName -windows $true

Save-VM -Name $vmName

Get-VMSnapshot -VMName $vmName  | Remove-VMSnapshot -IncludeAllChildSnapshots
return $vm