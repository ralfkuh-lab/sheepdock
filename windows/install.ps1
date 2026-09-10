# sheepdock for Windows - install a private, branded copy of Windows Terminal
# that opens herdr in its own window with its own taskbar icon.
#
# No admin rights needed: everything lands under %LOCALAPPDATA%.
#
#   .\install.ps1 [-Prefix DIR] [-Icon SRC] [-TerminalVersion X.Y.Z.W]
#                 [-Force] [-NoStartMenu]
#
#Requires -Version 5.1
[CmdletBinding()]
param(
    # where the terminal copy, icon, launcher script and shortcut go
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\sheepdock'),
    # logo URL or image path
    [string]$Icon = 'https://herdr.dev/assets/logo.png',
    # Windows Terminal release to download (the unpackaged zip, run in portable mode)
    [string]$TerminalVersion = '1.24.11911.0',
    # rcedit release used to embed the icon
    [string]$RceditVersion = '2.0.0',
    # overwrite an existing settings.json of the terminal copy
    [switch]$Force,
    # skip the Start Menu entry
    [switch]$NoStartMenu
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor White }
function Ok($msg)   { Write-Host "    + $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

function Download($url, $dest) {
    $tmp = "$dest.download"
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers @{ 'User-Agent' = 'sheepdock (+https://github.com/ralfkuh-lab/sheepdock)' }
    Move-Item -Force $tmp $dest
}

function Sha256($path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() }

function JsonPath($p) { $p -replace '\\', '\\' }

function Find-Python {
    foreach ($name in 'python', 'python3', 'py') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        # The Microsoft Store placeholder is on PATH even when Python is not installed.
        if ($cmd.Source -like '*\WindowsApps\*') { continue }
        try {
            $v = & $cmd.Source --version 2>&1
            if ($LASTEXITCODE -eq 0 -and "$v" -match 'Python 3') { return $cmd.Source }
        } catch { }
    }
    return $null
}

if ($env:OS -ne 'Windows_NT') { Die 'this script is for Windows. On macOS use ./install.sh.' }

$termDir = Join-Path $Prefix 'terminal'
$exe = Join-Path $termDir 'WindowsTerminal.exe'
$settingsDir = Join-Path $termDir 'settings'
$settings = Join-Path $settingsDir 'settings.json'

# --- locate herdr -------------------------------------------------------------
Step 'Locating herdr'
$herdr = $null
$cmd = Get-Command herdr -ErrorAction SilentlyContinue
if ($cmd) { $herdr = $cmd.Source }
if (-not $herdr) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
    if (Test-Path $candidate) { $herdr = $candidate }
}
if (-not $herdr) { Die 'herdr not found. Install it first:  irm https://herdr.dev/install.ps1 | iex' }
Ok $herdr

# --- nothing of ours may be running --------------------------------------------
if (Get-Process -Name 'WindowsTerminal' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) {
    Die 'the herdr window is open. Close it first, then re-run.'
}

# --- Windows Terminal, unpackaged ---------------------------------------------
Step "Fetching Windows Terminal $TerminalVersion (unpackaged)"
New-Item -ItemType Directory -Force -Path $Prefix, (Join-Path $Prefix 'tools') | Out-Null
$zip = Join-Path $env:TEMP "sheepdock-terminal-$TerminalVersion.zip"
Download "https://github.com/microsoft/terminal/releases/download/v$TerminalVersion/Microsoft.WindowsTerminal_${TerminalVersion}_x64.zip" $zip
Ok "sha256 $(Sha256 $zip)"

# Keep the settings folder across upgrades; everything else is replaced.
$keep = $null
if (Test-Path $settingsDir) {
    $keep = Join-Path $env:TEMP "sheepdock-settings-$PID"
    if (Test-Path $keep) { Remove-Item -Recurse -Force $keep }
    Move-Item $settingsDir $keep
}
if (Test-Path $termDir) { Remove-Item -Recurse -Force $termDir }
$extract = Join-Path $env:TEMP "sheepdock-extract-$PID"
if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
Expand-Archive -Path $zip -DestinationPath $extract
$inner = Get-ChildItem $extract -Directory | Select-Object -First 1
Move-Item $inner.FullName $termDir
Remove-Item -Recurse -Force $extract
if ($keep) { Move-Item $keep $settingsDir }
# An empty ".portable" file next to the exe switches Windows Terminal to portable
# mode: settings and state live in .\settings, nothing touches %LOCALAPPDATA%.
New-Item -ItemType File -Force -Path (Join-Path $termDir '.portable') | Out-Null
New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
Ok "$termDir (portable mode)"

# --- rcedit ------------------------------------------------------------------
$rcedit = Join-Path $Prefix 'tools\rcedit-x64.exe'
if (-not (Test-Path $rcedit)) {
    Step "Fetching rcedit $RceditVersion"
    Download "https://github.com/electron/rcedit/releases/download/v$RceditVersion/rcedit-x64.exe" $rcedit
    Ok "sha256 $(Sha256 $rcedit)"
}

