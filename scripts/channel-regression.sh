#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_HOME="$(mktemp -d /tmp/metis-channel.XXXXXX)"
GATEWAY_PID=""
GATEWAY_PORT="28789"
FIXTURE_PLUGIN_ID="metis-fixture"
BIN="$ROOT/target/release/bin/metis"
STDX_LIB_PATH="$ROOT/../CangjieMagic/libs/cangjie-stdx-mac-aarch64-1.0.0.1/darwin_aarch64_llvm/dynamic/stdx"
CLI_LIB_PATH="$ROOT/target/release/metis:$ROOT/ffi"
MAGIC_LIB_PATH="$ROOT/target/release/magic"
LIB_PATHS="$CLI_LIB_PATH:$MAGIC_LIB_PATH:$STDX_LIB_PATH"
TELEGRAM_THREAD_SESSION_KEY="agent:main:channel-regression-telegram-thread"
TELEGRAM_THREAD_SESSION_STEM="agent_main_channel-regression-telegram-thread"
CONTROL_UI_DEVICE_ID=""
CONTROL_UI_DEVICE_TOKEN=""

append_if_dir() {
  local dir="$1"
  if [[ -n "$dir" && -d "$dir" ]]; then
    LIB_PATHS="$LIB_PATHS:$dir"
  fi
}

prepare_runtime_env() {
  append_if_dir "/Users/l3gi0n/cangjie100/runtime/lib/darwin_aarch64_llvm"
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

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 80); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "channel regression http surface not ready: $url" >&2
  exit 1
}

load_control_ui_auth() {
  local auth_json
  auth_json="$(curl -fsS "http://127.0.0.1:${GATEWAY_PORT}/__metis/control-ui-auth.json")"
  CONTROL_UI_DEVICE_ID="$(printf '%s\n' "$auth_json" | sed -n 's/.*"deviceId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CONTROL_UI_DEVICE_TOKEN="$(printf '%s\n' "$auth_json" | sed -n 's/.*"deviceToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  if [[ -z "$CONTROL_UI_DEVICE_ID" || -z "$CONTROL_UI_DEVICE_TOKEN" ]]; then
    echo "failed to resolve control-ui device auth headers" >&2
    exit 1
  fi
}

control_ui_get() {
  local path="$1"
  curl -fsS \
    -H "X-Metis-Device-Id: ${CONTROL_UI_DEVICE_ID}" \
    -H "X-Metis-Device-Token: ${CONTROL_UI_DEVICE_TOKEN}" \
    "http://127.0.0.1:${GATEWAY_PORT}${path}"
}

seed_telegram_thread_session_fixture() {
  local sessions_root="$TMP_HOME/agents/main/sessions"
  local transcript_path="$sessions_root/${TELEGRAM_THREAD_SESSION_STEM}.jsonl"
  mkdir -p "$sessions_root"
  cat >"$transcript_path" <<EOF
{"kind":"meta","v":"1","sessionKey":"${TELEGRAM_THREAD_SESSION_KEY}"}
{"role":"system","text":"sessions_spawn metadata: runtime=subagent, streamTo=telegram:group:-1001234567890:topic:42, thread=true"}
EOF
}

start_gateway_run() {
  if [[ -n "${GATEWAY_PID}" ]] && kill -0 "${GATEWAY_PID}" >/dev/null 2>&1; then
    return 0
  fi
  prepare_runtime_env
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" \
    "$BIN" gateway run >/tmp/metis-channel-run.log 2>&1 &
  GATEWAY_PID=$!
  disown "${GATEWAY_PID}" >/dev/null 2>&1 || true
  wait_for_http "http://127.0.0.1:${GATEWAY_PORT}/healthz"
}

mkdir -p "$TMP_HOME"
mkdir -p "$TMP_HOME/gateway-plugins"
seed_telegram_thread_session_fixture
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
    "telegram": {
      "enabled": true,
      "botToken": "tg-token",
      "reactionNotifications": "all",
      "reactionLevel": "ack",
      "ackReaction": "👀"
    },
    "gatewayPlugins": [
      {
        "id": "metis-fixture",
        "enabled": true
      }
    ],
    "channelsExtra": {
      "slack": {
        "enabled": true,
        "configured": true,
        "botToken": "xoxb-demo"
      },
      "discord": {
        "enabled": true,
        "configured": true,
        "botToken": "discord-demo"
      },
      "metis-fixture": {
        "token": "fixture-token",
        "accountIds": ["fixture:default"],
        "defaultAccountId": "fixture:default"
      }
    }
  }
}
EOF

echo "[channel-regression] build"
with_metis_cjpm_build_lock /bin/zsh -lc "source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH=\"/Users/l3gi0n/cangjie100/runtime/lib/darwin_aarch64_llvm:/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/openssl@3.5/lib:/usr/local/opt/openssl@3/lib:${DYLD_LIBRARY_PATH:-}\" && rtk cjpm clean >/dev/null && mkdir -p target build-script-cache/release/metis/bin build-script-cache/release/magic/bin && rtk cjpm build -i >/dev/null"

echo "[channel-regression] start gateway run"
start_gateway_run
load_control_ui_auth

echo "[channel-regression] rpc discover"
discover_out="$(run_gateway call discover.detail)"
printf '%s\n' "$discover_out"
assert_contains "$discover_out" '"channelCatalog"'
assert_contains "$discover_out" '"pluginCatalog"'
assert_contains "$discover_out" '"telegram"'
assert_contains "$discover_out" '"slack"'
assert_contains "$discover_out" '"discord"'
assert_contains "$discover_out" '"metis-fixture"'

echo "[channel-regression] rpc channels"
channels_status_out="$(run_gateway call channels.status '{"probe":true,"timeoutMs":2222}')"
printf '%s\n' "$channels_status_out"
assert_contains "$channels_status_out" '"channelOrder"'
assert_contains "$channels_status_out" '"channelAccounts"'
assert_contains "$channels_status_out" '"channelDefaultAccountId"'
assert_contains "$channels_status_out" '"metis-fixture"'
assert_matches "$channels_status_out" '"probe"[[:space:]]*:[[:space:]]*true'
assert_matches "$channels_status_out" '"timeoutMs"[[:space:]]*:[[:space:]]*2222'

