# Metis Agent Team Series 23：源码复核、GAP 量化、补齐方案和手工验收基线

日期：2026-05-16

## 1. 本次结论先行

这次复核把 Agent Team 的剩余差距一次性按性质锁定，避免继续把不同性质的缺口混在一起：

- **本地代码能力完成度：94/100**。多 agent、workspace、agentDir、session、profile、per-agent model、per-agent credential、binding、team CRUD、broadcast、CLI、Control UI 基础管理面、Feishu native command、OAuth/OAPI/Card/rich-event 本地边界已经在源码中存在。
- **真实生产验收完成度：76/100**。主要缺的是真实 Telegram bot、真实 Feishu app/bot/accountId、真实 OAuth/UAT/TAT、真实 OAPI 资源、真实 CardKit、真实 rich events 的 operator evidence。
- **OpenClaw/openclaw-lark/Miaoda 体验对齐度：83/100**。底层架构大体对齐；差距集中在 Miaoda-like 普通用户管理 UI、官方安装器式一键建/关联机器人、真实 CardKit streaming、丰富飞书事件闭环。
- **综合交付闭环完成度：88/100**。这里的“综合交付闭环”不是此前 series17 里的“综合工程完成度”。它额外扣入真实 Feishu/Telegram live 证据、Miaoda-like 产品体验、自动创建 Feishu app/bot 平台边界和发布验收证据，因此不能和此前的 90/100 工程口径直接比较。

历史口径对齐：

| 历史文档 | 当时口径 | 分数 | 与本文关系 |
| --- | --- | ---: | --- |
| series17 | 综合工程完成度 | 90/100 | 只看本地工程和 fake/local 验收时，本文对应口径已提升到 94/100，没有下降。 |
| series19 | 本地代码能力 | 90/100 | 本文同口径提升到 94/100。 |
| series21 | 本地代码能力 | 92/100 | 本文同口径提升到 94/100。 |
| series21 | 真实生产验收 | 74/100 | 本文同口径提升到 76/100。 |
| series23 | 综合交付闭环 | 88/100 | 这是更严格的交付闭环口径，包含 live evidence、产品体验和平台边界，不表示工程完成度倒退。 |

剩余工作量不是周级。若你能提供测试 Telegram bot、测试 Feishu app/bot、测试租户、测试群、测试文档/日历/任务/多维表格/表格资源，剩余可验证补齐预计 **4-7 人日**。如果还要求“Metis 自动创建 Feishu app/bot”，先需要 **0.5-1 人日平台能力确认**；只有飞书开放平台确实提供可用 API、租户权限和审核路径时，才追加 **3-5 人日实现**。

## 2. 为什么之前看起来每轮只补一小部分

不是应该把进度拖慢，而是此前缺口口径不够硬：

1. **本地代码缺口**可以通过源码、fake transport、临时 `METIS_HOME`、单测和 UI/browser smoke 闭合。
2. **真实 live 缺口**不能靠本地代码声称闭合。比如 Feishu OAuth、OAPI、CardKit、rich events 必须接真实租户、真实权限和真实资源。
3. **平台边界缺口**不能靠猜。比如“自动创建 Feishu app/bot”只有飞书平台确认 API、权限、审核和租户角色后才能实现。
4. **产品体验缺口**不是架构缺失。比如 Control UI 已有管理页，但距离飞书妙搭式普通用户管理台仍有产品化工作。

后续新增 GAP 必须满足一条规则：**必须有 OpenClaw/openclaw-lark/飞书网页或 Metis 源码证据，并标明属于 local-code、external-live、platform-boundary、product-ux、test-infra 哪一类**。没有证据的猜测不进入计划；需要外部资源的项目不再伪装成本地代码失败。

## 3. 证据范围

网页证据：

- 飞书官方文章《OpenClaw飞书官方插件上线｜一文讲清功能、安装更新教程与常见问题！》：`https://www.feishu.cn/content/article/7613711414611463386`。
- 该页面说明官方插件安装命令是 `npx -y @larksuite/openclaw-lark install`，安装时可选择新建机器人或关联已有机器人。
- 该页面说明飞书内主要命令包括 `/feishu start`、`/feishu doctor`、`/feishu auth`。
- 该页面说明官方插件涉及 OAuth 授权、权限导入、消息/文档/日历/知识库/资源/reaction 等权限。

OpenClaw core 源码证据：

