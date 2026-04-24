# Magic-CLI Gateway P0 实现说明（仓颉）

本文档描述已在 `magic-cli` 中新增的 P0 基础能力实现，目标是先打通最小链路：

1. 统一消息协议层（跨渠道统一模型）
2. Gateway 核心最小路由
3. 一个渠道先打通（当前为 Feishu 适配器）

**阅读指引（按主题）**

| 主题 | 章节 |
|------|------|
| 目录与核心文件索引 | **一、二** |
| P0 联调与 P1 demo 参数 | **三、五、六** |
| 飞书长连接 / Webhook | **七** |
| QQ / OneBot / 官方 WS | **八** |
| Skills、`SKILL.md`、网关 `weather` 工具、工具策略映射 | **九** |
| 文档与代码关系 | **十** |
| **会话键 `dmScope`、持久化 jsonl、`gateway sessions` CLI** | **十一** |
| **定时任务 `gateway cron`、`cron/jobs.json`、Dashboard、HTTP API** | **十二** |

**运行时配置约定**：网关与 CLI 共用 **`~/.metis/metis.json`**。常驻网关入口为 `magic-cli gateway serve`（见 `src/gateway/runtime/gateway_cli.cj`），启动时会合并环境变量并加载 `AgentBridge`、`GatewayRouter`、`GatewaySessionStore` 等（见 `gateway_config_factory.cj`）。

---

## 一、目录层级

新增目录如下：

```text
src/gateway/
├── model/
│   ├── types.cj
│   └── config.cj
├── core/
│   ├── channel_adapter.cj
│   ├── router.cj
│   ├── agent_bridge.cj
│   └── gateway_service.cj
├── channels/
│   └── feishu/
│       └── feishu_adapter.cj
└── runtime/
    └── bootstrap.cj
```

演进补充（P1+）：Skills、网关工具、会话持久化相关还包括：

- `src/core/skills/`（`skills_runtime.cj` 等）
- `src/gateway/tools/`（`gateway_weather_toolset.cj`、`gateway_tool_policy.cj`）
- `src/gateway/core/gateway_session_store.cj`（会话 jsonl 转录）
- `src/cron/`（定时任务核心：`cron_command.cj`、调度与 `~/.metis/cron/jobs.json` 持久化；目录布局与当前仓库定时任务实现保持一致）
- 仓库根 `skills/<技能名>/SKILL.md`（示例技能）

Skills / 工具详见 **第九节**；会话与 `dmScope` 详见 **第十一节**；定时任务详见 **第十二节**。

---

## 二、文件与功能说明

### 1) `src/gateway/model/types.cj`

统一消息协议层核心类型：

- `ChannelType`: 渠道枚举（`Feishu`, `QQ`）
- `ChatType`: 会话类型（`Direct`, `Group`）
- `InboundMessage`: 入站消息统一模型
- `OutboundMessage`: 出站消息统一模型
- `SendResult`: 发送结果
- `RouteDecision`: 路由决策结果
- `channelToString` / `chatTypeToString`: 枚举转字符串工具函数

设计价值：

- 渠道 SDK 差异被屏蔽在适配器内，核心链路统一处理
- 后续新增 QQ、钉钉、企业微信时，不需改核心路由逻辑

### 2) `src/gateway/model/config.cj`

网关最小配置模型：

- `ChannelPolicyConfig`: 路由策略（allowlist、群聊是否需要 @、私聊/群聊开关）
- `FeishuConfig`: 飞书账号配置（P0 仅保留最小凭据）
- `GatewayConfig`: 总配置对象（含按渠道策略映射）

设计价值：

- 把“行为策略”与“代码逻辑”分离，便于后续从 JSON 文件加载

### 3) `src/gateway/core/channel_adapter.cj`

渠道适配器接口 `ChannelAdapter`，定义了 5 个关键能力：

- `name`
- `start`
- `stop`
- `pullInbound`
- `send`

设计价值：

- Gateway 与具体平台彻底解耦
- 任何新渠道只需实现同一接口即可接入

### 4) `src/gateway/core/router.cj`

最小路由器 `GatewayRouter`：

- 校验空文本
- 检查私聊/群聊开关
- 群聊可选 @mention 门槛（`ChannelPolicyConfig.requireMentionInGroup`）
- sender allowlist 校验（`allowFrom`：空表示不限制；含 `"*"` 或匹配 `senderId` 则放行）
- 生成 **`conversationKey`**，作为 `AgentBridge.reply(...)` 的第一参数，用于隔离不同聊天上下文

**`conversationKey`（会话键）**

- 并非固定为单一格式，而是由 **`gateway.session.dmScope`**（及环境变量 `GATEWAY_SESSION_DM_SCOPE`）决定分桶方式。
- 默认 **`per-chat`** 下，私聊形如 `{channel}:direct:{peerId}`，群聊形如 `{channel}:group:{peerId}`；其它取值下会产生 `gateway:dm:main`、`gateway:dm:u:...`、`gateway:peer:...` 等形式。
- **完整规则表、私聊/群聊对照**见 **第十一节**，代码见 `buildConversationKey` / `normalizeDmScope`。

设计价值：

- 先实现“安全、可控、可扩展”的最小路由闭环
- 会话维度与持久化文件名一一对应，便于排查与运维

### 5) `src/gateway/core/agent_bridge.cj`

`AgentBridge` 用于连接路由层与 AI 回复层：

- `reply(conversationKey, prompt)`：按会话键记录历史并生成回复
- **P1 起**已接入真实大模型与 **Agent Skills + 网关工具**（详见本文 **第九节**）

设计价值：

- 把“调用真实 Agent”的复杂性隔离到单点
- 渠道与路由不随 Skills / 工具策略变化而改动

### 6) `src/gateway/core/gateway_service.cj`

网关主服务 `GatewayService`，负责把链路串起来：

- 注册适配器
- 启停适配器
- 单次轮询处理 `processOnce()`
- 处理流程：
  - 拉取消息
  - 路由判定
  - 调用 AgentBridge
  - 发送回复

设计价值：

- 结构清晰，便于先本地验证，再切换到常驻循环/调度器

### 7) `src/gateway/channels/feishu/feishu_adapter.cj`

飞书 P0 适配器（基础版）：

- 实现 `ChannelAdapter` 接口
- 提供 `simulateIncomingText(...)` 作为联调入口
- `send(...)` 暂记录到本地日志（`outboundLog`）

设计价值：

- 在不依赖真实飞书网络事件的情况下，先完成端到端链路验证
- 后续可平滑替换为真实 WebSocket/webhook 事件处理

### 8) `src/gateway/runtime/bootstrap.cj`

P0 组装入口：

- 构建默认路由策略
- 初始化 `GatewayRouter` / `AgentBridge` / `GatewayService`
- 注册 `FeishuAdapter`
- 返回 `(GatewayService, FeishuAdapter)` 便于测试或主流程接入

设计价值：

- 把对象装配逻辑集中管理，避免在 `main` 中散落初始化代码

---

## 三、当前 P0 链路如何工作

P0 数据流如下：

