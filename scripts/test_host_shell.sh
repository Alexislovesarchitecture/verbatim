#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="$(uname -s)"

case "$platform" in
  Darwin)
    "$repo_root/scripts/build_rust_core.sh"
    cd "$repo_root/Shells/macOS"
    swift test
    ;;
  Linux)
    cargo test --manifest-path "$repo_root/Shells/linux/Cargo.toml" "$@"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    pwsh -File "$repo_root/Shells/windows/scripts/test.ps1" "$@"
    ;;
  *)
    echo "Unsupported host platform: $platform" >&2
    exit 1
    ;;
esac
