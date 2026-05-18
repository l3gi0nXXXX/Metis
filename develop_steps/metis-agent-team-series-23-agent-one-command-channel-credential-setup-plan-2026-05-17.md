# Metis Agent One-Command Channel Credential Setup Plan

日期：2026-05-17

## 1. 目标

本方案解决一个明确问题：用户创建一个 agent 时，可以在同一条命令中同时写入该 agent 的模型、Feishu AppId/AppSecret、QQ Bot AppId/AppSecret、Telegram Bot Token，并自动完成渠道账号配置与 agent 路由绑定。

目标命令形态：

```bash
metis agents add \
  --agent zhihu-strategist \
  --name "知乎策略师" \
  --model qwen/qwen3.6-plus \
  --feishu "cli_fake_app_id:fake_feishu_secret" \
  --qqbot "1020000000:fake_qq_secret" \
  --telegram-bot-token "123456789:fake_telegram_token"
```

可选显式账号 ID：

```bash
metis agents add \
  --agent zhihu-strategist \
  --name "知乎策略师" \
  --model qwen/qwen3.6-plus \
  --feishu-account zhihu-feishu \
  --feishu "cli_fake_app_id:fake_feishu_secret" \
  --qqbot-account zhihu-qq \
  --qqbot "1020000000:fake_qq_secret" \
  --telegram-account zhihu-telegram \
  --telegram-bot-token "123456789:fake_telegram_token"
```

本阶段按用户要求接受裸凭据输入。安全边界是：命令行参数可以裸传，但 CLI 输出、Gateway RPC 返回、日志、测试断言、AGENT.md/SOUL.md/IDENTITY.md/USER.md 等 agent 文档都不得泄露完整 secret/token。

## 2. 源码依据

### 2.1 OpenClaw 已有的“一条命令创建 agent + 绑定渠道”依据

OpenClaw 的 CLI 注册中，`agents add [name]` 支持 `--workspace`、`--model`、`--agent-dir`、`--bind <channel[:accountId]>`、`--json`，说明“创建 agent 时附带路由绑定”是 OpenClaw 已有设计，而不是 Metis 自创。

依据：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/cli/program/register.agent.ts:170-199`。

OpenClaw 的 `agentsAddCommand` 在非交互路径中先 `applyAgentConfig`，再 `parseBindingSpecs`，再 `applyAgentBindings`，最后 `replaceConfigFile`，说明 agent 创建与 binding 可以在同一个命令流程中统一落配置。

依据：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/agents.commands.add.ts:104-135`。

OpenClaw 输出时只打印 agent、workspace、agent dir、model 和 binding 冲突摘要，不把底层配置 JSON 整包暴露给用户。

依据：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/agents.commands.add.ts:145-180`。

### 2.2 Metis 当前 agent add 与 bind 的现状

Metis 当前 `metis agents` 帮助中已有 `agents add`、`agents bind`、`agents unbind`、`agents team`，说明 agent 和 team 在 CLI 层已经是两个不同功能入口。

依据：`src/program/cli_local_flows.cj:1760-1780`。

Metis 当前参数解析器识别 `--bind`，但在 `--bind` 分支只跳过参数，没有保存到数组，也没有传给 `agents.add`。

依据：`src/program/cli_local_flows.cj:1868-1873`。

Metis 当前 `agents add` 只向 Gateway RPC 传 `agentId`、`name`、`workspace`、`model`，没有传 binding，也没有传 Feishu/QQ/Telegram 凭据。

依据：`src/program/cli_local_flows.cj:2156-2180`。

Metis 当前 `agents bind` 已经支持重复 `--bind`，并调用 Gateway RPC `agents.bind`，且非 JSON 模式会打印 Added/Skipped/Conflicts 的人类可读摘要。

依据：`src/program/cli_local_flows.cj:2021-2095`。

Metis Gateway 当前 `agents.add` 会创建 agent entry、workspace、agentDir、sessionsDir、默认 AGENT.md，然后 `MetisConfigManager.writeRoot(root)` 写配置。

依据：`src/gateway/runtime/gateway_server_methods_agents.cj:1274-1365`。

Metis Gateway 当前 `agents.bind` 会解析 binding specs，并通过 `gatewayApplyAgentRouteBindings` 写入 route bindings。

依据：`src/gateway/runtime/gateway_server_methods_agents.cj:1210-1232`。

Metis route binding 的冲突规则已经存在：同一个 channel/account 路由如果已属于同一 agent 就 skipped，属于其他 agent 就 conflicts。

依据：`src/gateway/core/gateway_agent_route_resolver.cj:822-889`。

### 2.3 Metis 当前渠道账号配置现状

Telegram 用户配置已有 `defaultAccount`、`botToken`、`tokenFile`、`accounts`。

依据：`src/core/config/gateway_user_settings.cj:379-392`。

Telegram runtime config 已持有 `accountId`、`defaultAccount`、`botToken`、`tokenFile`、`accounts`。

依据：`src/gateway/model/config.cj:749-819`。

Telegram adapter 会优先读取 account override 中的 `tokenFile`/`botToken`，没有 account override 时再回退到顶层 `tokenFile`/`botToken`。

依据：`src/gateway/channels/telegram/telegram_adapter.cj:1305-1331`。

Feishu 用户配置已有 `defaultAccount`、`appId`、`appSecret`、`accounts`。

依据：`src/core/config/gateway_user_settings.cj:451-459`。

Feishu runtime config 已持有 `accountId`、`defaultAccount`、`appId`、`appSecret`、`accounts`。

依据：`src/gateway/model/config.cj:940-984`。

Feishu account resolver 会从 `accounts[accountId]` 读取 `appId`/`appSecret` override，并保留顶层字段作为 fallback。

依据：`src/gateway/channels/feishu/feishu_accounts.cj:63-94`。

Feishu inspect/status 已经对 `appSecret` 做 redacted 输出。

依据：`src/gateway/channels/feishu/feishu_accounts.cj:131-171`。

QQ 用户配置当前只有顶层 `appId`、`appSecret`，没有 `accounts` 字段。

依据：`src/core/config/gateway_user_settings.cj:489-508`。

QQ runtime config 当前只有顶层 `appId`、`appSecret`，没有 `accountId`、`defaultAccount`、`accounts` 字段。

依据：`src/gateway/model/config.cj:1045-1087`。

QQ adapter 当前启动时要求 `config.appId` 和 `config.appSecret` 非空，并用这两个字段换取官方 access token。

依据：`src/gateway/channels/qq/qq_adapter.cj:62-78`、`src/gateway/channels/qq/qq_adapter.cj:680-692`。

## 3. Superpowers 头脑风暴

### 3.1 方案 A：把 Feishu/QQ/Telegram 凭据直接写进 agent entry

优点：实现最短。

问题：Metis 现有架构把 agent 元数据放在 `agents.entries`，把 IM 凭据放在 `gateway.<channel>`；Telegram/Feishu/QQ adapter 也从 channel config 读取凭据。把凭据写进 agent entry 会突破 channel/session 架构边界，并导致 adapter 无法自然读取。

结论：拒绝。

### 3.2 方案 B：`agents add` 编排 agent 创建、channel account 写入、route binding 应用

优点：与 OpenClaw `agents add --bind` 的命令语义一致；与 Metis 当前 `agents.add`、`agents.bind`、channel config、route resolver 边界一致；用户只需要一条命令。

代价：需要扩展 CLI 参数、Gateway RPC 参数、channel credential apply 逻辑、QQ per-account 能力。

结论：采用。

### 3.3 方案 C：用户先配置 channel，再 `agents add`，再 `agents bind`

优点：当前已有部分能力。

问题：用户明确要求一条命令把一个 agent 配好；当前 `--bind` 在 `agents add` 中被解析但丢弃，本身也是缺陷。

结论：不能作为目标方案，只能作为兼容路径保留。

### 3.4 方案 D：只支持 Feishu/Telegram，一期不支持 QQ per-account

优点：Feishu/Telegram 已有 accounts 字段，实现风险较低。

问题：用户明确把 QQ Bot `appid:appsecret` 放在同一条目标命令中；QQ 如果继续只有顶层凭据，多 agent 多 QQ bot 会互相覆盖。

结论：拒绝。QQ 要补 `accounts`/`defaultAccount`/`accountId`，否则不满足完整需求。

### 3.5 方案 E：裸凭据先打通，后续再补 secret-ref/env-file

优点：符合用户“appid 和 appsecret 先设计成裸的，先把功能打通”的要求。

风险：shell history、process list、日志都有泄漏风险。

控制措施：本阶段接受裸参数，但必须做到 CLI/Gateway 输出 redacted、日志 redacted、测试不使用真实凭据、不把 secret 写进 agent 文档。后续可以在不破坏命令语义的基础上补 `--feishu-env`、`--qqbot-env`、`--telegram-token-file`、交互式输入。

结论：采用。

## 4. 目标架构

### 4.1 命令层

`metis agents add` 增加以下参数：

- `--bind <channel[:account]>`：修复当前解析后丢弃的问题，完全按现有 `agents bind` 语义传给 Gateway。
- `--feishu <appId:appSecret>`：写入 `gateway.feishu.accounts[accountId]`。
- `--feishu-account <accountId>`：默认值为 `--agent` 的 agentId。
- `--qqbot <appId:appSecret>`：写入 `gateway.qq.accounts[accountId]`。
- `--qqbot-account <accountId>`：默认值为 `--agent` 的 agentId。
- `--telegram-bot-token <botToken>`：写入 `gateway.telegram.accounts[accountId].botToken`。
- `--telegram <botToken>`：`--telegram-bot-token` 的短别名。
- `--telegram-account <accountId>`：默认值为 `--agent` 的 agentId。
- `--channel-overwrite`：当目标 account 已存在但凭据不同，允许覆盖；默认不覆盖并返回明确冲突。

默认行为：

- 提供 `--feishu` 时，自动追加 binding `feishu:<feishuAccountId>`。
- 提供 `--qqbot` 时，自动追加 binding `qq:<qqbotAccountId>`。
- 提供 `--telegram-bot-token` 或 `--telegram` 时，自动追加 binding `telegram:<telegramAccountId>`。
- 用户显式提供的 `--bind` 与自动 binding 合并去重。
- 未提供任何 channel credential 时，`agents add` 保持当前行为。

### 4.2 Gateway RPC 层

扩展 `agents.add` 请求参数：

```json
{
  "agentId": "zhihu-strategist",
  "name": "知乎策略师",
  "model": "qwen/qwen3.6-plus",
  "bind": ["telegram:zhihu-strategist", "feishu:zhihu-strategist", "qq:zhihu-strategist"],
  "channelCredentials": {
    "telegram": {
      "accountId": "zhihu-strategist",
      "botToken": "123456789:fake_telegram_token"
    },
    "feishu": {
      "accountId": "zhihu-strategist",
      "appId": "cli_fake_app_id",
      "appSecret": "fake_feishu_secret"
    },
    "qq": {
      "accountId": "zhihu-strategist",
      "appId": "1020000000",
      "appSecret": "fake_qq_secret"
    }
  },
  "channelOverwrite": false
}
```

RPC 内部必须使用同一个 cloned root 完成预检与写入：

1. 校验 agentId、agent 是否已存在。
2. 校验 channel credential 字段格式。
3. 校验 accountId 合法性。
4. 检查目标 channel account 是否已存在。
5. 已存在且凭据相同：复用 account。
6. 已存在且凭据不同且没有 `channelOverwrite`：失败，不写任何配置。
7. 已存在且凭据不同且有 `channelOverwrite`：覆盖 account。
8. 合并自动 binding 和显式 `bind`。
9. 调用现有 binding parser/apply 逻辑处理 route conflicts。
10. 无错误后才创建目录/manifest，并一次性写 root。

### 4.3 配置层

Telegram：

```json
"telegram": {
  "enabled": true,
  "defaultAccount": "default",
  "accounts": {
    "zhihu-strategist": {
      "botToken": "123456789:fake_telegram_token"
    }
  }
}
```

Feishu：

```json
"feishu": {
  "enabled": true,
  "defaultAccount": "default",
  "accounts": {
    "zhihu-strategist": {
      "appId": "cli_fake_app_id",
      "appSecret": "fake_feishu_secret"
    }
  }
}
```

QQ：

```json
"qq": {
  "enabled": true,
  "defaultAccount": "default",
  "accounts": {
    "zhihu-strategist": {
      "appId": "1020000000",
      "appSecret": "fake_qq_secret",
      "mode": "official_ws"
    }
  }
}
```

QQ 需要新增 per-account resolver。resolver 规则应与 Feishu/Telegram 对齐：

- 指定 accountId 时优先读取 `qq.accounts[accountId]`。
- account 未配置时回退顶层 `qq.appId`/`qq.appSecret`。
- accountId 非 default 且 accounts 存在但找不到 account 时，返回明确配置错误。
- status/inspect 输出只显示 appId 摘要，不显示 appSecret。

### 4.4 绑定层

最终 route binding 示例：

```json
{
  "type": "route",
  "agentId": "zhihu-strategist",
  "match": {
    "channel": "telegram",
    "accountId": "zhihu-strategist"
  },
  "enabled": true
}
```

Feishu 和 QQ 同理。binding 冲突继续使用现有 `gatewayApplyAgentRouteBindings` 的 added/skipped/conflicts 规则。

### 4.5 输出层

非 JSON 输出示例：

```text
Added agent: zhihu-strategist
  name: 知乎策略师
  model: qwen/qwen3.6-plus
  workspace: /Users/...
  agentDir: /Users/...