1. `FeishuAdapter.simulateIncomingText(...)` 注入入站消息（或 P1 起由 webhook / 长连接真实入队）
2. `GatewayService.processOnce()` 拉取入站消息
3. `GatewayRouter.route(...)` 做最小策略判断，并生成 **`conversationKey`**
4. `AgentBridge.reply(conversationKey, ...)` 生成回复（**P1 起为真实模型**；含会话记忆与可选持久化，见 **第十一节**）
5. `FeishuAdapter.send(...)` 发送回复（**P1 起飞书为真实 API**；QQ 等见 **第八节**）

这条链路完成了“收 -> 路由 -> AI -> 回”的基础闭环。**当前生产路径**以 **`gateway serve` + 渠道适配器真实收消息** 为主，本节 P0 模拟仍可用于最小回归。

---

## 四、后续建议（P1/P2）

在当前基础上，建议按以下顺序增强：

1. **Agent 能力**：Skills 注入、网关工具与当前策略映射见 **第九节**（持续扩展工具集、`/tools/invoke` 等）。
2. **渠道可靠性**：消息去重（messageId TTL 缓存）、发送失败重试与退避（部分已在 QQ 适配器中具备去重窗口）。
3. **多渠道**：QQ 等已接入时，继续复用 `ChannelAdapter` 与统一路由。

---

## 五、如何快速验证（已接入运行参数）

> Dashboard 使用提醒：在执行 `/dashboard` 前，需要先启动 `gateway serve`。  
> 否则 Dashboard 仅显示“网关未运行”提示页，不会进入可聊天状态。

已增加运行参数：

- `--gateway-p0-demo`

效果：

- 程序启动后不会进入交互式 CLI；
- 会自动运行一次 Gateway P0 联调流程（模拟飞书入站消息 -> 路由 -> AgentBridge -> 回包）；
- 控制台会输出发送日志条数与文本内容，用于确认链路打通。

示例：

```bash
cjpm run --name cli --run-args "--gateway-p0-demo"
```

---

## 六、P1 进展（真实模型调用 + 飞书 webhook 事件入队）

已完成的 P1 基础能力：

1. `AgentBridge` 已替换为真实大模型调用（不再返回占位文本）
   - 文件：`src/gateway/core/agent_bridge.cj`
   - 说明：按 **`conversationKey`** 维护会话；**`buildModelInput`** 拼接 Skills 与历史；与 **`GatewaySessionStore`** 配合时可落盘（见 **第十一节**）。
   - 演进：在 **第九节** 所述 Skills + **`weather`** 工具接入后，执行器为 **tool-loop**，不再是最简单轮文本。

2. `FeishuAdapter` 支持 ingest 飞书 webhook 原始 JSON
   - 文件：`src/gateway/channels/feishu/feishu_adapter.cj`
   - 新增方法：`ingestWebhookPayload(payload: String): String`
   - 能力：
     - 处理 `url_verification`（返回 challenge）
     - 解析 `im.message.receive_v1` 文本消息并转为 `InboundMessage` 入队

3. 增加 P1 演示运行参数
   - 参数：`--gateway-p1-demo`
   - 文件：`src/gateway/runtime/demo.cj`, `src/main.cj`, `src/parse_args.cj`

运行示例：

```bash
cjpm run --name cli --run-args "--gateway-p1-demo"
```

---

## 七、P1.5 进展（飞书：长连接默认 + 可选 Webhook）

### 7.1 长连接（默认：仅需 App ID + App Secret）

- 默认 `FEISHU_RECEIVE_MODE=long_connect`（或未设置时等同）。
- 进程启动后向 `${FEISHU_DOMAIN}/callback/ws/endpoint` 申请 `wss` 地址，使用 **二进制 protobuf 帧**（`feishu_ws_frame.cj`）与开放平台维持连接并接收事件。
- **不需要**在飞书后台填写「将事件发送至开发者服务器」的 **请求地址**；但必须在开放平台 **事件与回调** 中：
  - 订阅方式选择 **使用长连接接收事件**（保存前需本客户端已在线，见官方文档）；
  - 添加 **`im.message.receive_v1`**（及所需权限）。
- 可选环境变量：`FEISHU_DOMAIN`（默认 `https://open.feishu.cn`，国际版可用 `https://open.larksuite.com`）。

### 7.2 Webhook（可选）

1. 设置 `FEISHU_RECEIVE_MODE=webhook` 时，`FeishuAdapter.start()` 启动内置 HTTP webhook 服务
   - 监听地址默认：`127.0.0.1:3000`
   - 回调路径默认：`/feishu/events`
   - 健康检查：`/healthz`

2. webhook 收到请求后调用 `ingestWebhookPayload(...)`
   - 支持 `url_verification`
   - 支持 `im.message.receive_v1` 文本消息解析并入队

3. 新增常驻运行参数（非 demo）
   - `--gateway-feishu-webhook`
4. `send()` 已接入飞书真实发消息 API（文本）
   - 自动申请并缓存 `tenant_access_token`
   - 使用 `im/v1/messages` 发送文本回复（`receive_id_type=chat_id`）
5. 增加 webhook 入站安全校验与错误可观测性
   - 校验 `X-Lark-Request-Timestamp` 时间窗
   - 可选要求 `X-Lark-Signature` 头存在
   - 可选校验 payload `token`（`FEISHU_VERIFICATION_TOKEN`）
   - 发送 API 按返回 `code/msg` 判断成功与失败

运行方式：

```bash
cjpm run --name cli --run-args "--gateway-feishu-webhook"
```

运行前请配置环境变量（用于飞书应用鉴权）：

```bash
FEISHU_APP_ID=cli_xxx
FEISHU_APP_SECRET=xxx
```

长连接默认模式下 **`FEISHU_VERIFICATION_TOKEN` 可不配**。若使用 `FEISHU_RECEIVE_MODE=webhook`，仍建议配置 `FEISHU_VERIFICATION_TOKEN`。

其它可选变量：`FEISHU_RECEIVE_MODE`、`FEISHU_DOMAIN`、`FEISHU_ENABLED`、`FEISHU_WEBHOOK_*`、`FEISHU_REQUIRE_SIGNATURE_HEADERS`、`FEISHU_REQUEST_MAX_SKEW_SECONDS`、`FEISHU_BOT_OPEN_ID`（详见上文 7.1 / 7.2）。

---

## 八、QQ 接入进展（OneBot 最小链路）

已新增：

- `src/gateway/channels/qq/qq_adapter.cj`

能力说明：

1. 内置 QQ webhook 服务（OneBot 上报）
   - 默认 `127.0.0.1:5701/qq/events`
   - 健康检查 `GET /healthz`

2. 入站事件解析
   - 解析 `post_type=message`
   - 识别 `message_type=private/group`
   - 转换为统一 `InboundMessage` 入队

3. 出站消息发送
   - 调 OneBot API：
     - 私聊：`/send_private_msg`
     - 群聊：`/send_group_msg`
   - 解析 `status/retcode/msg` 判断发送是否成功

