#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="$(uname -s)"

case "$platform" in
  Darwin)
    exec "$repo_root/Shells/macOS/scripts/install_dev_app.sh" "$@"
    ;;
  Linux)
    echo "Linux install packaging is not automated yet. Build with scripts/build_host_shell.sh and package from Shells/linux." >&2
    exit 1
    ;;
  MINGW*|MSYS*|CYGWIN*)
    pwsh -File "$repo_root/Shells/windows/scripts/install.ps1" "$@"
    ;;
  *)
    echo "Unsupported host platform: $platform" >&2
    exit 1
    ;;
esac
