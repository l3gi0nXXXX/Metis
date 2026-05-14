# Metis AgentTeam Series 12 Docs Verification Completion

Date: 2026-05-14

Worker scope: Phase 0 documentation baseline/regression gate, Phase 7 documentation side, Phase 8 management-UI copy plan, and Phase 9 runbook/verification gate. This worker did not modify runtime code or UI TypeScript.

## Source Boundary

Allowed writes for this slice:

- `docs/user/agent-team.md`
- AgentTeam documentation/runbook files under `develop_steps/`
- Optional documentation smoke scripts under `scripts/`

Files intentionally not touched:

- `src/gateway/**`
- `src/core/**`
- `ui/src/**`

The requested reference plan path, `develop_steps/metis-agent-team-series-12-current-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`, was not present in this worktree. This completion note records the Series 12 document-side gate for integration review.

## User-Facing Documentation Baseline

`docs/user/agent-team.md` now records these externally visible constraints:

- CLI usage goes through `metis agents team create/list/get/update/delete`, `metis agents bind/unbind`, and `metis gateway call agents.teams.*` for richer JSON routes and broadcast.
- Control UI usage is the existing `Agents -> Teams` page only. The document does not claim any separate non-existent tab or entry point.
- Telegram usage assumes an existing configured Telegram bot account; Metis binds and routes that account but does not create the bot.
- Feishu usage assumes an operator-created Feishu app/bot, event subscriptions, tenant installation/authorization, and Gateway-backed credentials. Metis provides setup guidance, redacted status, OAuth/status helpers, diagnostics, route binding, and config write-back through Gateway; it cannot non-interactively create the Feishu app/bot or grant tenant permissions.
- Each managed agent has independent workspace, `agentDir`, sessions directory, profile files, `models.json`, and `auth-profiles.json`.
- The supported agent profile names are `AGENTS.md`, `SOUL.md`, `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`, and `MEMORY.md`.
- `BOOTSTRAP.md` is supported but is not auto-created.

## Phase 0-9 Completion Checklist

| Phase | Document-side acceptance | Verification command or gate | Default network policy | Status |
| --- | --- | --- | --- | --- |
| Phase 0 | Documentation baseline exists; stale wording is checked before landing. | `rg -n "non-interactively create|BOOTSTRAP.md|Agents -> Teams|auth-profiles.json" docs/user/agent-team.md develop_steps/metis-agent-team-series-12-docs-verification-completion-2026-05-14.md` | Local text check only. | done |
| Phase 1 | Agent/team runtime source changes are outside this worker's scope. | Integration owner runs `source /Users/l3gi0n/cangjie100/envsetup.sh && cjpm test ...` for touched runtime slices. | Fake/local tests by default. | not-applicable |
| Phase 2 | Route/session/channel runtime source changes are outside this worker's scope. | Integration owner runs focused Gateway route/session tests for runtime changes. | Fake/local tests by default. | not-applicable |
| Phase 3 | Telegram runtime source changes are outside this worker's scope. | Telegram checks must use fake Bot API or local fixtures unless explicitly opted into live. | No real Telegram network by default. | not-applicable |
| Phase 4 | Feishu runtime source changes are outside this worker's scope. | Feishu checks must use fake webhook/OAPI fixtures unless explicitly opted into live. | No real Feishu network by default. | not-applicable |
| Phase 5 | Migration/apply runtime changes are outside this worker's scope. | `metis agents migrate --dry-run --json` may be used with fake config roots. | No user `~/.metis` writes by default. | not-applicable |
| Phase 6 | Model/auth runtime changes are outside this worker's scope. | Use temporary `METIS_HOME` and redacted fake credentials for any model/auth smoke. | No real provider credentials by default. | not-applicable |
| Phase 7 | User docs explain CLI, Control UI, Telegram, and Feishu without claiming unavailable entry points. | Markdown/text smoke with `rg`; reviewer reads `docs/user/agent-team.md`. | Local text check only. | done |
| Phase 8 | Management UI copy plan is documented while leaving `ui/src/**` untouched. | Verify docs only mention existing `Agents -> Teams` surface and Gateway RPC behavior. | Local text check only. | done |
| Phase 9 | Runbook gate lists clean/build/test/UI/browser-smoke requirements and live opt-in constraints. | See verification gate below. | Full live IM checks require explicit opt-in. | done |

## Verification Gate

Use this gate before claiming an integrated AgentTeam landing is release-ready. The document-only worker did not run the full gate because this slice did not modify runtime Cangjie or UI TypeScript, and other workers may still be changing those files in separate worktrees.

Baseline environment:

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
```

Repository clean/build/test:

```bash
cjpm clean
cjpm build -i
cjpm test
```

Control UI build:

```bash
npm --prefix ui run build
```

Control UI browser smoke must be run against built assets or a live Gateway page whenever `ui/`, `assets/control-ui/`, or Gateway static serving changes. Minimum smoke items:

- Built JavaScript has no raw TypeScript decorator syntax that the browser would reject.
- `customElements.get("metis-app")` is registered in the browser.
- The page renders visible Metis UI content instead of a blank document.
- Browser console has no page errors.
- Browser network has no failed JavaScript or CSS asset requests.
- Control token bootstrap writes to the same storage backend read by runtime code.
- Gateway static filenames are stable, or the running Gateway process is restarted before testing.
- Favicon and touch-icon assets remain Metis-owned and do not contain OpenClaw-specific markers such as `lobster-gradient`, `Left Claw`, `Right Claw`, or `pixel-lobster`.

## Live Opt-In Rules

The default verification gate must not use:

- real Telegram network;
- real Telegram bot tokens;
- real Feishu tenant/app credentials;
- real Feishu OAuth user tokens;
- real provider API keys;
- real user files under `~/.metis`.

Live Telegram or Feishu checks are opt-in only when all of these are true:

- An integration owner explicitly requests live validation for a named account/tenant.
- The account uses disposable or approved credentials.
- Logs and screenshots are checked for redaction before sharing.
- The test command uses a temporary `METIS_HOME` unless the owner explicitly authorizes a real config path.
- The final report names the exact live scope, date, account alias, and any skipped destructive action.

## Documentation Smoke Commands

Run these document-only checks in this worktree:

```bash
rg -n "create.*Feishu.*automatically|automatically create.*Feishu|BOOTSTRAP.md|auth-profiles.json|Agents -> Teams" docs/user/agent-team.md develop_steps/metis-agent-team-series-12-docs-verification-completion-2026-05-14.md
rg -n "OpenClaw public branding|lobster-gradient|Left Claw|Right Claw|pixel-lobster" docs/user/agent-team.md develop_steps/metis-agent-team-series-12-docs-verification-completion-2026-05-14.md
```

The first command confirms the required AgentTeam wording is present. The second command is expected to match only the verification-gate text that says those markers must not appear in Metis branding assets.

## Integration Note

`develop_steps/` is ignored by git in this repository. The integration owner must use `git add -f develop_steps/metis-agent-team-series-12-docs-verification-completion-2026-05-14.md` when collecting this completion artifact.