4. 启用方式（环境变量）
   - `QQ_ENABLED=true`
   - `QQ_MODE=official_ws|official_webhook|onebot`（默认 official_ws）

   **官方模式（与当前 AppId/AppSecret 配置体验一致）**
   - `QQ_APP_ID=xxx`
   - `QQ_APP_SECRET=xxx`
   - `official_ws`：使用官方网关 WebSocket 收消息（无需手动配置回调地址）
   - `official_webhook`：使用 HTTP 回调收消息（需要回调地址）
   - `QQ_OFFICIAL_TOKEN_URL=https://bots.qq.com/app/getAppAccessToken`（可选）
   - `QQ_OFFICIAL_GATEWAY_URL=https://api.sgroup.qq.com/gateway`（可选）
   - `QQ_OFFICIAL_WS_URL=wss://api.sgroup.qq.com/websocket/`（可选，默认直连官方 WS）
   - `QQ_OFFICIAL_INTENTS=33559041`（可选，默认 33559041：基础事件 + 频道/私聊消息 + 群/C2C 事件）
   - `QQ_OFFICIAL_BOT_TOKEN=xxx`（已弃用，当前实现会忽略）
   - `QQ_OFFICIAL_SEND_PRIVATE_URL_TEMPLATE=https://api.sgroup.qq.com/v2/users/{peer_id}/messages`（可选）
   - `QQ_OFFICIAL_SEND_GROUP_URL_TEMPLATE=https://api.sgroup.qq.com/v2/groups/{peer_id}/messages`（可选）
   - `QQ_OFFICIAL_AUTH_SCHEME=QQBot`（可选）

   **OneBot 模式**
   - `QQ_ONEBOT_API_BASE_URL=http://127.0.0.1:5700`
   - `QQ_ACCESS_TOKEN=xxx`（推荐，`requireAuthorizationHeader=true` 时建议必配）
   - `QQ_REQUIRE_AUTH_HEADER=true|false`（默认 true，建议保持）
   - `QQ_WEBHOOK_HOST=127.0.0.1`（可选）
   - `QQ_WEBHOOK_PORT=5701`（可选，支持常见端口）
   - `QQ_WEBHOOK_PATH=/qq/events`（可选）
   - `QQ_BOT_ID=12345678`（用于群聊 @ 识别，推荐配置）
   - `QQ_SEND_API_MODE=split|unified`（默认 split）

5. 加固项（当前实现采用的关键思路）
   - 默认开启入站鉴权头检查（避免伪造回调）
   - 未配置 `QQ_BOT_ID` 时群聊默认不触发（避免误触发）
   - 发送 API 支持 split/unified 两种模式
   - 增加 `message_id` 去重窗口（默认 2000）

补充说明（联调友好）：
- `official_webhook` 模式下，当 `QQ_REQUIRE_AUTH_HEADER=true` 且 `QQ_ACCESS_TOKEN` 为空时，程序会打印安全警告但不阻止启动（便于本地联调）。
- `onebot` 模式下保持严格：上述条件会阻止启动，避免暴露未鉴权的消息入口。

启动后可在飞书事件订阅中配置回调地址（按你的网络拓扑映射到本机）：

- `POST /feishu/events`
- `GET /healthz` 用于自检

---

## 九、Agent Skills 与网关工具（能力映射）

本节描述 **Skills（SKILL.md）**、**网关 P1 Agent 工具**、以及 **`metis.json` 配置** 的改动；并说明当前仓库中「Tools / Skills / Plugins」分层及策略的对应关系。

### 9.1 概念映射

| Reference | 含义 | Metis 现状 |
|----------|------|------------------|
| **Tools** | 模型可调用的类型化能力（exec、web_fetch、web_search 等） | **已实现（网关）**：`GatewayWeatherToolset.weather`，仅请求 **wttr.in**（白名单 URL，避免任意 HTTP）。CLI 侧仍沿用既有 `ShellTool`、`FSToolset` 等，**未**与「网关工具列表」合并为同一套 registry。 |
| **Skills** | `SKILL.md` 注入上下文，教模型何时、如何配合工具 | **已实现**：扫描 `SKILL.md`，注入到 **CLI 主 Agent** 与 **网关 `GatewayP1ChatAgent`** 的上下文中（见 9.2）。 |
| **Plugins** | 打包渠道、工具、Skills 等 | **未实现**：无独立插件包机制；能力以源码模块形式扩展。 |
| **`tools.allow` / `tools.deny`** | 工具白名单/黑名单，**deny 优先** | **已实现（网关）**：`metis.json` → `gateway.tools`（见 9.4）。 |
| **`tools.profile` / `group:*`** | 按 profile/分组批量选工具 | **未实现**：无 `group:web` 等简写；需按工具名配置。 |
| **`POST /tools/invoke`** | 网关 HTTP 上受鉴权的直接调工具接口 | **未实现**：与 Feishu/QQ 现有 HTTP 入口分离，可作为后续阶段。 |
| **`gateway.tools` HTTP 层额外 deny** | 在网关 HTTP 上再拦一批工具名 | **未实现**：当前仅在 **Agent 执行工具前** 按配置拒绝（见 `gateway_weather_toolset.cj` 与 `gateway_tool_policy.cj`）。 |

### 9.2 Skills：实现要点与涉及文件

**行为摘要**

- 从多个目录发现子目录下的 `SKILL.md`，解析 YAML 风格 frontmatter（`name`、`description`、可选 `requires_env` 等），合并为一段 **prompt 附录**。
- **CLI**：`GeneralCodeAgent` / `CangjieCodeAgent` 的 `@prompt` 中拼接 `${SkillsPrompt.appendix}`（与 `AGENTS.md` / `userRules` 类似）。
- **网关**：`AgentBridge.buildModelInput` 在「对话历史」**之前**拼接同一段附录，使 IM 侧模型可见技能说明。
- **缓存**：`SkillsPrompt.invalidate()` 在 `parse_args` 结束、`gateway serve` 的 `applyRuntimeForGatewayServe` 等处调用；会清空缓存并 **立即重新扫描磁盘**（便于启动日志中可见完整 discover 链路）。
- **显式 skill 命令（新增）**：支持 `/skillName 参数`（如 `/weather 上海`、`/summarize 链接`），命中后跳过意图识别，直接按指定 skill 执行（CLI 与 Gateway 一致）。

**显式 skill 命令规则（CLI + Gateway）**

- 输入以 `/` 开头时，先按 `skillName` 精确匹配已加载 skill（忽略大小写）。
- 匹配成功：将该 skill 作为本轮 `forcedSkill`，优先级高于自动分类。
- 匹配失败：按原有命令体系处理（内置命令/自定义命令等）。
- 若 `forcedSkill` 对应条目被禁用（`skills.entries.<name>.enabled=false`），本轮不走该 skill 工具链，回退通用模型回答。
- 为避免“串技能工具调用”，运行期会记录 `forcedSkill` 上下文，工具可据此拒绝跨 skill 调用（例如 `/summarize ...` 时拒绝 `weather` 工具）。

**按 skill 可选指定模型（新增，非必须）**

你可以在某个 `skills/<skill-name>/SKILL.md` 的 frontmatter 中额外配置以下字段（都为可选项）：

- `model`: 指定该 skill 生效时优先使用的 LLM（例如 `deepseek:deepseek-chat`）
- `api_key_env`: 指定要覆盖/读取的环境变量名（例如 `DEEPSEEK_API_KEY`）
- `api_key`: 直接提供 api key（不推荐写入仓库；优先使用 `api_key_env`）

运行时规则：
- 若该 skill 未配置 `model`：使用全局 `metis.json` 的 `model/fastModel/fallbackModels`
- 若配置了 `model`：当输入中命中该 skill（基于 skill `name` 的最佳努力匹配）时，优先尝试使用该 skill 的 `model` 与对应 api key
- 若 skill 的鉴权失败（例如鉴权/401/无效 key 等异常）：按现有模型重试与 fallback 逻辑回退到全局模型配置