channels_list_out="$(run_gateway call channels.list '{"probe":false}')"
printf '%s\n' "$channels_list_out"
assert_contains "$channels_list_out" '"channels"'
assert_contains "$channels_list_out" '"channelAccounts"'

channels_get_telegram_out="$(run_gateway call channels.get '{"channelId":"telegram"}')"
printf '%s\n' "$channels_get_telegram_out"
assert_contains "$channels_get_telegram_out" '"telegram"'
assert_contains "$channels_get_telegram_out" '"supports"'
assert_contains "$channels_get_telegram_out" '"actions"'
assert_contains "$channels_get_telegram_out" '"commandsNative"'
assert_contains "$channels_get_telegram_out" '"customCommandCount"'
assert_contains "$channels_get_telegram_out" '"reactionNotifications"'
assert_contains "$channels_get_telegram_out" '"reactionLevel"'
assert_contains "$channels_get_telegram_out" '"ackReaction"'
assert_contains "$channels_get_telegram_out" '"topicBindings"'
assert_contains "$channels_get_telegram_out" '"reactionEvents"'
assert_contains "$channels_get_telegram_out" '"mediaPhoto"'
assert_contains "$channels_get_telegram_out" '"mediaAudio"'
assert_contains "$channels_get_telegram_out" '"mediaVoice"'
assert_contains "$channels_get_telegram_out" '"mediaVideo"'
assert_contains "$channels_get_telegram_out" '"mediaVideoNote"'

channels_get_fixture_out="$(run_gateway call channels.get '{"channelId":"metis-fixture"}')"
printf '%s\n' "$channels_get_fixture_out"
assert_contains "$channels_get_fixture_out" '"metis-fixture"'

channels_runtime_telegram_out="$(run_gateway call channels.runtime '{"channelId":"telegram","probe":true}')"
printf '%s\n' "$channels_runtime_telegram_out"
assert_contains "$channels_runtime_telegram_out" '"telegram"'
assert_contains "$channels_runtime_telegram_out" '"allowedUpdates"'
assert_contains "$channels_runtime_telegram_out" '"message_reaction"'
assert_contains "$channels_runtime_telegram_out" '"registrationPayload"'
assert_contains "$channels_runtime_telegram_out" '"healthSnapshot"'
assert_contains "$channels_runtime_telegram_out" '"offsetPersistenceEnabled"'
assert_contains "$channels_runtime_telegram_out" '"lastInboundUpdateId"'
assert_contains "$channels_runtime_telegram_out" '"liveProbe"'
assert_contains "$channels_runtime_telegram_out" '"supports"'
assert_contains "$channels_runtime_telegram_out" '"mediaAudio"'
assert_contains "$channels_runtime_telegram_out" '"mediaVideoNote"'
assert_contains "$channels_runtime_telegram_out" '"summary"'

channels_runtime_out="$(run_gateway call channels.runtime '{"channelId":"metis-fixture"}')"
printf '%s\n' "$channels_runtime_out"
assert_contains "$channels_runtime_out" '"bootstrap"'
assert_contains "$channels_runtime_out" '"configuredBindings"'
assert_contains "$channels_runtime_out" '"metis-fixture"'

channels_manager_out="$(run_gateway call channels.manager '{"channelId":"telegram"}')"
printf '%s\n' "$channels_manager_out"
assert_contains "$channels_manager_out" '"manager"'
assert_contains "$channels_manager_out" '"monitorEnabledCount"'
assert_contains "$channels_manager_out" '"taskState"'

channels_bindings_telegram_out="$(run_gateway call channels.bindings '{"channelId":"telegram"}')"
printf '%s\n' "$channels_bindings_telegram_out"
assert_contains "$channels_bindings_telegram_out" '"bindings"'
assert_contains "$channels_bindings_telegram_out" '"registry"'
assert_contains "$channels_bindings_telegram_out" '"configuredBinding"'

channels_bindings_fixture_out="$(run_gateway call channels.bindings '{"channelId":"metis-fixture"}')"
printf '%s\n' "$channels_bindings_fixture_out"
assert_contains "$channels_bindings_fixture_out" '"metis-fixture"'
assert_contains "$channels_bindings_fixture_out" '"fixture:default"'
assert_contains "$channels_bindings_fixture_out" '"configuredAccountIds"'

channels_policy_out="$(run_gateway call channels.policy)"
printf '%s\n' "$channels_policy_out"
assert_contains "$channels_policy_out" '"policy"'
assert_contains "$channels_policy_out" '"byPolicyState"'

channels_health_out="$(run_gateway call channels.health '{"probe":true}')"
printf '%s\n' "$channels_health_out"
assert_contains "$channels_health_out" '"channels"'
assert_contains "$channels_health_out" '"byHealthState"'
assert_contains "$channels_health_out" '"telegram"'
assert_contains "$channels_health_out" '"healthSnapshot"'
assert_contains "$channels_health_out" '"offsetPersistenceEnabled"'
assert_contains "$channels_health_out" '"lastInboundUpdateId"'
assert_contains "$channels_health_out" '"liveProbe"'

