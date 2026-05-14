# Metis AgentTeam 系列 13：源码复核、GAP 量化、补齐计划与手工验收清单

日期：2026-05-15

## 1. 本轮结论

本轮重新复核了飞书官方网页、OpenClaw 核心多 Agent 源码、OpenClaw-Lark 飞书插件源码、Metis 当前 `main` 分支源码，以及 series 08 到 series 12 的历史分析和补齐进展。

结论分两层：

- **AgentTeam 核心架构层**：Metis 已经基本对齐 OpenClaw 的多 Agent 隔离、`agents/` 目录语义、workspace、agentDir、session、per-agent model、per-agent auth profile、binding apply、`accountId`、路由优先级、Gateway RPC 管理、Control UI Teams 页面和 deterministic fan-out。本轮 Phase 0-9 补齐 broadcast aggregate detail、manual acceptance gate 和 Feishu setup wizard 后，按源码和本地测试能力量化，当前完成度约 **95/100**。
- **飞书 Claw 生产体验层**：Metis 已补齐 Feishu OAuth lifecycle、OAPI native client/toolset、rich event baseline、streaming card controller、Control UI Auth & Doctor、Teams wizard 和 profile/model 管理。本轮 Phase 0-9 进一步补齐了 live auth smoke gate、TAT/app token provider、OpenClaw-Lark 当前源码 108 action 自动 parity report、Card/Event 可观测状态和手工验收 gate；剩余差距集中在真实 UAT/TAT/app-scope 自动授权闭环、scope-exact OAPI closure、完整 CardKit 细节、Miaoda-like 管理闭环和真实租户验收。按真实飞书生产体验量化，当前完成度约 **84/100**。

后续工作量估算：

- 达到“源码/本地 fake-tested 能力 95 分以上”：本轮 Phase 0-9 落地后已基本达到，后续主要是根据 scope-exact report 关闭 partial 行，约 **1-2 人日**。
- 达到“真实飞书租户生产验收 90 分以上”：约 **5-8 人日**，前提是提供可测试的飞书应用、租户、测试用户、测试群、必要事件订阅和 scopes。
- 达到“OpenClaw-Lark 全量体验追平，包括 108 action scope-exact closure、完整 CardKit 细节、真实事件矩阵和 Miaoda-like 管理 UI”：约 **8-12 人日**。

本轮 Phase 0-9 落地记录：

- Phase 1：新增 `channels.feishu.auth.liveSmoke`、`METIS_FEISHU_LIVE_AUTH_SMOKE` 和 redacted fixture/report gate，完成记录见 `develop_steps/metis-agent-team-series-13-feishu-auth-live-smoke-completion-2026-05-15.md`。
- Phase 2/3：新增 TAT/app token provider 与自动 action parity report，完成记录见 `develop_steps/metis-agent-team-series-13-oapi-action-parity-report-2026-05-15.md`。
- Phase 4/5：新增 Feishu streaming-card observable state、image resolver、rich event replay baseline 和 event replay live gate，完成记录见 `develop_steps/metis-agent-team-series-13-feishu-card-events-completion-2026-05-15.md`。
- Phase 6：新增 Control UI Feishu setup/repair wizard，完成记录见 `develop_steps/metis-agent-team-series-13-control-ui-setup-wizard-completion-2026-05-15.md`。
- Phase 0/7/8/9：新增 AgentTeam docs/runbook、manual acceptance gate 和 broadcast aggregate detail，完成记录见 `develop_steps/metis-agent-team-series-13-team-docs-runbook-2026-05-15.md`。

## 2. 信息来源与复核边界

### 2.1 网页来源

- 飞书智能体团队介绍页：`https://www.feishu.cn/content/article/7613711414611463386`
- 飞书 OpenClaw-Lark/插件能力介绍页：`https://www.feishu.cn/content/article/7629286303804329160`

网页侧确认的产品方向包括：一次部署多个智能体、可视化创建和管理团队、飞书群内协作、模型管理、插件/工具能力、飞书渠道配置、OAuth/OAPI、自动诊断修复和流式卡片体验。

### 2.2 源码复核边界

本轮只对 AgentTeam 和飞书团队能力相关路径下结论：

- OpenClaw：`docs/concepts/multi-agent.md`、`docs/channels/channel-routing.md`、`src/agents/agent-scope.ts`、`src/routing/resolve-route.ts`、`src/routing/session-key.ts` 以及相关 agent/routing/gateway 文件清单。
- OpenClaw-Lark：`README.md`、`src/channel/*`、`src/messaging/inbound/*`、`src/messaging/outbound/*`、`src/core/*`、`src/tools/*`、`src/card/*` 和 OAPI tool 注册路径。
- Metis：`docs/user/agent-team.md`、`src/core/config/metis_agent_scope.cj`、`src/core/prompting/metis_workspace_bootstrap.cj`、`src/gateway/core/gateway_agent_route_resolver.cj`、`src/gateway/core/gateway_agent_team_broadcast.cj`、`src/gateway/channels/feishu/*`、`src/gateway/tools/gateway_feishu_oapi_*`、`src/gateway/runtime/gateway_server_methods_*`、`ui/src/ui/views/agents*.ts`、`ui/src/ui/controllers/agent-teams.ts`、`ui/src/ui/navigation.ts`。

不使用文件名推断作为结论。每个 GAP 都必须能落到源码路径、行号或历史验证结果。

### 2.3 历史进展纳入

纳入以下历史文档和当前主分支最新提交：

- `develop_steps/metis-agent-team-series-08-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-09-prioritized-implementation-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-10-feishu-openclaw-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-11-post-phase0-9-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-12-current-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-12-docs-verification-completion-2026-05-14.md`
- 本轮启动基线提交：`0f93f80 Complete AgentTeam series12 Feishu and UI parity`

series 12 之后已经合入的关键进展：

- UI profile 下拉已经从旧的 4 个文件补齐到 8 个文件：`AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md`，见 `ui/src/ui/controllers/agent-teams.ts:123-132`。
- Control UI Feishu Auth & Doctor 已有 `start/status/poll/complete/revoke` 操作按钮，见 `ui/src/ui/views/agents-panel-teams.ts:1276-1316`。
- Gateway RPC 已暴露 `channels.feishu.auth.start/status/poll/complete/revoke`，见 `src/gateway/runtime/gateway_server_methods_channels.cj:2317-2361`。
- series12 提交包含 Feishu auth、OAPI、card/events、team wizard/doctor、docs 和 built assets 更新，见 `git show --stat --oneline HEAD`。
- series12 集成验证记录为：`cjpm clean`、`cjpm build -i`、`cjpm test`、`npm --prefix ui test`、`npm --prefix ui run build` 和浏览器 smoke 均通过；其中 Cangjie 测试最终为 `1377/1377`，UI 测试为 `32/32`。

## 3. OpenClaw / OpenClaw-Lark 架构事实

