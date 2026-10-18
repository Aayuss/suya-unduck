#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
if [ "${SUYA_SKIP_COMPILE:-0}" != 1 ]; then ./scripts/build_dmg.sh; fi
dmg="$PWD/dist/suya-unduck-0.2.0-arm64.dmg"
mount_dir=$(mktemp -d /tmp/suya-install.XXXXXX)
stage="/Applications/.suya-unduck-update-$$.app"
backup="$PWD/dist/local-evidence/installed-backups/$(date +%Y%m%d-%H%M%S)"
cleanup() { hdiutil detach "$mount_dir" >/dev/null 2>&1 || true; rmdir "$mount_dir" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mount_dir" >/dev/null
codesign --verify --deep --strict "$mount_dir/suya-unduck.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mount_dir/suya-unduck.app/Contents/Info.plist")" = 0.2.0 ]
ditto "$mount_dir/suya-unduck.app" "$stage"
codesign --verify --deep --strict "$stage"
swiftc -sdk "$SDKROOT" scripts/terminate_app.swift -o .build/suya-unduck-quit
.build/suya-unduck-quit
mkdir -p "$backup"
settings="$HOME/Library/Application Support/suya-unduck/settings.json"
if [ -f "$settings" ]; then cp "$settings" "$backup/settings.json"; fi
if [ -d /Applications/suya-unduck.app ]; then mv /Applications/suya-unduck.app "$backup/suya-unduck.app"; fi
if ! mv "$stage" /Applications/suya-unduck.app; then
    if [ -d "$backup/suya-unduck.app" ]; then mv "$backup/suya-unduck.app" /Applications/suya-unduck.app; fi
    exit 1
fi
codesign --verify --deep --strict /Applications/suya-unduck.app
cmp /Applications/suya-unduck.app/Contents/MacOS/suya-unduck "$mount_dir/suya-unduck.app/Contents/MacOS/suya-unduck"
open /Applications/suya-unduck.app --args --show
printf 'Installed and opened suya-unduck 0.2.0. Previous app/settings backed up locally.\n'