channels_audit_telegram_out="$(run_gateway call channels.audit '{"channelId":"telegram"}')"
printf '%s\n' "$channels_audit_telegram_out"
assert_contains "$channels_audit_telegram_out" '"gateway-channels-audit"'
assert_contains "$channels_audit_telegram_out" '"T12"'
assert_contains "$channels_audit_telegram_out" '"registrationPayload"'
assert_contains "$channels_audit_telegram_out" '"healthSnapshot"'
assert_contains "$channels_audit_telegram_out" '"channelsRuntimeAvailable"'
assert_contains "$channels_audit_telegram_out" '"channelsHealthAvailable"'
assert_contains "$channels_audit_telegram_out" '"dashboardHttpAvailable"'
assert_contains "$channels_audit_telegram_out" '"controlUiHttpAvailable"'
assert_contains "$channels_audit_telegram_out" '"controlUiWsAvailable"'
assert_contains "$channels_audit_telegram_out" '"controlUiSessionsHttpAvailable"'
assert_contains "$channels_audit_telegram_out" '"controlUiSessionsWsAvailable"'
assert_contains "$channels_audit_telegram_out" '"telegramNativeRuntimeVisible"'
assert_contains "$channels_audit_telegram_out" '"telegramLiveProbeRuntimeVisible"'
assert_contains "$channels_audit_telegram_out" '"telegramReactionRuntimeVisible"'
assert_contains "$channels_audit_telegram_out" '"telegramMediaRuntimeVisible"'
assert_contains "$channels_audit_telegram_out" '"telegramMediaPersistenceVisible"'
assert_contains "$channels_audit_telegram_out" '"offsetPersistenceEnabled"'
assert_contains "$channels_audit_telegram_out" '"lastInboundUpdateId"'
assert_contains "$channels_audit_telegram_out" '"liveProbe"'
assert_contains "$channels_audit_telegram_out" '"downloadEnabled"'
assert_contains "$channels_audit_telegram_out" '"lastPersistedMediaId"'
assert_contains "$channels_audit_telegram_out" '"telegramThreadBindingVisibleInDashboardSessions"'
assert_contains "$channels_audit_telegram_out" '"telegramThreadBindingVisibleInControlUiSessions"'
assert_contains "$channels_audit_telegram_out" '"telegramThreadBindingVisibleInControlUiWsSessions"'
assert_contains "$channels_audit_telegram_out" '"rpc"'
assert_contains "$channels_audit_telegram_out" '"mcpOverHttp"'
assert_contains "$channels_audit_telegram_out" '"dashboardHttp"'
assert_contains "$channels_audit_telegram_out" '"dashboardSessions"'
assert_contains "$channels_audit_telegram_out" '"controlUiHttp"'
assert_contains "$channels_audit_telegram_out" '"controlUiWs"'
assert_contains "$channels_audit_telegram_out" '"controlUiSessionsHttp"'
assert_contains "$channels_audit_telegram_out" '"controlUiSessionsWs"'
assert_contains "$channels_audit_telegram_out" '"telegram-live-probe-runtime-is-visible-across-consumers"'
assert_contains "$channels_audit_telegram_out" '"telegram-reaction-and-media-runtime-are-visible-across-consumers"'
assert_contains "$channels_audit_telegram_out" '"telegram-media-download-and-file-persistence-are-visible-across-consumers"'
assert_not_contains "$channels_audit_telegram_out" '"telegram-webhook-live-probe-remains-ops-followup"'
assert_not_contains "$channels_audit_telegram_out" '"telegram-media-download-and-file-persistence-remain-followups"'
assert_contains "$channels_health_out" '"monitor"'
assert_contains "$channels_health_out" '"telegram"'
assert_contains "$channels_health_out" '"registrationPayload"'
assert_contains "$channels_health_out" '"healthSnapshot"'
assert_contains "$channels_health_out" '"actions"'
assert_contains "$channels_health_out" '"supports"'
assert_contains "$channels_health_out" '"mediaAudio"'
assert_contains "$channels_health_out" '"mediaVideoNote"'

channels_health_actions_out="$(run_gateway call channels.health.actions)"
printf '%s\n' "$channels_health_actions_out"
assert_contains "$channels_health_actions_out" '"actions"'

echo "[channel-regression] control-ui http channels"
http_channels_runtime_telegram_out="$(control_ui_get "/api/channels/runtime?channelId=telegram&probe=true")"
printf '%s\n' "$http_channels_runtime_telegram_out"
assert_contains "$http_channels_runtime_telegram_out" '"telegram"'
assert_contains "$http_channels_runtime_telegram_out" '"allowedUpdates"'
assert_contains "$http_channels_runtime_telegram_out" '"message_reaction"'
assert_contains "$http_channels_runtime_telegram_out" '"registrationPayload"'
assert_contains "$http_channels_runtime_telegram_out" '"healthSnapshot"'
assert_contains "$http_channels_runtime_telegram_out" '"offsetPersistenceEnabled"'
assert_contains "$http_channels_runtime_telegram_out" '"lastInboundUpdateId"'
assert_contains "$http_channels_runtime_telegram_out" '"liveProbe"'
assert_contains "$http_channels_runtime_telegram_out" '"mediaAudio"'
assert_contains "$http_channels_runtime_telegram_out" '"mediaVideoNote"'

http_channels_health_out="$(control_ui_get "/api/channels/health?probe=true")"
printf '%s\n' "$http_channels_health_out"
assert_contains "$http_channels_health_out" '"telegram"'
assert_contains "$http_channels_health_out" '"healthSnapshot"'
assert_contains "$http_channels_health_out" '"offsetPersistenceEnabled"'
assert_contains "$http_channels_health_out" '"lastInboundUpdateId"'
assert_contains "$http_channels_health_out" '"liveProbe"'
assert_contains "$http_channels_health_out" '"actions"'
assert_contains "$http_channels_health_out" '"supports"'
assert_contains "$http_channels_health_out" '"mediaAudio"'
assert_contains "$http_channels_health_out" '"mediaVideoNote"'

