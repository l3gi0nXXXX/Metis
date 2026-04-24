#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"

if rg -n \
  --glob 'README.md' \
  --glob 'docs/**' \
  --glob 'scripts/**' \
  --glob '.gitignore' \
  --glob '!scripts/check-no-dotenv-entrypoints.sh' \
  --glob '!magic-data-backend/**' \
  --glob '!tools/feishu-official-sdk/node_modules/**' \
  '创建 `?\.env|create `.env|参考项目根目录下 `.env|项目根目录创建 `.env|^\| `.env` \||ohos\\\.env' \
  .; then
  echo "Found forbidden .env entrypoints in repo-owned docs/scripts."
  exit 1
fi

echo "No repo-owned .env entrypoints found."
