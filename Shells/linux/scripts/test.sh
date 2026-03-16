#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "Linux shell tests require pkg-config on the host environment." >&2
  echo "Install pkgconf/pkg-config first, then rerun this script." >&2
  exit 1
fi

if ! pkg-config --exists gtk4 libadwaita-1; then
  echo "Linux shell tests require GTK4 and libadwaita development packages." >&2
  echo "On Ubuntu/Debian install: sudo apt-get install -y pkg-config libgtk-4-dev libadwaita-1-dev libasound2-dev" >&2
  exit 1
fi

cargo test --manifest-path "$repo_root/Shells/linux/Cargo.toml" "$@"
