<#
Download images if local copy stale. 
Convert to vhdx if not done already
#>

#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory = $true)]
  [string[]] $os,
  [switch[]] $windows
)

$VerbosePreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Get default Virtual Hard Disk path (requires administrative privileges)
$VMStoragePath = (Get-VMHost).VirtualHardDiskPath
if (-not $VMStoragePath) { throw "Couldn't get VMStoragePath from Get-VMHost, quitting" }
Write-Verbose "VirtualHardDiskPath: $VMStoragePath"

#get download URL from NR
Write-Host "`n`nquery nr for latest version of $os"
$VerbosePreference = 'SilentlyContinue'
$relProps = Invoke-RestMethod -Uri "https://nr.oc.baltsch.com/getOSRelease?d=$os"
$VerbosePreference = 'Continue'
if ([string]::IsNullOrEmpty($relProps.url)) { throw "nr didn't return url for os $os" }

$outputFolder = Join-Path $VMStoragePath "sensie_build_sources"
if (!(test-path $outputFolder)) { mkdir -Path $outputFolder | out-null }

if ($windows) {
  $downloadFile = [string] $relProps.relToNum + "-source.vhdx"
  $outputVHDX = $downloadFile
}
else {
  #get file extension from url
  if ($relProps.url -like "*.tar.*") { 
    $fileExtension = ($relProps.url -split '\.' | Select-Object -last 2) -join '.' 
  }
  else { 
    $fileExtension = $relProps.url -split '\.' | Select-Object -last 1
  }
  $downloadFile = [string] $os + "-" + $relProps.relToNum + "-source." + $fileExtension  
  $outputVHDX = [string] $os + "-" + $relProps.relToNum + "-source.vhdx"
}

$downloadFile = Join-Path $outputFolder $downloadFile
$outputVHDX = Join-Path $outputFolder $outputVHDX

#download image if not already
#previously checked etag but now can't be bothered. filename includes version and that will do
if (test-path $downloadFile) {
  Write-Host "no download required, $downloadFile already exists"
}
else {
  Write-Host "download $($relProps.url), $($relProps.contentLengthGigs) gigs"
  if ($windows) {
    & .\scripts\wakeNas.ps1
  }
  $ProgressPreference = "SilentlyContinue" #Disable progress indicator else Invoke-WebRequest slow
  Invoke-WebRequest "$($relProps.url)" -OutFile "$downloadFile" -UseBasicParsing
  $ProgressPreference = "Continue" #Restore progress indicator.
}

#if the output vhdx exists, return
if (test-path $outputVHDX) {
  Write-Host "output VHDX $outputVHDX exists, skip processing"
  return $outputVHDX
}

#extract image if tar
#it's almost as costly to look in tar as just to extract, so just extract
if ($downloadFile.ToLower() -like "*.tar.xz" -or $downloadFile -like "*.tar.gz") {
  Write-Verbose "extract tar, might be slow"
  $tarOutput = cmd /c tar -v -x -f "$downloadFile" -C "$outputFolder"'2>&1'  
  #get filename in tar. Can list tar but avoid calling tar twice as it's slow
  $downloadFile = Join-Path $outputFolder $tarOutput.split()[1]
} 

#convert to vhd
if ($downloadFile.ToLower() -notlike "*.vhd") {
  Write-host "Extracted image is not vhd, convert"
  $parentDirectory = Split-Path -Path $PSScriptRoot -Parent
  $qemuImgPath = Join-Path $parentDirectory "qemu-img\qemu-img.exe"
  $downloadFile = &".\scripts\convertToVHD.ps1"  -ImageCachePath "$outputFolder" -extractedImage $downloadFile -qemuImgPath "$qemuImgPath"
}

#adjust vhd. Will convert to vhdx if not already
$preppedVHDX = &".\scripts\prepVHD.ps1"-sourceVHD "$downloadFile"
Rename-Item -Path "$preppedVHDX" -NewName "$outputVHDX"

return $outputVHDX