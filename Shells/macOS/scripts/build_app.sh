#!/usr/bin/env bash
set -euo pipefail

shell_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$shell_root/../.." && pwd)"
cd "$shell_root"

app_name="Verbatim"
bundle_id="AVA.VERBATIM-SWIFTPM-DEV"
dist_root="$repo_root/dist"
app_bundle="$dist_root/${app_name}.app"
bin_path="$(swift build --show-bin-path)"

reset_permissions=0

for arg in "$@"; do
  case "$arg" in
    --reset-permissions)
      reset_permissions=1
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: ./scripts/build_app.sh [--reset-permissions]" >&2
      exit 64
      ;;
  esac
done

"$repo_root/scripts/build_rust_core.sh" || true
swift build

python3 - <<PY
import glob, os, shutil
path = r"""$app_bundle"""
if os.path.exists(path):
    shutil.rmtree(path)
for legacy in glob.glob(r"""$dist_root/${app_name}.app.prev-*"""):
    if os.path.exists(legacy):
        shutil.rmtree(legacy)
for legacy in (r"""/tmp/${app_name}.app""", r"""/tmp/${app_name}-dev.app"""):
    if os.path.exists(legacy):
        shutil.rmtree(legacy)
PY
mkdir -p \
  "$dist_root" \
  "$app_bundle/Contents/MacOS" \
  "$app_bundle/Contents/Frameworks" \
  "$app_bundle/Contents/Resources"

ditto --noextattr --noqtn "$bin_path/$app_name" "$app_bundle/Contents/MacOS/$app_name"

while IFS= read -r bundle; do
  ditto --noextattr --noqtn "$bundle" "$app_bundle/Contents/Resources/$(basename "$bundle")"
done < <(find "$bin_path" -maxdepth 1 -type d -name "*.bundle" | sort)

while IFS= read -r framework; do
  ditto --noextattr --noqtn "$framework" "$app_bundle/Contents/Frameworks/$(basename "$framework")"
done < <(find "$bin_path" -maxdepth 1 -type d -name "*.framework" | sort)

install_name_tool -add_rpath "@executable_path/../Frameworks" "$app_bundle/Contents/MacOS/$app_name"

cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Verbatim</string>
  <key>CFBundleIdentifier</key>
  <string>AVA.VERBATIM-SWIFTPM-DEV</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Verbatim</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Verbatim uses the microphone to record audio for transcription.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Verbatim uses speech recognition to transcribe audio locally on device.</string>
</dict>
</plist>
PLIST

chmod -R u+w "$app_bundle"
xattr -cr "$app_bundle"
/usr/bin/codesign --force --deep --sign - "$app_bundle" >/dev/null

if [[ "$reset_permissions" == "1" ]]; then
  tccutil reset Accessibility "$bundle_id" || true
  tccutil reset Microphone "$bundle_id" || true
  tccutil reset SpeechRecognition "$bundle_id" || true
fi

python3 - <<PY
import os, shutil
for path in (
    r"""$repo_root/.build""",
    r"""$repo_root/build""",
    r"""$repo_root/RustCore/target""",
    r"""$repo_root/RustCore/dist""",
    r"""$repo_root/Shells/linux/target""",
    r"""$repo_root/.swiftpm/xcode/package.xcworkspace/xcuserdata""",
):
    if os.path.exists(path):
        shutil.rmtree(path)
PY

echo "Built app bundle at: $app_bundle"
