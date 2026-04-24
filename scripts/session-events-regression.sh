#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_HOME="$(mktemp -d /tmp/metis-session-events.XXXXXX)"
GATEWAY_PID=""
GATEWAY_PORT="28791"
BIN="$ROOT/target/release/bin/metis"
STDX_LIB_PATH="$ROOT/../CangjieMagic/libs/cangjie-stdx-mac-aarch64-1.0.0.1/darwin_aarch64_llvm/dynamic/stdx"
CLI_LIB_PATH="$ROOT/target/release/metis:$ROOT/ffi"
MAGIC_LIB_PATH="$ROOT/target/release/magic"
LIB_PATHS="$CLI_LIB_PATH:$MAGIC_LIB_PATH:$STDX_LIB_PATH"

append_if_dir() {
  local dir="$1"
  if [[ -n "$dir" && -d "$dir" ]]; then
    LIB_PATHS="$LIB_PATHS:$dir"
  fi
}

prepare_runtime_env() {
  append_if_dir "/opt/homebrew/opt/openssl@3/lib"
  append_if_dir "/opt/homebrew/opt/openssl@3.5/lib"
  append_if_dir "/usr/local/opt/openssl@3/lib"
  export DYLD_LIBRARY_PATH="$LIB_PATHS:${DYLD_LIBRARY_PATH:-}"
}

cleanup() {
  local exit_code=$?
  if [[ -n "${GATEWAY_PID}" ]] && kill -0 "${GATEWAY_PID}" >/dev/null 2>&1; then
    kill "${GATEWAY_PID}" >/dev/null 2>&1 || true
    pkill -TERM -P "${GATEWAY_PID}" >/dev/null 2>&1 || true
    wait "${GATEWAY_PID}" >/dev/null 2>&1 || true
  fi
  for _ in $(seq 1 8); do
    rm -rf "${TMP_HOME}" >/dev/null 2>&1 && break
    sleep 0.25
  done
  return "${exit_code}"
}
trap cleanup EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if ! printf '%s\n' "$haystack" | rg -F "$needle" >/dev/null; then
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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if printf '%s\n' "$haystack" | rg -F "$needle" >/dev/null; then
    echo "unexpected text present: $needle" >&2
    exit 1
  fi
}

run_gateway() {
  prepare_runtime_env
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" "$BIN" gateway "$@"
}

run_cli() {
  prepare_runtime_env
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" "$BIN" "$@"
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 80); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "session events regression http surface not ready: $url" >&2
  exit 1
}

start_gateway_run() {
  if [[ -n "${GATEWAY_PID}" ]] && kill -0 "${GATEWAY_PID}" >/dev/null 2>&1; then
    return 0
  fi
  prepare_runtime_env
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" \
    "$BIN" gateway run >"$TMP_HOME/gateway-run.log" 2>&1 &
  GATEWAY_PID="$!"
  disown "${GATEWAY_PID}" >/dev/null 2>&1 || true
  wait_for_http "http://127.0.0.1:${GATEWAY_PORT}/healthz"
}

mkdir -p "$TMP_HOME"
cat >"$TMP_HOME/metis.json" <<EOF
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
    "port": ${GATEWAY_PORT},
    "auth": {
      "mode": "none"
    },
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    }
  }
}
EOF

echo "[session-events-regression] build"
mkdir -p target build-script-cache/release/metis/bin build-script-cache/release/magic/bin
with_metis_cjpm_build_lock rtk cjpm build -i >/dev/null

echo "[session-events-regression] start gateway run"
start_gateway_run

echo "[session-events-regression] sessions.subscribe records transcript subscriber kinds"
session_subscribe_out="$(run_gateway call sessions.subscribe '{"clientId":"session-events-regression"}')"
printf '%s\n' "$session_subscribe_out"
assert_matches "$session_subscribe_out" '"method"[[:space:]]*:[[:space:]]*"sessions.subscribe"'
assert_matches "$session_subscribe_out" '"subscribed"[[:space:]]*:[[:space:]]*true'
assert_contains "$session_subscribe_out" '"session.transcript.updated"'
assert_contains "$session_subscribe_out" '"sessions.changed"'

echo "[session-events-regression] connect.subscriptions reflects sessions.subscribe"
subscriptions_after_subscribe_out="$(run_gateway call connect.subscriptions '{"clientId":"session-events-regression"}')"
printf '%s\n' "$subscriptions_after_subscribe_out"
assert_contains "$subscriptions_after_subscribe_out" '"eventKinds"'
assert_contains "$subscriptions_after_subscribe_out" '"session.transcript.updated"'
assert_contains "$subscriptions_after_subscribe_out" '"sessions.changed"'

echo "[session-events-regression] sessions.unsubscribe clears transcript subscriber kinds"
session_unsubscribe_out="$(run_gateway call sessions.unsubscribe '{"clientId":"session-events-regression"}')"
printf '%s\n' "$session_unsubscribe_out"
assert_matches "$session_unsubscribe_out" '"method"[[:space:]]*:[[:space:]]*"sessions.unsubscribe"'
assert_matches "$session_unsubscribe_out" '"subscribed"[[:space:]]*:[[:space:]]*false'

