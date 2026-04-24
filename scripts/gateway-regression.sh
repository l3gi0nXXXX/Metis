#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_HOME="$(mktemp -d /tmp/metis-gateway.XXXXXX)"
GATEWAY_PID=""
GATEWAY_PORT="28789"
FIXTURE_PLUGIN_ID="metis-fixture"
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
  if ! printf '%s\n' "$haystack" | rg "$pattern" >/dev/null; then
    echo "missing expected pattern: $pattern" >&2
    exit 1
  fi
}

extract_json_string() {
  local haystack="$1"
  local key="$2"
  printf '%s\n' "$haystack" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/p" | head -n 1
}

extract_json_number() {
  local haystack="$1"
  local key="$2"
  printf '%s\n' "$haystack" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/p" | head -n 1
}

run_gateway() {
  prepare_runtime_env
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" "$BIN" gateway "$@"
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 80); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "gateway http surface not ready: $url" >&2
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
mkdir -p "$TMP_HOME/gateway-plugins"
cp -R "$ROOT/scripts/fixtures/metis-fixture-plugin" "$TMP_HOME/gateway-plugins/$FIXTURE_PLUGIN_ID"
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
    "port": 28789,
    "auth": {
      "mode": "none"
    },
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    },
    "http": {
      "endpoints": {
        "chatCompletions": {
          "enabled": true
        },
        "responses": {
          "enabled": true
        }
      }
    },
    "gatewayPlugins": [
      {
        "id": "metis-fixture",
        "enabled": true
      }
    ],
    "channelsExtra": {
      "metis-fixture": {
        "token": "fixture-token",
        "accountIds": ["fixture:default"],
        "defaultAccountId": "fixture:default"
      }
    }
  }
}
EOF

echo "[gateway-regression] build"
with_metis_cjpm_build_lock bash -lc 'rtk cjpm clean >/dev/null && mkdir -p target build-script-cache/release/metis/bin build-script-cache/release/magic/bin && rtk cjpm build -i >/dev/null'

echo "[gateway-regression] start gateway run"
start_gateway_run

echo "[gateway-regression] status"
status_out="$(run_gateway call status)"
printf '%s\n' "$status_out"
assert_matches "$status_out" '"method"[[:space:]]*:[[:space:]]*"status"'
assert_matches "$status_out" '"result"[[:space:]]*:'
assert_matches "$status_out" '"rpc"[[:space:]]*:'

echo "[gateway-regression] health"
health_out="$(run_gateway call health)"
printf '%s\n' "$health_out"
assert_matches "$health_out" '"surfaces"[[:space:]]*:'
assert_matches "$health_out" '"platform"[[:space:]]*:'

echo "[gateway-regression] readiness"
readiness_out="$(run_gateway call readiness)"
printf '%s\n' "$readiness_out"
assert_matches "$readiness_out" '"surfaces"[[:space:]]*:'
assert_matches "$readiness_out" '"platform"[[:space:]]*:'

echo "[gateway-regression] local method families"
for method in \
  "connect.summary" \
  "connect.status" \
  "connect.client" \
  "connect.challenge" \
  "connect.events" \
  "connect.lifecycle" \
  "connect.subscriptions" \
  "connect.stream.open" \
  "connect.stream.attach" \
  "connect.stream.detach" \
  "connect.stream" \
  "connect.stream.status" \
  "connect.stream.keepalive" \
  "connect.stream.resume" \
  "connect.stream.next" \
  "connect.stream.push" \
  "connect.stream.close" \
  "connect.stream.session" \
  "connect.streams" \
  "connect.bindings" \
  "connect.requests" \
  "connect.actions" \
  "agents.summary" \
  "agents.status" \
  "agents.health" \
  "agents.capabilities" \
  "agent.get" \
  "agent.health" \
  "agent.actions" \
  "agent.routing" \
  "agent.preview" \
  "control_ui.summary" \
  "control_ui.status" \
  "control_ui.contract" \
  "control_ui.routes" \
  "control_ui.binding" \
  "control_ui.runtime" \
  "control_ui.auth" \
  "control_ui.state" \
  "control_ui.origin_policy" \
  "control_ui.health" \
  "control_ui.assets" \
  "control_ui.stop" \
  "control_ui.reload" \
  "webchat.reload" \
  "platform.runtime" \
  "canvas.runtime" \
  "canvas.pipeline" \
  "canvas.audit" \
  "canvas.actions" \
  "talk.runtime" \
  "talk.pipeline" \
  "talk.audit" \
  "talk.actions" \
  "transport.runtime" \
  "transport.remote" \
  "transport.reconnect.history" \
  "transport.reconnect.state" \
  "transport.reconnect.window" \
  "transport.reconnect.plan" \
  "transport.reconnect.audit" \
  "transport.reconnect.reset" \
  "transport.connections" \
  "transport.lifecycle" \
  "transport.subscriptions" \
  "transport.stream.health" \
  "transport.stream.audit" \
  "transport.stream.sessions" \
  "transport.streams" \
  "transport.health" \
  "transport.reconnect" \
  "platform.executor" \
  "nodes.status" \
  "nodes.list" \
  "nodes.get" \
  "nodes.health" \
  "nodes.lifecycle" \
  "nodes.scheduler" \
  "nodes.policy" \
  "nodes.policy.audit" \
  "nodes.policy.reconcile" \
  "nodes.start" \
  "nodes.restart" \
  "nodes.stop" \
  "nodes.heartbeat" \
  "nodes.pending" \
  "nodes.pending_work" \
  "nodes.backlog" \
  "nodes.dispatch.batch" \
  "nodes.retry" \
  "nodes.recover" \
  "nodes.fail" \
  "nodes.executor" \
  "nodes.dispatch" \
  "devices.status" \
  "devices.list" \
  "devices.get" \
  "devices.health" \
  "devices.auth" \
  "devices.lifecycle" \
  "devices.runtime" \
  "devices.policy" \
  "devices.policy.audit" \
  "devices.presence" \
  "devices.approve" \
  "devices.deny" \
  "devices.revalidate" \
  "devices.recover" \
  "devices.touch" \
  "devices.unregister" \
  "push.status" \
  "push.deliveries" \
  "push.summary" \
  "push.lifecycle" \
  "push.dispatcher" \
  "push.orchestration" \
  "push.orchestration.audit" \
  "push.orchestration.actions" \
  "push.orchestrate" \
  "push.get" \
  "push.fail" \
  "push.recover" \
  "push.retry" \
  "push.wake" \
  "models.status" \
  "models.list" \
  "models.current" \
  "models.get" \
  "logs.status" \
  "logs.list" \
  "logs.get" \
  "logs.tail" \
  "usage.status" \
  "usage.summary" \
  "usage-cost" \
  "secrets.summary" \
  "secrets.get" \
  "discover" \
  "discover.detail" \
  "channels.status" \
  "channels.list" \
  "channels.runtime" \
  "channels.manager" \
  "channels.get" \
  "channels.health" \
  "channels.bindings" \
  "channels.policy" \
  "plugins.status" \
  "plugins.list" \
  "plugins.runtime" \
  "plugins.manager" \
  "plugins.get" \
  "plugins.health" \
  "plugins.bindings" \
  "plugins.policy" \
  "plugins.setup.apply" \
  "chat.status" \
  "chat.history" \
  "chat.sessions.list" \
  "wizard.status" \
  "wizard.get" \
  "http.status" \
  "webchat.status" \
  "sessions.list" \
  "sessions.path" \
  "cron.list" \
  "cron.path" \
  "doctor" \
  "doctor.actions" \
  "doctor.remediation" \
  "probe" \
  "probe.actions" \
  "probe.remediation" \
  "nodes.execute" \
  "connect.ping"
do
  out="$(run_gateway call "$method")"
  printf '%s\n' "$out"
  assert_matches "$out" "\"method\"[[:space:]]*:[[:space:]]*\"${method//./\\.}\""
done

http_status="$(run_gateway call http.status)"
printf '%s\n' "$http_status"
assert_matches "$http_status" '"health"[[:space:]]*:'
assert_matches "$http_status" '"healthz"[[:space:]]*:'
assert_matches "$http_status" '"ready"[[:space:]]*:'
assert_matches "$http_status" '"readyz"[[:space:]]*:'
assert_matches "$http_status" '"probePaths"[[:space:]]*:'

echo "[gateway-regression] deep runtime assertions"
connect_summary="$(run_gateway call connect.summary)"
printf '%s\n' "$connect_summary"
assert_matches "$connect_summary" '"eventHistoryCount"[[:space:]]*:'
assert_matches "$connect_summary" '"remote"[[:space:]]*:'
assert_matches "$connect_summary" '"reconnect"[[:space:]]*:'
assert_matches "$connect_summary" '"reconnectState"[[:space:]]*:'
assert_matches "$connect_summary" '"policyState"[[:space:]]*:'
assert_matches "$connect_summary" '"runtimeModel"[[:space:]]*:'

connect_events="$(run_gateway call connect.events)"
printf '%s\n' "$connect_events"
assert_matches "$connect_events" '"eventHistory"[[:space:]]*:'
assert_contains "$connect_events" 'request.begin'
assert_matches "$connect_events" '"pull"[[:space:]]*:'
assert_matches "$connect_events" '"nextCursor"[[:space:]]*:'

connect_events_cursor="$(run_gateway call connect.events '{"clientId":"metis-cli","limit":1,"sinceId":"evt-1","peek":true}')"
printf '%s\n' "$connect_events_cursor"
assert_matches "$connect_events_cursor" '"sinceId"[[:space:]]*:[[:space:]]*"evt-1"'
assert_matches "$connect_events_cursor" '"deliveredCount"[[:space:]]*:'
assert_matches "$connect_events_cursor" '"peek"[[:space:]]*:[[:space:]]*true'

connect_subscriptions="$(run_gateway call connect.subscriptions '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_subscriptions"
assert_matches "$connect_subscriptions" '"eventSubscriptions"[[:space:]]*:'
assert_matches "$connect_subscriptions" '"lastPullAtMs"[[:space:]]*:'
assert_matches "$connect_subscriptions" '"deliveredEventCount"[[:space:]]*:'
assert_matches "$connect_subscriptions" '"peekPullCount"[[:space:]]*:'
assert_matches "$connect_subscriptions" '"lastCursor"[[:space:]]*:'

connect_stream_open="$(run_gateway call connect.stream.open '{"clientId":"metis-cli","limit":2,"waitMs":50}')"
printf '%s\n' "$connect_stream_open"
assert_matches "$connect_stream_open" '"opened"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_open" '"stream"[[:space:]]*:'
assert_matches "$connect_stream_open" '"openCount"[[:space:]]*:'
assert_matches "$connect_stream_open" '"attachCount"[[:space:]]*:'
assert_matches "$connect_stream_open" '"sessionMode"[[:space:]]*:[[:space:]]*"persistent-session"'
assert_matches "$connect_stream_open" '"attachable"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_open" '"phase"[[:space:]]*:'
assert_matches "$connect_stream_open" '"waitMs"[[:space:]]*:[[:space:]]*50'
assert_matches "$connect_stream_open" '"mode"[[:space:]]*:[[:space:]]*"long-poll"'
assert_matches "$connect_stream_open" '"serverPush"[[:space:]]*:[[:space:]]*false'
connect_stream_generation="$(extract_json_number "$connect_stream_open" "sessionGeneration")"

connect_stream_status="$(run_gateway call connect.stream.status '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_stream_status"
assert_matches "$connect_stream_status" '"stream"[[:space:]]*:'
assert_matches "$connect_stream_status" '"subscription"[[:space:]]*:'
assert_matches "$connect_stream_status" '"leaseExpiresAtMs"[[:space:]]*:'
assert_matches "$connect_stream_status" '"streamId"[[:space:]]*:'
assert_matches "$connect_stream_status" '"serverPushCapable"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_status" '"sessionMode"[[:space:]]*:[[:space:]]*"persistent-session"'
assert_matches "$connect_stream_status" '"attachable"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_status" '"state"[[:space:]]*:'
assert_matches "$connect_stream_status" '"phase"[[:space:]]*:'
assert_matches "$connect_stream_status" '"sessionGeneration"[[:space:]]*:'
assert_matches "$connect_stream_status" '"attachCount"[[:space:]]*:'
assert_matches "$connect_stream_status" '"lastAttachAtMs"[[:space:]]*:'

connect_stream_keepalive="$(run_gateway call connect.stream.keepalive '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_stream_keepalive"
assert_matches "$connect_stream_keepalive" '"keepalive"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_keepalive" '"keepaliveCount"[[:space:]]*:'
assert_matches "$connect_stream_keepalive" '"streamId"[[:space:]]*:'

connect_stream_attach="$(run_gateway call connect.stream.attach '{"clientId":"metis-cli","waitMs":0}')"
printf '%s\n' "$connect_stream_attach"
assert_matches "$connect_stream_attach" '"attached"[[:space:]]*:[[:space:]]*true'
assert_contains "$connect_stream_attach" "\"sessionGeneration\": ${connect_stream_generation}"
assert_matches "$connect_stream_attach" '"sessionMode"[[:space:]]*:[[:space:]]*"persistent-session"'

connect_stream_resume="$(run_gateway call connect.stream.resume '{"clientId":"metis-cli","limit":1}')"
printf '%s\n' "$connect_stream_resume"
assert_matches "$connect_stream_resume" '"resumed"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_resume" '"pull"[[:space:]]*:'
assert_contains "$connect_stream_resume" "\"sessionGeneration\": ${connect_stream_generation}"

connect_stream_next="$(run_gateway call connect.stream.next '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_stream_next"
assert_matches "$connect_stream_next" '"next"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_next" '"pull"[[:space:]]*:'
assert_contains "$connect_stream_next" "\"sessionGeneration\": ${connect_stream_generation}"

connect_stream_push="$(run_gateway call connect.stream.push '{"clientId":"metis-cli","kind":"stream.push","detail":"regression-push"}')"
printf '%s\n' "$connect_stream_push"
assert_matches "$connect_stream_push" '"pushed"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_push" '"queueDepth"[[:space:]]*:'
assert_matches "$connect_stream_push" '"pendingPushCount"[[:space:]]*:'

connect_stream_session="$(run_gateway call connect.stream.session '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_stream_session"
assert_matches "$connect_stream_session" '"session"[[:space:]]*:'
assert_matches "$connect_stream_session" '"sessionGeneration"[[:space:]]*:'
assert_matches "$connect_stream_session" '"attachCount"[[:space:]]*:'
assert_matches "$connect_stream_session" '"detachCount"[[:space:]]*:'

connect_streams="$(run_gateway call connect.streams '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_streams"
assert_matches "$connect_streams" '"eventStreams"[[:space:]]*:'
assert_matches "$connect_streams" '"active"[[:space:]]*:'
assert_matches "$connect_streams" '"openCount"[[:space:]]*:'
assert_matches "$connect_streams" '"leaseExpiresAtMs"[[:space:]]*:'
assert_matches "$connect_streams" '"keepaliveCount"[[:space:]]*:'
assert_matches "$connect_streams" '"pendingPushCount"[[:space:]]*:'
assert_matches "$connect_streams" '"serverPushCapable"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_streams" '"state"[[:space:]]*:'
assert_matches "$connect_streams" '"phase"[[:space:]]*:'
assert_matches "$connect_streams" '"sessionGeneration"[[:space:]]*:'
assert_matches "$connect_streams" '"attachCount"[[:space:]]*:'
assert_matches "$connect_streams" '"detachCount"[[:space:]]*:'

