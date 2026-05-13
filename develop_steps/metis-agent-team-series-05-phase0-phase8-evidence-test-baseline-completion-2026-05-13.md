# Metis AgentTeam Series 05 Phase 0 / Phase 8 Evidence, Tests, And Completion Template

Date: 2026-05-13

Scope owner: Phase 0 and Phase 8 only. This record intentionally avoids Feishu adapter deep implementation and Control UI implementation changes.

## Phase 0 Evidence Baseline

| Capability | Current evidence | Current status | Planned delta |
| --- | --- | --- | --- |
| AgentTeam doctor is read-only | `src/gateway/core/gateway_agent_team_doctor.cj:891`-`:918` clones/scans config and returns `readOnly=true`; `src/gateway/core/gateway_agent_team_doctor_test.cj:150`-`:178` asserts the source root is unchanged. | aligned | Extend findings as later phases add Feishu policies and runtime enforcement. |
| Migration dry-run is read-only | `src/gateway/core/gateway_agent_team_doctor.cj:921`-`:940` builds dry-run output from a cloned binding apply preview; `src/gateway/core/gateway_agent_team_doctor_test.cj:198`-`:232` asserts binding preview does not mutate config. | aligned | Add apply-mode only after explicit user acceptance; dry-run must remain no-write. |
| Feishu migration preview | `src/gateway/core/gateway_agent_team_doctor.cj:740`-`:889` derives Feishu single/multi-account shape, default account, account suggestions, thread session, and group preview; `src/gateway/core/gateway_agent_team_doctor.cj:52`-`:99` redacts secret-like config preview fields. | partial | Later phases should wire true multi-account Feishu config and account-management RPC. |
| Route/session is channel-neutral | `src/gateway/core/gateway_im_route_session_context_test.cj:90`-`:112` builds one fake Gateway root with Telegram and Feishu accounts; `src/gateway/core/gateway_im_route_session_context_test.cj:263`-`:342` verifies Telegram alias, Feishu multi-account thread routes, and binding conflict. | aligned | Extend the same route semantics to future IM adapters. |
| Feishu adapter route context exists | `src/gateway/channels/feishu/feishu_adapter.cj:401`-`:444` attaches `mediaContext.context.imRoute` with `channel`, `accountId`, `peerKind`, `peerId`, parent peer, sender, and message id. | partial | Later phases add Feishu group policy, native mentions, resource download, and native commands. |
| Telegram alias baseline exists | `src/gateway/channels/telegram/telegram_adapter_test.cj:447`-`:460` fake-tests Telegram alias mention routing to writer and default fallback. | aligned | Keep Telegram as first validation channel for route/alias regressions. |
| User docs set capability boundary | `docs/user/agent-team.md` now includes a current-vs-planned table and states that Feishu plugin-level capabilities are not complete. | aligned | Keep release notes synchronized when planned Feishu work lands. |
| Control UI contract boundary | `docs/metis_control_ui_contract.md` now documents AgentTeam IM scope and `agents.migration.dryRun` shape without claiming full Feishu plugin support. | aligned | Control UI implementation must browser-smoke test any future UI change. |

## Phase 0 Test Baseline

| Test area | Evidence | Covers | Gaps |
| --- | --- | --- | --- |
| AgentTeam doctor/dry-run | `src/gateway/core/gateway_agent_team_doctor_test.cj:150`-`:283` | read-only scan, binding preview, Feishu migration preview, secret redaction expectation | Does not apply migrations. |
| Route/session fake E2E | `src/gateway/core/gateway_im_route_session_context_test.cj:263`-`:342` | same Gateway, Telegram + Feishu, multiple accounts, multiple agents, multiple threads, binding conflict | Does not invoke live transport or LLM runtime. |
| Feishu adapter fake payloads | `src/gateway/channels/feishu/feishu_adapter_test.cj:91`-`:160` | fake webhook thread/account route context | Does not call real Feishu API. |
| Telegram fake payloads | `src/gateway/channels/telegram/telegram_adapter_test.cj:447`-`:460` | fake Telegram alias routing | Does not call real Telegram API. |

## Phase 8 Acceptance Record Template

Use this template for each AgentTeam Series phase completion entry.

```text
## Phase N Completion - YYYY-MM-DD

Status: DONE | DONE_WITH_CONCERNS | BLOCKED

Scope:
- Files changed:
- Runtime behavior changed:
- Docs changed:

Source-backed evidence:
- Capability:
- Metis source path:line:
- Test path:line:

Verification:
- Command:
- Result:
- Known unrelated failures:

Safety checks:
- No real Telegram/Feishu network:
- No real token/credential:
- No real ~/.metis writes:
- Temp METIS_HOME/test home:
- Secret redaction checked:

Integration notes:
- Possible conflict files:
- Required main integration follow-up:
- Pending capabilities not implemented:
```

## Phase 8 Completion Snapshot For This Branch

Status: DONE_WITH_CONCERNS

Completed:

- `agents.migration.dryRun` now includes read-only `feishuMigration` preview for Feishu single-account shape, default account, account suggestions, threadSession, and groups.
- Binding apply `configPreview` is redacted before returning from migration dry-run.
- Fake route/session E2E covers same Gateway, Telegram alias routing, Feishu multiple accounts, multiple agents, multiple threads, and team binding conflict.
- User docs, Control UI contract, and Feishu channel docs state Telegram/Feishu first-priority IM scope and separate current capability from planned Feishu plugin-level work.

Verification recorded during implementation:

- `source /Users/l3gi0n/cangjie100/envsetup.sh && cjpm test src/gateway/core --filter GatewayAgentTeamDoctorTest.migrationDryRunPreviewsFeishuSingleAccountThreadSessionAndGroupsUpgrade`
  - Result: passed, 1 passed / 168 skipped in `metis.gateway.core`.
- `source /Users/l3gi0n/cangjie100/envsetup.sh && cjpm test src/gateway/core --filter GatewayImRouteSessionContextTest.fakeTelegramAndFeishuE2eRoutesMultipleChannelsAccountsThreadsAndConflicts`
  - Result: passed, 1 passed / 168 skipped in `metis.gateway.core`.
- `source /Users/l3gi0n/cangjie100/envsetup.sh && cjpm test`
  - Result: failed on environment/package issues outside this branch: `stdx.crypto` could not load OpenSSL `SHA1_Init` for Tencent Flash ASR tests, plus `metis.gateway.session` and `metis.program` package exit code 9. AgentTeam-related `metis.gateway.core` passed 169/169 inside the same run.

Integration notes:

- Potential policy-worker overlap: `src/gateway/core/gateway_agent_team_doctor.cj`, `src/gateway/core/gateway_agent_team_doctor_test.cj`, and `src/gateway/core/gateway_im_route_session_context_test.cj`.
- This branch does not implement Feishu adapter deep features, Feishu native commands, Feishu tool/resource downloads, or Control UI runtime implementation.
