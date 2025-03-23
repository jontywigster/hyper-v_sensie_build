#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)]
    [string] $vmName
)

#$pipePath = "\\.\pipe\$vmName-comBuild"
$pipePath = "\\.\pipe\$vmName-com1"
Write-Host "wait for serial connection to vm"

# Define the mapping of patterns to actions
$mapping = @{
    "*Cloud-init * running 'init-local'" = "begin"
    "*Cloud-init * running 'init'*"      = "bring up network"
    "*Cloud-init * 'modules:config'*"    = "install OS updates"
    "*Cloud-init * 'modules:final'*"     = "runcmd"
    "*Setting up ansible *"              = "install ansible"
    "*ansible pull*"                     = "pull ansible playbook"
    "*Reached target*cloud-init.target*" = "done"
}

$pipeContent = @()
$lineCounter = 0

try {
    $pipeStream = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipePath.Split("\")[-1], [System.IO.Pipes.PipeDirection]::In)
    $pipeStream.Connect(5000) # wait up to 5 seconds for connection
    $reader = New-Object System.IO.StreamReader($pipeStream)

    Write-Host "connected, wait for cloud-init"
    while ($pipeStream.IsConnected -and !$reader.EndOfStream) {
        $line = $reader.ReadLine().Trim()
        if ($line) {
            $pipeContent += $line
            $lineCounter++
            #Write-Host "$line"

            #build done, close pipe to end
            if ($line -like "*Reached target*cloud-init.target*") {
                Write-Host "done"
                $pipeStream.Close() 
            }
            else {
                # output mapping text if there's a match
                foreach ($key in $mapping.Keys) {
                    if ($line -like $key) {
                        Write-Host "`n$($mapping[$key])"
                        break
                    }
                    else {
                        if ($lineCounter % 50 -eq 0) { Write-Host "." -NoNewline }
                    }
                }
            }
        }
    }
}
catch {
    return "Failed to connect to named pipe: $pipePath. Error: $_"
}
finally {
    if ($pipeStream -and $pipeStream.IsConnected) {
        $pipeStream.Close()
    }
}

#Write-Host "`nComplete Pipe Content:"
#$pipeContent | ForEach-Object { Write-Host $_ }
return "done"