- `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/agents/agent-scope.ts:57-95`：枚举 agents 和 default agent。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/agents/agent-scope.ts:129-160`：resolved agent config 包含 workspace、agentDir、model、skills、memory、heartbeat、identity、groupChat、subagents、sandbox、tools。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/config/types.agents.ts:28-59`：binding match 支持 channel、accountId、peer、guildId、teamId、roles。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/config/types.agents.ts:61-105`：AgentConfig 支持 per-agent workspace、agentDir、model、skills、tools、runtime。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/agents/workspace.ts:24-33`：profile 文件名集合包含 AGENTS、SOUL、TOOLS、IDENTITY、USER、HEARTBEAT、BOOTSTRAP、MEMORY。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/concepts/system-prompt.md:97-124`：这些 profile 文件会注入上下文；sub-agent 只注入 AGENTS 和 TOOLS。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/concepts/models.md:234-250`：per-agent `models.json` 位于 `~/.openclaw/agents/<agentId>/agent/models.json`，并定义 merge precedence。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/channels/broadcast-groups.md:168-184`：broadcast agent 的 session、history、workspace、tool access、memory/context 隔离。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/channels/feishu.md:611-635`：Feishu bindings 可将不同 DM/group 路由到不同 agent。

openclaw-lark 源码证据：

- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/openclaw.plugin.json:14-55`：官方工具 contract 覆盖 bitable、calendar、chat、doc、drive、im、oauth、search、sheet、task、wiki、ask_user 等工具。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:78-126`：Feishu channel plugin 声明 direct/group、media、reactions、threads、nativeCommands、blockStreaming。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:167-220`：config adapter 支持 listAccountIds、resolveAccount、defaultAccountId、enable/disable/delete/describe account。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/accounts.ts:85-108`：多账号枚举，顶层 appId/appSecret 可作为 default account。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/accounts.ts:121-208`：按 accountId 合并顶层和 account override，并构造 account-scoped config。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/handler.ts:1-15`：入站消息七阶段 pipeline。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/handler.ts:70-87`：先解析 account，再创建 account-scoped config。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/handler.ts:114-223`：policy gate、历史、sender command authorization、group config、dispatch。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/tool-client.ts:139-250`：ToolClient 统一处理 UAT/TAT、app scopes、user auth、owner fallback。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/tool-client.ts:287-298`：raw path API 复用统一 token/scope 链路。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/card/cardkit.ts:69-95`、`:108-130`、`:142-166`、`:185-245`、`:253-277`：CardKit create、stream patch、final update、send interactive card、settings streaming mode。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/commands/index.ts:95-260`：`/feishu start`、`/feishu doctor`、`/feishu auth`、`/feishu help` 注册。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/commands/auth.ts:115-190`：auth 命令检查 sender、account、self_manage、owner、offline_access、stored token，再触发 onboarding。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/commands/doctor.ts:410-650`：doctor 输出 app scope、user token、权限对照、repair 链接。
- `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/onboarding.ts:38-50`、`:94-171`、`:192-240`：安装向导提示去飞书开放平台创建自建应用、输入 appId/appSecret、探测连接。

Metis 源码证据：

