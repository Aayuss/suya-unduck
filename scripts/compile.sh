#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
configuration=${1:-release}
bin="$PWD/.build/direct-$configuration"
mkdir -p "$bin" "$CLANG_MODULE_CACHE_PATH"
lock="$PWD/.build/compile-$configuration.lock"
mkdir "$lock" 2>/dev/null || { echo "A $configuration build is already running ($lock)" >&2; exit 1; }
trap 'rmdir "$lock"' EXIT
flags=(-swift-version 5 -sdk "$SDKROOT" -target arm64-apple-macosx14.2 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I Sources/CAtomics/include -I "$bin")
cflags=(-isysroot "$SDKROOT" -target arm64-apple-macosx14.2 -I Sources/CAtomics/include)
if [ "$configuration" = tsan ]; then flags+=(-sanitize=thread -g); cflags+=(-fsanitize=thread -g); else flags+=(-O); cflags+=(-O2); fi
clang "${cflags[@]}" -c Sources/CAtomics/CAtomics.c -o "$bin/CAtomics.o"
swiftc "${flags[@]}" -parse-as-library -emit-library -static -emit-module -module-name MixerCore Sources/MixerCore/*.swift -o "$bin/libMixerCore.a" -emit-module-path "$bin/MixerCore.swiftmodule"
swiftc "${flags[@]}" -parse-as-library -emit-library -static -emit-module -module-name MixerEngine Sources/MixerEngine/*.swift -o "$bin/libMixerEngine.a" -emit-module-path "$bin/MixerEngine.swiftmodule"
libs=(-L "$bin" -lMixerEngine -lMixerCore "$bin/CAtomics.o" -framework CoreAudio -framework AudioToolbox -framework AppKit)
for pair in 'SuyaUnduck:suya-unduck' 'SuyaUnduckLab:suya-unduck-lab' 'SuyaUnduckSelfTest:suya-unduck-selftest'; do
  target=${pair%%:*}; name=${pair#*:}
  swiftc "${flags[@]}" Sources/"$target"/*.swift "${libs[@]}" -framework SwiftUI -framework ServiceManagement -o "$bin/$name"
done
printf 'Built %s\n' "$bin"
