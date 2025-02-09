<#
Download images if local copy stale. 
Convert to vhdx if not done already
#>

#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string[]] $aOS,
  [switch[]] $windows
)

$VerbosePreference='SilentlyContinue'
$parentDirectory = Split-Path -Path $PSScriptRoot -Parent
$qemuImgPath = Join-Path $parentDirectory "qemu-img\qemu-img.exe"

#dashes as will use for hostname
$VMNameSuffix = "-template"

$ErrorActionPreference = 'Stop'

# Get default Virtual Hard Disk path (requires administrative privileges)
$VMStoragePath = (Get-VMHost).VirtualHardDiskPath
if (-not $VMStoragePath) {throw "Couldn't get VMStoragePath from Get-VMHost, quitting"}
Write-Verbose "VirtualHardDiskPath: $VMStoragePath"

#prep retval
$returnString=""

#get image details fron NR
Write-Verbose "`n`nquery nr for latest version of $os"
$VerbosePreference='SilentlyContinue'
$relProps = Invoke-RestMethod -Uri "https://nr.oc.baltsch.com/getLinuxRelease?d=$aOS"
$VerbosePreference='Continue'
if ([string]::IsNullOrEmpty($relProps.url)) {  throw "nr didn't return url for os $os"  }

$templateName = [string] $aOS + "-" + $relProps.relToNum + $VMNameSuffix

$templateFolder = Join-Path $VMStoragePath $templateName.Trim()
$templateVHDXFileName=$templateName+"-source.vhdx"
$templateVHDX= Join-Path $templateFolder $templateVHDXFileName
$returnString+="$templateName,$templateFolder,$templateVHDX,$templateVHDXFileName"

# download image if not already downloaded and up to date
#use etag val to determine whether download is current
#as at 13/10/24, debian download doesn't supply etag header, nr sets latest update header as etag
$etagFile=Join-Path $templateFolder "etag"
$etag= $($relProps.etag -replace '"', "")
#default explicitly to no download
$download=$false
$image=Join-Path $templateFolder $relProps.file

if (!(test-path $templateFolder)) {
  #template folder doesn't exist, obviously download
  $download=$true
  mkdir -Path $templateFolder | out-null
} else {
  #template folder exists, check if image exists
  if (test-path $image) {
    #image already downloaded, check if stale
    Write-host "$image already downloaded, checking if stale"
    # NR etag header exists, check if local etag file exists and content matches
    if (!(test-path $etagFile)) {
      #etag local file doesn't exist, assume file should be downloaded
      $download=$true
    } else {
      #etag file exists, check content matches
      $localEtag=  Get-Content -Path $etagFile
      if ($localEtag -ne $etag) {
        Write-Verbose "local etag doesn't match NR, download image"
        $download=$true
      } else {Write-Verbose "local etag matches, skip download"}
    }
  } else {$download=$true} 
} 

#if no download required and template out file vhdx already exists, quit out
if ((test-path $templateVHDX)  -and ($download -eq $false)) {
  Write-Verbose "no download required, template vhdx already exists. Skip $os"
  return $returnString+=",true"
}

if ($download) {
  Write-Host "download $($relProps.url), $($relProps.contentLengthGigs) gigs"
  $ProgressPreference = "SilentlyContinue" #Disable progress indicator else Invoke-WebRequest slow
  Invoke-WebRequest "$($relProps.url)" -OutFile "$image" -UseBasicParsing
  $ProgressPreference = "Continue" #Restore progress indicator.
  Set-Content -Path $etagFile -Value $($relProps.etag -replace '"', "")
} 

#Extract and/or convert downloaded image
#it's almost as costly to look in archive to check if already extracted, as just to extract
#so just extract/convert

#extract image if archive
if ($image -like "*.tar.xz" -or $image -like "*.tar.gz") {
  Write-Verbose "extract tar, might be slow"
  $tarOutput = cmd /c tar -v -x -f "$image" -C "$templateFolder"'2>&1'  
  #get filename in tar. Can list tar but avoid calling tar twice
  $image=Join-Path $templateFolder $tarOutput.split()[1]
}

#convert to vhd
if ($image -like "*.raw" -or $image -like "*.img" -or $image -like "*.qcow2") {
  Write-host "Image is not vhd, convert"
  $image = &".\scripts\convertToVHD.ps1"  -ImageCachePath "$templateFolder" -extractedImage $image -qemuImgPath "$qemuImgPath"
} 

#adjust vhd. Will convert to vhdx if not already
$image = &".\scripts\prepVHD.ps1"-sourceVHD "$image"

#if template out file already existed, would have quit out
#if here, will regenerate template out file, remove old template out file
#if it already exists
if (Test-Path $templateVHDX) {
  Remove-Item $templateVHDX
}

#there is no intermediate .vhd(x) for windows
if ($windows) {
  #copy to template out file 
  Copy-Item -Path "$image" -Destination "$templateVHDX"
} else {
  Rename-Item -Path "$image" -NewName "$templateVHDX"
}

Write-Verbose "$os image download done"
return $returnString+=",false"