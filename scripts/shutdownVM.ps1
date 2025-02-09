#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory=$true)]
  [string[]] $vmName
)

function Get-VMState {
    param (
        [string]$vmName
    )
    $vm = Get-VM -Name $vmName
    return $vm.State
}

try {
    Stop-VM -Name $vmName -Force
} catch {

    #vm-stop for ubuntuAz unreliable. Issue shutdown command via SSH
    . .\scripts\getSecrets.ps1
    $sshKeyPath = $LINUX_VM_SSH_KEY_PATH
    $sshUser = $LINUX_VM_SSH_USER
    $shutdownCommand = "sudo shutdown -h now"

    $vmNetworkAdapter = Get-VMNetworkAdapter -VMName "$hostname"
    $ipAddresses = $vmNetworkAdapter.IPAddresses
    $sshHost = $ipAddresses | Where-Object { $_ -match "^\d{1,3}(\.\d{1,3}){3}$" }
    $sshCommand = "ssh -o StrictHostKeyChecking=no -i $sshKeyPath $sshUser@$sshHost $shutdownCommand"
    Invoke-Expression $sshCommand

    # Wait for VM to shut down
    Write-Output "Waiting for VM to shut down..."
    while ((Get-VMState -vmName $hostname) -ne 'Off') {
    Start-Sleep -Seconds 5
    echo "."
    }

    Write-Output "VM is now shut down."
}
