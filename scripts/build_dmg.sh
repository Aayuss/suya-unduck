#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh
stage=$(mktemp -d /tmp/suya-dmg.XXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto dist/suya-unduck.app "$stage/suya-unduck.app"
ln -s /Applications "$stage/Applications"
cp README.md "$stage/Read Me.md"
cp TESTING.md REPORT.md THIRD_PARTY_NOTICES.md "$stage/"
hdiutil create -volname suya-unduck -srcfolder "$stage" -ov -format UDZO dist/suya-unduck-0.2.0-arm64.dmg
(cd dist && shasum -a 256 suya-unduck-0.2.0-arm64.dmg > SHA256SUMS.txt)
