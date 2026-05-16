#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

if [[ "${METIS_AGENTTEAM_SKIP_ENVSETUP:-0}" != "1" && -f /Users/l3gi0n/cangjie100/envsetup.sh ]]; then
  set +u
  source /Users/l3gi0n/cangjie100/envsetup.sh
  set -u
fi

fail() {
  echo "[agentteam-gate] ERROR: $*" >&2
  exit 1
}

info() {
  echo "[agentteam-gate] $*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

flag_enabled() {
  local name="$1"
  case "${!name:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

redacted_status() {
  if [[ -n "${1:-}" ]]; then
    printf "provided-redacted"
  else
    printf "missing"
  fi
}

resource_present() {
  local name="$1"
  [[ -n "${!name:-}" ]]
}

all_resources_present() {
  local name
  for name in "$@"; do
    resource_present "$name" || return 1
  done
  return 0
}

resource_json_line() {
  local domain="$1"
  local env_name="$2"
  local label="$3"
  local required_for="$4"
  local suffix="$5"
  local status
  status="$(redacted_status "${!env_name:-}")"
  printf '    {"domain": "%s", "env": "%s", "label": "%s", "requiredFor": "%s", "status": "%s", "value": "not-recorded"}%s\n' \
    "$domain" "$env_name" "$label" "$required_for" "$status" "$suffix"
}

manual_json_line() {
  local id="$1"
  local status="$2"
  local phase="$3"
  local title="$4"
  local evidence="$5"
  local next_step="$6"
  local suffix="$7"
  printf '    {"id": "%s", "status": "%s", "phase": "%s", "title": "%s", "evidence": "%s", "nextStep": "%s", "evidenceFields": ["operatorResult", "evidencePathOrLogExcerpt", "timestamp", "redactionNotes"], "redaction": "record redacted ids and statuses only; omit secret values, bearer headers, provider keys, proxy auth values"}%s\n' \
    "$id" "$status" "$phase" "$(json_escape "$title")" "$(json_escape "$evidence")" "$(json_escape "$next_step")" "$suffix"
}

guidance_json_line() {
  local id="$1"
  local status="$2"
  local next_step="$3"
  local suffix="$4"
  printf '    {"id": "%s", "status": "%s", "nextStep": "%s", "evidenceFields": ["operatorResult", "redactedIds", "timestamps", "logExcerptOrReportPath"], "redaction": "store only redacted account/resource ids, status codes, timestamps, and sanitized log excerpts"}%s\n' \
    "$id" "$status" "$(json_escape "$next_step")" "$suffix"
}

release_json_line() {
  local id="$1"
  local status="$2"
  local command="$3"
  local next_step="$4"
  local suffix="$5"
  printf '    {"id": "%s", "status": "%s", "command": "%s", "nextStep": "%s", "evidenceFields": ["exitCode", "outputPath", "startedAt", "finishedAt", "redactionNotes"], "redaction": "attach logs only after removing secret values, bearer headers, provider keys, proxy auth values, and real user home paths"}%s\n' \
    "$id" "$status" "$(json_escape "$command")" "$(json_escape "$next_step")" "$suffix"
}

compute_live_statuses() {
  TELEGRAM_OPT_IN=false
  FEISHU_OPT_IN=false
  CONTROL_UI_PROVIDED=false

  PHASE1_STATUS="skipped"
  PHASE1_REASON="live-opt-in-disabled"
  PHASE2_STATUS="skipped"
  PHASE2_REASON="live-opt-in-disabled"
  PHASE3_STATUS="skipped"
  PHASE3_REASON="live-opt-in-disabled"
  PHASE4_STATUS="skipped"
  PHASE4_REASON="live-opt-in-disabled"
  PHASE5_STATUS="skipped"
  PHASE5_REASON="live-opt-in-disabled"
  PHASE6_STATUS="skipped"
  PHASE6_REASON="live-opt-in-disabled"
  PHASE7_STATUS="operator-record-required"
  PHASE7_REASON="control-ui-product-operator-record-required"
  PHASE8_STATUS="external-resource-required"
  PHASE8_REASON="feishu-platform-boundary-evidence-required"
  PHASE9_STATUS="operator-record-required"
  PHASE9_REASON="release-verification-operator-record-required"
  CONTROL_UI_SMOKE_STATUS="skipped"
  CONTROL_UI_SMOKE_REASON="control-ui-url-not-provided"

  if flag_enabled METIS_AGENTTEAM_LIVE_TELEGRAM; then
    TELEGRAM_OPT_IN=true
    if all_resources_present \
      METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID \
      METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID; then
      PHASE1_STATUS="operator-record-required"
      PHASE1_REASON="manual-live-record-required"
    else
      PHASE1_STATUS="external-resource-required"
      PHASE1_REASON="missing-live-resource"
    fi
  fi

  if flag_enabled METIS_AGENTTEAM_LIVE_FEISHU; then
    FEISHU_OPT_IN=true
    if all_resources_present \
      METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_A \
      METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_B \
      METIS_AGENTTEAM_FEISHU_TEST_GROUP_ID \
      METIS_AGENTTEAM_FEISHU_TEST_THREAD_ID; then
      PHASE2_STATUS="operator-record-required"
      PHASE2_REASON="manual-live-record-required"
      PHASE6_STATUS="operator-record-required"
      PHASE6_REASON="manual-live-record-required"
    else
      PHASE2_STATUS="external-resource-required"
      PHASE2_REASON="missing-live-resource"
      PHASE6_STATUS="external-resource-required"
      PHASE6_REASON="missing-live-resource"
    fi

    if all_resources_present \
      METIS_AGENTTEAM_FEISHU_TEST_APP_ID \
      METIS_AGENTTEAM_FEISHU_TEST_USER_ID \
      METIS_AGENTTEAM_FEISHU_TEST_DOC_ID \
      METIS_AGENTTEAM_FEISHU_TEST_WIKI_ID \
      METIS_AGENTTEAM_FEISHU_TEST_CALENDAR_ID \
      METIS_AGENTTEAM_FEISHU_TEST_TASK_ID \
      METIS_AGENTTEAM_FEISHU_TEST_BITABLE_ID \
      METIS_AGENTTEAM_FEISHU_TEST_SHEET_ID \
      METIS_AGENTTEAM_FEISHU_TEST_MESSAGE_ID; then
      PHASE3_STATUS="operator-record-required"
      PHASE3_REASON="manual-live-record-required"
    else
      PHASE3_STATUS="external-resource-required"
      PHASE3_REASON="missing-live-resource"
    fi

    if resource_present METIS_AGENTTEAM_FEISHU_CARDKIT_CHAT_ID; then
      PHASE4_STATUS="operator-record-required"
      PHASE4_REASON="manual-live-record-required"
    else
      PHASE4_STATUS="external-resource-required"
      PHASE4_REASON="missing-live-resource"
    fi

    if resource_present METIS_AGENTTEAM_FEISHU_RICH_EVENT_CHAT_ID; then
      PHASE5_STATUS="operator-record-required"
      PHASE5_REASON="manual-live-record-required"
    else
      PHASE5_STATUS="external-resource-required"
      PHASE5_REASON="missing-live-resource"
    fi
  fi

  if [[ -n "${METIS_AGENTTEAM_CONTROL_UI_URL:-}" ]]; then
    CONTROL_UI_PROVIDED=true
    CONTROL_UI_SMOKE_STATUS="operator-record-required"
    CONTROL_UI_SMOKE_REASON="control-ui-url-provided-redacted"
  fi
}

write_report_json() {
  local report_json="$1"
  local created_at="$2"
  local head="$3"
  local branch="$4"

  cat >"$report_json" <<JSON
{
  "kind": "metis-agentteam-series23-manual-acceptance-gate-report",
  "series": "23",
  "createdAt": "$created_at",
  "source": {
    "id": "series23",
    "path": "$SERIES23_DOC_REL",
    "available": $SERIES23_SOURCE_AVAILABLE
  },
  "git": {
    "head": "$head",
    "branch": "$(json_escape "$branch")"
  },
  "workspace": {
    "metisHome": "$(json_escape "$METIS_HOME_CANONICAL")",
    "reportDir": "$(json_escape "$REPORT_DIR_CANONICAL")",
    "realHomeBlocked": true
  },
  "statuses": {
    "localPass": "local-pass",
    "skipped": "skipped",
    "externalResourceRequired": "external-resource-required",
    "operatorRecordRequired": "operator-record-required"
  },
  "envOptIn": {
    "telegram": {
      "env": "METIS_AGENTTEAM_LIVE_TELEGRAM",
      "enabled": $TELEGRAM_OPT_IN
    },
    "feishu": {
      "env": "METIS_AGENTTEAM_LIVE_FEISHU",
      "enabled": $FEISHU_OPT_IN
    },
    "controlUi": {
      "env": "METIS_AGENTTEAM_CONTROL_UI_URL",
      "provided": $CONTROL_UI_PROVIDED,
      "status": "$(redacted_status "${METIS_AGENTTEAM_CONTROL_UI_URL:-}")"
    }
  },
  "phaseStatus": [
    {
      "id": "phase0",
      "title": "Freeze source-backed GAP matrix",
      "status": "local-pass",
      "reason": "series23-source-backed-index-present",
      "gaps": ["G01", "G02", "G03", "G04", "G05", "G06", "G07", "G08", "G09", "G10", "G24", "G25"],
      "manualItems": ["M01", "M03", "M04", "M05", "M06", "M07", "M08", "M09", "M10", "M11", "M32"]
    },
    {
      "id": "phase1",
      "title": "Telegram live route and broadcast gate",
      "status": "$PHASE1_STATUS",
      "reason": "$PHASE1_REASON",
      "gaps": ["G11"],
      "manualItems": ["M12", "M13", "M14"]
    },
    {
      "id": "phase2",
      "title": "Feishu multi-account route gate",
      "status": "$PHASE2_STATUS",
      "reason": "$PHASE2_REASON",
      "gaps": ["G12", "G13", "G22"],
      "manualItems": ["M15", "M16", "M17"]
    },
    {
      "id": "phase3",
      "title": "Feishu OAuth and OAPI gate",
      "status": "$PHASE3_STATUS",
      "reason": "$PHASE3_REASON",
      "gaps": ["G14", "G15", "G16", "G17"],
      "manualItems": ["M18", "M19", "M20", "M21"]
    },
    {
      "id": "phase4",
      "title": "Feishu CardKit streaming gate",
      "status": "$PHASE4_STATUS",
      "reason": "$PHASE4_REASON",
      "gaps": ["G18"],
      "manualItems": ["M22"]
    },
    {
      "id": "phase5",
      "title": "Feishu rich event and resource gate",
      "status": "$PHASE5_STATUS",
      "reason": "$PHASE5_REASON",
      "gaps": ["G19"],
      "manualItems": ["M23", "M24"]
    },
    {
      "id": "phase6",
      "title": "Feishu native command live gate",
      "status": "$PHASE6_STATUS",
      "reason": "$PHASE6_REASON",
      "gaps": ["G20"],
      "manualItems": ["M25", "M26", "M27"]
    },
    {
      "id": "phase7",
      "title": "Control UI product acceptance",
      "status": "$PHASE7_STATUS",
      "reason": "$PHASE7_REASON",
      "gaps": ["G23"],
      "manualItems": ["M28", "M29", "M30", "M31"]
    },
    {
      "id": "phase8",
      "title": "Feishu app and bot platform boundary",
      "status": "$PHASE8_STATUS",
      "reason": "$PHASE8_REASON",
      "gaps": ["G21"],
      "manualItems": []
    },
    {
      "id": "phase9",
      "title": "Release verification and evidence pack gate",
      "status": "$PHASE9_STATUS",
      "reason": "$PHASE9_REASON",
      "gaps": ["G24", "G25", "G26"],
      "manualItems": ["M02", "M28", "M29", "M30", "M31", "M32"]
    }
  ],
  "gapStatus": [
    {"id": "G01", "status": "local-pass", "phase": "phase0", "title": "multi-agent config and default agent"},
    {"id": "G02", "status": "local-pass", "phase": "phase0", "title": "per-agent workspace and session isolation"},
    {"id": "G03", "status": "local-pass", "phase": "phase0", "title": "profile files"},
    {"id": "G04", "status": "local-pass", "phase": "phase0", "title": "per-agent model"},
    {"id": "G05", "status": "local-pass", "phase": "phase0", "title": "per-agent credential source"},
    {"id": "G06", "status": "local-pass", "phase": "phase0", "title": "tool and skill filtering"},
    {"id": "G07", "status": "local-pass", "phase": "phase0", "title": "binding match dimensions"},
    {"id": "G08", "status": "local-pass", "phase": "phase0", "title": "CLI UI Gateway management surface"},
    {"id": "G09", "status": "local-pass", "phase": "phase0", "title": "team CRUD and member creation"},
    {"id": "G10", "status": "local-pass", "phase": "phase0", "title": "team broadcast local fan-out plan"},
    {"id": "G11", "status": "$PHASE1_STATUS", "phase": "phase1", "title": "Telegram live route and broadcast"},
    {"id": "G12", "status": "$PHASE2_STATUS", "phase": "phase2", "title": "Feishu multi-account live route"},
    {"id": "G13", "status": "$PHASE2_STATUS", "phase": "phase2", "title": "Feishu group and thread policy live route"},
    {"id": "G14", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Feishu OAuth live grant"},
    {"id": "G15", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Feishu app and tenant credential modes"},
    {"id": "G16", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Feishu OAPI live tool matrix"},
    {"id": "G17", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Feishu scope diagnostic live validation"},
    {"id": "G18", "status": "$PHASE4_STATUS", "phase": "phase4", "title": "Feishu CardKit streaming live validation"},
    {"id": "G19", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu rich event and resource live validation"},
    {"id": "G20", "status": "$PHASE6_STATUS", "phase": "phase6", "title": "Feishu native command parity live smoke"},
    {"id": "G21", "status": "$PHASE8_STATUS", "phase": "phase8", "title": "Feishu app and bot creation platform boundary"},
    {"id": "G22", "status": "$PHASE2_STATUS", "phase": "phase2", "title": "multi-bot mapping to agent or team"},
    {"id": "G23", "status": "$PHASE7_STATUS", "phase": "phase7", "title": "Control UI product acceptance"},
    {"id": "G24", "status": "local-pass", "phase": "phase9", "title": "manual acceptance and evidence pack"},
    {"id": "G25", "status": "local-pass", "phase": "phase9", "title": "redaction discipline"},
    {"id": "G26", "status": "operator-record-required", "phase": "phase9", "title": "one-shot cjpm test stability"}
  ],
  "operatorGuidance": [
$(guidance_json_line telegram-live "$PHASE1_STATUS" "Set METIS_AGENTTEAM_LIVE_TELEGRAM=1 with test bot account, chat, group, and topic ids; then record redacted route and broadcast evidence." ",")
$(guidance_json_line feishu-route "$PHASE2_STATUS" "Set METIS_AGENTTEAM_LIVE_FEISHU=1 with two test Feishu accounts, a test group, and a test thread; then record redacted account and route evidence." ",")
$(guidance_json_line feishu-oauth-oapi "$PHASE3_STATUS" "Provide test OAuth/OAPI resource ids and record auth status plus read/write smoke results without credential values." ",")
$(guidance_json_line feishu-cardkit "$PHASE4_STATUS" "Provide a CardKit-capable test chat and record create, patch, final, settings, abort, and fallback outcomes." ",")
$(guidance_json_line feishu-rich-events "$PHASE5_STATUS" "Provide rich-event test messages and record media/resource/reaction/quote/merge-forward outcomes." ",")
$(guidance_json_line control-ui "$CONTROL_UI_SMOKE_STATUS" "Set METIS_AGENTTEAM_CONTROL_UI_URL for browser smoke, then record visible UI, custom element registration, asset status, and page errors." "")
  ],
  "releaseVerification": [
$(release_json_line cangjie-build-test operator-record-required "source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib:\$DYLD_LIBRARY_PATH && cjpm clean && cjpm build -i && cjpm test" "Run the full Cangjie release check in an isolated METIS_HOME; if default test concurrency flakes, also record cjpm test -j 1 and file G26 follow-up evidence." ",")
$(release_json_line ui-build operator-record-required "npm --prefix ui run build" "Run the UI production build and attach sanitized output." ",")
$(release_json_line ui-browser-smoke "$CONTROL_UI_SMOKE_STATUS" "METIS_AGENTTEAM_CONTROL_UI_URL=http://127.0.0.1:<port>/ scripts/agentteam-manual-acceptance-gate.sh" "Serve built assets or a live Gateway page, then rerun this gate with METIS_AGENTTEAM_CONTROL_UI_URL." ",")
$(release_json_line manual-gate local-pass "scripts/agentteam-manual-acceptance-gate.sh" "Keep report.json and manual-acceptance-template.md as the redacted evidence pack." ",")
$(release_json_line live-gates skipped "METIS_AGENTTEAM_LIVE_TELEGRAM=1 or METIS_AGENTTEAM_LIVE_FEISHU=1 scripts/agentteam-manual-acceptance-gate.sh" "Enable only with test resources; otherwise retain skipped/external-resource-required statuses." "")
  ],
  "manualAcceptance": [
$(manual_json_line M01 local-pass phase0 "temporary environment safety" "isolated METIS_HOME and report directory enforced" "Keep METIS_HOME and METIS_AGENTTEAM_REPORT_DIR under temporary test directories." ",")
$(manual_json_line M02 operator-record-required phase9 "full Cangjie build and tests" "operator records command output" "Run cjpm clean, cjpm build -i, and cjpm test with the Cangjie environment sourced." ",")
$(manual_json_line M03 local-pass phase0 "CLI team create" "source-backed Gateway RPC mapping" "Record CLI JSON output from a temporary METIS_HOME when doing manual release acceptance." ",")
$(manual_json_line M04 local-pass phase0 "CLI team list and get" "source-backed Gateway RPC mapping" "Record team list/get JSON from the temporary test home." ",")
$(manual_json_line M05 local-pass phase0 "CLI team update" "source-backed Gateway RPC mapping" "Record update JSON and any conflict diagnostic from the temporary test home." ",")
$(manual_json_line M06 local-pass phase0 "CLI team delete" "source-backed preserve-member semantics" "Record delete result and member workspace preservation evidence." ",")
$(manual_json_line M07 local-pass phase0 "member agent auto creation" "source-backed member workspace and agentDir creation" "Record created member agent ids and redacted workspace paths." ",")
$(manual_json_line M08 local-pass phase0 "profile file isolation" "local tests and source-backed scoped file IO" "Record per-agent profile read/write evidence from temporary files." ",")
$(manual_json_line M09 local-pass phase0 "model isolation" "local tests and source-backed per-agent model path" "Record per-agent model state summaries without credential values." ",")
$(manual_json_line M10 local-pass phase0 "credential profile isolation" "local tests and source-backed per-agent credential source" "Record redacted credential-source summaries only." ",")
$(manual_json_line M11 local-pass phase0 "binding conflict" "local route conflict tests reject duplicate route writes" "Record conflict response and verify no partial binding write." ",")
$(manual_json_line M12 "$PHASE1_STATUS" phase1 "Telegram private route" "$PHASE1_REASON" "Provide a test Telegram bot account and private chat; record redacted inbound/outbound route evidence." ",")
$(manual_json_line M13 "$PHASE1_STATUS" phase1 "Telegram group and topic route" "$PHASE1_REASON" "Provide test group and topic ids; record session key separation evidence." ",")
$(manual_json_line M14 "$PHASE1_STATUS" phase1 "Telegram team broadcast" "$PHASE1_REASON" "Trigger a test broadcast and record per-member aggregate rows." ",")
$(manual_json_line M15 "$PHASE2_STATUS" phase2 "Feishu account status" "$PHASE2_REASON" "Provide two test Feishu accounts and record redacted configured/enabled/running status." ",")
$(manual_json_line M16 "$PHASE2_STATUS" phase2 "Feishu group policy and mention gate" "$PHASE2_REASON" "Record @ and non-@ behavior plus allowlist result from a test group." ",")
$(manual_json_line M17 "$PHASE2_STATUS" phase2 "Feishu thread session" "$PHASE2_REASON" "Record separate test thread context evidence." ",")
$(manual_json_line M18 "$PHASE3_STATUS" phase3 "Feishu OAuth start status and poll" "$PHASE3_REASON" "Record pending/authorized/scope diagnostic states with safe user-facing auth fields only." ",")
$(manual_json_line M19 "$PHASE3_STATUS" phase3 "Feishu app and token modes" "$PHASE3_REASON" "Record app, tenant, bot, and user credential mode smoke results or exact diagnostics." ",")
$(manual_json_line M20 "$PHASE3_STATUS" phase3 "Feishu OAPI read" "$PHASE3_REASON" "Record one low-risk read result per OAPI family against test resources." ",")
$(manual_json_line M21 "$PHASE3_STATUS" phase3 "Feishu OAPI write" "$PHASE3_REASON" "Record test-only create/update results and cleanup notes." ",")
$(manual_json_line M22 "$PHASE4_STATUS" phase4 "Feishu CardKit streaming" "$PHASE4_REASON" "Record create, patch sequence, final, settings, abort, and fallback outcomes in a test chat." ",")
$(manual_json_line M23 "$PHASE5_STATUS" phase5 "Feishu resource read" "$PHASE5_REASON" "Record current-turn resource context and fetch diagnostics for test media/files." ",")
$(manual_json_line M24 "$PHASE5_STATUS" phase5 "Feishu rich event" "$PHASE5_REASON" "Record reaction, quote, and merged-forward behavior from test messages." ",")
$(manual_json_line M25 "$PHASE6_STATUS" phase6 "Feishu start command" "$PHASE6_REASON" "Record redacted /feishu start response from a test conversation." ",")
$(manual_json_line M26 "$PHASE6_STATUS" phase6 "Feishu doctor command" "$PHASE6_REASON" "Record redacted /feishu doctor diagnostics from a test conversation." ",")
$(manual_json_line M27 "$PHASE6_STATUS" phase6 "Feishu auth command" "$PHASE6_REASON" "Record only safe auth URL/code summary fields and status transitions." ",")
$(manual_json_line M28 "$CONTROL_UI_SMOKE_STATUS" phase9 "Control UI browser smoke" "$CONTROL_UI_SMOKE_REASON" "Set METIS_AGENTTEAM_CONTROL_UI_URL and rerun the gate against built assets or a live Gateway page." ",")
$(manual_json_line M29 operator-record-required phase9 "Control UI team CRUD" "$PHASE9_REASON" "Record create/edit/delete persistence evidence after browser smoke is available." ",")
$(manual_json_line M30 operator-record-required phase9 "Control UI profile model and binding" "$PHASE9_REASON" "Record Gateway RPC success or clear redacted error for profile/model/binding edits." ",")
$(manual_json_line M31 operator-record-required phase9 "Control UI Feishu wizard" "$PHASE9_REASON" "Record setup/repair wizard states and next-step text without credential values." ",")
$(manual_json_line M32 local-pass phase9 "evidence pack" "report and template generated with redaction scan" "review report.json and complete manual-acceptance-template.md with redacted operator evidence" "")
  ],
  "externalResources": [
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID "Telegram account id" phase1 ",")
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID "Telegram private chat or topic id" phase1 ",")
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_TEST_GROUP_ID "Telegram test group id" phase1 ",")
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_TEST_TOPIC_ID "Telegram test topic id" phase1 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_A "Feishu account A id" phase2 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_B "Feishu account B id" phase2 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_GROUP_ID "Feishu test group id" phase2 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_THREAD_ID "Feishu test thread id" phase2 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_APP_ID "Feishu test app id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_USER_ID "Feishu test user id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_DOC_ID "Feishu test doc id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_WIKI_ID "Feishu test wiki id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_CALENDAR_ID "Feishu test calendar id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_TASK_ID "Feishu test task id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_BITABLE_ID "Feishu test bitable id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_SHEET_ID "Feishu test sheet id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_MESSAGE_ID "Feishu test message id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_CARDKIT_CHAT_ID "Feishu CardKit test chat id" phase4 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_RICH_EVENT_CHAT_ID "Feishu rich-event test chat id" phase5 ",")
$(resource_json_line control-ui METIS_AGENTTEAM_CONTROL_UI_URL "Control UI smoke URL" phase9 "")
  ],
  "redactionScan": {
    "status": "local-pass",
    "rawSensitiveValuesRecorded": false,
    "resourceValuesRecorded": false,
    "forbiddenIdentifiersAbsent": true
  }
}
JSON
}

write_manual_template() {
  local template_md="$1"
  local created_at="$2"
  local head="$3"

  cat >"$template_md" <<MD
# Metis AgentTeam Series23 Manual Acceptance Evidence

- Date: $created_at
- Git head: $head
- Series source: $SERIES23_DOC_REL
- METIS_HOME: $METIS_HOME_CANONICAL
- Report dir: $REPORT_DIR_CANONICAL
- Operator: TODO
- Gateway URL: TODO local-only or redacted
- Control UI URL state: $(redacted_status "${METIS_AGENTTEAM_CONTROL_UI_URL:-}")

## Evidence fields

For each manual item, record operator result, timestamp, redacted resource ids, sanitized log excerpt or report path, and redaction notes.

## Redaction

Do not record secret values, bearer headers, provider keys, proxy auth values, credential file contents, or real user home paths.

## Phase 0 Source Matrix

| Check | Result | Evidence |
| --- | --- | --- |
| Series23 source-backed matrix exists | local-pass | $SERIES23_DOC_REL |
| G01-G26 are represented in report.json | local-pass | report.json gapStatus |
| M01-M32 are represented in report.json | local-pass | report.json manualAcceptance |
| Real network gates are opt-in | local-pass | METIS_AGENTTEAM_LIVE_TELEGRAM / METIS_AGENTTEAM_LIVE_FEISHU |

## Phase 1 Telegram Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M12 Telegram private route | $PHASE1_STATUS | TODO | redacted account and chat ids only |
| M13 Telegram group/topic route | $PHASE1_STATUS | TODO | redacted group/topic ids only |
| M14 Telegram team broadcast | $PHASE1_STATUS | TODO | aggregate rows with agentId/status/sessionKey |

Required env state is in report.json externalResources. The gate does not call Telegram by default.

## Phase 2 Feishu Route Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M15 Feishu account status | $PHASE2_STATUS | TODO | two account ids, redacted |
| M16 Feishu group policy and mention gate | $PHASE2_STATUS | TODO | @ and non-@ behavior |
| M17 Feishu thread session | $PHASE2_STATUS | TODO | separate thread context evidence |

Required env state is in report.json externalResources. The gate does not call Feishu by default.

## Phase 3 Feishu OAuth And OAPI Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M18 OAuth start/status/poll | $PHASE3_STATUS | TODO | safe auth URL/code summary only |
| M19 Feishu app and token modes | $PHASE3_STATUS | TODO | app/tenant/bot/user credential-mode status or diagnostic |
| M20 OAPI read | $PHASE3_STATUS | TODO | low-risk test resources only |
| M21 OAPI write | $PHASE3_STATUS | TODO | test-only resources only |

## Phase 4 CardKit Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M22 CardKit streaming | $PHASE4_STATUS | TODO | create, stream patch, final update, settings, abort, fallback |

## Phase 5 Rich Event Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M23 Resource read | $PHASE5_STATUS | TODO | image/file/audio/video test resources |
| M24 Rich event | $PHASE5_STATUS | TODO | reaction, quote, merged-forward event evidence |

## Phase 6 Feishu Native Command Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M25 Feishu start command | $PHASE6_STATUS | TODO | account/version/status output |
| M26 Feishu doctor command | $PHASE6_STATUS | TODO | config/event/scope/OAuth/OAPI/CardKit diagnostics |
| M27 Feishu auth command | $PHASE6_STATUS | TODO | safe auth fields and state transitions |

## Phase 9 Release Evidence Pack

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M02 Full Cangjie build and tests | operator-record-required | TODO | cjpm clean/build/test output |
| M28 Control UI browser smoke | $CONTROL_UI_SMOKE_STATUS | TODO | no blank page, JS error, asset 404; metis-app registered |
| M29 Control UI team CRUD | operator-record-required | TODO | create/edit/delete persists after refresh |
| M30 Control UI profile/model/binding | operator-record-required | TODO | Gateway RPC success or clear error |
| M31 Control UI Feishu wizard | operator-record-required | TODO | setup/repair wizard states |
| M32 Evidence pack | local-pass | generated | report.json and this template |

## GAP Status Index

| GAP | Gate status | Evidence |
| --- | --- | --- |
| G01 | local-pass | source-backed matrix |
| G02 | local-pass | workspace and session isolation |
| G03 | local-pass | profile files |
| G04 | local-pass | per-agent model |
| G05 | local-pass | per-agent credential source |
| G06 | local-pass | tool and skill filtering |
| G07 | local-pass | binding match dimensions |
| G08 | local-pass | CLI/UI/Gateway management boundary |
| G09 | local-pass | team CRUD and member creation |
| G10 | local-pass | local broadcast fan-out plan |
| G11 | $PHASE1_STATUS | Telegram live route/broadcast gate |
| G12 | $PHASE2_STATUS | Feishu multi-account route gate |
| G13 | $PHASE2_STATUS | Feishu group/thread policy gate |
| G14 | $PHASE3_STATUS | Feishu OAuth live grant |
| G15 | $PHASE3_STATUS | Feishu app and tenant credential modes |
| G16 | $PHASE3_STATUS | Feishu OAPI live tool matrix |
| G17 | $PHASE3_STATUS | Feishu scope diagnostic live validation |
| G18 | $PHASE4_STATUS | Feishu CardKit streaming live validation |
| G19 | $PHASE5_STATUS | Feishu rich event and resource live validation |
| G20 | $PHASE6_STATUS | Feishu native command parity live smoke |
| G21 | $PHASE8_STATUS | Feishu app and bot creation platform boundary |
| G22 | $PHASE2_STATUS | multi-bot mapping to agent or team |
| G23 | $PHASE7_STATUS | Control UI product acceptance |
| G24 | local-pass | manual acceptance and evidence pack |
| G25 | local-pass | redaction discipline |
| G26 | operator-record-required | one-shot cjpm test stability |

## M01-M32 Operator Checklist

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M01 | local-pass | generated | temporary environment safety |
| M02 | operator-record-required | TODO | full Cangjie build and tests |
| M03 | local-pass | TODO | CLI team create |
| M04 | local-pass | TODO | CLI team list/get |
| M05 | local-pass | TODO | CLI team update |
| M06 | local-pass | TODO | CLI team delete |
| M07 | local-pass | TODO | member agent auto creation |
| M08 | local-pass | TODO | profile file isolation |
| M09 | local-pass | TODO | model isolation |
| M10 | local-pass | TODO | credential profile isolation |
| M11 | local-pass | TODO | binding conflict |
| M12 | $PHASE1_STATUS | TODO | Telegram private route |
| M13 | $PHASE1_STATUS | TODO | Telegram group/topic route |
| M14 | $PHASE1_STATUS | TODO | Telegram team broadcast |
| M15 | $PHASE2_STATUS | TODO | Feishu account status |
| M16 | $PHASE2_STATUS | TODO | Feishu group policy and mention gate |
| M17 | $PHASE2_STATUS | TODO | Feishu thread session |
| M18 | $PHASE3_STATUS | TODO | OAuth start/status/poll |
| M19 | $PHASE3_STATUS | TODO | Feishu app and token modes |
| M20 | $PHASE3_STATUS | TODO | OAPI read |
| M21 | $PHASE3_STATUS | TODO | OAPI write |
| M22 | $PHASE4_STATUS | TODO | CardKit streaming |
| M23 | $PHASE5_STATUS | TODO | resource read |
| M24 | $PHASE5_STATUS | TODO | rich event |
| M25 | $PHASE6_STATUS | TODO | Feishu start command |
| M26 | $PHASE6_STATUS | TODO | Feishu doctor command |
| M27 | $PHASE6_STATUS | TODO | Feishu auth command |
| M28 | $CONTROL_UI_SMOKE_STATUS | TODO | Control UI browser smoke |
| M29 | operator-record-required | TODO | Control UI team CRUD |
| M30 | operator-record-required | TODO | Control UI profile/model/binding |
| M31 | operator-record-required | TODO | Control UI Feishu wizard |
| M32 | local-pass | generated | evidence pack |

## Redaction Checklist

- Real operator home was not used for METIS_HOME.
- Bot credential values were not recorded.
- Feishu credential values were not recorded.
- OAuth credential values were not recorded.
- Request credential headers were not recorded.
- Proxy credential and provider key values were not recorded.
MD
}

scan_evidence_pack() {
  local report_dir="$1"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/metis-agentteam-gate-redaction.XXXXXX")"
  if rg -n -i 'appSecret|accessToken|refreshToken|Authorization|bot[ _-]?token' "$report_dir" >"$tmp"; then
    cat "$tmp" >&2
    rm -f "$tmp"
    fail "redaction scan found forbidden identifier in $report_dir"
  fi
  if rg -n -i 'xox[baprs]-|sk-[A-Za-z0-9_-]{16,}|[0-9]{5,}:[A-Za-z0-9_-]{20,}|bearer[[:space:]]+[A-Za-z0-9._-]{8,}' "$report_dir" >"$tmp"; then
    cat "$tmp" >&2
    rm -f "$tmp"
    fail "redaction scan found secret-like value in $report_dir"
  fi
  rm -f "$tmp"
}

write_evidence_pack() {
  local report_dir="$1"
  local report_json="$report_dir/report.json"
  local template_md="$report_dir/manual-acceptance-template.md"
  local created_at
  local head
  local branch

  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  head="$(git rev-parse HEAD)"
  branch="$(git rev-parse --abbrev-ref HEAD)"

  compute_live_statuses
  write_report_json "$report_json" "$created_at" "$head" "$branch"
  write_manual_template "$template_md" "$created_at" "$head"
  scan_evidence_pack "$report_dir"
}

require_command git
require_command rg

SERIES23_DOC_REL="develop_steps/metis-agent-team-series-23-source-backed-gap-quantification-manual-acceptance-2026-05-16.md"
SERIES23_DOC_MAIN="/Users/l3gi0n/work/workspace_cangjie/Metis/$SERIES23_DOC_REL"
PARITY_REPORT="develop_steps/metis-agent-team-series-14-oapi-action-parity-report-2026-05-15.md"
SERIES14_DOC="develop_steps/metis-agent-team-series-14-current-source-recheck-gap-quantification-manual-acceptance-2026-05-15.md"

if [[ -f "$SERIES23_DOC_REL" || -f "$SERIES23_DOC_MAIN" ]]; then
  SERIES23_SOURCE_AVAILABLE=true
else
  fail "missing series23 source-backed matrix: $SERIES23_DOC_REL or $SERIES23_DOC_MAIN"
fi

METIS_HOME_VALUE="${METIS_HOME:-}"
[[ -n "$METIS_HOME_VALUE" ]] || fail "set METIS_HOME to an isolated test directory, for example /tmp/metis-agentteam-manual-acceptance"

REAL_HOME="$(cd "$HOME" && pwd -P)/.metis"
METIS_HOME_CANONICAL="$(mkdir -p "$METIS_HOME_VALUE" && cd "$METIS_HOME_VALUE" && pwd -P)"
if [[ "$METIS_HOME_CANONICAL" == "$REAL_HOME" ]]; then
  fail "METIS_HOME points at the real home ($REAL_HOME). Use an isolated test home."
fi
info "METIS_HOME=$METIS_HOME_CANONICAL"

REPORT_DIR_VALUE="${METIS_AGENTTEAM_REPORT_DIR:-$METIS_HOME_CANONICAL/agentteam-manual-acceptance-report}"
mkdir -p "$REPORT_DIR_VALUE"
REPORT_DIR_CANONICAL="$(cd "$REPORT_DIR_VALUE" && pwd -P)"
if [[ "$REPORT_DIR_CANONICAL" == "$REAL_HOME"* ]]; then
  fail "report dir points inside the real home ($REAL_HOME). Use METIS_AGENTTEAM_REPORT_DIR outside the real home."
fi
write_evidence_pack "$REPORT_DIR_CANONICAL"
info "redacted evidence pack written to $REPORT_DIR_CANONICAL"

stale_patterns=(
  "Auth status RPC missing"
  "只 start"
  "4 个文件"
  "自动创建 Feishu"
  "TAT/app-token provider parity"
  "series13 is the current source-recheck"
)
for pattern in "${stale_patterns[@]}"; do
  if rg -n "$pattern" docs/user/agent-team.md >/tmp/metis-agentteam-gate-rg.txt; then
    cat /tmp/metis-agentteam-gate-rg.txt >&2
    fail "stale AgentTeam/Feishu wording found in docs/user/agent-team.md: $pattern"
  fi
done
rm -f /tmp/metis-agentteam-gate-rg.txt
info "docs stale-wording check passed"

[[ -f "$SERIES14_DOC" ]] || fail "missing series14 evidence document: $SERIES14_DOC"
rg -n "tenant_access_token.*bot_access_token.*app_access_token|user/TAT/bot/app token provider" "$SERIES14_DOC" >/dev/null \
  || fail "series14 evidence document must record current Feishu token provider support"
info "series14 evidence document check passed"

[[ -f "$PARITY_REPORT" ]] || fail "missing OAPI parity report: $PARITY_REPORT"
rg -n "OpenClaw-Lark source currently enumerates 108" "$PARITY_REPORT" >/dev/null \
  || fail "OAPI parity report must identify the 108 action source baseline"
rg -n "^-? ?aligned: 108$" "$PARITY_REPORT" >/dev/null \
  || fail "OAPI parity report aligned count changed; regenerate and review the report"
rg -n "^-? ?partial: 0$" "$PARITY_REPORT" >/dev/null \
  || fail "OAPI parity report partial count changed; regenerate and review the report"
rg -n "^-? ?missing: 0$" "$PARITY_REPORT" >/dev/null \
  || fail "OAPI parity report missing count is not the reviewed baseline"
rg -n "^-? ?not-applicable: 0$" "$PARITY_REPORT" >/dev/null \
  || fail "OAPI parity report not-applicable count changed; regenerate and review the report"
INVALID_STATUS="$(awk -F'|' '/^\| feishu_/ { gsub(/^[ \t]+|[ \t]+$/, "", $3); if ($3 != "aligned" && $3 != "partial" && $3 != "missing" && $3 != "not-applicable") print $0 }' "$PARITY_REPORT")"
[[ -z "$INVALID_STATUS" ]] || fail "OAPI parity report contains an invalid status: $INVALID_STATUS"
ACTION_ROWS="$(awk '/^\| feishu_/ { count += 1 } END { print count + 0 }' "$PARITY_REPORT")"
[[ "$ACTION_ROWS" == "108" ]] || fail "OAPI parity report must contain 108 action rows, found $ACTION_ROWS"
info "OAPI parity report check passed"

git diff --check
info "git diff --check passed"

if [[ -z "${METIS_AGENTTEAM_CONTROL_UI_URL:-}" ]]; then
  info "browser smoke skipped; set METIS_AGENTTEAM_CONTROL_UI_URL to a built Control UI or live Gateway URL to enable it"
else
  require_command node
  [[ -d "$ROOT/ui/node_modules" ]] || fail "ui/node_modules is missing; run npm --prefix ui install before browser smoke"
  SMOKE_BASE="$(mktemp "$ROOT/ui/.agentteam-browser-smoke.XXXXXX")"
  SMOKE_SCRIPT="${SMOKE_BASE}.mjs"
  mv "$SMOKE_BASE" "$SMOKE_SCRIPT"
  cleanup_smoke() {
    rm -f "$SMOKE_SCRIPT"
  }
  trap cleanup_smoke EXIT
  cat >"$SMOKE_SCRIPT" <<'NODE'
import fs from "node:fs";
import { chromium } from "playwright";

const url = process.argv[2];
if (!url) {
  throw new Error("missing Control UI URL");
}

const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const launchOptions = fs.existsSync(chromePath)
  ? { headless: true, executablePath: chromePath }
  : { headless: true };

const browser = await chromium.launch(launchOptions);
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
const errors = [];
page.on("pageerror", (err) => errors.push(`pageerror: ${err.message}`));
page.on("requestfailed", (req) => {
  const type = req.resourceType();
  if (type === "document" || type === "script" || type === "stylesheet") {
    errors.push(`requestfailed: ${type} ${req.url()} ${req.failure()?.errorText ?? ""}`);
  }
});

try {
  await page.goto(url, { waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => Boolean(customElements.get("metis-app")), null, { timeout: 15000 });
  await page.waitForTimeout(500);
  const initial = await page.evaluate(() => ({
    defined: Boolean(customElements.get("metis-app")),
    visibleText: document.body.innerText,
  }));
  if (!initial.defined) {
    throw new Error("customElements.get(\"metis-app\") is not registered");
  }
  if (!initial.visibleText.includes("Metis")) {
    throw new Error("visible Metis UI content was not rendered");
  }

  const agentsLink = page.locator('a[href="/agents"]').first();
  const hasAgentsLink = await agentsLink.count();
  if (hasAgentsLink > 0) {
    await agentsLink.click();
    await page.waitForURL(/\/agents(?:$|[?#])/, { timeout: 10000 });
    await page.waitForFunction(
      () => document.body.innerText.includes("Teams") || document.body.innerText.includes("Agent Teams"),
      null,
      { timeout: 10000 },
    );
  }
  const finalText = await page.evaluate(() => document.body.innerText);
  if (!finalText.includes("Teams") && !finalText.includes("Agent Teams")) {
    throw new Error("Agents -> Teams content is not visible after navigation");
  }
  if (errors.length > 0) {
    throw new Error(errors.join("\n"));
  }
} finally {
  await browser.close();
}
NODE
  (cd "$ROOT/ui" && node "$SMOKE_SCRIPT" "$METIS_AGENTTEAM_CONTROL_UI_URL")
  info "browser smoke passed"
fi

if [[ "$TELEGRAM_OPT_IN" == true ]]; then
  if [[ "$PHASE1_STATUS" == "operator-record-required" ]]; then
    info "live Telegram gate opted in; operator must record private route, group/topic route, alias route, and broadcast evidence"
  else
    info "live Telegram gate opted in but external resources are missing"
  fi
else
  info "live Telegram gate skipped; set METIS_AGENTTEAM_LIVE_TELEGRAM=1 with redacted test resource ids to enable manual smoke"
fi

if [[ "$FEISHU_OPT_IN" == true ]]; then
  if [[ "$PHASE2_STATUS" == "operator-record-required" || "$PHASE3_STATUS" == "operator-record-required" || "$PHASE4_STATUS" == "operator-record-required" || "$PHASE5_STATUS" == "operator-record-required" || "$PHASE6_STATUS" == "operator-record-required" ]]; then
    info "live Feishu gate opted in; operator must record account route, OAuth, OAPI, CardKit, rich event, and redaction evidence"
  else
    info "live Feishu gate opted in but external resources are missing"
  fi
else
  info "live Feishu gate skipped"
fi

info "manual acceptance preflight passed"