- `src/core/config/metis_agent_scope.cj:74-223`：读取 agents/default agent。
- `src/core/config/metis_agent_scope.cj:635-707`：解析 per-agent model。
- `src/core/config/metis_agent_scope.cj:865-923`：per-agent `auth-profiles.json`、per-agent `models.json`、global providers、env 的 credential source precedence。
- `src/core/prompting/metis_workspace_bootstrap.cj:8-20`、`:178-201`、`:203-232`：Metis 支持同类 profile 文件；`BOOTSTRAP.md` 支持读取但不自动创建。
- `src/gateway/core/gateway_agent_route_resolver.cj:7-63`、`:365-431`、`:473-570`、`:572-655`：route input、accountId、binding priority、session key、fallback diagnostics。
- `src/gateway/runtime/gateway_server_methods_agents.cj:1897-1940`、`:1996-2008`、`:2056-2070`、`:2081-2097`、`:2123-2305`：team template、member agent 自动创建、binding apply、产品语义、team CRUD。
- `src/gateway/core/gateway_agent_team_broadcast.cj:136-153`、`:215-270`、`:329-412`、`:463-514`：team/broadcast 发现、binding match、per-turn scope、fan-out plan。
- `src/program/cli_local_flows.cj:372-459`、`:553-571`、`:1668-1675`：CLI team CRUD 映射和 IM/CLI 边界说明。
- `ui/src/ui/navigation.ts:4-10`、`:48-50`：Control UI 有 agent 分组和 `/agent-teams` 路径。
- `ui/src/ui/views/agents-panel-teams.ts:89-142`、`:145-215`、`:230-295`：Agent Team panel、manual evidence、外部资源 readiness、Feishu guided setup 边界。
- `ui/src/ui/controllers/agent-teams.ts:180-189`、`:191-285`：profile 文件集合和 team templates。
- `src/gateway/channels/feishu/feishu_accounts.cj:43-176`：Feishu 多账号解析和脱敏 account status。
- `src/gateway/core/gateway_service.cj:197-208`、`:468-642`、`:645-745`：Feishu native commands 在 GatewayService 中处理，绕过模型路径，输出 start/doctor/auth/info。
- `src/gateway/core/gateway_service_feishu_native_test.cj:240-475`：native commands 绕过 group gate、输出配置/OAuth/OAPI/Card 状态、脱敏 token/secret。
- `src/gateway/channels/feishu/feishu_auth.cj:191-256`、`:590-780`：Feishu device flow start/poll/status，pending session，scope missing，redacted result。
- `src/gateway/core/gateway_feishu_native_auth.cj:68-120`、`:161-203`：native auth runner 和强制脱敏。
- `src/gateway/tools/gateway_feishu_oapi_client.cj:607-700`、`:977-1095`：user/tenant/bot/app token lookup、统一 invoke、auth/scope/app-scope/API error 分类、message resource fetch。
- `src/gateway/tools/gateway_feishu_oapi_toolset.cj:102-285`：Feishu OAPI toolset 覆盖 doc、wiki、drive、search、bitable、calendar、task、sheet、chat、user。
- `src/gateway/channels/feishu/feishu_cards.cj:6-210`：interactive card JSON、fallback 分类、CardKit live smoke checklist。
- `src/gateway/channels/feishu/feishu_adapter.cj:1720-1885`、`:1960-2110`：group policy context、alias candidates、attachment context、quote、merge_forward、resource boundary。
- `scripts/agentteam-manual-acceptance-gate.sh:71-198`、`:206-433`、`:442-608`：series23 live opt-in、G01-G26、M01-M32、releaseVerification 和 redacted evidence pack gate status。

## 4. 架构对比

### 4.1 OpenClaw + openclaw-lark

OpenClaw core 的 Agent Team 能力不是一个单独 team daemon，而是由下面几层组合：

```text
Control UI / CLI / setup wizard
  -> OpenClaw Gateway/config RPC
  -> agents.list / bindings / models.json / workspace / agentDir / sessions
  -> channel plugins
       -> openclaw-lark Feishu plugin
          -> accountId scoped config
          -> inbound event pipeline
          -> OAuth/UAT/TAT ToolClient
          -> OAPI tools
          -> CardKit
          -> native commands
```

关键点：

- `agents.list` 是多 agent 的事实来源。
- `bindings` 决定 channel/account/peer/team/roles 到 agent 的路由。
- `agentDir` 下可有 `models.json` 等 agent 私有文件。
- workspace/profile 文件定义 agent 的身份、工具、记忆和行为边界。
- openclaw-lark 是 Feishu channel plugin，解决 Feishu 账号、事件、OAuth/OAPI、CardKit 和命令，不负责把所有 agent 管理逻辑塞进 Feishu 消息处理。

### 4.2 Metis

Metis 当前架构与上述主轴基本一致：

```text
CLI / Control UI
  -> Gateway RPC
  -> agents.list / agentTeams.list / bindings / per-agent model/auth/workspace
  -> Gateway session coordinator / route resolver / broadcast planner
  -> Telegram ChannelAdapter / Feishu ChannelAdapter
       -> runtime route, alias, native command
       -> Feishu OAuth/OAPI/Card/rich-event boundaries
```

Metis 与 OpenClaw 的对应关系：

- OpenClaw `agents.list` 对应 Metis `agents.list` + `MetisAgentScope`。
- OpenClaw `bindings` 对应 Metis `gateway_agent_route_resolver.cj`。
- OpenClaw broadcast groups 对应 Metis `gateway_agent_team_broadcast.cj`。
- OpenClaw Gateway agent RPC 对应 Metis `gateway_server_methods_agents.cj`。
- openclaw-lark Feishu account model 对应 Metis `feishu_accounts.cj`。
- openclaw-lark ToolClient 对应 Metis `gateway_feishu_oapi_client.cj`。
- openclaw-lark CardKit 对应 Metis 当前 `feishu_cards.cj` 的 card JSON/fallback/checklist，加上后续真实 CardKit live 验收。

当前差异主要不在 Agent Team 核心架构，而在：

- openclaw-lark 有更完整的官方安装器/插件体验。
- openclaw-lark CardKit 是真实 SDK API 调用链，Metis 目前保留 live checklist 和 fallback 边界，真实 streaming 仍需外部资源验收或补实现。
- 飞书官方/Miaoda 页面是普通用户管理体验，Metis Control UI 当前更像工程管理台。

