#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

BIN="$ROOT/target/release/bin/metis"
ITERATIONS="${ITERATIONS:-10}"
PORT="${PORT:-28789}"
TMP_ROOT="$(mktemp -d /tmp/metis-gateway-timing.XXXXXX)"
FIXTURE_PLUGIN_ID="metis-fixture"
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
  rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

prepare_runtime_env

mkdir -p target build-script-cache/release/metis/bin build-script-cache/release/magic/bin
with_metis_cjpm_build_lock rtk cjpm build -i >/dev/null

prepare_home() {
  local home_dir="$1"
  mkdir -p "$home_dir"
  mkdir -p "$home_dir/gateway-plugins"
  cp -R "$ROOT/scripts/fixtures/metis-fixture-plugin" "$home_dir/gateway-plugins/$FIXTURE_PLUGIN_ID"
  cat >"$home_dir/metis.json" <<EOF
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
    "port": ${PORT},
    "auth": { "mode": "none" },
    "controlUi": { "enabled": true, "allowInsecureAuth": true },
    "http": {
      "endpoints": {
        "chatCompletions": { "enabled": true },
        "responses": { "enabled": true }
      }
    },
    "gatewayPlugins": [
      {
        "id": "${FIXTURE_PLUGIN_ID}",
        "enabled": true
      }
    ]
  }
}
EOF
}

wait_for_health() {
  local home_dir="$1"
  local url="http://127.0.0.1:${PORT}/healthz"
  for _ in $(seq 1 120); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  echo "health check timeout for $home_dir" >&2
  return 1
}

latest_app_log() {
  local home_dir="$1"
  ls -1t "$home_dir/logs" 2>/dev/null | head -n 1
}

extract_timing_from_file() {
  local file="$1"
  local pattern="$2"
  local key="$3"
  rg "$pattern" "$file" -o -r '$0' 2>/dev/null | sed -nE "s/.*${key}=([0-9]+).*/\\1/p" | tail -n 1
}

extract_step_elapsed() {
  local file="$1"
  local prefix="$2"
  local step="$3"
  sed -nE "s/.*${prefix}.*step=${step}.*elapsedMs=([0-9]+).*/\\1/p" "$file" | tail -n 1
}

stop_gateway_best_effort() {
  local home_dir="$1"
  METIS_HOME="$home_dir" METIS_CJPM_ROOT="$ROOT" "$BIN" gateway stop >/dev/null 2>&1 || true
  sleep 1
}

print_mode_summary() {
  local mode="$1"
  local result_file="$2"
  echo
  echo "== ${mode} summary =="
  cat "$result_file"
  awk '
    BEGIN { ext_sum=0; ext_count=0; poll_sum=0; poll_count=0; launch_sum=0; launch_count=0; stop_sum=0; stop_count=0; }
    {
      for (i=1; i<=NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "externalReadyMs" && kv[2] != "") { ext_sum += kv[2]; ext_count++ }
        if (kv[1] == "pollLoopMs" && kv[2] != "") { poll_sum += kv[2]; poll_count++ }
        if (kv[1] == "launchMs" && kv[2] != "") { launch_sum += kv[2]; launch_count++ }
        if (kv[1] == "stopMs" && kv[2] != "") { stop_sum += kv[2]; stop_count++ }
      }
    }
    END {
      if (ext_count > 0) printf("avg externalReadyMs=%.1f\n", ext_sum / ext_count)
      if (poll_count > 0) printf("avg pollLoopMs=%.1f\n", poll_sum / poll_count)
      if (launch_count > 0) printf("avg launchMs=%.1f\n", launch_sum / launch_count)
      if (stop_count > 0) printf("avg stopMs=%.1f\n", stop_sum / stop_count)
    }
  ' "$result_file"
}

