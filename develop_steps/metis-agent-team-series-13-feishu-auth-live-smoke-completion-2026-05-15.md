# Metis AgentTeam series13 Feishu Auth Live Smoke Completion

Date: 2026-05-15

Scope: Phase 1 Feishu OAuth/UAT live validation gate.

## Implemented

- Added `channels.feishu.auth.liveSmoke` Gateway RPC.
- Added `METIS_FEISHU_LIVE_AUTH_SMOKE` opt-in gating. Without the env gate, the smoke writes a redacted skipped report and does not call Feishu network.
- Added `METIS_FEISHU_LIVE_AUTH_REPORT_DIR` report output support.
- Live smoke uses temporary report-local token/session stores instead of the user's normal token store.
- Live smoke records redacted fixtures for `start`, `status`, `poll`, `complete`, `refresh`, and `revoke`.
- Missing app credentials return a `configuration_error` report without network access.
- Report and fixture redaction removes app secrets, access tokens, refresh tokens, device codes, and Authorization headers.

## Tests

- `FeishuAuthFoundationTest` covers skipped mode, env-gated mode, missing credentials, fake-client full lifecycle, fixture redaction, and checklist metadata.
- `GatewayServerMethodsChannelsTest` covers the Gateway RPC skipped path and redacted report write.

## Acceptance

- Fake tests must not use real Feishu network, real app secrets, real user tokens, or the real `~/.metis` token store.
- Live validation is a manual release gate only after a test Feishu app, test tenant, and test user are prepared.