http_channels_audit_telegram_out="$(control_ui_get "/api/channels/audit?channelId=telegram")"
printf '%s\n' "$http_channels_audit_telegram_out"
assert_contains "$http_channels_audit_telegram_out" '"gateway-channels-audit"'
assert_contains "$http_channels_audit_telegram_out" '"T12"'
assert_contains "$http_channels_audit_telegram_out" '"registrationPayload"'
assert_contains "$http_channels_audit_telegram_out" '"healthSnapshot"'
assert_contains "$http_channels_audit_telegram_out" '"channelsRuntimeAvailable"'
assert_contains "$http_channels_audit_telegram_out" '"channelsHealthAvailable"'
assert_contains "$http_channels_audit_telegram_out" '"dashboardHttpAvailable"'
assert_contains "$http_channels_audit_telegram_out" '"controlUiHttpAvailable"'
assert_contains "$http_channels_audit_telegram_out" '"controlUiWsAvailable"'
assert_contains "$http_channels_audit_telegram_out" '"telegramNativeRuntimeVisible"'
assert_contains "$http_channels_audit_telegram_out" '"telegramLiveProbeRuntimeVisible"'
assert_contains "$http_channels_audit_telegram_out" '"telegramReactionRuntimeVisible"'
assert_contains "$http_channels_audit_telegram_out" '"telegramMediaRuntimeVisible"'
assert_contains "$http_channels_audit_telegram_out" '"telegramMediaPersistenceVisible"'
assert_contains "$http_channels_audit_telegram_out" '"offsetPersistenceEnabled"'
assert_contains "$http_channels_audit_telegram_out" '"lastInboundUpdateId"'
assert_contains "$http_channels_audit_telegram_out" '"liveProbe"'
assert_contains "$http_channels_audit_telegram_out" '"downloadEnabled"'
assert_contains "$http_channels_audit_telegram_out" '"lastPersistedMediaId"'
assert_contains "$http_channels_audit_telegram_out" '"telegramThreadBindingVisibleInDashboardSessions"'
assert_contains "$http_channels_audit_telegram_out" '"telegramThreadBindingVisibleInControlUiSessions"'
assert_contains "$http_channels_audit_telegram_out" '"telegramThreadBindingVisibleInControlUiWsSessions"'
assert_contains "$http_channels_audit_telegram_out" '"rpc"'
assert_contains "$http_channels_audit_telegram_out" '"mcpOverHttp"'
assert_contains "$http_channels_audit_telegram_out" '"dashboardHttp"'
assert_contains "$http_channels_audit_telegram_out" '"dashboardSessions"'
assert_contains "$http_channels_audit_telegram_out" '"controlUiHttp"'
assert_contains "$http_channels_audit_telegram_out" '"controlUiWs"'
assert_contains "$http_channels_audit_telegram_out" '"controlUiSessionsHttp"'
assert_contains "$http_channels_audit_telegram_out" '"controlUiSessionsWs"'
assert_contains "$http_channels_audit_telegram_out" '"telegram-live-probe-runtime-is-visible-across-consumers"'
assert_contains "$http_channels_audit_telegram_out" '"telegram-reaction-and-media-runtime-are-visible-across-consumers"'
assert_contains "$http_channels_audit_telegram_out" '"telegram-media-download-and-file-persistence-are-visible-across-consumers"'
assert_not_contains "$http_channels_audit_telegram_out" '"telegram-webhook-live-probe-remains-ops-followup"'
assert_not_contains "$http_channels_audit_telegram_out" '"telegram-media-download-and-file-persistence-remain-followups"'

dashboard_channels_audit_telegram_out="$(run_gateway call dashboard.channels.audit '{"channelId":"telegram"}')"
printf '%s\n' "$dashboard_channels_audit_telegram_out"
assert_contains "$dashboard_channels_audit_telegram_out" '"gateway-channels-audit"'
assert_contains "$dashboard_channels_audit_telegram_out" '"T12"'
assert_contains "$dashboard_channels_audit_telegram_out" '"registrationPayload"'
assert_contains "$dashboard_channels_audit_telegram_out" '"healthSnapshot"'
assert_contains "$dashboard_channels_audit_telegram_out" '"message_reaction"'
assert_contains "$dashboard_channels_audit_telegram_out" '"mediaAudio"'
assert_contains "$dashboard_channels_audit_telegram_out" '"mediaVideoNote"'
assert_contains "$dashboard_channels_audit_telegram_out" '"liveProbe"'
assert_contains "$dashboard_channels_audit_telegram_out" '"telegramReactionRuntimeVisible"'
assert_contains "$dashboard_channels_audit_telegram_out" '"telegramLiveProbeRuntimeVisible"'
assert_contains "$dashboard_channels_audit_telegram_out" '"telegramMediaPersistenceVisible"'
assert_contains "$dashboard_channels_audit_telegram_out" '"downloadEnabled"'
assert_contains "$dashboard_channels_audit_telegram_out" '"dashboardHttp"'
assert_contains "$dashboard_channels_audit_telegram_out" '"dashboardSessions"'
assert_contains "$dashboard_channels_audit_telegram_out" '"telegramThreadBindingVisibleInDashboardSessions"'

http_sessions_list_out="$(control_ui_get "/api/sessions/list")"
printf '%s\n' "$http_sessions_list_out"
assert_contains "$http_sessions_list_out" "$TELEGRAM_THREAD_SESSION_KEY"
assert_contains "$http_sessions_list_out" '"threadBinding"'
assert_contains "$http_sessions_list_out" '"telegram"'
assert_contains "$http_sessions_list_out" '"group:-1001234567890:topic:42"'
assert_matches "$http_sessions_list_out" '"threadId"[[:space:]]*:[[:space:]]*"42"'

channels_start_out="$(run_gateway call channels.start '{"channelId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$channels_start_out"
assert_contains "$channels_start_out" '"started"'
assert_contains "$channels_start_out" '"host"'

channels_send_out="$(run_gateway call channels.send '{"channelId":"metis-fixture","accountId":"fixture:default","peerId":"fixture-peer","text":"hello-from-channel-regression"}')"
printf '%s\n' "$channels_send_out"
assert_contains "$channels_send_out" '"ok"'
assert_contains "$channels_send_out" 'fixture-peer'

channels_stop_out="$(run_gateway call channels.stop '{"channelId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$channels_stop_out"
assert_contains "$channels_stop_out" '"stopped"'
assert_contains "$channels_stop_out" '"host"'

channels_logout_out="$(run_gateway call channels.logout '{"channelId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$channels_logout_out"
assert_contains "$channels_logout_out" '"metis-fixture"'
assert_contains "$channels_logout_out" '"fixture:default"'
assert_contains "$channels_logout_out" '"manualStop"'
assert_contains "$channels_logout_out" '"channel"'
assert_contains "$channels_logout_out" '"cleared"'
assert_contains "$channels_logout_out" '"loggedOut"'

echo "[channel-regression] rpc plugins"
plugins_status_out="$(run_gateway call plugins.status '{"probe":true,"timeoutMs":3333}')"
printf '%s\n' "$plugins_status_out"
assert_contains "$plugins_status_out" '"pluginOrder"'
assert_contains "$plugins_status_out" '"pluginMeta"'
assert_contains "$plugins_status_out" '"pluginAccounts"'
assert_contains "$plugins_status_out" '"metis-fixture"'

