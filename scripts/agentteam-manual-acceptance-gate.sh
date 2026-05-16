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

compute_live_statuses() {
  TELEGRAM_OPT_IN=false
  FEISHU_OPT_IN=false
  CONTROL_UI_PROVIDED=false

  PHASE3_STATUS="external-resource-required"
  PHASE3_REASON="live-opt-in-disabled"
  PHASE4_STATUS="external-resource-required"
  PHASE4_REASON="live-opt-in-disabled"
  PHASE5_STATUS="external-resource-required"
  PHASE5_REASON="live-opt-in-disabled"
  PHASE9_STATUS="operator-record-required"
  PHASE9_REASON="control-ui-operator-record-required"

  if flag_enabled METIS_AGENTTEAM_LIVE_TELEGRAM; then
    TELEGRAM_OPT_IN=true
    if all_resources_present \
      METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID \
      METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID; then
      PHASE3_STATUS="operator-record-required"
      PHASE3_REASON="manual-live-record-required"
    else
      PHASE3_REASON="missing-live-resource"
    fi
  fi

  if flag_enabled METIS_AGENTTEAM_LIVE_FEISHU; then
    FEISHU_OPT_IN=true
    if all_resources_present \
      METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_A \
      METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_B \
      METIS_AGENTTEAM_FEISHU_TEST_GROUP_ID \
      METIS_AGENTTEAM_FEISHU_TEST_THREAD_ID; then
      PHASE4_STATUS="operator-record-required"
      PHASE4_REASON="manual-live-record-required"
    else
      PHASE4_REASON="missing-live-resource"
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
      PHASE5_STATUS="operator-record-required"
      PHASE5_REASON="manual-live-record-required"
    else
      PHASE5_REASON="missing-live-resource"
    fi
  fi

  if [[ -n "${METIS_AGENTTEAM_CONTROL_UI_URL:-}" ]]; then
    CONTROL_UI_PROVIDED=true
    PHASE9_REASON="control-ui-url-provided-redacted"
  fi
}