示例：把 `weather` skill 的模型固定为 deepseek

```yaml
---
name: weather
description: "Get current weather and forecasts via wttr.in or Open-Meteo. ..."
homepage: https://wttr.in/:help

model: deepseek:deepseek-chat
api_key_env: DEEPSEEK_API_KEY
---
```

**扫描顺序（同名后者覆盖）**

1. `metis.json` → `skills.loadExtraDirs`（每项为技能根目录）
2. `~/.metis/skills`
3. `cwd/.agents/skills`
4. **`dotDir.parent/skills`**（含 `metis.json` 的项目根下 `skills/`，**不依赖**当前 shell 是否在子目录）
5. `cwd/skills`

（若 `projectRoot/skills` 与 `cwd/skills` 为同一路径，实现上会 **去重**，只扫描一次。）

**主要文件**

| 路径 | 作用 |
|------|------|
| `src/core/config/skills_user_settings.cj` | `skills.enabled`、`loadExtraDirs`、`entries`（按技能名禁用等） |
| `src/core/config/cli_setting.cj` | `CliSetting.skills` 持久化 |
| `src/core/skills/skills_runtime.cj` | `SkillsPrompt`、发现、解析、格式化、日志、`forcedSkill` 请求级上下文 |
| `skills/<name>/SKILL.md` | 仓库内示例技能（如 `weather`、`example-metis`） |

**补充：skill-creator 用法示例（创建/改写 skill）**

当你希望生成一个新的 `skills/<name>/SKILL.md`（或改写已有 skill），可以在对话里让模型“调用 `skill-creator`”来产出一个可直接落地的最小模板。

示例对话（你可以直接照抄你的需求并替换字段）：

```text
请使用 `skill-creator` 帮我创建一个新 skill：

1) skill name：my-transcript-to-notes
2) 功能：把用户提供的会议纪要/访谈转写提炼为「要点 + 待办 + 风险/不确定点」
3) 触发条件：用户说“总结 / 提炼 / 行动项 / 待办 / 纪要 / 转写”
4) 输出格式要求：
   - 要点：3-6条
   - 待办：列出负责人与截止日期；若原文没有则填“待确认”
   - 风险/不确定点：0-3条
5) 约束：优先用我提供的文本；不要默认在 Windows 上使用 shell curl 抓网页
6) 可选：在该 skill 触发时优先使用 deepseek：deepseek-chat（可写入 model/api_key_env）

请直接输出完整 `skills/my-transcript-to-notes/SKILL.md`（包含 frontmatter + 全文 body），保证可被本仓库的 skills 扫描并加载。
```

你拿到的 `SKILL.md` 放到对应目录后即可生效（同名 skill 按扫描顺序后者覆盖前者）。

### 9.3 网关 P1：工具（Phase 1 天气）

**行为摘要**

- `GatewayP1ChatAgent` 使用 **`executor: "tool-loop:32"`**，注册 **`GatewayWeatherToolset()`**。
- 工具 **`weather`**：通过 `HttpUtils.get` 请求 **`https://wttr.in/...?format=3`**，并对 `location` 参数做基本安全校验（禁止 `://`、`..`、`?`、`#` 等）。
- 系统提示（`GATEWAY_P1_PROMPT`）要求：天气类问题须 **先调用 `weather`**，再依据返回内容回答，**禁止**编造实时气温等。
- 对显式 skill 命令场景：`weather` 工具会校验当前 `forcedSkill`；若本轮强制 skill 不是 `weather`，工具拒绝执行（避免跨 skill 串调用）。

**主要文件**

| 路径 | 作用 |
|------|------|
| `src/gateway/tools/gateway_weather_toolset.cj` | `weather` 工具实现（wttr.in 白名单） |
| `src/gateway/tools/gateway_tool_policy.cj` | `isGatewayToolAllowed`（deny 优先，再 allow 白名单） |
| `src/gateway/core/agent_bridge.cj` | `GatewayP1ChatAgent` 的 tools / executor / 与 Skills 拼接 |

### 9.4 配置示例（`~/.metis/metis.json`）

改完 `metis.json` 后，若已加载过配置，需让程序重新读 settings；SkillsPrompt.invalidate() 会在「加载 settings 或切换工作目录」等场景被调用以刷新缓存。若你改完仍看到旧行为，可重启 CLI/网关进程再试。

**Skills（根键 `skills`）**

```json
"skills": {
  "enabled": true,  //全部 Skills的使能开关
  "loadExtraDirs": [], // 额外技能根目录列表（每个目录下仍是「子目录 + SKILL.md」结构）
  "entries": { // 某一个skill是否使能，未出现在 entries 里的技能 默认启用
    "example-metis": { "enabled": false }，
    "weather": { "enabled": true }
  }
}
```

**网关工具策略（`gateway.tools`，沿用 allow/deny 语义）**

```json
"gateway": {
  "tools": {
    "allow": [],
    "deny": []
  }
}
```

- **`deny` 含 `"weather"`**：禁止执行天气工具（工具内返回中文说明）。
- **`deny` 含 `"*"`**：拒绝所有网关工具（当前仅 `weather`）。
- **`allow` 非空**：仅允许列表中出现的工具名（仍受 `deny` 约束）。
- **`allow` 与 `deny` 均为空**：允许当前注册的网关内置工具（现阶段即 `weather`）。

**按渠道绑定模型（新增）**

可在 `gateway.channelModels` 中按 IM 平台配置主模型（键为渠道名，值为模型名）：

```json
"gateway": {
  "channelModels": {
    "feishu": "deepseek:deepseek-chat",
    "qq": "qwen:qwen-plus"
  }
}
```

运行时行为：
- 网关收到消息后，先按 `channelModels.<channel>` 选择该渠道优先模型；
- 再叠加现有 skill 模型覆盖逻辑（若命中且可用）；
- 若渠道未配置模型或配置为空，回退全局 `model/fallbackModels` 流程。
- 若渠道模型创建失败（模型名/provider 配置错误）或调用失败（API key 无效、鉴权/网络异常等），会自动降级到全局模型链继续尝试，不会直接中断该轮回复。

### 9.5 已实现 vs 待实现

**已实现**

- Skills：发现、`SKILL.md` 解析、注入 CLI + 网关、`settings`、`requires_env`、按路径去重、诊断日志。
- Skills：支持在 `SKILL.md` frontmatter 可选配置 `model/api_key_env/api_key`，并在鉴权失败时回退到全局模型配置。
- 网关：`weather` 工具、tool-loop、`gateway.tools` 策略、系统提示与 Skills 协同说明。
- 配置：`SkillsUserSettings`、`GatewayToolsUserSettings` 持久化到 `metis.json`。

**待实现 / 可选增强**

- 网关 HTTP **`POST /tools/invoke`**（受信任运维调用接口，需鉴权与 rate limit）。
- 更多网关工具（如 `web_fetch` 白名单域名、与 CLI `SearchToolset` 能力对齐）及 **`tools.profile` / `group:*`** 简写。
- **插件（Plugins）** 包与动态注册。
- 天气工具 **`location` 中文城市名**：需 UTF-8 路径编码或 `zh.wttr.in` 等策略（当前以英文地名为稳妥路径）。
- 网关侧 **exec / 全量 Shell**（安全风险高，需更严格的审批与策略）。

