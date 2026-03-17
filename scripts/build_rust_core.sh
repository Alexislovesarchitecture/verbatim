#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate_root="$repo_root/RustCore"
dist_root="$crate_root/dist"
macos_runtime_root="$repo_root/Shells/macOS/Verbatim/RustRuntime"
profile="debug"
profile_flag=""

if [[ "${1:-}" == "--release" ]]; then
  profile="release"
  profile_flag="--release"
fi

mkdir -p "$dist_root" "$macos_runtime_root"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found; skipping Rust core build" >&2
  exit 0
fi

cargo build --manifest-path "$crate_root/Cargo.toml" -p verbatim_core_ffi $profile_flag

dylib_path="$crate_root/target/$profile/libverbatim_core_ffi.dylib"
if [[ -f "$dylib_path" ]]; then
  cp "$dylib_path" "$dist_root/libverbatim_core_ffi.dylib"
  cp "$dylib_path" "$macos_runtime_root/libverbatim_core_ffi.dylib"
  chmod u+w "$dist_root/libverbatim_core_ffi.dylib" "$macos_runtime_root/libverbatim_core_ffi.dylib"
  xattr -cr "$dist_root/libverbatim_core_ffi.dylib" "$macos_runtime_root/libverbatim_core_ffi.dylib" 2>/dev/null || true
fi

header_path="$crate_root/include/verbatim_core.h"
if [[ -f "$header_path" ]]; then
  cp "$header_path" "$dist_root/verbatim_core.h"
fi
