<#
Based on
https://github.com/schtritoff/hyperv-vm-provisioning
Cheers
#>

#requires -Modules Hyper-V

# Check if the script is running as an administrator
$adminCheck = [Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())
if ( !($adminCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $path="'"+$PSScriptRoot+"'"
    $scriptName = ".\"+$MyInvocation.MyCommand.Name
    Start-Process Powershell.exe -ArgumentList "-ExecutionPolicy bypass", "-command", "cd", "$path; $scriptName"  -Verb RunAs

    exit
}

$ErrorActionPreference = 'Stop'
$VerbosePreference = "SilentlyContinue"

$sshCommand = "ssh"
$sshArgs = "build@wds.baltsch.com exit"
$process = Start-Process -FilePath $sshCommand -ArgumentList $sshArgs -NoNewWindow -PassThru -Wait

if ($process.ExitCode -ne 0) { throw "Couldn't establish SSH session to WDS server: $sshResult. Key must be stored in agent" }

. .\scripts\getSecrets.ps1


# Check if the WDS_DEFAULT_PW variable is set
if (-Not (Get-Variable -Name "WDS_DEFAULT_PW" -ErrorAction SilentlyContinue)) {
    throw "Secrets read but WDS_DEFAULT_PW is missing"
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
            break
        }
    } else {
        Write-Output "Invalid selection"
    }
} while (-not $selectedOS -or $confirmation -ne "yes")

$defaultHostname=$edition
. .\scripts\PromptHostname.ps1
$hostname=promptHostname -defaultHostname $defaultHostname
$newPassword = Read-Host "set $($hostname) admin account password" -AsSecureString

$templateVM=$(& .\scripts\refreshWindowsTemplate.ps1 -edition $edition -winName $winName)

#close template vm window
& .\scripts\closeWindow.ps1 -windowTitleToMatch $($templateVm.Name  + " * Virtual Machine Connection")
#new vm might be being rebuilt so is already open. Close it, if so
& .\scripts\closeWindow.ps1 -windowTitleToMatch $($hostname  + " * Virtual Machine Connection")
Write-Output "clone template vm"
$vm=& .\scripts\cloneVm.ps1 -sourceVmName $templateVm.Name -cloneVmName $hostname
Start-VM -Name $hostname

# Retrieve the WDS build default admin password securely
$securePassword = Get-Secret -Name "WDSAdminPassword"
$credential = New-Object System.Management.Automation.PSCredential ("administrator", $securePassword)

(Invoke-Command -VMName $hostname -Credential $credential -ScriptBlock {
    param (
        [System.Security.SecureString]$newPassword,
        [string]$hostname
    )

    Set-LocalUser -Name "Administrator" -Password $newPassword

    Rename-Computer -NewName $hostname -Force -WarningAction SilentlyContinue

    Start-Transcript -Path "c:\sensie_build\get_rdp_cert.log" -Append
    Write-Output "new hostname: $hostname"
    #get rdp cert script
	Invoke-WebRequest -uri "https://nr.oc.baltsch.com/sensie_build/win/rdp_cert_script" -OutFile "C:\sensie_build\get_rdp_cert.ps1"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-File C:\sensie_build\get_rdp_cert.ps1 -hostname $hostname" -Wait
    Stop-Transcript
} -ArgumentList $newPassword, "$hostname") > $null 2>&1

#NB - won't bother sysprepping
Stop-VM -Name $hostname
Set-VM -CheckpointType Production -Name $hostname
Checkpoint-VM -SnapshotName "sensie build snap before first boot" -Name $hostname

Write-Output "$($vm.name) done"

$startVm = Read-Host "Start VM $($hostname)? (y/n)"

if ($startVm -eq 'y' -or [string]::IsNullOrEmpty($startVm)) {
    Start-VM -Name $hostname
    Start-Process "vmconnect" "localhost","$hostname"
}
