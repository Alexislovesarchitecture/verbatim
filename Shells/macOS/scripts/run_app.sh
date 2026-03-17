#!/usr/bin/env bash
set -euo pipefail

shell_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$shell_root/../.." && pwd)"
app_bundle="$repo_root/dist/Verbatim.app"

reset_permissions=0
open_app=1

for arg in "$@"; do
  case "$arg" in
    --reset-permissions)
      reset_permissions=1
      ;;
    --no-open)
      open_app=0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: ./scripts/run_app.sh [--reset-permissions] [--no-open]" >&2
      exit 64
      ;;
  esac
done

build_args=()
if [[ "$reset_permissions" == "1" ]]; then
  build_args+=(--reset-permissions)
fi

"$shell_root/scripts/build_app.sh" "${build_args[@]}"

if [[ "$open_app" == "1" ]]; then
  open "$app_bundle"
fi
