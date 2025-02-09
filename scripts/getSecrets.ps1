<#
get secret variables' values
#>

$filePath = ".\build.env"

# Check if the file exists
if (-Not (Test-Path -Path $filePath)) {
    throw "Secrets file $filePath does not exist"
}

# Read the content of the file
$content = Get-Content -Path $filePath

# Loop through each line and set variables
foreach ($line in $content) {
    if ($line -match "^(.*?)='(.*?)'$") {
        $variableName = $matches[1]
        $variableValue = $matches[2]
        Set-Variable -Name $variableName -Value $variableValue
    }
}
