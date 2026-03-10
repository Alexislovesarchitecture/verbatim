#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_app="$repo_root/tmp/Verbatim-dev.app"
target_dir="${HOME}/Applications"
target_app="${target_dir}/Verbatim Dev.app"

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
      echo "Usage: ./scripts/install_dev_app.sh [--reset-permissions] [--no-open]" >&2
      exit 64
      ;;
  esac
done

build_args=(--no-open)
if [[ "$reset_permissions" == "1" ]]; then
  build_args+=(--reset-permissions)
fi

"$repo_root/scripts/run_dev_app.sh" "${build_args[@]}"

mkdir -p "$target_dir"
rm -rf "$target_app"
ditto --noextattr --noqtn "$source_app" "$target_app"
chmod -R u+w "$target_app"
xattr -cr "$target_app"
/usr/bin/codesign --force --deep --sign - "$target_app" >/dev/null

echo "Installed dev app at: $target_app"

if [[ "$open_app" == "1" ]]; then
  open "$target_app"
fi
