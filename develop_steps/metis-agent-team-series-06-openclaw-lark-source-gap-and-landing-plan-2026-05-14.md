# Metis Agent Team Series 06: OpenClaw / OpenClaw-lark Source-Backed Gap and Landing Plan

Date: 2026-05-14

## 1. Scope and Evidence Rule

This document re-checks the Agent Team feature against:

- Feishu public web article: `https://www.feishu.cn/content/article/7613711414611463386`
- OpenClaw core source: `/Users/l3gi0n/work/workspace_cangjie/openclaw`
- OpenClaw Feishu/Lark plugin source: `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark`
- Metis current source: `/Users/l3gi0n/work/workspace_cangjie/Metis`

Rules used in this document:

- Every GAP below is backed by a source path and line reference.
- If a behavior was not verified from source, it is not treated as a conclusion.
- The plan keeps changes inside Metis boundaries: config/scope, Gateway route/session, Feishu channel adapter, Gateway tools, Gateway RPC, Control UI, tests, and docs.
- This document does not change code or configuration.

## 2. Web Evidence: Feishu OpenClaw Official Plugin

The Feishu article is about the official OpenClaw Feishu plugin, not only a generic IM connector.

Verified public article facts:

- The page title is "OpenClaw飞书官方插件上线", dated 2026-03-05.
- It describes OpenClaw as a local/personal or server-side agent framework that can connect models, tools, and services.
- The official Feishu plugin can operate with user authorization and can access Feishu workplace context such as messages, docs, meetings, bitable, calendar, and tasks.
- It lists capabilities including message history/search/send/reply/resource download, docs create/update/read, bitable CRUD, calendar/event/freebusy, and task management.
- It explicitly mentions streaming card replies, merged-forward message recognition, and reactions.
- The usage section includes `/feishu auth`, `/feishu start`, `/feishu doctor`, Feishu streaming config, and `threadSession`.

The article-level capability list is consistent with `openclaw-lark/openclaw.plugin.json` and the source files below. Therefore the Metis comparison must not stop at "message routing works"; the meaningful parity target also includes Feishu OAuth, OAPI tools, streaming cards, resources, and thread/session behavior.

## 3. OpenClaw Core Agent Team Architecture

### 3.1 Current OpenClaw Core Diagram

```text
OpenClaw Control UI / CLI / Channel Plugin
        |
        v
Gateway RPC + Channel Runtime
        |
        v
Route Resolver
  input: channel, accountId, peer, parentPeer, guildId, teamId, roles
  output: agentId, accountId, sessionKey, mainSessionKey, matchedBy
        |
        v
Agent Scope
  agents.list[] / agents.defaults
  workspace
  agentDir
  sessions
  model
  skills/tools/memory/search/group/subagents/sandbox policy
        |
        +-----------------------------+
        |                             |
        v                             v
Per-Agent Workspace             Per-Agent State
  AGENTS.md                       auth-profiles.json
  SOUL.md                         models.json
  TOOLS.md                        sessions/
  IDENTITY.md
  USER.md
  HEARTBEAT.md
  BOOTSTRAP.md
  MEMORY.md
```

### 3.2 OpenClaw Core Source Facts

| Area | OpenClaw evidence | Meaning |
| --- | --- | --- |
| Agent isolation | `openclaw/docs/concepts/multi-agent.md:10-18` | One agent has separate workspace, state dir, and session store. |
| Per-agent auth | `openclaw/docs/concepts/multi-agent.md:20-37` | Each agent reads its own `auth-profiles.json`; main credentials are not shared automatically. |
| Per-agent skills | `openclaw/docs/concepts/multi-agent.md:39-44` | Skills load from agent workspace plus shared roots, then are filtered by agent allowlist. |
| Paths | `openclaw/docs/concepts/multi-agent.md:53-68` | Default config/state/workspace/agentDir/sessions layout. |
| Routing rules | `openclaw/docs/concepts/multi-agent.md:227-247` | Most-specific binding wins; omitted `accountId` means default account; `*` means channel-wide fallback; apply can upgrade channel binding to account-scoped. |
| Multiple accounts | `openclaw/docs/concepts/multi-agent.md:249-263` | Channels including `telegram` and `feishu` support account-level routing. |
| Route resolver inputs/outputs | `openclaw/src/routing/resolve-route.ts:26-60` | Route input/output structure. |
| Route tier order | `openclaw/src/routing/resolve-route.ts:743-830` | peer, parent, peer wildcard, guild+roles, guild, team, account, channel, default. |
| Workspace files | `openclaw/src/agents/workspace.ts:24-33`, `openclaw/src/agents/workspace.ts:132-141` | OpenClaw bootstrap set includes `HEARTBEAT.md` and `BOOTSTRAP.md` in addition to SOUL/AGENTS/etc. |
| Boundary-safe workspace read | `openclaw/src/agents/workspace.ts:56-69` | Reads are guarded by workspace root and max bytes. |
| Agent runtime schema | `openclaw/src/config/zod-schema.agent-runtime.ts:773-815` | Agent entries include model, skills, memorySearch, humanDelay, heartbeat, identity, groupChat, subagents, sandbox, tools, runtime. |
| Per-agent models.json | `openclaw/src/agents/models-config.ts:135-185` | `models.json` is ensured under agentDir with fingerprint/cache/write-lock behavior. |
| Gateway RPC list/create/files | `openclaw/src/gateway/server-methods/agents.ts:525-631`, `openclaw/src/gateway/server-methods/agents.ts:740-880` | Gateway exposes agents list/create and boundary-safe file list/get/set. |

