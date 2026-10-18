#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh
ditto dist/suya-unduck.app /Applications/suya-unduck.app
open /Applications/suya-unduck.app
