# sheepdock - start herdr in its own window from a shell.
#
# The taskbar shortcut points at herdr-terminal.exe directly; this script is
# for launching from a terminal, a herdr pane or another script. It drops the
# HERDR_* variables a pane would hand down (herdr refuses to start "nested"
# when it sees them, and a new window is not nesting) and passes any arguments
# on to herdr, e.g.
#
#   herdr-launch.ps1 --session scratch
#
# Placeholders in {{...}} are filled in by install.ps1.
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$HerdrArgs
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $here 'herdr-terminal.exe'
$config = '{{CONFIG}}'
$herdr = '{{HERDR}}'

if (-not (Test-Path $exe)) {
    Write-Error "herdr-terminal.exe is missing next to this script. Re-run install.ps1."
    exit 1
}

Get-ChildItem Env: | Where-Object { $_.Name -like 'HERDR_*' } | ForEach-Object {
    Remove-Item -Path "Env:$($_.Name)" -ErrorAction SilentlyContinue
}

$argList = @('--config-file', $config)
if ($HerdrArgs) {
    # Extra arguments mean "run herdr with these"; -e replaces the configured shell.
    $argList += @('-e', $herdr) + $HerdrArgs
}

Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $HOME