### 3.1 OpenClaw 核心 AgentTeam 架构

源码事实：

- OpenClaw 将一个 Agent 定义为独立 workspace、`agentDir` 和 sessions，见 `openclaw/docs/concepts/multi-agent.md:10-18`。
- per-agent auth profile 路径为 `~/.openclaw/agents/<agentId>/agent/auth-profiles.json`，主 Agent 凭证不会自动共享，见 `openclaw/docs/concepts/multi-agent.md:20-37`。
- Skills 来自 agent workspace 和共享 roots，再由 agent allowlist 过滤，见 `openclaw/docs/concepts/multi-agent.md:39-44`。
- 默认路径、默认 agentId、`agent:main:main` session key 和默认 state 路径见 `openclaw/docs/concepts/multi-agent.md:53-68`。
- agent wizard 和 bindings 使用方式见 `openclaw/docs/concepts/multi-agent.md:72-84`。
- 每个 agent workspace 包含 `SOUL.md`、`AGENTS.md`、可选 `USER.md`，并有独立 `agentDir` 和 session store，见 `openclaw/docs/concepts/multi-agent.md:98-99`。
- channel/accountId/agentId/sessionKey 的术语定义见 `openclaw/docs/channels/channel-routing.md:14-23`。
- 路由优先级为 exact peer、parent peer、guild+roles、guild、team、account、channel、default，见 `openclaw/docs/channels/channel-routing.md:58-73`。
- broadcast groups 能让同一个 inbound peer 运行多个 agents，见 `openclaw/docs/channels/channel-routing.md:75-91`。
- Agent scope 解析 name/workspace/agentDir/model/skills/memory/heartbeat/identity/groupChat/subagents/sandbox/tools，见 `openclaw/src/agents/agent-scope.ts:129-159`。
- workspace fallback 和 agentDir fallback 逻辑见 `openclaw/src/agents/agent-scope.ts:271-292`、`openclaw/src/agents/agent-scope.ts:350-362`。
- route resolver 归一化 channel/account/peer/team 并生成 sessionKey/mainSessionKey，见 `openclaw/src/routing/resolve-route.ts:631-708`。
- route tiers 和谓词见 `openclaw/src/routing/resolve-route.ts:743-830`。
- main session key、direct/group/thread session key 构造见 `openclaw/src/routing/session-key.ts:118-174`、`openclaw/src/routing/session-key.ts:234-253`。

架构图：

```text
OpenClaw runtime
  |
  +-- Gateway server / Control RPC
  |     |
  |     +-- agents.* / agents.files.* / tools.catalog / skills.*
  |
  +-- ChannelManager
  |     |
  |     +-- Telegram / Discord / Slack / WhatsApp / extension channels
  |           |
  |           +-- inbound event
  |
  +-- Route resolver
  |     |
  |     +-- bindings: channel/account/peer/thread/team/roles -> agentId
  |     +-- deterministic priority: peer > parent > guild+roles > guild > team > account > channel > default
  |     +-- session key: agent:<agentId>:...
  |
  +-- Agent scope
        |
        +-- workspace: ~/.openclaw/workspace or ~/.openclaw/workspace-<agentId>
        +-- agentDir:  ~/.openclaw/agents/<agentId>/agent
        +-- sessions:  ~/.openclaw/agents/<agentId>/sessions
        +-- auth-profiles.json / models / skills allowlist / tools policy
```

### 3.2 OpenClaw-Lark 飞书插件架构

源码事实：

- OpenClaw-Lark README 标明它连接 OpenClaw Agent 到飞书 workspace，覆盖 message/docs/base/sheets/calendar/tasks 等能力，见 `openclaw-lark/README.md:9-28`。
- Feishu channel plugin 能力包括 direct/group、media、reactions、threads、native commands、block streaming，见 `openclaw-lark/src/channel/plugin.ts:78-126`。
- account config 包含 appId/appSecret/domain/connectionMode/webhook/history/replyMode/streaming/footer/dedup/reaction/threadSession/uat 等，见 `openclaw-lark/src/core/config-schema.ts:157-201`。
- Gateway startAccount 从 account config 取 webhook port、connectionMode 并启动 monitor，见 `openclaw-lark/src/channel/plugin.ts:318-338`。这说明 OpenClaw-Lark 依赖已配置的飞书 app/account，不是运行时自动创建飞书开放平台 app。
- event handler 做 app_id 归属校验、自回声过滤、dedup、stale 丢弃、abort fast-path、queue，见 `openclaw-lark/src/channel/event-handlers.ts:49-167`。
- inbound dispatch context 解析 accountId、peer、thread 并进入 OpenClaw route/session，见 `openclaw-lark/src/messaging/inbound/dispatch-context.ts:102-201`。
- tool client 统一处理 UAT/TAT、app scope、offline_access、owner fallback、invokeAsUser，见 `openclaw-lark/src/core/tool-client.ts:139-250`。
- auto-auth 对 UserAuthRequired、UserScopeInsufficient、AppScopeMissing 做工具层自动授权和 scope 合并，见 `openclaw-lark/src/tools/auto-auth.ts:1-245`。
- tool action enum 标注 96 个工具动作，见 `openclaw-lark/src/core/tool-scopes.ts:57-167`。
- OAPI 注册覆盖 common/user、chat、IM、calendar、task、bitable、search、drive、wiki、sheets、bot IM 等，见 `openclaw-lark/src/tools/oapi/index.ts:46-94`。
- StreamingCardController 管理 idle/create/stream/completed/aborted/terminated 生命周期，见 `openclaw-lark/src/card/streaming-card-controller.ts:1-11`。
- StreamingCardController 有 CardKit state、flush、guard、image resolver、reasoning、toolUse、footer metrics，见 `openclaw-lark/src/card/streaming-card-controller.ts:83-185`。

架构图：

```text
OpenClaw-Lark plugin
  |
  +-- Channel plugin: feishu/lark
  |     |
  |     +-- configured account: appId/appSecret/domain/webhook/long_connect/groups/threadSession/uat
  |     +-- capabilities: direct/group/media/reactions/threads/nativeCommands/blockStreaming
  |
  +-- Event handlers
  |     |
  |     +-- app_id ownership / stale / dedup / self echo
  |     +-- message / reaction / card action / drive comment / membership / rich events
  |     +-- queue and abort fast-path
  |
  +-- Dispatch context
  |     |
  |     +-- accountId + peer + thread -> OpenClaw route/session
  |
  +-- Tool client + OAPI registry
  |     |
  |     +-- 108 action keys in current OpenClaw-Lark source
  |     +-- UAT/TAT decision
  |     +-- app scope / user scope / offline_access / auto-auth cards
  |
  +-- CardKit streaming reply
        |
        +-- create / patch / finalize / abort / fallback
        +-- reasoning / tool-use / footer metrics / image resolver / flush guard
```

## 4. Metis 当前 AgentTeam 架构事实