plugins_list_out="$(run_gateway call plugins.list '{"probe":false}')"
printf '%s\n' "$plugins_list_out"
assert_contains "$plugins_list_out" '"plugins"'
assert_contains "$plugins_list_out" '"pluginAccounts"'

plugins_get_out="$(run_gateway call plugins.get '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_get_out"
assert_contains "$plugins_get_out" '"metis-fixture"'
assert_contains "$plugins_get_out" '"approval"'
assert_contains "$plugins_get_out" '"packageProbe"'
assert_contains "$plugins_get_out" '"setup"'
assert_contains "$plugins_get_out" '"hostStatus"'
assert_contains "$plugins_get_out" '"hostActions"'
assert_contains "$plugins_get_out" '"runtimeForwarders"'
assert_contains "$plugins_get_out" '"setupRegistry"'

plugins_runtime_out="$(run_gateway call plugins.runtime '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_runtime_out"
assert_contains "$plugins_runtime_out" '"runtime"'
assert_contains "$plugins_runtime_out" '"metis-fixture"'
assert_contains "$plugins_runtime_out" '"fixture:default"'

plugins_manager_out="$(run_gateway call plugins.manager '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_manager_out"
assert_contains "$plugins_manager_out" '"manager"'
assert_contains "$plugins_manager_out" '"monitorEnabledCount"'

plugins_bindings_out="$(run_gateway call plugins.bindings '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_bindings_out"
assert_contains "$plugins_bindings_out" '"bindings"'
assert_contains "$plugins_bindings_out" '"fixture:default"'
assert_contains "$plugins_bindings_out" '"configuredAccountIds"'

plugins_policy_out="$(run_gateway call plugins.policy)"
printf '%s\n' "$plugins_policy_out"
assert_contains "$plugins_policy_out" '"policy"'
assert_contains "$plugins_policy_out" '"byPolicyState"'

plugins_health_out="$(run_gateway call plugins.health)"
printf '%s\n' "$plugins_health_out"
assert_contains "$plugins_health_out" '"plugins"'
assert_contains "$plugins_health_out" '"byHealthState"'

plugins_health_actions_out="$(run_gateway call plugins.health.actions)"
printf '%s\n' "$plugins_health_actions_out"
assert_contains "$plugins_health_actions_out" '"actions"'

plugins_setup_apply_out="$(run_gateway call plugins.setup.apply '{"pluginId":"metis-fixture","config":{"token":"fixture-token","accountIds":["fixture:default"],"defaultAccountId":"fixture:default"}}')"
printf '%s\n' "$plugins_setup_apply_out"
assert_contains "$plugins_setup_apply_out" '"applied"'
assert_contains "$plugins_setup_apply_out" '"fixture:default"'
assert_contains "$plugins_setup_apply_out" '"bindings"'

plugins_actions_out="$(run_gateway call plugins.actions '{"pluginId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$plugins_actions_out"
assert_contains "$plugins_actions_out" '"actionNames"'

plugins_approvals_out="$(run_gateway call plugins.approvals)"
printf '%s\n' "$plugins_approvals_out"
assert_contains "$plugins_approvals_out" '"approval"'

plugins_package_state_out="$(run_gateway call plugins.package_state)"
printf '%s\n' "$plugins_package_state_out"
assert_contains "$plugins_package_state_out" '"packageProbe"'
assert_contains "$plugins_package_state_out" '"status"'
assert_contains "$plugins_package_state_out" '"actions"'

plugins_setup_out="$(run_gateway call plugins.setup)"
printf '%s\n' "$plugins_setup_out"
assert_contains "$plugins_setup_out" '"setup"'
assert_contains "$plugins_setup_out" '"metis-fixture"'
assert_contains "$plugins_setup_out" '"setupRegistry"'
assert_contains "$plugins_setup_out" '"actions"'

plugins_setup_registry_out="$(run_gateway call plugins.setup.registry '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_setup_registry_out"
assert_contains "$plugins_setup_registry_out" '"setupRegistry"'
assert_contains "$plugins_setup_registry_out" '"supported": true'

plugins_runtime_forwarders_out="$(run_gateway call plugins.runtime.forwarders '{"pluginId":"metis-fixture"}')"
printf '%s\n' "$plugins_runtime_forwarders_out"
assert_contains "$plugins_runtime_forwarders_out" '"runtimeForwarders"'
assert_contains "$plugins_runtime_forwarders_out" '"dispatchAction": true'

plugins_resolve_account_out="$(run_gateway call plugins.resolve_account '{"pluginId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$plugins_resolve_account_out"
assert_contains "$plugins_resolve_account_out" '"accountId": "fixture:default"'
assert_contains "$plugins_resolve_account_out" '"configured": true'

plugins_directory_out="$(run_gateway call plugins.directory '{"pluginId":"metis-fixture","accountId":"fixture:default","groupId":"fixture-group"}')"
printf '%s\n' "$plugins_directory_out"
assert_contains "$plugins_directory_out" '"supported": true'
assert_contains "$plugins_directory_out" '"fixture-peer"'
assert_contains "$plugins_directory_out" '"fixture-group"'

plugins_targets_out="$(run_gateway call plugins.targets '{"pluginId":"metis-fixture","accountId":"fixture:default","target":"fixture-peer"}')"
printf '%s\n' "$plugins_targets_out"
assert_contains "$plugins_targets_out" '"resolved": true'
assert_contains "$plugins_targets_out" '"targetKind": "peer"'

plugins_dispatch_out="$(run_gateway call plugins.actions.dispatch '{"pluginId":"metis-fixture","accountId":"fixture:default","action":"fixture-send-text","payload":{"text":"hello-from-dispatch"}}')"
printf '%s\n' "$plugins_dispatch_out"
assert_contains "$plugins_dispatch_out" '"dispatched": true'
assert_contains "$plugins_dispatch_out" '"echoedText": "hello-from-dispatch"'

plugins_start_out="$(run_gateway call plugins.start '{"pluginId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$plugins_start_out"
assert_contains "$plugins_start_out" '"started"'
assert_contains "$plugins_start_out" '"manager"'

