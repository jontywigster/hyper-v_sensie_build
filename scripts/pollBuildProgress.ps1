#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
  [Parameter(mandatory = $true)]
  [string] $vmName,
  [switch[]] $windows
)

$verbosePref=(Get-Variable -Name VerbosePreference).Value

Import-Module Hyper-V
Write-Host "Waiting for build to start"

function getKVPBuildStatus {
  $vm = Get-CimInstance -Namespace "root\virtualization\v2" -ClassName "Msvm_ComputerSystem" -Filter "ElementName = '$vmName'"
  $kvpData = Get-CimInstance -Namespace "root\virtualization\v2" -ClassName "Msvm_KvpExchangeComponent" | Where-Object { $_.SystemName -eq $vm.Name }

  if ($kvpData.GuestExchangeItems.count -eq 0) {
    return "no gei"
  }
  else {
    #if the guest writes multiple keys, GuestExchangeItems is not valid XML
    #bodge regex instead
      
    $guestExchangeItemsString = [string]$kvpData.GuestExchangeItems
    $instances = $guestExchangeItemsString -split '</INSTANCE>'

    foreach ($instance in $instances) {
      if ($instance -match '<VALUE>sensie_build</VALUE>') {
        #$dataValue = $instance -match '<PROPERTY NAME="Data" TYPE="string"><VALUE>(.*?)</VALUE>'
        $instance -match '<PROPERTY NAME="Data" TYPE="string"><VALUE>(.*?)</VALUE>'
        if ($matches[1]) {
          return $($matches[1])
        }
      }
    }
  }
}

function getWindowsKVPBuildStatus {
  $vm = Get-WmiObject -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter "ElementName='$vmName'"

  #get KVP Exchange Component
  $kvpComponent = Get-WmiObject -Namespace root\virtualization\v2 -Query "Associators of {$vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
  $kvpValues = $kvpComponent.GuestExchangeItems

  if ($null -ne $kvpValues) {
    $kvpValues | Where-Object { $_ -ne $null } | ForEach-Object {
      $kvpXml = [xml]$_
      $name = $kvpXml.SelectSingleNode("/INSTANCE/PROPERTY[@NAME='Name']/VALUE").InnerText
      if ($name -eq "sensie_build") {
          $data = $kvpXml.SelectSingleNode("/INSTANCE/PROPERTY[@NAME='Data']/VALUE").InnerText
          #Write-Host "here $data"
          return $data
      }
    }
  } else {
    Write-Host "The variable \$kvpValues is null."
  }
}

function prettyPrint($buildStatus) {
  switch ($buildStatus) {
       "no gei" {$pretty="Waiting for OS"; Break }
       "base" {$pretty="Ansible build"; Break }
       "circ" {$pretty="cloud-init started"; Break }
       "dock" {$pretty="Docker install"; Break }
       "done" {$pretty="done"; Break }
       "inan" {$pretty="cloud-init runcmd"; Break }
       "rena" {$pretty="Rename host"; Break }
  }
  return $pretty
}

if ($windows) {
  $buildStatus = getWindowsKVPBuildStatus 
} else {
  $buildStatus = getKVPBuildStatus
}

$previousStatus = $buildStatus

while ($buildStatus -ne "done") {
    Start-Sleep -Seconds 5

    $buildStatus = ($windows) ? $(getWindowsKVPBuildStatus) : $(prettyPrint(getKVPBuildStatus))

    if ($null -eq $buildStatus) {
        Write-Host -NoNewline "."
    } else {
        if ($buildStatus -eq $previousStatus) {
            Write-Host -NoNewline "."
        } else {
            Write-Host "`r`n$($buildStatus)"
            $previousStatus = $buildStatus
        }
    }
}

$VerbosePreference = $verbosePref
#return $true
