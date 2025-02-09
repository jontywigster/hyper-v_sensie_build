#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(mandatory=$true)]    
    [string[]] $vmName
)

$vm = Get-VM -VMName "$vmName" -ErrorAction 'SilentlyContinue'

if (!($vm)) { return "" }

$VMStoragePath = (Get-VMHost).VirtualHardDiskPath
if (-not $VMStoragePath) {
    throw "Couldn't get VMStoragePath from Get-VMHost, quitting" 
}

$hostVMFolder = (Get-VMHost).VirtualMachinePath
if (-not $hostVMFolder) {
  throw "Couldn't get VirtualMachinePath from Get-VMHost"
}

Write-host "ensure vm $($vm.Name) stopped, removed"
$oldWarningPreference = $WarningPreference
$WarningPreference = "SilentlyContinue"
Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue > $null
$WarningPreference = $oldWarningPreference

Get-VMSnapshot -VMName $vmName  | Remove-VMSnapshot -IncludeAllChildSnapshots

Get-vhd -VMId "$($vm.Id)" -ErrorAction SilentlyContinue | ForEach-Object {
    #remove folder containing disk if not empty
    #and not h-v machine or disk path
    $folder =(Get-Item $_.path).DirectoryName
    remove-item -path $_.path -force -ErrorAction SilentlyContinue
    if (("$folder" -ne "$VMStoragePath") -and ("$folder" -ne "$hostVMFolder"))  {
        If ((Get-ChildItem -Path "$folder" -Force | Measure-Object).Count -eq 0) {
            Remove-Item -Path "$folder"
        } 
    }
}

# remove vm
$vm | Remove-VM -Force -ErrorAction Stop > $null

Write-Host "vm $vm removed"

