#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/build_lock.sh"

set +u
source /Users/l3gi0n/cangjie100/envsetup.sh
set -u
set +o pipefail
export MAGIC_MEMORY_DETERMINISTIC_NARRATIVE=1

TMP_HOME="$(mktemp -d /tmp/metis-memory.XXXXXX)"

cleanup() {
  local exit_code=$?
  rm -rf "${TMP_HOME}" >/dev/null 2>&1 || true
  return "${exit_code}"
}
trap cleanup EXIT
mkdir -p "$TMP_HOME/agents"

write_memory_config() {
  local backend="$1"
  cat >"$TMP_HOME/metis.json" <<EOF
{
  "memory": {
    "backend": "${backend}",
    "citations": "auto"
  }
}
EOF
}

run_local_agent_message() {
  local message
  message="$(printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g')"
  METIS_HOME="$TMP_HOME" METIS_CJPM_ROOT="$ROOT" \
    rtk cjpm run --skip-script --skip-build --name metis --run-args "agent --local --message \"$message\""
}

has_real_qmd() {
  command -v qmd >/dev/null 2>&1 && qmd --version >/dev/null 2>&1
}

run_qmd_cli() {
  local prompt
  prompt="$1"
  if has_real_qmd; then
    MAGIC_MEMORY_QMD_COMMAND="qmd" \
    MAGIC_MEMORY_QMD_SEARCH_MODE="search" \
    MAGIC_MEMORY_QMD_SESSIONS_ENABLED="true" \
    MAGIC_MEMORY_QMD_PATHS="memory" \
    run_cli_args 'qmd' "$prompt"
  else
    MAGIC_MEMORY_QMD_COMMAND="bash scripts/mock-qmd.sh" \
    MAGIC_MEMORY_QMD_SEARCH_MODE="search" \
    run_cli_args 'qmd' "$prompt"
  fi
}

run_qmd_cli_with_env() {
  local prompt
  prompt="$1"
  shift
  write_memory_config "qmd"
  if has_real_qmd; then
    env \
      METIS_HOME="$TMP_HOME" \
      METIS_CJPM_ROOT="$ROOT" \
      MAGIC_MEMORY_QMD_COMMAND="qmd" \
      MAGIC_MEMORY_QMD_SEARCH_MODE="search" \
      MAGIC_MEMORY_QMD_SESSIONS_ENABLED="true" \
      MAGIC_MEMORY_QMD_PATHS="memory" \
      "$@" \
      bash -lc "cd '$ROOT' && msg=\$(printf '%s' '$prompt' | perl -0pe 's/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g') && rtk cjpm run --skip-script --skip-build --name metis --run-args \"agent --local --message \\\"\$msg\\\"\""
  else
    env \
      METIS_HOME="$TMP_HOME" \
      METIS_CJPM_ROOT="$ROOT" \
      MAGIC_MEMORY_QMD_COMMAND="bash scripts/mock-qmd.sh" \
      MAGIC_MEMORY_QMD_SEARCH_MODE="search" \
      "$@" \
      bash -lc "cd '$ROOT' && msg=\$(printf '%s' '$prompt' | perl -0pe 's/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g') && rtk cjpm run --skip-script --skip-build --name metis --run-args \"agent --local --message \\\"\$msg\\\"\""
  fi
}

run_cli() {
  run_cli_args "local" "$1"
}

run_cli_args() {
  local backend
  backend="$1"
  write_memory_config "$backend"
  run_local_agent_message "$2"
}

today="$(date +%F)"
mkdir -p "$ROOT/memory"
cat >"$ROOT/memory/$today.md" <<EOF
# $today

## Build Notes
- Keep memory promotion replay-safe.
- Daily ingestion should surface concise durable snippets.

## Follow-ups
- Verify dreaming phases ingest daily notes before ranking.
EOF

