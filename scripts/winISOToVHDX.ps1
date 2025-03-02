[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$sourceISO,
    [Parameter(Mandatory = $true)]
    [string]$outputVHDX,
    [Parameter(Mandatory = $true)]
    [string]$os
)

$ErrorActionPreference = 'Stop'

# Check if the VHDX file already exists
if (Test-Path $outputVHDX) {
    # make sure the VHDX is not mounted
    $mountedVHD = Get-DiskImage -ImagePath $outputVHDX -ErrorAction SilentlyContinue
    if ($mountedVHD) {
        Dismount-VHD -Path $outputVHDX
    }
    # Delete the existing VHDX file
    Remove-Item -Path $outputVHDX -Force
}

# Mount the source ISO
Mount-DiskImage -ImagePath $sourceISO
$mountedISO = Get-DiskImage -ImagePath $sourceISO | Get-Volume
$mountedDriveLetter = $mountedISO.DriveLetter
if (-not $mountedDriveLetter) {
    Dismount-VHD -Path $outputVHDX
    throw "Failed to get the drive letter of the mounted ISO."
}

$mountedDriveLetterPath = $mountedDriveLetter + ":\"

# Create the VHDX
$SizeBytes = "60GB"
New-VHD -Path $outputVHDX -Dynamic -SizeBytes $SizeBytes
Mount-VHD -Path $outputVHDX
$vhd = Get-Disk | Where-Object { $_.Location -eq "$outputVHDX" }

# Initialize, partition, and format the VHDX
Initialize-Disk -Number $vhd.Number -PartitionStyle GPT

# Create the EFI System Partition
$systemPartition = New-Partition -DiskNumber $vhd.Number -Size 100MB -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -AssignDriveLetter
Format-Volume -Partition $systemPartition -FileSystem FAT32 -NewFileSystemLabel "System"

# Create the MSR Partition
New-Partition -DiskNumber $vhd.Number -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}"

# Create the Windows Partition
$windowsPartition = New-Partition -DiskNumber $vhd.Number -UseMaximumSize -GptType "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" -AssignDriveLetter
Format-Volume -Partition $windowsPartition -FileSystem NTFS -NewFileSystemLabel "Windows"

# Create necessary directory structure on EFI System Partition
New-Item -Path "$($systemPartition.DriveLetter):\EFI" -ItemType Directory -Force


$mapping = @{
    "25s"  = "*Standard*Desktop*"
    "25d"  = "*Datacenter*Desktop*"
    "25sc" = "* Standard *"
    "25dc" = "* Datacenter *"
}
  
$installWimPath = $mountedDriveLetterPath + "sources\install.wim"
$imageInfo = Get-WindowsImage -ImagePath $installWimPath
$imageInfo = $imageInfo | Sort-Object ImageName

#lookup image index of $os using mapping
$imageIndex = $null
$pattern = $mapping[$os]
foreach ($image in $imageInfo) {
    if ($image.ImageName -like $pattern) {
        $imageIndex = $image.ImageIndex
        $imageName=$image.ImageName
        break
    }
}

if ($null -eq $imageIndex) {
    Dismount-VHD -Path $outputVHDX
    Dismount-DiskImage -ImagePath $sourceISO
    Remove-Item -Path $outputVHDX -Force
    throw "No matching image found for $os."
}

Write-Host "dism apply, will be slow - $imageName"
dism /Apply-Image /ImageFile:${mountedDriveLetterPath}sources\install.wim /Index:$($image.ImageIndex) /ApplyDir:$($windowsPartition.DriveLetter):\ /CheckIntegrity

#prep boot files
bcdboot "$($windowsPartition.DriveLetter):\Windows" /s "$($systemPartition.DriveLetter):" /f ALL

# Copy the unattend file to the Windows partition
#Copy-Item -Path $UnattendPath -Destination "$($windowsPartition.DriveLetter):\Windows\Panther\Unattend.xml" -Force

# Dismount the VHDX and the ISO
Dismount-VHD -Path $outputVHDX
Dismount-DiskImage -ImagePath $sourceISO

