# Metis AgentTeam 系列 12：源码复核、历史进展、当前 GAP、量化完成度与补齐计划

## 1. 本轮结论

本轮基于公开网页、OpenClaw 核心源码、OpenClaw-Lark 源码、Metis 当前主工作区源码、历史系列文档和最近补齐提交重新复核 AgentTeam 功能。

结论分两层：

- **核心 AgentTeam 架构层**：Metis 已基本对齐 OpenClaw 的多 Agent 隔离、`agentDir`、workspace、session、per-agent model、per-agent auth profile、binding apply、`accountId`、路由优先级和 Gateway RPC 管理模型。源码/本地假数据可验证完成度约 **84/100**。
- **飞书 Claw 生产体验层**：Metis 已有 Feishu auth lifecycle、OAPI client/toolset、rich events、card controller、Control UI Teams 页面和 doctor 面板基础，但距离飞书团队基于 OpenClaw-Lark 的真实 OAuth/UAT/OAPI/CardKit/Miaoda-like 管理体验还有差距。真实生产等价完成度约 **72/100**。

后续工作量估算：

- 达到“本地/假数据路径 90 分以上”：约 **4-6 人日**。
- 达到“真实飞书租户生产可用 90 分以上”：约 **8-12 人日**，前提是提供可测试的飞书应用、租户、测试用户、测试群、必要事件订阅和 scope。
- 若要求完整追平 OpenClaw-Lark 所有 OAPI 动作、CardKit 细节、事件转换器和飞书线上异常矩阵：约 **12-16 人日**。

## 2. 信息来源与约束

### 2.1 网页来源

- 飞书 OpenClaw 智能体团队介绍页：`https://www.feishu.cn/content/article/7613711414611463386`
- 飞书 OpenClaw-Lark/插件能力介绍页：`https://www.feishu.cn/content/article/7629286303804329160`

网页侧能确认的产品方向是：飞书团队将 OpenClaw 能力产品化为智能体团队、飞书 Bot/插件、用户授权、飞书文档/多维表格/日历/任务/OAPI、流式卡片和可视化管理体验。

### 2.2 本轮源码复核边界

本轮结论只基于 AgentTeam、Channel Routing、Feishu/Lark、Gateway RPC、Control UI Teams、OAuth/OAPI/Card 相关执行路径。与 AgentTeam 无关的 OpenClaw provider、模型接入、无关测试夹具、构建脚本不作为 GAP 判断依据。

不使用“文件名推断”或“函数名推断”作为结论。每个 GAP 都要求能落到源码或历史文档证据。

### 2.3 历史进展纳入

本轮纳入以下历史文档和补齐进展：

- `develop_steps/metis-agent-team-series-08-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-09-prioritized-implementation-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-10-feishu-openclaw-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`
- `develop_steps/metis-agent-team-series-11-post-phase0-9-source-recheck-gap-quantification-and-landing-plan-2026-05-14.md`

当前主工作区最新进展：

```text
610884d Regenerate control UI assets after AgentTeam wizard build
1415564 AgentTeam phases0-9 docs e2e runbook
b4fe5be AgentTeam phases7-8 team wizard doctor ux
2f25b1e AgentTeam phase1 feishu auth lifecycle
81c48a3 AgentTeam phases5-6 feishu cards events
a29f9cb AgentTeam phases2-4 feishu oapi scope matrix
f105bf7 Complete AgentTeam Feishu OpenClaw parity phases
2cdc7fc Regenerate AgentTeam control UI assets
e6166ef Enhance AgentTeam UI workflow
2923872 Add Feishu events cards parity hooks
dbcd35b Close Feishu media resource boundary
b0bed11 Add Feishu OAuth OAPI runtime
```

系列 11 的 `74% live parity` 结论已部分过期，因为后续提交补齐了 auth lifecycle、OAPI matrix、cards/events、team wizard/doctor 和 docs e2e runbook。本轮重新量化为 `84/100 local`、`72/100 live`。

## 3. OpenClaw / OpenClaw-Lark 架构事实

### 3.1 OpenClaw 核心 AgentTeam 架构

源码证据：