Configured channel accounts:
  - telegram:zhihu-strategist token=[redacted]
  - feishu:zhihu-strategist appId=cli_... appSecret=[redacted]
  - qq:zhihu-strategist appId=1020... appSecret=[redacted]
Added bindings:
  - telegram:zhihu-strategist -> zhihu-strategist
  - feishu:zhihu-strategist -> zhihu-strategist
  - qq:zhihu-strategist -> zhihu-strategist
```

`--json` 输出也必须 redacted，不允许把 raw token/appSecret 放进 response。

### 4.6 实现文件映射

后续实现必须优先在下列文件内落地，不应绕到无关模块：

| 层级 | 文件 | 作用 | 设计约束 |
| --- | --- | --- | --- |
| CLI 参数与输出 | `src/program/cli_local_flows.cj` | `metis agents add` 参数解析、Gateway RPC 参数组装、非 JSON 输出 | 只改 `agents add` 相关路径；`agents bind/unbind/team` 不应被重写 |
| CLI 测试 | `src/program/cli_local_flows_agent_team_test.cj` 或新增同目录测试 | 覆盖 CLI 参数、输出、redaction | 不用真实 token；不访问真实 Gateway |
| Gateway agent RPC | `src/gateway/runtime/gateway_server_methods_agents.cj` | 扩展 `agents.add`，统一预检、credential 写入、binding apply、result redaction | 一次请求内完成；失败不写配置 |
| Gateway agent RPC 测试 | `src/gateway/runtime/gateway_server_methods_agents_test.cj` | 覆盖成功、冲突、overwrite、atomicity | 使用临时配置根；不访问真实 `~/.metis` |
| 配置模型 | `src/core/config/gateway_user_settings.cj` | 增加 QQ accounts/defaultAccount | Telegram/Feishu 已有 accounts，不重复造结构 |
| 运行态配置 | `src/gateway/model/config.cj` | 增加 QQ accountId/defaultAccount/accounts | 保持旧顶层 QQ 配置兼容 |
| 配置构建 | `src/gateway/config/gateway_config_builder.cj` | 从用户配置构建 QQ runtime config | 旧配置仍能启动 |
| QQ resolver | 建议新增 `src/gateway/channels/qq/qq_accounts.cj` | 解析 QQ per-account 配置 | 语义参考 Feishu account resolver |
| QQ adapter | `src/gateway/channels/qq/qq_adapter.cj` | 使用 resolved QQ account 的 appId/appSecret | 不改变 official_ws 主路径 |
| channel inspect/status | `src/gateway/runtime/gateway_server_methods_channels.cj` | 增加 QQ accounts inspect/状态摘要 | secret 必须 redacted |
| 用户文档 | `docs/user/agent-team.md` 或新增 `docs/user/agents.md` | 说明 agent 与 team 区别、快捷配置命令、手工验收 | 不把此能力写成 team 功能 |

### 4.7 单入口、单路径、最大复用原则

这是本需求的硬性实现原则，后续代码实现和测试必须逐条满足：

1. 不新增子命令。入口仍然是现有 `metis agents add`，只新增参数。
2. CLI 不直接写配置。CLI 只解析参数、做最基础的格式校验、组装 `agents.add` RPC params。
3. Gateway `agents.add` 是唯一编排入口。agent 创建、channel account credential 写入、route binding apply 必须在同一个 Gateway RPC 内完成。
4. 不允许 CLI 里串行调用 `agents.add`、`agents.bind`、channel config mutation 来模拟一命令能力；这种实现会产生半成功状态。
5. agent 创建逻辑必须复用 `gatewayAgentAddJson` 现有 agent/workspace/agentDir/sessions/manifest 创建路径，不允许新增第二套 agent 创建函数。
6. binding 解析必须复用 `gatewayAgentParseBindingSpecs`，binding 写入必须复用 `gatewayApplyAgentRouteBindings`，不允许新增第二套路由匹配/冲突判断。
7. Telegram credential 必须复用现有 `gateway.telegram.accounts.<accountId>.botToken/tokenFile` 配置结构和 Telegram adapter resolver，不允许新增 `agents.entries[].telegramToken` 之类字段。
8. Feishu credential 必须复用现有 `gateway.feishu.accounts.<accountId>.appId/appSecret` 配置结构和 `gatewayFeishuResolveAccount` 语义，不允许新增第二套 Feishu account 解析。
9. QQ 因当前缺少 per-account 能力，可以新增 resolver，但必须参考 Feishu/Telegram 的 account resolver 语义，不能设计第三种 account 语义。
10. 配置写入必须复用 `MetisConfigManager.writeRoot(root)` 的完整 root 写入模型，不能绕过 config manager 直接写用户配置文件。
11. 输出 redaction 必须集中成 helper 复用；CLI、RPC result、error 路径不能各自手写一套 secret masking。
12. 后续任何 phase 发现需要新增与既有函数重复的逻辑时，必须先回到本文档说明为什么既有函数不能复用，再实施。

专项测试要求：

- 必须有测试证明 `agents add --bind ...` 最终走 `agents.add` 的 binding parser/apply 结果，而不是 CLI 侧二次调用 `agents.bind`。
- 必须有测试证明 Telegram/Feishu 写入的是现有 accounts 结构，而不是 agent entry 或新字段。
- 必须有测试证明 QQ 顶层旧配置仍可用，新增 accounts 只是扩展，不替代旧路径。
- 必须有 redaction 测试覆盖成功输出、JSON 输出、错误输出，确保集中 helper 生效。

## 5. 分阶段落地计划和验收项（可执行细化版）

每个 phase 必须满足三个规则：

1. 先补测试或至少补测试计划，再补实现。
2. 不允许把 secret/token 打印到 stdout、stderr、日志、RPC result、测试失败信息。
3. 任意失败都不能产生“配置写了一半”的状态；如果文件系统目录已经创建但配置未写入，需要在错误路径做 best-effort cleanup 或在结果中明确标记为未注册且不可见。
4. 不允许为已有能力新增第二套实现路径；必须先复用现有函数，缺口只能在现有函数无法覆盖时补最小扩展。

### Phase 0：冻结源码事实、实现边界和测试矩阵

目标：

- 把实现范围固定为 `metis agents add`。
- 明确它与 `metis onboard`、`metis agents team create` 的区别。
- 把所有后续实现用到的源码依据、目标文件、测试入口写清楚。

源码依据：

- OpenClaw `agents add --bind`：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/cli/program/register.agent.ts:170-199`。
- OpenClaw add 命令将 agent config 与 binding 一起落盘：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/agents.commands.add.ts:104-135`。
- Metis 当前 `agents add` 没传 binding/credential：`src/program/cli_local_flows.cj:2156-2180`。
- Metis 当前 `agents bind` 已有 binding apply 调用：`src/program/cli_local_flows.cj:2021-2095`、`src/gateway/runtime/gateway_server_methods_agents.cj:1210-1232`。

实施步骤：

1. 保留本文件作为单一实施说明，不再新增相互冲突的 agent 快捷配置文档。
2. 在本文件增加“实现文件映射”，确认所有代码修改都能落在表中列出的模块。
3. 列出测试矩阵，至少包括：
   - CLI 参数解析。
   - RPC schema 解析。
   - Telegram account 写入。
   - Feishu account 写入。
   - QQ per-account 写入与 resolver。
   - binding 自动生成与冲突。
   - redaction。
   - atomicity。
4. 明确实现不触碰真实 `~/.metis`、真实 Telegram/Feishu/QQ 网络、真实 bot token。

Phase 0 冻结矩阵：

| 冻结项 | 结论 | 依据 | 验收方式 |
| --- | --- | --- | --- |
| 功能入口 | 只扩展 `metis agents add` 参数 | 目标命令形态和 `4.1 命令层` | 文档和 CLI help 不出现新的 credential/setup 子命令 |
| 单 agent 与 team 边界 | `metis agents add` 创建单 agent；`metis agents team create` 创建团队模板 | Metis CLI 已分离 `agents add` 和 `agents team` | 用户文档必须分别说明 Create One Agent 和 Create A Team |
| onboard 边界 | `metis onboard` 仍用于全局默认设置，不承担本快捷配置 | 本需求要求 agent 创建时绑定 channel account | 文档不得把本能力描述为 onboard 流程 |
| IM 应用创建边界 | Metis 不自动创建 Telegram Bot、Feishu App、QQ Bot | Provider 应用必须由用户在平台控制台创建 | 文档和验收清单必须提醒先准备测试应用 |
| credential 落点 | 写入既有 channel account 配置 | Telegram/Feishu 已有 accounts；QQ 需补 per-account | 配置快照测试不出现 `agents.entries[].telegram/feishu/qq` secret 字段 |
| binding 落点 | 写入既有 route bindings | 现有 `gatewayApplyAgentRouteBindings` | 自动 binding 与手工 `agents bind` 冲突语义一致 |
| 事务入口 | Gateway `agents.add` 统一编排 | CLI 只组装 RPC params | CLI mock 只看到一次 `agents.add` 调用 |
| secret 输出 | stdout/stderr/log/RPC result 必须 redacted | 本阶段接受裸参数但不允许泄露 | 默认输出、`--json`、错误输出均断言 raw secret 不存在 |
| 测试环境 | 不使用真实 `~/.metis`、真实网络、真实生产 secret | Telegram transport notes 和安全边界 | 测试必须使用临时 home、fake adapter 或 isolated config |

Phase 0 文档验收矩阵：

| 文档位置 | 必须覆盖 | 禁止内容 |
| --- | --- | --- |
| 本方案 `目标`、`4.1`、`5 Phase 0` | 命令形态、参数、落点、事务边界 | 新增子命令方案 |
| 本方案 `4.6`、`4.7` | 实现文件映射和复用原则 | 绕过 Gateway/ConfigManager 的写入路径 |
| 本方案 `5 Phase 8` | 功能测试、复用测试、redaction 测试、atomicity 测试 | 只测 happy path |
| `docs/user/agent-team.md` 或 `docs/user/agents.md` | 用户操作命令、检查命令、overwrite、fake secret 提醒 | 把 agent credential shortcut 写成 team 功能 |

复用约束：

- Phase 0 只冻结设计，不允许引入“新增子命令”方案。
- 测试矩阵必须单独列出“复用既有函数/既有配置结构”的测试项，不能只测最终效果。
- 后续实现文件如果超出 `4.6 实现文件映射`，必须先补本文档说明理由。

自动化验收：

- 文档包含 OpenClaw 与 Metis 源码路径。
- 文档包含本节的实现文件映射。
- 文档明确 `agents add`、`onboard`、`agents team create` 三者边界。
- 文档包含 `4.7 单入口、单路径、最大复用原则`。
- Phase 8 测试矩阵包含复用专项测试。

手工验收：

- 人工阅读文档时，可以回答：
  - 此功能入口是不是 `metis agents add`。
  - 是否会创建 team。
  - 是否会自动创建 IM 平台应用。
  - 是否会写 agent markdown。

完成定义：

- 本文档成为后续实现依据；新增代码如果发现本文档未覆盖的新设计点，必须先回到本文档补充。

### Phase 1：CLI 参数解析与请求组装

目标：

- 让 `metis agents add` 能接收 agent 模型、IM credential、显式 accountId、显式 binding、overwrite 开关。
- 只做参数解析和 RPC params 组装，不在 CLI 层直接写配置。

涉及文件：

- `src/program/cli_local_flows.cj`
- `src/program/cli_local_flows_agent_team_test.cj` 或新增同目录 focused test

新增参数：

| 参数 | 是否可重复 | 默认值 | 写入 RPC 字段 | 说明 |
| --- | --- | --- | --- | --- |
| `--bind <channel[:account]>` | 是 | 空数组 | `bind: JsonArray` | 修复当前解析后丢弃问题 |
| `--feishu <appId:appSecret>` | 否 | 空 | `channelCredentials.feishu.appId/appSecret` | 使用第一个冒号切分 |
| `--feishu-account <id>` | 否 | `agentId` | `channelCredentials.feishu.accountId` | 为空时回退 agentId |
| `--qqbot <appId:appSecret>` | 否 | 空 | `channelCredentials.qq.appId/appSecret` | 使用第一个冒号切分 |
| `--qqbot-account <id>` | 否 | `agentId` | `channelCredentials.qq.accountId` | 为空时回退 agentId |
| `--telegram-bot-token <token>` | 否 | 空 | `channelCredentials.telegram.botToken` | 不切分 token |
| `--telegram <token>` | 否 | 空 | 同上 | `--telegram-bot-token` 别名 |
| `--telegram-account <id>` | 否 | `agentId` | `channelCredentials.telegram.accountId` | 为空时回退 agentId |
| `--channel-overwrite` | 否 | false | `channelOverwrite` | 允许覆盖已有 account credential |

实现步骤：

1. 在 `cliRunAgentsFlow` 的统一参数扫描区新增本 phase 参数变量：
   - `binds: ArrayList<String>`
   - `feishuRaw`
   - `feishuAccount`
   - `qqRaw`
   - `qqAccount`
   - `telegramToken`
   - `telegramAccount`
   - `channelOverwrite`
2. 当前 `--bind` 分支只 `i += 2`，必须改为保存值到 `binds`。
3. 新增 `cliAgentsParseCredentialPair(raw, label)` 语义：
   - trim 后为空：错误。
   - 不含冒号：错误。
   - 冒号前为空：错误。
   - 冒号后为空：错误。
   - 只按第一个冒号切分，后续冒号属于 secret。
4. Telegram token 不使用 pair parser，原样 trim 后写入。
5. 组装 `params.channelCredentials` 时只放用户提供的 channel。
6. 如果用户同时传 `--telegram` 和 `--telegram-bot-token`：
   - 值相同：接受一次。
   - 值不同：返回 usage error，不调用 Gateway。
7. 帮助文案增加完整示例，不把示例 secret 写成真实格式。

错误处理：

- 缺参数：复用 `cliReturnMissingArgument`。
- pair 格式错误：返回 usage error，消息只包含字段名，不回显 raw secret。
- accountId 格式错误不在 CLI 层最终裁决；CLI 只 trim，Gateway 负责 sanitize/拒绝。

复用约束：

- CLI 只能扩展现有 `agents add` 分支，不能新增 `agents add-channel`、`agents setup`、`agents credential` 等子命令。
- CLI 不调用 `MetisConfigManager.writeRoot`、`CliSettingManager.writeGatewaySettings`、`agents.bind` RPC 或 gateway channel mutation。
- CLI 参数缺失继续复用 `cliReturnMissingArgument`；未知参数继续复用 `cliReturnInvalidArgument`。
- CLI 组装 `bind` 参数时必须使用现有 `agents.bind` RPC 已接受的 `bind: JsonArray` 结构，不新增另一个 binding 参数名。
- CLI 输出默认人类可读的最终渲染可以新增 helper，但不能直接打印 raw `res.toJson().toJsonString()`。

自动化测试：

1. `agents add` 无新增参数时，RPC params 与旧行为一致。
2. `--bind telegram:a --bind feishu:b` 最终 params 中有两个 bind。
3. `--feishu "cli:id:secret"` 被解析为 `appId=cli`、`appSecret=id:secret`。
4. `--qqbot "1020:secret:tail"` 被解析为 `appId=1020`、`appSecret=secret:tail`。
5. `--telegram-bot-token "123:ABC"` 保持完整 token。
6. `--telegram "123:A" --telegram-bot-token "123:B"` 返回错误且不调用 Gateway。
7. 输出和错误信息不包含测试 raw secret。
8. mock Gateway client 断言 CLI 只调用一次 `agents.add`，不调用 `agents.bind` 或其他 mutation。
9. mock Gateway client 断言 CLI 不直接写本地配置文件。

手工验收：

```bash
metis agents add --agent demo --name Demo \
  --model qwen/qwen3.6-plus \
  --bind telegram:demo \
  --feishu "cli_test:secret_test" \
  --qqbot "1020:test_secret" \
  --telegram-bot-token "123456:test_token"
