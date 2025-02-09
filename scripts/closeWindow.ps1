[CmdletBinding()]
param(
    [Parameter(mandatory = $true)]
    [string] $windowTitleToMatch
)

# Iterate through all processes and find the one matching the window title
$foundProcess = Get-Process | Where-Object { $_.MainWindowTitle -like $windowTitleToMatch }

# Add type definition for user32.dll functions
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    public const int WM_SYSCOMMAND = 0x0112;
    public const int SC_CLOSE = 0xF060;

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@

$foundProcess = Get-Process | Where-Object { $_.MainWindowTitle -like $windowTitleToMatch }

if (-not $foundProcess) {
    #Write-Output "No window found matching: $windowTitleToMatch"
    Exit
}

$hWnd = $foundProcess.MainWindowHandle

# Check if the window handle is valid
if ($hWnd -ne [IntPtr]::Zero) {
    # Send the SC_CLOSE command to the window
    [Win32]::SendMessage($hWnd, [Win32]::WM_SYSCOMMAND, [IntPtr][Win32]::SC_CLOSE, [IntPtr]::Zero)
}