- `openclaw/docs/concepts/multi-agent.md:10-18`：一个 Agent 是独立 workspace、`agentDir`、sessions。
- `openclaw/docs/concepts/multi-agent.md:20-37`：auth profiles 是 per-agent，主 Agent 凭证不会自动共享。
- `openclaw/docs/concepts/multi-agent.md:39-44`：技能来自 agent workspace 和共享 roots，再由 allowlist 过滤。
- `openclaw/docs/concepts/multi-agent.md:53-68`：默认路径、`agent:main:main` session key、`~/.openclaw/agents/<agentId>/agent`。
- `openclaw/docs/concepts/multi-agent.md:72-84`：通过 agent wizard 添加 agent，随后配置 bindings。
- `openclaw/docs/concepts/multi-agent.md:98-99`：每个 agent 有自己的 `SOUL.md`、`AGENTS.md`、可选 `USER.md`、`agentDir`、session store。
- `openclaw/docs/channels/channel-routing.md:10-23`：channel/accountId/agentId/sessionKey 的术语定义。
- `openclaw/docs/channels/channel-routing.md:58-73`：路由优先级为 peer、parent peer、guild+roles、guild、team、account、channel、default。
- `openclaw/docs/channels/channel-routing.md:75-91`：broadcast groups 能让一个 inbound peer 跑多个 agents。
- `openclaw/src/agents/agent-scope.ts:129-159`：解析 per-agent workspace、agentDir、model、skills、memorySearch、heartbeat、identity、groupChat、subagents、sandbox、tools。

架构图：

```text
OpenClaw runtime
  |
  +-- Gateway server / Control RPC
  |     |
  |     +-- agents.* RPC / agents.files.* / tools.catalog / skills.*
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
  |     +-- session key: agent:<agentId>:...
  |
  +-- Agent scope
        |
        +-- workspace: ~/.openclaw/workspace-<agentId>
        +-- agentDir:  ~/.openclaw/agents/<agentId>/agent
        +-- sessions:  ~/.openclaw/agents/<agentId>/sessions
        +-- auth-profiles.json / models / skills allowlist
```

### 3.2 OpenClaw-Lark 飞书插件架构

源码证据：

- `openclaw-lark/README.md:9-28`：官方 Feishu/Lark 插件连接飞书 workspace，支持消息、docs、base、sheets、calendar、tasks、interactive cards、streaming responses、permission policies、group config。
- `openclaw-lark/src/channel/plugin.ts:78-126`：Feishu channel plugin 能力包括 direct/group、media、reactions、threads、nativeCommands、blockStreaming。
- `openclaw-lark/src/core/config-schema.ts:141-201`：group policy、requireMention、tools、skills、allowFrom、systemPrompt、connectionMode、webhook、history、replyMode、streaming、footer、dedup、reactionNotifications、threadSession、uat 等配置。
- `openclaw-lark/src/channel/event-handlers.ts:49-167`：事件 app_id 归属校验、message handler、自回声过滤、dedup、abort fast-path、queue。
- `openclaw-lark/src/messaging/inbound/dispatch-context.ts:102-201`：Feishu inbound 解析 channel/accountId/peer/thread 并进入 route/session。
- `openclaw-lark/src/core/tool-client.ts:139-250`：工具调用统一入口，处理 UAT/TAT、app scope、offline_access、owner fallback、invokeAsUser。
- `openclaw-lark/src/tools/auto-auth.ts:1-245`：自动处理 UserAuthRequired、UserScopeInsufficient、AppScopeMissing，并按 user/app 维度合并授权请求。
- `openclaw-lark/src/core/tool-scopes.ts:57-167`：枚举 96 个 Feishu tool action。
- `openclaw-lark/src/tools/oapi/index.ts:46-94`：注册 common/user、chat、IM、calendar、task、bitable、search、drive、wiki、sheets、bot IM 等 OAPI tools。
- `openclaw-lark/src/card/streaming-card-controller.ts:1-11`：CardKit card lifecycle 为 idle、creating、streaming、completed、aborted、terminated。
- `openclaw-lark/src/card/streaming-card-controller.ts:83-129`：流式卡片有明确状态机、CardKit state、reasoning、toolUse、flush、guard、image resolver。
- `openclaw-lark/src/card/streaming-card-controller.ts:139-178`：footer session metrics 会读取 tokens/cache/context/model。

架构图：

```text
OpenClaw-Lark plugin
  |
  +-- Channel plugin: feishu / lark
  |     |
  |     +-- account config: appId/appSecret/domain/webhook/long_connect/groups/threadSession/uat
  |     +-- capabilities: direct, group, media, reactions, threads, native commands, block streaming
  |
  +-- Feishu event handlers
  |     |
  |     +-- app_id ownership / stale / dedup / self echo / abort command
  |     +-- message / reaction / card action / drive comment / membership / rich events
  |
  +-- Dispatch context
  |     |
  |     +-- accountId + peer + thread -> OpenClaw route/session
  |
  +-- Tool client + OAPI tools
  |     |
  |     +-- 96 tool actions
  |     +-- UAT/TAT decision
  |     +-- app scope / user scope / offline_access / auto auth
  |
  +-- CardKit streaming reply
        |
        +-- create / patch / finalize / abort / fallback
        +-- reasoning / tool-use / footer metrics / image resolver / flush guard
```

## 4. Metis 当前 AgentTeam 架构事实

源码证据：

