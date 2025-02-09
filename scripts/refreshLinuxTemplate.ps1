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
  [string] $os,
  [Parameter(mandatory=$true)]
  [bool] $bDocker
)

if(!($PSBoundParameters.ContainsKey('windows'))) {
  $windows = $false
}

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'

$hostVMFolder = (Get-VMHost).VirtualMachinePath
if (-not $hostVMFolder) {
  throw"Couldn't get VirtualMachinePath from Get-VMHost"
}

#refresh disk image for os if needed
Write-Host "Check downloaded OS image exists and is not stale "
$imageTemplateString=& .\scripts\refreshDiskImage.ps1 -aOS "$os" -windows $windows
$aImageTemplateString = $imageTemplateString -split ","
$vmName=$aImageTemplateString[0].replace(".","")
$vmFolder=$aImageTemplateString[1]
$templateVHDX=$aImageTemplateString[2]

if ($bDocker) {$vmName+="-docker"}
$outputVHDX=Join-Path $vmFolder ($vmName+ ".vhdx")

#if the os image was downloaded, delete the template
if ($aImageTemplateString[4] -eq "false") {
  Remove-Item -Path "$outputVHDX" -ErrorAction SilentlyContinue
} else {
  #source image was not downloaded but might want to rebuild anyway. Prompt
  if (Test-Path $outputVHDX) { 
    $refresh = Read-Host "The source image is not stale and template vhdx exists. Recreate template? (y/n)"
    if ($refresh -eq 'y') {
      & .\scripts\removeVM.ps1 $vmName
      Remove-Item -Path "$outputVHDX" -ErrorAction SilentlyContinue
    }  
  }
} 

if (-not (Test-Path $outputVHDX)) { 
  Write-host "copying template vhdx to out file"
  & .\scripts\copyFileWithProgress.ps1 -sourcePath "$templateVHDX" -destinationPath "$outputVHDX"
} else {
  #not refreshing template, ensure vm clean then return
  $vm=Get-VM -VMName $vmName -ErrorAction SilentlyContinue
  if ($vm -and ((Get-VM -Name $vmName).State -eq 'Running')) { Stop-VM -Name $vmName > $null }
  if ($vm) { Get-VMSnapshot -VMName $vmName  | Remove-VMSnapshot -IncludeAllChildSnapshots }
  if ($vm) { return $vm }
}

$mntID=[System.Guid]::NewGuid().ToString()
Write-Host "Mounting $outputVHDX to /mnt/wsl/$mntID"
$mntCmd = wsl --mount --vhd "$outputVHDX" -p ($os -like "alma*" ? 4:1) --name "$mntID"
if ($LASTEXITCODE -ne 0) {
    throw "$mntCmd"
}
$mntCmd

#cloud-init will call ansible, set extra param
$ansiblePlay= $bDocker ? "docker":"base"

#bodge removing existing cloud datasources etc.
if ($os -like "ubuntu*") {&".\scripts\wslSetCloudInit.ps1" -mntID $mntID -hostname $vmName -os $os -ansiblePlay $ansiblePlay}
if (($os -like "alma*") -or ($os -like "debian*")) {&".\scripts\wslSeedCloudInit.ps1" -mntID $mntID -hostname $vmName -os $os -ansiblePlay $ansiblePlay}

#Write-Host "Entering image chrooted to /mnt/wsl/$mntID. ctrl+d to exit" -f Green
#wsl -u root chroot /mnt/wsl/$mntID
write-host "will unmount - "
write-host "wsl --unmount \\?\$outputVHDX"
wsl --unmount \\?\$outputVHDX


#Create new virtual machine
$vm=& .\scripts\createVM.ps1 -vmName $vmName -vmFolder "$vmFolder"  -vhdx "$outputVHDX" -notes $vmNotes

#call hvc explicitly so window is closed automatically
wt --title "sensie-build_$vmName" hvc.exe serial $vmName
 
& .\scripts\pollBuildProgress.ps1 -vmName $vmName -windows $windows

stop-vm $vmName
Get-VMSnapshot -VMName $vmName  | Remove-VMSnapshot -IncludeAllChildSnapshots

return $vm