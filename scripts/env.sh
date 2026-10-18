#!/bin/bash
# Source from the repository root. Prefer the newest compatible numeric SDK.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
export SDKROOT="${SDKROOT:-}"
if [ -z "$SDKROOT" ]; then
  probe_dir=$(mktemp -d /tmp/suya-sdk.XXXXXX)
  probe="$probe_dir/probe.swift"
  printf 'import CoreAudio\nimport SwiftUI\n' > "$probe"
  for sdk in $(find /Library/Developer/CommandLineTools/SDKs /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs -maxdepth 1 -name 'MacOSX[0-9]*.sdk' 2>/dev/null | sort -rV); do
    if SDKROOT="$sdk" swiftc -typecheck "$probe" >/dev/null 2>&1; then export SDKROOT="$sdk"; break; fi
  done
  rm -f "$probe"
  rmdir "$probe_dir"
  [ -n "$SDKROOT" ] || { echo 'No compatible macOS SDK'; return 1; }
fi
printf 'Using SDKROOT=%s\n' "$SDKROOT"