- `docs/user/agent-team.md:1-6`：AgentTeam 让一个 Gateway runtime 管理多个 named agents，路由 IM accounts，隔离 workspace/model/session，Telegram 和 Feishu 是第一优先级 IM。
- `docs/user/agent-team.md:7-12`：当前产品语义是确定性 Gateway routing 和可选 fan-out；manager delegation 尚不是独立产品化 runtime。
- `docs/user/agent-team.md:15-25`：能力矩阵说明 agent isolation、team management、route bindings、broadcast、workspace profiles、model state、Telegram、Feishu、migration。
- `src/core/config/metis_agent_scope.cj:952-1080`：Metis Agent Scope 解析 agentId、workspaceDir、agentDir、modelsJsonPath、authProfilesPath、legacyAuthPath、sessionsDir、modelRef、policies、identity、groupChat、subagents、memorySearch、sandbox。
- `src/core/config/metis_agent_scope.cj:1083-1134`：auth profile 诊断和显式复制语义。
- `src/core/prompting/metis_workspace_bootstrap.cj:8-20`：支持 `AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md`；`BOOTSTRAP.md` 不自动创建。
- `src/core/prompting/metis_workspace_bootstrap.cj:178-200`：自动创建 profile 文件列表和支持读取/写入的 profile 文件列表。
- `src/gateway/runtime/gateway_server_methods_agents.cj:1886-2162`：Team 模板、成员 agent 创建、binding 预检、冲突处理、team create。
- `src/gateway/runtime/gateway_server_methods_agents.cj:2165-2278`：team update/delete。
- `src/gateway/runtime/gateway_server_methods_agents.cj:3151-3230`：`agents.files.*`、`agents.models.*`、`agents.teams.*` RPC 注册。
- `src/gateway/core/gateway_agent_route_resolver.cj:436-545`：binding 匹配和优先级为 peer.exact、peer.parent、peer.wildcard、guild+roles、guild、team、account、channel。
- `src/gateway/core/gateway_agent_route_resolver.cj:547-632`：session key 生成、fallback/default、main session、main DM owner guard。
- `src/gateway/core/gateway_agent_route_resolver.cj:759-860`：binding apply 的 account default 升级、冲突检测和更新。
- `src/gateway/core/gateway_agent_team_broadcast.cj:136-501`：从 `agentTeams.list` 和 legacy `teams` 读取团队，按 broadcast members 生成多 agent executable turns。
- `src/gateway/channels/feishu/feishu_accounts.cj:32-148`：Feishu 多 account/default/account status 摘要。
- `src/gateway/channels/feishu/feishu_adapter.cj:589-693`：card action、reaction、drive comment、bot membership、VC、bitable、message 等事件入口。
- `src/gateway/channels/feishu/feishu_adapter.cj:741-773`：支持 text/post/image/file/audio/video/media/interactive/merge_forward/sticker/share_chat/share_user，并做 app_id 归属校验。
- `src/gateway/channels/feishu/feishu_auth.cj:438-636`：Feishu OAuth token/session store、start/status/poll/complete/revoke runner。
- `src/gateway/tools/gateway_feishu_oapi_client.cj:395-417`：OAPI token provider、app scope checker、refresh client、HTTP client、OAPI client interface。
- `src/gateway/tools/gateway_feishu_oapi_client.cj:475-520`：本地 token provider 能处理 missing scope、expired、offline_access 摘要。
- `src/gateway/tools/gateway_feishu_oapi_client.cj:713-793`：OAPI client 能返回 app_scope_missing、scope_missing、auth_required、api_error 等结构化结果。
- `src/gateway/tools/gateway_feishu_oapi_client.cj:975-1026`：支持多类工具 action，但 token mode 当前统一为 `user_access_token`。
- `src/gateway/tools/gateway_feishu_oapi_toolset.cj:61-100`：Feishu OAPI tool boundary 注入测试 runner/client，默认走 native client。
- `src/gateway/tools/gateway_feishu_oapi_toolset.cj:110-336`：公开 docs/wiki/drive/search/bitable/calendar/task/sheets/chat/user/IM/OAuth/bot image/ask-user-question 等工具。
- `src/gateway/channels/feishu/feishu_cards.cj:148-173`：live card smoke checklist 默认 opt-in，网络默认 disabled。
- `src/gateway/channels/feishu/feishu_cards.cj:245-312`：reply footer config 和 interactive card draft。
- `ui/src/ui/views/agents-panel-teams.ts:85-130`：Control UI Teams 页面包含 workflow、wizard、list/editor、binding、workspace、model、Feishu、capabilities、auth doctor、doctor。
- `ui/src/ui/views/agents-panel-teams.ts:806-915`：Workspace Profiles 和 Model Editor。
- `ui/src/ui/views/agents-panel-teams.ts:1204-1295`：Feishu Auth & Doctor 面板只读展示 status/doctor/OAPI，并提供 Start OAuth via Gateway。
- `ui/src/ui/controllers/agent-teams.ts:122-127`：UI profile 下拉目前只列 `SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`。
- `ui/src/ui/controllers/agent-teams.ts:844-871`：UI 当前只调用 `channels.feishu.auth.start`，未完整暴露 status/poll/complete/revoke 操作。

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
  |     +-- Agents -> Teams
  |     +-- team wizard / binding editor / workspace profiles / model editor
  |     +-- Feishu auth start + doctor/status display
  |
  +-- Channel adapters
  |     |
  |     +-- Telegram adapter
  |     +-- Feishu adapter
  |           |
  |           +-- webhook/long_connect event -> InboundMessage
  |
  +-- Route/session context
  |     |
  |     +-- channel/account/peer/thread/team/roles -> agentId
  |     +-- session key: agent:<agentId>:...
  |
  +-- Agent scope
  |     |
  |     +-- workspace: ~/.metis/workspaces/<agentId>
  |     +-- agentDir:  ~/.metis/agents/<agentId>/agent
  |     +-- sessions:  ~/.metis/agents/<agentId>/sessions
  |     +-- models.json / auth-profiles.json / profile files
  |
  +-- Feishu integrations
        |
        +-- OAuth lifecycle: start/status/poll/complete/revoke
        +-- OAPI native client and toolset
        +-- interactive card draft/controller/fallback
        +-- rich event mapping baseline
