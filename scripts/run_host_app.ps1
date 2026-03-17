param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

$ErrorActionPreference = "Stop"
$windowsFlag = Get-Variable IsWindows -ErrorAction SilentlyContinue
$isWindowsHost = ($env:OS -eq "Windows_NT") -or ($windowsFlag -and $windowsFlag.Value)
if (-not $isWindowsHost) {
    throw "run_host_app.ps1 is intended for Windows hosts. Use scripts/run_host_app.sh on macOS or Linux."
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $RepoRoot "Shells\windows\scripts\run.ps1") @ForwardedArgs
