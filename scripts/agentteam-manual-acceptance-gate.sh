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

require_command git
require_command rg

METIS_HOME_VALUE="${METIS_HOME:-}"
[[ -n "$METIS_HOME_VALUE" ]] || fail "set METIS_HOME to an isolated test directory, for example /tmp/metis-agentteam-manual-acceptance"

REAL_HOME="$(cd "$HOME" && pwd -P)/.metis"
METIS_HOME_CANONICAL="$(mkdir -p "$METIS_HOME_VALUE" && cd "$METIS_HOME_VALUE" && pwd -P)"
if [[ "$METIS_HOME_CANONICAL" == "$REAL_HOME" && "${METIS_AGENTTEAM_ALLOW_REAL_HOME:-0}" != "1" ]]; then
  fail "METIS_HOME points at the real home ($REAL_HOME). Use a test home or set METIS_AGENTTEAM_ALLOW_REAL_HOME=1 deliberately."
fi
info "METIS_HOME=$METIS_HOME_CANONICAL"

stale_patterns=(
  "Auth status RPC missing"
  "只 start"
  "4 个文件"
  "自动创建 Feishu"
)
for pattern in "${stale_patterns[@]}"; do
  if rg -n "$pattern" docs/user/agent-team.md >/tmp/metis-agentteam-gate-rg.txt; then
    cat /tmp/metis-agentteam-gate-rg.txt >&2
    fail "stale AgentTeam/Feishu wording found in docs/user/agent-team.md: $pattern"
  fi
done
rm -f /tmp/metis-agentteam-gate-rg.txt
info "docs stale-wording check passed"

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
  info "live Telegram gate is opt-in; record test bot/account, group/topic, pass/fail, and log redaction result in the runbook"
else
  info "live Telegram gate skipped"
fi

if [[ "${METIS_AGENTTEAM_LIVE_FEISHU:-0}" == "1" ]]; then
  info "live Feishu gate is opt-in; record app/account/tenant/scopes, pass/fail, and log redaction result in the runbook"
else
  info "live Feishu gate skipped"
fi

info "manual acceptance preflight passed"