plugins_send_out="$(run_gateway call plugins.send '{"pluginId":"metis-fixture","accountId":"fixture:default","peerId":"fixture-peer","text":"hello-from-plugin-regression"}')"
printf '%s\n' "$plugins_send_out"
assert_contains "$plugins_send_out" '"ok"'
assert_contains "$plugins_send_out" 'fixture-peer'

plugins_stop_out="$(run_gateway call plugins.stop '{"pluginId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$plugins_stop_out"
assert_contains "$plugins_stop_out" '"stopped"'
assert_contains "$plugins_stop_out" '"manager"'

plugins_logout_out="$(run_gateway call plugins.logout '{"pluginId":"metis-fixture","accountId":"fixture:default"}')"
printf '%s\n' "$plugins_logout_out"
assert_contains "$plugins_logout_out" '"cleared"'
assert_contains "$plugins_logout_out" '"plugin"'
assert_contains "$plugins_logout_out" '"loggedOut"'
assert_contains "$plugins_logout_out" '"manager"'

echo "[channel-regression] mcp list"
mcp_list_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')"
printf '%s\n' "$mcp_list_out"
assert_contains "$mcp_list_out" 'gateway.discover.detail'
assert_contains "$mcp_list_out" 'gateway.channels.status'
assert_contains "$mcp_list_out" 'gateway.channels.list'
assert_contains "$mcp_list_out" 'gateway.channels.get'
assert_contains "$mcp_list_out" 'gateway.channels.runtime'
assert_contains "$mcp_list_out" 'gateway.channels.health'
assert_contains "$mcp_list_out" 'gateway.channels.bindings'
assert_contains "$mcp_list_out" 'gateway.channels.policy'
assert_contains "$mcp_list_out" 'gateway.channels.manager'
assert_contains "$mcp_list_out" 'gateway.channels.health.actions'
assert_contains "$mcp_list_out" 'gateway.channels.start'
assert_contains "$mcp_list_out" 'gateway.channels.stop'
assert_contains "$mcp_list_out" 'gateway.channels.send'
assert_contains "$mcp_list_out" 'gateway.channels.logout'
assert_contains "$mcp_list_out" 'gateway.plugins.status'
assert_contains "$mcp_list_out" 'gateway.plugins.list'
assert_contains "$mcp_list_out" 'gateway.plugins.get'
assert_contains "$mcp_list_out" 'gateway.plugins.runtime'
assert_contains "$mcp_list_out" 'gateway.plugins.health'
assert_contains "$mcp_list_out" 'gateway.plugins.bindings'
assert_contains "$mcp_list_out" 'gateway.plugins.policy'
assert_contains "$mcp_list_out" 'gateway.plugins.manager'
assert_contains "$mcp_list_out" 'gateway.plugins.health.actions'
assert_contains "$mcp_list_out" 'gateway.plugins.actions'
assert_contains "$mcp_list_out" 'gateway.plugins.approvals'
assert_contains "$mcp_list_out" 'gateway.plugins.package_state'
assert_contains "$mcp_list_out" 'gateway.plugins.setup'
assert_contains "$mcp_list_out" 'gateway.plugins.setup.apply'
assert_contains "$mcp_list_out" 'gateway.plugins.setup.registry'
assert_contains "$mcp_list_out" 'gateway.plugins.runtime.forwarders'
assert_contains "$mcp_list_out" 'gateway.plugins.resolve_account'
assert_contains "$mcp_list_out" 'gateway.plugins.directory'
assert_contains "$mcp_list_out" 'gateway.plugins.targets'
assert_contains "$mcp_list_out" 'gateway.plugins.actions.dispatch'
assert_contains "$mcp_list_out" 'gateway.plugins.start'
assert_contains "$mcp_list_out" 'gateway.plugins.stop'
assert_contains "$mcp_list_out" 'gateway.plugins.send'
assert_contains "$mcp_list_out" 'gateway.plugins.logout'

echo "[channel-regression] mcp calls"
mcp_discover_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"gateway.discover.detail","arguments":{}}}')"
printf '%s\n' "$mcp_discover_out"
assert_contains "$mcp_discover_out" '"channelCatalog"'
assert_contains "$mcp_discover_out" '"metis-fixture"'

mcp_channels_status_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"gateway.channels.status","arguments":{"probe":true,"timeoutMs":2100}}}')"
printf '%s\n' "$mcp_channels_status_out"
assert_contains "$mcp_channels_status_out" '"channelAccounts"'
assert_contains "$mcp_channels_status_out" '"metis-fixture"'

mcp_channels_list_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"gateway.channels.list","arguments":{"probe":false}}}')"
printf '%s\n' "$mcp_channels_list_out"
assert_contains "$mcp_channels_list_out" '"channels"'

mcp_channels_get_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"gateway.channels.get","arguments":{"channelId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_channels_get_out"
assert_contains "$mcp_channels_get_out" '"metis-fixture"'

mcp_channels_get_telegram_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":140,"method":"tools/call","params":{"name":"gateway.channels.get","arguments":{"channelId":"telegram"}}}')"
printf '%s\n' "$mcp_channels_get_telegram_out"
assert_contains "$mcp_channels_get_telegram_out" '"telegram"'
assert_contains "$mcp_channels_get_telegram_out" '"supports"'
assert_contains "$mcp_channels_get_telegram_out" '"actions"'

mcp_channels_runtime_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"gateway.channels.runtime","arguments":{"channelId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_channels_runtime_out"
assert_contains "$mcp_channels_runtime_out" '"bootstrap"'
assert_contains "$mcp_channels_runtime_out" '"metis-fixture"'

mcp_channels_runtime_telegram_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":150,"method":"tools/call","params":{"name":"gateway.channels.runtime","arguments":{"channelId":"telegram","probe":true}}}')"
printf '%s\n' "$mcp_channels_runtime_telegram_out"
assert_contains "$mcp_channels_runtime_telegram_out" '"allowedUpdates"'
assert_contains "$mcp_channels_runtime_telegram_out" '"message_reaction"'
assert_contains "$mcp_channels_runtime_telegram_out" '"registrationPayload"'
assert_contains "$mcp_channels_runtime_telegram_out" '"healthSnapshot"'
assert_contains "$mcp_channels_runtime_telegram_out" '"offsetPersistenceEnabled"'
assert_contains "$mcp_channels_runtime_telegram_out" '"lastInboundUpdateId"'
assert_contains "$mcp_channels_runtime_telegram_out" '"liveProbe"'
assert_contains "$mcp_channels_runtime_telegram_out" '"mediaAudio"'
assert_contains "$mcp_channels_runtime_telegram_out" '"mediaVideoNote"'

mcp_channels_health_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"gateway.channels.health","arguments":{"probe":true}}}')"
printf '%s\n' "$mcp_channels_health_out"
assert_contains "$mcp_channels_health_out" '"byHealthState"'
assert_contains "$mcp_channels_health_out" '"telegram"'
assert_contains "$mcp_channels_health_out" '"healthSnapshot"'
assert_contains "$mcp_channels_health_out" '"offsetPersistenceEnabled"'
assert_contains "$mcp_channels_health_out" '"lastInboundUpdateId"'
assert_contains "$mcp_channels_health_out" '"liveProbe"'

