param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$Project = Join-Path $RepoRoot "Shells\windows\Verbatim.Windows\Verbatim.Windows.csproj"

& cargo test --manifest-path (Join-Path $RepoRoot "RustCore\Cargo.toml")
& dotnet build $Project @ForwardedArgs