connect_stream_close="$(run_gateway call connect.stream.close '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_stream_close"
assert_matches "$connect_stream_close" '"closed"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_close" '"active"[[:space:]]*:[[:space:]]*false'
assert_matches "$connect_stream_close" '"lastDetachAtMs"[[:space:]]*:'

connect_stream_detach="$(run_gateway call connect.stream.detach '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_stream_detach"
assert_matches "$connect_stream_detach" '"detached"[[:space:]]*:[[:space:]]*true'
assert_matches "$connect_stream_detach" '"sessionGeneration"[[:space:]]*:'

connect_lifecycle="$(run_gateway call connect.lifecycle '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_lifecycle"
assert_matches "$connect_lifecycle" '"eventHistory"[[:space:]]*:'
assert_matches "$connect_lifecycle" '"clientId"[[:space:]]*:[[:space:]]*"metis-cli"'
assert_matches "$connect_lifecycle" '"remote"[[:space:]]*:'
assert_matches "$connect_lifecycle" '"reconnect"[[:space:]]*:'
assert_matches "$connect_lifecycle" '"reconnectState"[[:space:]]*:'

connect_actions="$(run_gateway call connect.actions '{"clientId":"metis-cli"}')"
printf '%s\n' "$connect_actions"
assert_matches "$connect_actions" '"actions"[[:space:]]*:'
assert_contains "$connect_actions" '"method": "connect.stream.keepalive"'
assert_contains "$connect_actions" '"policyState"'
assert_contains "$connect_actions" '"params"'

control_summary="$(run_gateway call control_ui.summary)"
printf '%s\n' "$control_summary"
assert_matches "$control_summary" '"healthy"[[:space:]]*:'
assert_matches "$control_summary" '"statePath"[[:space:]]*:'

agent_health="$(run_gateway call agent.health '{"agentId":"general"}')"
printf '%s\n' "$agent_health"
assert_matches "$agent_health" '"healthy"[[:space:]]*:[[:space:]]*true'
assert_matches "$agent_health" '"state"[[:space:]]*:[[:space:]]*"ready"'
assert_contains "$agent_health" '"policyState": "routable"'
assert_contains "$agent_health" '"actions"'

agents_summary="$(run_gateway call agents.summary)"
printf '%s\n' "$agents_summary"
assert_matches "$agents_summary" '"defaultId"[[:space:]]*:[[:space:]]*"general"'
assert_matches "$agents_summary" '"mainKey"[[:space:]]*:[[:space:]]*"main"'
assert_matches "$agents_summary" '"scope"[[:space:]]*:[[:space:]]*"global"'
assert_matches "$agents_summary" '"agents"[[:space:]]*:'
assert_matches "$agents_summary" '"skills"[[:space:]]*:'

agents_status="$(run_gateway call agents.status)"
printf '%s\n' "$agents_status"
assert_matches "$agents_status" '"defaultId"[[:space:]]*:[[:space:]]*"general"'
assert_matches "$agents_status" '"mainKey"[[:space:]]*:[[:space:]]*"main"'
assert_matches "$agents_status" '"scope"[[:space:]]*:[[:space:]]*"global"'
assert_matches "$agents_status" '"agents"[[:space:]]*:'
assert_matches "$agents_status" '"skills"[[:space:]]*:'

agent_actions="$(run_gateway call agent.actions '{"agentId":"general","channel":"gateway-rpc","session":"main","text":"hello"}')"
printf '%s\n' "$agent_actions"
assert_matches "$agent_actions" '"actions"[[:space:]]*:'
assert_matches "$agent_actions" '"policyState"[[:space:]]*:'
assert_matches "$agent_actions" '"remediationState"[[:space:]]*:'
assert_matches "$agent_actions" '"constraints"[[:space:]]*:'

agent_routing="$(run_gateway call agent.routing '{"agentId":"general","channel":"gateway-rpc","session":"main","text":"hello"}')"
printf '%s\n' "$agent_routing"
assert_matches "$agent_routing" '"routing"[[:space:]]*:'
assert_matches "$agent_routing" '"transport"[[:space:]]*:[[:space:]]*"rpc"'
assert_matches "$agent_routing" '"delivery"[[:space:]]*:[[:space:]]*"invoke"'
assert_contains "$agent_routing" '"policyState": "direct-rpc"'
assert_contains "$agent_routing" '"action": "invoke-agent"'

control_binding="$(run_gateway call control_ui.binding)"
printf '%s\n' "$control_binding"
assert_matches "$control_binding" '"binding"[[:space:]]*:'
assert_matches "$control_binding" '"httpUrl"[[:space:]]*:'
assert_matches "$control_binding" '"wsUrl"[[:space:]]*:'
assert_matches "$control_binding" '"apiPrefix"[[:space:]]*:[[:space:]]*"/api"'
assert_matches "$control_binding" '"assetsPath"[[:space:]]*:[[:space:]]*"/assets"'
assert_matches "$control_binding" '"summary"[[:space:]]*:'
assert_matches "$control_binding" '"contract"[[:space:]]*:'
assert_matches "$control_binding" '"state"[[:space:]]*:'

control_runtime="$(run_gateway call control_ui.runtime)"
printf '%s\n' "$control_runtime"
assert_matches "$control_runtime" '"runtime"[[:space:]]*:'
assert_matches "$control_runtime" '"healthy"[[:space:]]*:'
assert_matches "$control_runtime" '"originPolicy"[[:space:]]*:'
assert_matches "$control_runtime" '"binding"[[:space:]]*:'
assert_matches "$control_runtime" '"contract"[[:space:]]*:'
assert_matches "$control_runtime" '"summary"[[:space:]]*:'

control_origin_policy="$(run_gateway call control_ui.origin_policy)"
printf '%s\n' "$control_origin_policy"
assert_matches "$control_origin_policy" '"originPolicy"[[:space:]]*:'
assert_matches "$control_origin_policy" '"csp"[[:space:]]*:'
assert_matches "$control_origin_policy" '"summary"[[:space:]]*:'
assert_matches "$control_origin_policy" '"binding"[[:space:]]*:'
assert_matches "$control_origin_policy" '"contract"[[:space:]]*:'

control_auth="$(run_gateway call control_ui.auth)"
printf '%s\n' "$control_auth"
assert_matches "$control_auth" '"auth"[[:space:]]*:'
assert_matches "$control_auth" '"summary"[[:space:]]*:'
assert_matches "$control_auth" '"binding"[[:space:]]*:'
assert_matches "$control_auth" '"contract"[[:space:]]*:'

control_state="$(run_gateway call control_ui.state)"
printf '%s\n' "$control_state"
assert_matches "$control_state" '"state"[[:space:]]*:'
assert_matches "$control_state" '"statePath"[[:space:]]*:'
assert_matches "$control_state" '"summary"[[:space:]]*:'
assert_matches "$control_state" '"binding"[[:space:]]*:'
assert_matches "$control_state" '"contract"[[:space:]]*:'

control_health="$(run_gateway call control_ui.health)"
printf '%s\n' "$control_health"
assert_matches "$control_health" '"healthy"[[:space:]]*:'
assert_matches "$control_health" '"summary"[[:space:]]*:'
assert_matches "$control_health" '"binding"[[:space:]]*:'
assert_matches "$control_health" '"contract"[[:space:]]*:'
assert_matches "$control_health" '"state"[[:space:]]*:'

control_assets="$(run_gateway call control_ui.assets)"
printf '%s\n' "$control_assets"
assert_matches "$control_assets" '"assetsPath"[[:space:]]*:'
assert_matches "$control_assets" '"summary"[[:space:]]*:'
assert_matches "$control_assets" '"binding"[[:space:]]*:'
assert_matches "$control_assets" '"contract"[[:space:]]*:'

control_stop="$(run_gateway call control_ui.stop)"
printf '%s\n' "$control_stop"
assert_matches "$control_stop" '"stopped"[[:space:]]*:'

control_reload="$(run_gateway call control_ui.reload)"
printf '%s\n' "$control_reload"
assert_matches "$control_reload" '"reloaded"[[:space:]]*:'
assert_contains "$control_reload" '"started": true'

webchat_reload="$(run_gateway call webchat.reload)"
printf '%s\n' "$webchat_reload"
assert_matches "$webchat_reload" '"reloaded"[[:space:]]*:'
assert_matches "$webchat_reload" '"webchat"[[:space:]]*:'

platform_runtime="$(run_gateway call platform.runtime)"
printf '%s\n' "$platform_runtime"
assert_matches "$platform_runtime" '"paths"[[:space:]]*:'
assert_matches "$platform_runtime" '"health"[[:space:]]*:'
assert_matches "$platform_runtime" '"platformState"[[:space:]]*:'
assert_matches "$platform_runtime" '"nodeHealth"[[:space:]]*:'
assert_matches "$platform_runtime" '"deviceHealth"[[:space:]]*:'
assert_matches "$platform_runtime" '"nodeLifecycle"[[:space:]]*:'
assert_matches "$platform_runtime" '"deviceAuth"[[:space:]]*:'
assert_matches "$platform_runtime" '"pushLifecycle"[[:space:]]*:'
assert_matches "$platform_runtime" '"deviceRuntime"[[:space:]]*:'
assert_matches "$platform_runtime" '"devicePresence"[[:space:]]*:'
assert_matches "$platform_runtime" '"pushDispatcher"[[:space:]]*:'
assert_matches "$platform_runtime" '"canvasRuntime"[[:space:]]*:'
assert_matches "$platform_runtime" '"talkRuntime"[[:space:]]*:'
assert_matches "$platform_runtime" '"backlog"[[:space:]]*:'
assert_matches "$platform_runtime" '"nodePolicy"[[:space:]]*:'
assert_matches "$platform_runtime" '"nodePolicyAudit"[[:space:]]*:'
assert_matches "$platform_runtime" '"devicePolicy"[[:space:]]*:'
assert_matches "$platform_runtime" '"devicePolicyAudit"[[:space:]]*:'
assert_matches "$platform_runtime" '"pushOrchestration"[[:space:]]*:'
assert_matches "$platform_runtime" '"pushOrchestrationAudit"[[:space:]]*:'
assert_matches "$platform_runtime" '"canvasPipeline"[[:space:]]*:'
assert_matches "$platform_runtime" '"talkPipeline"[[:space:]]*:'

canvas_runtime="$(run_gateway call canvas.runtime)"
printf '%s\n' "$canvas_runtime"
assert_matches "$canvas_runtime" '"phase"[[:space:]]*:'
assert_matches "$canvas_runtime" '"healthy"[[:space:]]*:'
assert_matches "$canvas_runtime" '"rootPresent"[[:space:]]*:'
assert_matches "$canvas_runtime" '"assetState"[[:space:]]*:'
assert_matches "$canvas_runtime" '"watchState"[[:space:]]*:'
assert_matches "$canvas_runtime" '"policyState"[[:space:]]*:'

canvas_pipeline="$(run_gateway call canvas.pipeline)"
printf '%s\n' "$canvas_pipeline"
assert_matches "$canvas_pipeline" '"pipelineState"[[:space:]]*:'
assert_matches "$canvas_pipeline" '"enabled"[[:space:]]*:'
assert_matches "$canvas_pipeline" '"policyState"[[:space:]]*:'
assert_matches "$canvas_pipeline" '"remediationState"[[:space:]]*:'
assert_matches "$canvas_pipeline" '"constraints"[[:space:]]*:'
assert_matches "$canvas_pipeline" '"actionsNeeded"[[:space:]]*:'
assert_matches "$canvas_pipeline" '"actions"[[:space:]]*:'

canvas_audit="$(run_gateway call canvas.audit)"
printf '%s\n' "$canvas_audit"
assert_matches "$canvas_audit" '"audit"[[:space:]]*:'
assert_matches "$canvas_audit" '"auditState"[[:space:]]*:'
assert_matches "$canvas_audit" '"actionsNeeded"[[:space:]]*:'
assert_matches "$canvas_audit" '"constraints"[[:space:]]*:'
assert_matches "$canvas_audit" '"actions"[[:space:]]*:'

canvas_actions="$(run_gateway call canvas.actions)"
printf '%s\n' "$canvas_actions"
assert_matches "$canvas_actions" '"actions"[[:space:]]*:'
assert_matches "$canvas_actions" '"auditState"[[:space:]]*:'
assert_matches "$canvas_actions" '"actionsNeeded"[[:space:]]*:'
assert_matches "$canvas_actions" '"constraints"[[:space:]]*:'

talk_runtime="$(run_gateway call talk.runtime)"
printf '%s\n' "$talk_runtime"
assert_matches "$talk_runtime" '"phase"[[:space:]]*:'
assert_matches "$talk_runtime" '"healthy"[[:space:]]*:'
assert_matches "$talk_runtime" '"providerConfigured"[[:space:]]*:'
assert_matches "$talk_runtime" '"inputState"[[:space:]]*:'
assert_matches "$talk_runtime" '"outputState"[[:space:]]*:'
assert_matches "$talk_runtime" '"policyState"[[:space:]]*:'

talk_pipeline="$(run_gateway call talk.pipeline)"
printf '%s\n' "$talk_pipeline"
assert_matches "$talk_pipeline" '"pipelineState"[[:space:]]*:'
assert_matches "$talk_pipeline" '"provider"[[:space:]]*:'
assert_matches "$talk_pipeline" '"policyState"[[:space:]]*:'
assert_matches "$talk_pipeline" '"remediationState"[[:space:]]*:'
assert_matches "$talk_pipeline" '"constraints"[[:space:]]*:'
assert_matches "$talk_pipeline" '"actionsNeeded"[[:space:]]*:'
assert_matches "$talk_pipeline" '"actions"[[:space:]]*:'

talk_audit="$(run_gateway call talk.audit)"
printf '%s\n' "$talk_audit"
assert_matches "$talk_audit" '"audit"[[:space:]]*:'
assert_matches "$talk_audit" '"auditState"[[:space:]]*:'
assert_matches "$talk_audit" '"actionsNeeded"[[:space:]]*:'
assert_matches "$talk_audit" '"constraints"[[:space:]]*:'
assert_matches "$talk_audit" '"actions"[[:space:]]*:'

talk_actions="$(run_gateway call talk.actions)"
printf '%s\n' "$talk_actions"
assert_matches "$talk_actions" '"actions"[[:space:]]*:'
assert_matches "$talk_actions" '"auditState"[[:space:]]*:'
assert_matches "$talk_actions" '"actionsNeeded"[[:space:]]*:'
assert_matches "$talk_actions" '"constraints"[[:space:]]*:'

nodes_lifecycle="$(run_gateway call nodes.lifecycle)"
printf '%s\n' "$nodes_lifecycle"
assert_matches "$nodes_lifecycle" '"byLifecycleState"[[:space:]]*:'
assert_matches "$nodes_lifecycle" '"byPhase"[[:space:]]*:'
assert_matches "$nodes_lifecycle" '"transitionCount"[[:space:]]*:'
assert_matches "$nodes_lifecycle" '"restartCount"[[:space:]]*:'

nodes_scheduler="$(run_gateway call nodes.scheduler)"
printf '%s\n' "$nodes_scheduler"
assert_matches "$nodes_scheduler" '"byPhase"[[:space:]]*:'
assert_matches "$nodes_scheduler" '"byRecoveryState"[[:space:]]*:'
assert_matches "$nodes_scheduler" '"executorState"[[:space:]]*:'

