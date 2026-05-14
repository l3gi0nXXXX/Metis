# Metis AgentTeam series13 Feishu Card/Event Completion

Date: 2026-05-15

Scope: Phase 4 and Phase 5 Feishu streaming-card and rich-event parity baseline.

## Implemented

- Added observable streaming-card state for phase, CardKit status, card message id, sequence, flush state, fallback state, unavailable termination state, and image resolver state.
- Added pending flush exposure and message-unavailable fallback details so UI/diagnostics can explain stream termination.
- Added safe image reference resolver that reuses registered Feishu `img_` keys and never fetches remote/local files by default.
- Added card action deduplication and card action thread projection.
- Expanded Feishu event replay samples with account id, app id, peer id, thread id, dedup expectations, system-event kinds, and media metadata expectations.
- Added `METIS_FEISHU_LIVE_EVENT_REPLAY_SMOKE` checklist for opt-in live replay validation.

## Tests

- `FeishuAdapterTest` covers streaming observable state, fallback/unavailable detail, image resolver boundaries, event replay checklist, replay sample expectations, dedup behavior, thread projection, and media metadata-only replay.

## Acceptance

- Fake tests must not call real Feishu network or download real media.
- Event replay fixtures must remain redacted and must not include Authorization headers, tenant secrets, access tokens, refresh tokens, or private user content.
- Live event replay remains opt-in and requires test Feishu tenant/app/chat fixtures.
