# Metis AgentTeam series13 Team/Docs/Runbook Completion

Date: 2026-05-15

Worker: Team/Docs/Runbook

Worktree: `/Users/l3gi0n/work/workspace_cangjie/Metis/.worktrees/agentteam-s13-team-docs-20260515`

Branch: `work/agentteam-s13-team-docs-20260515`

## Scope

This completion record covers the non-UI, non-Feishu-OAPI/Auth/Card slice of series13:

- Phase 0: freeze evidence and acceptance baseline.
- Phase 7: clarify team collaboration UX and manager semantics.
- Phase 8: update end-to-end docs and add a Control UI browser smoke helper.
- Phase 9: define manual IM acceptance and release gate.

No UI source, Feishu OAPI, Feishu Auth, or Feishu Card implementation files are changed by this worker.

## Authority

The source-backed series13 plan is:

`/Users/l3gi0n/work/workspace_cangjie/Metis/develop_steps/metis-agent-team-series-13-source-recheck-gap-quantification-manual-acceptance-2026-05-15.md`

This worktree did not contain that file at start, so this record treats the main-workspace file above as the authoritative plan and persists the worker-local completion/runbook artifact here.

## Phase 0 Baseline

Evidence baseline now used by user-facing docs:

- AgentTeam product semantics are deterministic single-agent routing plus explicit fan-out.
- Manager behavior is manager-as-member or manager-as-default-agent only.
- Metis must not claim an autonomous manager runtime.
- Feishu wording must not regress to old "missing auth RPC" or "only start" style claims; current docs describe OAuth lifecycle RPC/buttons, native OAPI baseline, streaming-card baseline, and remaining live/parity gates.
- Live Telegram/Feishu validation is opt-in and must use test credentials.

Doc stale-wording gate:

```bash
METIS_HOME=/tmp/metis-agentteam-manual-acceptance scripts/agentteam-manual-acceptance-gate.sh
```

The helper rejects stale terms in `docs/user/agent-team.md`, runs `git diff --check`, and skips real browser or live IM checks unless explicitly configured.

## Phase 7 Semantics And Broadcast Aggregate

Gateway team RPC responses already expose:

```json
{
  "singleRoute": "deterministic-single-agent",
  "broadcast": "explicit-fan-out",
  "manager": "member-or-default-agent-only",
  "autonomousManagerRuntime": false
}
```

Broadcast aggregate rows now carry a deterministic per-agent `detail` field in addition to existing `status`, `delivered`, `deliveryStatus`, `deliveryError`, `error`, `elapsedMs`, `deliveryMessageId`, and `answer`.

Current timing limitation:

- `elapsedMs` remains present and stable for every row.
- The current aggregate builder receives completed `GatewayResolvedSessionTurnResult` values but no precise per-agent runner timing, so `elapsedMs` is `0` until runner timing is wired into the result contract.
- `detail` is the testable user-facing reason: `delivered`, `not-requested`, `send-failed: <error>`, or `missing-result: no execution result for broadcast member`.

Acceptance tests:

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:${DYLD_LIBRARY_PATH:-}"
cjpm test src/gateway/core --filter GatewayAgentTeamBroadcastTest --no-color
cjpm test src/gateway/runtime --filter GatewayServerMethodsAgentsTest --no-color
```

## Phase 8 Browser Smoke Helper

Added helper:

`scripts/agentteam-manual-acceptance-gate.sh`

Default behavior:

- Requires `METIS_HOME` to be set to an isolated test directory.
- Refuses the real `$HOME/.metis` unless `METIS_AGENTTEAM_ALLOW_REAL_HOME=1` is deliberately set.
- Checks stale AgentTeam/Feishu docs wording in `docs/user/agent-team.md`.
- Runs `git diff --check`.
- Skips browser smoke unless `METIS_AGENTTEAM_CONTROL_UI_URL` is set.

Browser smoke opt-in:

```bash
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
export METIS_AGENTTEAM_CONTROL_UI_URL="http://127.0.0.1:3000/"
scripts/agentteam-manual-acceptance-gate.sh
```

The browser smoke requires `ui/node_modules` and Playwright. It verifies:

- `customElements.get("metis-app")` is registered.
- visible Metis UI content is rendered.
- no browser page errors occur.
- no failed document/script/stylesheet requests occur.
- Agents navigation can reveal Teams content.

## Phase 9 Manual Acceptance Gate

Always start with a test home:

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
```

Gateway startup:

```bash
cjpm run --skip-build --name metis --run-args "gateway run"
```

Minimum local acceptance:

```bash
metis gateway status
metis gateway health
metis agents team create --team manual --name "Manual Team" --template pm-writer-reviewer
metis agents team get --team manual
metis gateway call agents.teams.update '{"id":"manual","broadcast":{"enabled":true,"members":["manual-writer","manual-reviewer"]}}'
metis gateway call agents.teams.get '{"id":"manual"}'
scripts/agentteam-manual-acceptance-gate.sh
```

Live IM acceptance is opt-in:

- Telegram: set `METIS_AGENTTEAM_LIVE_TELEGRAM=1` only with a test bot, test group/topic, and redacted log collection.
- Feishu: set `METIS_AGENTTEAM_LIVE_FEISHU=1` only with a test app, test tenant, test user, test group, declared scopes, and redacted log collection.
- Do not use real production groups or credentials for the manual gate.
- Never record bot tokens, app secrets, access tokens, refresh tokens, proxy credentials, or Authorization headers.

Manual result template:

```text
Acceptance date:
Metis commit:
METIS_HOME:
Gateway startup command:
Control UI URL:
Telegram test bot/account:
Feishu test app/account/tenant:
Authorized scopes:

Passed:
Failed:
Skipped with reason:
Browser smoke result:
Log redaction check:
Artifacts/screenshots:
Release decision:
```

## Pre-Submit Commands

Focused commands for this worker:

```bash
cjpm test src/gateway/core --filter GatewayAgentTeamBroadcastTest --no-color
cjpm test src/gateway/runtime --filter GatewayServerMethodsAgentsTest --no-color
METIS_HOME=/tmp/metis-agentteam-manual-acceptance scripts/agentteam-manual-acceptance-gate.sh
git diff --check
```

Full integration command set for main control:

```bash
cjpm clean
cjpm build -i
cjpm test
npm --prefix ui test
npm --prefix ui run build
METIS_HOME=/tmp/metis-agentteam-manual-acceptance scripts/agentteam-manual-acceptance-gate.sh
```

When the Control UI built assets or serving path changes, set `METIS_AGENTTEAM_CONTROL_UI_URL` and run the browser smoke instead of treating static builds as sufficient.

## Remaining Main-Control Items

- Wire precise per-agent elapsed timing into `GatewayResolvedSessionTurnResult` if runner-level timing becomes available.
- Run full `cjpm clean && cjpm build -i && cjpm test` in the integration branch.
- Run UI build/test and browser smoke in the integration branch or a live Gateway because this worker did not change UI source or built assets.
- Execute real Telegram/Feishu acceptance only with explicit test credentials and record skipped/live results in the template above.