```

## 5. 源码对比矩阵

| 能力项 | OpenClaw / OpenClaw-Lark 源码事实 | Metis 源码事实 | 状态 | 当前 GAP | 补齐任务 |
| --- | --- | --- | --- | --- | --- |
| Agent 隔离 | `multi-agent.md:10-18` 定义 workspace/agentDir/sessions 隔离 | `metis_agent_scope.cj:952-1080` 解析 workspaceDir/agentDir/sessionsDir | aligned | 无核心架构 GAP | 保持回归测试 |
| per-agent auth | `multi-agent.md:20-37` 每个 agent 独立 auth-profiles | `metis_agent_scope.cj:1083-1134` 诊断并要求显式复制 | aligned | 无核心架构 GAP | 增强 UI 诊断文案 |
| `agents/` 目录语义 | OpenClaw 使用 `~/.openclaw/agents/<agentId>/agent` 与 sessions | Metis 使用 `~/.metis/agents/<agentId>/agent` 与 sessions | aligned | 无核心架构 GAP | 文档继续保持准确 |
| profile 文件 | OpenClaw workspace 含 `SOUL.md`、`AGENTS.md`、可选 `USER.md` | Metis backend 支持 8 个 profile 文件 | partial | Control UI 下拉只列 4 个文件 | UI 下拉与 backend 支持列表对齐 |
| per-agent model | `agent-scope.ts:142-145` 支持 entry.model | `metis_agent_scope.cj:952-1080`、`agents.models.*`、UI Model Editor | aligned | 真实 provider 凭证仍需用户配置 | 增加 provider readiness doctor |
| shared skills/tools | OpenClaw 支持 workspace + shared roots + allowlist | Metis 有共享内置 toolset 和 per-agent profile，但未完全等价插件市场/skill allowlist UI | partial | 缺少 OpenClaw 式插件/skill 可视化管理 | 后续单独做 skill/tool catalog UI |
| binding apply | `channel-routing.md:58-73`、`resolve-route.ts` 优先级清晰 | `gateway_agent_route_resolver.cj:436-545` 对齐优先级 | aligned | 无核心 GAP | 保持 binding conflict/fallback 测试 |
| `accountId` 语义 | `channel-routing.md:16-20` 默认 account 与 explicit account | `gateway_agent_route_resolver.cj:759-860` default 升级和冲突处理 | aligned | 无核心 GAP | 增加 docs 示例 |
| session key | OpenClaw 使用 `agent:<agentId>:...` | Metis `gateway_agent_route_resolver.cj:547-632` 同结构 | aligned | Feishu thread-capable live cache 仍需真实验证 | 增加真实 Feishu thread smoke |
| team CRUD | OpenClaw wizard + config + bindings | Metis `agents.teams.*` create/update/delete/list/get | aligned | 模板库较小 | 扩展模板不是阻塞项 |
| team broadcast | OpenClaw broadcast groups | Metis `gateway_agent_team_broadcast.cj:136-501` fan-out | partial | manager delegation 不是独立产品化 runtime，失败聚合 UX 不完整 | 明确 manager/fan-out 产品语义并补 UI/CLI 展示 |
| Telegram AgentTeam | OpenClaw ChannelManager + binding | Metis Telegram adapter 走统一 route/session，docs 标注 Telegram 第一优先级 | partial | 本轮未重新做 Telegram live 端到端 | 后续按 Telegram 矩阵继续验证 |
| Feishu account/group/thread | OpenClaw-Lark config 支持 account、group policy、threadSession | Metis Feishu accounts + event mapping + route context | partial | 真实 thread/group policy/cache 与配置诊断不如 OpenClaw-Lark 完整 | 补 live thread/group diagnostic |
| Feishu OAuth/UAT | OpenClaw-Lark tool-client/auto-auth 处理 UAT/TAT、scope、offline_access、auto auth | Metis backend 有 start/status/poll/complete/revoke；UI 只 start | partial | UI 不完整；token store 是本地文件；revoke 只删本地；refresh 缺默认 live refresh client | 完成 UI auth lifecycle、安全 token store、refresh/server revoke |
| Feishu OAPI tools | OpenClaw-Lark 96 action enum，OAPI 注册覆盖多域 | Metis 公开多类 Cangjie tools，覆盖 docs/wiki/drive/search/bitable/calendar/task/sheets/chat/user/IM/OAuth | partial | 需要逐项对齐 96 action；`feishu_get_user.basic_batch` 缺失；tokenMode 总是 UAT | 建立 action parity 测试并补缺口、UAT/TAT 决策 |
| Feishu media/resource | OpenClaw-Lark messenger 支持 history/thread/resource/image/file | Metis 支持 metadata 与 current-turn resource/OAPI 边界 | partial | historical resource fetch 与完整 resource type live 不足 | 补 resource fixture 和 live opt-in smoke |
| rich events | OpenClaw-Lark 有 message/reaction/card/drive/membership 等事件处理 | Metis 已映射 card/reaction/drive/bot membership/VC/bitable/message | partial | converter 宽度和真实事件夹具少于 OpenClaw-Lark | 补事件 fixture replay 与 converter matrix |
| streaming card | OpenClaw-Lark 有完整 CardKit 状态机、flush、guard、image resolver、footer metrics | Metis 有 card draft/controller/fallback/live smoke checklist | partial | 未达到完整 CardKit lifecycle/flush/guard/image/footer 等价 | 补 CardKit parity 和 live smoke |
| Control UI 管理 | 飞书 Miaoda-like 页面能可视化管理多 Agent、模型、插件、Bot/工具 | Metis 有 Agents -> Teams 页面、wizard、binding、workspace、model、doctor | partial | 缺完整 OAuth 操作、Bot/app 自动化向导、plugin/skill catalog、scope repair flow | 补 Miaoda-like 管理闭环 |
| 自动创建 Feishu Bot | 飞书平台普通应用凭证不能直接在第三方系统里无交互创建另一个 Feishu app/bot | Metis 目前不支持自动创建 Feishu bot | not-applicable | 不能把 Feishu 开放平台后台创建 app/bot 完全自动化承诺为 Metis 功能 | 做“配置向导/检查清单/回填配置”，不伪装成自动创建 |

## 6. 用户如何使用当前 AgentTeam

### 6.1 CLI

用户先启动 Gateway：

```bash
cjpm run --skip-build --name metis --run-args "gateway run"
```

然后可以创建团队：

```bash
metis agents team create --team content --name "Content Team" --template pm-writer-reviewer
metis agents team list
metis agents team get --team content
```

绑定 IM 账号或 peer 到指定 member agent：

```bash
metis agents bind --channel telegram --account default --agent content-writer
metis agents bind --channel feishu --account default --agent content-pm
```

需要结构化 binding、broadcast、复杂 team 更新时，通过 Gateway RPC：

```bash
metis gateway call agents.teams.update '{"id":"content","broadcast":{"enabled":true,"members":["content-pm","content-writer","content-reviewer"],"mode":"fan-out"}}'
```

### 6.2 Control UI

当前文档中的入口应描述为：

```text
打开 Control UI -> 左侧导航 Agent 组 -> Agents 页面 -> Teams 区域
```

如果某些构建版本左侧只显示“聊天/Chat”等入口，说明当前运行的 gateway/control-ui 静态资源可能不是最新构建，或导航没有暴露 Agents tab。源码中 `ui/src/ui/navigation.ts` 已存在 `agents` tab，`ui/src/ui/views/agents-panel-teams.ts` 已有 Teams 页面。

在 Teams 页面，用户可以：

- 创建 team 或选择 `PM / Writer / Reviewer` 模板。
- 编辑 members、default member、aliases、bindings。
- 预览并应用 binding。
- 编辑 member 的 workspace profile 文件。
- 读写 per-agent `models.json`。
- 查看 Feishu status/doctor/OAPI readiness。
- 点击 `Start OAuth via Gateway` 发起 Feishu OAuth。

当前 UI 还不能完整完成：

- OAuth status/poll/complete/revoke 的交互闭环。
- 一键修复 app scope、user scope、offline_access。
- 创建或配置 Feishu Bot/App。
- 完整 plugin/skill marketplace 管理。

### 6.3 Telegram / Feishu IM

IM 工具本身不负责创建团队。当前语义是：

- 用户先通过 CLI 或 Control UI 创建 team 和 binding。
- Telegram/Feishu 入站消息进入 ChannelAdapter。
- Gateway route resolver 根据 channel/account/peer/thread/team/roles 选择 agent。
- 如果 team broadcast 开启，Gateway fan-out 到多个 member agents。
- 用户在 IM 里可以通过自然语言、mentions、aliases 或原生命令触发不同 agent 路由，但团队生命周期管理仍应留在 Gateway RPC/CLI/UI。

这个边界是合理的：IM 消息是运行时入口，CLI/UI/Gateway RPC 是管理入口。

## 7. 当前完成度量化

### 7.1 分项评分

| 分项 | 权重 | 当前得分 | 说明 |
| --- | ---: | ---: | --- |
| Agent scope / workspace / agentDir / sessions / models | 15 | 14.0 | 核心隔离已对齐 OpenClaw，剩余是更多诊断和真实路径回归 |
| Route binding / accountId / session key / alias | 14 | 13.0 | 优先级和 apply 语义对齐，继续补真实 IM 边界 |
| Team CRUD / template / broadcast | 12 | 10.5 | CRUD 和 fan-out 已有，manager delegation 未产品化 |
| Telegram AgentTeam 路径 | 8 | 7.0 | 走统一 route/session，仍需本轮之外的 Telegram live 回归 |
| Feishu account / group / thread / events | 12 | 9.0 | rich events 已补基础，真实 thread/group policy/cache 仍需验证 |
| OAuth / UAT / OAPI backend | 15 | 11.0 | backend 边界已有，UI/refresh/revoke/UAT/TAT/action parity 不完整 |
| Card / rich reply / streaming UX | 8 | 5.2 | 有 card draft 和 smoke checklist，距离 OpenClaw-Lark CardKit 仍有差距 |
| Control UI management | 10 | 8.0 | Teams 页面已成型，缺 Miaoda-like 完整闭环 |
| Docs / doctor / live validation gates | 6 | 5.0 | docs/runbook 已补，live opt-in 证据不足 |
| **合计** | **100** | **82.7** | 向上按源码本地可验证口径取 **84/100** |

### 7.2 两种完成度口径

- **源码/本地假数据可验证完成度：84/100**
  依据是核心架构、RPC、route、team、workspace、model、Feishu auth/OAPI/card/event 的源码边界都已存在，且有历史测试/回归脚本支撑。

- **真实飞书生产等价完成度：72/100**
  扣分集中在真实 OAuth/UAT/TAT、app scope repair、token refresh/server revoke、安全 token store、完整 96 action parity、CardKit live streaming、Miaoda-like 管理 UI、真实事件/资源/live smoke。

## 8. 还需要用户补充的信息

如果目标是本地/假数据闭环，用户无需补充真实凭证。

如果目标是真实飞书生产可用，用户需要在本机配置或提供以下测试条件，不能把 token/secrets 直接写入文档或聊天：

- 一个可测试的 Feishu/Lark app，已启用 bot。
- `appId` / `appSecret` 通过 Metis 配置或本地环境变量配置。
- 测试租户、测试用户、测试群、测试话题/thread。
- 已订阅的事件：message receive、reaction、card action、drive comment、bot membership；如果要覆盖 VC/bitable，也需要对应事件。
- OAPI scopes：offline_access、IM、Docs、Drive、Wiki、Sheets、Base、Calendar、Task、Search、User 等按测试动作授权。
- live smoke 显式开关，例如 Feishu card smoke 和 OAPI smoke，默认不能跑真实网络。
- Telegram live 验证需要独立 Telegram bot token 和测试 chat，不允许写入测试夹具。

## 9. 分阶段补齐方案

### Phase 0：证据基线与回归门禁

目标：把当前 series 12 的 GAP 矩阵变成执行前基线，避免重复猜测。

工作项：

- 保留本文件作为本轮 source-backed baseline。
- 为 `agents.teams.*`、`agents.files.*`、`agents.models.*`、`channels.feishu.auth.*`、Feishu OAPI toolset、Feishu card/event 测试建立 phase 对应清单。
- 将历史系列 08-11 的已完成项标注为“已落地”，未完成项只保留真实 GAP。

验收项：

- 文档中每个 `partial`/`missing` 都有源码证据、补齐任务和验证方式。
- 不能出现“猜测缺口”。
- 文件实际存在且可通过 `wc -l`/`sed` 检查；如果 `develop_steps/` 被 `.gitignore` 忽略，需要提交时使用 `git add -f` 明确纳入版本库。

### Phase 1：Feishu OAuth lifecycle UI 闭环

目标：Control UI 不只 start OAuth，还能 status/poll/complete/revoke，并展示 redacted scope/token 状态。

工作项：

- 后端确认 `channels.feishu.auth.start/status/poll/complete/revoke` RPC 行为一致。
- `channels.status` 增加 redacted `channels.feishu.auth` 或 `oauth` 对象，满足 UI 现有读取路径。
- UI 增加 `Status`、`Poll`、`Complete`、`Revoke local auth` 操作。
- UI 不写 token 文件、不保存 app secret、不展示 access token/refresh token。

验收项：

- 单元测试覆盖 missing_app_credentials、pending、authorized、expired、revoked。
- Control UI 显示 accountId、status、tokenStatus、scopeSummary，不显示 secrets。
- 浏览器 smoke：Agents -> Teams -> Feishu Auth & Doctor 不再显示 “Auth status RPC missing”。
- 默认测试不访问真实飞书网络；live 测试必须显式 opt-in。

### Phase 2：安全 token store、refresh、server revoke 和 scope diagnostic

目标：把 OAuth 从“能跑”提升到“可持续使用和可诊断”。

工作项：

- 为 token store 增加权限检查和更明确的文件安全诊断。
- 接入 refresh client 默认实现，使用 refresh_token 更新 access token。
- 区分本地 revoke 和 Feishu server revoke；server revoke 需要显式 opt-in 或可用 app credential。
- scope diagnostic 输出 app scope、user scope、offline_access、缺失 scope、修复入口。

验收项：

- 过期 token + refresh_token 可在 fake client 测试中刷新并保存。
- 缺失 offline_access 时提示重新授权，而不是静默失败。
- revoke 测试验证不会输出 token。
- 没有真实凭证时只返回结构化 diagnostic。

### Phase 3：Feishu OAPI action parity 与 UAT/TAT 决策

目标：按 OpenClaw-Lark 的 96 action enum 做逐项对齐，不只按工具大类对齐。

工作项：

- 建立 `OpenClaw action key -> Metis tool/action -> required scopes -> token mode -> converter -> tests` 矩阵。
- 补 `feishu_get_user.basic_batch` 等当前明确缺失 action。
- `feishuOapiTokenModeForActionKey` 从固定 `user_access_token` 改为 action-aware UAT/TAT 决策。
- 对 task/calendar/IM/bot image 等需要 tenant token 或 bot token 的动作单独建路径。
- 为 unsupported/action invalid/scope missing/app scope missing/API error 保持结构化结果。

验收项：

- 每个 OpenClaw-Lark 96 action 至少有 `aligned`、`not-applicable` 或 `partial with reason` 状态。
- 不能再用“工具大类覆盖”替代 action-level parity。
- fake OAPI client 测试覆盖 UAT、TAT、missing app scope、missing user scope、expired auth。
- 默认测试不访问真实 OAPI。

### Phase 4：Feishu media/resource 与 rich event replay

目标：补齐真实 IM 资源、历史消息资源和 rich event 转换器的可验证边界。

工作项：

- 为 text/post/image/file/audio/video/media/interactive/merge_forward/sticker/share_chat/share_user 建 fixture。
- 为 reaction、card action、drive comment、bot membership、VC、bitable field changed 建 replay 测试。
- 区分 current-turn staged resource、historical resource fetch、bot image、doc media。
- 所有 media/resource 测试不得读取真实用户文件或真实飞书资源。

验收项：

- 每种支持 message type 都有 route/session/mediaContext 断言。
- unsupported event 返回明确 diagnostic，不吞掉错误。
- resource 获取缺 auth/scope 时返回结构化结果。
- 日志不输出 authorization header、token、file content。

### Phase 5：Streaming Card / CardKit parity

目标：把 Metis card 从“可发卡片”提升到接近 OpenClaw-Lark 的 streaming CardKit lifecycle。

工作项：

- 对齐 lifecycle：create、streaming patch、finalize、abort、fallback。
- 补 flush throttle、unavailable guard、card message id recovery、tool-use/reasoning/footer metrics。
- footer 读取 session metrics：input tokens、output tokens、cache read、context%、model。
- live smoke 继续 opt-in，默认只跑 fake transport。

验收项：

- fake card transport 覆盖 create/patch/finalize/abort/fallback。
- message unavailable、rate limit、table limit 都有 fallback。
- footer metrics 在有 session metrics 时可显示，在无 metrics 时优雅降级。
- live smoke 开关关闭时，`cjpm test` 不访问飞书。

### Phase 6：Team collaboration product semantics

目标：明确 manager delegation、deterministic fan-out、alias mention、default member 的产品边界。

工作项：

- 文档和 UI 中区分“普通 route 到单 agent”、“broadcast fan-out 到多 agent”、“manager 作为普通成员/默认成员”的语义。
- fan-out 结果聚合显示每个 member 的状态、错误、耗时、是否发送到 IM。
- alias mention 与 route binding 的优先级写入测试。
- 不引入突破当前 Gateway route/session 边界的隐式 cross-agent handoff。

验收项：

- `@pm`、`@writer`、`@reviewer` alias route 测试覆盖。
- broadcast 成功/部分失败/全失败都有结构化结果。
- CLI 和 Control UI 文案不承诺尚未实现的 autonomous manager。

### Phase 7：Control UI Miaoda-like 管理闭环

目标：让用户能在 Control UI 中完成 AgentTeam 常用管理工作。

工作项：

- Profile 文件下拉补齐 `AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md`。
- Feishu setup wizard：app credentials checklist、event subscriptions checklist、scope checklist、test group checklist。
- OAuth UI 增加 status/poll/complete/revoke。
- OAPI readiness panel 显示 action parity、missing scopes、auth repair next step。
- 保留当前 Gateway RPC 边界，浏览器不直接写配置文件和 token 文件。

验收项：

- Browser smoke：Control UI 打开后 `customElements.get("metis-app")` 注册，页面可见。
- Agents -> Teams 能创建 team、编辑 member、编辑 profile、编辑 model、应用 binding。
- Feishu Auth & Doctor 不展示 secret。
- UI 构建后静态资源能被 Gateway 正确加载。

### Phase 8：CLI / IM UX 与文档修正

目标：让用户知道每个入口该做什么，避免把 IM 当成管理入口。

工作项：

- `docs/user/agent-team.md` 明确 CLI、Control UI、Telegram、Feishu 的使用路径。
- CLI 增加或修正 `metis agents team ...` help 文案。
- Telegram/Feishu IM 中只支持运行时触发、alias、native command，不承担 team CRUD。
- Feishu bot 自动创建能力明确写为“不支持一键创建飞书开放平台应用；支持配置向导和检查清单”。

验收项：

- 文档不再引用不存在的导航名称。
- 用户能按文档完成：创建 team、绑定 Telegram、绑定 Feishu、编辑 profile、编辑 per-agent model。
- IM 文档不承诺后台自动创建 Feishu Bot。

### Phase 9：端到端验证与发布门禁

目标：把源码补齐变成可交付质量。

默认验证命令：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
cjpm clean
cjpm build -i
cjpm test
npm --prefix ui run build
```

