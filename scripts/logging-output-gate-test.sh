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
  "$TMP_ROOT/src/gateway/config" \
  "$TMP_ROOT/src/gateway/runtime" \
  "$TMP_ROOT/src/gateway/channels/feishu" \
  "$TMP_ROOT/src/gateway/channels/qq" \
  "$TMP_ROOT/src/gateway/logging" \
  "$TMP_ROOT/src/gateway/tools" \
  "$TMP_ROOT/scripts"

cat > "$TMP_ROOT/src/gateway/core/gateway_service.cj" <<'FIXTURE'
func fixtureStructured() {
    gatewayLogEventInfo("gateway", "gateway.ready", "structured log")
}
FIXTURE

cat > "$TMP_ROOT/scripts/feishu-ws-sidecar.mjs" <<'FIXTURE'
process.stdout.write(`${JSON.stringify({ ok: true })}\n`);
process.stderr.write("[feishu-monitor] ok\n");
FIXTURE

cat > "$TMP_ROOT/src/gateway/runtime/gateway_cli.cj" <<'FIXTURE'
func fixtureJsonMode(res: GatewayProtocolResponse) {
    PrintUtils.printLine(res.toJson().toJsonString())
}
FIXTURE

cat > "$TMP_ROOT/scripts/openclaw-compat-capabilities.mjs" <<'FIXTURE'
process.stdout.write(`${JSON.stringify({ ok: true })}\n`);
FIXTURE

"$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/pass.out"
rg -q "logging-output-gate: passed" "$TMP_ROOT/pass.out"
rg -q "Gateway LogUtils: allowed=0 disallowed=0" "$TMP_ROOT/pass.out"
rg -q "Gateway direct toJsonString output: allowed=1 disallowed=0" "$TMP_ROOT/pass.out"
rg -q "JS stdout protocol/report: allowed=2 disallowed=0" "$TMP_ROOT/pass.out"

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
cat > "$TMP_ROOT/src/gateway/config/new_config_output.cj" <<'FIXTURE'
func fixtureDisallowedConfigLog() {
    LogUtils.info("config package legacy log")
}
FIXTURE

if "$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/fail-config.out" 2>&1; then
  echo "logging-output-gate-test: expected gate failure for disallowed config LogUtils" >&2
  exit 1
fi
rg -q "new_config_output.cj" "$TMP_ROOT/fail-config.out"

rm "$TMP_ROOT/src/gateway/config/new_config_output.cj"
cat > "$TMP_ROOT/src/gateway/channels/qq/qq_adapter.cj" <<'FIXTURE'
func fixtureDisallowedPrint() {
    PrintUtils.printLine("runtime adapter shell output")
}
FIXTURE

if "$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/fail-printutils.out" 2>&1; then
  echo "logging-output-gate-test: expected gate failure for disallowed PrintUtils.printLine" >&2
  exit 1
fi
rg -q "Gateway PrintUtils.printLine" "$TMP_ROOT/fail-printutils.out"
rg -q "qq_adapter.cj" "$TMP_ROOT/fail-printutils.out"

rm "$TMP_ROOT/src/gateway/channels/qq/qq_adapter.cj"
cat > "$TMP_ROOT/src/gateway/tools/raw_tool_output.cj" <<'FIXTURE'
func fixtureDisallowedToolResult(res: GatewayProtocolResponse) {
    PrintUtils.printToolResult(res.toJson().toJsonString())
}
FIXTURE

if "$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/fail-tool-json.out" 2>&1; then
  echo "logging-output-gate-test: expected gate failure for disallowed tool raw JSON output" >&2
  exit 1
fi
rg -q "Gateway direct toJsonString output" "$TMP_ROOT/fail-tool-json.out"
rg -q "raw_tool_output.cj" "$TMP_ROOT/fail-tool-json.out"

rm "$TMP_ROOT/src/gateway/tools/raw_tool_output.cj"
cat > "$TMP_ROOT/scripts/new-sidecar.mjs" <<'FIXTURE'
process.stdout.write("human text\n");
FIXTURE

if "$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/fail-sidecar.out" 2>&1; then
  echo "logging-output-gate-test: expected gate failure for disallowed sidecar stdout" >&2
  exit 1
fi
rg -q "new-sidecar.mjs" "$TMP_ROOT/fail-sidecar.out"

rm "$TMP_ROOT/scripts/new-sidecar.mjs"
cat > "$TMP_ROOT/scripts/new-runtime-sidecar.mjs" <<'FIXTURE'
console.log("diagnostic on protocol stdout");
FIXTURE

if "$GATE" --root "$TMP_ROOT" > "$TMP_ROOT/fail-console.out" 2>&1; then
  echo "logging-output-gate-test: expected gate failure for disallowed sidecar console usage" >&2
  exit 1
fi
rg -q "JS console usage" "$TMP_ROOT/fail-console.out"
rg -q "new-runtime-sidecar.mjs" "$TMP_ROOT/fail-console.out"

echo "logging-output-gate-test: passed"