nodes_policy="$(run_gateway call nodes.policy)"
printf '%s\n' "$nodes_policy"
assert_matches "$nodes_policy" '"dispatchable"[[:space:]]*:'
assert_matches "$nodes_policy" '"byBrowserMode"[[:space:]]*:'
assert_matches "$nodes_policy" '"byDecision"[[:space:]]*:'
assert_matches "$nodes_policy" '"byBlockedReason"[[:space:]]*:'
assert_matches "$nodes_policy" '"policyState"[[:space:]]*:'

nodes_policy_audit="$(run_gateway call nodes.policy.audit)"
printf '%s\n' "$nodes_policy_audit"
assert_matches "$nodes_policy_audit" '"audit"[[:space:]]*:'
assert_matches "$nodes_policy_audit" '"actionsNeeded"[[:space:]]*:'
assert_matches "$nodes_policy_audit" '"auditState"[[:space:]]*:'

nodes_policy_reconcile="$(run_gateway call nodes.policy.reconcile '{"nodeId":"local-gateway","limit":1}')"
printf '%s\n' "$nodes_policy_reconcile"
assert_matches "$nodes_policy_reconcile" '"reconcile"[[:space:]]*:'
assert_matches "$nodes_policy_reconcile" '"actions"[[:space:]]*:'
assert_matches "$nodes_policy_reconcile" '"decision"[[:space:]]*:'

nodes_backlog="$(run_gateway call nodes.backlog)"
printf '%s\n' "$nodes_backlog"
assert_matches "$nodes_backlog" '"pendingWork"[[:space:]]*:'
assert_matches "$nodes_backlog" '"scheduler"[[:space:]]*:'
assert_matches "$nodes_backlog" '"backlog"[[:space:]]*:'
assert_matches "$nodes_backlog" '"byKind"[[:space:]]*:'
assert_matches "$nodes_backlog" '"byTarget"[[:space:]]*:'
assert_matches "$nodes_backlog" '"byRecoveryState"[[:space:]]*:'
assert_matches "$nodes_backlog" '"nextReadyAtMs"[[:space:]]*:'

devices_auth="$(run_gateway call devices.auth)"
printf '%s\n' "$devices_auth"
assert_matches "$devices_auth" '"authModes"[[:space:]]*:'
assert_matches "$devices_auth" '"authStates"[[:space:]]*:'
assert_matches "$devices_auth" '"byPhase"[[:space:]]*:'
assert_matches "$devices_auth" '"policyStates"[[:space:]]*:'

devices_lifecycle="$(run_gateway call devices.lifecycle)"
printf '%s\n' "$devices_lifecycle"
assert_matches "$devices_lifecycle" '"byPhase"[[:space:]]*:'

devices_runtime="$(run_gateway call devices.runtime)"
printf '%s\n' "$devices_runtime"
assert_matches "$devices_runtime" '"byKind"[[:space:]]*:'
assert_matches "$devices_runtime" '"byStatus"[[:space:]]*:'
assert_matches "$devices_runtime" '"byAuthState"[[:space:]]*:'
assert_matches "$devices_runtime" '"transitionCount"[[:space:]]*:'

devices_policy="$(run_gateway call devices.policy)"
printf '%s\n' "$devices_policy"
assert_matches "$devices_policy" '"approvalRequired"[[:space:]]*:'
assert_matches "$devices_policy" '"byApprovalState"[[:space:]]*:'
assert_matches "$devices_policy" '"policyState"[[:space:]]*:'
assert_matches "$devices_policy" '"recoverable"[[:space:]]*:'

devices_policy_audit="$(run_gateway call devices.policy.audit)"
printf '%s\n' "$devices_policy_audit"
assert_matches "$devices_policy_audit" '"audit"[[:space:]]*:'
assert_matches "$devices_policy_audit" '"actionsNeeded"[[:space:]]*:'
assert_matches "$devices_policy_audit" '"auditState"[[:space:]]*:'

devices_presence="$(run_gateway call devices.presence)"
printf '%s\n' "$devices_presence"
assert_matches "$devices_presence" '"byPresence"[[:space:]]*:'
assert_matches "$devices_presence" '"presenceState"[[:space:]]*:'
assert_matches "$devices_presence" '"controlUiDevices"[[:space:]]*:'

push_summary="$(run_gateway call push.summary)"
printf '%s\n' "$push_summary"
assert_matches "$push_summary" '"summary"[[:space:]]*:'
assert_matches "$push_summary" '"byStatus"[[:space:]]*:'
assert_matches "$push_summary" '"byLifecycleState"[[:space:]]*:'

push_lifecycle="$(run_gateway call push.lifecycle)"
printf '%s\n' "$push_lifecycle"
assert_matches "$push_lifecycle" '"retryingDeliveries"[[:space:]]*:'
assert_matches "$push_lifecycle" '"failedDeliveries"[[:space:]]*:'

push_dispatcher="$(run_gateway call push.dispatcher)"
printf '%s\n' "$push_dispatcher"
assert_matches "$push_dispatcher" '"byChannel"[[:space:]]*:'
assert_matches "$push_dispatcher" '"byTarget"[[:space:]]*:'
assert_matches "$push_dispatcher" '"byTargetState"[[:space:]]*:'
assert_matches "$push_dispatcher" '"wakeTargets"[[:space:]]*:'
assert_matches "$push_dispatcher" '"recoverableDeliveries"[[:space:]]*:'
assert_matches "$push_dispatcher" '"dispatcherState"[[:space:]]*:'

push_orchestration="$(run_gateway call push.orchestration)"
printf '%s\n' "$push_orchestration"
assert_matches "$push_orchestration" '"recoverableTargets"[[:space:]]*:'
assert_matches "$push_orchestration" '"byAction"[[:space:]]*:'
assert_matches "$push_orchestration" '"orchestratorState"[[:space:]]*:'
assert_matches "$push_orchestration" '"approvalPolicyState"[[:space:]]*:'
assert_matches "$push_orchestration" '"dispatcherState"[[:space:]]*:'
assert_matches "$push_orchestration" '"presenceState"[[:space:]]*:'
assert_matches "$push_orchestration" '"policyState"[[:space:]]*:'
assert_matches "$push_orchestration" '"actionsNeeded"[[:space:]]*:'
assert_matches "$push_orchestration" '"constraints"[[:space:]]*:'
assert_matches "$push_orchestration" '"actions"[[:space:]]*:'

push_orchestration_audit="$(run_gateway call push.orchestration.audit)"
printf '%s\n' "$push_orchestration_audit"
assert_matches "$push_orchestration_audit" '"audit"[[:space:]]*:'
assert_matches "$push_orchestration_audit" '"actionsNeeded"[[:space:]]*:'
assert_matches "$push_orchestration_audit" '"auditState"[[:space:]]*:'
assert_matches "$push_orchestration_audit" '"constraints"[[:space:]]*:'
assert_matches "$push_orchestration_audit" '"actions"[[:space:]]*:'

push_orchestration_actions="$(run_gateway call push.orchestration.actions)"
printf '%s\n' "$push_orchestration_actions"
assert_matches "$push_orchestration_actions" '"actions"[[:space:]]*:'
assert_matches "$push_orchestration_actions" '"auditState"[[:space:]]*:'
assert_matches "$push_orchestration_actions" '"actionsNeeded"[[:space:]]*:'
assert_matches "$push_orchestration_actions" '"constraints"[[:space:]]*:'

push_orchestrate="$(run_gateway call push.orchestrate '{"channel":"local","limit":1}')"
printf '%s\n' "$push_orchestrate"
assert_matches "$push_orchestrate" '"orchestrator"[[:space:]]*:'
assert_matches "$push_orchestrate" '"processed"[[:space:]]*:'
assert_matches "$push_orchestrate" '"actions"[[:space:]]*:'

transport_runtime="$(run_gateway call transport.runtime)"
printf '%s\n' "$transport_runtime"
assert_matches "$transport_runtime" '"statePath"[[:space:]]*:'
assert_matches "$transport_runtime" '"preferred"[[:space:]]*:'
assert_matches "$transport_runtime" '"runtimeModel"[[:space:]]*:'
assert_matches "$transport_runtime" '"policyState"[[:space:]]*:'
assert_matches "$transport_runtime" '"constraints"[[:space:]]*:'
assert_matches "$transport_runtime" '"actions"[[:space:]]*:'

transport_remote="$(run_gateway call transport.remote)"
printf '%s\n' "$transport_remote"
assert_matches "$transport_remote" '"remote"[[:space:]]*:'
assert_matches "$transport_remote" '"summary"[[:space:]]*:'
assert_matches "$transport_remote" '"reconnect"[[:space:]]*:'
assert_matches "$transport_remote" '"policyState"[[:space:]]*:'

transport_reconnect_history="$(run_gateway call transport.reconnect.history)"
printf '%s\n' "$transport_reconnect_history"
assert_matches "$transport_reconnect_history" '"lifecycle"[[:space:]]*:'
assert_matches "$transport_reconnect_history" '"reconnectState"[[:space:]]*:'
assert_matches "$transport_reconnect_history" '"remote"[[:space:]]*:'
assert_matches "$transport_reconnect_history" '"reconnect"[[:space:]]*:'

transport_reconnect_state="$(run_gateway call transport.reconnect.state)"
printf '%s\n' "$transport_reconnect_state"
assert_matches "$transport_reconnect_state" '"state"[[:space:]]*:'
assert_matches "$transport_reconnect_state" '"transitionCount"[[:space:]]*:'
assert_matches "$transport_reconnect_state" '"phase"[[:space:]]*:'
assert_matches "$transport_reconnect_state" '"stable"[[:space:]]*:'
assert_matches "$transport_reconnect_state" '"cooldownRemainingMs"[[:space:]]*:'
assert_matches "$transport_reconnect_state" '"eligibleForReconnect"[[:space:]]*:'
assert_matches "$transport_reconnect_state" '"remote"[[:space:]]*:'
assert_matches "$transport_reconnect_state" '"reconnect"[[:space:]]*:'

transport_reconnect_window="$(run_gateway call transport.reconnect.window)"
printf '%s\n' "$transport_reconnect_window"
assert_matches "$transport_reconnect_window" '"window"[[:space:]]*:'
assert_matches "$transport_reconnect_window" '"consecutiveFailureCount"[[:space:]]*:'
assert_matches "$transport_reconnect_window" '"cooldownRemainingMs"[[:space:]]*:'
assert_matches "$transport_reconnect_window" '"remote"[[:space:]]*:'
assert_matches "$transport_reconnect_window" '"reconnect"[[:space:]]*:'

transport_reconnect_plan="$(run_gateway call transport.reconnect.plan)"
printf '%s\n' "$transport_reconnect_plan"
assert_matches "$transport_reconnect_plan" '"plan"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"nextRetryAtMs"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"phase"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"runtimeModel"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"policyState"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"cooldownRemainingMs"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"eligibleForReconnect"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"remote"[[:space:]]*:'
assert_matches "$transport_reconnect_plan" '"reconnect"[[:space:]]*:'

transport_reconnect_audit="$(run_gateway call transport.reconnect.audit)"
printf '%s\n' "$transport_reconnect_audit"
assert_matches "$transport_reconnect_audit" '"audit"[[:space:]]*:'
assert_matches "$transport_reconnect_audit" '"auditState"[[:space:]]*:'
assert_matches "$transport_reconnect_audit" '"constraints"[[:space:]]*:'
assert_matches "$transport_reconnect_audit" '"actions"[[:space:]]*:'
assert_matches "$transport_reconnect_audit" '"remote"[[:space:]]*:'
assert_matches "$transport_reconnect_audit" '"reconnect"[[:space:]]*:'

transport_reconnect_reset="$(run_gateway call transport.reconnect.reset)"
printf '%s\n' "$transport_reconnect_reset"
assert_matches "$transport_reconnect_reset" '"reset"[[:space:]]*:[[:space:]]*true'

transport_connections="$(run_gateway call transport.connections)"
printf '%s\n' "$transport_connections"
assert_matches "$transport_connections" '"connections"[[:space:]]*:'

transport_subscriptions="$(run_gateway call transport.subscriptions)"
printf '%s\n' "$transport_subscriptions"
assert_matches "$transport_subscriptions" '"eventSubscriptions"[[:space:]]*:'

transport_lifecycle="$(run_gateway call transport.lifecycle)"
printf '%s\n' "$transport_lifecycle"
assert_matches "$transport_lifecycle" '"lifecycle"[[:space:]]*:'
assert_matches "$transport_lifecycle" '"lastProtocolVersion"[[:space:]]*:'
assert_matches "$transport_lifecycle" '"remote"[[:space:]]*:'
assert_matches "$transport_lifecycle" '"reconnect"[[:space:]]*:'

transport_stream_health="$(run_gateway call transport.stream.health)"
printf '%s\n' "$transport_stream_health"
assert_matches "$transport_stream_health" '"streamCount"[[:space:]]*:'
assert_matches "$transport_stream_health" '"subscriptionCount"[[:space:]]*:'
assert_matches "$transport_stream_health" '"streamSummary"[[:space:]]*:'
assert_matches "$transport_stream_health" '"subscriptionSummary"[[:space:]]*:'

transport_stream_audit="$(run_gateway call transport.stream.audit)"
printf '%s\n' "$transport_stream_audit"
assert_matches "$transport_stream_audit" '"audit"[[:space:]]*:'
assert_matches "$transport_stream_audit" '"auditState"[[:space:]]*:'
assert_matches "$transport_stream_audit" '"constraints"[[:space:]]*:'
assert_matches "$transport_stream_audit" '"actions"[[:space:]]*:'
assert_matches "$transport_stream_audit" '"streamSummary"[[:space:]]*:'
assert_matches "$transport_stream_audit" '"subscriptionSummary"[[:space:]]*:'

transport_stream_sessions="$(run_gateway call transport.stream.sessions)"
printf '%s\n' "$transport_stream_sessions"
assert_matches "$transport_stream_sessions" '"sessions"[[:space:]]*:'
assert_matches "$transport_stream_sessions" '"subscriptions"[[:space:]]*:'
assert_matches "$transport_stream_sessions" '"runtimeModel"[[:space:]]*:'
assert_matches "$transport_stream_sessions" '"resumable"[[:space:]]*:'
assert_matches "$transport_stream_sessions" '"leaseState"[[:space:]]*:'
assert_matches "$transport_stream_sessions" '"audit"[[:space:]]*:'
assert_matches "$transport_stream_sessions" '"streamSummary"[[:space:]]*:'
assert_matches "$transport_stream_sessions" '"subscriptionSummary"[[:space:]]*:'

transport_streams="$(run_gateway call transport.streams)"
printf '%s\n' "$transport_streams"
assert_matches "$transport_streams" '"eventStreams"[[:space:]]*:'

transport_health="$(run_gateway call transport.health)"
printf '%s\n' "$transport_health"
assert_matches "$transport_health" '"health"[[:space:]]*:'
assert_matches "$transport_health" '"preferred"[[:space:]]*:'
assert_matches "$transport_health" '"phase"[[:space:]]*:'
assert_matches "$transport_health" '"policyState"[[:space:]]*:'
assert_matches "$transport_health" '"eligibleForReconnect"[[:space:]]*:'
assert_matches "$transport_health" '"remote"[[:space:]]*:'
assert_matches "$transport_health" '"reconnect"[[:space:]]*:'

transport_reconnect="$(run_gateway call transport.reconnect)"
printf '%s\n' "$transport_reconnect"
assert_matches "$transport_reconnect" '"preferred"[[:space:]]*:'
assert_matches "$transport_reconnect" '"connected"[[:space:]]*:'