### 4.1 核心 AgentTeam 架构

源码事实：

- `docs/user/agent-team.md:1-11` 定义 Metis AgentTeam：一个 Gateway runtime 管理多个 named agents，隔离 workspace/model/session；默认产品语义为 deterministic routing + optional fan-out，manager delegation 尚不是独立 runtime。
- `docs/user/agent-team.md:48-57` 明确 CLI、Telegram、Feishu、Control UI 四类用户入口。
- `docs/user/agent-team.md:125-153` 说明 Control UI 的 Teams 页面是 Gateway RPC client，支持 team wizard、members、aliases、broadcast、bindings、workspace profiles、model state、Feishu readiness/doctor。
- `docs/user/agent-team.md:155-228` 说明每个 managed agent 有独立 workspace、`agentDir`、sessions、`models.json`、`auth-profiles.json` 和 8 个 profile 文件。
- `docs/user/agent-team.md:230-258` 说明 Telegram/Feishu account binding 和 team aliases。
- `docs/user/agent-team.md:271-312` 说明 Feishu 需要用户先创建 app/bot，Metis 提供 setup guidance、status、OAuth、diagnostics，不承诺非交互创建飞书 bot/app。
- `src/core/config/metis_agent_scope.cj:952-1080` 解析 agentId、workspaceDir、agentDir、modelsJsonPath、authProfilesPath、legacyAuthPath、sessionsDir、modelRef、skills/tools/identity/subagents/memory/sandbox。
- `src/core/config/metis_agent_scope.cj:1083-1134` 提供 auth profile diagnostics，并要求显式复制凭证。
- `src/core/prompting/metis_workspace_bootstrap.cj:8-20` 定义 profile 文件和 `BOOTSTRAP.md` 不自动创建。
- `src/core/prompting/metis_workspace_bootstrap.cj:178-200` 定义 auto-created 文件和 supported profile 文件列表。
- `src/gateway/runtime/gateway_server_methods_agents.cj:1886-2177` 支持 template members、member agent 创建、binding preflight、binding conflict 检查、team create。
- `src/gateway/runtime/gateway_server_methods_agents.cj:3151-3235` 注册 `agents.files.*`、`agents.models.*`、`agents.teams.*` RPC。
- `src/gateway/core/gateway_agent_route_resolver.cj:436-545` 实现 route binding 匹配和优先级。
- `src/gateway/core/gateway_agent_route_resolver.cj:547-632` 实现 session key、main session、lastRoute policy 和 main DM owner guard。
- `src/gateway/core/gateway_agent_route_resolver.cj:759-865` 实现 binding apply 的 scope upgrade、冲突检测和更新。
- `src/gateway/core/gateway_agent_team_broadcast.cj:136-171` 从 `agentTeams.list` 和 legacy `teams` 读取团队和 broadcast member 列表。
- `src/gateway/core/gateway_agent_team_broadcast.cj:451-501` 生成多 agent broadcast turns。
- `src/gateway/core/gateway_agent_team_broadcast.cj:516-582` 聚合 per-agent status、deliveryError、answer、deliveredCount。

### 4.2 Feishu / OAPI / Card / UI

源码事实：

- Feishu adapter 处理 card action、reaction、drive comment、bot membership、VC、bitable、message 等事件入口，见 `src/gateway/channels/feishu/feishu_adapter.cj:589-693`。
- Feishu adapter 支持 text/post/image/file/audio/video/media/interactive/merge_forward/sticker/share_chat/share_user，并做 app_id 归属校验，见 `src/gateway/channels/feishu/feishu_adapter.cj:741-773`。
- bot membership 事件映射为 system event，见 `src/gateway/channels/feishu/feishu_adapter.cj:1112-1168`。
- Feishu native auth runner 注册 start/status/poll/complete/revoke/revokeOptions，见 `src/gateway/channels/feishu/feishu_auth.cj:523-549`。
- OAuth device flow start 使用 appId/appSecret/domain，并返回 redacted pending/authorized/missing credential 状态，见 `src/gateway/channels/feishu/feishu_auth.cj:551-616`。
- OAuth status 支持 pending/authorized/expired 和 expired token refresh，见 `src/gateway/channels/feishu/feishu_auth.cj:618-659`、`src/gateway/channels/feishu/feishu_auth.cj:847-899`。
- OAuth complete/revoke 和 server revoke option 见 `src/gateway/channels/feishu/feishu_auth.cj:731-827`。
- `FeishuOapiTokenProvider` 已抽象 `userAccessToken` 与 `tokenLookup`，见 `src/gateway/tools/gateway_feishu_oapi_client.cj:409-417`。
- 当前 native token provider 对 `tenant_access_token` 返回 `token_mode_unsupported`，见 `src/gateway/tools/gateway_feishu_oapi_client.cj:540-545`。
- OAPI client 返回 unsupported/app_scope_missing/token_mode_unsupported/auth_required/scope_missing/api_error 等结构化结果，见 `src/gateway/tools/gateway_feishu_oapi_client.cj:769-805`。
- action key 归一化已包含 `feishu_get_user.basic_batch` 和多类 action，见 `src/gateway/tools/gateway_feishu_oapi_client.cj:984-1018`。
- OAPI supported actions 和 required scopes 覆盖 chat、IM、docs、wiki、drive、search、calendar、task、sheets、bitable 等，见 `src/gateway/tools/gateway_feishu_oapi_client.cj:1020-1035`、`src/gateway/tools/gateway_feishu_oapi_client.cj:1296-1384`。
- OAPI toolset 默认通过 native client 调用，并允许测试 runner/client 注入，见 `src/gateway/tools/gateway_feishu_oapi_toolset.cj:61-95`。
- OAPI toolset 暴露 docs/wiki/drive/search/bitable/calendar/task/sheets/chat/user/IM/OAuth/bot image/ask-user-question 等，见 `src/gateway/tools/gateway_feishu_oapi_toolset.cj:110-336`。
- Feishu card live smoke 默认需要 opt-in，网络默认 disabled，见 `src/gateway/channels/feishu/feishu_cards.cj:148-173`。
- Metis `FeishuStreamingCardController` 支持 creating/streaming/terminated、fallback、throttled patch、flushPending、tool payload update，见 `src/gateway/channels/feishu/feishu_cards.cj:315-470`。
- Control UI 主导航有 `agents` tab，见 `ui/src/ui/navigation.ts:4-24`、`ui/src/ui/navigation.ts:47-67`。
- Agents 页面包含 `Teams` 子 tab，见 `ui/src/ui/views/agents.ts:29`、`ui/src/ui/views/agents.ts:393-420`。
- Teams 页面结构包含 workflow、wizard、teams list/editor、binding、workspace profile、model、Feishu settings、capabilities、Feishu Auth & Doctor、doctor，见 `ui/src/ui/views/agents-panel-teams.ts:86-132`。
- Workspace Profile UI 使用 8 个 profile 文件，见 `ui/src/ui/controllers/agent-teams.ts:123-132` 和 `ui/src/ui/views/agents-panel-teams.ts:807-890`。
- Model Editor 通过 Gateway 读写 per-agent `models.json`，见 `ui/src/ui/views/agents-panel-teams.ts:895-930`。
- Feishu Auth & Doctor 面板显示 status/doctor/OAPI 并提供 start/status/poll/complete/revoke 操作，见 `ui/src/ui/views/agents-panel-teams.ts:1205-1327`。
- `METIS_HOME` 支持测试隔离，见 `src/core/config/metis_paths.cj:7-23`。

