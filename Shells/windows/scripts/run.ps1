param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$Project = Join-Path $RepoRoot "Shells\windows\Verbatim.Windows\Verbatim.Windows.csproj"

& (Join-Path $PSScriptRoot "build.ps1")
& dotnet run --project $Project --no-build @ForwardedArgs