## 4. OpenClaw-lark Feishu Plugin Architecture

### 4.1 Current OpenClaw-lark Diagram

```text
Feishu / Lark Platform
  webhook / long connect / card.action.trigger
        |
        v
openclaw-lark Channel Plugin
  plugin id: openclaw-lark
  channel: feishu
  capabilities: direct/group/media/reactions/threads/nativeCommands/blockStreaming
        |
        +-----------------------+
        |                       |
        v                       v
Account Config              Inbound Dispatch
  channels.feishu             accountScopedCfg
  channels.feishu.accounts    resolveAgentRoute(channel=feishu, accountId)
  per-account overrides       threadSessionKey
        |                       |
        |                       v
        |                    Gateway Runtime / Agent Session
        |
        +-----------------------+
        |                       |
        v                       v
OAuth / Token / Scope      Feishu OAPI Tools
  device flow                 user/bot message
  UAT token store             docs/wiki/drive/search
  app/user scope check        bitable/calendar/task/sheets
        |
        v
Outbound UX
  streaming card
  interactive card update
  tool-use display
  command cards
```

### 4.2 OpenClaw-lark Source Facts

| Area | OpenClaw-lark evidence | Meaning |
| --- | --- | --- |
| Plugin contract | `openclaw-lark/openclaw.plugin.json:1-64` | Plugin id is `openclaw-lark`; channel is `feishu`; declares Feishu tools for bitable/calendar/chat/docs/drive/search/sheets/task/wiki/OAuth/resource fetch. |
| Channel capabilities | `openclaw-lark/src/channel/plugin.ts:118-126` | Feishu channel supports direct/group, media, reactions, threads, native commands, and block streaming. |
| Prompt hints | `openclaw-lark/src/channel/plugin.ts:132-138` | Agents are told Feishu supports interactive cards, target inference, reactions, and delete constraints. |
| Plugin account config hooks | `openclaw-lark/src/channel/plugin.ts:167-201` | Plugin exposes account list/resolve/default/enable/delete/describe/allowFrom operations. |
| Multi-account config merge | `openclaw-lark/src/core/accounts.ts:5-9`, `openclaw-lark/src/core/accounts.ts:45-69`, `openclaw-lark/src/core/accounts.ts:80-112`, `openclaw-lark/src/core/accounts.ts:198-223` | `channels.feishu.accounts` overrides top-level config; account-scoped config replaces `channels.feishu` for downstream helpers. |
| Inbound route context | `openclaw-lark/src/messaging/inbound/dispatch-context.ts:27-45`, `openclaw-lark/src/messaging/inbound/dispatch-context.ts:105-135` | Dispatch context keeps `accountScopedCfg`, account, route, and system event keyed to the resolved session. |
| Thread sessions | `openclaw-lark/src/messaging/inbound/dispatch-context.ts:172-201` | `threadSession` checks whether the group is thread-capable, then creates thread-specific session keys. |
| Native command card path | `openclaw-lark/src/messaging/inbound/dispatch.ts:464-525` | `/feishu doctor/auth/start/help` are intercepted and sent as i18n cards. |
| Streaming card/tool use display | `openclaw-lark/src/messaging/inbound/dispatch.ts:63-75`, `openclaw-lark/src/messaging/inbound/dispatch.ts:241-270` | Normal messages use streaming card flow and optional tool-use display. |
| OAuth device flow | `openclaw-lark/src/core/device-flow.ts:96-163`, `openclaw-lark/src/core/device-flow.ts:192-260` | Device authorization requests `offline_access` and polls token endpoint. |
| UAT token store | `openclaw-lark/src/core/token-store.ts:5-18`, `openclaw-lark/src/core/token-store.ts:90-130` | User tokens are persisted in Keychain on macOS or encrypted files on Linux/Windows. |
| Scope-aware tool client | `openclaw-lark/src/core/tool-client.ts:140-156`, `openclaw-lark/src/core/tool-client.ts:196-250`, `openclaw-lark/src/core/tool-client.ts:317-390` | Tool invocation chooses UAT/TAT, checks app/user scopes, refreshes user token, and returns structured auth errors. |
| OAPI tools | `openclaw-lark/src/tools/oapi/index.ts:46-95` | Registers user/chat/IM/calendar/task/bitable/search/drive/wiki/sheets/bot tools. |
| User resource fetch | `openclaw-lark/src/tools/oapi/im/resource.ts:90-135`, `openclaw-lark/src/tools/oapi/im/resource.ts:157-180` | `feishu_im_user_fetch_resource` uses user OAuth and saves resources under `/tmp/openclaw`. |
| Interactive cards | `openclaw-lark/src/messaging/outbound/send.ts:214-315`, `openclaw-lark/src/channel/interactive-dispatch.ts:92-181` | Sends and patches interactive cards, and dispatches `card.action.trigger`. |

