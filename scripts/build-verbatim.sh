#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Verbatim is a macOS app. Run this command on macOS."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required for this path."
  echo "Install with: brew install xcodegen"
  exit 1
fi

echo "Generating Verbatim.xcodeproj with xcodegen..."
xcodegen generate

if [[ ! -d "Verbatim.xcodeproj" ]]; then
  echo "xcodegen did not produce Verbatim.xcodeproj."
  exit 1
fi

open -a Xcode Verbatim.xcodeproj
