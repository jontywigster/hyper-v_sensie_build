[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$vhdx,
    [Parameter(Mandatory = $true)]
    [string]$os,
    [Parameter(Mandatory = $true)]
    [string]$hostname,
    [Parameter(Mandatory = $true)]
    [string]$adminPwd
)

$ErrorActionPreference = 'Stop'

Mount-VHD -Path $vhdx
$mountedVHDX= Get-Disk | Where-Object { $_.Location -eq "$vhdx" }

#get template file
$parentDirectory = Split-Path -Path $PSScriptRoot -Parent
$unattendTemplateDirectory = Join-Path -Path $parentDirectory "win_unattend_templates"
$unattendTemplateFile = Join-Path -Path $unattendTemplateDirectory -ChildPath "$os.xml"

if (-not (Test-Path -Path $unattendTemplateFile)) { throw "file $templateUnattendFile doesn't exist" }
$unattendXML = [xml](Get-Content -Path $unattendTemplateFile)

#set ComputerName in template
$computerNameNode=$unattendXML.unattend.settings.component | Where-Object { $_.ComputerName -ne $null } 
$computerNameNode.ComputerName="$hostname"

#set admin password in template
$adminPasswordNode=$unattendXML.unattend.settings.component.UserAccounts.AdministratorPassword | Where-Object { $_.Value -ne $null } 
$adminPasswordNode.Value=$adminPwd

#set autologon password in template
$AutoLogonNode = $unattendXML.unattend.settings.component.AutoLogon.Password | Where-Object { $_.Value -ne $null } 
$AutoLogonNode.Value =$adminPwd

#Write-Host $unattendXML.OuterXml

#create unattend file in vhdx
$partition = Get-Partition -DiskNumber $mountedVHDX.Number | Where-Object { $_.Type -eq 'Basic' }
$driveLetter = $partition.DriveLetter
$unattendFilePath = "$($driveLetter):\Windows\Panther\Unattend.xml"
$pantherPath = Split-Path -Path $unattendFilePath
if (-not (Test-Path -Path $pantherPath)) {
    New-Item -Path $pantherPath -ItemType Directory
}
$unattendXML.OuterXml | Out-File -FilePath $unattendFilePath -Encoding UTF8

dismount-VHD -Path $vhdx