## 5. Metis Current Agent Team Architecture

### 5.1 Current Metis Diagram

```text
Control UI / CLI / Telegram / Feishu
        |
        v
Metis Gateway
  Gateway RPC
  ChannelManager / native channel adapters
        |
        v
Gateway Route Resolver
  channel, accountId, peer, parentPeer, guildId, teamId, roles
  binding apply/update/conflict checks
        |
        v
Gateway IM Route Session Context
  agentId
  workspaceDir
  agentDir
  modelsJsonPath
  authProfilesPath
  sessionsDir
  sessionKey
        |
        v
Gateway Agent Bridge
  unified Gateway tools
  runtime tool policy
  per-agent model order
  workspace bootstrap prompt
        |
        +---------------------------+
        |                           |
        v                           v
Native Telegram Adapter        Native Feishu Adapter
  mature media/send path         message.receive_v1 mapping
                                tenant token send/download
                                basic native commands
```

### 5.2 Metis Source Facts

| Area | Metis evidence | Meaning |
| --- | --- | --- |
| User-facing scope | `docs/user/agent-team.md:3-15` | Metis docs say agents have separate workspace/model/session; Telegram/Feishu are first-priority channels; Feishu plugin parity is not complete. |
| Workspace/state paths | `docs/user/agent-team.md:41-54` | Agent paths are under `~/.metis/workspaces/<agent-id>` and `~/.metis/agents/<agent-id>`. |
| Workspace files | `docs/user/agent-team.md:108-136` | Documents SOUL/AGENTS/IDENTITY/USER/TOOLS/MEMORY. |
| Model/auth docs | `docs/user/agent-team.md:149-158` | Documents `agents.models.*`, `models.json`, credential resolution. |
| Binding docs | `docs/user/agent-team.md:162-187` | Documents Telegram/Feishu account binding and structured route matching. |
| Explicit Feishu limitation | `docs/user/agent-team.md:231-232` | Docs state full OpenClaw Lark plugin surface is planned unless later release notes say otherwise. |
| Agent config validation/default | `src/core/config/metis_agent_scope.cj:139-223` | Parses entries, rejects duplicates, picks default agent. |
| Path boundaries | `src/core/config/metis_agent_scope.cj:254-317` | Expands paths and prevents relative path escapes. |
| Identity | `src/core/config/metis_agent_scope.cj:419-467` | Identity comes from config or `IDENTITY.md`, with avatar boundary checks. |
| Skills/tools policies | `src/core/config/metis_agent_scope.cj:496-542` | Reads per-agent/default array/object policies. |
| Per-agent model | `src/core/config/metis_agent_scope.cj:617-707` | Reads primary/fallback model from agent entry/defaults. |
| Per-agent provider/auth probe | `src/core/config/metis_agent_scope.cj:805-847` | Reads provider info from `models.json` and `auth-profiles.json`. |
| Route input/output | `src/gateway/core/gateway_agent_route_resolver.cj:7-105` | Metis route input/output mirrors OpenClaw concepts. |
| Account semantics | `src/gateway/core/gateway_agent_route_resolver.cj:341-410` | Default account, omitted account, explicit `default`, and wildcard are handled. |
| Route tier order | `src/gateway/core/gateway_agent_route_resolver.cj:436-559` | Metis route tier order mirrors OpenClaw plus exact naming. |
| Binding apply | `src/gateway/core/gateway_agent_route_resolver.cj:797-865` | Preserves non-route bindings, detects conflicts, and scope-upgrades. |
| Agent files RPC | `src/gateway/runtime/gateway_server_methods_agents.cj:1503-1582` | Lists/gets/sets workspace files through safe workspace helpers. |
| Agent models RPC | `src/gateway/runtime/gateway_server_methods_agents.cj:1678-1730` | Gets/sets per-agent `models.json`, returns redacted credential source. |
| Team CRUD | `src/gateway/runtime/gateway_server_methods_agents.cj:1814-1855`, `src/gateway/runtime/gateway_server_methods_agents.cj:1885-2085` | Supports team template/member agents/bindings/aliases/broadcast field/team create/update/list/get. |
| Agent delete cleanup | `src/gateway/runtime/gateway_server_methods_agents.cj:2248-2310` | Deletes non-main agent config/bindings and removes home-scoped workspace/agentDir. |
| Broadcast field only | `src/gateway/runtime/gateway_server_methods_agents.cj:1902-1910`, `src/gateway/runtime/gateway_server_methods_agents.cj:2064` | Team `broadcast` is persisted. Negative check used `rg "broadcast|gatewayAgentTeamBroadcast|team.*broadcast|broadcast.*team" src/gateway src/core docs ui/src`; only persistence/config/UI hits were found, not a Gateway turn execution consumer. |
| Runtime tools | `src/gateway/core/agent_bridge.cj:31-50` | Gateway includes Feishu media toolset, but not OpenClaw-lark OAPI docs/wiki/calendar/task/bitable tools. |
| Tool policy + prompt | `src/gateway/core/agent_bridge.cj:437-467`, `src/gateway/core/agent_bridge.cj:505-559` | Metis applies runtime tool policy and builds prompt from per-agent workspace files. |
| Feishu adapter API surface | `src/gateway/channels/feishu/feishu_adapter.cj:32-80` | Native Feishu client supports thread-capable check and message resource fetch only. |
| Feishu start path | `src/gateway/channels/feishu/feishu_adapter.cj:181-209` | Native adapter can run webhook or official SDK monitor host. |
| Feishu event breadth | `src/gateway/channels/feishu/feishu_adapter.cj:337-357` | Only `im.message.receive_v1` is accepted; other events are ignored. |
| Feishu inbound mapping | `src/gateway/channels/feishu/feishu_adapter.cj:446-520` | Maps text-bearing message events to unified inbound with route/gate/attachment context. |
| Feishu tenant resource download | `src/gateway/channels/feishu/feishu_adapter.cj:894-940`, `src/gateway/channels/feishu/feishu_adapter.cj:2019-2065` | Downloads current message resources using tenant token. |
| Feishu native commands | `src/gateway/core/gateway_service.cj:420-539` | `/feishu start/doctor/auth/info/help` return plain text; auth says OAuth is not completed. |
| Feishu current-turn media tools | `src/gateway/tools/gateway_feishu_media_toolset.cj:33-47`, `src/gateway/tools/gateway_feishu_media_toolset.cj:97-166` | Tools can list/fetch only resources already staged in current turn context. |
| Control UI profile files | `ui/src/ui/controllers/agent-teams.ts:94-101` | UI profile editor currently exposes SOUL/AGENTS/IDENTITY/USER/TOOLS/MEMORY. |
| Control UI team load | `ui/src/ui/controllers/agent-teams.ts:216-275` | UI can list/get team details and draft editor state. |

