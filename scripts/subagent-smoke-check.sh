#!/usr/bin/env bash
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u

TMP_DIR="$(mktemp -d /tmp/metis-subagent-smoke.XXXXXX)"
RUNTIME_HOME="${METIS_HOME:-${HOME}/.metis}"
LABEL="smoke-$(date +%s)"
RUN_TIMEOUT="${RUN_TIMEOUT:-180}"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

extract_field() {
  local json="$1"
  local field="$2"
  (printf '%s\n' "$json" | rg -o "\"${field}\"\\s*:\\s*\"[^\"]*\"" | tail -n 1 | sed -E "s/.*\"${field}\"\\s*:\\s*\"([^\"]*)\"/\\1/") || true
}

run_cli_prompt() {
  local prompt_file="$1"
  local escaped_prompt_file="${prompt_file//\'/\'\\\'\'}"
  perl -e 'alarm shift @ARGV; system @ARGV; exit($? == -1 ? 1 : $? >> 8)' \
    "$RUN_TIMEOUT" \
    zsh -lc "rtk cjpm run --skip-script --skip-build --name metis --run-args '--prompt-file ${escaped_prompt_file}'"
}

run_cli_prompt_background() {
  local prompt_file="$1"
  local output_file="$2"
  run_cli_prompt "$prompt_file" >"$output_file" 2>&1 &
}

with_metis_cjpm_build_lock rtk cjpm build -i

spawn_prompt="$TMP_DIR/spawn_prompt.txt"
cat > "$spawn_prompt" <<EOF
Use the \`sessions_spawn\` tool exactly once with these arguments:
- task: Explore the project at /Users/l3gi0n/work/workspace_cangjie/Metis. Briefly identify the package name from /Users/l3gi0n/work/workspace_cangjie/Metis/cjpm.toml only.
- label: ${LABEL}
- runtime: subagent
- agentId: explorer
- cwd: /Users/l3gi0n/work/workspace_cangjie/Metis
- cleanup: keep

After the tool call, output only the raw JSON result from the tool and nothing else.
EOF

spawn_output_file="$TMP_DIR/spawn_output.txt"
run_cli_prompt_background "${spawn_prompt}" "${spawn_output_file}"
spawn_pid=$!
deadline=$(( $(date +%s) + RUN_TIMEOUT ))
session_key=""
transcript_path=""
transcript_glob="$RUNTIME_HOME/agents/main/sessions/gateway_spawn_subagent-explorer-${LABEL}_*.jsonl"
while (( $(date +%s) < deadline )); do
  for candidate in $transcript_glob; do
    if [[ -f "$candidate" ]]; then
      transcript_path="$candidate"
      session_key="$(extract_field "$(sed -n '1,20p' "$candidate")" "sessionKey")"
      break
    fi
  done
  if [[ -n "$session_key" && -n "$transcript_path" ]]; then
    break
  fi
  sleep 1
done

kill "$spawn_pid" >/dev/null 2>&1 || true
wait "$spawn_pid" >/dev/null 2>&1 || true

if [[ -z "$session_key" || -z "$transcript_path" ]]; then
  echo "failed to resolve spawned session transcript for label ${LABEL}" >&2
  [[ -f "$spawn_output_file" ]] && cat "$spawn_output_file" >&2 || true
  ls -1 "$RUNTIME_HOME/agents/main/sessions" | tail -n 20 >&2 || true
  exit 1
fi

deadline=$(( $(date +%s) + RUN_TIMEOUT ))
while (( $(date +%s) < deadline )); do
  if rg -q '"role"[[:space:]]*:[[:space:]]*"assistant"' "$transcript_path"; then
    break
  fi
  sleep 2
done

if ! rg -q '"role"[[:space:]]*:[[:space:]]*"assistant"' "$transcript_path"; then
  echo "subagent transcript never recorded an assistant reply" >&2
  sed -n '1,240p' "$transcript_path" >&2 || true
  exit 1
fi

if ! rg -q 'metis' "$transcript_path"; then
  echo "subagent transcript missing expected package name" >&2
  sed -n '1,240p' "$transcript_path" >&2 || true
  exit 1
fi

if rg -q "target/release/bin/cli|can not find the 'target/release/bin/cli' file" "$transcript_path"; then
  echo "subagent transcript still references legacy cli binary path" >&2
  sed -n '1,240p' "$transcript_path" >&2 || true
  exit 1
fi

rtk cjpm run --skip-script --skip-build --name metis --run-args "gateway sessions clear $session_key" >/dev/null
rm -f "$transcript_path"
if [[ -e "$transcript_path" ]]; then
  echo "expected cleared session transcript to be deleted: $transcript_path" >&2
  exit 1
fi

echo "[subagent-smoke] ok"