echo "[session-events-regression] connect.subscriptions drops transcript subscriber after unsubscribe"
subscriptions_after_unsubscribe_out="$(run_gateway call connect.subscriptions '{"clientId":"session-events-regression"}')"
printf '%s\n' "$subscriptions_after_unsubscribe_out"
assert_not_contains "$subscriptions_after_unsubscribe_out" '"session.transcript.updated"'
assert_not_contains "$subscriptions_after_unsubscribe_out" '"sessions.changed"'

echo "[session-events-regression] subscribe transcript events"
subscribe_out="$(run_gateway call events.stream '{"clientId":"session-events-regression","session":"agent:reviewer:explicit:phase14-events","eventKinds":["session.transcript.updated"],"limit":8,"waitMs":0}')"
printf '%s\n' "$subscribe_out"
assert_matches "$subscribe_out" '"method"[[:space:]]*:[[:space:]]*"events.stream"'
assert_matches "$subscribe_out" '"stream"[[:space:]]*:'
assert_matches "$subscribe_out" '"pull"[[:space:]]*:'

echo "[session-events-regression] subscription snapshot records event kinds"
subscriptions_out="$(run_gateway call connect.subscriptions '{"clientId":"session-events-regression"}')"
printf '%s\n' "$subscriptions_out"
assert_contains "$subscriptions_out" '"eventKinds"'
assert_contains "$subscriptions_out" '"session.transcript.updated"'

echo "[session-events-regression] invoke reviewer session with binding metadata"
invoke_out="$(run_gateway call agent.invoke '{"agentId":"reviewer","session":"phase14-events","text":"/definitely-unknown","channel":"cli","conversationId":"conv-phase14","threadId":"thread-phase14","sourceMessageId":"src-phase14","replyChannel":"feishu","replyTo":"ou_phase14","replyAccount":"feishu:default","replyToMessageId":"reply-phase14","replyInThread":"true"}')"
printf '%s\n' "$invoke_out"
assert_matches "$invoke_out" '"method"[[:space:]]*:[[:space:]]*"agent.invoke"'
assert_matches "$invoke_out" '"ok"[[:space:]]*:[[:space:]]*true'
assert_contains "$invoke_out" '"delivery"'
assert_contains "$invoke_out" '"binding"'
assert_contains "$invoke_out" '"conv-phase14"'
assert_contains "$invoke_out" '"thread-phase14"'
assert_contains "$invoke_out" '"reply-phase14"'

echo "[session-events-regression] transcript stream returns projected session event"
events_out="$(run_gateway call events.stream '{"clientId":"session-events-regression","session":"agent:reviewer:explicit:phase14-events","eventKinds":["session.transcript.updated"],"limit":8,"waitMs":0}')"
printf '%s\n' "$events_out"
assert_contains "$events_out" '"session.transcript.updated"'
assert_contains "$events_out" '"binding"'
assert_contains "$events_out" '"delivery"'
assert_contains "$events_out" '"origin"'
assert_contains "$events_out" '"conv-phase14"'
assert_contains "$events_out" '"thread-phase14"'
assert_contains "$events_out" '"reply-phase14"'
assert_contains "$events_out" '"entryKind": "turn"'

echo "[session-events-regression] sessions.changed stream returns message-phase projection"
changed_subscribe_out="$(run_gateway call events.stream '{"clientId":"session-events-changed","session":"agent:reviewer:explicit:phase14-events","eventKinds":["sessions.changed"],"limit":8,"waitMs":0}')"
printf '%s\n' "$changed_subscribe_out"
assert_matches "$changed_subscribe_out" '"method"[[:space:]]*:[[:space:]]*"events.stream"'

changed_invoke_out="$(run_gateway call agent.invoke '{"agentId":"reviewer","session":"phase14-events","text":"/definitely-unknown","channel":"cli","conversationId":"conv-phase14","threadId":"thread-phase14","sourceMessageId":"src-phase14","replyChannel":"feishu","replyTo":"ou_phase14","replyAccount":"feishu:default","replyToMessageId":"reply-phase14","replyInThread":"true"}')"
printf '%s\n' "$changed_invoke_out"
assert_matches "$changed_invoke_out" '"ok"[[:space:]]*:[[:space:]]*true'

changed_events_out="$(run_gateway call events.stream '{"clientId":"session-events-changed","session":"agent:reviewer:explicit:phase14-events","eventKinds":["sessions.changed"],"limit":8,"waitMs":0}')"
printf '%s\n' "$changed_events_out"
assert_contains "$changed_events_out" '"sessions.changed"'
assert_contains "$changed_events_out" '"phase": "message"'
assert_contains "$changed_events_out" '"binding"'
assert_contains "$changed_events_out" '"delivery"'

echo "[session-events-regression] control-ui session list replays transcript binding"
sessions_out="$(run_gateway call sessions.list)"
printf '%s\n' "$sessions_out"
assert_contains "$sessions_out" '"binding"'
assert_contains "$sessions_out" '"delivery"'
assert_contains "$sessions_out" '"origin"'

echo "[session-events-regression] ok"
