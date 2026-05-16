#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/metis-agentteam-gate-test.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  echo "[agentteam-gate-test] ERROR: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  rg -n "$pattern" "$file" >/dev/null || fail "$file does not contain expected pattern: $pattern"
}

assert_tree_not_contains_secret() {
  local dir="$1"
  if rg -n -i 'appSecret|accessToken|refreshToken|Authorization|bot[ _-]?token|xox[baprs]-|sk-[A-Za-z0-9_-]{16,}|[0-9]{5,}:[A-Za-z0-9_-]{20,}|bearer[[:space:]]+[A-Za-z0-9._-]{8,}' "$dir" >/dev/null; then
    fail "secret-like evidence found under $dir"
  fi
}

run_gate() {
  local home="$1"
  local metis_home="$2"
  local report_dir="$3"
  local log_file="$4"
  env -i \
    PATH="$PATH" \
    HOME="$home" \
    METIS_AGENTTEAM_SKIP_ENVSETUP=1 \
    METIS_HOME="$metis_home" \
    METIS_AGENTTEAM_REPORT_DIR="$report_dir" \
    bash "$ROOT/scripts/agentteam-manual-acceptance-gate.sh" >"$log_file" 2>&1
}

fake_home="$TMP_ROOT/operator-home"
metis_home="$TMP_ROOT/metis-home"
report_dir="$TMP_ROOT/evidence"
mkdir -p "$fake_home"

run_gate "$fake_home" "$metis_home" "$report_dir" "$TMP_ROOT/success.log"

[[ -f "$report_dir/report.json" ]] || fail "report.json was not written"
[[ -f "$report_dir/manual-acceptance-template.md" ]] || fail "manual-acceptance-template.md was not written"
assert_file_contains "$report_dir/report.json" '"series": "23"'
assert_file_contains "$report_dir/report.json" '"id": "series23"'
assert_file_contains "$report_dir/report.json" '"phaseStatus"'
assert_file_contains "$report_dir/report.json" '"manualAcceptance"'
assert_file_contains "$report_dir/report.json" '"operatorGuidance"'
assert_file_contains "$report_dir/report.json" '"releaseVerification"'
assert_file_contains "$report_dir/report.json" '"externalResources"'
assert_file_contains "$report_dir/report.json" '"envOptIn"'
assert_file_contains "$report_dir/report.json" '"id": "phase1"'
assert_file_contains "$report_dir/report.json" '"id": "phase2"'
assert_file_contains "$report_dir/report.json" '"id": "phase9"'
assert_file_contains "$report_dir/report.json" '"id": "G11"'
assert_file_contains "$report_dir/report.json" '"id": "G25"'
assert_file_contains "$report_dir/report.json" '"id": "G26"'
assert_file_contains "$report_dir/report.json" '"id": "M32"'
assert_file_contains "$report_dir/report.json" '"status": "local-pass"'
assert_file_contains "$report_dir/report.json" '"status": "skipped"'
assert_file_contains "$report_dir/report.json" '"status": "external-resource-required"'
assert_file_contains "$report_dir/report.json" '"status": "operator-record-required"'
assert_file_contains "$report_dir/report.json" '"realHomeBlocked": true'
assert_file_contains "$report_dir/report.json" '"rawSensitiveValuesRecorded": false'
assert_file_contains "$report_dir/manual-acceptance-template.md" '## Phase 0 Source Matrix'
assert_file_contains "$report_dir/manual-acceptance-template.md" '## Phase 1 Telegram Live Gate'
assert_file_contains "$report_dir/manual-acceptance-template.md" '## Phase 2 Feishu Route Live Gate'
assert_file_contains "$report_dir/manual-acceptance-template.md" '## Phase 3 Feishu OAuth And OAPI Live Gate'
assert_file_contains "$report_dir/manual-acceptance-template.md" '## Phase 9 Release Evidence Pack'
assert_file_contains "$report_dir/manual-acceptance-template.md" '\| G11 \| skipped \|'
assert_file_contains "$report_dir/manual-acceptance-template.md" '\| G25 \| local-pass \|'
assert_file_contains "$report_dir/manual-acceptance-template.md" '\| G26 \| operator-record-required \|'
assert_file_contains "$report_dir/manual-acceptance-template.md" '\| M32 \| local-pass \|'
assert_tree_not_contains_secret "$report_dir"

real_home="$TMP_ROOT/real-home"
mkdir -p "$real_home"
if env -i \
  PATH="$PATH" \
  HOME="$real_home" \
  METIS_AGENTTEAM_SKIP_ENVSETUP=1 \
  METIS_AGENTTEAM_ALLOW_REAL_HOME=1 \
  METIS_HOME="$real_home/.metis" \
  bash "$ROOT/scripts/agentteam-manual-acceptance-gate.sh" >"$TMP_ROOT/real-home.log" 2>&1; then
  fail "gate accepted HOME/.metis even though Phase 0 requires isolated METIS_HOME"
fi
assert_file_contains "$TMP_ROOT/real-home.log" 'real home'

echo "[agentteam-gate-test] passed"
