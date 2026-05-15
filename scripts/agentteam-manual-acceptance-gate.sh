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

redacted_flag() {
  if [[ -n "${1:-}" ]]; then
    printf "provided-redacted"
  else
    printf "not-provided"
  fi
}

resource_status() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    printf "provided-redacted"
  else
    printf "missing"
  fi
}

write_evidence_pack() {
  local report_dir="$1"
  local report_json="$report_dir/report.json"
  local template_md="$report_dir/manual-acceptance-template.md"
  local created_at
  local head
  local telegram_status
  local telegram_reason
  local telegram_check_status
  local telegram_check_reason
  local telegram_opt_in
  local feishu_status
  local control_ui_status

  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  head="$(git rev-parse HEAD)"
  telegram_status="skipped"
  telegram_reason="opt-in-disabled"
  telegram_check_status="skipped"
  telegram_check_reason="opt-in-disabled"
  telegram_opt_in="false"
  feishu_status="skipped"
  control_ui_status="skipped"
  if [[ "${METIS_AGENTTEAM_LIVE_TELEGRAM:-0}" == "1" ]]; then
    telegram_opt_in="true"
    if [[ -z "${METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID:-}" || -z "${METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID:-}" ]]; then
      telegram_status="skipped"
      telegram_reason="external-resource-required"
      telegram_check_status="skipped"
      telegram_check_reason="external-resource-required"
    else
      telegram_status="manual-opt-in-record-required"
      telegram_reason="operator-record-required"
      telegram_check_status="manual-opt-in-record-required"
      telegram_check_reason="operator-record-required"
    fi
  fi
  if [[ "${METIS_AGENTTEAM_LIVE_FEISHU:-0}" == "1" ]]; then
    feishu_status="manual-opt-in-record-required"
  fi
  if [[ -n "${METIS_AGENTTEAM_CONTROL_UI_URL:-}" ]]; then
    control_ui_status="enabled"
  fi

  cat >"$report_json" <<JSON
{
  "kind": "metis-agentteam-manual-acceptance-evidence",
  "series": "17",
  "phases": "0-1",
  "createdAt": "$created_at",
  "gitHead": "$head",
  "metisHome": "$METIS_HOME_CANONICAL",
  "reportDir": "$report_dir",
  "controlUi": {
    "status": "$control_ui_status",
    "url": "$(redacted_flag "${METIS_AGENTTEAM_CONTROL_UI_URL:-}")"
  },
  "liveGates": {
    "telegram": {
      "status": "$telegram_status",
      "reason": "$telegram_reason",
      "optIn": $telegram_opt_in,
      "accountId": "$(redacted_flag "${METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID:-}")",
      "chatOrTopic": "$(redacted_flag "${METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID:-}")",
      "requiredResources": [
        {
          "name": "METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID",
          "status": "$(resource_status METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID)"
        },
        {
          "name": "METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID",
          "status": "$(resource_status METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID)"
        }
      ],
      "manualChecks": [
        {
          "id": "account-route",
          "status": "$telegram_check_status",
          "reason": "$telegram_check_reason"
        },
        {
          "id": "group-topic-session-isolation",
          "status": "$telegram_check_status",
          "reason": "$telegram_check_reason"
        },
        {
          "id": "alias-route",
          "status": "$telegram_check_status",
          "reason": "$telegram_check_reason"
        },
        {
          "id": "broadcast-aggregate",
          "status": "$telegram_check_status",
          "reason": "$telegram_check_reason"
        }
      ]
    },
    "feishu": {
      "status": "$feishu_status",
      "accountId": "$(redacted_flag "${METIS_AGENTTEAM_FEISHU_ACCOUNT_ID:-}")",
      "tenant": "$(redacted_flag "${METIS_AGENTTEAM_FEISHU_TENANT_ID:-}")",
      "chatOrThread": "$(redacted_flag "${METIS_AGENTTEAM_FEISHU_CHAT_ID:-}")"
    }
  },
  "redaction": {
    "storesRealMetisHome": false,
    "containsTelegramBotToken": false,
    "containsFeishuAppSecret": false,
    "containsAccessToken": false,
    "containsRefreshToken": false,
    "containsAuthorizationHeader": false
  }
}
JSON

  cat >"$template_md" <<MD
# Metis AgentTeam Manual Acceptance Evidence

- Date: $created_at
- Git head: $head
- METIS_HOME: $METIS_HOME_CANONICAL
- Report dir: $report_dir
- Operator: TODO
- Gateway URL: TODO redacted or local-only
- Control UI URL: ${control_ui_status}

## Phase 0 Evidence Freeze

| Check | Result | Evidence |
| --- | --- | --- |
| Series 15 source-backed conclusion is current | TODO pass/fail | TODO |
| Series 14 OAPI parity is 108 aligned / 0 partial / 0 missing / 0 not-applicable | TODO pass/fail | TODO |
| Live Telegram/Feishu gates are opt-in only | TODO pass/fail | See report.json liveGates |

## Phase 1 Redacted Live Resource Pack

| Resource | Result | Redacted Evidence |
| --- | --- | --- |
| Isolated METIS_HOME | TODO pass/fail | $METIS_HOME_CANONICAL |
| Telegram test bot/account | TODO skipped/pass/fail | redacted id only |
| Telegram test group/topic | TODO skipped/pass/fail | redacted id only |
| Feishu test app/account | TODO skipped/pass/fail | redacted id only |
| Feishu tenant/user/group/thread | TODO skipped/pass/fail | redacted id only |
| Provider key for per-agent model smoke | TODO skipped/pass/fail | source summary only |

## Phase 1 Core AgentTeam CLI/RPC Acceptance

| Check | Result | Evidence |
| --- | --- | --- |
| CLI team create/list/get/update/delete | TODO pass/fail | TODO |
| CLI custom members and aliases | TODO pass/fail | TODO |
| RPC agents.teams create/list/get/update/delete | TODO pass/fail | TODO |
| Profile files list/get/set including BOOTSTRAP.md creation | TODO pass/fail | TODO |
| Per-agent models and credential source redaction | TODO pass/fail | TODO |
| Binding conflict rejects same route/different agent without partial write | TODO pass/fail | TODO |
| Broadcast aggregate includes per-agent status/detail/answer/sessionKey | TODO pass/fail | TODO |

## Phase 3 Telegram Live Route Gate

| Check | Gate Result | Evidence |
| --- | --- | --- |
| Account route | $telegram_check_status | $telegram_check_reason; redacted account only |
| Group/topic session isolation | $telegram_check_status | $telegram_check_reason; redacted chat/topic only |
| Alias route | $telegram_check_status | $telegram_check_reason; @writer or /agent writer manual smoke |
| Broadcast aggregate | $telegram_check_status | $telegram_check_reason; aggregate rows must include agentId/status/sessionKey |

## Redaction Checklist

- No real ~/.metis path was used.
- No Telegram bot token was recorded.
- No Feishu app secret was recorded.
- No access or refresh token was recorded.
- No auth header was recorded.
- No proxy credentials or provider keys were recorded.
MD

  if rg -n -i 'bot[ _-]?token[=:][^ ]+|app[ _-]?secret[=:][^ ]+|access[ _-]?token[=:][^ ]+|refresh[ _-]?token[=:][^ ]+|authorization:[[:space:]]*bearer[[:space:]]+[^ ]+|sk-[A-Za-z0-9_-]{16,}' "$report_dir" >/tmp/metis-agentteam-gate-redaction.txt; then
    cat /tmp/metis-agentteam-gate-redaction.txt >&2
    rm -f /tmp/metis-agentteam-gate-redaction.txt
    fail "redaction scan found secret-like evidence in $report_dir"
  fi
  rm -f /tmp/metis-agentteam-gate-redaction.txt
}