echo "[gateway-regression] platform mutation assertions"
queue_out="$(run_gateway call nodes.queue)"
printf '%s\n' "$queue_out"
assert_matches "$queue_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.queue"'
assert_contains "$queue_out" '"status": "queued"'

execute_out="$(run_gateway call nodes.execute)"
printf '%s\n' "$execute_out"
assert_matches "$execute_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.execute"'
assert_matches "$execute_out" '"completed"[[:space:]]*:'
assert_matches "$execute_out" '"nodeId"[[:space:]]*:'
assert_matches "$execute_out" '"retrying"[[:space:]]*:'
assert_matches "$execute_out" '"failed"[[:space:]]*:'
assert_matches "$execute_out" '"pendingWork"[[:space:]]*:'
assert_matches "$execute_out" '"scheduler"[[:space:]]*:'
assert_matches "$execute_out" '"backlog"[[:space:]]*:'
assert_matches "$execute_out" '"platform"[[:space:]]*:'

dispatch_out="$(run_gateway call nodes.dispatch '{"nodeId":"local-gateway"}')"
printf '%s\n' "$dispatch_out"
assert_matches "$dispatch_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.dispatch"'
assert_matches "$dispatch_out" '"nodeId"[[:space:]]*:[[:space:]]*"local-gateway"'

dispatch_batch_seed_a="$(run_gateway call nodes.queue '{"kind":"generic","targetId":"local-gateway","message":"batch-a"}')"
dispatch_batch_seed_b="$(run_gateway call nodes.queue '{"kind":"generic","targetId":"local-gateway","message":"batch-b"}')"
printf '%s\n%s\n' "$dispatch_batch_seed_a" "$dispatch_batch_seed_b"
dispatch_batch_out="$(run_gateway call nodes.dispatch.batch '{"nodeId":"local-gateway","limit":2}')"
printf '%s\n' "$dispatch_batch_out"
assert_matches "$dispatch_batch_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.dispatch\.batch"'
assert_matches "$dispatch_batch_out" '"executed"[[:space:]]*:[[:space:]]*2'
assert_matches "$dispatch_batch_out" '"backlog"[[:space:]]*:'