## 6. Source-Backed GAP Matrix

Status values:

- `aligned`: Metis source matches the verified OpenClaw/OpenClaw-lark behavior closely enough.
- `partial`: Metis has the skeleton or a subset, but lacks source-backed parity.
- `missing`: no verified Metis implementation found in the relevant path.
- `not-applicable`: verified OpenClaw behavior is intentionally outside Metis scope.

| ID | Capability | OpenClaw / OpenClaw-lark evidence | Metis evidence | Status | Exact GAP | Implementation task | Acceptance items |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AT-01 | Per-agent workspace, agentDir, sessions | `openclaw/docs/concepts/multi-agent.md:10-18`, `:53-68` | `docs/user/agent-team.md:41-54`, `src/core/config/metis_agent_scope.cj:254-317` | aligned | No core isolation gap found. | Keep current Metis path model; strengthen tests during later phases. | Existing agent route/session tests keep passing; temp-home tests prove two agents resolve different workspace/agentDir/sessions. |
| AT-02 | Per-agent auth profiles are not shared implicitly | `openclaw/docs/concepts/multi-agent.md:20-37` | `docs/user/agent-team.md:149-158`, `src/core/config/metis_agent_scope.cj:805-847` | partial | Metis can probe per-agent `auth-profiles.json`, but lifecycle and UI for explicit copy/import/diagnostics are weaker than OpenClaw's documented per-agent auth story. | Add auth profile management affordances and doctor checks without auto-sharing credentials. | Fake temp-home tests verify main auth is not copied unless explicit import RPC is used; UI never displays secrets. |
| AT-03 | Agent bootstrap file set | `openclaw/src/agents/workspace.ts:24-33`, `:132-141` | `docs/user/agent-team.md:108-136`, `ui/src/ui/controllers/agent-teams.ts:94-101` | partial | Metis UI exposes six files; OpenClaw also treats `HEARTBEAT.md` and `BOOTSTRAP.md` as bootstrap files. | Decide and implement Metis-owned `HEARTBEAT.md` / `BOOTSTRAP.md` support or explicitly mark them unsupported. If supported, expose via RPC/UI and prompt loader. | `agents.files.list` includes the full selected file set; boundary-safe get/set tests cover every file; prompt tests prove included files affect only the selected agent. |
| AT-04 | Agent runtime schema breadth | `openclaw/src/config/zod-schema.agent-runtime.ts:773-815` | `src/core/config/metis_agent_scope.cj:496-542`, `src/core/config/metis_agent_scope.cj:617-707`; doctor warnings: `src/gateway/core/gateway_agent_team_doctor.cj:419-445` | partial | Metis parses many policies, but memorySearch/subagents/sandbox/heartbeat enforcement is not at OpenClaw breadth. | Add enforcement or explicit diagnostics for each parsed-but-not-enforced agent field. | Doctor produces deterministic `ok/warning/error` rows; unit tests prove policy denial/enforcement for tools/subagents/sandbox/memory where implemented. |
| AT-05 | Binding route semantics and accountId semantics | `openclaw/docs/concepts/multi-agent.md:227-247`, `openclaw/src/routing/resolve-route.ts:743-830` | `src/gateway/core/gateway_agent_route_resolver.cj:341-559`, `:797-865` | aligned | No semantic gap found for route tier and binding apply. Naming differs (`binding.peer.exact` vs OpenClaw `binding.peer`) but behavior is comparable. | Keep semantics; add compatibility notes/tests when touching routing. | Tests cover omitted `accountId`, explicit `default`, `*`, peer/parent/wildcard/guild/team/account/channel priority, and scope-upgrade conflict behavior. |
| AT-06 | Team CRUD and managed member agents | OpenClaw core exposes agents create/list/files; Feishu/Miaoda team UX is product-level | `src/gateway/runtime/gateway_server_methods_agents.cj:1814-2085` | partial | Metis has team create/update/list/get and member creation, but only one built-in template (`pm-writer-reviewer`) and limited team-management UX compared with the Feishu/Miaoda product goal. | Expand templates and Control UI wizard around existing RPC instead of inventing a separate runtime. | UI can create/edit/delete a team with 1-N members, aliases, bindings, model files, and workspace profile files; all writes go through Gateway RPC. |
| AT-07 | Team broadcast / multiple agents for same incoming peer | OpenClaw docs point shared groups to broadcast groups: `openclaw/docs/concepts/multi-agent.md:224-225` | Metis stores `broadcast`: `src/gateway/runtime/gateway_server_methods_agents.cj:1902-1910`, `:2064`; negative check command listed in section 5.2 found no Gateway turn consumer | partial | Metis persists broadcast config but does not execute fan-out to multiple team members. | Design team broadcast as an explicit Gateway orchestration path with per-agent isolated sessions, concurrency limits, and delivery policy. | Fake channel test sends one group message and verifies selected team members each receive a separate turn/session; disabled broadcast remains single-agent. |
| FEI-01 | Feishu plugin capability declaration | `openclaw-lark/openclaw.plugin.json:1-64`, `src/channel/plugin.ts:118-126` | Metis native adapter, not plugin contract: `src/gateway/channels/feishu/feishu_adapter.cj:32-80` | partial | Metis has a native Feishu channel, but no source-backed capability registry equivalent to openclaw-lark's plugin contract. | Add Metis-native Feishu capability descriptor exposed through channel status/RPC, without replacing native adapter. | `channels.status`/Control UI show Feishu capabilities and missing setup states; tests verify descriptor is redacted and deterministic. |
| FEI-02 | Feishu multi-account merged config | `openclaw-lark/src/core/accounts.ts:5-69`, `:80-112`, `:198-223` | Metis route supports accountId; native adapter has accountId fields but no equivalent account-override merge source was verified | partial | Routing can distinguish accounts, but Feishu channel config lacks OpenClaw-lark's clear `channels.feishu.accounts` merge and account-scoped config view. | Add account override schema and resolver for Feishu native adapter, mirroring OpenClaw-lark one-level merge semantics. | Unit tests cover top-level default account, explicit accounts, account override precedence, redacted account listing, and disabled account behavior. |
| FEI-03 | Feishu native commands | `openclaw-lark/src/messaging/inbound/dispatch.ts:464-525` | `src/gateway/core/gateway_service.cj:420-539` | partial | Metis supports commands but returns plain text; `/feishu auth` is only guidance and does not start OAuth/onboarding. | Keep commands in Gateway service, upgrade output to structured/card-capable transport once card layer exists, and wire auth to OAuth phase. | Tests cover `/feishu start/doctor/auth/help/info`; auth test returns device-flow state after OAuth phase, not "not completed". |
| FEI-04 | OAuth/UAT token storage/scope manager | `openclaw-lark/src/core/device-flow.ts:96-163`, `:192-260`; `src/core/token-store.ts:5-18`, `:90-130`; `src/core/tool-client.ts:140-156`, `:196-250`, `:317-390` | Metis `/feishu auth` says OAuth incomplete: `src/gateway/core/gateway_service.cj:531-538`; tenant token only: `src/gateway/channels/feishu/feishu_adapter.cj:2019-2065` | missing | No Metis user OAuth device flow, user token store, user scope preflight, or refresh/retry path was verified. | Implement Metis Feishu auth subsystem: device flow, token store, scope metadata, redacted diagnostics, and structured auth errors. | No real Feishu network in tests; fake auth server verifies request/poll/expiry; token store tests use temp encrypted/keychain abstraction; logs never include tokens. |
| FEI-05 | Feishu OAPI tool suite | `openclaw-lark/openclaw.plugin.json:14-55`; `openclaw-lark/src/tools/oapi/index.ts:46-95` | Metis Gateway tools only include `GatewayFeishuMediaToolset`: `src/gateway/core/agent_bridge.cj:31-50` | missing | Metis lacks Feishu docs/wiki/drive/search/bitable/calendar/task/sheets/chat/user tools. | Add Metis-native Feishu OAPI toolsets backed by shared Feishu client and scope manager, phased by domain. | Tool inventory tests verify exact names/descriptions; fake Feishu API tests cover success/auth-missing/scope-missing for each domain; tool policy can allow/deny per agent. |
| FEI-06 | Current-turn media/resource handling | `openclaw-lark/src/tools/oapi/im/resource.ts:90-135`, `:157-180` | `src/gateway/channels/feishu/feishu_adapter.cj:894-940`; `src/gateway/tools/gateway_feishu_media_toolset.cj:33-166` | partial | Metis can fetch/stage current-message resources with tenant token, but lacks user-identity resource fetch for messages found through OAPI search/history. | Preserve current-turn tool; add user OAuth-backed resource fetch for arbitrary OAPI message resources. | Fake current-turn tests remain; fake user-resource tests save to temp Metis cache and reject > configured max size without real files. |
| FEI-07 | Interactive cards and streaming card UX | `openclaw-lark/src/messaging/inbound/dispatch.ts:63-75`, `:241-270`; `src/messaging/outbound/send.ts:214-315`; `src/channel/interactive-dispatch.ts:92-181` | Metis Feishu sends text through `sendTextToPeerDetailed`; no Feishu card send/update/action handler verified in native adapter/service | missing | Metis lacks Feishu interactive card send/patch, streaming card dispatcher, tool-use display, and card action callback handling. | Add native Feishu card abstraction in adapter + Gateway delivery hooks; keep text fallback. | Fake Feishu client records `interactive` send/patch; browser/control tests unaffected; normal text path remains fallback when card disabled. |
| FEI-08 | Feishu inbound event breadth | OpenClaw-lark handles card action and richer message converters: `openclaw-lark/src/channel/event-handlers.ts:407-421`, `openclaw-lark/src/messaging/inbound/parse.ts:101-109`; interactive dispatch source above | `src/gateway/channels/feishu/feishu_adapter.cj:337-357` | partial | Metis only accepts `im.message.receive_v1`; other events are ignored. | Add event dispatcher table for supported Feishu events, initially card actions and required message variants. | Fake webhook tests cover ignored unsupported events, accepted card action, text, image/file, and malformed payloads. |
| FEI-09 | Thread-capable Feishu group sessions | `openclaw-lark/src/messaging/inbound/dispatch-context.ts:172-201` | Metis API has `isThreadCapableGroup` and route context: `src/gateway/channels/feishu/feishu_adapter.cj:32-35`, `:446-520` | partial | Metis has the hook and context, but parity depends on native client implementation and tests for real thread-capable groups. | Make thread-capable check an injectable client responsibility with diagnostics and deterministic session key tests. | Fake Feishu client marks one group thread-capable; test proves thread message uses thread session and normal group uses group session. |
| UI-01 | Miaoda-like Agent Team management page | Product article establishes Feishu/OpenClaw official plugin focus; OpenClaw gateway exposes agents files/create/list | Metis UI can load teams and profile files: `ui/src/ui/controllers/agent-teams.ts:94-101`, `:216-275` | partial | Metis has Agent Team UI foundations, but not a full management page for agent creation, workspace/profile/model/auth/bindings/Feishu accounts in one workflow. | Build a Control UI Agent Team page over existing/new Gateway RPCs. | Browser smoke verifies page renders, custom element is registered, no JS errors, and CRUD works against fake Gateway RPC. |
| OPS-01 | Diagnostics | OpenClaw-lark `/feishu doctor` checks account/tool/auth states; evidence `openclaw-lark/src/messaging/inbound/dispatch.ts:493-504` | Metis doctor exists and redacts: `src/gateway/core/gateway_service.cj:489-528`; AgentTeam doctor reports model/auth/path and partial policy findings: `src/gateway/core/gateway_agent_team_doctor.cj:315-335`, `:419-445` | partial | Metis doctor is useful for AgentTeam core, but not deep enough for Feishu OAuth/OAPI/scopes/card/thread/account merge. | Extend doctor by capability area and expose same result to CLI/Telegram/Feishu/Control UI. | Doctor test snapshots cover missing app credential, missing OAuth, missing scopes, account conflict, card disabled, and no secret leakage. |