---

## 十、文档与代码一致性说明

- **第二节** 中各文件说明随 P1/P1+ 持续更新：`router.cj` / `agent_bridge.cj` 已与 **第十一节**（`dmScope`、持久化）及 **第九节**（Skills、网关工具）交叉引用；同一节已增加 **第 9、10 项**（`gateway_session_store.cj`、`gateway_config_factory.cj`）。
- **第九节** 为 Skills / 工具能力映射的权威补充；**第十一节** 为网关 **Session / 持久化 / dmScope** 的权威补充。
- 若目录结构随版本增加 `src/gateway/tools/`、`src/core/skills/` 等，请以仓库实际文件为准。

---

## 十一、网关会话（Session）与持久化

本节描述 **会话键 `conversationKey`（与持久化中的 `sessionKey` 同义）**、**私信分桶策略 `dmScope`**、**转录落盘格式**、以及 **`gateway sessions` CLI**；实现当前仓库中「按 session 维度维护上下文并可落盘转录」的基础思路。

### 11.1 配置项（`metis.json` → `gateway.session`）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `dmScope` | string | `per-chat` | 私信/群聊如何映射到会话键（见 11.2）。合法值：`per-chat`、`main`、`per-peer`、`per-channel-peer`；非法或空按 `per-chat` 处理。 |
| `persistenceEnabled` | bool | `true` | 是否将会话轮次追加写入 `~/.metis/gateway-sessions/*.jsonl`。为 `false` 时仅内存中保留当前进程内的历史（重启后丢失），且不落盘。 |

**代码位置**：`src/core/config/gateway_user_settings.cj` 中 `GatewaySessionUserSettings`。

**运行时合并**：`src/gateway/runtime/gateway_config_factory.cj` 中 `mergeGatewaySession` 会合并 **环境变量**（优先）与上述配置，再构造 `GatewayRouter` 与 `GatewaySessionStore`。

### 11.2 `conversationKey` 生成规则（`GatewayRouter`）

路由器在通过策略校验后，根据 **渠道名**、**聊天类型（私聊/群聊）**、`peerId`、`senderId` 与 **`dmScope`** 生成唯一字符串，供 `AgentBridge` 作为会话桶使用。

**私聊（`ChatType.Direct`）**

| `dmScope` | `conversationKey` 形式 |
|-----------|------------------------|
| `per-chat`（默认） | `{channel}:direct:{peerId}`，例如 `feishu:direct:oc_xxx` |
| `main` | `gateway:dm:main`（**所有渠道私聊共一条**，仅适合单用户/自用机器人） |
| `per-peer` | `gateway:dm:u:{senderId}`（按发送者全局分桶，跨渠道同一 sender 可共享） |
| `per-channel-peer` | `{channel}:dm:u:{senderId}`（按「渠道 + 发送者」分桶） |

**群聊（`ChatType.Group`）**

| `dmScope` | `conversationKey` 形式 |
|-----------|------------------------|
| `per-chat` / `main`（`main` 对群聊不特殊） | `{channel}:group:{peerId}`（群维度一条上下文） |
| `per-peer` | `gateway:peer:{senderId}`（群内每人一条上下文） |
| `per-channel-peer` | `{channel}:group:{peerId}:u:{senderId}`（按群 + 发送者） |

**说明**

- `channel` 为字符串枚举，见 `channelToString`（如 `feishu`、`qq`）。
- 与旧版「`channel:chatType:peerId`」在 **`per-chat` + 私聊** 下语义对齐；群聊在 `per-peer` / `per-channel-peer` 下更细粒度。

**代码位置**：`src/gateway/core/router.cj`（`buildConversationKey`、`normalizeDmScope`）。

### 11.3 持久化目录与文件格式（`GatewaySessionStore`）

**目录**

- 固定为：`{CliConfig.dotDir}/gateway-sessions/`
- `dotDir` 为 `~/.metis` 数据根目录。

**文件命名**

- 每个会话对应一个文件：`{fileStem}.jsonl`
- `fileStem` 由 `GatewaySessionStore.fileStemForSessionKey(sessionKey)` 对 `sessionKey` 做安全字符替换（尖括号、冒号、引号、斜杠、竖线、问号、星号等替换为 `_`）；过长键使用 `djb2` 哈希与长度后缀，避免文件名过长。

**jsonl 内容**

1. **首行 meta**（JSON 对象）：`kind: "meta"`，`v: "1"`，`sessionKey: "<原始会话键>"`，用于 `gateway sessions list` 与人工对齐。
2. **后续每行一条消息**：JSON 对象，含 `role`（`user` / `assistant` 等）、`text`、`ts`（毫秒时间戳字符串）。

**主要能力**

- `loadHistoryLines(sessionKey)`：读入为 `AgentBridge` 使用的 `user:` / `assistant:` 行列表（跳过 meta）。
- `appendUser` / `appendAssistant`：一轮对话中先写 user，模型返回后再写 assistant。
- `appendTranscriptEntry`：任意 role，供扩展（如 system、工具注入）。
- `listSessionKeys`：扫描目录下 jsonl，从首行 meta 解析 `sessionKey`。
- `readTranscriptRaw` / `deleteSession`：按完整 `sessionKey` 或**不含冒号的文件名主干**查找文件。
- `spawnSession(shortLabel)`：生成 `gateway:spawn:...` 形式的新会话文件（预留给后续「多会话 spawn」等能力）。

**代码位置**：`src/gateway/core/gateway_session_store.cj`。

### 11.4 `AgentBridge` 与内存 / 磁盘

- 每个 `conversationKey` 在内存中维护 `ArrayList<String>` 历史（格式为 `user: ...` / `assistant: ...`）。
- **首次**处理某 `conversationKey` 时，若持久化开启，则尝试从 `GatewaySessionStore.loadHistoryLines` **恢复**。
- 每次用户消息与模型回复后，调用 `appendUser` / `appendAssistant`（若 `enabled`）。

**代码位置**：`src/gateway/core/agent_bridge.cj`。

### 11.5 环境变量覆盖（优先于 `metis.json`）

| 环境变量 | 作用 |
|----------|------|
| `GATEWAY_SESSION_DM_SCOPE` | 覆盖 `gateway.session.dmScope` |
| `GATEWAY_SESSION_PERSISTENCE` | 覆盖 `gateway.session.persistenceEnabled`（实现上为布尔合并，见 `mergeGatewaySession`） |

### 11.6 CLI：`gateway sessions`

用于在未打开文件管理器时直接查看/清理转录（`~/.metis/gateway-sessions`）。

| 子命令 | 作用 |
|--------|------|
| `gateway sessions path` | 打印会话目录绝对路径 |
| `gateway sessions list` | 列出已持久化的 `sessionKey`（从各 jsonl 首行 meta 读取）；若目录为空会提示如何开启持久化与产生首条消息 |
| `gateway sessions show <key>` | 打印某会话转录**原文**（`key` 可为完整 `sessionKey` 或文件主干） |
| `gateway sessions clear <key>` | 删除对应 `.jsonl` 文件（与 `show` 同参规则） |

**代码位置**：`src/gateway/runtime/gateway_sessions_cli.cj`；入口在 `gateway_cli.cj` 的 `gateway sessions` 分支。

### 11.7 相关概念说明

