param (
    [Parameter(mandatory = $true)]    
    [string]$vmName,
    [string]$AdminUser = "Administrator",
    [string]$AdminPwd = "$(. .\scripts\getEnvVars.ps1; $WIN_TEMPLATE_ADMIN_PWD)",
    [string]$NewAdminPwd
)

if (!$AdminPwd) { throw "AdminPwd is not set" }

# Import Hyper-V module
Import-Module Hyper-V

$vm = Get-VM -Name $vmName

if ($vm.State -ne "Running") {
    Write-Output "start $vmName"
    Start-VM -Name $vmName
    & .\scripts\pollVMStartup.ps1 -vmName $vmName
} 

## Create a PowerShell session to the VM
$securePwd = ConvertTo-SecureString $AdminPwd -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($AdminUser, $securePwd)

$SecureNewAdminPwd = ConvertTo-SecureString $NewAdminPwd -AsPlainText -Force -WarningVariable renameWarning -WarningAction SilentlyContinue

$result = @{
    success = $true
    fails   = ""
    log     = ""
}
$session = $null

while ($null -eq $session) {
    $session = New-PSSession -VMName $vmName -Credential $credential -ErrorAction SilentlyContinue
    Write-Host "PowerShell session to $vmName established."
    Start-Sleep -Seconds 1
}

try {
    $output = Invoke-Command -Session $session -ScriptBlock {
        param (
            [string]$AdminUser,
            [System.Security.SecureString]$SecureNewAdminPwd,
            [string]$vmName
        )
        try {
            Set-LocalUser -Name $AdminUser -Password $SecureNewAdminPwd -PasswordNeverExpires $true
            echo "password changed for $AdminUser"
        }
        catch {
            $result.fails = "pw chg err: $_"
            $result.success = $false
        }
        
        Rename-Computer -NewName $vmName -Force
        Write-Output "hostname changed to $vmName"
    } -ArgumentList $AdminUser, $SecureNewAdminPwd, $vmName
}
catch {
    $result.fails = "Error: $_"
    $result.success = $false
}
finally {
    $result.log = $output -join "`n"
}

Restart-VM -Name $vmName -Force -PassThru | Out-Null
& .\scripts\pollVMStartup.ps1 -vmName $vmName

return $result