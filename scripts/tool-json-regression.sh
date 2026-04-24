#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_DIR="$(mktemp -d /tmp/metis-tool-json.XXXXXX)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_prompt() {
  local prompt_file="$1"
  rtk cjpm run --skip-script --skip-build --name metis --run-args "--prompt-file ${prompt_file}"
}

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

with_metis_cjpm_build_lock rtk cjpm build -i

sessions_list_prompt="$TMP_DIR/sessions_list.txt"
cat > "$sessions_list_prompt" <<'EOF'
Use the `sessions_list` tool exactly once with:
- limit: 3
- messageLimit: 1

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

gateway_status_prompt="$TMP_DIR/gateway_status.txt"
cat > "$gateway_status_prompt" <<'EOF'
Use the `gateway` tool exactly once with:
- action: status

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

cron_status_prompt="$TMP_DIR/cron_status.txt"
cat > "$cron_status_prompt" <<'EOF'
Use the `cron` tool exactly once with:
- action: status

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

message_poll_prompt="$TMP_DIR/message_poll.txt"
cat > "$message_poll_prompt" <<'EOF'
Use the `message` tool exactly once with:
- action: poll
- channel: qq
- to: regression-peer
- poll: Lunch?|Rice|Noodles|Salad

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

sessions_spawn_prompt="$TMP_DIR/sessions_spawn.txt"
cat > "$sessions_spawn_prompt" <<'EOF'
Use the `sessionsSpawn` tool exactly once with:
- shortLabel: regression-json

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

sessions_history_prompt="$TMP_DIR/sessions_history.txt"
cat > "$sessions_history_prompt" <<'EOF'
Use the `sessionsHistory` tool exactly once with:
- sessionKey: main
- maxEntries: 2

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

sessions_send_prompt="$TMP_DIR/sessions_send.txt"
cat > "$sessions_send_prompt" <<'EOF'
Use the `sessionsSend` tool exactly once with:
- sessionKey: main
- message: regression check
- role: system

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

sessions_list_output="$(run_prompt "$sessions_list_prompt")"
printf '%s\n' "$sessions_list_output"
assert_matches "$sessions_list_output" '"action"\s*:\s*"sessions_list"'
assert_matches "$sessions_list_output" '"status"\s*:\s*"ok"'
assert_matches "$sessions_list_output" '"sessions"\s*:'

gateway_status_output="$(run_prompt "$gateway_status_prompt")"
printf '%s\n' "$gateway_status_output"
assert_matches "$gateway_status_output" '"action"\s*:\s*"status"'
assert_matches "$gateway_status_output" '"gateway"\s*:'

cron_status_output="$(run_prompt "$cron_status_prompt")"
printf '%s\n' "$cron_status_output"
assert_matches "$cron_status_output" '"action"\s*:\s*"status"'
assert_matches "$cron_status_output" '"path"\s*:'

message_poll_output="$(run_prompt "$message_poll_prompt")"
printf '%s\n' "$message_poll_output"
assert_matches "$message_poll_output" '"action"\s*:\s*"poll"'
assert_matches "$message_poll_output" '"payloadKind"\s*:\s*"poll"'
assert_matches "$message_poll_output" '"pollTitle"\s*:\s*"Lunch\?"'
assert_matches "$message_poll_output" '"pollOptions"\s*:'

sessions_spawn_output="$(run_prompt "$sessions_spawn_prompt")"
printf '%s\n' "$sessions_spawn_output"
assert_matches "$sessions_spawn_output" '"action"\s*:\s*"sessionsSpawn"'
assert_matches "$sessions_spawn_output" '"sessionKey"\s*:'

sessions_history_output="$(run_prompt "$sessions_history_prompt")"
printf '%s\n' "$sessions_history_output"
assert_matches "$sessions_history_output" '"action"\s*:\s*"sessionsHistory"'
assert_matches "$sessions_history_output" '"history"\s*:'

sessions_send_output="$(run_prompt "$sessions_send_prompt")"
printf '%s\n' "$sessions_send_output"
assert_matches "$sessions_send_output" '"action"\s*:\s*"sessionsSend"'
assert_matches "$sessions_send_output" '"role"\s*:\s*"system"'