```

预期：

- 如果 Gateway 尚未实现 Phase 2，CLI 至少应能正确发送 params。
- 如果 Gateway 已实现，进入后续 phase 行为。

完成定义：

- CLI 层不写配置。
- CLI 层不泄露 secret。
- CLI 层能把所有新增字段传给 `agents.add`。

### Phase 2：Gateway RPC schema、预检计划与原子写入框架

目标：

- 扩展 `agents.add`，让 Gateway 作为唯一配置写入者。
- 所有校验在写配置、创建目录、写 manifest 前完成。
- 构建一个统一 plan，包含 agent entry、channel credential changes、binding changes、filesystem changes。

涉及文件：

- `src/gateway/runtime/gateway_server_methods_agents.cj`
- `src/gateway/runtime/gateway_server_methods_agents_test.cj`

请求 schema：

```json
{
  "agentId": "zhihu-strategist",
  "name": "知乎策略师",
  "workspace": "/path/to/workspace",
  "model": "qwen/qwen3.6-plus",
  "bind": ["telegram:zhihu-strategist"],
  "channelCredentials": {
    "telegram": {"accountId": "zhihu-strategist", "botToken": "123456:fake_test_token"},
    "feishu": {"accountId": "zhihu-strategist", "appId": "cli_test", "appSecret": "fake_test_secret"},
    "qq": {"accountId": "zhihu-strategist", "appId": "1020", "appSecret": "fake_test_secret"}
  },
  "channelOverwrite": false
}
```

内部 helper 建议：

- `gatewayAgentCredentialObject(request)`：读取 `channelCredentials`。
- `gatewayAgentCredentialString(obj, keys, default)`：安全读取字段。
- `gatewayAgentCredentialNormalizeAccountId(agentId, raw)`：raw 为空则 agentId，最终用已有 agent/account sanitizer。
- `gatewayAgentBuildCredentialPlan(root, agentId, request)`：返回 plan 或错误。
- `gatewayAgentApplyCredentialPlan(root, plan)`：只修改 cloned root，不写磁盘。
- `gatewayAgentCredentialPlanRedactedJson(plan)`：只输出 redacted summary。

复用约束：

- `gatewayAgentAddJson` 继续作为唯一 `agents.add` 实现入口，不新增平行的 `gatewayAgentAddWithCredentialsJson` RPC 方法。
- agent entry、workspace、agentDir、sessionsDir、manifest 的创建流程必须复用 `gatewayAgentAddJson` 现有逻辑；允许把现有代码抽取成 helper，但调用路径仍只有 `agents.add`。
- binding parse 必须调用 `gatewayAgentParseBindingSpecs`；binding apply 必须调用 `gatewayApplyAgentRouteBindings`。
- 写配置必须使用一个 cloned root，并最终只调用一次 `MetisConfigManager.writeRoot(root)`。
- 不允许调用 `gatewayAgentBindingsApplyJson` 来“顺手绑定”，因为那会让 `agents.add` 事务拆成两个写入路径。

预检顺序：

1. `agentId` 必填并 sanitize。
2. agent 不存在。
3. workspace/agentDir/sessionsDir 计算完成。
4. auth copy plan 校验完成。
5. 解析 channelCredentials。
6. 校验每个 credential 的必填字段。
7. 校验 account 是否已存在、是否可复用、是否需要 overwrite。
8. 合成自动 binding。
9. 合并显式 binding。
10. 调用 binding parser 与 conflict checker。
11. 所有错误为空后，进入 filesystem 创建和 root 写入。

原子性策略：

- 配置写入必须只调用一次 `MetisConfigManager.writeRoot(root)`。
- 若 credential 或 binding 预检失败，不创建 agentDir/workspace/sessionsDir。
- 若目录创建失败，不写配置。
- 若 manifest 写入失败，不写配置。
- 若目录已经创建但随后失败，执行 best-effort cleanup；cleanup 失败也不写配置，并在错误中说明只留下未注册目录。

错误消息规则：

- 错误消息必须包含 channel 和 accountId。
- 错误消息不得包含 raw appSecret/botToken/apiKey。
- 格式示例：
  - `feishu credential requires appId:appSecret.`
  - `telegram account "demo" already exists with a different token; pass --channel-overwrite to replace it.`
  - `binding telegram:demo is already claimed by agent "old-agent".`

自动化测试：

1. agent 已存在时，`channelCredentials` 不写入。
2. `channelCredentials.feishu.appSecret` 缺失时，不创建目录、不写 root。
3. binding 冲突时，不创建目录、不写 root。
4. account 冲突且无 overwrite 时，不创建目录、不写 root。
5. manifest 写入失败模拟时，不写 root。
6. 所有失败响应都不包含 raw secret。
7. spy 或测试替身确认成功路径只发生一次 root write。
8. 构造 binding 冲突，确认结果与直接调用现有 binding apply 逻辑的冲突语义一致。
9. 断言不存在第二个公开 RPC 方法承担同样创建职责。

手工验收：

- 在临时 Metis home 下构造已存在 binding，再执行冲突命令。
- 验证 `metis agents list` 中没有新 agent。
- 验证 channel account inspect 中没有新 account。

完成定义：

- `agents.add` 支持新 schema。
- 失败不产生注册态半成品。
- 成功 result 只包含 redacted channel account summary。

### Phase 3：Telegram 与 Feishu account 写入

目标：

- 使用现有 Telegram/Feishu accounts 配置结构，不发明新结构。
- 支持 created/reused/updated/conflict 四种结果。

涉及文件：

- `src/gateway/runtime/gateway_server_methods_agents.cj`
- `src/core/config/gateway_user_settings.cj`
- `src/gateway/channels/telegram/telegram_adapter.cj`（只作为现有 resolver 验证依据，通常不应改）
- `src/gateway/channels/feishu/feishu_accounts.cj`（只作为现有 resolver 验证依据，通常不应改）
- `src/gateway/runtime/gateway_server_methods_agents_test.cj`

Telegram 写入规则：

```json
"gateway": {
  "telegram": {
    "enabled": true,
    "accounts": {
      "agent-id": {
        "botToken": "123456:test_token"
      }
    }
  }
}
```

Feishu 写入规则：

```json
"gateway": {
  "feishu": {
    "enabled": true,
    "accounts": {
      "agent-id": {
        "appId": "cli_test",
        "appSecret": "secret_test"
      }
    }
  }
}
```

兼容规则：

- 不修改已有 `defaultAccount`。
- 不修改已有顶层 `botToken/appId/appSecret`，除非用户传的是 default account 且实现明确选择 default 语义；本方案默认全部写入 `accounts[agentId]`。
- 如果 account 不存在：created。
- 如果 account 存在且字段相同：reused。
- 如果 account 存在且字段不同且 `channelOverwrite=false`：conflict。
- 如果 account 存在且字段不同且 `channelOverwrite=true`：updated。

复用约束：

- Telegram 只写现有 `gateway.telegram.accounts`，不能新增 `gateway.telegram.agentAccounts`、`agents.entries[].telegram` 等结构。
- Feishu 只写现有 `gateway.feishu.accounts`，不能新增平行 account store。
- 运行态读取不能新增第二套 Telegram/Feishu resolver；必须依赖现有 Telegram adapter `resolveTelegramAccountConfig/resolveTelegramToken` 和 Feishu `gatewayFeishuResolveAccount` 语义。
- 如果实现中需要构造 account object，只允许补最小写入 helper；helper 输出结构必须被现有 resolver 直接识别。

redaction 规则：

- Telegram botToken：永远输出 `[redacted]`。
- Feishu appId：可输出 `cli_...` 摘要。
- Feishu appSecret：永远输出 `[redacted]`。

自动化测试：

1. 新建 Telegram account，root 中出现 `gateway.telegram.accounts.agent.botToken`。
2. 新建 Feishu account，root 中出现 `gateway.feishu.accounts.agent.appId/appSecret`。
3. 复用相同 Telegram account，result action 为 `reused`，root 内容不重复。
4. 复用相同 Feishu account，result action 为 `reused`。
5. 不带 overwrite 时不同 token/appSecret 失败。
6. 带 overwrite 时不同 token/appSecret 更新。
7. `gateway.telegram.defaultAccount` 和 `gateway.feishu.defaultAccount` 保持原值。
8. result/error 不包含 raw token/appSecret。
9. 断言 root 中没有 `agents.entries[].telegram`、`agents.entries[].feishu`、`gateway.telegram.agentAccounts`、`gateway.feishu.agentAccounts` 等新字段。
10. 用现有 Telegram/Feishu resolver 读取新写入的 account，确认不需要额外解析路径。

手工验收：

```bash
metis agents add --agent tg-demo --telegram-bot-token "123456:test_token"
metis gateway channel telegram accounts
metis agents add --agent fs-demo --feishu "cli_test:secret_test"
metis gateway channel feishu accounts
```

预期：

- account 列表里能看到对应 accountId configured。
- 输出不显示完整 token/appSecret。

完成定义：

- Telegram/Feishu 的 per-agent account 能被现有运行态 resolver 消费。
- 不破坏旧顶层配置。

### Phase 4：QQ per-account 配置补齐

目标：

- 补齐 QQ 与 Telegram/Feishu 对齐的 per-account 能力。
- 旧的顶层 `gateway.qq.appId/appSecret` 配置必须继续可用。

涉及文件：

- `src/core/config/gateway_user_settings.cj`
- `src/gateway/model/config.cj`
- `src/gateway/config/gateway_config_builder.cj`
- 建议新增：`src/gateway/channels/qq/qq_accounts.cj`
- `src/gateway/channels/qq/qq_adapter.cj`
- `src/gateway/runtime/gateway_server_methods_channels.cj`
- 对应测试文件

新增配置字段：

`QQUserSettings`：

```cangjie
public var defaultAccount: String = "default"
public var accounts: Option<JsonObject> = None
```

`QQConfig`：

```cangjie
public let accountId: String
public let defaultAccount: String
public let accounts: Option<JsonObject>
```

QQ resolver 语义：

- `gatewayQqDefaultAccountId(config)`：空值回退 `"default"`。
- `gatewayQqListAccountIds(config)`：包含 defaultAccount 和 accounts keys。
- `gatewayQqResolveAccount(config, accountId)`：
  - accountId 为空时用 defaultAccount。
  - 若 `accounts[accountId]` 存在，合并 override。
  - 若 accountId 是 default 或 accounts 为空，允许回退顶层 appId/appSecret。
  - 若 accountId 非 default、accounts 存在但找不到 account，返回 explicit missing diagnostic。
- `gatewayQqDescribeAccounts(config, runtime)`：输出 accountId/defaultAccount/enabled/configured/running/lastError/appId redacted/appSecret redacted。

复用约束：

- QQ 新增 per-account 是补齐缺失能力，不替换旧顶层 `gateway.qq.appId/appSecret`。
- QQ resolver 的函数命名、返回字段、credential source 描述尽量对齐 Feishu resolver，避免第三套概念。
- QQ adapter 仍保持 official_ws 主路径，不新增另一个 QQ adapter。
- QQ status/inspect redaction 复用或对齐现有 channel status redaction 风格。
- 如果 QQ account 缺失，错误应出现在 QQ resolver/adapter 配置诊断路径，不在 routing 层新增特殊判断。

QQ adapter 修改：

- 启动时使用 resolved config 的 appId/appSecret。
- token 请求 body 继续使用 `appId` 和 `clientSecret`，但来源是 resolved account。
- lastSendError 中不得包含 appSecret。

兼容测试：

1. 只配置顶层 appId/appSecret，QQ adapter 仍可启动。
2. 配置 `accounts.work` 且 runtime accountId 为 `work`，adapter 使用 `accounts.work`。
3. accountId 为 `missing` 且 accounts 存在时，adapter 不启动并给出 `unknown accountId` 类诊断。
4. status/inspect 不显示 appSecret。
5. 旧顶层配置和新 accounts 配置同时存在时，指定 accountId 优先，未指定时 default/top-level 兼容。
6. 测试确认没有新增第二个 QQ adapter 或第二套路由逻辑。

手工验收：

```bash
metis agents add --agent qq-demo --qqbot "10201234:secret_test"
metis gateway channel qq accounts
```

预期：

- account 列表能看到 `qq-demo`。
- appId 只显示摘要。
- appSecret 不显示。

完成定义：

- QQ per-agent account 与 Telegram/Feishu 在产品语义上对齐。
- 多个 agent 可以配置不同 QQ bot，不互相覆盖顶层凭据。

### Phase 5：自动 route binding 合并、去重与冲突处理

目标：

- credential 与 route binding 在同一条 `agents add` 中完成。
- 自动 binding 与用户显式 `--bind` 合并去重。
- 任何 binding 冲突都阻止整次创建。

涉及文件：

- `src/gateway/runtime/gateway_server_methods_agents.cj`
- `src/gateway/core/gateway_agent_route_resolver.cj`（复用，不应重写）
- `src/gateway/runtime/gateway_server_methods_agents_test.cj`

自动 binding 规则：

| credential | 自动 binding |
| --- | --- |
| `channelCredentials.telegram.accountId = tg` | `telegram:tg` |
| `channelCredentials.feishu.accountId = fs` | `feishu:fs` |
| `channelCredentials.qq.accountId = qq` | `qq:qq` |

合并规则：

1. 先收集显式 `bind`。
2. 再追加自动 binding。
3. 用 normalized binding key 去重。
4. 去重不改变显式 binding 的优先语义；只避免重复写入。
5. 调用既有 `gatewayAgentParseBindingSpecs`，保持现有 binding 格式能力。
6. 调用既有 `gatewayApplyAgentRouteBindings` 做冲突判断。

复用约束：

- 自动 binding 必须被转换成现有 `bind` specs 或现有 route binding object 后，再进入 `gatewayAgentParseBindingSpecs`/`gatewayApplyAgentRouteBindings`。
- 不允许在 credential 写入 helper 中直接修改 `bindings[]`。
- 不允许新增第二个 conflict checker；冲突必须由 `gatewayApplyAgentRouteBindings` 的现有 key/scope 规则判定。
- binding 描述输出尽量复用 `gatewayAgentBindingDescribe`。

冲突规则：

- binding 已属于同 agent：skipped。
- binding 已属于其他 agent：conflict，整个 `agents.add` 失败。
- binding 格式非法：失败，不写配置。

自动化测试：

1. `--telegram-bot-token` 自动生成 `telegram:<agentId>`。
2. `--feishu-account fs1 --feishu ...` 自动生成 `feishu:fs1`。
3. `--qqbot-account qq1 --qqbot ...` 自动生成 `qq:qq1`。
4. 显式 `--bind telegram:a` 与自动 `telegram:a` 只保留一条。
5. binding 已被其他 agent 占用时，agent 不创建、credential 不写入。
6. binding skipped 时 result 显示 skipped，但不报错。
7. 测试确认自动 binding 和手工 `agents.bind` 生成的 route binding JSON 结构一致。
8. 测试确认同一个冲突输入在 `agents.add` 和 `agents.bind` 下得到同类冲突结果。

手工验收：

```bash
metis agents add --agent all-demo \
  --telegram-bot-token "123456:test_token" \
  --feishu "cli_test:secret_test" \
  --qqbot "10201234:secret_test"
