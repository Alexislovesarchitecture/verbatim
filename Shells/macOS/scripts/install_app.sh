#!/usr/bin/env bash
set -euo pipefail

shell_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$shell_root/../.." && pwd)"
cd "$shell_root"

source_app="$repo_root/dist/Verbatim.app"
target_dir="${HOME}/Applications"
target_app="${target_dir}/Verbatim.app"
legacy_target_app="${target_dir}/Verbatim Dev.app"

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
      echo "Usage: ./scripts/install_app.sh [--reset-permissions] [--no-open]" >&2
      exit 64
      ;;
  esac
done

build_args=()
if [[ "$reset_permissions" == "1" ]]; then
  build_args+=(--reset-permissions)
fi

if [[ "$reset_permissions" == "1" ]]; then
  "$shell_root/scripts/build_app.sh" --reset-permissions
else
  "$shell_root/scripts/build_app.sh"
fi

mkdir -p "$target_dir"
python3 - <<PY
import os, shutil
path = r"""$target_app"""
if os.path.exists(path):
    shutil.rmtree(path)
legacy = r"""$legacy_target_app"""
if os.path.exists(legacy):
    shutil.rmtree(legacy)
PY
ditto --noextattr --noqtn "$source_app" "$target_app"
chmod -R u+w "$target_app"
xattr -cr "$target_app"
/usr/bin/codesign --force --deep --sign - "$target_app" >/dev/null

echo "Installed app at: $target_app"

if [[ "$open_app" == "1" ]]; then
  open "$target_app"
fi
