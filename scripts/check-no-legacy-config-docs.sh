#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if rg -n '\.magic-cli/settings\.json|ARK_API_KEY' README.md docs; then
  echo "legacy config doc entrypoints found"
  exit 1
fi

echo "legacy config doc entrypoints check passed"
