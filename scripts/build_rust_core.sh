#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate_root="$repo_root/RustCore"
runtime_root="$repo_root/Verbatim/RustRuntime"
profile="debug"
profile_flag=""

if [[ "${1:-}" == "--release" ]]; then
  profile="release"
  profile_flag="--release"
fi

mkdir -p "$runtime_root"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found; skipping Rust core build" >&2
  exit 0
fi

cargo build --manifest-path "$crate_root/Cargo.toml" -p verbatim_core_ffi $profile_flag

dylib_path="$crate_root/target/$profile/libverbatim_core.dylib"
if [[ -f "$dylib_path" ]]; then
  cp "$dylib_path" "$runtime_root/libverbatim_core.dylib"
  chmod u+w "$runtime_root/libverbatim_core.dylib"
  xattr -cr "$runtime_root/libverbatim_core.dylib" 2>/dev/null || true
fi
