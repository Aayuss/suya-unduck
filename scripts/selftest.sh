#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/compile.sh
.build/direct-release/suya-unduck-selftest
./scripts/compile.sh tsan
.build/direct-tsan/suya-unduck-selftest