mkdir -p "$TMP_HOME/gateway-sessions"
cat >"$TMP_HOME/gateway-sessions/qmd_regression_session.jsonl" <<EOF
{"kind":"meta","v":"1","sessionKey":"gateway:qmd:regression"}
{"role":"user","text":"Please remember that replay-safe memory promotion matters.","ts":"1"}
{"role":"assistant","text":"I will keep durable snippets replay-safe and compact.","ts":"2"}
EOF

echo "[memory-regression] build"
with_metis_cjpm_build_lock rtk cjpm build -i >/dev/null

echo "[memory-regression] /memory status"
status_out="$(run_cli '/memory status')"
grep -q 'Memory backend:' <<<"$status_out" || {
  echo "status output missing backend line" >&2
  exit 1
}

echo "[memory-regression] /memory status --json"
status_json="$(run_cli_args 'local' '/memory status --json')"
grep -Eq '"action"[[:space:]]*:[[:space:]]*"memory_status"' <<<"$status_json" || {
  echo "status json missing action" >&2
  exit 1
}
grep -Eq '"provider"[[:space:]]*:[[:space:]]*"local"' <<<"$status_json" || {
  echo "status json missing default provider" >&2
  exit 1
}

echo "[memory-regression] /memory status --json with --memory-provider builtin"
status_compat_json="$(run_cli '/memory status --json --backend builtin')"
grep -Eq '"previewResolvedBackendConfig"[[:space:]]*:' <<<"$status_compat_json" || {
  echo "status json missing builtin preview config" >&2
  exit 1
}
grep -Eq '"providerId"[[:space:]]*:[[:space:]]*"builtin"' <<<"$status_compat_json" || {
  echo "status json missing builtin preview provider" >&2
  exit 1
}
grep -Eq '"backend"[[:space:]]*:[[:space:]]*"builtin-file"' <<<"$status_compat_json" || {
  echo "status json missing builtin preview backend" >&2
  exit 1
}
grep -Eq '"availableProviders"[[:space:]]*:' <<<"$status_compat_json" || {
  echo "status json missing provider inventory" >&2
  exit 1
}

echo "[memory-regression] /memory status --json with --memory-provider external"
status_external_json="$(
  MAGIC_MEMORY_EXTERNAL_COMMAND="bash" \
  MAGIC_MEMORY_EXTERNAL_ARGS="scripts/mock-memory-backend.sh" \
  MAGIC_MEMORY_EXTERNAL_BACKEND="mock-external" \
  MAGIC_MEMORY_EXTERNAL_INDEX_PATH="external-memory/mock-index" \
  run_cli '/memory status --json --backend external'
)"
grep -Eq '"previewResolvedBackendConfig"[[:space:]]*:' <<<"$status_external_json" || {
  echo "status json missing external preview config" >&2
  exit 1
}
grep -Eq '"providerId"[[:space:]]*:[[:space:]]*"external"' <<<"$status_external_json" || {
  echo "status json missing external preview provider" >&2
  exit 1
}
grep -Eq '"backend"[[:space:]]*:[[:space:]]*"external-command"' <<<"$status_external_json" || {
  echo "status json missing external preview backend" >&2
  exit 1
}

echo "[memory-regression] /memory status --json with --memory-provider qmd"
status_qmd_json="$(run_qmd_cli '/memory status --json --backend qmd')"
grep -Eq '"previewResolvedBackendConfig"[[:space:]]*:' <<<"$status_qmd_json" || {
  echo "status json missing qmd preview config" >&2
  exit 1
}
grep -Eq '"providerId"[[:space:]]*:[[:space:]]*"qmd"' <<<"$status_qmd_json" || {
  echo "status json missing qmd preview provider" >&2
  exit 1
}
grep -Eq '"backend"[[:space:]]*:[[:space:]]*"qmd"' <<<"$status_qmd_json" || {
  echo "status json missing qmd preview backend" >&2
  exit 1
}

# Restore local provider for the rest of the regression run.
run_cli_args 'local' '/memory status --json' >/dev/null