- **Session 键 / 会话分桶**：本仓库按 channel、thread、用户等维度拆分会话；用 **`conversationKey` + `dmScope`** 表达「谁在哪个上下文里说话」。
- **转录落盘**：本仓库使用 **jsonl + 首行 meta** 实现最小可运维格式，并支持 CLI 列出/查看/删除。

### 11.8 已实现 / 待实现（会话子域）

**已实现**

- `dmScope` 四种策略、`persistenceEnabled`、环境变量覆盖、jsonl 转录、`gateway sessions` 子命令、`AgentBridge` 恢复与追加、`spawnSession` 基础能力。

**待实现 / 可选增强**

- 更完整的 **session 命名空间、跨设备同步、按群组策略覆盖 dmScope**。
- 网关 HTTP 上暴露 **session 管理 API**（若与全局 `POST /tools/invoke` 一并设计更佳）。
- 大文件转录的 **压缩/轮转**、敏感信息脱敏导出。

---

## 十二、定时任务（Cron）

定时任务按 **every（固定间隔）**、**at（一次性绝对时间）** 或 **cron（五段式表达式）** 向网关会话投递一条 **prompt**，触发一次 Agent 运行；可选将 **Agent 回复** 再投递到已注册的 IM 适配器（如飞书）。**本仓库存储路径、CLI 子命令与部分扩展字段**以当前代码为准（见 **12.1**、**12.8**）。

- 总览帮助：`gateway cron`（仅 `cron` 一词时）或 `gateway cron help`。
- 子命令详解：`gateway cron <子命令> --help` 或 `-h`（`-h`/`--help` 可出现在子命令参数中任意位置，由 `tryCronSubcommandHelpFromArgv` 统一识别）。

### 12.1 存储位置与路径

| 项 | 含义 |
|----|------|
| 数据根目录 | 由 **`CliConfig.dotDir`** 决定，等价于 **`MetisPaths.homeRoot()`**：优先环境变量 **`METIS_HOME`**（非空绝对路径）；未设置时为当前用户下的 **`~/.metis`**（Windows 常见为 `%USERPROFILE%\.metis`）。 |
| 任务清单 | **`<dotDir>/cron/jobs.json`**。根对象为 JSON：`version`（当前为 `1`）+ `jobs`（任务数组）。实现见 `cron_store.cj` 的 `cronStorePath`。 |
| 运行记录 | 与 `jobs.json` 同级的 **`runs/`** 目录，按任务 id 分文件记录执行历史（`cron_run_log.cj`）。 |

查看本机实际文件路径：

```bash
gateway cron path
```

### 12.2 `jobs.json` 中主要字段

| 字段 | 含义 |
|------|------|
| `jobs[].id` | 任务唯一标识（与 `--name` / `-n` 一致）。 |
| `jobs[].enabled` | 是否启用；`false` 时不会按调度触发。 |
| `jobs[].prompt` | 到期时发给会话的**文本提示**。 |
| `jobs[].sessionTarget` | 会话目标：`main`、`isolated`、`current`，或 `session:<gatewaySessionKey>` 等。 |
| `jobs[].schedule.kind` | `"every"` / `"at"` / `"cron"`。 |
| `jobs[].schedule.everyMs` | 周期间隔（毫秒）；`kind=every`。 |
| `jobs[].schedule.atMs` | 一次性触发 Unix 毫秒；`kind=at`。 |
| `jobs[].schedule.anchorMs` | 周期对齐锚点（内部字段，一般勿手改）。 |
| `jobs[].schedule.cronExpr` | 五段式表达式；`kind=cron`。 |
| `jobs[].schedule.timeZone` | `--tz` 写入的原始字符串；参与 cron 墙上时钟解释。 |
| `jobs[].schedule.staggerMs` | 与五段式 cron 配合的抖动窗口（毫秒）；`--stagger` / `--exact` 影响该字段。 |
| `jobs[].timeoutMs`、`maxRetries`、`retryBackoffMs` | 单次执行超时与失败重试策略。 |
| `jobs[].failureChannel` / `failureTo` / `failureAnnounce` | 失败时的通知渠道与目标（与 `--failure-*` 对应）。 |
| `jobs[].deliveryChannel` / `deliveryTo` / `deliveryAnnounce` | 成功后将 Agent 回复投递到 IM（需 **`gateway serve`** 且已注入 **`GatewayService`**）。 |
| `jobs[].systemEvent` / `wakeMode` | 可选字符串；**当前仅持久化**，未接系统事件总线。 |
| `jobs[].description`、`agentId`、`sessionKey`、`modelOverride` 等 | 扩展字段：写入 JSON；执行路径是否消费见各字段注释与 `gateway cron add --help` 脚注。 |
| `jobs[].state.*` | `nextRunAtMs`、`lastRunAtMs`、`lastError`、`lastStatus`、`consecutiveErrors` 等，由 **CronRunner** 与命令执行路径维护。 |

### 12.3 命令行：`gateway cron`

在已实现 `gateway` 子命令的构建中运行（入口见 `src/gateway/runtime/gateway_cli.cj`）。传给 `executeGatewayCronCommand` 的数组**首元素必须为字符串 `cron`**，第二个元素起为子命令与参数。

#### 12.3.1 子命令一览

| 命令 | 作用 |
|------|------|
| `gateway cron` | 仅含 `cron` 时，等价于 `gateway cron help`。 |
| `gateway cron help` | 打印中文总览（含外部文档链接）。 |
| `gateway cron path` | 打印 `jobs.json` 的**绝对路径**（单行文本，退出码 0）。 |
| `gateway cron status` | 打印 JSON：`enabled`（网关设置中的 cron 总开关）、`storePath`、`jobs` 数量、`nextWakeAtMs` 等。 |
| `gateway cron list` | 打印任务列表 **JSON**；默认仅启用任务。可选 `--all` / `--include-disabled`、`--limit`、`--offset`。 |
| `gateway cron add` / `create` | 新建或**按 id 覆盖**已有任务，见 **12.3.3**。 |
| `gateway cron update` | 按 `--job-id` / `--id` 增量更新已有任务（调度、投递、扩展字段等），见 **12.3.7**。 |
| `gateway cron edit <jobId>` | 轻量编辑：**仅** `--enabled` 与/或 `--message`（二者至少其一）。 |
| `gateway cron remove <id>`、`remove --job-id <id>`、`remove --id <id>` | 删除任务；`rm`、`delete` 同义；**幂等**（无此 id 时 JSON 仍返回 `removed:false`）。 |
| `gateway cron enable <id>` / `disable <id>` | 启用 / 禁用（位置参数 id）。 |
| `gateway cron run` | 走与定时 tick **同源**的 CronRunner 路径执行一次；支持位置 `jobId` 或 `--job-id` / `--id`；`--due` 表示仅当已到期才执行（未到期退出码 1）。**在 IM 内 `/cron run`** 需已 `gateway serve` 并注册钩子；**CLI `gateway cron run`** 会自行注册钩子，可不先起 serve。 |
| `gateway cron runs` | 打印运行日志 **JSON**（`entries`、`total`、`offset`、`limit`、`hasMore` 等）；可选 `--job-id` / `--id`；无 id 时合并所有任务按时间倒序分页。 |
| `gateway cron wake` | 将匹配到的**已启用**任务的 `nextRunAtMs` 提前为「现在」或约 **+10s**（`--mode next-heartbeat`），并写回存储；**不**执行 Agent。**`--text <hint>` 必须非空**，否则返回 `{"ok":false}`。 |

