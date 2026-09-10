# sheepdock for Windows - build and install herdr-terminal.exe, a launcher that
# opens herdr in its own Alacritty window with its own taskbar icon.
#
# No admin rights needed: everything lands under %LOCALAPPDATA% and %APPDATA%.
#
#   .\install.ps1 [-Prefix DIR] [-ConfigDir DIR] [-Icon SRC]
#                 [-AlacrittyVersion X.Y.Z] [-Force] [-NoStartMenu]
#
#Requires -Version 5.1
[CmdletBinding()]
param(
    # where herdr-terminal.exe, the icon and the launcher script go
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\sheepdock'),
    # where the Alacritty profile for this window lives
    [string]$ConfigDir = (Join-Path $env:APPDATA 'sheepdock'),
    # logo URL or image path
    [string]$Icon = 'https://herdr.dev/assets/logo.png',
    # Alacritty release to download (portable build, single exe)
    [string]$AlacrittyVersion = '0.17.0',
    # rcedit release used to embed the icon
    [string]$RceditVersion = '2.0.0',
    # overwrite an existing alacritty.toml in the config directory
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

# --- Alacritty portable ------------------------------------------------------
Step "Fetching Alacritty $AlacrittyVersion (portable)"
New-Item -ItemType Directory -Force -Path $Prefix, (Join-Path $Prefix 'tools') | Out-Null
$exe = Join-Path $Prefix 'herdr-terminal.exe'
if (Get-Process -Name 'herdr-terminal' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) {
    Die 'herdr-terminal.exe is running. Close the herdr window first, then re-run.'
}
$alacrittyUrl = "https://github.com/alacritty/alacritty/releases/download/v$AlacrittyVersion/Alacritty-v$AlacrittyVersion-portable.exe"
Download $alacrittyUrl $exe
Ok "$exe"
Ok "sha256 $(Sha256 $exe)"

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
Step 'Embedding the icon into herdr-terminal.exe'
& $rcedit $exe --set-icon $ico `
    --set-version-string ProductName 'herdr' `
    --set-version-string FileDescription 'herdr' `
    --set-version-string OriginalFilename 'herdr-terminal.exe'
if ($LASTEXITCODE -ne 0) { Die "rcedit failed (exit $LASTEXITCODE)" }
Ok 'icon and version strings set'

# --- Alacritty profile -------------------------------------------------------
Step 'Installing the Alacritty profile'
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
$config = Join-Path $ConfigDir 'alacritty.toml'
if ((Test-Path $config) -and -not $Force) {
    Warn "$config exists - keeping it (use -Force to replace)"
} else {
    Add-Type -AssemblyName System.Drawing
    $fonts = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object Name
    $font = if ($fonts -contains 'Cascadia Mono') { 'Cascadia Mono' } else { 'Consolas' }

    # Inherit the user's own Alacritty config when there is one, so colours and
    # keybindings carry over. Alacritty errors on a missing import, hence the check.
    $userConfig = Join-Path $env:APPDATA 'alacritty\alacritty.toml'
    $import = ''
    if (Test-Path $userConfig) {
        $import = "[general]`nimport = [`"$($userConfig -replace '\\', '/')`"]`n"
        Ok "importing $userConfig"
    }

    $template = Get-Content -Raw (Join-Path $Repo 'src\alacritty.toml')
    $rendered = $template.Replace('{{IMPORT}}', $import).Replace('{{FONT}}', $font).Replace('{{HERDR}}', ($herdr -replace '\\', '/'))
    Set-Content -Path $config -Value $rendered -Encoding UTF8 -NoNewline
    Ok "$config (font: $font)"
}

# --- launcher script ---------------------------------------------------------
Step 'Installing the launcher script'
$launcher = Join-Path $Prefix 'herdr-launch.ps1'
$template = Get-Content -Raw (Join-Path $Repo 'src\herdr-launch.ps1')
Set-Content -Path $launcher -Value ($template.Replace('{{CONFIG}}', $config).Replace('{{HERDR}}', $herdr)) -Encoding UTF8 -NoNewline
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
    $s.Arguments = "--config-file `"$config`""
    $s.WorkingDirectory = $HOME
    $s.IconLocation = "$exe,0"
    $s.Description = 'herdr - terminal workspace for AI coding agents'
    $s.Save()
    Ok $lnk
}

Step 'Done'
Write-Host '    Start herdr from the Start Menu, or run:'
Write-Host "        & `"$launcher`""
Write-Host ''
Write-Host '    To pin it: open the Start Menu, right-click "herdr", choose "Pin to taskbar".'
Write-Host '    Pin the Start Menu entry, not a running window - a pinned window loses the'
Write-Host '    --config-file argument and would open a plain Alacritty next time.'
