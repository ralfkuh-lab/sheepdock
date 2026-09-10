# sheepdock - start herdr in its own window from a shell.
#
# The taskbar shortcut points at the private WindowsTerminal.exe directly; this
# script is for launching from a terminal, a herdr pane or another script. It
# drops the HERDR_* variables a pane would hand down (herdr refuses to start
# "nested" when it sees them, and a new window is not nesting) and passes any
# arguments on to herdr, e.g.
#
#   herdr-launch.ps1 --session scratch
#
# Placeholders in {{...}} are filled in by install.ps1.
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$HerdrArgs
)

$exe = '{{EXE}}'
$herdr = '{{HERDR}}'

if (-not (Test-Path $exe)) {
    Write-Error "The herdr terminal is missing at $exe. Re-run install.ps1."
    exit 1
}

Get-ChildItem Env: | Where-Object { $_.Name -like 'HERDR_*' } | ForEach-Object {
    Remove-Item -Path "Env:$($_.Name)" -ErrorAction SilentlyContinue
}

if ($HerdrArgs) {
    # Windows Terminal command line: open the herdr profile, but run herdr with these arguments.
    $argList = @('new-tab', '-p', 'herdr', $herdr) + $HerdrArgs
    Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $HOME
} else {
    Start-Process -FilePath $exe -WorkingDirectory $HOME
}