未知子命令返回 JSON 错误（退出码非 0），并提示查看 `gateway cron help`。

#### 12.3.2 帮助文本与终端颜色

| 说明 |
|------|
| `gateway cron <子命令> -h` / `--help` 输出该子命令的英文选项说明（`cronSubcommandHelpText`）。 |
| 在支持 ANSI 的终端中，子命令帮助会对 **`Usage:`、`Options:`、`Arguments:`** 使用橘色系高亮，对 **`--` 选项名与 `<占位符>`** 使用黄色；设置环境变量 **`NO_COLOR`**（任意值）可关闭着色。 |
| 实现：`formatCronHelpForTerminal`（`src/cron/cron_help_terminal.cj`），由 `runGatewayCronCli` 与聊天 **`/cron`** 路径在检测到 `Usage: gateway cron` 时套用。 |

#### 12.3.3 `gateway cron add`：两种写法

**A. 长选项（推荐）** — 第二个参数起为 `--name`、`-n` 或其它 `--` 选项：

- **调度三选一**：`--every`、**或** `--at`、**或** `--cron`。
- **必选**：`--name <jobId>`、`--message <文本...>`（`--message` / `-m` 建议置末尾，其后整段为提示，可含空格）。
- **常用**：`--session <目标>`（`main` \| `isolated` \| `current` \| `session:<key>` 等）。

**B. 兼容旧写法** — 第二参数为字面量 `every` 或 `at`：

```text
gateway cron add every <id> <everyMs> <prompt...>
gateway cron add at <id> <atMs> <prompt...>
```

`everyMs` / `atMs` 为**毫秒**整数；`prompt` 为剩余参数拼接。该写法**不支持**五段式 cron 与 IM 投递等扩展参数，请改用 **A**。

#### 12.3.4 调度与时间参数（`add` / `update` 共用语义）

| 参数 | 含义 |
|------|------|
| `--name` / `-n` | 任务 id。 |
| `--every <间隔>` | 周期：正整数**毫秒**，或 `30s`、`5m`、`1h`、`2d`。 |
| `--at <时间>` | 一次性：Unix **毫秒**、秒级时间戳、`ISO8601`、或相对时间如 **`20m`**（自**执行命令时刻**起算）。 |
| `--cron "<分> <时> <日> <月> <周>"` | 五段式；**整段一个参数**，含空格时请加引号。 |
| `--tz <zone>` | 与五段式 cron 一起解释墙上时钟。支持 **`UTC`/`GMT`/`Local`、空（同 UTC）、`UTC±`、`±HH:MM`**；另支持**内置表**内的常见 IANA 写法（解析为**固定偏移**，非完整时区数据库），例如：`Asia/Shanghai`、`Asia/Tokyo`、`America/New_York`、`Europe/London` 等（完整列表见 `cron_tz_iana.cj`）。**夏令时等复杂规则不在表内时，请用 UTC 偏移或扩展表。** |
| `--stagger` / `--exact` | 仅与 **`--cron`** 搭配：抖动窗口或强制无抖动（与 `every`/`at` 同条命令勿混用）。 |

单次 `add` 或 `update` 调用中，`--every` / `--at` / `--cron` **至多选一**（`update` 未传调度则保留原调度）。

#### 12.3.5 投递、超时、重试与失败通知

仅在 **`gateway serve`** 且 CronRunner 注入 **`GatewayService`** 时，成功路径的 **`--channel` / `--to`** 投递才会真正发往 IM；否则仍执行 Agent，但可能跳过出站。

| 参数 | 含义 |
|------|------|
| `--channel` / `--to` | 适配器名与接收方 peer（如飞书 `chat_id`）。 |
| `--announce` / `--no-announce` | 是否在正文前加 `[cron:<jobId>]`（`update` 可显式关闭）。 |
| `--timeout-ms` / `--timeout-seconds` | Agent 等待回复超时。 |
| `--max-retries` / `--retry-backoff-ms` | 失败后的额外重试与退避。 |
| `--failure-channel` / `--failure-to` / `--failure-announce` / `--no-failure-announce` | 失败通知路径。 |
| `--description`、`--delete-after-run`、`--agent` / `--session-key`、`--model` 等 | 见 `jobs.json` 字段表；部分**仅持久化**，执行层逐步接线，以 `--help` 脚注为准。 |
| `--system-event`、`--wake-mode`（`--wake`） | **仅写入 JSON**，无独立运行时总线。 |

#### 12.3.6 五段式 `cron` 表达式（简要）

五段依次为：**分、时、日、月、周**（空格分隔）。支持常见子集：`*`、单值、区间 `a-b`、列表 `a,b,c`、步进 `/n`。**日**与**周**均非「全量」时，按常见实现为 **或** 关系。周字段 `0` 与 `7` 均表示周日。

```text
0 * * * *          每小时的 0 分
0 9 * * 1          每周一 09:00（在 --tz 对应偏移/表内 IANA 的墙上时钟下解释）
*/15 * * * *       每 15 分钟
```

#### 12.3.7 `gateway cron update`

- **必选**：`--job-id <id>` 或 `--id <id>`。
- **至少一个**修改项：如 `--enabled`、`--message`、调度三选一、`--tz`、`--channel`、`--timeout-*`、重试、失败通知、`--stagger`/`--exact` 等（完整列表见 `gateway cron update --help`）。
- 修改调度后会**重算** `nextRunAtMs`。勿在同一调用中把 `--stagger`/`--exact` 与 `--every`/`--at` 混用。

#### 12.3.8 `run` / `runs` / `wake` / `status`（要点）

| 子命令 | 要点 |
|--------|------|
| `run` | 与计划任务**同一套**执行与落盘逻辑；`--due` 用于「仅到期才跑」。 |
| `runs` | 查 jsonl 聚合后的 JSON 日志；默认 `limit=50`，支持分页。 |
| `wake` | 只改 `nextRunAtMs` 并保存；**必须**提供非空 `--text`。 |
| `status` | 看网关 cron 总开关与下一唤醒时间等元数据。 |

#### 12.3.9 命令示例汇编

```bash
# —— 路径与状态 ——
gateway cron path
gateway cron status
gateway cron list
gateway cron list --include-disabled --limit 100

# —— every / at ——
gateway cron add --name daily-report --every 30m --session main --message 请总结今日仓库提交要点
gateway cron add --name tick --every 10s --session main --message 心跳检查
gateway cron add --name ping --every 300000 --session main --message ping
gateway cron add --name once --at 1735689600000 --session main --message 一次性提醒
gateway cron add --name soon --at 20m --session main --message 20 分钟后提醒

# —— 五段式 cron + 时区（偏移或表内 IANA）——
gateway cron add --name weekly-brief --cron "0 9 * * 1" --tz UTC+8 --session main --message 周一晨间简报
gateway cron add --name tokyo-brief --cron "0 9 * * 1" --tz Asia/Tokyo --session main --message 东京九点简报

# —— 投递（需 gateway serve 且渠道已注册）——
gateway cron add --name push-summary --every 1h --session main --channel feishu --to oc_xxx --announce --message 生成一小时摘要

# —— 增量更新（改调度、提示、投递等）——
gateway cron update --job-id daily-report --every 45m --message 调整频率后的提示
gateway cron update --job-id weekly-brief --cron "30 9 * * 1" --tz UTC+8

# —— 轻量编辑（仅开关或仅文案）——
gateway cron edit daily-report --message 新的提示内容可很长
gateway cron edit daily-report --enabled false

# —— 执行、日志、唤醒 ——
gateway cron run daily-report
gateway cron run --job-id daily-report --due
gateway cron runs --job-id daily-report --limit 20
gateway cron runs --limit 10
gateway cron wake --text "manual-bump" --mode now
gateway cron wake --job-id daily-report --text "bump-one" --mode next-heartbeat

# —— 其它 ——
gateway cron disable daily-report
gateway cron remove daily-report
gateway cron add --help
gateway cron update --help
```

