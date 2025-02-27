param (
    [Parameter(mandatory = $true)]
    [string]$sourcePath,
    [Parameter(mandatory = $true)]
    [string]$destinationPath
)

#if $destinationPath is a directory, append the filename from the source path
if (Test-Path -Path $destinationPath -PathType Container) {
    $filename = Split-Path -Path $sourcePath -Leaf
    $destinationPath = Join-Path -Path $destinationPath -ChildPath $filename
} 

$sourceFile = Get-Item -Path $sourcePath
$totalSize = $sourceFile.Length
$bufferSize = 8MB
$bytesCopied = 0
$lastPercentComplete = 0

$sourceStream = [System.IO.File]::OpenRead($sourcePath)
$destinationStream = [System.IO.File]::Create($destinationPath)
$buffer = New-Object byte[] $bufferSize

try {
    while (($bytesRead = $sourceStream.Read($buffer, 0, $bufferSize)) -gt 0) {
        $destinationStream.Write($buffer, 0, $bytesRead)
        $bytesCopied += $bytesRead
        $percentComplete = [math]::Floor(($bytesCopied / $totalSize) * 100)
        
        # update progress bar only if the new percentage is greater than the last reported percentage
        if ($percentComplete -gt $lastPercentComplete) {
            Write-Progress -Activity "Copying file" -Status "$percentComplete% complete" -PercentComplete $percentComplete
            $lastPercentComplete = $percentComplete
        }
    }
}
catch { throw "Error copying file: $_" }
finally {
    $sourceStream.Close()
    $destinationStream.Close()
}

return $destinationPath