echo "[memory-regression] /memory status --deep --json"
status_deep_json="$(run_cli '/memory status --deep --json')"
grep -Eq '"deep"[[:space:]]*:[[:space:]]*true' <<<"$status_deep_json" || {
  echo "status --deep json missing deep flag" >&2
  exit 1
}
grep -Eq '"dailyIngestionStatePath"[[:space:]]*:' <<<"$status_deep_json" || {
  echo "status --deep json missing daily ingestion state path" >&2
  exit 1
}
grep -Eq '"dreamingMarkdownConfigPath"[[:space:]]*:' <<<"$status_deep_json" || {
  echo "status --deep json missing dreaming markdown config path" >&2
  exit 1
}
grep -Eq '"dreamingNarrativeRunsPath"[[:space:]]*:' <<<"$status_deep_json" || {
  echo "status --deep json missing dreaming narrative runs path" >&2
  exit 1
}

echo "[memory-regression] /memory status --fix"
status_fix_out="$(run_cli '/memory status --fix')"
grep -q 'Memory fix:' <<<"$status_fix_out" || {
  echo "status --fix output missing fix header" >&2
  exit 1
}

echo "[memory-regression] /memory index"
index_out="$(run_cli '/memory index')"
printf '%s\n' "$index_out" | grep -q 'Memory index' || {
  echo "index output missing success text" >&2
  exit 1
}

echo "[memory-regression] /memory index --force"
index_force_out="$(run_cli '/memory index --force')"
printf '%s\n' "$index_force_out" | grep -q 'Memory index' || {
  echo "index --force output missing success text" >&2
  exit 1
}

echo "[memory-regression] /memory search"
search_json="$(run_cli_args 'local' '/memory search memory --json')"
grep -Eq '"query"[[:space:]]*:[[:space:]]*"memory"' <<<"$search_json" || {
  echo "memory search output missing query" >&2
  exit 1
}
grep -Eq '"results"[[:space:]]*:' <<<"$search_json" || {
  echo "memory search output missing results" >&2
  exit 1
}

echo "[memory-regression] /memory search --query --max-results"
search_query_json="$(run_cli_args 'local' '/memory search --query memory --max-results 2 --min-score 0.1 --json')"
grep -Eq '"query"[[:space:]]*:[[:space:]]*"memory"' <<<"$search_query_json" || {
  echo "memory search --query output missing query" >&2
  exit 1
}

echo "[memory-regression] /memory promote --json"
promote_json="$(run_cli '/memory promote --json')"
printf '%s\n' "$promote_json" | grep -Eq '"action"[[:space:]]*:[[:space:]]*"memory_promote_preview"' || {
  echo "promote json missing action" >&2
  exit 1
}

echo "[memory-regression] /memory promote --json --include-promoted"
promote_include_json="$(run_cli '/memory promote --json --include-promoted')"
printf '%s\n' "$promote_include_json" | grep -Eq '"includePromoted"[[:space:]]*:[[:space:]]*true' || {
  echo "promote include-promoted json missing flag" >&2
  exit 1
}

echo "[memory-regression] /memory promote explain"
explain_json="$(run_cli '/memory promote explain memory --json')"
printf '%s\n' "$explain_json" | grep -Eq '"action"[[:space:]]*:[[:space:]]*"memory_promote_explain"|"status"[[:space:]]*:[[:space:]]*"not_found"' || {
  echo "promote explain output missing expected fields" >&2
  exit 1
}

echo "[memory-regression] /memory promote-explain"
explain_alias_json="$(run_cli '/memory promote-explain memory --json --limit 4')"
printf '%s\n' "$explain_alias_json" | grep -Eq '"action"[[:space:]]*:[[:space:]]*"memory_promote_explain"|"status"[[:space:]]*:[[:space:]]*"not_found"' || {
  echo "promote-explain alias output missing expected fields" >&2
  exit 1
}

echo "[memory-regression] /memory rem-harness --json"
rem_json="$(run_cli '/memory rem-harness --json')"
printf '%s\n' "$rem_json" | grep -Eq '"action"[[:space:]]*:[[:space:]]*"memory_rem_harness"' || {
  echo "rem-harness json missing action" >&2
  exit 1
}