Control UI 相关变更必须做浏览器 smoke：

- 页面不是空白。
- `customElements.get("metis-app")` 已注册。
- 无浏览器 JS error。
- 无 failed JS/CSS assets。
- Agents -> Teams 可见且基础操作可用。

Live opt-in 验证：

- Feishu OAuth device flow。
- Feishu OAPI docs/wiki/drive/sheets/base/calendar/task/search/user/IM 选定动作。
- Feishu card create/patch/finalize/abort/fallback。
- Telegram route/session/broadcast smoke。

验收项：

- 默认测试不修改真实环境配置、真实用户文件、真实 token。
- live 测试必须通过显式环境变量开启，并使用测试租户/测试群。
- 所有 redaction 测试通过，日志不泄露 secrets。
- 所有 phase 对应测试和 docs 更新随代码提交。

## 10. 后续优先级建议

推荐顺序仍是用户之前选择的 A，然后补 B 和 C：

1. **A：可用闭环优先**
   OAuth UI lifecycle、token refresh/revoke、OAPI action parity、docs/doctor。目标是让 Telegram/Feishu + CLI/UI 能稳定管理和运行 AgentTeam。

2. **B：飞书体验增强**
   rich events、streaming card、CardKit footer、tool-use/reasoning 显示、live smoke。目标是接近 OpenClaw-Lark 的飞书对话体验。

3. **C：管理 UI 完整化**
   Miaoda-like AgentTeam 管理页、scope repair、setup wizard、profile/model/tool/skill 可视化。目标是让普通用户不用手写 JSON 也能创建和管理团队。

## 11. 最终判断

Metis 当前不是“缺 AgentTeam 核心架构”，而是“核心架构已基本建立，飞书生产体验和可视化管理闭环仍需补齐”。最应该继续补的是：

- Feishu OAuth/UAT/TAT 的 UI 和 runtime 闭环。
- OAPI 96 action 级别 parity 和 tokenMode 决策。
- CardKit streaming 的真实生命周期和 footer metrics。
- Rich event/resource replay 与 live opt-in 验证。
- Control UI Miaoda-like setup wizard 和 profile/model/auth/doctor 完整闭环。

这些工作都可以在 Metis 现有 Gateway RPC、ChannelAdapter、RouteResolver、AgentScope、Control UI 边界内完成，不需要突破架构边界。
