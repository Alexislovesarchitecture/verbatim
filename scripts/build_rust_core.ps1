param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CrateRoot = Join-Path $RepoRoot "RustCore"
$DistRoot = Join-Path $CrateRoot "dist"
$Profile = if ($Release) { "release" } else { "debug" }
$CargoArgs = @("build", "--manifest-path", (Join-Path $CrateRoot "Cargo.toml"), "-p", "verbatim_core_ffi")

if ($Release) {
    $CargoArgs += "--release"
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "cargo was not found on PATH. Install Rust or add cargo to PATH before building the shared Verbatim core."
}

New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null

& cargo @CargoArgs

$TargetRoot = Join-Path $CrateRoot "target\$Profile"
$RustBinary = Join-Path $TargetRoot "verbatim_core_ffi.dll"
$RustPdb = Join-Path $TargetRoot "verbatim_core_ffi.pdb"
$HeaderPath = Join-Path $CrateRoot "include\verbatim_core.h"

if (-not (Test-Path $RustBinary)) {
    throw "Missing Rust bridge output: $RustBinary"
}

Copy-Item $RustBinary (Join-Path $DistRoot "verbatim_core_ffi.dll") -Force
if (Test-Path $RustPdb) {
    Copy-Item $RustPdb (Join-Path $DistRoot "verbatim_core_ffi.pdb") -Force
}
if (Test-Path $HeaderPath) {
    Copy-Item $HeaderPath (Join-Path $DistRoot "verbatim_core.h") -Force
}
