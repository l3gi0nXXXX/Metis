#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" = "--root" ]; then
  ROOT_DIR="$(cd "$2" && pwd)"
  shift 2
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "logging-output-gate: ripgrep (rg) is required" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/metis-logging-gate.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

failures=0

is_allowed_path() {
  path="$1"
  shift
  for allowed in "$@"; do
    case "$path" in
      $allowed) return 0 ;;
    esac
  done
  return 1
}

report_scan() {
  title="$1"
  pattern="$2"
  output_file="$3"
  shift 3
  : > "$output_file"
  rg -n "$pattern" "$@" > "$output_file" 2>/dev/null
  status=$?
  if [ "$status" -eq 1 ]; then
    : > "$output_file"
    return 0
  fi
  if [ "$status" -ne 0 ]; then
    echo "logging-output-gate: scan failed for ${title}" >&2
    exit "$status"
  fi
  return 0
}

check_file_allowlist() {
  title="$1"
  scan_file="$2"
  allowed_file="$3"
  shift 3
  : > "$allowed_file"
  disallowed_file="${allowed_file}.disallowed"
  : > "$disallowed_file"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line%%:*}"
    if is_allowed_path "$path" "$@"; then
      printf '%s\n' "$line" >> "$allowed_file"
    else
      printf '%s\n' "$line" >> "$disallowed_file"
    fi
  done < "$scan_file"

  allowed_count=$(wc -l < "$allowed_file" | tr -d ' ')
  disallowed_count=$(wc -l < "$disallowed_file" | tr -d ' ')
  echo "${title}: allowed=${allowed_count} disallowed=${disallowed_count}"
  if [ "$disallowed_count" -gt 0 ]; then
    echo "Disallowed ${title} output points:"
    sed -n '1,120p' "$disallowed_file"
    failures=$((failures + 1))
  fi
}

cd "$ROOT_DIR" || exit 2

logutils_scan="$TMP_DIR/logutils.txt"
direct_print_scan="$TMP_DIR/direct-print.txt"
sidecar_stdout_scan="$TMP_DIR/sidecar-stdout.txt"
sidecar_stderr_scan="$TMP_DIR/sidecar-stderr.txt"

report_scan \
  "gateway/channel LogUtils" \
  'LogUtils\.(trace|debug|info|error)' \
  "$logutils_scan" \
  -g '*.cj' src/gateway/core src/gateway/runtime src/gateway/channels

report_scan \
  "gateway/channel direct print" \
  '(^|[^A-Za-z0-9_])(println|print|eprintln)\(' \
  "$direct_print_scan" \
  -g '*.cj' src/gateway/core src/gateway/runtime src/gateway/channels

report_scan \
  "JS sidecar stdout" \
  'process\.stdout\.write' \
  "$sidecar_stdout_scan" \
  -g '*.mjs' scripts

report_scan \
  "JS sidecar stderr" \
  'process\.stderr\.write' \
  "$sidecar_stderr_scan" \
  -g '*.mjs' scripts

# Phase 0/8 legacy allowlist. These files are still direct-output owners until
# the Gateway logger facade and sidecar helper are landed. New files should not
# be added here without updating the internal logging plan.
check_file_allowlist \
  "gateway/channel LogUtils" \
  "$logutils_scan" \
  "$TMP_DIR/logutils.allowed" \
  "src/gateway/core/agent_bridge.cj" \
  "src/gateway/core/gateway_channel_manager.cj" \
  "src/gateway/core/gateway_cron_session_reaper.cj" \
  "src/gateway/core/gateway_process_memory.cj" \
  "src/gateway/core/gateway_service.cj" \
  "src/gateway/core/gateway_session_executor.cj" \
  "src/gateway/core/gateway_session_store.cj" \
  "src/gateway/runtime/cron_runner.cj" \
  "src/gateway/runtime/demo.cj" \
  "src/gateway/runtime/gateway_chat_turn_runtime.cj" \
  "src/gateway/runtime/gateway_cli.cj" \
  "src/gateway/runtime/gateway_config_factory.cj" \
  "src/gateway/runtime/gateway_config_reload_handler.cj" \
  "src/gateway/runtime/gateway_config_reloader.cj" \
  "src/gateway/runtime/gateway_configured_channel_binding_registry.cj" \
  "src/gateway/runtime/gateway_control_ui_ws.cj" \
  "src/gateway/runtime/gateway_external_console.cj" \
  "src/gateway/runtime/gateway_platform_state.cj" \
  "src/gateway/channels/feishu/feishu_adapter.cj" \
  "src/gateway/channels/plugin/command_plugin_adapter.cj" \
  "src/gateway/channels/plugin/legacy_node_plugin_adapter.cj" \
  "src/gateway/channels/qq/qq_adapter.cj" \
  "src/gateway/channels/telegram/telegram_adapter.cj"

check_file_allowlist \
  "gateway/channel direct print" \
  "$direct_print_scan" \
  "$TMP_DIR/direct-print.allowed" \
  "src/gateway/runtime/gateway_control_ui_app.cj"

check_file_allowlist \
  "JS sidecar stdout" \
  "$sidecar_stdout_scan" \
  "$TMP_DIR/sidecar-stdout.allowed" \
  "scripts/feishu-ws-sidecar.mjs" \
  "scripts/legacy-channel-host.mjs" \
  "scripts/openclaw-compat-capabilities.mjs" \
  "scripts/openclaw-compat-ci-gate.mjs" \
  "scripts/openclaw-compat-host.mjs" \
  "scripts/openclaw-compat-real-plugin-smoke.mjs" \
  "scripts/openclaw-compat-security-policy.mjs" \
  "scripts/openclaw-plugin-inventory.mjs" \
  "scripts/openclaw-plugin-sidecar.mjs"

check_file_allowlist \
  "JS sidecar stderr" \
  "$sidecar_stderr_scan" \
  "$TMP_DIR/sidecar-stderr.allowed" \
  "scripts/feishu-ws-sidecar.mjs"

if [ "$failures" -gt 0 ]; then
  echo "logging-output-gate: failed"
  exit 1
fi

echo "logging-output-gate: passed"