## 7. Target Metis Architecture After Gap Closure

```text
Control UI / CLI / Telegram / Feishu
        |
        v
Metis Gateway
  Gateway RPC
  ChannelManager
  AgentTeam Admin APIs
        |
        +------------------------------+
        |                              |
        v                              v
Agent Team Core                  Feishu Native Channel
  Agent scope                      account config resolver
  Route resolver                   webhook/long-connect events
  Team CRUD                        text/media/card outbound
  Team broadcast                   thread/session context
  Models/auth profile admin        card action dispatch
        |                              |
        v                              v
Gateway Turn Runtime             Feishu Auth + OAPI Layer
  per-agent workspace              tenant token
  per-agent agentDir                OAuth device flow
  per-agent sessions                UAT token store
  per-agent models                  scope-aware tool client
  runtime tool policy               docs/wiki/drive/search
  workspace bootstrap files         bitable/calendar/task/sheets
        |
        v
Delivery Hooks
  Telegram text/media/voice/video
  Feishu text/media/interactive cards/stream updates
```

Architecture constraints:

- Control UI must never call model providers or Feishu OpenAPI directly; it goes through Gateway RPC.
- Feishu adapter owns Feishu transport details; routing/session/model logic stays in Gateway core.
- Feishu OAuth/token storage is a Gateway subsystem, not an agent workspace file.
- Per-agent `auth-profiles.json` and `models.json` are isolated; no implicit copy from main.
- OAPI tools must use runtime tool policy so different agents/teams can expose different tools.
- Tests must use fake Feishu clients, fake auth servers, fake temp Metis home, and must not touch real `~/.metis` or real Feishu credentials.

