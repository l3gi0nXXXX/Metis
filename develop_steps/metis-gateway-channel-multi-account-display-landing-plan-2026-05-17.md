# Metis Gateway Channel 多账户展示补齐方案

日期：2026-05-17

## 1. 背景与目标

用户在同一个 Metis 实例中配置了两个 Telegram bot 后，执行：

```bash
metis gateway channel get telegram
```

当前输出只展示 `Channel: telegram`、通道启用状态、网络、媒体和动作能力，无法说明这是哪个 Telegram bot，也无法列出已配置的多个 bot/account。因此用户无法判断：

- 当前 Telegram channel 下到底有哪些 account/bot。
- 哪个 account 是默认 account。
- 每个 account 是否已经配置 token。
- `gateway channel runtime telegram` 展示的是运行时 adapter 状态，还是配置中的 bot 状态。
- `agents bindings` 中的 `telegram:<accountId>` 应该和哪个 bot 对应。

本方案目标是补齐 **Gateway channel 多账户的人类可读展示**，先制定方案，不修改代码。

## 2. 不突破架构边界的原则

| 原则 | 结论 | 来源依据 | 验收要求 |
|---|---|---|---|
| 只做展示补齐，不重写配置逻辑 | 多账户展示应复用现有 `channels.get`、`channels.runtime` 返回的结构化字段；不新增第二套 Telegram/Feishu/QQ account 读取逻辑。 | Metis `gatewayChannelGetJson` 已把 Telegram `accountInspect` 放入 channel JSON：`src/gateway/runtime/gateway_server_methods_channels.cj:923-927`；Telegram account inspect 由 `gatewayTelegramAccountInspectJson` 构造：`src/gateway/runtime/gateway_server_methods_channels.cj:1122-1149`。 | 实现后代码中账号展示只消费 RPC 返回对象；不直接重新读取 `GatewayUserSettings.telegram.accounts` 或真实配置文件。 |
| 默认输出必须人类可读 | 默认 CLI 不能把 raw JSON 丢给用户；账号列表必须是文本摘要。 | Metis 当前统一入口是 `gatewayPrintCommandOutput` -> `gatewayFormatCommandOutput`：`src/gateway/runtime/gateway_cli_human_output.cj:678-722`；用户此前已明确 raw JSON 是红线。 | 默认执行 `metis gateway channel get telegram`，输出中不能出现裸 `{`、`"accountInspect"`、`"accounts"` 等 JSON 结构字段。 |
| channel 状态与 account 状态必须区分 | `gateway channel get telegram` 是通道级详情，但必须附带 account 列表；`gateway channel runtime telegram` 是运行时 adapter 状态，不能被解释为“全部 bot 配置状态”。 | Metis runtime 渲染当前只显示 runtime accounts：`src/gateway/runtime/gateway_cli_human_output.cj:242-269`；`channels.runtime` 返回 `accounts/defaultAccountId`，并在 Telegram 下额外返回 `telegram.accountInspect`：`src/gateway/runtime/gateway_server_methods_channels.cj:2545-2566`、`1227-1268`。 | 两个命令的输出标题和说明不同：`get` 明确是 configured accounts；`runtime` 明确是 live adapter state。 |
| 对齐 OpenClaw 的 account-first 展示 | 多账户场景必须展示 `channel + accountId`，不能只显示 channel。 | OpenClaw `channels list` 按 `plugin.config.listAccountIds(cfg)` 遍历账号并逐行展示：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels/list.ts:137-150`；OpenClaw `channels status` 也逐账号渲染：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels/status.ts:97-169`。 | Metis 默认输出至少包含 `telegram/<accountId>` 或等价清晰格式；两个 bot 时必须出现两行账号摘要。 |
| 不能泄露凭证 | token/appSecret 只能展示来源、是否配置、是否继承，不展示明文。 | Metis Telegram inspect row 只放 `tokenSource/hasBotToken/hasTokenFile`，不放 token 明文：`src/gateway/runtime/gateway_server_methods_channels.cj:1091-1118`；现有测试断言 inspect 不包含 `secret-main-token`：`src/gateway/runtime/gateway_server_methods_channels_test.cj:729-736`。 | 单元测试和手工验收必须覆盖 fake token 不出现在 stdout/stderr。 |
| 不能只修 Telegram | Feishu、QQ 也已经有 `accountInspect`；展示逻辑应通用读取 `accountInspect.accounts`。 | Feishu channel JSON 放入 `accountInspect`：`src/gateway/runtime/gateway_server_methods_channels.cj:754-766`；QQ channel JSON 放入 `accountInspect`：`src/gateway/runtime/gateway_server_methods_channels.cj:778-782`；QQ 测试覆盖 secret 脱敏：`src/gateway/runtime/gateway_server_methods_channels_test.cj:897-909`。 | `metis gateway channel get feishu`、`metis gateway channel get qq` 在有多 account 时也能显示账号列表。 |