metis agents bindings --agent all-demo
```

预期：

- 三条 binding 都能看到。
- binding 描述可读。
- 没有重复 binding。

完成定义：

- 一条命令真正完成 agent + channel account + route binding。
- 冲突不会产生半成品。

### Phase 6：用户可读输出、JSON 输出与 secret redaction

目标：

- 默认输出给用户看得懂。
- `--json` 给自动化调用用，但也不能泄露 secret。
- 不允许直接把 `toJsonString()` 的原始 RPC response 打给普通用户。

涉及文件：

- `src/program/cli_local_flows.cj`
- `src/gateway/runtime/gateway_server_methods_agents.cj`
- CLI output 相关测试

Gateway result 建议结构：

```json
{
  "agentId": "zhihu-strategist",
  "name": "知乎策略师",
  "workspace": "...",
  "agentDir": "...",
  "model": "qwen/qwen3.6-plus",
  "channelAccounts": [
    {"channel": "telegram", "accountId": "zhihu-strategist", "action": "created", "token": "[redacted]"},
    {"channel": "feishu", "accountId": "zhihu-strategist", "action": "created", "appId": "cli_...", "appSecret": "[redacted]"},
    {"channel": "qq", "accountId": "zhihu-strategist", "action": "created", "appId": "1020...", "appSecret": "[redacted]"}
  ],
  "bindings": {
    "added": ["telegram:zhihu-strategist"],
    "skipped": [],
    "conflicts": []
  }
}
```

默认输出格式：

```text
Added agent: zhihu-strategist
  name: 知乎策略师
  model: qwen/qwen3.6-plus
  workspace: /Users/...
  agentDir: /Users/...