require_command git
require_command rg

PARITY_REPORT="develop_steps/metis-agent-team-series-14-oapi-action-parity-report-2026-05-15.md"
SERIES14_DOC="develop_steps/metis-agent-team-series-14-current-source-recheck-gap-quantification-manual-acceptance-2026-05-15.md"

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
  cleanup() {
    rm -f "$SMOKE_SCRIPT"
  }
  trap cleanup EXIT
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

if [[ "${METIS_AGENTTEAM_LIVE_TELEGRAM:-0}" == "1" ]]; then
  if [[ -z "${METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID:-}" || -z "${METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID:-}" ]]; then
    info "live Telegram gate skipped: external-resource-required; provide METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID and METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID to enable manual smoke"
  else
    info "live Telegram gate opted in for account=${METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID}; test chat/topic ids are operator-provided and must be redacted in reports"
    info "live Telegram route checks remain manual: account route, group/topic session isolation, alias routing, and team broadcast aggregate"
  fi
else
  info "live Telegram gate skipped; set METIS_AGENTTEAM_LIVE_TELEGRAM=1 with METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID and METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID to enable manual smoke"
fi

if [[ "${METIS_AGENTTEAM_LIVE_FEISHU:-0}" == "1" ]]; then
  info "live Feishu gate is opt-in; record app/account/tenant/scopes, pass/fail, and log redaction result in the runbook"
else
  info "live Feishu gate skipped"
fi

info "manual acceptance preflight passed"
