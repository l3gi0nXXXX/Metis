# Metis Gateway Parity Matrix

This document tracks one-to-one parity work between the current Metis gateway runtime and the upstream gateway platform.

Status labels:
- `done`: behavior is close enough to treat as implemented
- `partial`: implemented, but still not upstream-equivalent
- `missing`: not yet implemented

## Module Matrix

| Reference gateway area | Current Cangjie location | Status | Gap |
| --- | --- | --- | --- |
| transport / protocol / client-server runtime | `src/gateway/protocol/*.cj` + `src/gateway/runtime/gateway_server.cj` + `src/gateway/runtime/gateway_transport.cj` + `src/gateway/runtime/gateway_rpc_client.cj` | `partial` | Protocol envelopes, `connect/disconnect/connect.ack`, cancel, event pull, local/remote transport, `/rpc`, runtime snapshots, and transport state persistence exist, but reconnect state machine, server-driven push/streaming, and richer remote lifecycle semantics are still lighter than the reference runtime. |
| gateway CLI facade | `src/gateway/runtime/gateway_cli.cj` | `partial` | `metis gateway` command tree and primary subcommands now exist, but command semantics and operational depth are still not fully identical to the reference CLI. |
| server-method dispatch / families | `src/gateway/runtime/gateway_rpc_server_methods.cj` + `src/gateway/runtime/gateway_server_methods_*.cj` | `partial` | Method families now cover status/config/platform/sessions/channels/agents/chat/wizard/connect/dashboard/ops, but method depth and parameter semantics still need further parity work. |
| auth / scopes / device auth | `src/gateway/security/*.cj` | `partial` | Gateway token/password/trusted-proxy/device-auth enforcement exists, but the full reference auth/runtime interplay remains deeper. |
| control-ui runtime | `src/gateway/runtime/gateway_control_ui_runtime.cj` + `src/gateway/runtime/dashboard_server.cj` | `partial` | Control-ui contract, status, routes, auth summary, CSP, assets path, and runtime state exist, but it is still effectively a gateway-shaped dashboard rather than full reference control-ui parity. |
| dashboard API downshift | `src/gateway/runtime/gateway_dashboard_api.cj` + `src/gateway/runtime/gateway_server_methods_dashboard.cj` | `done` | Dashboard `/api/*` no longer owns business logic and now routes through gateway method families. |
| platform runtime | `src/gateway/runtime/gateway_platform_state.cj` + `src/gateway/runtime/gateway_server_methods_ops.cj` | `partial` | Node registry, pending work, device registration, push delivery, executor summary, and platform runtime summaries now exist, but node/device/push lifecycle depth is still lighter than the reference runtime. |
| HTTP runtime | `src/gateway/runtime/gateway_http_surface.cj` | `partial` | `/healthz`, `/readyz`, `/v1/chat/completions`, `/v1/responses`, `/v1/models`, `/v1/embeddings`, `/mcp`, and `/rpc` exist, with request context and MCP tool exposure, but attachments/files/images and runtime semantics remain lighter than the reference runtime. |

## Behavior Matrix

### Transport / Runtime

| Capability | Status | Notes |
| --- | --- | --- |
| protocol envelope / versioning | `done` | `protocolVersion`, `errorCode`, `details`, and request ids are part of request/response contracts. |
| `connect` / `disconnect` / `connect.ack` | `done` | Supported through both local and remote transport paths. |
| `request.cancel` / `events.pull` | `done` | Server-side active request registry and per-client event queues exist. |
| remote `/rpc` round-trip | `done` | Remote transport uses real HTTP `/rpc` requests. |
| reconnect / lifecycle depth | `partial` | Reconnect state fields and retries exist, but server-driven push, richer reconnect transitions, and full lifecycle parity are still missing. |

### Method Families

| Capability | Status | Notes |
| --- | --- | --- |
| `connect.*` family | `partial` | Includes `status`, `summary`, `ping`, `client`, `challenge`, `events`, `bindings`, `requests`, `disconnect`, `reconnect`; deeper control semantics still missing. |
| `agents.*` / `agent.*` family | `partial` | Includes `list`, `status`, `summary`, `health`, `capabilities`, `get`, `preview`, `invoke`; richer agent runtime control remains missing. |
| `channels.*` / `plugins.*` family | `partial` | Includes `list`, `status`, `get`, `health`, and `discover.detail`; still lighter than the reference plugin/channel runtime. |
| `chat.*` family | `partial` | Includes `history`, `send`, `status`, `sessions.list`, `sessions.delete`; still rooted in local bridge semantics. |
| `doctor` / `probe` | `partial` | Structured `checks`, `issues`, and `summary` exist; the check set still needs reference-level completeness. |

### Platform Runtime

| Capability | Status | Notes |
| --- | --- | --- |
| node registry / heartbeat | `done` | Persisted node registry and heartbeat updates exist. |
| pending work queue / claim / complete / execute | `partial` | End-to-end queue and executor summary exist, but this is still a minimal executor. |
| device register / device health | `partial` | Device registration and health/status views exist; richer lifecycle/auth flow still missing. |
| push send / record / summary / get | `partial` | Persisted delivery records and send APIs exist, but delivery runtime remains minimal. |

### Control UI / HTTP

| Capability | Status | Notes |
| --- | --- | --- |
| control-ui contract | `partial` | `basePath`, routes, auth mode, CSP, assets path, and summary exist. |
| control-ui routes/auth/assets methods | `partial` | `control_ui.status`, `contract`, `routes`, `auth`, `health`, `summary`, `assets`, `start` exist; still not identical to the reference control-ui runtime. |
| OpenAI-compatible HTTP endpoints | `partial` | Primary endpoints exist and return structured request context. |
| MCP over HTTP | `partial` | `initialize`, `ping`, `tools/list`, `tools/call` are supported with gateway runtime tools, but semantics are still lighter than the reference runtime. |

## Remaining Hard Gaps

These gaps are still considered mandatory parity work:

1. Transport/runtime must deepen beyond retry fields into fuller reconnect and remote lifecycle semantics.
2. Control-ui must continue moving away from “dashboard with gateway wrapping” toward a more native reference-style runtime.
3. Platform runtime must deepen node/device/push lifecycle behavior beyond today’s minimal executor/registry model.
4. Method families still need richer operational semantics, not just structured summaries.
5. HTTP runtime still needs deeper reference-style request/attachment/runtime behavior.
6. The external HTTP surface exposed by `gateway run` now aligns with the internal `gateway_http_surface` contract for the current regression set (`/healthz`, `/readyz`, `/rpc`, `/mcp`, `/v1/models`, `/v1/embeddings`), but richer reference-style HTTP/runtime semantics are still missing.

## Regression Priority

Before more gateway feature work, regression coverage should exist for:

1. Local gateway CLI + local RPC method families.
2. Real `gateway run` startup against an isolated `METIS_HOME`.
3. HTTP `/healthz`, `/readyz`, `/rpc`, `/mcp`, `/v1/models`, `/v1/embeddings`.
4. Core runtime methods:
   - `connect.summary`
   - `agents.summary`
   - `control_ui.summary`
   - `platform.runtime`
   - `doctor`
   - `nodes.execute`
5. Session event surfaces:
   - `events.stream` transcript subscriptions
   - `connect.subscriptions` event-kind registry
   - transcript-backed `binding` / `delivery` / `origin` replay