queue_retry_out="$(run_gateway call nodes.queue '{"kind":"generic","message":"retry-me"}')"
printf '%s\n' "$queue_retry_out"
queue_retry_id="$(printf '%s\n' "$queue_retry_out" | rg -o '"id": "([^"]+)"' -r '$1' | head -n 1)"
fail_out="$(run_gateway call nodes.fail "{\"workId\":\"${queue_retry_id}\",\"error\":\"regression-fail\"}")"
printf '%s\n' "$fail_out"
assert_matches "$fail_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.fail"'
assert_contains "$fail_out" '"status": "failed"'
retry_out="$(run_gateway call nodes.retry "{\"workId\":\"${queue_retry_id}\",\"error\":\"regression-retry\"}")"
printf '%s\n' "$retry_out"
assert_matches "$retry_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.retry"'
assert_contains "$retry_out" '"lifecycleState": "retrying"'
assert_matches "$retry_out" '"recoveryState"[[:space:]]*:[[:space:]]*"scheduled"'
assert_matches "$retry_out" '"backoffMs"[[:space:]]*:'

recover_out="$(run_gateway call nodes.recover "{\"workId\":\"${queue_retry_id}\"}")"
printf '%s\n' "$recover_out"
assert_matches "$recover_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.recover"'
assert_matches "$recover_out" '"lifecycleState"[[:space:]]*:[[:space:]]*"recovered"'
assert_matches "$recover_out" '"recoveryState"[[:space:]]*:[[:space:]]*"ready"'

nodes_list_out="$(run_gateway call nodes.list)"
printf '%s\n' "$nodes_list_out"
assert_matches "$nodes_list_out" '"lifecycleState"[[:space:]]*:'
assert_matches "$nodes_list_out" '"phase"[[:space:]]*:'

nodes_start_out="$(run_gateway call nodes.start '{"nodeId":"local-gateway"}')"
printf '%s\n' "$nodes_start_out"
assert_matches "$nodes_start_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.start"'
assert_contains "$nodes_start_out" '"running": true'

nodes_restart_out="$(run_gateway call nodes.restart '{"nodeId":"local-gateway"}')"
printf '%s\n' "$nodes_restart_out"
assert_matches "$nodes_restart_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.restart"'
assert_contains "$nodes_restart_out" '"restarted": true'
assert_contains "$nodes_restart_out" '"running": true'
assert_matches "$nodes_restart_out" '"transitionCount"[[:space:]]*:'
assert_matches "$nodes_restart_out" '"restartCount"[[:space:]]*:'

nodes_stop_out="$(run_gateway call nodes.stop '{"nodeId":"local-gateway"}')"
printf '%s\n' "$nodes_stop_out"
assert_matches "$nodes_stop_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.stop"'
assert_contains "$nodes_stop_out" '"running": false'

nodes_stopped_list_out="$(run_gateway call nodes.list)"
printf '%s\n' "$nodes_stopped_list_out"
assert_contains "$nodes_stopped_list_out" '"status": "offline"'
assert_contains "$nodes_stopped_list_out" '"lifecycleState": "stopped"'

nodes_heartbeat_out="$(run_gateway call nodes.heartbeat '{"nodeId":"local-gateway","running":true}')"
printf '%s\n' "$nodes_heartbeat_out"
assert_matches "$nodes_heartbeat_out" '"method"[[:space:]]*:[[:space:]]*"nodes\.heartbeat"'
assert_contains "$nodes_heartbeat_out" '"running": true'

nodes_policy_reconcile_mutation="$(run_gateway call nodes.policy.reconcile '{"nodeId":"local-gateway","limit":1}')"
printf '%s\n' "$nodes_policy_reconcile_mutation"
assert_matches "$nodes_policy_reconcile_mutation" '"method"[[:space:]]*:[[:space:]]*"nodes\.policy\.reconcile"'
assert_matches "$nodes_policy_reconcile_mutation" '"decision"[[:space:]]*:'

device_register_out="$(run_gateway call devices.register '{"deviceId":"test-device","kind":"browser","authMode":"device-auth"}')"
printf '%s\n' "$device_register_out"
assert_matches "$device_register_out" '"method"[[:space:]]*:[[:space:]]*"devices\.register"'
assert_contains "$device_register_out" '"test-device"'
assert_matches "$device_register_out" '"authState"[[:space:]]*:[[:space:]]*"validated"'
assert_matches "$device_register_out" '"approvalState"[[:space:]]*:[[:space:]]*"approved"'
assert_matches "$device_register_out" '"phase"[[:space:]]*:[[:space:]]*"trusted"'

device_touch_out="$(run_gateway call devices.touch '{"deviceId":"test-device","authState":"refreshed","status":"active"}')"
printf '%s\n' "$device_touch_out"
assert_matches "$device_touch_out" '"method"[[:space:]]*:[[:space:]]*"devices\.touch"'
assert_matches "$device_touch_out" '"authState"[[:space:]]*:[[:space:]]*"refreshed"'
assert_matches "$device_touch_out" '"phase"[[:space:]]*:[[:space:]]*"active"'

device_unregister_out="$(run_gateway call devices.unregister '{"deviceId":"test-device"}')"
printf '%s\n' "$device_unregister_out"
assert_matches "$device_unregister_out" '"method"[[:space:]]*:[[:space:]]*"devices\.unregister"'
assert_contains "$device_unregister_out" '"deviceId": "test-device"'
assert_matches "$device_unregister_out" '"authState"[[:space:]]*:[[:space:]]*"revoked"'
assert_matches "$device_unregister_out" '"status"[[:space:]]*:[[:space:]]*"inactive"'
assert_matches "$device_unregister_out" '"phase"[[:space:]]*:[[:space:]]*"revoked"'

device_revalidate_out="$(run_gateway call devices.revalidate '{"deviceId":"test-device","authState":"validated"}')"
printf '%s\n' "$device_revalidate_out"
assert_matches "$device_revalidate_out" '"method"[[:space:]]*:[[:space:]]*"devices\.revalidate"'
assert_matches "$device_revalidate_out" '"authState"[[:space:]]*:[[:space:]]*"revalidating"'
assert_matches "$device_revalidate_out" '"approvalState"[[:space:]]*:[[:space:]]*"pending"'
assert_matches "$device_revalidate_out" '"status"[[:space:]]*:[[:space:]]*"inactive"'
assert_matches "$device_revalidate_out" '"lifecycleState"[[:space:]]*:[[:space:]]*"revalidating"'

device_approve_out="$(run_gateway call devices.approve '{"deviceId":"test-device","authState":"validated"}')"
printf '%s\n' "$device_approve_out"
assert_matches "$device_approve_out" '"method"[[:space:]]*:[[:space:]]*"devices\.approve"'
assert_matches "$device_approve_out" '"approvalState"[[:space:]]*:[[:space:]]*"approved"'
assert_matches "$device_approve_out" '"lifecycleState"[[:space:]]*:[[:space:]]*"approved"'

device_deny_out="$(run_gateway call devices.deny '{"deviceId":"test-device","reason":"regression-deny"}')"
printf '%s\n' "$device_deny_out"
assert_matches "$device_deny_out" '"method"[[:space:]]*:[[:space:]]*"devices\.deny"'
assert_matches "$device_deny_out" '"approvalState"[[:space:]]*:[[:space:]]*"denied"'
assert_matches "$device_deny_out" '"lifecycleState"[[:space:]]*:[[:space:]]*"denied"'

device_recover_out="$(run_gateway call devices.recover '{"deviceId":"test-device"}')"
printf '%s\n' "$device_recover_out"
assert_matches "$device_recover_out" '"method"[[:space:]]*:[[:space:]]*"devices\.recover"'
assert_matches "$device_recover_out" '"lifecycleState"[[:space:]]*:[[:space:]]*"recovered"'
assert_matches "$device_recover_out" '"approvalState"[[:space:]]*:[[:space:]]*"approved"'
assert_matches "$device_recover_out" '"phase"[[:space:]]*:[[:space:]]*"trusted"'

push_send_out="$(run_gateway call push.send)"
printf '%s\n' "$push_send_out"
assert_matches "$push_send_out" '"method"[[:space:]]*:[[:space:]]*"push\.send"'
assert_contains "$push_send_out" '"status": "sent"'
assert_matches "$push_send_out" '"phase"[[:space:]]*:[[:space:]]*"delivered"'

push_delivery_id="$(printf '%s\n' "$push_send_out" | rg -o '"id": "([^"]+)"' -r '$1' | head -n 1)"
push_retry_out="$(run_gateway call push.retry "{\"deliveryId\":\"${push_delivery_id}\"}")"
printf '%s\n' "$push_retry_out"
assert_matches "$push_retry_out" '"method"[[:space:]]*:[[:space:]]*"push\.retry"'
assert_contains "$push_retry_out" '"status": "retried"'
assert_matches "$push_retry_out" '"retryCount"[[:space:]]*:'
assert_matches "$push_retry_out" '"phase"[[:space:]]*:[[:space:]]*"retrying"'

push_fail_out="$(run_gateway call push.fail "{\"deliveryId\":\"${push_delivery_id}\",\"reason\":\"regression-fail\"}")"
printf '%s\n' "$push_fail_out"
assert_matches "$push_fail_out" '"method"[[:space:]]*:[[:space:]]*"push\.fail"'
assert_contains "$push_fail_out" '"status": "failed"'
assert_matches "$push_fail_out" '"phase"[[:space:]]*:[[:space:]]*"failed"'

push_recover_out="$(run_gateway call push.recover "{\"deliveryId\":\"${push_delivery_id}\",\"detail\":\"regression-recover\"}")"
printf '%s\n' "$push_recover_out"
assert_matches "$push_recover_out" '"method"[[:space:]]*:[[:space:]]*"push\.recover"'
assert_contains "$push_recover_out" '"status": "sent"'
assert_matches "$push_recover_out" '"lifecycleState"[[:space:]]*:[[:space:]]*"recovered"'
assert_matches "$push_recover_out" '"orchestrationAction"[[:space:]]*:[[:space:]]*"recover"'

push_wake_out="$(run_gateway call push.wake '{"targetId":"test-device","channel":"local","message":"wake-test"}')"
printf '%s\n' "$push_wake_out"
assert_matches "$push_wake_out" '"method"[[:space:]]*:[[:space:]]*"push\.wake"'
assert_contains "$push_wake_out" '"targetId": "test-device"'
assert_matches "$push_wake_out" '"status"[[:space:]]*:[[:space:]]*"sent"'
assert_matches "$push_wake_out" '"targetStateBefore"[[:space:]]*:[[:space:]]*"reachable"'
assert_matches "$push_wake_out" '"wokeTarget"[[:space:]]*:[[:space:]]*true'

push_orchestrate_out="$(run_gateway call push.orchestrate '{"channel":"local","limit":2}')"
printf '%s\n' "$push_orchestrate_out"
assert_matches "$push_orchestrate_out" '"method"[[:space:]]*:[[:space:]]*"push\.orchestrate"'
assert_matches "$push_orchestrate_out" '"processed"[[:space:]]*:'
assert_matches "$push_orchestrate_out" '"actions"[[:space:]]*:'

push_summary_after="$(run_gateway call push.summary)"
printf '%s\n' "$push_summary_after"
assert_matches "$push_summary_after" '"retryingDeliveries"[[:space:]]*:'
assert_matches "$push_summary_after" '"failedDeliveries"[[:space:]]*:'
assert_matches "$push_summary_after" '"recovered"[[:space:]]*:'

push_lifecycle_after="$(run_gateway call push.lifecycle)"
printf '%s\n' "$push_lifecycle_after"
assert_matches "$push_lifecycle_after" '"failedDeliveries"[[:space:]]*:'
assert_matches "$push_lifecycle_after" '"recovered"[[:space:]]*:'

channels_bindings_out="$(run_gateway call channels.bindings '{"channelId":"feishu"}')"
printf '%s\n' "$channels_bindings_out"
assert_matches "$channels_bindings_out" '"bindings"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"bindingState"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"bindingTarget"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"policyState"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"registry"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"configuredBinding"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"primed"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"autoEnabled"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"primedAtMs"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"constraints"[[:space:]]*:'
assert_matches "$channels_bindings_out" '"actions"[[:space:]]*:'

channels_policy_out="$(run_gateway call channels.policy)"
printf '%s\n' "$channels_policy_out"
assert_matches "$channels_policy_out" '"policy"[[:space:]]*:'
assert_matches "$channels_policy_out" '"byPolicyState"[[:space:]]*:'
assert_matches "$channels_policy_out" '"remediationState"[[:space:]]*:'

channels_health_out="$(run_gateway call channels.health)"
printf '%s\n' "$channels_health_out"
assert_matches "$channels_health_out" '"channels"[[:space:]]*:'
assert_matches "$channels_health_out" '"policyState"[[:space:]]*:'
assert_matches "$channels_health_out" '"byHealthState"[[:space:]]*:'
assert_matches "$channels_health_out" '"actions"[[:space:]]*:'
assert_matches "$channels_health_out" '"monitorEnabled"[[:space:]]*:'

channels_health_actions_out="$(run_gateway call channels.health.actions)"
printf '%s\n' "$channels_health_actions_out"
assert_matches "$channels_health_actions_out" '"actions"[[:space:]]*:'
assert_matches "$channels_health_actions_out" '"policyState"[[:space:]]*:'
assert_matches "$channels_health_actions_out" '"byHealthState"[[:space:]]*:'

channels_probe_out="$(run_gateway call channels.status '{"probe":true,"timeoutMs":2345}')"
printf '%s\n' "$channels_probe_out"
assert_matches "$channels_probe_out" '"probe"[[:space:]]*:[[:space:]]*true'
assert_matches "$channels_probe_out" '"timeoutMs"[[:space:]]*:[[:space:]]*2345'
assert_matches "$channels_probe_out" '"channelOrder"[[:space:]]*:'
assert_matches "$channels_probe_out" '"channelLabels"[[:space:]]*:'
assert_matches "$channels_probe_out" '"channelDetailLabels"[[:space:]]*:'
assert_matches "$channels_probe_out" '"channelSystemImages"[[:space:]]*:'
assert_matches "$channels_probe_out" '"channelMeta"[[:space:]]*:'
assert_matches "$channels_probe_out" '"channelAccounts"[[:space:]]*:'
assert_matches "$channels_probe_out" '"channelDefaultAccountId"[[:space:]]*:'
assert_matches "$channels_probe_out" '"runtime"[[:space:]]*:'
assert_matches "$channels_probe_out" '"defaultAccount"[[:space:]]*:'
assert_matches "$channels_probe_out" '"lastProbeAtMs"[[:space:]]*:'
assert_matches "$channels_probe_out" '"audit"[[:space:]]*:'
assert_contains "$channels_probe_out" '"telegram"'
assert_contains "$channels_probe_out" '"slack"'
assert_contains "$channels_probe_out" '"discord"'

channels_runtime_out="$(run_gateway call channels.runtime)"
printf '%s\n' "$channels_runtime_out"
assert_matches "$channels_runtime_out" '"runtime"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"bootstrap"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"bootstrapped"[[:space:]]*:[[:space:]]*true'
assert_matches "$channels_runtime_out" '"configuredBindingCount"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"primedBindingCount"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"configuredBindings"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"primedBindings"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"accounts"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"channelId"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"startCount"[[:space:]]*:'
assert_matches "$channels_runtime_out" '"restartCount"[[:space:]]*:'

channels_manager_out="$(run_gateway call channels.manager)"
printf '%s\n' "$channels_manager_out"
assert_matches "$channels_manager_out" '"manager"[[:space:]]*:'
assert_matches "$channels_manager_out" '"monitorEnabledCount"[[:space:]]*:'
assert_matches "$channels_manager_out" '"manualStopCount"[[:space:]]*:'
assert_matches "$channels_manager_out" '"taskState"[[:space:]]*:'
assert_matches "$channels_manager_out" '"restartBudgetState"[[:space:]]*:'

channels_logout_out="$(run_gateway call channels.logout '{"channelId":"feishu","accountId":"feishu:default"}')"
printf '%s\n' "$channels_logout_out"
assert_matches "$channels_logout_out" '"cleared"[[:space:]]*:[[:space:]]*true'
assert_matches "$channels_logout_out" '"accountId"[[:space:]]*:[[:space:]]*"feishu:default"'
assert_matches "$channels_logout_out" '"lifecycleState"[[:space:]]*:[[:space:]]*"stopped"'
assert_matches "$channels_logout_out" '"manualStop"[[:space:]]*:[[:space:]]*true'
assert_matches "$channels_logout_out" '"phase"[[:space:]]*:[[:space:]]*"idle"'

plugins_bindings_out="$(run_gateway call plugins.bindings)"
printf '%s\n' "$plugins_bindings_out"
assert_matches "$plugins_bindings_out" '"bindings"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"bindingState"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"activeChannelIds"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"defaultAccountId"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"policyState"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"registry"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"configuredBinding"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"primed"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"autoEnabled"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"primedAtMs"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"constraints"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"actions"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"configuredAccountIds"[[:space:]]*:'
assert_matches "$plugins_bindings_out" '"configuredAccountCount"[[:space:]]*:'
assert_contains "$plugins_bindings_out" '"metis-fixture"'
assert_contains "$plugins_bindings_out" '"fixture:default"'
assert_contains "$plugins_bindings_out" '"defaultAccountId": "fixture:default"'

fixture_channel_bindings_out="$(run_gateway call channels.bindings '{"channelId":"metis-fixture"}')"
printf '%s\n' "$fixture_channel_bindings_out"
assert_contains "$fixture_channel_bindings_out" '"metis-fixture"'
assert_contains "$fixture_channel_bindings_out" '"configuredAccountIds"'
assert_contains "$fixture_channel_bindings_out" '"defaultAccountId": "fixture:default"'

plugins_policy_out="$(run_gateway call plugins.policy)"
printf '%s\n' "$plugins_policy_out"
assert_matches "$plugins_policy_out" '"policy"[[:space:]]*:'
assert_matches "$plugins_policy_out" '"byPolicyState"[[:space:]]*:'
assert_matches "$plugins_policy_out" '"remediationState"[[:space:]]*:'

plugins_health_out="$(run_gateway call plugins.health)"
printf '%s\n' "$plugins_health_out"
assert_matches "$plugins_health_out" '"plugins"[[:space:]]*:'
assert_matches "$plugins_health_out" '"policyState"[[:space:]]*:'
assert_matches "$plugins_health_out" '"byHealthState"[[:space:]]*:'
assert_matches "$plugins_health_out" '"actions"[[:space:]]*:'

plugins_health_actions_out="$(run_gateway call plugins.health.actions)"
printf '%s\n' "$plugins_health_actions_out"
assert_matches "$plugins_health_actions_out" '"actions"[[:space:]]*:'
assert_matches "$plugins_health_actions_out" '"policyState"[[:space:]]*:'
assert_matches "$plugins_health_actions_out" '"byHealthState"[[:space:]]*:'

plugins_probe_out="$(run_gateway call plugins.status '{"probe":true,"timeoutMs":3456}')"
printf '%s\n' "$plugins_probe_out"
assert_matches "$plugins_probe_out" '"probe"[[:space:]]*:[[:space:]]*true'
assert_matches "$plugins_probe_out" '"timeoutMs"[[:space:]]*:[[:space:]]*3456'
assert_matches "$plugins_probe_out" '"pluginOrder"[[:space:]]*:'
assert_matches "$plugins_probe_out" '"pluginMeta"[[:space:]]*:'
assert_matches "$plugins_probe_out" '"pluginAccounts"[[:space:]]*:'
assert_contains "$plugins_probe_out" '"metis-fixture"'
assert_contains "$plugins_probe_out" '"fixture:default"'

plugins_get_out="$(run_gateway call plugins.get)"
printf '%s\n' "$plugins_get_out"
assert_matches "$plugins_get_out" '"plugin"[[:space:]]*:'
assert_matches "$plugins_get_out" '"approval"[[:space:]]*:'
assert_matches "$plugins_get_out" '"packageProbe"[[:space:]]*:'
assert_matches "$plugins_get_out" '"setup"[[:space:]]*:'
assert_contains "$plugins_get_out" '"compatibilityMode": "legacy-plugin-host"'
assert_contains "$plugins_get_out" '"defaultAccountId": "fixture:default"'

plugins_package_state_out="$(run_gateway call plugins.package_state)"
printf '%s\n' "$plugins_package_state_out"
assert_matches "$plugins_package_state_out" '"items"[[:space:]]*:'
assert_matches "$plugins_package_state_out" '"packageProbe"[[:space:]]*:'
assert_contains "$plugins_package_state_out" '"metis-fixture"'

plugins_setup_out="$(run_gateway call plugins.setup)"
printf '%s\n' "$plugins_setup_out"
assert_matches "$plugins_setup_out" '"items"[[:space:]]*:'
assert_matches "$plugins_setup_out" '"setup"[[:space:]]*:'
assert_contains "$plugins_setup_out" '"metis-fixture"'

plugins_setup_apply_out="$(run_gateway call plugins.setup.apply '{}')"
printf '%s\n' "$plugins_setup_apply_out"
assert_matches "$plugins_setup_apply_out" '"items"[[:space:]]*:'
assert_matches "$plugins_setup_apply_out" '"count"[[:space:]]*:'
assert_matches "$plugins_setup_apply_out" '"state"[[:space:]]*:'
assert_contains "$plugins_setup_apply_out" '"metis-fixture"'
assert_contains "$plugins_setup_apply_out" '"applied": true'

plugins_setup_registry_out="$(run_gateway call plugins.setup.registry '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_setup_registry_out"
assert_matches "$plugins_setup_registry_out" '"setupRegistry"[[:space:]]*:'
assert_contains "$plugins_setup_registry_out" '"supported": true'

plugins_runtime_forwarders_out="$(run_gateway call plugins.runtime.forwarders '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_runtime_forwarders_out"
assert_matches "$plugins_runtime_forwarders_out" '"runtimeForwarders"[[:space:]]*:'
assert_contains "$plugins_runtime_forwarders_out" '"dispatchAction": true'

plugins_resolve_account_out="$(run_gateway call plugins.resolve_account '{"pluginId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$plugins_resolve_account_out"
assert_contains "$plugins_resolve_account_out" '"accountId": "fixture:default"'
assert_contains "$plugins_resolve_account_out" '"configured": true'

plugins_directory_out="$(run_gateway call plugins.directory '{"pluginId":"metis-fixture","accountId":"fixture:default","groupId":"fixture-group"}')"
printf '%s\n' "$plugins_directory_out"
assert_contains "$plugins_directory_out" '"fixture-peer"'
assert_contains "$plugins_directory_out" '"fixture-group"'

plugins_targets_out="$(run_gateway call plugins.targets '{"pluginId":"metis-fixture","accountId":"fixture:default","target":"fixture-peer"}')"
printf '%s\n' "$plugins_targets_out"
assert_contains "$plugins_targets_out" '"resolved": true'
assert_contains "$plugins_targets_out" '"targetKind": "peer"'

plugins_dispatch_out="$(run_gateway call plugins.actions.dispatch '{"pluginId":"metis-fixture","accountId":"fixture:default","action":"fixture-send-text","payload":{"text":"hello-from-gateway-dispatch"}}')"
printf '%s\n' "$plugins_dispatch_out"
assert_contains "$plugins_dispatch_out" '"dispatched": true'
assert_contains "$plugins_dispatch_out" '"echoedText": "hello-from-gateway-dispatch"'

plugins_runtime_out="$(run_gateway call plugins.runtime)"
printf '%s\n' "$plugins_runtime_out"
assert_matches "$plugins_runtime_out" '"runtime"[[:space:]]*:'
assert_matches "$plugins_runtime_out" '"bootstrap"[[:space:]]*:'
assert_matches "$plugins_runtime_out" '"configuredBindingCount"[[:space:]]*:'
assert_matches "$plugins_runtime_out" '"primedBindingCount"[[:space:]]*:'
assert_contains "$plugins_runtime_out" '"metis-fixture"'

plugins_manager_out="$(run_gateway call plugins.manager)"
printf '%s\n' "$plugins_manager_out"
assert_matches "$plugins_manager_out" '"manager"[[:space:]]*:'
assert_matches "$plugins_manager_out" '"monitorEnabledCount"[[:space:]]*:'
assert_matches "$plugins_manager_out" '"manualStopCount"[[:space:]]*:'
assert_contains "$plugins_manager_out" '"metis-fixture"'

discover_detail_out="$(run_gateway call discover.detail)"
printf '%s\n' "$discover_detail_out"
assert_matches "$discover_detail_out" '"channelCatalog"[[:space:]]*:'
assert_matches "$discover_detail_out" '"pluginCatalog"[[:space:]]*:'
assert_contains "$discover_detail_out" '"telegram"'
assert_contains "$discover_detail_out" '"slack"'
assert_contains "$discover_detail_out" '"discord"'
assert_contains "$discover_detail_out" '"metis-fixture"'

probe_actions_out="$(run_gateway call probe.actions)"
printf '%s\n' "$probe_actions_out"
assert_matches "$probe_actions_out" '"actions"[[:space:]]*:'
assert_matches "$probe_actions_out" '"method"[[:space:]]*:'
assert_matches "$probe_actions_out" '"policyState"[[:space:]]*:'
assert_matches "$probe_actions_out" '"constraints"[[:space:]]*:'
assert_matches "$probe_actions_out" '"transport"[[:space:]]*:'
assert_matches "$probe_actions_out" '"http"[[:space:]]*:'
assert_matches "$probe_actions_out" '"platform"[[:space:]]*:'
assert_matches "$probe_actions_out" '"controlUi"[[:space:]]*:'

probe_remediation_out="$(run_gateway call probe.remediation)"
printf '%s\n' "$probe_remediation_out"
assert_matches "$probe_remediation_out" '"remediation"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"policyState"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"remediationState"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"blockingCount"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"issueCodes"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"transport"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"http"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"platform"[[:space:]]*:'
assert_matches "$probe_remediation_out" '"controlUi"[[:space:]]*:'

doctor_actions_out="$(run_gateway call doctor.actions)"
printf '%s\n' "$doctor_actions_out"
assert_matches "$doctor_actions_out" '"actions"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"summary"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"policyState"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"constraints"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"runtime"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"transport"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"http"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"platform"[[:space:]]*:'
assert_matches "$doctor_actions_out" '"controlUi"[[:space:]]*:'

doctor_remediation_out="$(run_gateway call doctor.remediation)"
printf '%s\n' "$doctor_remediation_out"
assert_matches "$doctor_remediation_out" '"remediation"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"policyState"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"remediationState"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"blockingCount"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"issueCodes"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"runtime"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"transport"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"http"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"platform"[[:space:]]*:'
assert_matches "$doctor_remediation_out" '"controlUi"[[:space:]]*:'

echo "[gateway-regression] http healthz"
healthz="$(curl -fsS http://127.0.0.1:${GATEWAY_PORT}/healthz)"
printf '%s\n' "$healthz"
assert_matches "$healthz" '"ok"[[:space:]]*:[[:space:]]*true'
assert_matches "$healthz" '"status"[[:space:]]*:[[:space:]]*"live"'
assert_matches "$healthz" '"gateway"[[:space:]]*:'

echo "[gateway-regression] http health alias"
health_alias="$(curl -fsS http://127.0.0.1:${GATEWAY_PORT}/health)"
printf '%s\n' "$health_alias"
assert_matches "$health_alias" '"ok"[[:space:]]*:[[:space:]]*true'
assert_matches "$health_alias" '"status"[[:space:]]*:[[:space:]]*"live"'

echo "[gateway-regression] http readyz"
readyz="$(curl -fsS http://127.0.0.1:${GATEWAY_PORT}/readyz)"
printf '%s\n' "$readyz"
assert_matches "$readyz" '"ready"[[:space:]]*:'
assert_matches "$readyz" '"ok"[[:space:]]*:'
assert_matches "$readyz" '"status"[[:space:]]*:'
assert_matches "$readyz" '"gateway"[[:space:]]*:'

echo "[gateway-regression] http ready alias"
ready_alias="$(curl -fsS http://127.0.0.1:${GATEWAY_PORT}/ready)"
printf '%s\n' "$ready_alias"
assert_matches "$ready_alias" '"ready"[[:space:]]*:'
assert_matches "$ready_alias" '"status"[[:space:]]*:'

echo "[gateway-regression] http probe post rejected"
probe_post_headers="$(mktemp)"
probe_post_body="$(mktemp)"
curl -sS -D "$probe_post_headers" -o "$probe_post_body" -X POST http://127.0.0.1:${GATEWAY_PORT}/healthz >/dev/null
assert_contains "$(cat "$probe_post_headers")" '405'
assert_contains "$(cat "$probe_post_headers")" 'Allow: GET, HEAD'
assert_contains "$(cat "$probe_post_body")" 'Method Not Allowed'
rm -f "$probe_post_headers" "$probe_post_body"

echo "[gateway-regression] http readyz head"
readyz_head_headers="$(mktemp)"
readyz_head_body="$(mktemp)"
curl -sS -D "$readyz_head_headers" -o "$readyz_head_body" -I http://127.0.0.1:${GATEWAY_PORT}/readyz >/dev/null
assert_contains "$(cat "$readyz_head_headers")" '200'
if [[ -s "$readyz_head_body" ]]; then
  echo "expected empty HEAD /readyz body" >&2
  exit 1
fi
rm -f "$readyz_head_headers" "$readyz_head_body"

echo "[gateway-regression] http rpc"
rpc_body="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/rpc -H 'content-type: application/json' -d '{"protocolVersion":"2025-03-26","requestId":"http-rpc-1","method":"connect.status","params":{},"connect":{"client":{"id":"http-test","name":"http-test","mode":"http","version":"1.0"},"transport":"local","transportKind":"local","gatewayUrl":"local://gateway","requestedAtMs":1}}')"
printf '%s\n' "$rpc_body"
assert_matches "$rpc_body" '"ok"[[:space:]]*:[[:space:]]*true'
assert_matches "$rpc_body" '"method"[[:space:]]*:[[:space:]]*"connect\.status"'

echo "[gateway-regression] cli routes to running gateway"
remote_cli_status="$(run_gateway call connect.status)"
printf '%s\n' "$remote_cli_status"
assert_matches "$remote_cli_status" '"bindMode"[[:space:]]*:[[:space:]]*"loopback"'

echo "[gateway-regression] remote control-ui start"
remote_control_ui_start="$(run_gateway call control_ui.start)"
printf '%s\n' "$remote_control_ui_start"
assert_matches "$remote_control_ui_start" '"started"[[:space:]]*:[[:space:]]*true'

remote_control_ui_status="$(run_gateway call control_ui.status)"
printf '%s\n' "$remote_control_ui_status"
assert_matches "$remote_control_ui_status" '"started"[[:space:]]*:[[:space:]]*true'

echo "[gateway-regression] remote control-ui reload"
remote_control_ui_reload="$(run_gateway call control_ui.reload)"
printf '%s\n' "$remote_control_ui_reload"
assert_matches "$remote_control_ui_reload" '"reloaded"[[:space:]]*:[[:space:]]*true'
assert_contains "$remote_control_ui_reload" '"started": true'

remote_channels_status="$(run_gateway call channels.status '{"probe":true,"timeoutMs":4567}')"
printf '%s\n' "$remote_channels_status"
assert_matches "$remote_channels_status" '"channelAccounts"[[:space:]]*:'
assert_matches "$remote_channels_status" '"accountId"[[:space:]]*:'
assert_matches "$remote_channels_status" '"runtime"[[:space:]]*:'
assert_matches "$remote_channels_status" '"timeoutMs"[[:space:]]*:[[:space:]]*4567'

remote_channels_runtime="$(run_gateway call channels.runtime)"
printf '%s\n' "$remote_channels_runtime"
assert_matches "$remote_channels_runtime" '"bootstrap"[[:space:]]*:'
assert_matches "$remote_channels_runtime" '"bootstrapped"[[:space:]]*:[[:space:]]*true'
assert_matches "$remote_channels_runtime" '"accounts"[[:space:]]*:'
assert_matches "$remote_channels_runtime" '"startCount"[[:space:]]*:'
assert_matches "$remote_channels_runtime" '"running"[[:space:]]*:'
assert_matches "$remote_channels_runtime" '"manualStop"[[:space:]]*:[[:space:]]*false'

remote_transport_connections="$(run_gateway call transport.connections)"
printf '%s\n' "$remote_transport_connections"
assert_matches "$remote_transport_connections" '"connections"[[:space:]]*:'
assert_matches "$remote_transport_connections" '"transport"[[:space:]]*:'

remote_transport_subscriptions="$(run_gateway call transport.subscriptions)"
printf '%s\n' "$remote_transport_subscriptions"
assert_matches "$remote_transport_subscriptions" '"eventSubscriptions"[[:space:]]*:'

remote_connect_stream="$(run_gateway call connect.stream '{"clientId":"metis-cli","limit":1,"waitMs":25}')"
printf '%s\n' "$remote_connect_stream"
assert_matches "$remote_connect_stream" '"stream"[[:space:]]*:'
assert_matches "$remote_connect_stream" '"waitMs"[[:space:]]*:[[:space:]]*25'
assert_matches "$remote_connect_stream" '"mode"[[:space:]]*:[[:space:]]*"long-poll"'
assert_matches "$remote_connect_stream" '"phase"[[:space:]]*:'

remote_connect_stream_status="$(run_gateway call connect.stream.status '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_connect_stream_status"
assert_matches "$remote_connect_stream_status" '"stream"[[:space:]]*:'
assert_matches "$remote_connect_stream_status" '"leaseExpiresAtMs"[[:space:]]*:'
assert_matches "$remote_connect_stream_status" '"streamId"[[:space:]]*:'
assert_matches "$remote_connect_stream_status" '"attachCount"[[:space:]]*:'

remote_connect_stream_keepalive="$(run_gateway call connect.stream.keepalive '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_connect_stream_keepalive"
assert_matches "$remote_connect_stream_keepalive" '"keepalive"[[:space:]]*:[[:space:]]*true'

remote_connect_stream_attach="$(run_gateway call connect.stream.attach '{"clientId":"metis-cli","waitMs":0}')"
printf '%s\n' "$remote_connect_stream_attach"
assert_matches "$remote_connect_stream_attach" '"attached"[[:space:]]*:[[:space:]]*true'
assert_matches "$remote_connect_stream_attach" '"sessionMode"[[:space:]]*:[[:space:]]*"persistent-session"'
remote_stream_generation="$(extract_json_number "$remote_connect_stream_attach" "sessionGeneration")"
remote_stream_id="$(extract_json_string "$remote_connect_stream_attach" "streamId")"

remote_connect_stream_detach="$(run_gateway call connect.stream.detach '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_connect_stream_detach"
assert_contains "$remote_connect_stream_detach" "\"sessionGeneration\": ${remote_stream_generation}"
assert_contains "$remote_connect_stream_detach" "\"streamId\": \"${remote_stream_id}\""

remote_connect_stream_detached_status="$(run_gateway call connect.stream.status '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_connect_stream_detached_status"
assert_contains "$remote_connect_stream_detached_status" "\"sessionGeneration\": ${remote_stream_generation}"
assert_contains "$remote_connect_stream_detached_status" "\"streamId\": \"${remote_stream_id}\""
assert_matches "$remote_connect_stream_detached_status" '"phase"[[:space:]]*:[[:space:]]*"detached"'

remote_connect_stream_resume="$(run_gateway call connect.stream.resume '{"clientId":"metis-cli","limit":1}')"
printf '%s\n' "$remote_connect_stream_resume"
assert_matches "$remote_connect_stream_resume" '"resumed"[[:space:]]*:[[:space:]]*true'

remote_connect_stream_next="$(run_gateway call connect.stream.next '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_connect_stream_next"
assert_matches "$remote_connect_stream_next" '"next"[[:space:]]*:[[:space:]]*true'

remote_connect_stream_push="$(run_gateway call connect.stream.push '{"clientId":"metis-cli","detail":"remote-regression-push"}')"
printf '%s\n' "$remote_connect_stream_push"
assert_matches "$remote_connect_stream_push" '"pushed"[[:space:]]*:[[:space:]]*true'
assert_matches "$remote_connect_stream_push" '"pendingPushCount"[[:space:]]*:'

sleep 2
remote_connect_stream_expired="$(run_gateway call connect.stream.status '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_connect_stream_expired"
assert_matches "$remote_connect_stream_expired" '"active"[[:space:]]*:[[:space:]]*false'

remote_connect_stream_close="$(run_gateway call connect.stream.close '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_connect_stream_close"
assert_matches "$remote_connect_stream_close" '"closed"[[:space:]]*:[[:space:]]*true'

echo "[gateway-regression] remote stream wakeup"
run_gateway call connect.stream '{"clientId":"stream-remote","limit":1,"waitMs":0}' >/dev/null
stream_remote_status="$(run_gateway call connect.stream.status '{"clientId":"stream-remote"}')"
stream_remote_cursor="$(extract_json_string "$stream_remote_status" "lastCursor")"
stream_remote_out="$(mktemp /tmp/gateway-stream-remote.XXXXXX)"
run_gateway call connect.stream "{\"clientId\":\"stream-remote\",\"limit\":8,\"waitMs\":300,\"sinceId\":\"${stream_remote_cursor}\"}" >"$stream_remote_out" &
stream_remote_pid=$!
sleep 0.05
run_gateway call connect.stream.push '{"clientId":"stream-remote","kind":"stream.push","detail":"remote-wakeup"}' >/dev/null
wait "$stream_remote_pid"
stream_remote_wakeup="$(cat "$stream_remote_out")"
rm -f "$stream_remote_out"
printf '%s\n' "$stream_remote_wakeup"
assert_matches "$stream_remote_wakeup" '"serverPushCapable"[[:space:]]*:[[:space:]]*true'
assert_matches "$stream_remote_wakeup" '"mode"[[:space:]]*:'
assert_contains "$stream_remote_wakeup" 'remote-wakeup'

echo "[gateway-regression] remote seeded push session"
remote_seed_push="$(run_gateway call connect.stream.push '{"clientId":"stream-seeded","kind":"stream.push","detail":"seeded-push"}')"
printf '%s\n' "$remote_seed_push"
assert_matches "$remote_seed_push" '"pushed"[[:space:]]*:[[:space:]]*true'
assert_matches "$remote_seed_push" '"streamId"[[:space:]]*:[[:space:]]*"str-'
remote_seed_status="$(run_gateway call connect.stream.status '{"clientId":"stream-seeded"}')"
printf '%s\n' "$remote_seed_status"
assert_matches "$remote_seed_status" '"sessionMode"[[:space:]]*:[[:space:]]*"persistent-session"'
assert_matches "$remote_seed_status" '"streamId"[[:space:]]*:[[:space:]]*"str-'
assert_matches "$remote_seed_status" '"phase"[[:space:]]*:[[:space:]]*"queued"'

echo "[gateway-regression] remote transport reconnect"
remote_transport_reconnect="$(run_gateway call transport.reconnect)"
printf '%s\n' "$remote_transport_reconnect"
assert_matches "$remote_transport_reconnect" '"connected"[[:space:]]*:[[:space:]]*true'

remote_transport_reconnect_history="$(run_gateway call transport.reconnect.history)"
printf '%s\n' "$remote_transport_reconnect_history"
assert_matches "$remote_transport_reconnect_history" '"lifecycle"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_history" '"reconnectState"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_history" '"remote"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_history" '"reconnect"[[:space:]]*:'

remote_transport_reconnect_state="$(run_gateway call transport.reconnect.state)"
printf '%s\n' "$remote_transport_reconnect_state"
assert_matches "$remote_transport_reconnect_state" '"state"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_state" '"transitionCount"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_state" '"phase"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_state" '"cooldownRemainingMs"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_state" '"remote"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_state" '"reconnect"[[:space:]]*:'

remote_transport_reconnect_window="$(run_gateway call transport.reconnect.window)"
printf '%s\n' "$remote_transport_reconnect_window"
assert_matches "$remote_transport_reconnect_window" '"window"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_window" '"cooldownRemainingMs"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_window" '"remote"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_window" '"reconnect"[[:space:]]*:'

remote_transport_reconnect_plan="$(run_gateway call transport.reconnect.plan)"
printf '%s\n' "$remote_transport_reconnect_plan"
assert_matches "$remote_transport_reconnect_plan" '"plan"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_plan" '"phase"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_plan" '"remote"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_plan" '"reconnect"[[:space:]]*:'

remote_transport_reconnect_audit="$(run_gateway call transport.reconnect.audit)"
printf '%s\n' "$remote_transport_reconnect_audit"
assert_matches "$remote_transport_reconnect_audit" '"audit"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_audit" '"auditState"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_audit" '"remote"[[:space:]]*:'
assert_matches "$remote_transport_reconnect_audit" '"reconnect"[[:space:]]*:'

remote_transport_reconnect_reset="$(run_gateway call transport.reconnect.reset)"
printf '%s\n' "$remote_transport_reconnect_reset"
assert_matches "$remote_transport_reconnect_reset" '"reset"[[:space:]]*:[[:space:]]*true'

echo "[gateway-regression] remote auto reconnect on request"
remote_disconnect_for_reconnect="$(run_gateway call connect.disconnect '{"clientId":"metis-cli"}')"
printf '%s\n' "$remote_disconnect_for_reconnect"
assert_matches "$remote_disconnect_for_reconnect" '"disconnected"[[:space:]]*:[[:space:]]*true'
remote_auto_reconnect_status="$(run_gateway call connect.status)"
printf '%s\n' "$remote_auto_reconnect_status"
assert_matches "$remote_auto_reconnect_status" '"bindMode"[[:space:]]*:[[:space:]]*"loopback"'
remote_auto_reconnect_state="$(run_gateway call transport.reconnect.state)"
printf '%s\n' "$remote_auto_reconnect_state"
assert_matches "$remote_auto_reconnect_state" '"connected"[[:space:]]*:[[:space:]]*true'
assert_matches "$remote_auto_reconnect_state" '"phase"[[:space:]]*:'

echo "[gateway-regression] http mcp"
mcp_body="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')"
printf '%s\n' "$mcp_body"
assert_matches "$mcp_body" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_matches "$mcp_body" '"tools"[[:space:]]*:'
assert_contains "$mcp_body" 'gateway.nodes.restart'
assert_contains "$mcp_body" 'gateway.nodes.policy.audit'
assert_contains "$mcp_body" 'gateway.nodes.policy.reconcile'
assert_contains "$mcp_body" 'gateway.devices.unregister'
assert_contains "$mcp_body" 'gateway.devices.policy.audit'
assert_contains "$mcp_body" 'gateway.devices.approve'
assert_contains "$mcp_body" 'gateway.devices.deny'
assert_contains "$mcp_body" 'gateway.push.retry'
assert_contains "$mcp_body" 'gateway.push.orchestration.audit'
assert_contains "$mcp_body" 'gateway.push.orchestration.actions'
assert_contains "$mcp_body" 'gateway.push.orchestrate'
assert_contains "$mcp_body" 'gateway.canvas.audit'
assert_contains "$mcp_body" 'gateway.canvas.actions'
assert_contains "$mcp_body" 'gateway.talk.audit'
assert_contains "$mcp_body" 'gateway.talk.actions'
assert_contains "$mcp_body" 'gateway.readiness'
assert_contains "$mcp_body" 'gateway.config.get'
assert_contains "$mcp_body" 'gateway.config.schema.lookup'
assert_contains "$mcp_body" 'gateway.http.status'
assert_contains "$mcp_body" 'gateway.http.start'
assert_contains "$mcp_body" 'gateway.transport.runtime'
assert_contains "$mcp_body" 'gateway.transport.remote'
assert_contains "$mcp_body" 'gateway.transport.lifecycle'
assert_contains "$mcp_body" 'gateway.transport.reconnect.history'
assert_contains "$mcp_body" 'gateway.transport.reconnect.state'
assert_contains "$mcp_body" 'gateway.transport.reconnect.window'
assert_contains "$mcp_body" 'gateway.transport.reconnect.plan'
assert_contains "$mcp_body" 'gateway.transport.reconnect.audit'
assert_contains "$mcp_body" 'gateway.transport.reconnect.reset'
assert_contains "$mcp_body" 'gateway.transport.stream.health'
assert_contains "$mcp_body" 'gateway.transport.stream.audit'
assert_contains "$mcp_body" 'gateway.transport.reconnect'
assert_contains "$mcp_body" 'gateway.connect.lifecycle'
assert_contains "$mcp_body" 'gateway.connect.actions'
assert_contains "$mcp_body" 'gateway.connect.stream.status'
assert_contains "$mcp_body" 'gateway.connect.stream.open'
assert_contains "$mcp_body" 'gateway.connect.stream.attach'
assert_contains "$mcp_body" 'gateway.connect.stream.detach'
assert_contains "$mcp_body" 'gateway.connect.stream.keepalive'
assert_contains "$mcp_body" 'gateway.connect.stream.resume'
assert_contains "$mcp_body" 'gateway.connect.stream.next'
assert_contains "$mcp_body" 'gateway.connect.stream.push'
assert_contains "$mcp_body" 'gateway.connect.stream.close'
assert_contains "$mcp_body" 'gateway.agent.health'
assert_contains "$mcp_body" 'gateway.agent.actions'
assert_contains "$mcp_body" 'gateway.agent.routing'
assert_contains "$mcp_body" 'gateway.channels.bindings'
assert_contains "$mcp_body" 'gateway.channels.policy'
assert_contains "$mcp_body" 'gateway.channels.manager'
assert_contains "$mcp_body" 'gateway.channels.health.actions'
assert_contains "$mcp_body" 'gateway.channels.start'
assert_contains "$mcp_body" 'gateway.channels.stop'
assert_contains "$mcp_body" 'gateway.channels.send'
assert_contains "$mcp_body" 'gateway.channels.logout'
assert_contains "$mcp_body" 'gateway.plugins.bindings'
assert_contains "$mcp_body" 'gateway.plugins.policy'
assert_contains "$mcp_body" 'gateway.plugins.manager'
assert_contains "$mcp_body" 'gateway.plugins.health.actions'
assert_contains "$mcp_body" 'gateway.plugins.actions'
assert_contains "$mcp_body" 'gateway.plugins.setup.apply'
assert_contains "$mcp_body" 'gateway.plugins.setup.registry'
assert_contains "$mcp_body" 'gateway.plugins.runtime.forwarders'
assert_contains "$mcp_body" 'gateway.plugins.resolve_account'
assert_contains "$mcp_body" 'gateway.plugins.directory'
assert_contains "$mcp_body" 'gateway.plugins.targets'
assert_contains "$mcp_body" 'gateway.plugins.actions.dispatch'
assert_contains "$mcp_body" 'gateway.plugins.start'
assert_contains "$mcp_body" 'gateway.plugins.stop'
assert_contains "$mcp_body" 'gateway.plugins.send'
assert_contains "$mcp_body" 'gateway.plugins.logout'
assert_contains "$mcp_body" 'gateway.control_ui.status'
assert_contains "$mcp_body" 'gateway.control_ui.contract'
assert_contains "$mcp_body" 'gateway.control_ui.routes'
assert_contains "$mcp_body" 'gateway.control_ui.stop'
assert_contains "$mcp_body" 'gateway.control_ui.reload'
assert_contains "$mcp_body" 'gateway.control_ui.binding'
assert_contains "$mcp_body" 'gateway.control_ui.runtime'
assert_contains "$mcp_body" 'gateway.control_ui.auth'
assert_contains "$mcp_body" 'gateway.control_ui.state'
assert_contains "$mcp_body" 'gateway.control_ui.origin_policy'
assert_contains "$mcp_body" 'gateway.control_ui.health'
assert_contains "$mcp_body" 'gateway.control_ui.assets'
assert_contains "$mcp_body" 'gateway.control_ui.start'
assert_contains "$mcp_body" 'gateway.webchat.status'
assert_contains "$mcp_body" 'gateway.webchat.start'
assert_contains "$mcp_body" 'gateway.webchat.reload'
assert_contains "$mcp_body" 'gateway.probe'
assert_contains "$mcp_body" 'gateway.probe.actions'
assert_contains "$mcp_body" 'gateway.probe.remediation'
assert_contains "$mcp_body" 'gateway.doctor.actions'
assert_contains "$mcp_body" 'gateway.doctor.remediation'

echo "[gateway-regression] http mcp tools/call"
mcp_nodes_restart="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"gateway.nodes.restart","arguments":{"nodeId":"local-gateway"}}}')"
printf '%s\n' "$mcp_nodes_restart"
assert_matches "$mcp_nodes_restart" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_nodes_restart" '"restarted": true'

mcp_nodes_policy_reconcile="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"gateway.nodes.policy.reconcile","arguments":{"nodeId":"local-gateway","limit":1}}}')"
printf '%s\n' "$mcp_nodes_policy_reconcile"
assert_matches "$mcp_nodes_policy_reconcile" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_nodes_policy_reconcile" '"decision"'

mcp_nodes_policy_audit="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"gateway.nodes.policy.audit","arguments":{}}}')"
printf '%s\n' "$mcp_nodes_policy_audit"
assert_matches "$mcp_nodes_policy_audit" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_nodes_policy_audit" '"actionsNeeded"'

mcp_devices_unregister="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"gateway.devices.unregister","arguments":{"deviceId":"browser-control-ui"}}}')"
printf '%s\n' "$mcp_devices_unregister"
assert_matches "$mcp_devices_unregister" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_devices_unregister" '"deviceId": "browser-control-ui"'

mcp_devices_approve="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"gateway.devices.approve","arguments":{"deviceId":"browser-control-ui","authState":"validated"}}}')"
printf '%s\n' "$mcp_devices_approve"
assert_matches "$mcp_devices_approve" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_devices_approve" '"approvalState": "approved"'

mcp_devices_deny="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":32,"method":"tools/call","params":{"name":"gateway.devices.deny","arguments":{"deviceId":"browser-control-ui","reason":"mcp-deny"}}}')"
printf '%s\n' "$mcp_devices_deny"
assert_matches "$mcp_devices_deny" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_devices_deny" '"approvalState": "denied"'

mcp_devices_policy_audit="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":33,"method":"tools/call","params":{"name":"gateway.devices.policy.audit","arguments":{}}}')"
printf '%s\n' "$mcp_devices_policy_audit"
assert_matches "$mcp_devices_policy_audit" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_devices_policy_audit" '"actionsNeeded"'

mcp_push_send_for_retry="$(run_gateway call push.send)"
push_retry_id="$(printf '%s\n' "$mcp_push_send_for_retry" | rg -o '"id": "([^"]+)"' -r '$1' | head -n 1)"
mcp_push_retry="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.push.retry\",\"arguments\":{\"deliveryId\":\"${push_retry_id}\"}}}")"
printf '%s\n' "$mcp_push_retry"
assert_matches "$mcp_push_retry" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_push_retry" '"status": "retried"'

mcp_push_orchestrate="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":41,"method":"tools/call","params":{"name":"gateway.push.orchestrate","arguments":{"channel":"local","limit":1}}}')"
printf '%s\n' "$mcp_push_orchestrate"
assert_matches "$mcp_push_orchestrate" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_push_orchestrate" '"actions"'

mcp_push_orchestration_audit="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":42,"method":"tools/call","params":{"name":"gateway.push.orchestration.audit","arguments":{}}}')"
printf '%s\n' "$mcp_push_orchestration_audit"
assert_matches "$mcp_push_orchestration_audit" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_push_orchestration_audit" '"actionsNeeded"'

mcp_push_orchestration_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":421,"method":"tools/call","params":{"name":"gateway.push.orchestration.actions","arguments":{}}}')"
printf '%s\n' "$mcp_push_orchestration_actions"
assert_matches "$mcp_push_orchestration_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_push_orchestration_actions" '"actions"'
assert_contains "$mcp_push_orchestration_actions" '"auditState"'

mcp_canvas_audit="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":43,"method":"tools/call","params":{"name":"gateway.canvas.audit","arguments":{}}}')"
printf '%s\n' "$mcp_canvas_audit"
assert_matches "$mcp_canvas_audit" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_canvas_audit" '"auditState"'
assert_contains "$mcp_canvas_audit" '"actionsNeeded"'