## 8. Phased Landing Plan and Acceptance

### Phase 0: Evidence Baseline and Regression Harness

Subphases:

- 0.1 Freeze the source-backed capability matrix in this document.
- 0.2 Add or update test fixtures for temp Metis home, fake Feishu API client, fake Gateway RPC client, and fake Control UI client.
- 0.3 Add route/account/thread/binding snapshot tests where gaps will be touched.
- 0.4 Add docs cross-links from the current Agent Team docs to this series document.

Acceptance:

- No implementation behavior changes.
- `develop_steps` contains this source-backed GAP matrix.
- New test fixture code writes only under temp directories.
- `cjpm clean && cjpm build -i && cjpm test` passes after fixture-only code changes.

### Phase 1: OpenClaw Core Parity Hardening

Subphases:

- 1.1 Decide Metis-owned bootstrap file set: either add `HEARTBEAT.md` and `BOOTSTRAP.md`, or document why they are unsupported.
- 1.2 Ensure `agents.files.list/get/set` and Control UI profile editor expose the selected complete file set.
- 1.3 Strengthen per-agent auth lifecycle: redacted status, explicit import/copy operation if needed, no implicit main-agent sharing.
- 1.4 Extend doctor findings for parsed-but-not-enforced agent fields: memorySearch, subagents, sandbox, heartbeat, groupChat, tools.