架构图：

```text
Metis Gateway runtime
  |
  +-- Gateway RPC
  |     |
  |     +-- agents.* / agents.teams.* / agents.files.* / agents.models.*
  |     +-- channels.status / channels.feishu.auth.*
  |
  +-- Control UI
  |     |
  |     +-- top-level tab: Agents
  |     +-- sub-tab: Teams
  |     +-- team wizard / members / aliases / broadcast / bindings
  |     +-- workspace profile editor / model editor
  |     +-- Feishu Auth & Doctor / capabilities / setup guidance
  |
  +-- Channel adapters
  |     |
  |     +-- Telegram adapter
  |     +-- Feishu adapter
  |           |
  |           +-- webhook/long-connect event -> InboundMessage
  |           +-- message/reaction/card/drive/bot/vc/bitable rich events
  |
  +-- Route/session context
  |     |
  |     +-- channel/account/peer/thread/team/roles -> agentId
  |     +-- session key: agent:<agentId>:...
  |
  +-- Agent scope
  |     |
  |     +-- workspace: $METIS_HOME/workspaces/<agentId>
  |     +-- agentDir:  $METIS_HOME/agents/<agentId>/agent
  |     +-- sessions:  $METIS_HOME/agents/<agentId>/sessions
  |     +-- models.json / auth-profiles.json / supported profile files
  |
  +-- Feishu integrations
        |
        +-- OAuth lifecycle: start/status/poll/complete/revoke
        +-- OAPI native client and toolset
        +-- card controller / fallback / live smoke opt-in
```

## 5. 源码对比矩阵

| 能力项 | OpenClaw / OpenClaw-Lark 事实 | Metis 当前事实 | 状态 | 当前 GAP | 补齐任务 |
| --- | --- | --- | --- | --- | --- |
| Agent 隔离 | OpenClaw agent = workspace + agentDir + sessions，`multi-agent.md:10-18` | Metis scope 输出 workspaceDir/agentDir/sessionsDir，`metis_agent_scope.cj:952-1080` | aligned | 无核心 GAP | 保持 scope/路径回归测试 |
| per-agent auth | OpenClaw auth profile per-agent 且不自动共享，`multi-agent.md:20-37` | Metis auth diagnostics 要求显式复制，`metis_agent_scope.cj:1083-1134` | aligned | 无核心 GAP | UI 可继续增强“复制凭证需确认”提示 |
| `agents/` 目录 | OpenClaw `~/.openclaw/agents/<agentId>/agent` 和 sessions | Metis `$METIS_HOME/agents/<agentId>/agent` 和 sessions | aligned | 无核心 GAP | 文档/doctor 保持一致 |
| profile 文件 | OpenClaw 明确 `SOUL.md`、`AGENTS.md`、可选 `USER.md` | Metis backend 和 UI 均支持 8 个文件 | aligned | `BOOTSTRAP.md` 不自动创建是明确设计 | 验收 UI 下拉和 RPC list/get/set |
| per-agent model | OpenClaw agent entry 支持 `model`，`agent-scope.ts:142-145` | Metis `models.json`、`agents.models.*`、UI Model Editor | aligned | 真实 provider 凭证仍需用户配置 | 补 provider readiness live checklist |
| shared skills/tools | OpenClaw workspace + shared roots + allowlist | Metis 内置 tools/skills + profile/tool policy，UI capability 面板只读 | partial | 尚无 OpenClaw 式插件/skill marketplace 和 allowlist 编辑闭环 | 后续单独做 skill/tool catalog UI |
| binding apply | OpenClaw scope upgrade 和 deterministic binding | Metis route apply 支持 scope upgrade/conflict，`gateway_agent_route_resolver.cj:759-865` | aligned | 无核心 GAP | 增加更多 JSON binding CLI 示例 |
| `accountId` | OpenClaw account/default/account `*` 语义，`multi-agent.md:243-247` | Metis default account、preferredAccountId、scope upgrade | aligned | 无核心 GAP | 手工验收多账号绑定 |
| session key | OpenClaw `agent:<agentId>:...` | Metis direct/group session key 同构，`gateway_agent_route_resolver.cj:547-632` | aligned | Feishu thread live 仍待真实群验证 | 补 Feishu topic/thread live smoke |
| route priority | OpenClaw peer > parent > guild+roles > guild > team > account > channel > default | Metis 同优先级，另含 peer wildcard | aligned | peer wildcard 是 Metis 扩展，不突破架构 | 文档注明扩展语义 |
| team CRUD | OpenClaw agent wizard + config/bindings | Metis `agents.teams.*` + CLI + UI | aligned | 模板库较小 | 可补更多模板，但不是阻塞 |
| team broadcast | OpenClaw broadcast groups | Metis deterministic fan-out + aggregate | partial | 不是 autonomous manager runtime；失败聚合/耗时现在较基础 | 增强 per-agent elapsed/error/UI 展示 |
| Telegram AgentTeam | OpenClaw ChannelManager route binding | Metis Telegram 走统一 route/session；docs 标明第一优先级 | partial | 本轮未重新做真实 Telegram live 验收 | 放入手工验收和后续 live gate |
| Feishu account/group/thread | OpenClaw-Lark account config、group policy、threadSession | Metis Feishu accounts、route context、事件映射 | partial | 真实 thread-capable cache 和 group policy 诊断仍弱于 OpenClaw-Lark | 补 live group/thread diagnostic |
| Feishu OAuth/UAT | OpenClaw-Lark UAT/TAT/app scope/offline_access/auto-auth | Metis OAuth lifecycle 已有 start/status/poll/complete/revoke 和 refresh/revoke tests | partial | 自动 scope repair/card 合并、真实租户 UAT 验收不足 | 补 live OAuth runbook 和 auto-auth repair |
| TAT/app token | OpenClaw-Lark 可按 action 决策 user/tenant | Metis 本轮已增加 tenant/app token provider、tokenMode matrix 和 fake client tests | partial | 真实 tenant/app token 获取和 app scope repair 还需 live 验收 | 使用测试租户关闭 live token/scope 验收 |
| OAPI action parity | OpenClaw-Lark 当前源码 108 action enum 和 OAPI 注册 | Metis 已覆盖多域并含 `basic_batch`，本轮已生成自动 parity report | partial | 当前无 missing action；仍有 36 个 scope matrix partial 行和 live action 子集验收 | 按 report 关闭 scope-exact partial 行并做 live subset gate |
| media/resource | OpenClaw-Lark 支持 message history/resource/file/image 下载 | Metis 有 current-turn resource 和 media metadata/OAPI boundary | partial | historical resource fetch 和更多资源类型 live 仍不足 | 补 resource fixture/live opt-in |
| rich events | OpenClaw-Lark 覆盖 message/reaction/card/drive/membership 等 | Metis 覆盖 card/reaction/drive/bot membership/VC/bitable/message | partial | converter 宽度和真实事件夹具少于 OpenClaw-Lark | 建立事件 replay matrix |
| streaming card | OpenClaw-Lark CardKit state/flush/guard/image/footer metrics | Metis 本轮补齐 observable state、flush/unavailable detail 和 safe image resolver baseline | partial | CardKit 2 全量组件和真实 live card 矩阵仍不完全 | 继续补 CardKit parity 和 live smoke |
| Control UI 管理 | 飞书 Miaoda-like 页面可视化创建/管理团队/模型/插件/Bot/诊断 | Metis Agents -> Teams 有 setup/repair wizard、bindings、profiles、models、Feishu Auth & Doctor | partial | 不等价于完整 Miaoda 管理台；缺 plugin marketplace 和真实 bot/app live setup 闭环 | 基于 Gateway RPC 继续补 live setup/repair flow |
| 自动创建 Feishu Bot | OpenClaw-Lark 源码依赖已配置 account/appId/appSecret，未看到自动创建开放平台 app/bot | Metis 明确不自动创建 Feishu app/bot | not-applicable | 不能承诺“自动创建飞书开放平台 Bot” | 做配置向导、检查清单、回填配置，不做虚假自动化 |