mcp_channels_audit_telegram_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":160,"method":"tools/call","params":{"name":"gateway.channels.audit","arguments":{"channelId":"telegram"}}}')"
printf '%s\n' "$mcp_channels_audit_telegram_out"
assert_contains "$mcp_channels_audit_telegram_out" '"gateway-channels-audit"'
assert_contains "$mcp_channels_audit_telegram_out" '"T12"'
assert_contains "$mcp_channels_audit_telegram_out" '"registrationPayload"'
assert_contains "$mcp_channels_audit_telegram_out" '"healthSnapshot"'
assert_contains "$mcp_channels_audit_telegram_out" '"message_reaction"'
assert_contains "$mcp_channels_audit_telegram_out" '"mediaAudio"'
assert_contains "$mcp_channels_audit_telegram_out" '"mediaVideoNote"'
assert_contains "$mcp_channels_audit_telegram_out" '"liveProbe"'
assert_contains "$mcp_channels_audit_telegram_out" '"offsetPersistenceEnabled"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegramReactionRuntimeVisible"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegramLiveProbeRuntimeVisible"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegramMediaRuntimeVisible"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegramMediaPersistenceVisible"'
assert_contains "$mcp_channels_audit_telegram_out" '"downloadEnabled"'
assert_contains "$mcp_channels_audit_telegram_out" '"lastPersistedMediaId"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegramThreadBindingVisibleInDashboardSessions"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegramThreadBindingVisibleInControlUiSessions"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegramThreadBindingVisibleInControlUiWsSessions"'
assert_contains "$mcp_channels_audit_telegram_out" '"mcpOverHttp"'
assert_contains "$mcp_channels_audit_telegram_out" '"dashboardSessions"'
assert_contains "$mcp_channels_audit_telegram_out" '"controlUiSessionsHttp"'
assert_contains "$mcp_channels_audit_telegram_out" '"controlUiSessionsWs"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegram-live-probe-runtime-is-visible-across-consumers"'
assert_contains "$mcp_channels_audit_telegram_out" '"telegram-media-download-and-file-persistence-are-visible-across-consumers"'
assert_not_contains "$mcp_channels_audit_telegram_out" '"telegram-webhook-live-probe-remains-ops-followup"'
assert_not_contains "$mcp_channels_audit_telegram_out" '"telegram-media-download-and-file-persistence-remain-followups"'

mcp_channels_bindings_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"gateway.channels.bindings","arguments":{"channelId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_channels_bindings_out"
assert_contains "$mcp_channels_bindings_out" '"fixture:default"'

mcp_channels_policy_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"gateway.channels.policy","arguments":{}}}')"
printf '%s\n' "$mcp_channels_policy_out"
assert_contains "$mcp_channels_policy_out" '"policy"'

mcp_channels_manager_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"gateway.channels.manager","arguments":{"channelId":"telegram"}}}')"
printf '%s\n' "$mcp_channels_manager_out"
assert_contains "$mcp_channels_manager_out" '"manager"'

mcp_channels_health_actions_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"gateway.channels.health.actions","arguments":{}}}')"
printf '%s\n' "$mcp_channels_health_actions_out"
assert_contains "$mcp_channels_health_actions_out" '"actions"'

mcp_channels_start_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":201,"method":"tools/call","params":{"name":"gateway.channels.start","arguments":{"channelId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_channels_start_out"
assert_contains "$mcp_channels_start_out" '"started"'

mcp_channels_send_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":202,"method":"tools/call","params":{"name":"gateway.channels.send","arguments":{"channelId":"metis-fixture","accountId":"fixture:default","peerId":"fixture-peer","text":"hello-from-mcp-channel"}}}')"
printf '%s\n' "$mcp_channels_send_out"
assert_contains "$mcp_channels_send_out" '"ok"'

mcp_channels_stop_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":203,"method":"tools/call","params":{"name":"gateway.channels.stop","arguments":{"channelId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_channels_stop_out"
assert_contains "$mcp_channels_stop_out" '"stopped"'

mcp_channels_logout_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"gateway.channels.logout","arguments":{"channelId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_channels_logout_out"
assert_contains "$mcp_channels_logout_out" '"manualStop"'
assert_contains "$mcp_channels_logout_out" '"channel"'
assert_contains "$mcp_channels_logout_out" '"cleared"'
assert_contains "$mcp_channels_logout_out" '"loggedOut"'

mcp_plugins_status_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"gateway.plugins.status","arguments":{"probe":true,"timeoutMs":3100}}}')"
printf '%s\n' "$mcp_plugins_status_out"
assert_contains "$mcp_plugins_status_out" '"pluginAccounts"'
assert_contains "$mcp_plugins_status_out" '"metis-fixture"'

mcp_plugins_list_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"gateway.plugins.list","arguments":{"probe":false}}}')"
printf '%s\n' "$mcp_plugins_list_out"
assert_contains "$mcp_plugins_list_out" '"plugins"'

mcp_plugins_get_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"gateway.plugins.get","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_get_out"
assert_contains "$mcp_plugins_get_out" '"packageProbe"'
assert_contains "$mcp_plugins_get_out" '"hostStatus"'
assert_contains "$mcp_plugins_get_out" '"hostActions"'