Acceptance:

- Unit tests verify every supported profile file is boundary-safe and agent-scoped.
- Agent A cannot read or write Agent B workspace file through RPC.
- Per-agent auth status is redacted and deterministic.
- Doctor reports parsed-but-not-enforced fields as warnings until enforcement lands.

### Phase 2: Feishu Multi-Account Config Resolver

Subphases:

- 2.1 Add Metis Feishu account override schema mirroring OpenClaw-lark's one-level merge model.
- 2.2 Add `gatewayFeishuListAccountIds`, `gatewayFeishuResolveAccount`, `gatewayFeishuDefaultAccountId`, and redacted account descriptions.
- 2.3 Wire account-scoped config into Feishu adapter start/send/download/gate/thread checks.
- 2.4 Expose account diagnostics through Gateway RPC and Control UI status.

Acceptance:

- Tests prove top-level Feishu config is the default account.
- Tests prove account override fields win and unspecified fields fall back.
- Disabled accounts do not start adapter transport.
- Secrets are redacted in RPC/UI/log output.
- Existing Telegram/CLI routing is untouched.

### Phase 3: Team Runtime Orchestration and Broadcast

Subphases:

- 3.1 Specify exact Metis `team.broadcast` semantics: target member list, default agent behavior, concurrency, failure aggregation, and delivery format.
- 3.2 Implement Gateway orchestration path that fans out one inbound event to multiple team member turns only when explicit broadcast is enabled.
- 3.3 Keep each member turn isolated by agentId/sessionKey/workspace/model/tool policy.
- 3.4 Add safeguards for loops, duplicate delivery, and large group spam.

Acceptance:

- Fake group message to a broadcast team produces N isolated turns for selected members.
- Disabled broadcast preserves current single-agent behavior.
- Partial member failure is reported without cancelling successful member replies unless policy says so.
- Session keys prove no transcript mixing.

### Phase 4: Feishu OAuth / UAT / Scope Foundation

Subphases:

- 4.1 Implement Feishu OAuth device authorization and token polling behind an injectable HTTP client.
- 4.2 Implement Metis token store abstraction: macOS Keychain when available, encrypted temp/file backend for tests and non-macOS.
- 4.3 Add scope metadata and app/user scope preflight.
- 4.4 Upgrade `/feishu auth` from guidance-only to real device-flow onboarding.
- 4.5 Add redacted auth status RPC for Control UI.

Acceptance:

- Fake auth server tests cover success, authorization pending, slow down, expired token, denied token, and network error.
- Stored tokens never appear in logs, RPC responses, or test snapshots.
- `/feishu auth` returns a verification URL/user code and later reports authorized status.
- OAPI tool calls fail with structured `auth_required` or `scope_missing` before Phase 5 tools are fully enabled.

### Phase 5: Feishu OAPI Tool Surface

Subphases:

