param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardedArgs
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$Project = Join-Path $RepoRoot "Shells\windows\Verbatim.Windows\Verbatim.Windows.csproj"
$TargetFramework = "net8.0-windows10.0.19041.0"
$Configuration = "Debug"

& cargo build --manifest-path (Join-Path $RepoRoot "RustCore\Cargo.toml") -p verbatim_core_ffi
& dotnet build $Project -c $Configuration @ForwardedArgs

$AppOutput = Join-Path $RepoRoot "Shells\windows\Verbatim.Windows\bin\$Configuration\$TargetFramework"
$RustTarget = Join-Path $RepoRoot "RustCore\target\debug"
$RustBinary = Join-Path $RustTarget "verbatim_core_ffi.dll"
$RustPdb = Join-Path $RustTarget "verbatim_core_ffi.pdb"

if (-not (Test-Path $RustBinary)) {
    throw "Missing Rust bridge output: $RustBinary"
}

Copy-Item $RustBinary (Join-Path $AppOutput "verbatim_core_ffi.dll") -Force
if (Test-Path $RustPdb) {
    Copy-Item $RustPdb (Join-Path $AppOutput "verbatim_core_ffi.pdb") -Force
}
