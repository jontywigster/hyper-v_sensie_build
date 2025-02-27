<#
Based on
https://github.com/schtritoff/hyperv-vm-provisioning
Cheers
#>

#[CmdletBinding()]
#param(
#	#,
#    #[Parameter(Mandatory=$true)]
#    #[string]$password,
#    [Parameter(mandatory=$true)]
#    [string]$SourcePath,
#    [Parameter(mandatory=$true)]
#    [string]$Edition,
#    [Parameter(mandatory=$true)]
#    [string]$VHDPath,
#    [string]$SizeBytes = "60GB"
#)

#requires -Modules Hyper-V

# Check if the script is running as an administrator
$adminCheck = [Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())
if ( !($adminCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $path="'"+$PSScriptRoot+"'"
    $scriptName = ".\"+$MyInvocation.MyCommand.Name
    Start-Process Powershell.exe -ArgumentList "-ExecutionPolicy bypass", "-command", "cd", "$path; $scriptName"  -Verb RunAs

    exit
}

#prompt for os
$aOS = @(
    @{ Name = "25sc"; Description = "2025_Standard_Core" }
    @{ Name = "25dc"; Description = "2025_DC_Core" }
    @{ Name = "25s";  Description = "2025_Standard" }
    @{ Name = "25d";  Description = "2025_DC" }
)

do {
    Write-Output "Choose Windows version:"
    foreach ($os in $aOS) {
        Write-Output "$($os.Name) - $($os.Description)"
    }

    $choice = Read-Host "Enter OS short name"
    $selectedOS = $aOS | Where-Object { $_.Name -eq $choice }

    if ($selectedOS) {
        $confirmation = Read-Host "$($selectedOS.Name) ($($selectedOS.Description)) selected. Continue? (y/n) n will prompt again"
        if ($confirmation -eq "y" -or $confirmation -eq "") {
            $edition=$($selectedOS.Name)
            $winName=$($selectedOS.Description)
            $template=".\templates\$($selectedOS.Description).xml"
            break
        }
    } else {
        Write-Output "Invalid selection"
    }
} while (-not $selectedOS -or $confirmation -ne "yes")

$defaultHostname=$edition
. .\scripts\PromptHostname.ps1
$hostname=promptHostname -defaultHostname $defaultHostname
do {
    $password = Read-Host "set $($hostname) admin account password"
    if ([string]::IsNullOrWhiteSpace([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newPassword)))) {
        Write-Host "Password cannot be empty" -ForegroundColor Red
    }
} while ([string]::IsNullOrWhiteSpace([System.Runtime.InteropServices.Marshal]::PtrToStringBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newPassword))))


#get template file
if (-not (Test-Path -Path $template)) { throw "templateUnattend $templateUnattendFile doesn't exist" }
$unattendXML = [xml](Get-Content -Path $template)

#set ComputerName in template
$computerNameNode=$unattendXML.unattend.settings.component | Where-Object { $_.ComputerName -ne $null } 
$computerNameNode.ComputerName="$hostname"

#set admin password in template
$adminPasswordNode=$unattendXML.unattend.settings.component.UserAccounts.AdministratorPassword | Where-Object { $_.Value -ne $null } 
$adminPasswordNode.Value=$password

#set autologon password in template
$AutoLogonNode = $unattendXML.unattend.settings.component.AutoLogon.Password | Where-Object { $_.Value -ne $null } 
$AutoLogonNode.Value =$password

Write-Host $unattendXML.OuterXml


$ISOPath = Resolve-Path $SourcePath
$VHDXPath = $VHDPath

# Check if the VHDX file already exists
if (Test-Path $VHDXPath) {
    # Dismount the VHDX if it is mounted
    $mountedVHD = Get-DiskImage -ImagePath $VHDXPath -ErrorAction SilentlyContinue
    if ($mountedVHD) {
        Dismount-VHD -Path $VHDXPath
    }
    # Delete the existing VHDX file
    Remove-Item -Path $VHDXPath -Force
}