Configured channel accounts:
  - telegram:zhihu-strategist token=[redacted] created
  - feishu:zhihu-strategist appId=cli_... appSecret=[redacted] created
  - qq:zhihu-strategist appId=1020... appSecret=[redacted] created
Added bindings:
  - telegram:zhihu-strategist
  - feishu:zhihu-strategist
  - qq:zhihu-strategist
```

redaction helper 规则：

- 空值输出空字符串。
- secret/token 非空统一输出 `[redacted]`。
- appId 可显示前 4 位和 `...`，不足 4 位只显示 `[set]`。
- 错误消息只显示 channel/accountId/action，不显示 credential 原文。

复用约束：

- redaction 逻辑必须集中到 helper，不允许 CLI 输出、Gateway result、Gateway error 各自手写不同规则。
- CLI 默认输出只消费 Gateway 返回的 redacted summary，不应再读取 raw credential。
- `--json` 输出必须直接使用 Gateway redacted result；不能把原始 request params 合并进 JSON。
- 既有 `agents.bind` 的人类可读输出风格可以复用，但不能输出 raw route/config JSON。

自动化测试：

1. 默认输出不包含 `{` 开头大 JSON。
2. 默认输出包含 agentId/model/workspace/channel account/binding。
3. 默认输出不包含测试 raw secret。
4. `--json` 输出不包含测试 raw secret。
5. Gateway result 对象本身不包含 raw secret。
6. `printGatewayRpcFailure` 路径不包含 raw secret。
7. 测试证明 success JSON、default text、error text 三条路径调用同一 redaction 规则的输出格式。
8. 测试确认 CLI 没有从本地配置重新读取 raw secret 后渲染。

手工验收：

- 执行成功命令后，用户能不看 JSON 理解创建了什么。
- 执行冲突命令后，错误信息能告诉用户哪个 channel/account 冲突。

完成定义：

- CLI 与 RPC result 全链路 redacted。
- 默认输出符合此前“不能把大 JSON 扔给用户”的红线。

### Phase 7：文档、帮助与用户操作说明

目标：

- 用户能根据文档完成创建、检查、覆盖、排错。
- 文档清楚区分 agent 与 team。

涉及文件：

- `docs/user/agent-team.md` 或新增 `docs/user/agents.md`
- `src/program/cli_local_flows.cj` help text
- `develop_steps` 本文件

文档必须包含：

1. `metis agents add` 只创建单个 agent。
2. `metis agents team create` 管理多个 agent 的组合。
3. `metis onboard` 配置全局默认，与本命令无关。
4. 一条命令创建 agent + Telegram。
5. 一条命令创建 agent + Feishu。
6. 一条命令创建 agent + QQ。
7. 一条命令创建 agent + 三个 IM。
8. 如何查看：
   - `metis agents get --agent <id>`
   - `metis agents bindings --agent <id>`
   - `metis gateway channel telegram accounts`
   - `metis gateway channel feishu accounts`
   - `metis gateway channel qq accounts`
9. 如何处理 account 已存在：
   - 默认失败。
   - 使用 `--channel-overwrite` 覆盖。
10. 裸凭据风险说明：
   - 会进入 shell history。
   - 会写入本机配置文件。
   - 输出和日志会 redacted。

用户文档矩阵：

| 场景 | 用户命令 | 验收检查命令 | 必须说明的预期 |
| --- | --- | --- | --- |
| 只创建单 agent | `metis agents add --agent reviewer --name "Reviewer" --model qwen/qwen3.6-plus` | `metis agents get --agent reviewer`、`metis agents bindings --agent reviewer` | 创建单 agent，不创建 team，不新增 channel account 或 route binding |
| Telegram shortcut | `metis agents add --agent tg-writer --telegram-bot-token "123456789:fake-telegram-token"` | `metis gateway channel telegram accounts`、`metis agents bindings --agent tg-writer` | token redacted；默认 accountId 为 `tg-writer`；binding 为 `telegram:tg-writer` |
| Feishu shortcut | `metis agents add --agent feishu-writer --feishu "cli_fake_app_id:fake-feishu-secret"` | `metis gateway channel feishu accounts`、`metis agents bindings --agent feishu-writer` | appSecret redacted；account 写入 Feishu accounts；binding 为 `feishu:feishu-writer` |
| QQ shortcut | `metis agents add --agent qq-writer --qqbot "1020000000:fake-qq-secret"` | `metis gateway channel qq accounts`、`metis agents bindings --agent qq-writer` | appSecret redacted；account 写入 QQ accounts；旧顶层 QQ 配置兼容性不被破坏 |
| 三渠道 shortcut | 同一条 `metis agents add` 带 `--telegram-bot-token`、`--feishu`、`--qqbot` | 三个 channel accounts 命令和 `metis agents bindings --agent <id>` | 三个 account 和三条 binding 同一事务成功；输出不含 raw secret |
| 显式 accountId | 带 `--telegram-account`、`--feishu-account`、`--qqbot-account` | channel accounts 和 bindings | accountId 使用显式值，不再默认 agentId |
| 显式 `--bind` 去重 | 带 `--bind telegram:<id>` 和 Telegram credential | `metis agents bindings --agent <id>` | 显式 binding 与自动 binding 合并去重 |
| 已存在相同 credential | 再次配置相同 account credential | channel accounts 和 bindings | 可复用 existing account，结果标记 reused/skipped，不泄露 secret |
| 已存在不同 credential | 不带 `--channel-overwrite` | `metis agents get --agent <new-id>`、channel accounts | 命令失败；不创建新 agent；不改原 account；错误 redacted |
| 覆盖不同 credential | 带 `--channel-overwrite` | channel accounts、bindings、agent get | account 更新或在 binding 冲突时整体失败；无半写入 |
| JSON 输出 | 任一成功命令带 `--json` | 检查 stdout | JSON 可解析，包含 redacted summary，不包含 raw token/appSecret |

用户文档 redaction 规则：

| 字段 | 示例假值 | 允许展示 | 禁止展示 |
| --- | --- | --- | --- |
| Telegram `botToken` | `123456789:fake-telegram-token` | `[redacted]` | 完整 token 或 token 后缀 |
| Feishu `appSecret` | `fake-feishu-secret` | `[redacted]` | 完整 secret |
| QQ `appSecret` | `fake-qq-secret` | `[redacted]` | 完整 secret |
| Feishu/QQ `appId` | `cli_fake_app_id`、`1020000000` | 摘要如 `cli_...`、`1020...` | appSecret 拼接在同一字段里 |

文档措辞检查：

| 检查点 | 通过标准 |
| --- | --- |
| agent/team 区分 | 明确 `metis agents add` 是单 agent；`metis agents team create` 是团队模板 |
| 子命令边界 | 明确没有新增子命令，只扩展 `metis agents add` 参数 |
| 配置落点 | 明确 IM credential 写入既有 channel account 配置，binding 写入既有 route bindings |
| 事务边界 | 明确 CLI 不直接写配置，Gateway `agents.add` 统一处理 |
| 平台边界 | 明确 Metis 不自动创建 Telegram/Feishu/QQ 平台应用 |
| secret 安全 | 示例只用明显假值，提醒不要使用真实生产 secret 做验收 |
| 输出契约 | 默认输出人类可读；`--json` 也 redacted；不直接输出大 JSON 到默认人类界面 |

复用约束：

- 文档必须明确“不是新增子命令，只扩展 `metis agents add` 参数”。
- 文档必须明确“IM 凭据落在既有 channel account 配置，binding 落在既有 route bindings”。
- 文档必须明确“CLI 不直接写配置，Gateway `agents.add` 统一事务编排”。
- 文档不能教用户用多个命令模拟一命令实现作为内部实现方式；多个命令只能作为历史/手工替代路径说明。

自动化验收：

- help 文案含新增参数。
- docs 中不包含真实 secret 示例。
- docs 中不出现“自动创建 Feishu/QQ/Telegram 应用”的误导表述。
- docs 中明确写出复用原则和配置落点。

手工验收：

- 用户只读 docs 就能复制命令创建一个 agent。
- 用户能根据 docs 知道失败时检查哪个命令。

完成定义：

- 文档与 CLI help 一致。
- 文档不把此能力描述成 team 功能。

### Phase 8：自动化测试矩阵

目标：

- 用自动化测试守住解析、写入、绑定、redaction、atomicity、兼容性。

测试矩阵：

| 编号 | 测试项 | 入口 | 断言 |
| --- | --- | --- | --- |
| T1 | CLI add 无 credential 兼容 | `metis agents add --agent a` | 行为与旧逻辑一致 |
| T2 | CLI repeated bind | `--bind telegram:a --bind feishu:b` | params 中两个 bind |
| T3 | CLI Feishu pair | `--feishu cli:secret:tail` | appId/appSecret 正确 |
| T4 | CLI QQ pair | `--qqbot 1020:secret:tail` | appId/appSecret 正确 |
| T5 | CLI Telegram token | `--telegram-bot-token 123:ABC` | token 原样 |
| T6 | Gateway success all channels | `agents.add` RPC | agent、3 accounts、3 bindings 都存在 |
| T7 | Gateway duplicate same credential | `agents.add` RPC | action=reused |
| T8 | Gateway duplicate different no overwrite | `agents.add` RPC | 失败且无写入 |
| T9 | Gateway duplicate different overwrite | `agents.add` RPC | action=updated |
| T10 | Binding conflict | `agents.add` RPC | 失败且无 agent/account 写入 |
| T11 | Telegram resolver | runtime config | account botToken 可 resolved |
| T12 | Feishu resolver | runtime config | account appId/appSecret 可 resolved |
| T13 | QQ top-level compatibility | QQ adapter/config builder | 旧顶层配置仍可用 |
| T14 | QQ per-account resolver | QQ adapter/config builder | account override 生效 |
| T15 | Redaction success output | CLI/RPC | raw secret 不出现 |
| T16 | Redaction error output | CLI/RPC | raw secret 不出现 |
| T17 | Dry filesystem failure | simulated failure | 不写 root |
| T18 | No real environment | all tests | 不访问真实 `~/.metis`、真实网络 |
| R1 | CLI 单入口复用 | CLI mock Gateway client | `agents add` 只调用一次 `agents.add`，不调用 `agents.bind`/channel mutation |
| R2 | Gateway 单入口复用 | RPC method registry/测试替身 | 没有新增平行 `agents.add-with-credentials` 类 RPC |
| R3 | Binding parser 复用 | Gateway RPC test | 自动 binding 与显式 `--bind` 都走 `gatewayAgentParseBindingSpecs` 支持的结构 |
| R4 | Binding apply 复用 | Gateway RPC test | binding 冲突结果与 `gatewayApplyAgentRouteBindings` 语义一致 |
| R5 | Telegram account 结构复用 | Config snapshot + resolver test | 写入 `gateway.telegram.accounts.<id>`，现有 Telegram resolver 可读取 |
| R6 | Feishu account 结构复用 | Config snapshot + resolver test | 写入 `gateway.feishu.accounts.<id>`，`gatewayFeishuResolveAccount` 可读取 |
| R7 | QQ 兼容复用 | Config builder + adapter test | 顶层 QQ 配置仍可用，accounts 只是扩展 |
| R8 | Redaction helper 复用 | CLI/RPC output tests | success/default/json/error 使用同一 redaction 规则 |
| R9 | 配置写入路径复用 | Config manager spy/test home | 最终只通过 `MetisConfigManager.writeRoot` 写 root，不直接写用户配置文件 |
| R10 | 无新 agent credential 字段 | Config snapshot test | 不出现 `agents.entries[].telegram/feishu/qq` credential 字段 |

验收覆盖矩阵：

| 风险 | 覆盖测试 | 必须失败的反例 |
| --- | --- | --- |
| CLI 把快捷能力做成新子命令 | T1-T5、R1 | 出现 `agents setup-channel`、`agents credential` 等新入口 |
| CLI 串行调用多个 mutation 造成半成功 | R1、R9、T10、T17 | mock 记录到 `agents.bind` 或 channel config mutation |
| Gateway 写入一半配置 | T8、T10、T17、R9 | agent 已创建但 account/binding 失败后仍可见 |
| Secret 出现在默认输出 | T15、R8 | stdout/stderr 包含 `fake-telegram-token`、`fake-feishu-secret`、`fake-qq-secret` |
| Secret 出现在 JSON 输出 | T15、R8 | `--json` response 包含 raw `botToken` 或 `appSecret` |
| Secret 出现在错误路径 | T16、R8 | credential conflict 错误回显用户输入的 secret |
| Credential 写入错误位置 | R5、R6、R7、R10 | `agents.entries` 或 agent markdown 出现 IM secret 字段 |
| Binding 冲突逻辑分叉 | T10、R3、R4 | `agents.add` 与 `agents.bind` 对同一冲突给出不同结果 |
| QQ per-account 破坏旧配置 | T13、T14、R7 | 只有顶层 `qq.appId/appSecret` 的旧配置无法启动 |
| 测试污染用户环境 | T18 | 访问真实 `~/.metis`、真实 Telegram/Feishu/QQ 网络或生产 secret |

自动化与手工验收对应矩阵：

| 手工验收项 | 主要自动化测试 | 额外人工检查 |
| --- | --- | --- |
| 6.1 只创建单 agent | T1 | 默认输出不是大 JSON |
| 6.2 Telegram shortcut | T5、T6、T11、T15 | channel account inspect token redacted |
| 6.3 Feishu shortcut | T3、T6、T12、T15 | appId 摘要可读，appSecret redacted |
| 6.4 QQ shortcut | T4、T6、T13、T14、T15 | QQ accounts inspect 不泄露 appSecret |
| 6.5 三 IM 同一命令 | T6、R3、R4、R5、R6、R7 | 三条 binding 全部指向同一 agent |
| 6.6 冲突保护 | T8、T10、T16、T17 | 新 agent 不存在，原 account 未变 |
| 6.7 overwrite | T9、T10、T15 | binding 冲突时仍整体失败 |
| 6.8 显式 accountId | T6、R5、R6、R7 | accountId 不回退 agentId |
| 6.9 binding 去重 | T2、R3、R4 | bindings 列表不重复 |
| 6.10 JSON redaction | T15、R8 | JSON 可解析但不含 raw secret |

测试实现落点矩阵：

| 测试类型 | 建议文件 | 范围限制 |
| --- | --- | --- |
| CLI 参数和输出 | `src/program/cli_local_flows_agent_team_test.cj` 或同目录 focused test | 使用 mock Gateway；不访问真实 Gateway |
| Gateway RPC 和原子性 | `src/gateway/runtime/gateway_server_methods_agents_test.cj` | 使用临时 Metis home；不访问真实 `~/.metis` |
| Config builder/resolver | `src/gateway/model/config.cj`、`src/gateway/config/gateway_config_builder.cj`、QQ/Feishu/Telegram resolver 测试 | fake config only；不触发真实 channel 网络 |
| Channel status/inspect redaction | `src/gateway/runtime/gateway_server_methods_channels.cj` 相关测试 | 断言 secret 字段 redacted，不需要真实 provider |
| User-facing output contract | CLI/Gateway output tests | 默认输出不得直接打印 raw `toJsonString()` |

测试数据规则：

- 使用 `test-feishu-secret-never-visible`。
- 使用 `test-qq-secret-never-visible`。
- 使用 `123456:test-telegram-token-never-visible`。
- 每个 redaction 测试都断言这些原文不存在。

复用专项测试说明：

- R1 到 R10 是本需求的硬性测试，不是可选测试。
- 如果某个测试因为当前测试框架无法直接 spy 函数调用，则必须用可观测结果替代，例如：
  - 检查最终配置中没有新增平行字段。
  - 检查同一冲突输入在 `agents.add` 和 `agents.bind` 下得到一致冲突摘要。
  - 检查成功路径只有一次配置文件版本变化。
- 不能只用“最终能创建成功”替代复用专项测试；成功不等于复用。

执行要求：

- 不允许真实网络。
- 不允许真实 bot token。
- 不允许真实 appSecret。
- 不允许修改真实用户配置。

完成定义：

- 自动化测试覆盖成功路径、冲突路径、错误路径、兼容路径。
- redaction 测试覆盖默认输出、JSON 输出、RPC error。

### Phase 9：统一构建验证与提交前检查

目标：

- 用项目标准验证整轮变更质量。

实施内容：

执行：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm clean
cjpm build -i
cjpm test
```

提交前检查：

1. `git status --short` 不包含真实配置文件。
2. `git diff` 不包含真实 token/appSecret。
3. 新增测试没有真实网络调用。
4. 新增文档没有误导用户“Metis 自动创建 IM 平台应用”。
5. 若存在无关工作区变更，不纳入本次提交。

文档/验收补齐类变更的提交前检查：

| 检查 | 命令或审查方式 | 通过标准 |
| --- | --- | --- |
| 只改允许范围 | `git diff --name-only` | 只包含 `docs/user/...` 和本需求相关 `develop_steps/...` |
| 不改源码 | `git diff --name-only | rg '^(src|ui|assets|cjpm|package)'` | 无输出 |
| 不含生产 secret | 人工审查 `git diff`，并搜索 `token|secret|appSecret|botToken` | 只出现 fake/test/redacted 示例或字段名 |
| agent/team 边界 | 搜索 `agents add`、`agents team create` 文档段落 | 明确单 agent 与 team template 的区别 |
| 无新增子命令表述 | 搜索 `setup-channel|credential subcommand|agents credential|agents setup` | 不出现把能力写成新子命令的说明 |
| 配置落点 | 人工审查用户文档和 Phase 7 | 明确 credential 在 channel accounts，binding 在 route bindings |
| overwrite 预期 | 人工审查用户文档和手工验收 | 默认冲突失败；`--channel-overwrite` 才覆盖 |
| JSON/redaction 预期 | 人工审查 Phase 6/7/8 和用户文档 | 默认输出、`--json`、错误输出都要求 redacted |
| 不使用真实生产 secret | 人工审查示例 | 示例值必须是 `fake`、`test` 或 `[redacted]` 语义 |

文档-only 验证说明：

- 如果本次提交只补文档与验收矩阵、没有修改 Cangjie 源码或构建配置，可以不运行完整 `cjpm clean && cjpm build -i && cjpm test`，但最终回复必须明确说明未运行的原因。
- 如果同一提交包含任何源码、CLI help、Gateway runtime、config、Control UI 或测试代码变更，必须执行本 phase 的完整构建与测试命令。
- 文档-only 提交仍必须完成 `git diff` 审查，确认没有真实 credential、没有源码改动、没有跨职责文件。

复用检查：

1. `git diff` 中不应出现新增子命令注册。
2. `git diff` 中不应出现 CLI 直接写 `gateway.telegram/feishu/qq` 配置。
3. `git diff` 中不应出现第二套 binding conflict checker。
4. `git diff` 中不应出现 Telegram/Feishu 第二套 account resolver。
5. `git diff` 中不应出现 `agents.entries` 下保存 IM secret/token 的字段。
6. `git diff` 中如出现 QQ account resolver，必须能说明它是在补齐 QQ 缺失能力，且旧顶层 QQ 配置测试通过。
7. `git diff` 中如出现 redaction 逻辑，必须是集中 helper，而不是多个输出点各自拼接 `[redacted]`。

验收项：

| 变更类型 | 必须验收项 |
| --- | --- |
| 源码/测试/help 变更 | `cjpm clean`、`cjpm build -i`、`cjpm test` 成功；复用专项测试 R1 到 R10 全部通过，或有明确等价可观测测试说明 |
| 文档/验收矩阵变更 | `git status --short` 只包含本需求相关文档；`git diff` 无真实 token/appSecret；文档明确 agent/team 边界、无新增子命令、配置落点、overwrite、JSON/redaction 预期 |
| 混合变更 | 同时满足源码/测试/help 与文档/验收矩阵两类验收 |

完成定义：

- 主工作区构建和测试通过。
- 本地提交 message 描述 agent shortcut channel credential setup，不提无关项目。

## 6. 手工验收清单（细化版）

### 6.1 只创建单 agent

操作：

```bash
metis agents add --agent reviewer --name "Reviewer" --model qwen/qwen3.6-plus
metis agents get --agent reviewer
```

验收标准：

- agent 创建成功。
- agent 有独立 workspace、agentDir、sessionsDir。
- 不新增任何 channel account。
- 不新增 route binding。
- 默认输出不是大 JSON。
- `metis agents get --agent reviewer` 能看到 model/workspace/agentDir。
- `metis agents bindings --agent reviewer` 为空或显示无 binding。

### 6.2 创建 agent 并绑定 Telegram

操作：

```bash
metis agents add \
  --agent tg-writer \
  --name "Telegram Writer" \
  --model qwen/qwen3.6-plus \
  --telegram-bot-token "123456789:test_token"

metis agents bindings --agent tg-writer
metis gateway channel telegram accounts
```

验收标准：

- 输出显示 `Configured channel accounts: telegram:tg-writer token=[redacted]`。
- bindings 中存在 `telegram:tg-writer -> tg-writer`。
- Telegram account inspect 中显示 configured，但不显示完整 token。
- `metis agents get --agent tg-writer` 能看到 agent。
- `metis agents bindings --agent tg-writer` 能看到 Telegram binding。
- 终端输出中不出现 `123456789:test_token`。

### 6.3 创建 agent 并绑定 Feishu

操作：

```bash
metis agents add \
  --agent feishu-writer \
  --name "Feishu Writer" \
  --model qwen/qwen3.6-plus \
  --feishu "cli_test:secret_test"

metis agents bindings --agent feishu-writer
metis gateway channel feishu accounts
```

验收标准：

- 输出显示 `feishu:feishu-writer appId=cli_... appSecret=[redacted]`。
- bindings 中存在 `feishu:feishu-writer -> feishu-writer`。
- Feishu account inspect 中显示 configured，但不显示完整 appSecret。
- `metis agents get --agent feishu-writer` 能看到 agent。
- `metis agents bindings --agent feishu-writer` 能看到 Feishu binding。
- 终端输出中不出现 `secret_test`。

### 6.4 创建 agent 并绑定 QQ Bot

操作：

```bash
metis agents add \
  --agent qq-writer \
  --name "QQ Writer" \
  --model qwen/qwen3.6-plus \
  --qqbot "10201234:secret_test"

metis agents bindings --agent qq-writer
metis gateway channel qq accounts
```

验收标准：

- 输出显示 `qq:qq-writer appId=1020... appSecret=[redacted]`。
- bindings 中存在 `qq:qq-writer -> qq-writer`。
- QQ account inspect 中显示 configured，但不显示完整 appSecret。
- `metis agents get --agent qq-writer` 能看到 agent。
- `metis agents bindings --agent qq-writer` 能看到 QQ binding。
- 终端输出中不出现 `secret_test`。

### 6.5 一条命令同时配置三个 IM 渠道

操作：

```bash
metis agents add \
  --agent zhihu-strategist \
  --name "知乎策略师" \
  --model qwen/qwen3.6-plus \
  --feishu "cli_test:secret_test" \
  --qqbot "10201234:secret_test" \
  --telegram-bot-token "123456789:test_token"

metis agents bindings --agent zhihu-strategist
```

验收标准：

- agent 创建成功。
- Telegram、Feishu、QQ 三个 account 都创建成功。
- 三条 route binding 都存在。
- 默认输出不出现大 JSON。
- 默认输出和 `--json` 输出都不包含完整 secret/token。
- `metis gateway channel telegram accounts` 能看到 `zhihu-strategist`。
- `metis gateway channel feishu accounts` 能看到 `zhihu-strategist`。
- `metis gateway channel qq accounts` 能看到 `zhihu-strategist`。

### 6.6 已存在 account 的冲突保护

操作：

```bash
metis agents add \
  --agent another \
  --name "Another" \
  --feishu-account zhihu-strategist \
  --feishu "cli_test:different_secret"
```

验收标准：

- 命令失败。
- 错误说明 `feishu:zhihu-strategist` 已存在且凭据不同。
- 不创建 agent `another`。
- 不修改原有 account。
- 不新增 binding。
- 错误输出不出现 `different_secret`。
- `metis agents get --agent another` 返回不存在。

### 6.7 显式覆盖 account

操作：

```bash
metis agents add \
  --agent another \
  --name "Another" \
  --feishu-account zhihu-strategist \
  --feishu "cli_test:different_secret" \
  --channel-overwrite
```

验收标准：

- 命令成功或在 binding 已被其他 agent 占用时明确失败。
- 如果成功，account 被覆盖，输出显示 updated/redacted。
- 如果 route binding 冲突，配置不部分写入。
- 成功时，输出不出现 `different_secret`。
- 失败时，`another` 不存在，原 account 不被覆盖。

### 6.8 显式 accountId 与默认 agentId

操作：

```bash
metis agents add \
  --agent explicit-demo \
  --name "Explicit Demo" \
  --telegram-account bot-a \
  --telegram-bot-token "123456:test_token"

metis agents bindings --agent explicit-demo
metis gateway channel telegram accounts
```

验收标准：

- Telegram account ID 是 `bot-a`，不是 `explicit-demo`。
- binding 是 `telegram:bot-a -> explicit-demo`。
- 输出不出现完整 token。

### 6.9 显式 `--bind` 与自动 binding 去重

操作：

```bash
metis agents add \
  --agent dedupe-demo \
  --bind telegram:dedupe-demo \
  --telegram-bot-token "123456:test_token"

metis agents bindings --agent dedupe-demo
```

验收标准：

- 只出现一条 `telegram:dedupe-demo` binding。
- 输出可以显示 added/skipped，但不能重复创建 binding。

### 6.10 JSON 输出 redaction

操作：

```bash
metis agents add \
  --agent json-demo \
  --telegram-bot-token "123456:test_token" \
  --json
```

验收标准：

- 输出是 JSON。
- JSON 中包含 `agentId=json-demo`。
- JSON 中包含 channel account summary。
- JSON 中不包含 `123456:test_token`。

## 7. 不做的事情

- 不新增新的 agent credential setup 子命令。
- 不在 CLI 里串行调用 `agents.add`、`agents.bind`、channel config mutation 来模拟一命令能力。
- 不自动创建 Feishu 开放平台应用。
- 不自动创建 QQ Bot。
- 不自动创建 Telegram Bot。
- 不把 channel credential 写入 agent markdown 文件。
- 不把 channel credential 写入 `agents.entries`。
- 不新增第二套 route binding parser、route binding apply、route conflict checker。
- 不新增第二套 Telegram/Feishu account resolver。
- 不绕过 `MetisConfigManager.writeRoot` 直接写用户配置文件。
- 不把凭据写入 logs、CLI 默认输出、RPC result 明文。
- 不把单 agent 创建强行包装成 team 创建。

## 8. 预计工作量

如果只做 Telegram/Feishu，一天内可以完成；但本方案要求 QQ per-account 与完整 redaction/atomic tests，因此合理工作量为 2 到 3 个工程日。

拆分：

- CLI 与 RPC schema：0.5 天。
- Telegram/Feishu account 写入与 binding 编排：0.5 天。
- QQ per-account resolver 与兼容测试：0.75 到 1 天。
- 输出 redaction、文档、完整测试：0.5 到 1 天。

## 9. 实施顺序建议

必须按 Phase 1 到 Phase 9 顺序推进。尤其是 QQ per-account 不能跳过，否则用户用 `--qqbot` 创建第二个 agent 时会覆盖全局 QQ 凭据，破坏“每个 agent 单独配置 QQ Bot”的目标。

实现前如果发现当前文档没有覆盖的新架构点，应先补本文档，再写代码。

实现过程中每个 phase 都要先回答一个问题：这个逻辑有没有现有函数、现有配置结构、现有测试可以复用。如果答案是有，就必须复用；如果答案是没有，新增代码必须是对既有路径的最小扩展，并补 R1 到 R10 中对应的复用专项测试或等价可观测测试。