## 6. 当前完成度量化

### 6.1 评分口径

- **源码/本地能力完成度**：是否有代码实现、RPC/UI/CLI 入口、fake/local 测试、路径隔离和 redaction 保护。
- **真实生产体验完成度**：是否经过真实 Telegram/Feishu account、真实飞书租户、真实 OAuth/OAPI/Card/event 的端到端验收。

### 6.2 源码/本地能力完成度：95/100

| 分类 | 分值 | 当前得分 | 依据 |
| --- | ---: | ---: | --- |
| Agent scope、workspace、agentDir、sessions 隔离 | 15 | 15 | `metis_agent_scope.cj`、workspace bootstrap、agents tests |
| 路由、`accountId`、binding apply、session key | 14 | 14 | `gateway_agent_route_resolver.cj` 对齐 OpenClaw priority 和 scope upgrade |
| Team CRUD、CLI/RPC/UI 管理 | 12 | 11.5 | `agents.teams.*`、Control UI Teams 已具备；模板库较小 |
| Telegram AgentTeam 路由 | 8 | 7.2 | 统一 route/session 已具备，live 本轮未重验 |
| Feishu event/account/thread baseline | 12 | 11.0 | rich events、replay samples、dedup/thread/media baseline 已增强，真实 thread/group policy 仍需 live |
| Feishu OAuth/OAPI local boundary | 15 | 14.0 | OAuth lifecycle、live smoke gate、OAPI 多域、TAT/app token provider 和 action report 已实现，auto-auth repair 仍需 live |
| Streaming card/local controller | 8 | 7.4 | create/patch/fallback/throttle/flush、observable state、image resolver baseline 已有，CardKit 全量仍不足 |
| Control UI Miaoda-like 基础体验 | 10 | 9.4 | Agents -> Teams、profiles/models/auth/doctor、setup/repair wizard 已有，plugin catalog 和真实 bot/app setup 仍缺 |
| 文档、doctor、验证门禁 | 6 | 6.0 | docs/runbook/manual acceptance gate/browser smoke helper 已有，live 结果待真实租户记录 |
| **合计** | **100** | **95.0** | 以本轮 Phase 0-9 合入后的源码和集成验证为基准 |

### 6.3 真实飞书生产体验完成度：84/100

扣分主要来自真实租户验收和 OpenClaw-Lark 深度功能：

- 未完成真实飞书 OAuth device flow 的 end-to-end 记录。
- 未完成真实 UAT refresh、server revoke、scope missing、app scope missing 的租户级验收。
- TAT/app token provider 已有 fake-tested runtime；真实租户 token/scope 行为仍需验收。
- OAPI 已自动生成当前 OpenClaw-Lark 108 action parity report；仍有 36 个 scope matrix partial 行和代表性 live action 子集验收未关闭。
- CardKit full lifecycle 和真实 card live 矩阵仍低于 OpenClaw-Lark。
- Miaoda-like 管理 UI 仍缺 plugin/skill catalog 和真实 bot/app live setup 闭环。

## 7. 当前真实 GAP 与补齐措施

### GAP 1：真实 OAuth/UAT 仍缺生产验收

源码依据：

- OpenClaw-Lark 的 tool client 处理 UAT/TAT、app scope、offline_access 和 owner fallback，见 `openclaw-lark/src/core/tool-client.ts:139-250`。
- Metis 已有 native auth lifecycle 和 redaction tests，见 `src/gateway/channels/feishu/feishu_auth.cj:523-659`、`src/gateway/runtime/gateway_server_methods_channels_test.cj:227-325`。

补齐措施：

- 增加 live opt-in runbook：使用测试飞书 app、测试租户、测试用户、测试群。
- 在 `METIS_FEISHU_LIVE_*` opt-in 下验证 start/status/poll/complete/refresh/revoke。
- 验收 OAuth 输出只包含 redacted 状态，不泄露 access token、refresh token、app secret、Authorization header。

验收项：

- `channels.feishu.auth.start` 返回 pending 或 authorized。
- `channels.feishu.auth.status` 能显示 tokenStatus、scopeSummary、scopeDiagnostic。
- token 过期时 refresh 成功或返回明确 missing credential diagnostic。
- revoke local 和 serverRevoke opt-in 都有清晰状态。

### GAP 2：TAT/app token provider 与 action tokenMode 决策不完整

源码依据：

- OpenClaw-Lark `invoke` 默认 user，可用 `{ as: "tenant" }` 切换 TAT，见 `openclaw-lark/src/core/tool-client.ts:199-231`。
- Metis `MetisFeishuOapiTokenProvider.tokenLookup` 对 `tenant_access_token` 返回 unsupported，见 `src/gateway/tools/gateway_feishu_oapi_client.cj:540-545`。

补齐措施：

- 增加 tenant/app token provider：从 Feishu appId/appSecret 换取 tenant_access_token/app_access_token。
- 在 action matrix 中标注每个 action 默认 UAT/TAT/app tokenMode。
- OAPI request builder 按 action 或显式参数选择 tokenMode。

验收项：