## 5. 当前 GAP 总矩阵

状态含义：

- `closed-local`：本地代码和测试已具备。
- `external-live`：代码已有，但必须真实 Telegram/Feishu 资源验收。
- `platform-boundary`：需要飞书平台能力、租户权限或审核确认。
- `product-ux`：底层能力有，体验还没有达到飞书/Miaoda 形态。
- `test-infra`：测试/发布门禁问题。

| ID | 能力 | OpenClaw/openclaw-lark 事实 | Metis 当前事实 | 分类 | 当前结论 | 补齐动作 |
| --- | --- | --- | --- | --- | --- | --- |
| G01 | 多 agent/default agent | `agent-scope.ts:57-95` | `metis_agent_scope.cj:74-223` | closed-local | 已对齐 | 保留回归和手工验收。 |
| G02 | workspace/agentDir/session 隔离 | `agent-scope.ts:129-160`、broadcast docs `168-184` | `gateway_server_methods_agents.cj:1907-1940`、broadcast `329-412` | closed-local | 已对齐 | 手工验收跨 agent 不串。 |
| G03 | profile 文件集合 | `workspace.ts:24-33`、system prompt docs `97-124` | `metis_workspace_bootstrap.cj:8-20`、`:178-201` | closed-local | 已对齐，`BOOTSTRAP.md` 不自动创建是明确边界 | 手工验收 UI 可编辑/读取。 |
| G04 | per-agent model | `types.agents.ts:61-99`、models docs `234-250` | `metis_agent_scope.cj:635-707` | closed-local | 已对齐 | 继续守护 DeepSeek/max_tokens 类回归。 |
| G05 | per-agent credential source | OpenClaw `models.json` precedence | `metis_agent_scope.cj:865-923` | closed-local | 已对齐 | 手工验收 credential 不串。 |
| G06 | skill/tool 共享但可按 agent 过滤 | `types.agents.ts:76-99` | Metis agent scope、Control UI、Feishu group policy context | closed-local | 基础已对齐 | live 群 policy 还需验收。 |
| G07 | binding match 维度 | `types.agents.ts:28-59` | `gateway_agent_route_resolver.cj:473-570` | closed-local | 已对齐 | 验收 wildcard/account/team/roles 冲突。 |
| G08 | 管理面与 IM runtime 边界 | OpenClaw Gateway + plugin 分层 | `cli_local_flows.cj:553-571`、`gateway_server_methods_agents.cj:2081-2097` | closed-local | 已明确 | 文档继续强调。 |
| G09 | team CRUD/member 自动创建 | OpenClaw agents/workspace 管理 | `gateway_server_methods_agents.cj:2123-2305` | closed-local | 已具备 | 验收 delete 不删 workspace。 |
| G10 | team broadcast/fan-out | broadcast docs `160-184` | `gateway_agent_team_broadcast.cj:463-514` | closed-local | 已具备本地 plan | live delivery 见 G11/G13。 |
| G11 | Telegram private/group/topic/broadcast live | OpenClaw channel route 模型 | Metis Telegram adapter + route/broadcast gate | external-live | 代码已有，缺真实 bot/group/topic evidence | 提供测试 Telegram 资源，跑 M12-M14。 |
| G12 | Feishu 多 accountId route | `accounts.ts:85-208` | `feishu_accounts.cj:43-176` | external-live | 代码已有，缺两个真实 app/bot | 提供 account A/B，跑 M15。 |
| G13 | Feishu groupPolicy/requireMention/threadSession | inbound handler `114-223` | `feishu_accounts.cj:81-110`、adapter `1720-1733` | external-live | 代码已有，缺群/话题 evidence | 跑 M16-M17。 |
| G14 | Feishu OAuth/UAT device flow | `auth.ts:115-190`、ToolClient `139-250` | `feishu_auth.cj:191-256`、`:590-780` | external-live | 本地实现已有 | 提供 appId/appSecret/offline_access/test user。 |
| G15 | TAT/app/bot token modes | ToolClient `199-250` | `gateway_feishu_oapi_client.cj:607-700` | external-live | 本地实现已有 | 真实 token endpoint smoke。 |
| G16 | OAPI tool matrix | `openclaw.plugin.json:14-55` | `gateway_feishu_oapi_toolset.cj:102-285` | external-live | 工具入口已有 | 每个 family 跑低风险 read/write smoke。 |
| G17 | scope diagnostic/repair hint | doctor `410-650` | OAPI client `977-1050` | external-live | 本地分类已有 | 制造缺 app scope/user scope 的真实诊断。 |
| G18 | CardKit streaming | `cardkit.ts:69-277` | `feishu_cards.cj:6-210` | external-live + product-ux | Metis 有 card JSON/fallback/checklist，真实 streaming 需 live 闭环 | create/stream patch/final/settings/abort/fallback 验收；若无真实 API path 则补代码。 |
| G19 | Rich events/resource | inbound pipeline + media/reaction capabilities | `feishu_adapter.cj:1785-1885`、`:1960-2110` | external-live + product-ux | 当前为 metadata/resource boundary，缺真实事件 evidence | 图片/文件/音频/视频/reaction/quote/merge_forward 验收。 |
| G20 | `/feishu start/doctor/auth` | `commands/index.ts:95-260` | `gateway_service.cj:468-642`、tests `240-475` | closed-local + external-live | 本地已补齐，真实会话待验收 | 在真实飞书 bot 中截图/脱敏日志。 |
| G21 | 自动创建 Feishu app/bot | 飞书官方文章称官方安装器支持新建/关联 | Metis UI 明确只 guided setup | platform-boundary | 不能本地承诺 | 先调研飞书 API/权限/审核；不可行则保持“关联已有机器人”。 |
| G22 | 多机器人映射不同 agent/team | accountId + bindings | `feishu_accounts.cj` + route resolver | external-live | 代码已有 | 两个真实 bot 分别绑定不同 agent/team。 |
| G23 | Miaoda-like 管理 UI | 飞书/Miaoda 产品形态 | `agents-panel-teams.ts:89-295` | product-ux | 工程管理面已有，普通用户管理台未完全达标 | 模板库、导入导出、状态看板、证据包、向导闭环。 |
| G24 | evidence pack/manual gate | OpenClaw doctor/info/fix 思路 | `agentteam-manual-acceptance-gate.sh:71-608` | closed-local | 已具备 series23 本地 gate、skipped/external-resource-required/operator-record-required 区分和证据字段 | 接真实资源后补 live evidence。 |
| G25 | 安全脱敏 | `oauth.ts` 不返 token；doctor/auth 脱敏 | `gateway_feishu_native_auth.cj:161-203`、tests `367-475` | closed-local | 已具备 | 手工检查日志。 |
| G26 | 一键全量 `cjpm test` 稳定性 | OpenClaw 无直接对应 | 上一轮默认包级并发出现过 exit code 9，但单包和 `-j 1` 通过 | test-infra | 不影响功能，但影响发布口径 | 单独做 test runner/并发稳定性排查；不要把它混入 Agent Team 功能 GAP。 |