mcp_canvas_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":431,"method":"tools/call","params":{"name":"gateway.canvas.actions","arguments":{}}}')"
printf '%s\n' "$mcp_canvas_actions"
assert_matches "$mcp_canvas_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_canvas_actions" '"actions"'
assert_contains "$mcp_canvas_actions" '"auditState"'

mcp_talk_audit="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":44,"method":"tools/call","params":{"name":"gateway.talk.audit","arguments":{}}}')"
printf '%s\n' "$mcp_talk_audit"
assert_matches "$mcp_talk_audit" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_talk_audit" '"auditState"'
assert_contains "$mcp_talk_audit" '"actionsNeeded"'

mcp_talk_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":441,"method":"tools/call","params":{"name":"gateway.talk.actions","arguments":{}}}')"
printf '%s\n' "$mcp_talk_actions"
assert_matches "$mcp_talk_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_talk_actions" '"actions"'
assert_contains "$mcp_talk_actions" '"auditState"'

mcp_transport_reconnect="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"gateway.transport.reconnect","arguments":{}}}')"
printf '%s\n' "$mcp_transport_reconnect"
assert_matches "$mcp_transport_reconnect" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_reconnect" '"connected": true'

mcp_readiness="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":53,"method":"tools/call","params":{"name":"gateway.readiness","arguments":{}}}')"
printf '%s\n' "$mcp_readiness"
assert_matches "$mcp_readiness" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_readiness" '"readiness"'
assert_contains "$mcp_readiness" '"surfaces"'