- TAT action 不再返回 `token_mode_unsupported`。
- 缺 app credential 时不发网络请求，返回 missing credential diagnostic。
- TAT token 不写入 workspace profile，不在日志/结果中泄露。

### GAP 3：OAPI 108 action parity 需要 scope-exact closure

源码依据：

- OpenClaw-Lark tool action enum 标注 96 个 action，见 `openclaw-lark/src/core/tool-scopes.ts:57-167`。
- Metis action key 和 scopes 在 `gateway_feishu_oapi_client.cj:984-1384`，toolset 在 `gateway_feishu_oapi_toolset.cj:110-336`。

补齐措施：

- 编写生成脚本读取 OpenClaw-Lark `ToolActionKey` 和 Metis `feishuOapiSupportedActionsForTool`。
- 输出 `develop_steps` parity matrix：aligned/partial/missing/not-applicable。
- 对 missing action 明确补 toolset/action/scopes/path/test。

验收项：

- parity report 可重复生成。
- `feishu_get_user.basic_batch`、IM、docs、wiki、drive、search、calendar、task、sheets、bitable 均在报告中有状态。
- 每个 missing/partial 都有文件级补齐任务。

### GAP 4：CardKit full lifecycle 仍未完全追平

源码依据：

- OpenClaw-Lark StreamingCardController 有显式 phase、CardKit state、flush、guard、image resolver 和 footer metrics，见 `openclaw-lark/src/card/streaming-card-controller.ts:1-185`。
- Metis `FeishuStreamingCardController` 已有 create/patch/fallback/throttle/flush/toolUse，但结构比 OpenClaw-Lark 简化，见 `src/gateway/channels/feishu/feishu_cards.cj:315-470`。

补齐措施：

- 增加 CardKit 2 状态字段、unavailable guard、image resolver、footer metrics。
- 对 create/patch/finalize/abort/fallback 做 fake client 测试和 live opt-in smoke。

验收项：

- 卡片生命周期状态可观测。
- patch 失败可 fallback，message unavailable 可终止并转文本。
- footer 包含 elapsed/tokens/cache/context/model 时不泄露敏感信息。

### GAP 5：rich events 需要真实事件矩阵验收

源码依据：

- OpenClaw-Lark event handler 覆盖 message/reaction/card action/drive comment 等，见 `openclaw-lark/src/channel/event-handlers.ts:71-185`。
- Metis Feishu adapter 已覆盖 card/reaction/drive/bot membership/VC/bitable/message，见 `src/gateway/channels/feishu/feishu_adapter.cj:589-693`。

补齐措施：

- 建立 redacted event fixture replay matrix。
- 每类事件都验收 accountId、peer、thread、messageId、systemEventKind、dedup。
- 真实飞书租户 opt-in 捕获 redacted fixtures。

验收项：

- fake replay 覆盖每类事件。
- unsupported event 返回 clear diagnostic 而不是 crash。
- 错 app_id 被忽略并记录 wrong_app。

### GAP 6：Miaoda-like 管理 UI 仍缺配置闭环

源码依据：

- Metis UI 已有 Agents -> Teams、workspace profiles、model editor、Feishu Auth & Doctor，见 `ui/src/ui/views/agents.ts:393-420`、`ui/src/ui/views/agents-panel-teams.ts:86-132`、`ui/src/ui/views/agents-panel-teams.ts:1205-1327`。
- OpenClaw-Lark 配置面包含 appId/appSecret/domain/connectionMode/groups/threadSession/uat 等复杂设置，见 `openclaw-lark/src/core/config-schema.ts:157-201`。

补齐措施：

- 在 Teams 页面增加 Feishu setup wizard：app credential checklist、event subscription checklist、group/thread policy checklist。
- 增加 scope repair view：展示 app/user missing scopes、生成飞书开放平台配置步骤。
- 增加 plugin/skill/tool catalog 只读到可编辑演进计划。

验收项：

- 用户能从 UI 找到 Agents -> Teams -> Feishu setup。
- UI 不直接写 token 文件；所有变更走 Gateway RPC。
- 所有 secret-like 文本都 redacted。

### GAP 7：不能承诺自动创建 Feishu app/bot

源码依据：

- OpenClaw-Lark account schema 需要 appId/appSecret，见 `openclaw-lark/src/core/config-schema.ts:157-201`。
- OpenClaw-Lark startAccount 使用已配置 account，见 `openclaw-lark/src/channel/plugin.ts:318-338`。
- Metis 文档明确需要用户在飞书开发者后台创建 app/bot，见 `docs/user/agent-team.md:271-287`。

补齐措施：

- 不实现“自动创建飞书开放平台 app/bot”的伪自动化。
- 实现“配置向导 + 检查清单 + 配置回填 + 诊断修复建议”。

验收项：

- 文档和 UI 文案不出现“自动创建 Feishu bot/app”的承诺。
- UI 能指导用户填 appId/appSecret/domain/webhook/event subscriptions/scopes。

## 8. 分阶段补齐计划

### Phase 0：证据与验收基线冻结

目标：让所有后续实现都从同一份 source-backed GAP 出发。

工作项：

- 将本 series13 文档作为新的基线。
- 更新 `docs/user/agent-team.md` 中过期的 Feishu partial 表述，避免与 series12 后代码矛盾。
- 增加 live opt-in 约束说明：默认不访问真实 Telegram/Feishu/模型网络。

验收项：

- 文档能指出 series12 基线 `0f93f80` 后 UI 已有 8 profile 文件和 OAuth lifecycle 按钮。
- `rg -n "Auth status RPC missing|只 start|4 个文件|自动创建 Feishu" docs/user develop_steps` 不出现误导性旧结论。

工作量：0.5 人日。

### Phase 1：Feishu live OAuth/UAT 验收门禁

目标：把 fake-tested OAuth lifecycle 推进到真实飞书测试账号可验收。

工作项：

- 增加 `METIS_FEISHU_LIVE_AUTH_SMOKE=1` 风格 opt-in。
- 记录 start/status/poll/complete/refresh/revoke runbook。
- 输出 redacted JSON fixture 到临时目录，默认不写真实用户文件。

验收项：

- 无 opt-in 时 live 测试跳过。
- 有 opt-in 且配置完整时，device flow 能完成并写入测试 `METIS_HOME` token store。
- 结果和日志不包含 token、secret、Authorization header。

工作量：1 人日。

### Phase 2：TAT/app token provider 与 tokenMode matrix

目标：补齐 OpenClaw-Lark 的 UAT/TAT 决策基础。

工作项：

- 实现 tenant/app token 获取、缓存、过期刷新。
- 为每个 action 标注默认 tokenMode。
- 保持 `user_access_token` 兼容，未知 tokenMode 返回 clear diagnostic。

验收项：

- TAT action 不返回 `token_mode_unsupported`。
- 缺 app credential 时返回 missing credential 且不发网络请求。
- fake HTTP 测试覆盖成功、过期、失败、redaction。

工作量：1.5-2 人日。