## 6. 用户如何使用 Agent Team

### 6.1 CLI

CLI 是管理面，走 Gateway RPC，不是 IM channel。

启动 Gateway：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
metis gateway run
```

常用 team 操作：

```bash
metis agents team list --json
metis agents team create --team content --template pm-writer-reviewer --json
metis agents team get --team content --json
metis agents team update --team content --name "Content Team" --member content-writer:writer:Writer --alias @writer=content-writer --json
metis agents team delete --team content --json
```

验收要点：

- CLI 可以创建、查看、更新、删除 team。
- team delete 只删除 team 定义，不删除 member agents/workspaces。
- IM 工具不创建/删除 team，只触发 route、alias、native command。

### 6.2 Control UI

Control UI 是管理面，走 Gateway RPC。

操作路径：

1. 启动 Gateway。
2. 打开 Control UI。
3. 进入 agent 分组中的 `Agent Teams`，路径是 `/agent-teams`。
4. 选择模板或创建 team。
5. 编辑 members、default agent、aliases、bindings、broadcast。
6. 选择成员 agent，编辑 profile 文件和 model。
7. 使用 Feishu setup/repair wizard 查看 app credentials、event subscription、scopes、OAuth、OAPI、Card 状态。

当前边界：

- 支持 guided setup 和关联已有 Feishu bot。
- 不自动创建 Feishu app/bot。
- 不在浏览器保存 appSecret/token 文件。

### 6.3 Telegram

Telegram 是 IM runtime channel。

操作路径：

1. 先用 CLI 或 Control UI 创建 team 和 binding。
2. 私聊 bot，命中绑定 agent 或 default agent。
3. 群/topic 中 @ bot 或满足 group policy 后触发。
4. 若命中 team broadcast，Gateway fan-out 到 selected members 并聚合回复。

当前边界：

- Telegram 不负责 team CRUD。
- 真实验收需要测试 bot、私聊、群、topic、日志脱敏证据。

### 6.4 Feishu

Feishu 是 IM runtime channel + native command channel。

操作路径：

1. 先在飞书开放平台准备或关联测试 app/bot。
2. 在 CLI 或 Control UI 创建 team 和 binding。
3. 在飞书私聊或群聊中发送普通消息、@ bot 或使用命令。
4. `/feishu start` 查看连接和 route 基础状态。
5. `/feishu doctor` 查看 credentials、OAuth、OAPI、CardKit、live resource、AgentTeam findings。
6. `/feishu auth` 启动或查看 OAuth/user authorization。

当前边界：

- Feishu 不负责 team CRUD。
- Feishu 可以触发 runtime route、aliases、native commands。
- 真实 OAPI/Card/rich events 必须接测试租户和测试资源。

## 7. 后续分阶段补齐方案

### Phase 0：锁定 series23 基线

目标：以后新增缺口必须归类，不再把 live/resource/platform 问题伪装成本地代码问题。

工作：

- 将本文作为 series23 后的 source-backed 主基线。
- 所有新增 GAP 必须引用源码或网页证据。
- GAP 分类只使用 local-code、external-live、platform-boundary、product-ux、test-infra。

验收项：

- 本文落盘在 `develop_steps`。
- G01-G26 均有证据和补齐动作。
- 没有“猜测性缺口”。

### Phase 1：真实 Telegram route/broadcast 验收

目标：把 G11 从 external-live 转为 live-accepted。

工作：

- 准备测试 Telegram bot、私聊、普通群、topic 群。
- 配置 private/group/topic binding 和 team broadcast。
- 运行 manual gate 并收集脱敏日志。

验收项：

- 私聊命中指定 agent。
- 群/topic session 不串上下文。
- broadcast fan-out 到 selected members。
- 日志包含 `Gateway.inbound: channel=telegram` 和 outbound 成功记录。
- 日志不包含 bot token、Authorization、proxy credential。

### Phase 2：真实 Feishu 多账号和路由验收

目标：把 G12/G13/G22 转为 live-accepted。

工作：

- 准备两个测试 Feishu app/bot/accountId。
- 分别绑定到不同 agent/team。
- 验证 requireMention、groupPolicy、threadSession、allowlist。

验收项：

- bot A/B 分别命中不同 agent/team。
- 非 @ 消息在 `requireMention=true` 时不触发。
- 不同话题上下文隔离。
- 非 allowlist 用户不能触发敏感 native command。

### Phase 3：Feishu OAuth/UAT/TAT/OAPI live 验收

目标：把 G14-G17 转为 live-accepted。

工作：

- 开通 `offline_access` 和低风险 OAPI scopes。
- 完成 `/feishu auth` device flow。
- 对 doc/wiki/calendar/task/bitable/sheet/im 跑 read smoke。
- 对测试资源跑受控 write smoke。

验收项：

- auth start/status/poll/revoke 输出结构化且脱敏。
- user_access_token、tenant_access_token、bot_access_token、app_access_token 按预期工作或给出准确诊断。
- 每个 OAPI family 至少一个 read smoke 成功。
- 写操作只影响测试资源。
- 缺 scope repair hint 指向正确权限。

### Phase 4：Feishu CardKit streaming live 闭环

目标：把 G18 从 checklist/fallback 推进到真实 CardKit 闭环。

工作：

- 对照 openclaw-lark `cardkit.ts:69-277` 确认 Metis 是否已有可用真实 API path。
- 如果没有真实 create/patch/final/settings path，补实现；如果已有，直接 live smoke。
- 测试 create、stream patch、final update、settings streaming mode、abort、message unavailable fallback。

验收项：

- create 得到 cardId。
- patch 按 sequence 更新。
- final update 关闭 streaming。
- abort/fallback 不丢最终回复。
- 错误不泄露 token/tenant 信息。

### Phase 5：Feishu rich events/resource live 闭环

目标：把 G19 从 metadata/resource boundary 推进到真实事件闭环。

工作：

- 准备图片、文件、音频、视频、reaction、quote、merge_forward 测试消息。
- 验证 current-turn resource context。
- 验证 historical resource fetch 的 auth/scope/error 分类。

验收项：

- image/file/audio/video 均生成 resource context。
- resource fetch 成功或返回 auth_required/scope_missing/api_error。
- reaction、quote、merge_forward 不破坏主消息 dispatch。
- 下载只写测试目录。

### Phase 6：Feishu native command 真实会话验收

目标：把 G20 从本地闭合转为真实 Feishu 会话验收。

工作：

- 在真实测试 bot 私聊和测试群内运行 `/feishu start`、`/feishu doctor`、`/feishu auth`。
- 记录脱敏回复和 Gateway 日志。

验收项：

- `/feishu start` 显示 connection/configuration/accountStatus/route/OAPI。
- `/feishu doctor` 显示 credentials/OAuth/OAPI/CardKit/live resource/AgentTeam findings。
- `/feishu auth` 只展示 verificationUrl、userCode、expires、interval、scopeSummary、安全 message。
- 回复和日志不含 appSecret、deviceCode、accessToken、refreshToken、Authorization。

### Phase 7：Miaoda-like Control UI 产品化

目标：把 G23 从工程管理面提升为普通用户可用的团队管理页面。

工作：

- 增强模板库和角色说明。
- 增加导入/导出 team 配置。
- 增加 route preview、binding conflict preview、evidence pack 入口。
- 增加 Feishu/Telegram readiness 状态看板和修复路径。

验收项：

- 用户不看 CLI 文档也能创建 team。
- 用户能编辑每个 agent 的 profile/model/binding。
- 用户能看懂 Feishu 为什么不可用以及下一步要做什么。
- 浏览器 smoke 无 blank、JS error、asset 404；`customElements.get("metis-app")` 已注册。

### Phase 8：自动创建 Feishu app/bot 平台边界确认

目标：不要做伪实现。

工作：

- 查询飞书开放平台是否允许第三方 API 创建自建应用、启用机器人、配置事件订阅、导入 scopes、发布版本、通过审核。
- 记录 endpoint、token 类型、scope、租户角色、审核要求。
- 若不支持，产品保持 guided setup + 关联已有 bot。
- 若支持，另起实现计划。

验收项：

- 有平台能力结论文档。
- 没有把 `application:application:self_manage` 误写成“可自动创建 app/bot”的依据。
- Control UI 文案不承诺未验证能力。

### Phase 9：发布级验证和证据包

目标：完成代码、UI、真实 IM 和证据包闭环。

工作：

- Cangjie：`cjpm clean && cjpm build -i && cjpm test`。
- UI：`npm --prefix ui run build` 和真实浏览器 smoke。
- Gate：运行 `scripts/agentteam-manual-acceptance-gate.sh`。
- Live：资源具备时运行 Telegram/Feishu opt-in gates。

验收项：

- Cangjie 构建和测试通过，若默认并发 flake，需要记录 `-j 1` 通过和后续 test-infra task。
- UI build/browser smoke 通过。
- evidence pack 明确 pass/fail/skipped/external-resource-required。
- 无 token/secret/Authorization 泄露。

## 8. 手工验收列表

| 编号 | 手工验收条目 | 验收操作方法 | 验收标准 |
| --- | --- | --- | --- |
| M01 | 临时环境安全 | 设置临时 `METIS_HOME` 和报告目录，运行 manual gate | 只写临时目录，不改真实 `~/.metis`；报告脱敏。 |
| M02 | 完整构建和单测 | `source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm clean && cjpm build -i && cjpm test` | 全部通过；若默认并发出现包级 flake，记录 `cjpm test -j 1` 结果并单独进入 test-infra。 |
| M03 | CLI team create | `metis agents team create --team content --template pm-writer-reviewer --json` | 返回 ok；team 有 members/defaultAgentId/broadcast/semantics。 |
| M04 | CLI team list/get | `metis agents team list --json`、`metis agents team get --team content --json` | 能看到刚创建的 team、members、aliases、semantics。 |
| M05 | CLI team update | 更新 name/member/alias/binding | 配置持久化；binding apply 成功或返回明确 conflict。 |
| M06 | CLI team delete | `metis agents team delete --team content --json` | team 删除；member agents/workspaces 保留。 |
| M07 | member agent 自动创建 | 创建 team 后查看 agents list 或配置文件 | member agents 存在，workspace/agentDir/sessionsDir 独立。 |
| M08 | profile file 隔离 | 分别编辑 writer/reviewer 的 `SOUL.md` | 两者内容互不污染，UI/CLI 读取一致。 |
| M09 | model 隔离 | 给不同 agent 配不同 model | model status 不互相覆盖。 |
| M10 | credential profile 隔离 | 给 agent A/B 配不同测试 credential source | agent A/B 不串用 token/auth profile。 |
| M11 | binding conflict | 给两个 agent 设置同一 channel/account/peer binding | 第二次 apply 返回 conflict，不写半成品配置。 |
| M12 | Telegram 私聊 route | 测试 bot 私聊发送消息 | 命中指定 agent，回复成功，sessionKey 正确。 |
| M13 | Telegram 群/topic route | 测试群和 topic 中 @ bot | group/topic 独立 session，日志脱敏。 |
| M14 | Telegram team broadcast | 触发绑定 team broadcast | selected members 均执行，聚合回复可读。 |
| M15 | Feishu account status | 配两个测试 accountId，打开 channels status 或 `/feishu info --all` | 两个 account 均显示 configured/enabled/running 或明确错误；凭据脱敏。 |
| M16 | Feishu group policy/mention | 群内非 @ 和 @ bot 分别测试 | requireMention 行为正确，allowlist 生效。 |
| M17 | Feishu thread session | 话题群两个 topic 分别对话 | 上下文不串，replyInThread 行为正确。 |
| M18 | Feishu OAuth start/status/poll | `/feishu auth` 后完成 device flow，再看 status/poll | pending/authorized/scope_missing 状态正确；不泄露 deviceCode/token。 |
| M19 | Feishu app/token modes | 用测试 app 运行 app/tenant/bot/user token OAPI smoke | 成功或返回准确 missing_credential/auth_required/scope_missing/app_scope_missing。 |
| M20 | Feishu OAPI read smoke | doc/wiki/calendar/task/bitable/sheet/im 各读一个测试资源 | 每类至少一个 read 成功。 |
| M21 | Feishu OAPI write smoke | 对测试资源执行低风险 create/update | 只影响测试资源，有回滚或清理记录。 |
| M22 | Feishu CardKit streaming | 测试群跑 create/patch/final/settings/abort | card 可见、patch 有序、final 正确、fallback 可读。 |
| M23 | Feishu resource read | 图片/文件/音频/视频消息触发 resource context/fetch | current-turn metadata 正确；historical fetch 成功或准确诊断。 |
| M24 | Feishu rich events | reaction、quote、merge_forward 测试 | 事件不破坏 dispatch，context/diagnostic 可读。 |
| M25 | `/feishu start` | 测试会话发送 `/feishu start` | 显示 connection/configuration/accountStatus/route/OAPI。 |
| M26 | `/feishu doctor` | 测试会话发送 `/feishu doctor` | 显示 credentials/OAuth/OAPI/CardKit/live resource/AgentTeam findings，且脱敏。 |
| M27 | `/feishu auth` | 测试会话发送 `/feishu auth` | 只显示安全授权字段，不显示 token/secret/deviceCode。 |
| M28 | Control UI browser smoke | 打开 Gateway Control UI | 非空页面，无 JS error、asset 404；`metis-app` 已注册。 |
| M29 | Control UI team CRUD | 在 `/agent-teams` 创建/编辑/删除 team | 刷新后状态持久，错误可读。 |
| M30 | Control UI profile/model/binding | 在页面编辑 profile/model/binding | Gateway RPC 成功或返回明确错误；不泄露 secrets。 |
| M31 | Control UI Feishu wizard | 查看 setup/repair wizard | 能看到 app credentials、event subscription、scopes、OAuth、OAPI、Card 状态和下一步。 |
| M32 | evidence pack | 运行 manual acceptance gate 并收集报告 | 报告包含 pass/fail/skipped/external-resource-required，且脱敏。 |

## 9. 需要用户补充的真实资源

这些资源是把 external-live 项改为 live-accepted 的前提：

- Telegram：测试 bot token、测试私聊、测试群、测试 topic、代理配置如需要。
- Feishu：测试租户、两个测试 app/bot/accountId、开发者后台权限、测试用户、测试群、话题群。
- OAuth/OAPI：`offline_access`、必要 scopes、测试 doc/wiki/calendar/task/bitable/sheet/im 资源。
- CardKit：支持 card create/patch/final/settings 的测试群和权限。
- Rich events：图片、文件、音频、视频、reaction、quote、merge_forward 测试消息。
- 平台边界：若要自动创建 Feishu app/bot，需要飞书开放平台 API/租户角色/审核路径的官方或 live 证据。

## 10. 下一步执行建议

优先级 A：真实资源验收闭环。

- 先跑 Telegram M12-M14。
- 再跑 Feishu M15-M17。
- 再跑 OAuth/OAPI M18-M21。
- 最后跑 Card/rich M22-M24。

优先级 B：Control UI 产品化。

- 基于当前 `/agent-teams` 页面增强导入导出、route preview、证据包入口和状态看板。

优先级 C：平台能力确认。

- 只调研并记录 Feishu 是否允许自动创建 app/bot。
- 没有证据前，产品文案继续保持 guided setup + 关联已有 bot。

优先级 D：test-infra。

- 默认 `cjpm test` 并发稳定性单独处理，不和 Agent Team 功能需求混在一起。
