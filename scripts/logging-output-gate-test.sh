#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT_DIR/scripts/logging-output-gate.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/metis-logging-gate-test.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$TMP_ROOT/src/gateway/core" \
  "$TMP_ROOT/src/gateway/runtime" \
  "$TMP_ROOT/src/gateway/channels/feishu" \
  "$TMP_ROOT/scripts"

cat > "$TMP_ROOT/src/gateway/core/gateway_service.cj" <<'FIXTURE'
func fixtureAllowed() {
    LogUtils.info("legacy allowlist")
}
FIXTURE

cat > "$TMP_ROOT/scripts/feishu-ws-sidecar.mjs" <<'FIXTURE'
process.stdout.write(`${JSON.stringify({ ok: true })}\n`);
process.stderr.write("[feishu-monitor] ok\n");
FIXTURE

"$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/pass.out"
rg -q "logging-output-gate: passed" "$TMP_ROOT/pass.out"

cat > "$TMP_ROOT/src/gateway/core/new_runtime_output.cj" <<'FIXTURE'
func fixtureDisallowed() {
    LogUtils.info("new direct gateway log")
}
FIXTURE

if "$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/fail.out" 2>&1; then
  echo "logging-output-gate-test: expected gate failure for disallowed LogUtils" >&2
  exit 1
fi
rg -q "new_runtime_output.cj" "$TMP_ROOT/fail.out"

rm "$TMP_ROOT/src/gateway/core/new_runtime_output.cj"
cat > "$TMP_ROOT/scripts/new-sidecar.mjs" <<'FIXTURE'
process.stdout.write("human text\n");
FIXTURE

if "$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/fail-sidecar.out" 2>&1; then
  echo "logging-output-gate-test: expected gate failure for disallowed sidecar stdout" >&2
  exit 1
fi
rg -q "new-sidecar.mjs" "$TMP_ROOT/fail-sidecar.out"

echo "logging-output-gate-test: passed"
