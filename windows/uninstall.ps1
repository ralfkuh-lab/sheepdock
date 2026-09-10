# Remove herdr-terminal.exe, its shortcuts and, optionally, the Alacritty profile.
#
#   .\uninstall.ps1 [-Prefix DIR] [-ConfigDir DIR] [-Purge]
#
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\sheepdock'),
    [string]$ConfigDir = (Join-Path $env:APPDATA 'sheepdock'),
    # also delete the config directory (your alacritty.toml)
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

$exe = Join-Path $Prefix 'herdr-terminal.exe'
$running = Get-Process -Name 'herdr-terminal' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
if ($running) {
    Write-Host 'herdr-terminal.exe is running. Close the herdr window first.' -ForegroundColor Red
    exit 1
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\herdr.lnk'
if (Test-Path $startMenu) {
    Remove-Item -Force $startMenu
    Write-Host "removed $startMenu"
}

if (Test-Path $Prefix) {
    Remove-Item -Recurse -Force $Prefix
    Write-Host "removed $Prefix"
} else {
    Write-Host "nothing to remove at $Prefix"
}

if ($Purge) {
    if (Test-Path $ConfigDir) {
        Remove-Item -Recurse -Force $ConfigDir
        Write-Host "removed $ConfigDir"
    }
} else {
    Write-Host "kept $ConfigDir (use -Purge to remove it)"
}

Write-Host 'If herdr was pinned to the taskbar, the pin is now dead - right-click it and unpin.'
Write-Host 'herdr itself and any Alacritty you installed yourself were never modified.'
