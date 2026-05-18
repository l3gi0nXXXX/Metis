# Gateway Regression Contract

The gateway regression layer is split into focused scripts so new control-plane
and event-surface work can be locked down without inflating one giant script.

Current coverage:

- `scripts/gateway-regression.sh`
  - broad local RPC/control-plane surface
  - `connect.*`, `status`, `ops`, `control_ui.*`, `webchat.*`, HTTP/MCP
- `scripts/channel-regression.sh`
  - channel/plugin catalog, bindings, runtime, health, policy, and dispatch
- `scripts/cli-agent-gateway-regression.sh`
  - CLI to gateway to agent invoke path, session resolution, idempotency,
    delivery status, and managed agent commands
- `scripts/session-events-regression.sh`
  - transcript event subscription via `events.stream`
  - `connect.subscriptions` event-kind registry
  - `session.transcript.updated` payload projection
  - transcript-backed `binding` / `delivery` / `origin` replay in `sessions.list`

Build coordination:

- regression scripts that invoke `cjpm build` now share `scripts/build_lock.sh`
- this is required because multiple scripts building against the same `target/`
  and `build-script-cache/` can intermittently trigger linker failures such as:
  - `Array contains empty value: []`
  - `library not found for -lmetis.program`
- when adding a new regression or smoke script that calls `cjpm clean` or
  `cjpm build`, source `scripts/build_lock.sh` and wrap the build step with
  `with_metis_cjpm_build_lock ...`

Phase 14 expects new gateway/control-ui event work to extend one of these
scripts, instead of living only in unit tests.