echo "[memory-regression] /memory rem-harness --apply"
rem_apply_out="$(run_cli '/memory rem-harness --apply')"
printf '%s\n' "$rem_apply_out" | grep -q 'REM harness report written:' || {
  echo "rem-harness apply output missing success text" >&2
  exit 1
}

echo "[memory-regression] /memory dreaming status"
dream_status_json="$(run_cli '/memory dreaming status')"
printf '%s\n' "$dream_status_json" | grep -Eq '"action"[[:space:]]*:[[:space:]]*"memory_dreaming_status"' || {
  echo "dreaming status output missing action" >&2
  exit 1
}

echo "[memory-regression] /dreaming status"
dream_alias_status_json="$(run_cli '/dreaming status')"
printf '%s\n' "$dream_alias_status_json" | grep -Eq '"action"[[:space:]]*:[[:space:]]*"memory_dreaming_status"' || {
  echo "/dreaming alias output missing action" >&2
  exit 1
}

echo "[memory-regression] /memory dreaming reconcile"
dream_reconcile_out="$(run_cli '/memory dreaming reconcile')"
printf '%s\n' "$dream_reconcile_out" | grep -Eq 'Memory Light Dreaming|Memory REM Dreaming|已添加/更新 cron 任务' || {
  echo "dreaming reconcile output missing expected cron text" >&2
  exit 1
}

echo "[memory-regression] /memory dreaming register"
dream_register_out="$(run_cli '/memory dreaming register')"
printf '%s\n' "$dream_register_out" | grep -Eq 'Memory Light Dreaming|Memory REM Dreaming|已添加/更新 cron 任务' || {
  echo "dreaming register output missing expected cron text" >&2
  exit 1
}

echo "[memory-regression] /memory dreaming sweep light"
dream_light_out="$(run_cli '/memory dreaming sweep light')"
printf '%s\n' "$dream_light_out" | grep -Eq 'Light dreaming report written:|Deep phase is responsible for durable promotion' || {
  echo "dreaming sweep light output missing success text" >&2
  exit 1
}
printf '%s\n' "$dream_light_out" | grep -q 'daily-ingestion phase=light' || {
  echo "dreaming sweep light output missing daily ingestion summary" >&2
  exit 1
}

echo "[memory-regression] /memory dreaming sweep rem"
dream_rem_out="$(run_cli '/memory dreaming sweep rem')"
printf '%s\n' "$dream_rem_out" | grep -q 'REM harness report written:' || {
  echo "dreaming sweep rem output missing success text" >&2
  exit 1
}
grep -q '<!-- metis:dreaming:light:start -->' "$ROOT/DREAMS.md" || {
  echo "DREAMS.md missing light managed block" >&2
  exit 1
}
grep -q '<!-- metis:dreaming:rem:start -->' "$ROOT/DREAMS.md" || {
  echo "DREAMS.md missing rem managed block" >&2
  exit 1
}

echo "[memory-regression] /memory dreaming sweep deep"
dream_deep_out="$(run_cli '/memory dreaming sweep deep')"
printf '%s\n' "$dream_deep_out" | grep -q 'Deep dreaming report written:' || {
  echo "dreaming sweep deep output missing success text" >&2
  exit 1
}
printf '%s\n' "$dream_deep_out" | grep -Eq 'Promoted [0-9]+ candidate|No promote candidates found' || {
  echo "dreaming sweep deep output missing promotion result" >&2
  exit 1
}
grep -q '<!-- metis:dreaming:deep:start -->' "$ROOT/DREAMS.md" || {
  echo "DREAMS.md missing deep managed block" >&2
  exit 1
}

echo "[memory-regression] /memory dreaming sweep"
dream_sweep_out="$(run_cli '/memory dreaming sweep')"
printf '%s\n' "$dream_sweep_out" | grep -q 'Memory dreaming sweep completed.' || {
  echo "dreaming sweep output missing success text" >&2
  exit 1
}

echo "[memory-regression] ok"
