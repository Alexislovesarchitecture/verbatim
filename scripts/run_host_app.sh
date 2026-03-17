#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="$(uname -s)"

case "$platform" in
  Darwin)
    exec "$repo_root/Shells/macOS/scripts/run_app.sh" "$@"
    ;;
  Linux)
    cargo run --manifest-path "$repo_root/Shells/linux/Cargo.toml" "$@"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    pwsh -File "$repo_root/Shells/windows/scripts/run.ps1" "$@"
    ;;
  *)
    echo "Unsupported host platform: $platform" >&2
    exit 1
    ;;
esac
