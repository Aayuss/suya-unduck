#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/compile.sh
printf 'Run .build/direct-release/suya-unduck-lab help\n'
