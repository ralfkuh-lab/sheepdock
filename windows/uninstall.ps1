# Remove the herdr terminal copy, its shortcuts and settings.
#
#   .\uninstall.ps1 [-Prefix DIR]
#
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\sheepdock')
)

$ErrorActionPreference = 'Stop'

$exe = Join-Path $Prefix 'terminal\WindowsTerminal.exe'
if (Get-Process -Name 'WindowsTerminal' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) {
    Write-Host 'The herdr window is open. Close it first.' -ForegroundColor Red
    exit 1
}
$legacyExe = Join-Path $Prefix 'herdr-terminal.exe'
if (Get-Process -Name 'herdr-terminal' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $legacyExe }) {
    Write-Host 'The old Alacritty-based herdr window is open. Close it first.' -ForegroundColor Red
    exit 1
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\herdr.lnk'
if (Test-Path $startMenu) {
    Remove-Item -Force $startMenu
    Write-Host "removed $startMenu"
}

if (Test-Path $Prefix) {
    Remove-Item -Recurse -Force $Prefix
    Write-Host "removed $Prefix (including the terminal settings)"
} else {
    Write-Host "nothing to remove at $Prefix"
}

# config directory of the earlier Alacritty-based launcher
$legacyConfig = Join-Path $env:APPDATA 'sheepdock'
if (Test-Path $legacyConfig) {
    Remove-Item -Recurse -Force $legacyConfig
    Write-Host "removed $legacyConfig"
}

Write-Host 'If herdr was pinned to the taskbar, the pin is now dead - right-click it and unpin.'
Write-Host 'herdr itself and your regular Windows Terminal were never modified.'
