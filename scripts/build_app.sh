#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
if [ "${SUYA_SKIP_COMPILE:-0}" != 1 ]; then ./scripts/compile.sh; fi
app="$PWD/dist/suya-unduck.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/AppIcon.iconset
cp .build/direct-release/suya-unduck "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/{MenuBarIcon.png,AppIcon.png} "$app/Contents/Resources/"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp TESTING.md "$app/Contents/Resources/"
cp .build/direct-release/suya-unduck-lab "$app/Contents/MacOS/"
sign="${SUYA_SIGN_IDENTITY:--}"
codesign --force --sign "$sign" "$app/Contents/MacOS/suya-unduck-lab"
codesign --force --options runtime --entitlements Resources/suya-unduck.entitlements --sign "$sign" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
