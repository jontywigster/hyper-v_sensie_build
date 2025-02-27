# Define the NAS hostname and port to check
$nas = "nas.baltsch.com"
$port = 443

# Check if a specific port is open on the NAS
function Test-Port {
    param (
        [string]$ComputerName,
        [int]$Port
    )
    try {
        $tcpConnection = New-Object System.Net.Sockets.TcpClient
        $tcpConnection.Connect($ComputerName, $Port)
        $tcpConnection.Close()
        return $true
    } catch {
        return $false
    }
}

# Ping the NAS to check if it is running
Write-Host "Checking if NAS is up"

$pingResult = Test-Connection -ComputerName $nas -Count 2 -Quiet

if ($pingResult) {
    Write-Host "NAS reachable"
} else {
    Write-Host "NAS is not reachable, send wake request"

    # Call the Wake-on-LAN URL to wake the NAS
    $wolUrl = "https://wake.proxy.baltsch.com/nas"
    Invoke-RestMethod -Uri $wolUrl -Method Get
    Write-Host "Wake-on-LAN request sent"

    # Wait for the NAS to become pingable
    $maxAttempts = 30
    $attempt = 0
    $nasUp = $false

    Write-Host "Waiting for the NAS to become reachable" -NoNewline
    while ($attempt -lt $maxAttempts -and -not $nasUp) {
        Start-Sleep -Seconds 5
        $nasUp = Test-Connection -ComputerName $nas -Count 2 -Quiet
        $attempt++
        Write-Host "." -NoNewline
    }
    Write-Host ""

    if ($nasUp) {
        Write-Host "The NAS is now reachable. Checking if fully booted"
    } else {
        throw "The NAS could not be reached after attempting to wake it up."
    }
}

# Check if the specific port (e.g., SSH) is open
$portCheckAttempts = 30
$portCheckInterval = 10
$portIsOpen = $false

Write-Host "Checking if NAS port $($port) open" -NoNewline
for ($i = 0; $i -lt $portCheckAttempts; $i++) {
    if (Test-Port -ComputerName $nas -Port $port) {
        $portIsOpen = $true
        break
    } else {
        Start-Sleep -Seconds $portCheckInterval
        Write-Host "." -NoNewline
    }
}
Write-Host ""

if ($portIsOpen) {
    Write-Host "NAS ready"
} else {
    throw "NAS reachable but port $port is not"
}