### Phase 3：OAPI 108 action parity 自动报告

目标：避免人工漏项。

工作项：

- 生成 OpenClaw-Lark 当前源码 108 action 列表。
- 生成 Metis supported action 列表。
- 输出 parity matrix 到 `develop_steps`。
- 对缺失 action 补 tool method、request path、required scopes、fake tests。

验收项：

- 报告可重复生成。
- 每个 action 状态为 aligned/partial/missing/not-applicable。
- 新增 action 均有 unit test，不访问真实飞书网络。

工作量：1-2 人日。

### Phase 4：CardKit streaming parity

目标：补齐 streaming card 的状态机和 fallback 韧性。

工作项：

- 增加 CardKit state、footer metrics、unavailable guard、image resolver。
- 对 create/patch/finalize/abort/fallback 建 fake client 测试。
- 增加 live opt-in smoke checklist。

验收项：

- fake tests 覆盖每个 lifecycle phase。
- patch/finalize 失败有明确 fallback。
- live smoke 默认 disabled，需要显式环境变量。

工作量：1.5-2.5 人日。

### Phase 5：Rich event matrix 和资源验收

目标：使 Feishu events/resources 从“已有 baseline”提升为“可审计矩阵”。

工作项：

- 建立 message/reaction/card/drive/bot/vc/bitable/media event fixtures。
- 对每个 fixture 验证 accountId、peer、thread、systemEventKind、dedup。
- 补 historical resource fetch 或明确 not-applicable。

验收项：

- 每类事件都有 fake replay test。
- malformed/unsupported/wrong_app 都返回 clear diagnostic。
- live fixture 捕获必须 redacted。

工作量：1-1.5 人日。

### Phase 6：Control UI Feishu setup/repair wizard

目标：把 Miaoda-like 管理体验从“面板可见”推进到“配置闭环”。

工作项：

- 在 Agents -> Teams 增加 Feishu setup wizard。
- 展示 app credential、event subscription、scope、group/thread、OAuth、OAPI、card readiness。
- 增加 scope repair hints 和 copyable steps。

验收项：

- UI 可从 Agents -> Teams 进入。
- 无 Feishu 配置时显示缺什么、到哪里配置、如何验证。
- 所有操作走 Gateway RPC，不直接写 token/local files。
- Browser smoke 无 console error、无 failed JS/CSS。

工作量：2-3 人日。

### Phase 7：Team collaboration UX 与 manager 语义

目标：明确 deterministic routing、fan-out、manager-as-member 三种语义，避免误解为 autonomous manager runtime。

工作项：

- UI/CLI/docs 展示 team semantics。
- broadcast aggregate 增加 per-agent elapsed/error/detail。
- manager agent 模板和 profile 示例。

验收项：

- 用户能看出普通路由只进一个 agent。
- broadcast 显示每个 member 的结果。
- manager 不是独立 runtime 的限制被清晰说明。

工作量：1 人日。

### Phase 8：端到端文档与浏览器验收自动化

目标：把用户可操作步骤固化到 docs 和 browser smoke。

工作项：

- 更新 `docs/user/agent-team.md`。
- 增加 Control UI Agents -> Teams browser smoke。
- 增加 CLI/RPC runbook。

验收项：

- `npm --prefix ui run build` 后 built assets 可打开。
- `customElements.get("metis-app")` 注册。
- Agents -> Teams 可见，profile 下拉 8 项，Feishu auth 按钮可见。

工作量：1 人日。

### Phase 9：真实 IM 手工验收与发布门禁

目标：形成用户可执行验收结果。

工作项：

- 用测试 `METIS_HOME` 和测试账号执行本文件第 9 章手工验收。
- 记录通过/失败/跳过原因。
- 修复 blocker 后再提交。

验收项：

- CLI、Control UI、Telegram、Feishu 至少各通过核心路径。
- 真实 live 步骤必须注明账号、租户、日期、scope、跳过项。
- 提交前运行 `cjpm clean && cjpm build -i && cjpm test` 和 UI/browser smoke。

工作量：0.5-1 人日。

## 9. 手工验收列表

### 9.1 验收前准备