- 5.1 Add shared Metis Feishu OAPI client with tenant/user token modes and structured errors.
- 5.2 Implement high-value read tools first: user lookup, search, docs/wiki/drive read, chat/message search/history.
- 5.3 Implement write tools behind explicit tool policy: docs update/create, message send, task/calendar/bitable mutations.
- 5.4 Add per-agent tool allowlist integration and Control UI visibility.
- 5.5 Keep tool names compatible with OpenClaw-lark where practical, unless Metis has a clear reason and documented benefit to differ.

Acceptance:

- Tool inventory includes expected Feishu tool names and descriptions.
- Every tool has fake API tests for success, auth missing, scope missing, API error, and redacted logs.
- Write tools require explicit policy or operator-approved mode.
- Different agents can expose different Feishu tool subsets.

### Phase 6: Feishu Resource and Media Parity

Subphases:

- 6.1 Preserve current-turn tenant/bot resource staging.
- 6.2 Add user-auth resource fetch for message resources discovered through OAPI search/history.
- 6.3 Add size/type/path limits and a Metis temp cache policy.
- 6.4 Teach prompts/tool descriptions when to use current-turn fetch vs user OAPI fetch.

Acceptance:

- Current-turn media tests keep passing.
- User-resource tests fetch fake binary data into a temp Metis cache path.
- Oversized files, unsupported resource types, and missing scopes return structured diagnostics.
- Tests prove no writes outside temp/cache boundaries.

### Phase 7: Feishu Interactive Cards, Streaming, and Actions

Subphases:

- 7.1 Add Feishu outbound card abstraction to native adapter: send interactive, patch/update interactive, text fallback.
- 7.2 Add Gateway Feishu delivery hook for streaming card lifecycle.
- 7.3 Add tool-use display support based on account/team/agent config.
- 7.4 Add inbound `card.action.trigger` handling and route it through a safe action dispatcher.
- 7.5 Upgrade `/feishu start/doctor/auth/help` to card output with text fallback.

Acceptance:

- Fake Feishu client records interactive send and patch payloads.
- Streaming card tests verify initial card, partial updates, final update, and abort/error update.
- Card action tests verify accepted action, unknown action, and unauthorized action.
- Text fallback works when cards are disabled or Feishu returns card API failure.

### Phase 8: Control UI Agent Team Management Page

Subphases:

- 8.1 Add Agent Team dashboard: teams list, selected team summary, members, aliases, bindings, broadcast.
- 8.2 Add team create/edit wizard with explicit Telegram/Feishu first-priority binding helpers.
- 8.3 Add per-agent profile editor for supported workspace files.
- 8.4 Add per-agent model editor using `agents.models.get/set`.
- 8.5 Add Feishu account/auth/doctor panels.
- 8.6 Add capability and GAP indicators so the UI does not imply unsupported OpenClaw-lark parity.

Acceptance:

- Browser smoke test verifies Metis UI renders, `customElements.get("metis-app")` is registered, and no JS/CSS asset failures occur.
- UI operations use Gateway RPC only.
- Creating a team through UI produces the same config shape as direct RPC.
- Text does not expose raw `main`/internal ids where user-facing labels should be used.
- No OpenClaw branding assets are copied into Metis.

### Phase 9: Release Validation and Documentation

Subphases:

- 9.1 Update `docs/user/agent-team.md`, Control UI contract, and config examples.
- 9.2 Add migration notes from current Agent Team config to account-scoped Feishu config.
- 9.3 Run full validation: `source /Users/l3gi0n/cangjie100/envsetup.sh`, optional OpenSSL env if needed, `cjpm clean && cjpm build -i && cjpm test`.
- 9.4 Run Control UI build and browser smoke for any UI changes.
- 9.5 Add a release note section that clearly distinguishes aligned, partial, and still-missing OpenClaw-lark capabilities.

Acceptance:

- All Cangjie tests pass.
- UI build and browser smoke pass for UI phases.
- No test writes to real `~/.metis`, real Feishu config, real Telegram config, or real credentials.
- Docs include startup/usage steps for Telegram and Feishu Agent Team.
- The GAP matrix is updated to show which rows moved from `missing`/`partial` to `aligned`.

## 9. Immediate Priority Recommendation

The safest order is:

1. Finish Phase 1 and Phase 2 first, because they strengthen Metis' existing AgentTeam architecture without adding large Feishu OAPI scope.
2. Implement Phase 4 before Phase 5, because OpenClaw-lark's tools are built around UAT/TAT and scope preflight.
3. Implement Phase 7 after Phase 4, because auth/doctor/onboarding card UX depends on account/auth state.
4. Implement Phase 8 continuously but behind existing Gateway RPC, so UI never becomes a second source of truth.

The largest current Metis gaps are not basic agent routing. They are:

- Feishu user OAuth/UAT/scope subsystem.
- Feishu OAPI tool suite.
- Feishu interactive card/streaming card/action handling.
- Team broadcast runtime semantics.
- A complete Control UI management workflow for teams, agents, bindings, models, profile files, and Feishu accounts.
