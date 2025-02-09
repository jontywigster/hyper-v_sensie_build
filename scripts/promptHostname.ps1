function promptHostname {
    param (
        [Parameter(mandatory = $true)]
        [string] $defaultHostname
    )

    do {
        $hostname = Read-Host "`nSet hostname. If empty, will use default $defaultHostname"
        $hostname = $hostname.Trim()
        if ([string]::IsNullOrEmpty($hostname)) {
            $hostname = $defaultHostname
        }
        if (([System.Uri]::CheckHostName($hostname) -ne 'Dns') -or ($hostname.Contains("_")) -or ($hostname.Contains("."))) {
            Write-Host "`nhostname $hostname isn't valid, e.g. no underscore, no dot"
            $response = "n"
        }
        else {
            $vm = Get-VM -Name $hostname -ErrorAction SilentlyContinue
            if ($vm) {
                $response = Read-Host "A VM with the name $hostname already exists. Continue and overwrite? (y/n to enter new name)"
            }
            else {
                $response = "y"
            }
        }
    } while ($response -ne "y")
    return $hostname
}
