#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if rg -n \
  --glob 'scripts/tool-smoke-check.sh' \
  --glob 'scripts/memory-regression.sh' \
  --glob 'scripts/subagent-smoke-check.sh' \
  --glob 'scripts/ohos-build/ohos_install.bat' \
  '\.magic-cli/' \
  scripts; then
  echo "Found forbidden legacy .magic-cli script paths."
  exit 1
fi

echo "No legacy .magic-cli script paths found."