## 3. OpenClaw 参考结论

### 3.1 OpenClaw 的多账户展示方式

OpenClaw 没有把多账号状态压缩成一条 `Channel: telegram`。它的展示逻辑是 account-first：

1. `channels list`：
   - 通过 `plugin.config.listAccountIds(cfg)` 获取每个 channel 的 accountId。
   - 对每个 account 调 `buildChannelAccountSnapshot`。
   - 通过 `formatAccountLine` 输出 `Channel accountId: configured/token/...`。
   - 证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels/list.ts:54-88`、`137-150`。

2. `channels status`：
   - Gateway reachable 时，消费 `payload.channelAccounts`。
   - 每个 account 独立输出 enabled/configured/running/connected/token source/bot username/probe/audit/error。
   - 证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels/status.ts:97-169`。

3. account label：
   - `formatChannelAccountLabel` 把 channel label 和 account label 合成一个用户可读名字。
   - 证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels/shared.ts:43-70`。

4. 测试保护：
   - OpenClaw 测试覆盖新增非 default Telegram account：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels.adds-non-default-telegram-account.test.ts:372-377`。
   - OpenClaw 测试覆盖旧单账号配置迁移到 `accounts.default`：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels.adds-non-default-telegram-account.test.ts:379-431`。
   - OpenClaw 测试覆盖 status 输出中出现 `Telegram default`：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels.adds-non-default-telegram-account.test.ts:676-686`。
   - OpenClaw 测试覆盖 probe bot username 输出：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/commands/channels.adds-non-default-telegram-account.test.ts:754-766`。

### 3.2 OpenClaw 给 Metis 的直接约束

| OpenClaw 行为 | Metis 应采用的行为 | 验收要求 |
|---|---|---|
| 多账户展示以 accountId 为基本单位 | `gateway channel get <id>` 不能只显示 channel 级摘要，要追加 `Accounts` 段。 | 输出中能看出 `telegram/default`、`telegram/work` 或同等格式。 |
| 展示 credential source，不展示 secret | Metis 只展示 `account-botToken`、`account-tokenFile`、`global-inherited`、`missing` 等来源。 | fake token 字符串不出现在输出。 |
| status/runtime 可以显示 probe、bot username 等 live 信息 | Metis runtime 保持 live adapter 语义，可显示 runtime row；如果没有 live 信息，不伪造 bot username。 | 未执行 live probe 时输出不声称 bot 可用，只显示配置状态和 runtime state。 |
| binding 使用 `channel:accountId` | Metis channel 输出应帮助用户把 accountId 和 `agents bindings` 联系起来。 | 输出中提示 `Route binding key: telegram:<accountId>` 或在 account 行中展示 `binding=telegram:<accountId>`。 |

## 4. Metis 当前事实

### 4.1 数据层已经具备 accountInspect

| 通道 | 当前数据来源 | 已有字段 | 证据 |
|---|---|---|---|
| Telegram | `gatewayTelegramAccountInspectJson` | `defaultAccountId`、`tokenRedacted`、`accounts[]`、`accountId`、`defaultAccount`、`configured`、`tokenSource`、`hasBotToken`、`hasTokenFile`、`allowFromCount`、`groupAllowFromCount`、override 标记、`approvedSenderCount` | `src/gateway/runtime/gateway_server_methods_channels.cj:1091-1149` |
| Feishu | `gatewayFeishuAccountInspectJson` | `defaultAccountId`、`accounts[]`、`credentialSource`、secret 脱敏字段、group policy 相关字段 | `src/gateway/runtime/gateway_server_methods_channels.cj:511-560`、`754-766` |
| QQ | `gatewayQqDescribeAccounts` | `defaultAccountId`、`accounts[]`、脱敏 appId/appSecret 摘要 | `src/gateway/runtime/gateway_server_methods_channels.cj:778-782`、`src/gateway/runtime/gateway_server_methods_channels_test.cj:897-909` |

结论：多账户展示不需要新增配置读取能力，应该消费现有 `channel.accountInspect`。

验收项：

- `gatewayChannelGetJson(user, "telegram")` 在测试中仍包含 `accountInspect`。
- 多账号 Telegram 测试中 `defaultAccountId=main`、`accounts` 包含 `main/work`、不包含 token 明文。
- Feishu、QQ 的 `accountInspect` 继续通过原测试。

### 4.2 缺口在 CLI 人类可读渲染

当前 `cliRenderChannelGet` 只输出：

- `Channel`
- `Enabled/configured/mode`
- `Network`
- `Media`
- `Directory targets`
- `Enabled actions`

证据：`src/gateway/runtime/gateway_cli_human_output.cj:296-330`。

它没有读取：

- `channel.defaultAccountId`
- `channel.accountInspect.defaultAccountId`
- `channel.accountInspect.accounts`
- account 行中的 `accountId/defaultAccount/configured/tokenSource/credentialSource`

结论：用户执行 `metis gateway channel get telegram` 时看不到两个 bot 是当前实现缺口，不是用户配置问题。

验收项：

- 新增测试：输入带两个 Telegram account 的 `channels.get` JSON，`gatewayFormatCommandOutput` 输出包含两个 accountId。
- 新增测试：输出不包含 `"accountInspect"`、`"accounts"`、`{`。
- 新增测试：输出不包含 fake token。

### 4.3 runtime 输出不是配置列表

当前 `cliRenderChannelsRuntime` 从 `result.accounts` 或 `result.runtime.accounts` 读取运行时账号行，并输出 running、phase、pull/inbound/send 计数。

证据：`src/gateway/runtime/gateway_cli_human_output.cj:242-269`。

`channels.runtime` 会返回：

- `accounts`
- `defaultAccountId`
- `summary`
- `telegram.accountInspect`

证据：`src/gateway/runtime/gateway_server_methods_channels.cj:2545-2566`、`1227-1268`。

结论：`gateway channel runtime telegram` 应继续表示 live adapter runtime，但应补充说明“这是运行时状态，不是配置账号完整列表”；如果响应中有 `telegram.accountInspect`，可以追加“Configured accounts”摘要，避免用户把 runtime 中的一行误解为只有一个 bot。

验收项：

- `runtime` 默认输出标题仍是 `Channel runtime: telegram`。
- 输出说明包含 `runtime rows are live adapter state` 或中文等价说明。
- 如果 `telegram.accountInspect.accounts` 有两个账号，runtime 输出能追加 configured account count/default account。
- 不把未启动的账号误报为 running。

## 5. 目标用户体验

### 5.1 `gateway channel get telegram` 目标输出

示例：

```text
Channel: telegram
Enabled: true  configured=true  mode=polling
Network: apiRoot=https://api.telegram.org proxy=true envProxy=false
Media: download=true maxBytes=20971520 localSend=true urlSend=false
Directory targets: 1
Enabled actions: sendMessage, photo, document, audio, voice, video, reactions
Accounts: 2  default=writer  credentials=redacted
  - telegram/writer [default]: configured=true token=account-botToken allow=0 groupAllow=0 approvedSenders=0 overrides=none binding=telegram:writer
  - telegram/reviewer: configured=true token=account-botToken allow=0 groupAllow=0 approvedSenders=0 overrides=none binding=telegram:reviewer
Meaning: this command shows configured channel accounts; use `metis gateway channel runtime telegram` for live adapter state.
```

字段说明：

| 字段 | 含义 | 来源依据 | 验收要求 |
|---|---|---|---|
| `Accounts: <count>` | 账号数量 | `accountInspect.count` 或 `accounts.size()`；来源 `gatewayTelegramAccountInspectJson` | 两个 bot 时显示 2。 |
| `default=<id>` | 默认 accountId | `accountInspect.defaultAccountId`；来源 `src/gateway/runtime/gateway_server_methods_channels.cj:1124-1129` | defaultAccount 为 writer 时显示 writer。 |
| `telegram/<accountId>` | channel + accountId | OpenClaw `formatChannelAccountLabel` 使用 channel + account label；Metis routing binding 使用 `channel:accountId`。 | 用户能直接把 accountId 对应到 `telegram:<accountId>` binding。 |
| `[default]` | 当前默认账号标记 | row.defaultAccount | 只有默认账号行出现。 |
| `configured=true/false` | 凭证是否可用 | row.configured | 未配置 token 的账号显示 false，不说 bot 可用。 |
| `token=<source>` | token 来源 | row.tokenSource | 只出现来源，不出现 token。 |
| `allow/groupAllow` | allowlist 数量 | row.allowFromCount、row.groupAllowFromCount | 数量正确。 |
| `approvedSenders` | pairing 已批准 sender 数量 | row.approvedSenderCount | 读取测试隔离目录，不读真实用户目录。 |
| `overrides` | 是否有 account 级 media/network/direct/dms/groups 覆盖 | row.hasMediaOverride 等 | 有覆盖时显示 `media,network`；无覆盖显示 `none`。 |
| `binding=telegram:<accountId>` | 用户配置 `agents bind` 时应使用的键 | OpenClaw docs 明确绑定使用 `telegram:ops`：`/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/cli/agents.md:52-76` | 每行都有 binding key。 |

### 5.2 `gateway channel get feishu/qq` 目标输出

同一套 `Accounts` 段也应用于 Feishu、QQ：

```text
Accounts: 2  default=tenant-a  credentials=redacted
  - feishu/tenant-a [default]: configured=true credential=account appId=cli***123 binding=feishu:tenant-a
  - feishu/tenant-b: configured=false credential=missing binding=feishu:tenant-b
```

QQ 示例：

```text
Accounts: 2  default=work  credentials=redacted
  - qq/work [default]: configured=true appId=998***665 binding=qq:work
  - qq/backup: configured=false binding=qq:backup
```

验收要求：

- 同一个 renderer 能处理 Telegram、Feishu、QQ。
- channel 没有 `accountInspect` 时不报错，保持旧输出。
- secret 字段只显示脱敏摘要。

### 5.3 `gateway channel runtime telegram` 目标输出

示例：

```text
Channel runtime: telegram
Meaning: runtime rows are live adapter state; configured accounts are listed separately when available.
Default account: writer
Runtime accounts:
  - telegram/writer: running=true phase=running pull=12 inbound=3 sendOk=3 sendFail=0
Configured accounts: 2  default=writer
  - telegram/writer [default]: configured=true token=account-botToken binding=telegram:writer
  - telegram/reviewer: configured=true token=account-botToken binding=telegram:reviewer
```

结论：

- runtime 行继续展示 live adapter 状态。
- configured accounts 只展示配置摘要，不能把它们标成 running。
- 如果 runtime 没有 `accountInspect`，只显示 live adapter state。

## 6. 分阶段落地计划

### Phase 0：冻结事实与输出契约

目标：

- 在方案和测试中固定“channel-level get + account list”的语义。
- 明确 `runtime` 是 live adapter state，不是配置账号完整状态。

实施内容：

1. 在本方案基础上，后续实现前再次确认涉及文件：
   - `src/gateway/runtime/gateway_cli_human_output.cj`
   - `src/gateway/runtime/gateway_cli_human_output_test.cj`
   - `src/gateway/runtime/gateway_server_methods_channels_test.cj`
   - `docs/user/agent-team.md`
   - `develop_steps/metis-agent-team-series-24-manual-test-checklist-2026-05-17.md`
2. 不改 Gateway config schema。
3. 不新增真实网络测试。

依据：

- OpenClaw 已采用 account-first 展示：`openclaw/src/commands/channels/list.ts:137-150`。
- Metis 数据层已有 `accountInspect`：`src/gateway/runtime/gateway_server_methods_channels.cj:923-927`。

验收项：

- 方案文档存在于 `develop_steps/metis-gateway-channel-multi-account-display-landing-plan-2026-05-17.md`。
- 文档列出 OpenClaw 和 Metis 源码依据。
- 未修改业务代码。

### Phase 1：补齐账号摘要渲染 helper

目标：

- 在 `gateway_cli_human_output.cj` 中新增可复用的 account inspect 渲染逻辑。
- 不把 Telegram 字段硬编码成唯一场景，优先通用处理 `accountInspect.accounts`。

建议实现：

1. 新增私有 helper，例如：
   - `cliRenderChannelAccountInspect(channelId: String, channel: JsonObject): ArrayList<String>`
   - `cliRenderChannelAccountRow(channelId: String, row: JsonObject): String`
   - `cliAccountCredentialSummary(row: JsonObject): String`
   - `cliAccountOverrideSummary(row: JsonObject): String`
2. 输入只来自 `channel.accountInspect`。
3. 对公共字段统一处理：
   - `accountId`
   - `defaultAccount`
   - `configured`
   - `enabled`
   - `tokenSource`
   - `credentialSource`
   - `botTokenSource`
   - `appTokenSource`
   - `hasBotToken`
   - `hasTokenFile`
   - `allowFromCount`
   - `groupAllowFromCount`
   - `approvedSenderCount`
4. 对可选脱敏字段做安全展示：
   - `appId` 如果已经是脱敏值，可以显示。
   - `appSecret`、`botToken`、`token` 等明文字段即使意外出现也不打印。
5. 如果 `accountInspect.tokenRedacted=true` 或 `redacted=true`，在 `Accounts` 标题显示 `credentials=redacted`。

依据：

- Metis Telegram row 字段来自 `src/gateway/runtime/gateway_server_methods_channels.cj:1091-1118`。
- Feishu/QQ 也使用 `accountInspect.accounts` 结构，测试覆盖多账号和脱敏：`src/gateway/runtime/gateway_server_methods_channels_test.cj:739-909`。
- OpenClaw `formatAccountLine` 把 account snapshot 转成一行摘要：`openclaw/src/commands/channels/list.ts:54-88`。

验收项：

- Helper 不访问配置文件、不访问 `GatewayUserSettings`。
- Helper 对缺失字段容错：没有 `accountInspect` 时返回空行。
- Helper 对未知 channel/plugin 也可用，只要有 `accountInspect.accounts`。
- 单元测试覆盖一个仅有最小字段的 account row。
- 单元测试覆盖意外出现 `botToken` 或 `appSecret` 字段时不打印。

### Phase 2：增强 `gateway channel get <id>` 输出

目标：

- `metis gateway channel get telegram` 默认展示配置账号列表。
- 多 bot/account 时，用户能直接看出每个 accountId 和 default account。

建议实现：

1. 在 `cliRenderChannelGet` 原有输出之后追加 `Accounts` 段。
2. 若 `accountInspect.accounts` 为空：
   - 不追加账号段，保持旧行为。
3. 若 `accountInspect.accounts` 非空：
   - 输出 `Accounts: <count> default=<defaultAccountId> credentials=redacted`。
   - 每行格式使用 `channelId/accountId`。
   - 默认账号追加 `[default]`。
   - 每行追加 `binding=<channelId>:<accountId>`。
4. Telegram 行中优先展示：
   - `configured`
   - `token=<tokenSource>`
   - `allow`
   - `groupAllow`
   - `approvedSenders`
   - `overrides`
5. Feishu/QQ 行中展示：
   - `configured`
   - `credential=<credentialSource>` 或 `token/app/bot source`
   - 已脱敏 appId 摘要（如果存在）
   - `binding=<channelId>:<accountId>`
6. 追加解释行：
   - `Meaning: this command shows configured channel accounts; use metis gateway channel runtime <id> for live adapter state.`

依据：

- 当前 `cliRenderChannelGet` 未渲染账号：`src/gateway/runtime/gateway_cli_human_output.cj:296-330`。
- OpenClaw docs 明确 `channels status --probe` 是 per-account live 检查：`openclaw/docs/cli/channels.md:31-40`。
- OpenClaw routing 使用 `telegram:ops`：`openclaw/docs/cli/agents.md:52-76`。

验收项：

- 输入两个 Telegram accounts 的 `channels.get` JSON，输出包含：
  - `Accounts: 2`
  - `default=writer`
  - `telegram/writer [default]`
  - `telegram/reviewer`
  - `binding=telegram:writer`
  - `binding=telegram:reviewer`
- 输出不包含：
  - fake token
  - `"accountInspect"`
  - `"accounts"`
  - raw `{`
- 单账号时仍显示 `Accounts: 1`，避免用户误以为 command 不支持 account。
- 没有 `accountInspect` 的 plugin channel 仍能正常展示通道基础信息。

### Phase 3：增强 `gateway channel runtime <id>` 输出语义

目标：

- 避免用户把 runtime 中的一条 `telegram/default` 误认为“只配置了一个 bot”。
- 保留 live adapter state 和 configured account list 的边界。

建议实现：

1. 修改 `cliRenderChannelsRuntime` 的说明行：
   - 当前：`Meaning: running=live adapter process/task...`
   - 新增：`Runtime rows are live adapter state, not the full configured account list.`
2. 输出 `Default account: <defaultAccountId>`。
3. 把 runtime 行标题改为 `Runtime accounts:`。
4. 如果 `result.<channelId>.accountInspect` 存在，例如 `result.telegram.accountInspect`：
   - 追加 `Configured accounts` 段。
   - 复用 Phase 1 的 account inspect renderer。
5. 若 runtime accounts 为空但 configured accounts 存在：
   - 明确输出 `Runtime accounts: none registered`。
   - 仍显示 configured accounts。

依据：

- Metis runtime result 已返回 `defaultAccountId` 和 `telegram.accountInspect`：`src/gateway/runtime/gateway_server_methods_channels.cj:2545-2566`、`1227-1268`。
- 当前 runtime renderer 只消费 `accounts`，不消费 `defaultAccountId/accountInspect`：`src/gateway/runtime/gateway_cli_human_output.cj:242-269`。

验收项：

- `channels.runtime` 测试 JSON 中 `accounts` 只有 default，但 `telegram.accountInspect.accounts` 有 `writer/reviewer` 时，输出必须同时显示：
  - `Runtime accounts:`
  - runtime 中的实际一行
  - `Configured accounts: 2`
  - `telegram/writer`
  - `telegram/reviewer`
- 没有 running 的账号不能显示 `running=true`。
- 输出不包含 raw JSON。

### Phase 4：补齐测试矩阵

目标：

- 用自动化测试保护“多账号输出可读、脱敏、语义清晰”。

测试文件：

- `src/gateway/runtime/gateway_cli_human_output_test.cj`
- 必要时补充 `src/gateway/runtime/gateway_server_methods_channels_test.cj`

建议测试用例：

| 用例 | 输入 | 预期 |
|---|---|---|
| `formatsTelegramChannelGetWithMultipleAccounts` | `channels.get` JSON，Telegram 有 writer/reviewer 两个 account | 输出包含两行 account 和 default 标记。 |
| `redactsTelegramChannelGetAccountSecrets` | JSON 中故意放 fake `botToken` | 输出不包含 fake token。 |
| `formatsFeishuChannelGetWithAccounts` | Feishu accountInspect 有 tenant-a/tenant-b | 输出包含 `feishu/tenant-a`、`feishu/tenant-b`。 |
| `formatsQqChannelGetWithAccounts` | QQ accountInspect 有 work/backup | 输出包含 `qq/work`、`qq/backup`，不包含 appSecret。 |
| `keepsPluginChannelGetWithoutAccountInspectStable` | plugin channel 没有 accountInspect | 旧通道摘要仍输出，无异常。 |
| `formatsChannelRuntimeWithConfiguredAccountsSeparately` | `channels.runtime` JSON 同时含 runtime accounts 和 `telegram.accountInspect` | 输出区分 Runtime accounts 与 Configured accounts。 |
| `channelGetDefaultOutputHasNoRawJson` | 任一多账号 JSON | 输出不含 `{` 和 `"accounts"`。 |

依据：

- 现有 human output 测试已放在 `gateway_cli_human_output_test.cj`，并已有“无 raw JSON”模式：`src/gateway/runtime/gateway_cli_human_output_test.cj:7-79`。
- 现有 channel 数据测试已覆盖 Telegram/Feishu/QQ account inspect：`src/gateway/runtime/gateway_server_methods_channels_test.cj:680-736`、`739-909`。

验收项：

- `cjpm test -j 1` 全部通过。
- 新增测试不访问真实 `~/.metis`、真实 Telegram、真实 token。
- 测试 fake secret 不出现在 stdout 对应字符串中。

### Phase 5：修正文档与手工验收清单

目标：

- 不再用 `gateway channel get telegram` 的旧输出验收“某个 bot 状态”。
- 手工测试文档必须明确每条命令看到什么、如何判断通过。

涉及文档：

- `docs/user/agent-team.md`
- `develop_steps/metis-agent-team-series-24-manual-test-checklist-2026-05-17.md`
- 必要时补充 `docs/user/telegram.md` 多账号章节。

建议修改：

1. 将手工验收中所有 `gateway channel get telegram` 的验收标准改为：
   - 必须看到 `Accounts` 段。
   - 必须看到对应 accountId。
   - 必须看到 default account。
   - 必须看到 `binding=telegram:<accountId>`。
   - 不得看到 token 明文。
2. 对 runtime 命令写清楚：
   - `gateway channel runtime telegram` 看的是运行时 adapter 是否注册/运行。
   - 它不是配置账号唯一来源。
3. 对多 bot 验收写清楚：
   - 新增两个 fake account。
   - 执行 `gateway channel get telegram`。
   - 通过 `agents bindings --agent <agent>` 验证 route binding。

依据：

- 当前 manual checklist 多处使用 `gateway channel get telegram` 作为 channel/account 验收，但旧输出不能区分多个 bot：`develop_steps/metis-agent-team-series-24-manual-test-checklist-2026-05-17.md:285-288`、`393`。
- OpenClaw docs 明确 accountId 与 binding 关系：`openclaw/docs/cli/agents.md:62-76`。

验收项：

- 文档中不再出现“`gateway channel get telegram` 显示通道 configured 即可通过多 bot 验收”这种标准。
- 每个多账号手工验收项都包含：
  - 具体命令。
  - 应看到的 accountId。
  - 应看到的 default account。
  - 应看到的 binding key。
  - secret 不泄露要求。

### Phase 6：Control UI 对齐检查

目标：

- 确认 Control UI 如果展示 channel runtime/status，也不把多个 bot 折叠成不可分辨的一条 channel。

建议实施：

1. 检查 Control UI 当前是否消费 `channels.runtime`、`channels.get`。
   - 已知 gateway websocket 兼容层涉及 `channels.runtime`：`src/gateway/runtime/gateway_control_ui_ws.cj:1874-1875`。
2. 如果 UI 已展示 channel accounts：
   - 确认显示 accountId。
3. 如果 UI 没有展示：
   - 本轮可以不新增 UI 功能，但文档需说明 CLI 是当前多账号验收入口。

依据：

- Control UI validation discipline 要求 UI 变更必须真实浏览器验证；本功能首要缺口在 CLI，不能无计划扩大范围。

验收项：

- 如果不改 UI，方案/实现说明中明确“不涉及 UI 行为变更”。
- 如果改 UI，则必须执行 Control UI 浏览器 smoke test：
  - 页面非空。
  - 无 JS 报错。
  - `customElements.get("metis-app")` 注册。
  - 账号列表显示 accountId 且不泄露 secret。

### Phase 7：真实配置安全手工验收

目标：

- 用户能在本地用两个测试 Telegram bot 或两个 fake account 验证展示效果。

手工验收步骤：

1. 使用隔离目录，避免污染真实配置：

```bash
export METIS_HOME="/tmp/metis-channel-account-display-test"
rm -rf "$METIS_HOME"
mkdir -p "$METIS_HOME"
```

2. 创建两个测试 agent/account，使用 fake token 即可验证展示：

```bash
metis agents add --agent tg-writer --telegram-account writer --telegram-bot-token "111111111:fake-writer-token"
metis agents add --agent tg-reviewer --telegram-account reviewer --telegram-bot-token "222222222:fake-reviewer-token"
```

3. 查看 channel configured account：

```bash
metis gateway channel get telegram
```

通过标准：

- 输出包含 `Accounts: 2`。
- 输出包含 `telegram/writer`。
- 输出包含 `telegram/reviewer`。
- 输出包含一个 `[default]` 或明确 default 行。
- 输出包含 `binding=telegram:writer`、`binding=telegram:reviewer`。
- 输出不包含 `fake-writer-token` 或 `fake-reviewer-token`。
- 输出不是 JSON。

4. 查看 bindings：

```bash
metis agents bindings --agent tg-writer
metis agents bindings --agent tg-reviewer
```

通过标准：

- `tg-writer` 绑定到 `telegram:writer`。
- `tg-reviewer` 绑定到 `telegram:reviewer`。

5. 查看 runtime：

```bash
metis gateway channel runtime telegram
```

通过标准：

- 输出明确 runtime 是 live adapter state。
- 如果 Gateway 未运行对应 adapter，不应误报两个 account running。
- 如果响应中包含 configured account inspect，输出也能看到 configured accounts 摘要。

### Phase 8：统一构建与测试

目标：

- 按项目规则执行完整验证。

命令：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm clean
cjpm build -i
cjpm test -j 1
```

验收项：

- `cjpm clean` 成功。
- `cjpm build -i` 成功。
- `cjpm test -j 1` 成功。
- 如出现 OpenSSL 问题，使用上面的 `DYLD_LIBRARY_PATH` 后重跑。
- 验证结果记录在最终回复中。

### Phase 9：提交前审查

目标：

- 确保没有引入凭证泄露、真实环境写入、重复架构路径。

检查清单：

1. Git diff：

```bash
git diff -- src/gateway/runtime/gateway_cli_human_output.cj src/gateway/runtime/gateway_cli_human_output_test.cj docs/user/agent-team.md develop_steps/metis-agent-team-series-24-manual-test-checklist-2026-05-17.md
```

2. 敏感信息扫描：

```bash
rg -n "fake-writer-token|fake-reviewer-token|botToken\\\":\\\"[0-9]|appSecret\\\":\\\"" src docs develop_steps
```

通过标准：

- 测试数据中可出现 fake token 字符串作为输入，但默认输出断言必须确保它不被打印。
- 文档示例只能使用 fake token，不能出现真实 token。
- 不新增真实网络依赖。
- 不新增读取真实 `~/.metis` 的测试。

3. 架构边界：

- 渲染逻辑在 `gateway_cli_human_output.cj`。
- 配置/账号事实仍由 Gateway RPC 数据层提供。
- 不在 CLI renderer 里写配置。
- 不在 Telegram adapter 里加入 CLI 展示逻辑。

## 7. 最终验收矩阵

| 编号 | 验收条目 | 操作方法 | 通过标准 |
|---|---|---|---|
| A1 | Telegram channel get 展示多账号 | 构造两个 Telegram account 后执行 `metis gateway channel get telegram` | 输出含两个 `telegram/<accountId>` 行、default 标记、binding key。 |
| A2 | Telegram channel get 不泄露 token | 使用 fake token 创建账号后查看输出 | stdout/stderr 不含 fake token。 |
| A3 | Runtime 与配置账号语义区分 | 执行 `metis gateway channel runtime telegram` | 输出说明 runtime 是 live adapter state；configured accounts 单独展示或明确不在该命令完整展示。 |
| A4 | Feishu 多账号展示 | 构造两个 Feishu account 后执行 `metis gateway channel get feishu` | 输出含 `feishu/<accountId>`，appSecret 不泄露。 |
| A5 | QQ 多账号展示 | 构造两个 QQ account 后执行 `metis gateway channel get qq` | 输出含 `qq/<accountId>`，appSecret 不泄露，脱敏 appId 可读。 |
| A6 | 没有 accountInspect 的 channel 兼容 | 构造 plugin channel 或现有无 accountInspect channel | `gateway channel get <id>` 不崩溃，旧摘要仍可读。 |
| A7 | 无 raw JSON | 执行所有默认命令 | 输出不含裸 JSON。 |
| A8 | 测试不碰真实环境 | 阅读新增测试 | 测试使用内存 JSON/fake token，不访问真实 Telegram 或真实用户配置。 |
| A9 | OpenClaw 对齐 | 对比输出格式 | Metis 与 OpenClaw 一样能以 account 为单位展示，而不是只显示 channel。 |
| A10 | 全量验证 | 执行 `cjpm clean && cjpm build -i && cjpm test -j 1` | 全部通过。 |

## 8. 不纳入本轮的事项

| 事项 | 不纳入原因 | 后续入口 |
|---|---|---|
| 自动创建 Telegram bot | Telegram bot 需要用户在 BotFather 或 provider 控制台创建，Metis 不应伪造 provider 资源。 | 另起 provider onboarding 方案。 |
| 自动创建 Feishu app/bot | Feishu app 权限、事件订阅、tenant 授权需要外部控制台和管理员授权。 | Feishu OAuth/OAPI 方案。 |
| 新增 channel account 配置命令 | 当前缺口是展示；配置路径已经由 `agents add --telegram-account` 等快捷参数补齐。 | 若后续需要，可设计 `gateway channel account ...`，但不能和现有 `agents add`/bind 形成重复写配置路径。 |
| 真实 Telegram 网络探活 | 本轮默认验收不依赖真实网络。 | 可选 live smoke，需要用户提供测试 bot token。 |

## 9. 预计工作量

| 工作项 | 预估 |
|---|---|
| 渲染 helper 与 `channel get` 输出 | 0.5 天 |
| `runtime` 输出语义补齐 | 0.25 天 |
| 单元测试矩阵 | 0.5 天 |
| 文档与手工验收清单修正 | 0.25 天 |
| clean/build/test 与修正 | 0.25 天 |

总体预估：1.5 到 2 个工作日。若只做 CLI 展示和测试，不触碰 Control UI，则可以压缩到 1 天左右。

## 10. 实施前确认点

实施前需要确认：

1. 本轮是否只修改 CLI 人类可读输出和文档，不新增新命令。
2. 是否接受 `gateway channel get <id>` 默认永远展示 `Accounts` 段，即使只有一个 account。
3. 是否接受 runtime 输出追加 configured account 摘要，但不把 configured account 误标为 running。

建议选择：

- `gateway channel get <id>`：展示通道详情 + configured accounts。
- `gateway channel runtime <id>`：展示 live adapter runtime + 可选 configured account summary。
- 不新增 `gateway channel telegram accounts` 这种不存在且不符合当前命令层级的子命令。
