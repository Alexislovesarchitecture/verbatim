param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

$ErrorActionPreference = "Stop"
$windowsFlag = Get-Variable IsWindows -ErrorAction SilentlyContinue
$isWindowsHost = ($env:OS -eq "Windows_NT") -or ($windowsFlag -and $windowsFlag.Value)
if (-not $isWindowsHost) {
    throw "build_host_shell.ps1 is intended for Windows hosts. Use scripts/build_host_shell.sh on macOS or Linux."
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
& (Join-Path $RepoRoot "Shells\windows\scripts\build.ps1") @ForwardedArgs