mcp_config_get="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":531,"method":"tools/call","params":{"name":"gateway.config.get","arguments":{"path":"gateway.enabled"}}}')"
printf '%s\n' "$mcp_config_get"
assert_matches "$mcp_config_get" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_config_get" '"path":"gateway.enabled"'
assert_contains "$mcp_config_get" '"value"'

mcp_config_schema_lookup="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":532,"method":"tools/call","params":{"name":"gateway.config.schema.lookup","arguments":{"path":"gateway"}}}')"
printf '%s\n' "$mcp_config_schema_lookup"
assert_matches "$mcp_config_schema_lookup" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_config_schema_lookup" '"schema"'

mcp_webchat_status="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":533,"method":"tools/call","params":{"name":"gateway.webchat.status","arguments":{}}}')"
printf '%s\n' "$mcp_webchat_status"
assert_matches "$mcp_webchat_status" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_webchat_status" '"webchat"'

mcp_http_status="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":54,"method":"tools/call","params":{"name":"gateway.http.status","arguments":{}}}')"
printf '%s\n' "$mcp_http_status"
assert_matches "$mcp_http_status" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_http_status" '"http"'
assert_contains "$mcp_http_status" '"probePaths"'

mcp_http_start="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":541,"method":"tools/call","params":{"name":"gateway.http.start","arguments":{}}}')"
printf '%s\n' "$mcp_http_start"
assert_matches "$mcp_http_start" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_http_start" '"started": true'
assert_contains "$mcp_http_start" '"http"'

mcp_transport_lifecycle="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":55,"method":"tools/call","params":{"name":"gateway.transport.lifecycle","arguments":{}}}')"
printf '%s\n' "$mcp_transport_lifecycle"
assert_matches "$mcp_transport_lifecycle" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_lifecycle" '"lifecycle"'

mcp_transport_reconnect_history="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":56,"method":"tools/call","params":{"name":"gateway.transport.reconnect.history","arguments":{}}}')"
printf '%s\n' "$mcp_transport_reconnect_history"
assert_matches "$mcp_transport_reconnect_history" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_reconnect_history" '"lifecycle"'

mcp_transport_reconnect_state="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":565,"method":"tools/call","params":{"name":"gateway.transport.reconnect.state","arguments":{}}}')"
printf '%s\n' "$mcp_transport_reconnect_state"
assert_matches "$mcp_transport_reconnect_state" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_reconnect_state" '"transitionCount"'
assert_contains "$mcp_transport_reconnect_state" '"phase"'
assert_contains "$mcp_transport_reconnect_state" '"cooldownRemainingMs"'

mcp_connect_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":566,"method":"tools/call","params":{"name":"gateway.connect.actions","arguments":{"clientId":"metis-cli"}}}')"
printf '%s\n' "$mcp_connect_actions"
assert_matches "$mcp_connect_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_actions" '"actions"'
assert_contains "$mcp_connect_actions" '"policyState"'

mcp_agent_health="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":567,"method":"tools/call","params":{"name":"gateway.agent.health","arguments":{"agentId":"general"}}}')"
printf '%s\n' "$mcp_agent_health"
assert_matches "$mcp_agent_health" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_agent_health" '"healthy": true'
assert_contains "$mcp_agent_health" '"policyState": "routable"'

mcp_agent_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5671,"method":"tools/call","params":{"name":"gateway.agent.actions","arguments":{"agentId":"general","channel":"gateway-rpc","session":"main","text":"hello"}}}')"
printf '%s\n' "$mcp_agent_actions"
assert_matches "$mcp_agent_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_agent_actions" '"actions"'
assert_contains "$mcp_agent_actions" '"remediationState"'

mcp_agent_routing="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":568,"method":"tools/call","params":{"name":"gateway.agent.routing","arguments":{"agentId":"general","channel":"gateway-rpc","session":"main","text":"hello"}}}')"
printf '%s\n' "$mcp_agent_routing"
assert_matches "$mcp_agent_routing" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_agent_routing" '"delivery": "invoke"'
assert_contains "$mcp_agent_routing" '"policyState": "direct-rpc"'

mcp_channels_bindings="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":569,"method":"tools/call","params":{"name":"gateway.channels.bindings","arguments":{"channelId":"feishu"}}}')"
printf '%s\n' "$mcp_channels_bindings"
assert_matches "$mcp_channels_bindings" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_bindings" '"bindingState"'
assert_contains "$mcp_channels_bindings" '"registry"'
assert_contains "$mcp_channels_bindings" '"constraints"'

mcp_channels_policy="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5691,"method":"tools/call","params":{"name":"gateway.channels.policy","arguments":{}}}')"
printf '%s\n' "$mcp_channels_policy"
assert_matches "$mcp_channels_policy" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_policy" '"byPolicyState"'
assert_contains "$mcp_channels_policy" '"remediationState"'

mcp_channels_manager="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":56911,"method":"tools/call","params":{"name":"gateway.channels.manager","arguments":{"channelId":"feishu"}}}')"
printf '%s\n' "$mcp_channels_manager"
assert_matches "$mcp_channels_manager" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_manager" '"manager"'
assert_contains "$mcp_channels_manager" '"monitorEnabledCount"'

mcp_channels_health_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":56915,"method":"tools/call","params":{"name":"gateway.channels.health.actions","arguments":{}}}')"
printf '%s\n' "$mcp_channels_health_actions"
assert_matches "$mcp_channels_health_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_health_actions" '"actions"'
assert_contains "$mcp_channels_health_actions" '"byHealthState"'