# Mount the ISO
Mount-DiskImage -ImagePath $ISOPath
$mountedISO = Get-DiskImage -ImagePath $ISOPath | Get-Volume
$mountedDriveLetter = $mountedISO.DriveLetter
if (-not $mountedDriveLetter) {
    throw "Failed to get the drive letter of the mounted ISO."
}

$mountedDriveLetterPath = $mountedDriveLetter + ":\"

# Create the VHDX
New-VHD -Path $VHDXPath -Dynamic -SizeBytes $SizeBytes
Mount-VHD -Path $VHDXPath
$vhd = Get-Disk | Where-Object { $_.Location -eq "$VHDXPath" }

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

# Apply the Windows image to the VHDX
dism /Apply-Image /ImageFile:${mountedDriveLetterPath}sources\install.wim /Index:1 /ApplyDir:$($windowsPartition.DriveLetter):\ /CheckIntegrity

# Prepare the Boot Files
bcdboot "$($windowsPartition.DriveLetter):\Windows" /s "$($systemPartition.DriveLetter):" /f ALL

# Copy the unattend file to the Windows partition
#Copy-Item -Path $UnattendPath -Destination "$($windowsPartition.DriveLetter):\Windows\Panther\Unattend.xml" -Force

# Dismount the VHDX and the ISO
Dismount-VHD -Path $VHDXPath
Dismount-DiskImage -ImagePath $ISOPath

#Convert-WindowsImage -SourcePath "D:\iso\2022.iso" -Edition 'Windows Server 2022 Standard' -VHDPath 'D:\iso\test.vhdx' -SizeBytes "60GB"

$testpath= Resolve-Path ".\templates\closeWindow.ps1"
echo "$testpath"

## $templateVM=$(& .\scripts\refreshWindowsTemplate.ps1 -edition $edition -winName $winName)
## 
## #close template vm window
## & .\scripts\closeWindow.ps1 -windowTitleToMatch $($templateVm.Name  + " * Virtual Machine Connection")
## #new vm might be being rebuilt so is already open. Close it, if so
## & .\scripts\closeWindow.ps1 -windowTitleToMatch $($hostname  + " * Virtual Machine Connection")
## Write-Output "clone template vm"
## $vm=& .\scripts\cloneVm.ps1 -sourceVmName $templateVm.Name -cloneVmName $hostname
## Start-VM -Name $hostname
## 
## # Retrieve the WDS build default admin password securely
## $securePassword = Get-Secret -Name "WDSAdminPassword"
## $credential = New-Object System.Management.Automation.PSCredential ("administrator", $securePassword)
## 
## (Invoke-Command -VMName $hostname -Credential $credential -ScriptBlock {
##     param (
##         [System.Security.SecureString]$newPassword,
##         [string]$hostname
##     )
## 
##     Set-LocalUser -Name "Administrator" -Password $newPassword
## 
##     Rename-Computer -NewName $hostname -Force -WarningAction SilentlyContinue
## 
##     Start-Transcript -Path "c:\sensie_build\get_rdp_cert.log" -Append
##     Write-Output "new hostname: $hostname"
##     #get rdp cert script
## 	Invoke-WebRequest -uri "https://nr.oc.baltsch.com/sensie_build/win/rdp_cert_script" -OutFile "C:\sensie_build\get_rdp_cert.ps1"
##     Start-Process -FilePath "powershell.exe" -ArgumentList "-File C:\sensie_build\get_rdp_cert.ps1 -hostname $hostname" -Wait
##     Stop-Transcript
## } -ArgumentList $newPassword, "$hostname") > $null 2>&1
## 
## #NB - won't bother sysprepping
## Stop-VM -Name $hostname
## Set-VM -CheckpointType Production -Name $hostname
## Checkpoint-VM -SnapshotName "sensie build snap before first boot" -Name $hostname
## 
## Write-Output "$($vm.name) done"
## 
## $startVm = Read-Host "Start VM $($hostname)? (y/n)"
## 
## if ($startVm -eq 'y' -or [string]::IsNullOrEmpty($startVm)) {
##     Start-VM -Name $hostname
##     Start-Process "vmconnect" "localhost","$hostname"
## }