# --- icon --------------------------------------------------------------------
Step 'Building the icon'
$ico = Join-Path $Prefix 'herdr.ico'
$makeIcon = Join-Path $Repo 'tools\make-icon.py'
$built = $false
$python = Find-Python
if ($python) {
    & $python $makeIcon --source $Icon --out $ico
    if ($LASTEXITCODE -eq 0) { $built = $true }
    elseif ($LASTEXITCODE -eq 3 -and (Get-Command uv -ErrorAction SilentlyContinue)) {
        Warn 'Pillow missing - retrying through uv'
        & uv run --quiet --with pillow python $makeIcon --source $Icon --out $ico
        if ($LASTEXITCODE -eq 0) { $built = $true }
    }
} else {
    Warn 'no Python 3 found'
}
if (-not $built) {
    Warn 'falling back to herdr.dev/favicon.ico (32 px, looks soft in the taskbar)'
    Warn 'for the full-size icon install Python 3 with Pillow and re-run'
    Download 'https://herdr.dev/favicon.ico' $ico
}
Ok $ico

# --- brand the exe -----------------------------------------------------------
Step 'Embedding the icon into WindowsTerminal.exe'
& $rcedit $exe --set-icon $ico `
    --set-version-string ProductName 'herdr' `
    --set-version-string FileDescription 'herdr'
if ($LASTEXITCODE -ne 0) { Die "rcedit failed (exit $LASTEXITCODE)" }
Ok 'icon and version strings set'

# --- settings ----------------------------------------------------------------
Step 'Installing the terminal settings'
if ((Test-Path $settings) -and -not $Force) {
    Warn "$settings exists - keeping it (use -Force to replace)"
} else {
    Add-Type -AssemblyName System.Drawing
    $fonts = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object Name
    # Prefer a Nerd Font when installed (herdr and the agent CLIs use its glyphs),
    # else the Cascadia Mono that ships with Windows Terminal itself.
    $font = 'Cascadia Mono'
    if ($fonts -contains 'JetBrainsMono NFM') { $font = 'JetBrainsMono NFM' }

    $template = Get-Content -Raw (Join-Path $Repo 'src\settings.json')
    $rendered = $template.Replace('{{HERDR}}', (JsonPath $herdr)).Replace('{{ICON}}', (JsonPath $ico)).Replace('{{FONT}}', $font)
    Set-Content -Path $settings -Value $rendered -Encoding UTF8 -NoNewline
    Ok "$settings (font: $font)"
}

# --- launcher script ---------------------------------------------------------
Step 'Installing the launcher script'
$launcher = Join-Path $Prefix 'herdr-launch.ps1'
$template = Get-Content -Raw (Join-Path $Repo 'src\herdr-launch.ps1')
Set-Content -Path $launcher -Value ($template.Replace('{{EXE}}', $exe).Replace('{{HERDR}}', $herdr)) -Encoding UTF8 -NoNewline
Ok $launcher

# --- shortcuts ---------------------------------------------------------------
Step 'Creating shortcuts'
$shell = New-Object -ComObject WScript.Shell
$targets = @((Join-Path $Prefix 'herdr.lnk'))
if (-not $NoStartMenu) {
    $targets += Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\herdr.lnk'
}
foreach ($lnk in $targets) {
    $s = $shell.CreateShortcut($lnk)
    $s.TargetPath = $exe
    $s.Arguments = ''
    $s.WorkingDirectory = $HOME
    $s.IconLocation = "$exe,0"
    $s.Description = 'herdr - terminal workspace for AI coding agents'
    $s.Save()
    Ok $lnk
}

# --- leftovers from the Alacritty-based launcher (sheepdock before 2026-09) -----
$legacyExe = Join-Path $Prefix 'herdr-terminal.exe'
$legacyConfig = Join-Path $env:APPDATA 'sheepdock'
if ((Test-Path $legacyExe) -or (Test-Path $legacyConfig)) {
    Step 'Removing the old Alacritty-based launcher'
    if (Test-Path $legacyExe) {
        if (Get-Process -Name 'herdr-terminal' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $legacyExe }) {
            Warn "$legacyExe is still running - close that window and delete the file, or re-run install.ps1"
        } else {
            Remove-Item -Force $legacyExe
            Ok "removed $legacyExe"
        }
    }
    if (Test-Path $legacyConfig) {
        Remove-Item -Recurse -Force $legacyConfig
        Ok "removed $legacyConfig"
    }
}

Step 'Done'
Write-Host '    Start herdr from the Start Menu, or run:'
Write-Host "        & `"$launcher`""
Write-Host ''
Write-Host '    To pin it: start herdr, right-click its taskbar button, choose "Pin to taskbar".'
Write-Host '    (Or right-click the Start Menu entry.) If an older herdr pin is still there,'
Write-Host '    unpin it first - it points at the removed launcher.'