run_foreground_mode() {
  local mode="$1"
  local result_file="$2"
  : >"$result_file"
  for i in $(seq 1 "$ITERATIONS"); do
    local home_dir="$TMP_ROOT/${mode}-${i}"
    prepare_home "$home_dir"
    local cmd_log="$home_dir/${mode}.cmd.log"
    local start_ms end_ms ready_ms log_name app_log poll_ms http_ms control_ms start_done_ms
    start_ms="$(python3 - <<'PY'
import time
print(int(time.time()*1000))
PY
)"
    METIS_HOME="$home_dir" METIS_CJPM_ROOT="$ROOT" "$BIN" gateway "$mode" >"$cmd_log" 2>&1 &
    local pid="$!"
    wait_for_health "$home_dir"
    end_ms="$(python3 - <<'PY'
import time
print(int(time.time()*1000))
PY
)"
    ready_ms=$((end_ms - start_ms))
    sleep 1
    log_name="$(latest_app_log "$home_dir")"
    app_log="$home_dir/logs/$log_name"
    poll_ms="$(extract_step_elapsed "$app_log" "Gateway\\.serve\\.timing:" "poll-loop-enter")"
    http_ms="$(extract_step_elapsed "$app_log" "Gateway\\.serve\\.timing:" "http-started")"
    control_ms="$(extract_step_elapsed "$app_log" "Gateway\\.serve\\.timing:" "control-ui-started")"
    start_done_ms="$(extract_step_elapsed "$app_log" "Gateway\\.serve\\.timing:" "gateway-start-done")"
    echo "iter=$i externalReadyMs=${ready_ms} pollLoopMs=${poll_ms:-} httpMs=${http_ms:-} controlUiMs=${control_ms:-} gatewayStartDoneMs=${start_done_ms:-}" >>"$result_file"
    stop_gateway_best_effort "$home_dir"
    wait "$pid" >/dev/null 2>&1 || true
  done
}

run_restart_mode() {
  local result_file="$1"
  : >"$result_file"
  for i in $(seq 1 "$ITERATIONS"); do
    local home_dir="$TMP_ROOT/restart-${i}"
    prepare_home "$home_dir"
    local base_log="$home_dir/run-before-restart.log"
    METIS_HOME="$home_dir" METIS_CJPM_ROOT="$ROOT" "$BIN" gateway run >"$base_log" 2>&1 &
    local pid="$!"
    wait_for_health "$home_dir"
    sleep 1
    local restart_log="$home_dir/restart.cmd.log"
    local start_ms end_ms ready_ms stop_ms launch_ms log_name app_log poll_ms
    start_ms="$(python3 - <<'PY'
import time
print(int(time.time()*1000))
PY
)"
    METIS_HOME="$home_dir" METIS_CJPM_ROOT="$ROOT" "$BIN" gateway restart >"$restart_log" 2>&1
    wait_for_health "$home_dir"
    end_ms="$(python3 - <<'PY'
import time
print(int(time.time()*1000))
PY
)"
    ready_ms=$((end_ms - start_ms))
    sleep 1
    stop_ms="$(extract_step_elapsed "$restart_log" "\\[gateway\\.timing\\] flow=restart" "stop-done")"
    launch_ms="$(extract_step_elapsed "$restart_log" "\\[gateway\\.timing\\] flow=restart" "launch-done")"
    log_name="$(latest_app_log "$home_dir")"
    app_log="$home_dir/logs/$log_name"
    poll_ms="$(extract_step_elapsed "$app_log" "Gateway\\.serve\\.timing:" "poll-loop-enter")"
    echo "iter=$i externalReadyMs=${ready_ms} stopMs=${stop_ms:-} launchMs=${launch_ms:-} pollLoopMs=${poll_ms:-}" >>"$result_file"
    stop_gateway_best_effort "$home_dir"
    wait "$pid" >/dev/null 2>&1 || true
  done
}

RUN_RESULTS="$TMP_ROOT/run.results"
SERVE_RESULTS="$TMP_ROOT/serve.results"
RESTART_RESULTS="$TMP_ROOT/restart.results"

run_foreground_mode "run" "$RUN_RESULTS"
run_foreground_mode "serve" "$SERVE_RESULTS"
run_restart_mode "$RESTART_RESULTS"

print_mode_summary "run" "$RUN_RESULTS"
print_mode_summary "serve" "$SERVE_RESULTS"
print_mode_summary "restart" "$RESTART_RESULTS"
