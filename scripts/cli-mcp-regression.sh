#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_HOME="$(mktemp -d /tmp/metis-cli-mcp.XXXXXX)"
GATEWAY_LOG="$TMP_HOME/gateway.log"
GATEWAY_PID=""
MCP_PID=""
MCP_STDIN_PIPE="$TMP_HOME/mcp-stdin.pipe"
MCP_STDOUT_PIPE="$TMP_HOME/mcp-stdout.pipe"

cleanup() {
  local exit_code=$?
  if [[ -n "${MCP_PID}" ]]; then
    kill "${MCP_PID}" >/dev/null 2>&1 || true
    wait "${MCP_PID}" >/dev/null 2>&1 || true
  fi
  exec 3>&- 4<&- >/dev/null 2>&1 || true
  if [[ -n "${GATEWAY_PID}" ]]; then
    kill "${GATEWAY_PID}" >/dev/null 2>&1 || true
    wait "${GATEWAY_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TMP_HOME}" >/dev/null 2>&1 || true
  return "${exit_code}"
}
trap cleanup EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! printf '%s\n' "$haystack" | rg -F -- "$needle" >/dev/null; then
    echo "missing expected text: $needle" >&2
    exit 1
  fi
}

assert_matches() {
  local haystack="$1"
  local pattern="$2"
  if ! printf '%s\n' "$haystack" | rg --multiline "$pattern" >/dev/null; then
    echo "missing expected pattern: $pattern" >&2
    exit 1
  fi
}

run_cli() {
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" \
    rtk cjpm run --skip-script --skip-build --name metis --run-args "$*"
}

send_mcp_frame() {
  local payload="$1"
  printf 'Content-Length: %s\r\n\r\n%s' "${#payload}" "$payload" >&3
}

read_mcp_frame() {
  local line=""
  local length=""
  while IFS= read -r -u 4 line; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && break
    if [[ "$line" == Content-Length:* ]]; then
      length="${line#Content-Length: }"
      length="${length//[[:space:]]/}"
    fi
  done
  [[ -n "$length" ]] || return 1
  local body=""
  body="$(dd bs=1 count="$length" <&4 2>/dev/null)"
  printf '%s' "$body"
}

mkdir -p "$TMP_HOME"
cat >"$TMP_HOME/metis.json" <<'EOF'
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "qwen/qwen3.5-plus"
      }
    }
  },
  "models": {
    "providers": {
      "qwen": {
        "apiKey": "qwen-demo-key",
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1"
      }
    }
  },
  "gateway": {
    "enabled": true,
    "controlUi": {
      "enabled": true
    },
    "auth": {
      "mode": "token",
      "token": "cli-mcp-gateway-test-token"
    }
  }
}
EOF

echo "[cli-mcp-regression] list empty"
mcp_list_empty="$(run_cli mcp list)"
printf '%s\n' "$mcp_list_empty"
assert_contains "$mcp_list_empty" "No MCP servers configured"

echo "[cli-mcp-regression] set/show/unset"
mcp_set_out="$(run_cli mcp set context7 '{"command":"uvx","args":["context7-mcp"]}')"
printf '%s\n' "$mcp_set_out"
assert_contains "$mcp_set_out" 'Saved MCP server "context7"'

mcp_list_out="$(run_cli mcp list)"
printf '%s\n' "$mcp_list_out"
assert_contains "$mcp_list_out" "- context7"

mcp_show_out="$(run_cli mcp show context7)"
printf '%s\n' "$mcp_show_out"
assert_contains "$mcp_show_out" '"command": "uvx"'
assert_contains "$mcp_show_out" '"context7-mcp"'

mcp_unset_out="$(run_cli mcp unset context7)"
printf '%s\n' "$mcp_unset_out"
assert_contains "$mcp_unset_out" 'Removed MCP server "context7"'

echo "[cli-mcp-regression] start gateway"
METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" \
  rtk cjpm run --skip-script --skip-build --name metis --run-args "gateway run" \
  >"$GATEWAY_LOG" 2>&1 &
GATEWAY_PID="$!"

for _ in $(seq 1 60); do
  if [[ -f "$TMP_HOME/gateway-serve.lock" ]]; then
    break
  fi
  sleep 1
done

if [[ ! -f "$TMP_HOME/gateway-serve.lock" ]]; then
  echo "gateway did not start" >&2
  cat "$GATEWAY_LOG" >&2 || true
  exit 1
fi

echo "[cli-mcp-regression] wait for gateway health"
gateway_ready="false"
for _ in $(seq 1 60); do
  gateway_health_out="$(run_cli gateway health 2>&1 || true)"
  if printf '%s\n' "$gateway_health_out" | rg '"method"\s*:\s*"health"' >/dev/null; then
    gateway_ready="true"
    break
  fi
  sleep 1
done

if [[ "$gateway_ready" != "true" ]]; then
  echo "gateway did not become reachable" >&2
  printf '%s\n' "$gateway_health_out" >&2 || true
  cat "$GATEWAY_LOG" >&2 || true
  exit 1
fi

echo "[cli-mcp-regression] start mcp serve"
mkfifo "$MCP_STDIN_PIPE" "$MCP_STDOUT_PIPE"
METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" \
  CANGJIECLAW_MCP_STDIN_PATH="$MCP_STDIN_PIPE" \
  CANGJIECLAW_MCP_STDOUT_PATH="$MCP_STDOUT_PIPE" \
  CANGJIECLAW_MCP_STDERR_PATH="/dev/stderr" \
  rtk cjpm run --skip-script --skip-build --name metis --run-args "mcp serve --verbose" \
  <"$MCP_STDIN_PIPE" >"$MCP_STDOUT_PIPE" &
MCP_PID="$!"
exec 3>"$MCP_STDIN_PIPE"
exec 4<"$MCP_STDOUT_PIPE"
sleep 1

echo "[cli-mcp-regression] initialize"
send_mcp_frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cli-mcp-regression","version":"1.0.0"}}}'
initialize_body="$(read_mcp_frame)"
printf '%s\n' "$initialize_body"
assert_matches "$initialize_body" '"jsonrpc"\s*:\s*"2.0"'
assert_matches "$initialize_body" '"protocolVersion"\s*:\s*"2025-03-26"'

echo "[cli-mcp-regression] tools/list"
send_mcp_frame '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
tools_list_body="$(read_mcp_frame)"
printf '%s\n' "$tools_list_body"
assert_matches "$tools_list_body" '"tools"\s*:'
assert_matches "$tools_list_body" '"gateway.status"'

echo "[cli-mcp-regression] tools/call gateway.status"
send_mcp_frame '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"gateway.status","arguments":{}}}'
tools_call_body="$(read_mcp_frame)"
printf '%s\n' "$tools_call_body"
assert_matches "$tools_call_body" '"result"\s*:'
assert_matches "$tools_call_body" '"ok"'

echo "[cli-mcp-regression] ok"