mcp_plugins_runtime_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":25,"method":"tools/call","params":{"name":"gateway.plugins.runtime","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_runtime_out"
assert_contains "$mcp_plugins_runtime_out" '"runtime"'

mcp_plugins_health_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":26,"method":"tools/call","params":{"name":"gateway.plugins.health","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_health_out"
assert_contains "$mcp_plugins_health_out" '"byHealthState"'

mcp_plugins_bindings_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":27,"method":"tools/call","params":{"name":"gateway.plugins.bindings","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_bindings_out"
assert_contains "$mcp_plugins_bindings_out" '"fixture:default"'

mcp_plugins_policy_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":28,"method":"tools/call","params":{"name":"gateway.plugins.policy","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_policy_out"
assert_contains "$mcp_plugins_policy_out" '"policy"'

mcp_plugins_manager_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":29,"method":"tools/call","params":{"name":"gateway.plugins.manager","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_manager_out"
assert_contains "$mcp_plugins_manager_out" '"manager"'

mcp_plugins_health_actions_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"gateway.plugins.health.actions","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_health_actions_out"
assert_contains "$mcp_plugins_health_actions_out" '"actions"'

mcp_plugins_actions_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":301,"method":"tools/call","params":{"name":"gateway.plugins.actions","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_actions_out"
assert_contains "$mcp_plugins_actions_out" '"actionNames"'

mcp_plugins_approvals_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"gateway.plugins.approvals","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_approvals_out"
assert_contains "$mcp_plugins_approvals_out" '"approval"'

mcp_plugins_package_state_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":32,"method":"tools/call","params":{"name":"gateway.plugins.package_state","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_package_state_out"
assert_contains "$mcp_plugins_package_state_out" '"packageProbe"'
assert_contains "$mcp_plugins_package_state_out" '"status"'

mcp_plugins_setup_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":33,"method":"tools/call","params":{"name":"gateway.plugins.setup","arguments":{}}}')"
printf '%s\n' "$mcp_plugins_setup_out"
assert_contains "$mcp_plugins_setup_out" '"setup"'
assert_contains "$mcp_plugins_setup_out" '"setupRegistry"'

mcp_plugins_setup_apply_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":34,"method":"tools/call","params":{"name":"gateway.plugins.setup.apply","arguments":{"pluginId":"metis-fixture","config":{"token":"fixture-token","accountIds":["fixture:default"],"defaultAccountId":"fixture:default"}}}}')"
printf '%s\n' "$mcp_plugins_setup_apply_out"
assert_contains "$mcp_plugins_setup_apply_out" '"applied"'
assert_contains "$mcp_plugins_setup_apply_out" '"fixture:default"'

mcp_plugins_setup_registry_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":345,"method":"tools/call","params":{"name":"gateway.plugins.setup.registry","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_setup_registry_out"
assert_contains "$mcp_plugins_setup_registry_out" '"setupRegistry"'
assert_contains "$mcp_plugins_setup_registry_out" '"supported": true'

mcp_plugins_runtime_forwarders_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":346,"method":"tools/call","params":{"name":"gateway.plugins.runtime.forwarders","arguments":{"pluginId":"metis-fixture"}}}')"
printf '%s\n' "$mcp_plugins_runtime_forwarders_out"
assert_contains "$mcp_plugins_runtime_forwarders_out" '"runtimeForwarders"'
assert_contains "$mcp_plugins_runtime_forwarders_out" '"dispatchAction": true'

mcp_plugins_resolve_account_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":347,"method":"tools/call","params":{"name":"gateway.plugins.resolve_account","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_resolve_account_out"
assert_contains "$mcp_plugins_resolve_account_out" '"accountId": "fixture:default"'
assert_contains "$mcp_plugins_resolve_account_out" '"configured": true'

mcp_plugins_directory_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":348,"method":"tools/call","params":{"name":"gateway.plugins.directory","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","groupId":"fixture-group"}}}')"
printf '%s\n' "$mcp_plugins_directory_out"
assert_contains "$mcp_plugins_directory_out" '"fixture-peer"'
assert_contains "$mcp_plugins_directory_out" '"fixture-group"'

mcp_plugins_targets_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":349,"method":"tools/call","params":{"name":"gateway.plugins.targets","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","target":"fixture-peer"}}}')"
printf '%s\n' "$mcp_plugins_targets_out"
assert_contains "$mcp_plugins_targets_out" '"resolved": true'
assert_contains "$mcp_plugins_targets_out" '"targetKind": "peer"'

mcp_plugins_dispatch_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":350,"method":"tools/call","params":{"name":"gateway.plugins.actions.dispatch","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","action":"fixture-send-text","payload":{"text":"hello-from-mcp-dispatch"}}}}')"
printf '%s\n' "$mcp_plugins_dispatch_out"
assert_contains "$mcp_plugins_dispatch_out" '"dispatched": true'
assert_contains "$mcp_plugins_dispatch_out" '"echoedText": "hello-from-mcp-dispatch"'

mcp_plugins_start_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":341,"method":"tools/call","params":{"name":"gateway.plugins.start","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_start_out"
assert_contains "$mcp_plugins_start_out" '"started"'

mcp_plugins_send_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":342,"method":"tools/call","params":{"name":"gateway.plugins.send","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default","peerId":"fixture-peer","text":"hello-from-mcp-plugin"}}}')"
printf '%s\n' "$mcp_plugins_send_out"
assert_contains "$mcp_plugins_send_out" '"ok"'

mcp_plugins_stop_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":343,"method":"tools/call","params":{"name":"gateway.plugins.stop","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_stop_out"
assert_contains "$mcp_plugins_stop_out" '"stopped"'

mcp_plugins_logout_out="$(curl -fsS -X POST "http://127.0.0.1:${GATEWAY_PORT}/mcp" -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":344,"method":"tools/call","params":{"name":"gateway.plugins.logout","arguments":{"pluginId":"metis-fixture","accountId":"fixture:default"}}}')"
printf '%s\n' "$mcp_plugins_logout_out"
assert_contains "$mcp_plugins_logout_out" '"cleared"'
assert_contains "$mcp_plugins_logout_out" '"plugin"'
assert_contains "$mcp_plugins_logout_out" '"loggedOut"'

echo "[channel-regression] ok"