建议使用测试 home，避免误改真实 `~/.metis`：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
```

启动 Gateway：

```bash
cjpm run --skip-build --name metis --run-args "gateway run"
```

另开一个 shell：

```bash
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
metis gateway status
metis gateway health
```

真实 Telegram/Feishu 验收需要测试 bot/app/群/用户，不建议直接使用生产群。

### 9.2 手工验收条目

| 编号 | 手工验收条目 | 验收操作方法 | 验收标准 |
| --- | --- | --- | --- |
| M01 | CLI 可创建 team | 执行 `metis agents team create --team manual --name "Manual Team" --template pm-writer-reviewer`，再执行 `metis agents team get --team manual` | 返回成功；能看到 `manual-pm`、`manual-writer`、`manual-reviewer`；每个 agent 有独立 workspace、agentDir、sessionsDir |
| M02 | CLI 可列出 team | 执行 `metis agents team list` | 列表包含 `manual`；semantics 显示 deterministic routing / fan-out / manager-as-member 语义 |
| M03 | profile 文件隔离 | 执行 `metis gateway call agents.files.list '{"agentId":"manual-writer"}'` | 返回 8 个 profile 文件；`BOOTSTRAP.md` 可显示 missing；其他 auto-created 文件存在 |
| M04 | profile 文件可编辑 | 执行 `metis gateway call agents.files.set '{"agentId":"manual-writer","name":"SOUL.md","content":"# Soul\n\nManual writer acceptance.\n"}'`，再 get | get 返回内容包含 `Manual writer acceptance`；不影响 `manual-reviewer` 的 `SOUL.md` |
| M05 | per-agent model 可编辑 | 执行 `metis gateway call agents.models.set '{"agentId":"manual-writer","state":{"primaryModelRef":"openai:gpt-4o-mini","runtimePrimaryModelRef":"openai:gpt-4o-mini","providers":[]}}'`，再 `agents.models.get` | `manual-writer` 返回对应 modelRef；`manual-reviewer` 不被改动 |
| M06 | binding apply 无部分写 | 给 `manual-writer` 和 `manual-reviewer` 申请同一个 `telegram:test-bot` binding | 第二次冲突应返回错误；配置不出现半写入 |
| M07 | channel/account binding 生效 | 执行 `metis agents bind --agent manual-writer --bind telegram:test-bot`，再 `metis agents bindings --agent manual-writer` | 能看到 telegram/test-bot route binding，accountId 语义正确 |
| M08 | structured binding 可用 | 执行 `metis gateway call agents.teams.update`，传入 `bindings` 中含 `{"type":"route","agentId":"manual-writer","match":{"channel":"telegram","accountId":"test-bot","peer":{"kind":"group","id":"-100xxx"}}}` | update 成功；route binding match 中保留 peer kind/id |
| M09 | broadcast 可配置 | 执行 `metis gateway call agents.teams.update '{"id":"manual","broadcast":{"enabled":true,"members":["manual-writer","manual-reviewer"]}}'` | team get 显示 broadcast enabled，members 只包含合法 member |
| M10 | broadcast 结果聚合 | 对已绑定 peer 发一条能触发 team broadcast 的消息，或通过已有 fake/runtime trigger 触发 | 聚合结果包含每个 agent 的 agentId、status、delivered、answer/error；任何失败显示 partial/failed 而不是吞掉 |
| M11 | Control UI Agents tab 可见 | 打开 Gateway Control UI，进入左侧主导航 `Agents` | 页面不空白；没有浏览器 console error；顶部/侧边能看到 Agents |
| M12 | Control UI Teams 子页可见 | 在 Agents 页面点击 `Teams` 子 tab | 能看到 workflow、team wizard、team list/editor、binding、workspace profile、model、Feishu panels |
| M13 | Control UI 创建 team | 在 Teams wizard 选择 `PM / Writer / Reviewer`，填写 team id `ui-manual`，点击创建 | 成功提示；列表出现 `ui-manual`；详情有三名成员 |
| M14 | Control UI workspace profile 下拉 | 在 Workspace Profiles 选择 `ui-manual-writer` | Profile file 下拉包含 8 项：`AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md` |
| M15 | Control UI 保存 profile | 选择 `SOUL.md`，输入测试文本，点击 Save，再 Load | Load 后内容保持；保存通过 Gateway RPC；浏览器不直接写本地文件 |
| M16 | Control UI per-agent model | 在 Model Editor 选择 `ui-manual-writer`，填写 primary model ref，保存后重新 load | 只更新选中 agent；credential summary redacted |
| M17 | Control UI Feishu Auth 按钮 | 打开 Feishu Auth & Doctor 面板 | 能看到 Start OAuth via Gateway、Status、Poll、Complete、Revoke local auth；缺配置时有 clear diagnostic |
| M18 | Control UI secret redaction | 在 Feishu auth fake/error 路径或缺配置路径查看 UI 输出 | UI 中不出现 accessToken、refreshToken、appSecret、Authorization header |
| M19 | Telegram 单 agent 路由 | 使用测试 Telegram bot 向已绑定账号发送消息 | Gateway 日志出现 `channel=telegram` inbound；回复来自绑定 agent；sessionKey 形如 `agent:manual-writer:...` |
| M20 | Telegram alias 路由 | 在已配置 team alias 后，在群里发送 `@writer 请回复你的 agentId` | 路由到 writer；没有裸露内部 main/main 之类不可读标签 |
| M21 | Telegram topic/thread 隔离 | 在 Telegram forum topic 或 group peer 中发送两条不同 topic 消息 | sessionKey 按 topic/thread 隔离；两个 topic 的上下文不混 |
| M22 | Feishu 配置缺失诊断 | 在没有 appId/appSecret 的测试 `METIS_HOME` 中点击 Status/Start OAuth | 返回 `missing_app_credentials` 或等价 clear diagnostic；不抛异常、不泄露 secret |
| M23 | Feishu OAuth device flow | 使用测试飞书 app 配置 appId/appSecret/domain 后点击 Start OAuth，按 URL/userCode 完成授权，再点 Poll/Complete | 状态从 pending 到 authorized；tokenStatus authorized；scopeSummary 可见；结果 redacted |
| M24 | Feishu revoke local auth | 完成 M23 后点击 Revoke local auth，再点 Status | 本地 token 被移除；status/tokenStatus 变为 missing/revoked；server revoke 未请求时显示 not_requested |
| M25 | Feishu message route | 将测试飞书 bot 加入测试群，配置 event subscription 和 binding，发送一条 @bot 消息 | Gateway 收到 Feishu inbound；路由到绑定 agent；回复发回原飞书会话 |
| M26 | Feishu thread session | 在支持 thread/topic 的飞书群里发送 thread 消息 | sessionKey 包含 thread 或能看到 thread diagnostics；不同 thread 不串上下文 |
| M27 | Feishu rich reaction event | 对测试消息添加/删除 reaction | Gateway 映射为 reaction/system event 或 clear accepted diagnostic；重复事件被 dedup |
| M28 | Feishu card action event | 触发一张测试 interactive card 的按钮 | Gateway 映射 card action；能进入 route/session 或返回 clear diagnostic |
| M29 | Feishu drive comment event | 在测试文档评论触发已订阅事件 | Gateway 映射 drive comment system event；包含 accountId、comment target、messageId |
| M30 | Feishu bot membership event | 将 bot 加入/移出测试群 | Gateway 映射 `feishu.bot_membership`；不会进入错误循环 |
| M31 | Feishu OAPI auth_required | 未授权时让 agent 调用 `feishu_get_user` 或用 tool debug 调用 | 返回结构化 `auth_required`，包含 required scopes，不泄露 token |
| M32 | Feishu OAPI basic_batch | 授权后调用 `feishu_get_user` 的 `basic_batch` action | 不返回 unsupported；成功或返回 scope_missing/app_scope_missing 的结构化诊断 |
| M33 | Feishu TAT action 现状确认 | 调用需要 `tenant_access_token` 的代表 action | 当前允许返回 `token_mode_unsupported`；这是 GAP 2 的预期未完成项，不能当作发布完成 |
| M34 | Feishu card fallback | 在 fake/live opt-in 环境模拟 card patch 失败或 message unavailable | 控制器 fallback 为文本或终止；不 crash；diagnostic 清晰 |
| M35 | 日志安全 | 完成所有 live 步骤后检查 Gateway 日志 | 日志不包含 bot token、access token、refresh token、app secret、Authorization header |
| M36 | 清理测试配置 | 执行 `metis agents team delete --team manual`、`metis agents team delete --team ui-manual`，撤销测试 binding，删除测试 `METIS_HOME` | 测试 team 不再出现；真实 `~/.metis` 未被修改，除非测试前明确使用了真实 home |

### 9.3 手工验收结果记录模板

```text
验收日期：
Metis commit：
METIS_HOME：
Gateway 启动命令：
Telegram 测试 bot/account：
Feishu 测试 app/account/tenant：
已授权 scopes：

通过项：
失败项：
跳过项与原因：
日志安全检查结果：
截图/日志位置：
```

## 10. 后续建议

第一优先级应按真实缺口推进：

1. 先补 live OAuth/UAT 验收门禁，确认真实飞书测试租户能跑通授权。
2. 再按自动 parity report 关闭 TAT/app token 和 scope-exact OAPI partial 行。
3. 然后补 CardKit streaming parity、rich event matrix 和 UI setup/repair wizard。

不要再把“自动创建飞书 bot/app”作为目标。OpenClaw-Lark 源码本身也是基于已配置 app/account 启动，Metis 应该提供配置向导、诊断和回填，而不是突破飞书开放平台管理边界。