write_report_json() {
  local report_json="$1"
  local created_at="$2"
  local head="$3"
  local branch="$4"

  cat >"$report_json" <<JSON
{
  "kind": "metis-agentteam-series21-manual-live-gate-report",
  "series": "21",
  "createdAt": "$created_at",
  "source": {
    "id": "series21",
    "path": "$SERIES21_DOC_REL",
    "available": $SERIES21_SOURCE_AVAILABLE
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
      "reason": "series21-source-backed-index-present",
      "gaps": ["G01", "G02", "G03", "G04", "G05", "G06", "G07", "G08", "G09", "G10", "G24", "G25"],
      "manualItems": ["M01", "M02", "M31", "M32"]
    },
    {
      "id": "phase3",
      "title": "Telegram live route and broadcast gate",
      "status": "$PHASE3_STATUS",
      "reason": "$PHASE3_REASON",
      "gaps": ["G11"],
      "manualItems": ["M12", "M13", "M14"]
    },
    {
      "id": "phase4",
      "title": "Feishu multi-account route gate",
      "status": "$PHASE4_STATUS",
      "reason": "$PHASE4_REASON",
      "gaps": ["G12", "G13", "G22"],
      "manualItems": ["M15", "M16", "M17"]
    },
    {
      "id": "phase5",
      "title": "Feishu OAuth and OAPI gate",
      "status": "$PHASE5_STATUS",
      "reason": "$PHASE5_REASON",
      "gaps": ["G14", "G15", "G16", "G17", "G20"],
      "manualItems": ["M18", "M19", "M20", "M21", "M25", "M26"]
    },
    {
      "id": "phase9",
      "title": "Regression and evidence pack gate",
      "status": "$PHASE9_STATUS",
      "reason": "$PHASE9_REASON",
      "gaps": ["G23", "G24", "G25"],
      "manualItems": ["M27", "M28", "M29", "M30", "M31", "M32"]
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
    {"id": "G11", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Telegram live route and broadcast"},
    {"id": "G12", "status": "$PHASE4_STATUS", "phase": "phase4", "title": "Feishu multi-account live route"},
    {"id": "G13", "status": "$PHASE4_STATUS", "phase": "phase4", "title": "Feishu group and thread policy live route"},
    {"id": "G14", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu OAuth live grant"},
    {"id": "G15", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu app and tenant credential modes"},
    {"id": "G16", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu OAPI live tool matrix"},
    {"id": "G17", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu scope diagnostic live validation"},
    {"id": "G18", "status": "external-resource-required", "phase": "phase5", "title": "Feishu CardKit streaming live validation"},
    {"id": "G19", "status": "external-resource-required", "phase": "phase5", "title": "Feishu rich event and resource live validation"},
    {"id": "G20", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu native command parity live smoke"},
    {"id": "G21", "status": "external-resource-required", "phase": "phase5", "title": "Feishu app and bot creation platform boundary"},
    {"id": "G22", "status": "$PHASE4_STATUS", "phase": "phase4", "title": "multi-bot mapping to agent or team"},
    {"id": "G23", "status": "operator-record-required", "phase": "phase9", "title": "Control UI product acceptance"},
    {"id": "G24", "status": "local-pass", "phase": "phase9", "title": "manual acceptance and evidence pack"},
    {"id": "G25", "status": "local-pass", "phase": "phase9", "title": "redaction discipline"}
  ],
  "manualAcceptance": [
    {"id": "M01", "status": "local-pass", "phase": "phase0", "title": "temporary environment safety", "evidence": "isolated METIS_HOME and report directory enforced"},
    {"id": "M02", "status": "operator-record-required", "phase": "phase0", "title": "full Cangjie build and tests", "evidence": "operator records command output"},
    {"id": "M03", "status": "local-pass", "phase": "phase0", "title": "CLI team create", "evidence": "source-backed Gateway RPC mapping"},
    {"id": "M04", "status": "local-pass", "phase": "phase0", "title": "CLI team list and get", "evidence": "source-backed Gateway RPC mapping"},
    {"id": "M05", "status": "local-pass", "phase": "phase0", "title": "CLI team update", "evidence": "source-backed Gateway RPC mapping"},
    {"id": "M06", "status": "local-pass", "phase": "phase0", "title": "CLI team delete", "evidence": "source-backed preserve-member semantics"},
    {"id": "M07", "status": "local-pass", "phase": "phase0", "title": "member agent auto creation", "evidence": "source-backed member workspace and agentDir creation"},
    {"id": "M08", "status": "local-pass", "phase": "phase0", "title": "profile file isolation", "evidence": "local tests and source-backed scoped file IO"},
    {"id": "M09", "status": "local-pass", "phase": "phase0", "title": "model isolation", "evidence": "local tests and source-backed per-agent model path"},
    {"id": "M10", "status": "local-pass", "phase": "phase0", "title": "credential profile isolation", "evidence": "local tests and source-backed per-agent credential source"},
    {"id": "M11", "status": "local-pass", "phase": "phase0", "title": "binding conflict", "evidence": "local route conflict tests reject duplicate route writes"},
    {"id": "M12", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Telegram private route", "evidence": "$PHASE3_REASON"},
    {"id": "M13", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Telegram group and topic route", "evidence": "$PHASE3_REASON"},
    {"id": "M14", "status": "$PHASE3_STATUS", "phase": "phase3", "title": "Telegram team broadcast", "evidence": "$PHASE3_REASON"},
    {"id": "M15", "status": "$PHASE4_STATUS", "phase": "phase4", "title": "Feishu account status", "evidence": "$PHASE4_REASON"},
    {"id": "M16", "status": "$PHASE4_STATUS", "phase": "phase4", "title": "Feishu group policy and mention gate", "evidence": "$PHASE4_REASON"},
    {"id": "M17", "status": "$PHASE4_STATUS", "phase": "phase4", "title": "Feishu thread session", "evidence": "$PHASE4_REASON"},
    {"id": "M18", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu OAuth start status and poll", "evidence": "$PHASE5_REASON"},
    {"id": "M19", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu OAuth revoke", "evidence": "$PHASE5_REASON"},
    {"id": "M20", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu OAPI read", "evidence": "$PHASE5_REASON"},
    {"id": "M21", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu OAPI write", "evidence": "$PHASE5_REASON"},
    {"id": "M22", "status": "external-resource-required", "phase": "phase5", "title": "Feishu CardKit streaming", "evidence": "real CardKit-capable test chat required"},
    {"id": "M23", "status": "external-resource-required", "phase": "phase5", "title": "Feishu resource read", "evidence": "real media and file test resources required"},
    {"id": "M24", "status": "external-resource-required", "phase": "phase5", "title": "Feishu rich event", "evidence": "real reaction quote and merged-forward events required"},
    {"id": "M25", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu start command", "evidence": "$PHASE5_REASON"},
    {"id": "M26", "status": "$PHASE5_STATUS", "phase": "phase5", "title": "Feishu doctor command", "evidence": "$PHASE5_REASON"},
    {"id": "M27", "status": "operator-record-required", "phase": "phase9", "title": "Control UI browser smoke", "evidence": "$PHASE9_REASON"},
    {"id": "M28", "status": "operator-record-required", "phase": "phase9", "title": "Control UI team CRUD", "evidence": "$PHASE9_REASON"},
    {"id": "M29", "status": "operator-record-required", "phase": "phase9", "title": "Control UI profile model and binding", "evidence": "$PHASE9_REASON"},
    {"id": "M30", "status": "operator-record-required", "phase": "phase9", "title": "Control UI Feishu wizard", "evidence": "$PHASE9_REASON"},
    {"id": "M31", "status": "operator-record-required", "phase": "phase9", "title": "runtime log redaction", "evidence": "operator records Gateway and channel logs from test resources"},
    {"id": "M32", "status": "local-pass", "phase": "phase9", "title": "evidence pack", "evidence": "report and template generated with redaction scan"}
  ],
  "telegramLiveReadiness": {
    "phase": "phase1",
    "gap": "G11",
    "manualItems": ["M12", "M13", "M14"],
    "status": "$PHASE3_STATUS",
    "reason": "$PHASE3_REASON",
    "redacted": true,
    "routePreflight": {
      "requiredPeerKinds": ["private", "group", "topic"],
      "evidenceFields": ["privateBindingCount", "groupBindingCount", "topicBindingCount", "missingRequirements"],
      "operatorRecordRequired": true
    },
    "broadcastEvidenceFields": [
      "teamId",
      "selectedAgentIds",
      "agents[].agentId",
      "agents[].sessionKey",
      "agents[].deliveryStatus",
      "agents[].deliveryMessageId",
      "answer"
    ],
    "logEvidence": {
      "requiredMarkers": ["Gateway.inbound: channel=telegram", "outbound success"],
      "forbiddenMarkerRefs": ["auth-header", "bearer-secret", "proxy-credential", "telegram-credential"],
      "operatorRecordRequired": true
    }
  },
  "externalResources": [
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID "Telegram account id" phase3 ",")
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID "Telegram private chat or topic id" phase3 ",")
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_TEST_GROUP_ID "Telegram test group id" phase3 ",")
$(resource_json_line telegram METIS_AGENTTEAM_TELEGRAM_TEST_TOPIC_ID "Telegram test topic id" phase3 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_A "Feishu account A id" phase4 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_B "Feishu account B id" phase4 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_GROUP_ID "Feishu test group id" phase4 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_THREAD_ID "Feishu test thread id" phase4 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_APP_ID "Feishu test app id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_USER_ID "Feishu test user id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_DOC_ID "Feishu test doc id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_WIKI_ID "Feishu test wiki id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_CALENDAR_ID "Feishu test calendar id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_TASK_ID "Feishu test task id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_BITABLE_ID "Feishu test bitable id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_SHEET_ID "Feishu test sheet id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_TEST_MESSAGE_ID "Feishu test message id" phase5 ",")
$(resource_json_line feishu METIS_AGENTTEAM_FEISHU_CARDKIT_CHAT_ID "Feishu CardKit test chat id" phase5 ",")
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
# Metis AgentTeam Series21 Manual Acceptance Evidence

- Date: $created_at
- Git head: $head
- Series source: $SERIES21_DOC_REL
- METIS_HOME: $METIS_HOME_CANONICAL
- Report dir: $REPORT_DIR_CANONICAL
- Operator: TODO
- Gateway URL: TODO local-only or redacted
- Control UI URL state: $(redacted_status "${METIS_AGENTTEAM_CONTROL_UI_URL:-}")

## Phase 0 Source Matrix

| Check | Result | Evidence |
| --- | --- | --- |
| Series21 source-backed matrix exists | local-pass | $SERIES21_DOC_REL |
| G01-G25 are represented in report.json | local-pass | report.json gapStatus |
| M01-M32 are represented in report.json | local-pass | report.json manualAcceptance |
| Real network gates are opt-in | local-pass | METIS_AGENTTEAM_LIVE_TELEGRAM / METIS_AGENTTEAM_LIVE_FEISHU |

## Phase 3 Telegram Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M12 Telegram private route | $PHASE3_STATUS | TODO | redacted account and chat ids only |
| M13 Telegram group/topic route | $PHASE3_STATUS | TODO | redacted group/topic ids only |
| M14 Telegram team broadcast | $PHASE3_STATUS | TODO | aggregate rows with agentId/status/sessionKey |
| Route preflight | $PHASE3_STATUS | TODO | privateBindingCount, groupBindingCount, topicBindingCount, missingRequirements |
| Broadcast selected members | $PHASE3_STATUS | TODO | teamId, selectedAgentIds, agents[].agentId, agents[].sessionKey, agents[].deliveryStatus, agents[].deliveryMessageId |
| Log redaction scan | operator-record-required | TODO | required marker Gateway.inbound: channel=telegram; forbidden refs auth-header, bearer-secret, proxy-credential, telegram-credential |

Required env state is in report.json externalResources. The gate does not call Telegram by default.

## Phase 4 Feishu Route Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M15 Feishu account status | $PHASE4_STATUS | TODO | two account ids, redacted |
| M16 Feishu group policy and mention gate | $PHASE4_STATUS | TODO | @ and non-@ behavior |
| M17 Feishu thread session | $PHASE4_STATUS | TODO | separate thread context evidence |

Required env state is in report.json externalResources. The gate does not call Feishu by default.

## Phase 5 Feishu OAuth And OAPI Live Gate

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M18 OAuth start/status/poll | $PHASE5_STATUS | TODO | verification URL and user code only |
| M19 OAuth revoke | $PHASE5_STATUS | TODO | revoked or missing status |
| M20 OAPI read | $PHASE5_STATUS | TODO | low-risk test resources only |
| M21 OAPI write | $PHASE5_STATUS | TODO | test-only resources only |
| M22 CardKit streaming | external-resource-required | TODO | create, stream patch, final update, close/fallback |
| M23 Resource read | external-resource-required | TODO | image/file/audio/video test resources |
| M24 Rich event | external-resource-required | TODO | reaction, quote, merged-forward event evidence |
| M25 Feishu start command | $PHASE5_STATUS | TODO | account/version/status output |
| M26 Feishu doctor command | $PHASE5_STATUS | TODO | config/event/scope/OAuth/OAPI/CardKit diagnostics |

## Phase 9 Evidence Pack

| Item | Gate status | Operator result | Evidence |
| --- | --- | --- | --- |
| M27 Control UI browser smoke | operator-record-required | TODO | no blank page, JS error, asset 404; metis-app registered |
| M28 Control UI team CRUD | operator-record-required | TODO | create/edit/delete persists after refresh |
| M29 Control UI profile/model/binding | operator-record-required | TODO | Gateway RPC success or clear error |
| M30 Control UI Feishu wizard | operator-record-required | TODO | setup/repair wizard states |
| M31 Runtime log redaction | operator-record-required | TODO | Gateway/channel/OAPI logs from test resources |
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
| G11 | $PHASE3_STATUS | Telegram live route/broadcast gate |
| G12 | $PHASE4_STATUS | Feishu multi-account route gate |
| G13 | $PHASE4_STATUS | Feishu group/thread policy gate |
| G14 | $PHASE5_STATUS | Feishu OAuth live grant |
| G15 | $PHASE5_STATUS | Feishu app and tenant credential modes |
| G16 | $PHASE5_STATUS | Feishu OAPI live tool matrix |
| G17 | $PHASE5_STATUS | Feishu scope diagnostic live validation |
| G18 | external-resource-required | Feishu CardKit streaming live validation |
| G19 | external-resource-required | Feishu rich event and resource live validation |
| G20 | $PHASE5_STATUS | Feishu native command parity live smoke |
| G21 | external-resource-required | Feishu app and bot creation platform boundary |
| G22 | $PHASE4_STATUS | multi-bot mapping to agent or team |
| G23 | operator-record-required | Control UI product acceptance |
| G24 | local-pass | manual acceptance and evidence pack |
| G25 | local-pass | redaction discipline |

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
| M12 | $PHASE3_STATUS | TODO | Telegram private route |
| M13 | $PHASE3_STATUS | TODO | Telegram group/topic route |
| M14 | $PHASE3_STATUS | TODO | Telegram team broadcast |
| M15 | $PHASE4_STATUS | TODO | Feishu account status |
| M16 | $PHASE4_STATUS | TODO | Feishu group policy and mention gate |
| M17 | $PHASE4_STATUS | TODO | Feishu thread session |
| M18 | $PHASE5_STATUS | TODO | OAuth start/status/poll |
| M19 | $PHASE5_STATUS | TODO | OAuth revoke |
| M20 | $PHASE5_STATUS | TODO | OAPI read |
| M21 | $PHASE5_STATUS | TODO | OAPI write |
| M22 | external-resource-required | TODO | CardKit streaming |
| M23 | external-resource-required | TODO | resource read |
| M24 | external-resource-required | TODO | rich event |
| M25 | $PHASE5_STATUS | TODO | Feishu start command |
| M26 | $PHASE5_STATUS | TODO | Feishu doctor command |
| M27 | operator-record-required | TODO | Control UI browser smoke |
| M28 | operator-record-required | TODO | Control UI team CRUD |
| M29 | operator-record-required | TODO | Control UI profile/model/binding |
| M30 | operator-record-required | TODO | Control UI Feishu wizard |
| M31 | operator-record-required | TODO | runtime log redaction |
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

SERIES21_DOC_REL="develop_steps/metis-agent-team-series-21-post-phase20-source-backed-gap-quantification-manual-acceptance-2026-05-16.md"
SERIES21_DOC_MAIN="/Users/l3gi0n/work/workspace_cangjie/Metis/$SERIES21_DOC_REL"
PARITY_REPORT="develop_steps/metis-agent-team-series-14-oapi-action-parity-report-2026-05-15.md"
SERIES14_DOC="develop_steps/metis-agent-team-series-14-current-source-recheck-gap-quantification-manual-acceptance-2026-05-15.md"

if [[ -f "$SERIES21_DOC_REL" || -f "$SERIES21_DOC_MAIN" ]]; then
  SERIES21_SOURCE_AVAILABLE=true
else
  fail "missing series21 source-backed matrix: $SERIES21_DOC_REL or $SERIES21_DOC_MAIN"
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
  if [[ "$PHASE3_STATUS" == "operator-record-required" ]]; then
    info "live Telegram gate opted in; operator must record private route, group/topic route, alias route, and broadcast evidence"
  else
    info "live Telegram gate opted in but external resources are missing"
  fi
else
  info "live Telegram gate skipped; set METIS_AGENTTEAM_LIVE_TELEGRAM=1 with redacted test resource ids to enable manual smoke"
fi

if [[ "$FEISHU_OPT_IN" == true ]]; then
  if [[ "$PHASE4_STATUS" == "operator-record-required" || "$PHASE5_STATUS" == "operator-record-required" ]]; then
    info "live Feishu gate opted in; operator must record account route, OAuth, OAPI, CardKit, rich event, and redaction evidence"
  else
    info "live Feishu gate opted in but external resources are missing"
  fi
else
  info "live Feishu gate skipped"
fi

info "manual acceptance preflight passed"