mcp_channels_start="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":56916,"method":"tools/call","params":{"name":"gateway.channels.start","arguments":{"channelId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_channels_start"
assert_matches "$mcp_channels_start" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_start" '"started"'

mcp_channels_send="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":56917,"method":"tools/call","params":{"name":"gateway.channels.send","arguments":{"channelId":"metis-fixture","accountId":"fixture:default","peerId":"fixture-peer","text":"hello-from-gateway-regression"}}}')"
printf '%s\n' "$mcp_channels_send"
assert_matches "$mcp_channels_send" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_send" '"ok"'

mcp_channels_stop="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":56918,"method":"tools/call","params":{"name":"gateway.channels.stop","arguments":{"channelId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_channels_stop"
assert_matches "$mcp_channels_stop" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_stop" '"stopped"'

mcp_channels_logout="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5692,"method":"tools/call","params":{"name":"gateway.channels.logout","arguments":{"channelId":"feishu","accountId":"feishu:default"}}}')"
printf '%s\n' "$mcp_channels_logout"
assert_matches "$mcp_channels_logout" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_channels_logout" '"cleared": true'
assert_contains "$mcp_channels_logout" '"accountId": "feishu:default"'

mcp_plugins_bindings="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570,"method":"tools/call","params":{"name":"gateway.plugins.bindings","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_bindings"
assert_matches "$mcp_plugins_bindings" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_bindings" '"bindingState"'
assert_contains "$mcp_plugins_bindings" '"registry"'
assert_contains "$mcp_plugins_bindings" '"constraints"'

mcp_plugins_policy="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5701,"method":"tools/call","params":{"name":"gateway.plugins.policy","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_policy"
assert_matches "$mcp_plugins_policy" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_policy" '"byPolicyState"'
assert_contains "$mcp_plugins_policy" '"remediationState"'

mcp_plugins_manager="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57011,"method":"tools/call","params":{"name":"gateway.plugins.manager","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_manager"
assert_matches "$mcp_plugins_manager" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_manager" '"manager"'

mcp_plugins_health_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57015,"method":"tools/call","params":{"name":"gateway.plugins.health.actions","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_health_actions"
assert_matches "$mcp_plugins_health_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_health_actions" '"actions"'
assert_contains "$mcp_plugins_health_actions" '"byHealthState"'

mcp_plugins_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570151,"method":"tools/call","params":{"name":"gateway.plugins.actions","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_actions"
assert_matches "$mcp_plugins_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_actions" '"actionNames"'

mcp_plugins_setup_apply="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57016,"method":"tools/call","params":{"name":"gateway.plugins.setup.apply","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_setup_apply"
assert_matches "$mcp_plugins_setup_apply" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_setup_apply" '"state"'
assert_contains "$mcp_plugins_setup_apply" '"count"'

mcp_plugins_setup_registry="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570161,"method":"tools/call","params":{"name":"gateway.plugins.setup.registry","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_setup_registry"
assert_matches "$mcp_plugins_setup_registry" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_setup_registry" '"setupRegistry"'

mcp_plugins_runtime_forwarders="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570162,"method":"tools/call","params":{"name":"gateway.plugins.runtime.forwarders","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_runtime_forwarders"
assert_matches "$mcp_plugins_runtime_forwarders" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_runtime_forwarders" '"dispatchAction": true'

mcp_plugins_resolve_account="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570163,"method":"tools/call","params":{"name":"gateway.plugins.resolve_account","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_resolve_account"
assert_matches "$mcp_plugins_resolve_account" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_resolve_account" '"accountId": "fixture:default"'

mcp_plugins_directory="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570164,"method":"tools/call","params":{"name":"gateway.plugins.directory","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","groupId":"fixture-group"}}}')"
printf '%s\n' "$mcp_plugins_directory"
assert_matches "$mcp_plugins_directory" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_directory" '"fixture-peer"'

mcp_plugins_targets="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570165,"method":"tools/call","params":{"name":"gateway.plugins.targets","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","target":"fixture-peer"}}}')"
printf '%s\n' "$mcp_plugins_targets"
assert_matches "$mcp_plugins_targets" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_targets" '"targetKind": "peer"'

mcp_plugins_dispatch="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570166,"method":"tools/call","params":{"name":"gateway.plugins.actions.dispatch","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","action":"fixture-send-text","payload":{"text":"hello-from-mcp-gateway-dispatch"}}}}')"
printf '%s\n' "$mcp_plugins_dispatch"
assert_matches "$mcp_plugins_dispatch" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_dispatch" '"dispatched": true'

mcp_plugins_start="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57017,"method":"tools/call","params":{"name":"gateway.plugins.start","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_start"
assert_matches "$mcp_plugins_start" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_start" '"started"'

mcp_plugins_send="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57018,"method":"tools/call","params":{"name":"gateway.plugins.send","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","peerId":"fixture-peer","text":"hello-from-gateway-plugin"}}}')"
printf '%s\n' "$mcp_plugins_send"
assert_matches "$mcp_plugins_send" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_send" '"ok"'

mcp_plugins_stop="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57019,"method":"tools/call","params":{"name":"gateway.plugins.stop","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_stop"
assert_matches "$mcp_plugins_stop" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_stop" '"stopped"'

mcp_plugins_logout="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57020,"method":"tools/call","params":{"name":"gateway.plugins.logout","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_logout"
assert_matches "$mcp_plugins_logout" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_plugins_logout" '"cleared"'

mcp_probe_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":571,"method":"tools/call","params":{"name":"gateway.probe.actions","arguments":{}}}')"
printf '%s\n' "$mcp_probe_actions"
assert_matches "$mcp_probe_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_probe_actions" '"actions"'
assert_contains "$mcp_probe_actions" '"policyState"'

mcp_probe_remediation="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5711,"method":"tools/call","params":{"name":"gateway.probe.remediation","arguments":{}}}')"
printf '%s\n' "$mcp_probe_remediation"
assert_matches "$mcp_probe_remediation" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_probe_remediation" '"remediation"'
assert_contains "$mcp_probe_remediation" '"remediationState"'

mcp_doctor_actions="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":572,"method":"tools/call","params":{"name":"gateway.doctor.actions","arguments":{}}}')"
printf '%s\n' "$mcp_doctor_actions"
assert_matches "$mcp_doctor_actions" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_doctor_actions" '"actions"'
assert_contains "$mcp_doctor_actions" '"policyState"'

mcp_doctor_remediation="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5721,"method":"tools/call","params":{"name":"gateway.doctor.remediation","arguments":{}}}')"
printf '%s\n' "$mcp_doctor_remediation"
assert_matches "$mcp_doctor_remediation" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_doctor_remediation" '"remediation"'
assert_contains "$mcp_doctor_remediation" '"remediationState"'

mcp_transport_reconnect_window="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":566,"method":"tools/call","params":{"name":"gateway.transport.reconnect.window","arguments":{}}}')"
printf '%s\n' "$mcp_transport_reconnect_window"
assert_matches "$mcp_transport_reconnect_window" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_reconnect_window" '"consecutiveFailureCount"'
assert_contains "$mcp_transport_reconnect_window" '"cooldownRemainingMs"'

mcp_transport_reconnect_plan="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":560,"method":"tools/call","params":{"name":"gateway.transport.reconnect.plan","arguments":{}}}')"
printf '%s\n' "$mcp_transport_reconnect_plan"
assert_matches "$mcp_transport_reconnect_plan" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_reconnect_plan" '"plan"'
assert_contains "$mcp_transport_reconnect_plan" '"phase"'

mcp_transport_reconnect_audit="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5601,"method":"tools/call","params":{"name":"gateway.transport.reconnect.audit","arguments":{}}}')"
printf '%s\n' "$mcp_transport_reconnect_audit"
assert_matches "$mcp_transport_reconnect_audit" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_reconnect_audit" '"auditState"'

mcp_connect_stream_open="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":570,"method":"tools/call","params":{"name":"gateway.connect.stream.open","arguments":{"clientId":"metis-cli","limit":1,"waitMs":0}}}')"
printf '%s\n' "$mcp_connect_stream_open"
assert_matches "$mcp_connect_stream_open" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_open" '"opened": true'

mcp_connect_stream_attach="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":571,"method":"tools/call","params":{"name":"gateway.connect.stream.attach","arguments":{"clientId":"metis-cli","waitMs":0}}}')"
printf '%s\n' "$mcp_connect_stream_attach"
assert_matches "$mcp_connect_stream_attach" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_attach" '"attached": true'

mcp_transport_reconnect_reset="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":561,"method":"tools/call","params":{"name":"gateway.transport.reconnect.reset","arguments":{}}}')"
printf '%s\n' "$mcp_transport_reconnect_reset"
assert_matches "$mcp_transport_reconnect_reset" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_reconnect_reset" '"reset": true'

mcp_transport_stream_audit="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5611,"method":"tools/call","params":{"name":"gateway.transport.stream.audit","arguments":{}}}')"
printf '%s\n' "$mcp_transport_stream_audit"
assert_matches "$mcp_transport_stream_audit" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_transport_stream_audit" '"auditState"'

mcp_connect_stream_status="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":57,"method":"tools/call","params":{"name":"gateway.connect.stream.status","arguments":{"clientId":"metis-cli"}}}')"
printf '%s\n' "$mcp_connect_stream_status"
assert_matches "$mcp_connect_stream_status" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_status" '"stream"'
assert_contains "$mcp_connect_stream_status" '"streamId"'
assert_contains "$mcp_connect_stream_status" '"phase"'

mcp_connect_stream_keepalive="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":58,"method":"tools/call","params":{"name":"gateway.connect.stream.keepalive","arguments":{"clientId":"metis-cli"}}}')"
printf '%s\n' "$mcp_connect_stream_keepalive"
assert_matches "$mcp_connect_stream_keepalive" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_keepalive" '"keepalive": true'

mcp_connect_stream_resume="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":585,"method":"tools/call","params":{"name":"gateway.connect.stream.resume","arguments":{"clientId":"metis-cli","limit":1}}}')"
printf '%s\n' "$mcp_connect_stream_resume"
assert_matches "$mcp_connect_stream_resume" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_resume" '"resumed": true'

mcp_connect_stream_next="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":5851,"method":"tools/call","params":{"name":"gateway.connect.stream.next","arguments":{"clientId":"metis-cli"}}}')"
printf '%s\n' "$mcp_connect_stream_next"
assert_matches "$mcp_connect_stream_next" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_next" '"next": true'

mcp_connect_stream_push="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":586,"method":"tools/call","params":{"name":"gateway.connect.stream.push","arguments":{"clientId":"metis-cli","detail":"mcp-regression-push"}}}')"
printf '%s\n' "$mcp_connect_stream_push"
assert_matches "$mcp_connect_stream_push" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_push" '"pushed": true'

mcp_connect_stream_close="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":59,"method":"tools/call","params":{"name":"gateway.connect.stream.close","arguments":{"clientId":"metis-cli"}}}')"
printf '%s\n' "$mcp_connect_stream_close"
assert_matches "$mcp_connect_stream_close" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_close" '"closed": true'

mcp_connect_stream_detach="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":60,"method":"tools/call","params":{"name":"gateway.connect.stream.detach","arguments":{"clientId":"metis-cli"}}}')"
printf '%s\n' "$mcp_connect_stream_detach"
assert_matches "$mcp_connect_stream_detach" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_connect_stream_detach" '"detached": true'

mcp_control_reload="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"gateway.control_ui.reload","arguments":{}}}')"
printf '%s\n' "$mcp_control_reload"
assert_matches "$mcp_control_reload" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_control_reload" '"reloaded": true'

mcp_control_status="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":601,"method":"tools/call","params":{"name":"gateway.control_ui.status","arguments":{}}}')"
printf '%s\n' "$mcp_control_status"
assert_matches "$mcp_control_status" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_control_status" '"healthy"'
assert_contains "$mcp_control_status" '"summary"'

mcp_control_contract="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":602,"method":"tools/call","params":{"name":"gateway.control_ui.contract","arguments":{}}}')"
printf '%s\n' "$mcp_control_contract"
assert_matches "$mcp_control_contract" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_control_contract" '"contract"'

mcp_control_binding="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":61,"method":"tools/call","params":{"name":"gateway.control_ui.binding","arguments":{}}}')"
printf '%s\n' "$mcp_control_binding"
assert_matches "$mcp_control_binding" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_control_binding" '"wsUrl"'
assert_contains "$mcp_control_binding" '"assetsPath"'

mcp_control_runtime="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":62,"method":"tools/call","params":{"name":"gateway.control_ui.runtime","arguments":{}}}')"
printf '%s\n' "$mcp_control_runtime"
assert_matches "$mcp_control_runtime" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_control_runtime" '"originPolicy"'
assert_contains "$mcp_control_runtime" '"binding"'

mcp_webchat_reload="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/mcp -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"gateway.webchat.reload","arguments":{}}}')"
printf '%s\n' "$mcp_webchat_reload"
assert_matches "$mcp_webchat_reload" '"jsonrpc"[[:space:]]*:[[:space:]]*"2\.0"'
assert_contains "$mcp_webchat_reload" '"reloaded": true'

echo "[gateway-regression] http models"
models_body="$(curl -fsS http://127.0.0.1:${GATEWAY_PORT}/v1/models)"
printf '%s\n' "$models_body"
assert_matches "$models_body" '"object"[[:space:]]*:[[:space:]]*"list"'
assert_matches "$models_body" '"data"[[:space:]]*:'

echo "[gateway-regression] http embeddings"
embeddings_body="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/v1/embeddings -H 'content-type: application/json' -d '{"input":"hello","model":"ark:qwen3.5-plus"}')"
printf '%s\n' "$embeddings_body"
assert_matches "$embeddings_body" '"object"[[:space:]]*:[[:space:]]*"list"'
assert_matches "$embeddings_body" '"embedding"[[:space:]]*:'

echo "[gateway-regression] http chat completions"
chat_body="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/v1/chat/completions -H 'content-type: application/json' -d '{"model":"ark:kimi-k2-250905","messages":[{"role":"user","content":[{"type":"text","text":"say ok"},{"type":"image_url","image_url":{"url":"https://example.com/a.png"}},{"type":"file_url","file_url":{"url":"https://example.com/a.txt"}}]}]}')"
printf '%s\n' "$chat_body"
assert_matches "$chat_body" '"object"[[:space:]]*:[[:space:]]*"chat\.completion"'
assert_matches "$chat_body" '"system_fingerprint"[[:space:]]*:[[:space:]]*"metis-gateway"'
assert_matches "$chat_body" '"request_context"[[:space:]]*:'
assert_matches "$chat_body" '"attachment_summary"[[:space:]]*:'
assert_matches "$chat_body" '"images"[[:space:]]*:[[:space:]]*1'

echo "[gateway-regression] http responses"
responses_body="$(curl -fsS -X POST http://127.0.0.1:${GATEWAY_PORT}/v1/responses -H 'content-type: application/json' -d '{"model":"ark:kimi-k2-250905","input":[{"role":"user","content":[{"type":"input_text","text":"say ok again"},{"type":"file_id","file_id":"file-123"}]}]}')"
printf '%s\n' "$responses_body"
assert_matches "$responses_body" '"object"[[:space:]]*:[[:space:]]*"response"'
assert_matches "$responses_body" '"status"[[:space:]]*:[[:space:]]*"completed"'
assert_matches "$responses_body" '"output_text"[[:space:]]*:'
assert_matches "$responses_body" '"request_context"[[:space:]]*:'
assert_matches "$responses_body" '"file_ids"[[:space:]]*:[[:space:]]*1'

echo "[gateway-regression] ok"
