#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_PROMPT="$(mktemp /tmp/metis-tool-prompt.XXXXXX.txt)"

cleanup() {
  rm -f "$TMP_PROMPT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_cli() {
  rtk cjpm run --skip-script --skip-build --name metis --run-args "$*"
}

with_metis_cjpm_build_lock rtk cjpm build -i
printf '%s\n' 'Reply with exactly one line: ping' >"$TMP_PROMPT"

run_cli "--version"
run_cli "--prompt-file $TMP_PROMPT"
run_cli "gateway status"
run_cli "gateway cron path"
run_cli "gateway cron list"