### 12.4 交互式前缀：`/cron`

若 IM 或控制台支持将整行交给网关解析，可使用 **`/cron`** 前缀：去掉前缀后按空格拆成参数，**等价于**在参数数组前插入 `cron` 后走与 CLI 相同的 **`gatewayExecuteCronWithUnifiedRun`**（其中 `run` 子命令与 `gateway cron run` 一样走统一 CronRunner 路径）。例如：

```text
/cron help
/cron list
/cron add --name x --every 5m --session main --message 测试
/cron update --job-id x --message 新提示内容
/cron run x
```

子命令级 **`--help` / `-h`** 与终端着色规则与 **`gateway cron`** 一致（见 **12.3.2**）。

实现见 `parseSlashCronLine`（`src/cron/cron_command.cj`）、`handleGatewayCronLine`（`src/app/metis_command.cj`）、`gateway_cron_cli.cj`。

### 12.5 Web 控制台：`定时任务` 页

在 Dashboard **控制 → 定时任务**：

- 查看任务卡片、筛选（含 **cron** 类型）、排序、**任务描述**（prompt）、编辑 / 克隆 / 启用 / 禁用 / **立即运行** 等。
- **新建**：可选调度类型 **每隔 / 一次性 / 五段式 cron**；可选填写 **投递（渠道、接收方 peer、是否加前缀）**、**系统事件 / 唤醒模式**（与 CLI 一致，部分仅持久化）。
- **编辑**：保存时通过 `save_job` 写回 JSON（含 cron 与时区、投递字段等）。

界面通过 **`POST /api/cron`** 同步，无需手写 JSON。

### 12.6 HTTP API：`POST /api/cron`

Content-Type：`application/x-www-form-urlencoded`（或等价表单字段）。**必填**：`action`。

#### 12.6.1 `action` 与表单字段

| `action` | 必填 | 主要可选字段 | 说明 |
|----------|------|----------------|------|
| `add_every` | `name`, `every`, `message` | `session`（默认 `main`）；`delivery_channel`, `delivery_to`, `delivery_announce`（`true`/`false`/`1`/`yes`/`on`）；`system_event`, `wake_mode` | 对应 CLI `add --every`。 |
| `add_at` | `name`, `at`, `message` | 同上 | 对应 CLI `add --at`。 |
| `add_cron` | `name`, `cron_expr`, `message` | `time_zone`（默认 `UTC`）；`session`；其余同 `add_every` 投递与扩展字段 | 对应 CLI `add --cron`。 |
| `save_job` | `id`, `message` | `schedule_kind`：`every` \| `at` \| `cron`；`enabled`；`every` 或 `at` 或 `cron_expr`+`time_zone`；`session`；`delivery_*`、`system_event`、`wake_mode` | **仅更新已存在任务**；字段需与 `schedule_kind` 一致。 |
| `remove` | `id` | — | 删除。 |
| `enable` / `disable` | `id` | — | 启用 / 禁用。 |
| `edit_message` | `id`, `message` | — | 同 `gateway cron edit ... --message`。 |
| `edit_enabled` | `id`, `enabled` | — | `enabled` 为 `true` 或 `false`。 |
| `run_once` | `id` | — | 立即执行一次 Agent（**不**走 IM 投递逻辑；调度状态仍按任务类型更新）。 |

成功响应一般为 JSON：`ok`、`code`、`message`（以实际返回为准）。

**实现**：`POST /api/cron` 由 **`gatewayDashboardHandleCronPost`**（`src/gateway/runtime/gateway_dashboard_api.cj`）处理；路由注册见 **`gateway_control_ui_routes.cj`**；部分页面内嵌 cron 片段另见 **`gateway_control_ui_content.cj`**（如 **`appendCronJson`**）。

### 12.7 运行时与限制说明

- **调度推进**：由 **`CronRunner`** 在 **`gateway serve` 主循环**中调用；未启动网关进程则**不会**按表自动触发。
- **时区**：`--tz` 在 **`UTC/Local/偏移` 与 `cron_tz_iana` 表内 IANA** 上表现为**固定偏移分钟**；**非表内 IANA、历史夏令时**等需改用显式偏移或 UTC。
- **投递**：依赖已注册 **`ChannelAdapter`** 与 **`GatewayService`**。Dashboard **`run_once`** 与 CLI **`gateway cron run`** 的 IM 侧表现以当前实现为准（成功路径投递与「仅执行」场景可能不同）。
- **`--system-event` / `--wake-mode`**：仅存储于 `jobs.json`；**未接**统一系统事件总线。
- **外部文档**：链接仅供概念对照；存储路径、子命令与字段以本文与 **`gateway cron … --help`** 为准。

### 12.8 代码与文件索引

| 位置 | 说明 |
|------|------|
| `src/cron/cron_command.cj` | `executeGatewayCronCommand`、各子命令实现、`tryCronSubcommandHelpFromArgv`、中文总览帮助 |
| `src/cron/cron_help_terminal.cj` | 子命令帮助 ANSI 着色、`NO_COLOR` 判断 |
| `src/cron/cron_types.cj` | `CronJob` / `CronSchedule` / `CronJobState` |
| `src/cron/cron_store.cj` | `<dotDir>/cron/jobs.json` 读写与原子保存 |
| `src/cron/cron_tz_iana.cj` | 常见 IANA 名 → 固定偏移（表驱动） |
| `src/cron/cron_schedule.cj` | `computeNextRunAtMs`、`computeEveryNextFromAnchor` |
| `src/cron/cron_job_next.cj` | `computeJobNextRun`、错误退避与瞬态判断 |
| `src/cron/cron_expr.cj` | 五段式解析与下一触发时间 |
| `src/cron/cron_run_log.cj` | 运行记录 `runs/*.jsonl` |
| `src/gateway/runtime/gateway_cron_cli.cj` | `runGatewayCronCli`、`gatewayExecuteCronWithUnifiedRun`、打印前着色 |
| `src/gateway/runtime/cron_runner.cj` | 网关在途执行器：到期触发、投递、状态回写 |
| `src/gateway/core/gateway_service.cj` | `sendTextToPeer`（cron 投递） |
| `src/gateway/runtime/gateway_dashboard_api.cj` | Dashboard API：`gatewayDashboardHandleCronPost` 等 |
| `src/gateway/runtime/gateway_control_ui_routes.cj` | 注册 `/api/cron` 等控制 UI 路由 |
| `src/gateway/runtime/gateway_control_ui_content.cj` | 控制页 HTML 片段、`appendCronJson` 等 |

