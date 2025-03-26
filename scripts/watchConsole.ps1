#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(mandatory = $true)]
    [string] $vmName
)

#set up event handler for Ctrl-C
$global:cts = [System.Threading.CancellationTokenSource]::new()

#hndle Ctrl+C using a try-catch block
try {
    [System.Console]::TreatControlCAsInput = $false #treat Ctrl+C as interrupt
    [Console]::CancelKeyPress += {
        $global:cts.Cancel()
        Write-Host "`nStopping script"
    }
}
catch {
    Write-Host "Ctrl+C handling may not be fully functional in this environment" 
}

$pipePath = "\\.\pipe\$vmName-com1"
Write-Host "wait for serial connection to vm"

#map string patterns to output
$mapping = @{
    "*Cloud-init * running 'init-local'"     = "begin"
    "*Cloud-init * running 'init'*"          = "bring up network"
    "*Cloud-init * 'modules:config'*"       = "install OS updates"
    "*Cloud-init * 'modules:final'*"        = "runcmd"
    "*Setting up ansible *"                  = "install ansible"
    "ansible pull*"                          = "pull ansible playbook"
    "ansible play start"                     = "ansible play start"
    "ansible begin install *"                = "line"
    "ansible build done for *"              = "line"
    "*Reached target*cloud-init.target*"     = "done"
    "*loud-init*alma*running*modules:final*" = "done"
    "*cloud-init* Failed to run module *"    = "fail"
}

$pipeContent = @()
$success = $false
$fails = @()
$lineCounter = 0
$bufferString = "" #buffer to store partial lines
$pipeStream = $null # Initialize pipeStream to null

try {
    $pipeStream = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipePath.Split("\")[-1], [System.IO.Pipes.PipeDirection]::In)
    $pipeStream.Connect(5000)
    Write-Host "connected, wait for cloud-init" -NoNewline

    $buffer = [System.Array]::CreateInstance([byte], 1024)
    while ($pipeStream.IsConnected -and -not $global:cts.IsCancellationRequested) {
        $readTask = $pipeStream.ReadAsync($buffer, 0, $buffer.Length, $global:cts.Token)
        try {
            $readTask.Wait(100) #wait for 100 milliseconds, or until cancellation
        }
        catch [System.AggregateException] {
            if ($global:cts.IsCancellationRequested) {
                break; #cancelled, exit loop
            }
            throw; #re-throw if not a cancellation
        }
        catch [System.TimeoutException] {
            #continue on time out, will loop back and check for cancellation
        }

        if ($readTask.IsCompleted) {
            $bytesRead = $readTask.Result
            if ($bytesRead -gt 0) {
                $bufferString += [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)

                #split buffer to lines
                $lines = $bufferString.Split("`n", [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($lines.Count -gt 1) {
                    for ($i = 0; $i -lt ($lines.Count - 1); $i++) {
                        $line = $lines[$i].Trim([char]0x00, [char]0x0a, [char]0x0d)
                        if ($line) {
                            $pipeContent += $line
                            $lineCounter++

                            foreach ($key in $mapping.Keys) {
                                #output mapping text if there's a match
                                if ($line -ilike $key) {
                                    if ($($mapping[$key]) -eq "done") {
                                        Write-Host "`ndone" 
                                        $success=$true
                                        $pipeStream.Close()
                                        #break; 
                                    }
                                    elseif ($($mapping[$key]) -eq "line") {
                                        Write-Host "`n$line" -NoNewline
                                    }
                                    elseif ($($mapping[$key]) -eq "fail") {
                                        Write-Host "`n$line" -NoNewline
                                        $fails += $line 
                                        #have defaulted to false $success = $false
                                    }
                                    else {
                                        #got a match in map but no special handling, output line as-is
                                        Write-Host "`n$($mapping[$key])" 
                                        #break; #exit foreach loop
                                    }
                                }
                                else {
                                    #output a dot for every n lines since there's so much logging
                                    if ($lineCounter % 75 -eq 0) { Write-Host "." -NoNewline  }
                                }
                            }
                        }
                    }
                    $bufferString = $lines[$lines.Count - 1] #store remaining partial line
                }
            }
            elseif (!$pipeStream.IsConnected) {
                break
            }
        }
    }
}
catch [System.OperationCanceledException] {
    $success = $false;
    Write-Host "`ncancelled" 
}
catch {
    $success = $false
    Write-Host "Failed to connect to named pipe: $pipePath. Error: $_" 
}

finally {
    if ($pipeStream -and $pipeStream.IsConnected) {
        $pipeStream.Close() 
    }
    $global:cts.Dispose() 
}

#set output explicitly
$result = @{
    success = $success
    fails   = $fails
    log     = ($pipeContent -join "`n")
}

return $result