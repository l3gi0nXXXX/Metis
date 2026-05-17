# Metis Agent Team Series 25: Channel Account Inheritance Repair Plan

日期：2026-05-18

范围：本方案只制定补齐计划，不修改业务代码。后续实现必须先按本文件执行，遇到本文件未覆盖的实现细节，必须先回到 OpenClaw / OpenClaw-Lark / Metis 源码求证并更新本文档，再写代码。

## 1. 问题定义

用户创建多个 agent，并分别给 agent 配置 Telegram / Feishu / QQ Bot 后，当前 Metis 存在两类风险：

1. 命名账号可能误用顶层账号配置，尤其是 Telegram 的 `gateway.telegram.allowFrom`、`groupAllowFrom`、`groupPolicy` 等安全策略。用户期望 `tg-writer` 这种新 agent 账号不要自动继承 default bot 的 `allowFrom`，否则不同 bot 的准入策略会互相污染。
2. Feishu / QQ / Telegram 的账号配置、adapter 注册、runtime 启动、状态展示和 agent binding 还没有完全做到“一账号一运行实例、一账号一状态、一绑定明确 accountId”。这会导致 `agents add` 已写入账号凭据，但 Gateway 仍只注册或启动 `default` 账号，用户给新 bot 发消息时看不到回复。

本方案要同步覆盖 Telegram、Feishu、QQ。QQ 当前没有 `allowFrom`/`dmPolicy` 这种安全策略字段，但同样存在“命名账号不应误用 default/top-level 凭据”和“多账号 runtime 注册/展示”的问题。

## 2. 源码依据

### 2.1 OpenClaw Telegram 账号继承依据

OpenClaw Telegram 的账号解析集中在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/accounts.ts`。

- `mergeTelegramAccountConfig` 会把 top-level Telegram 配置作为 base，再叠加 `accounts.<accountId>` 覆盖值；源码行 127-154。
- 同一函数明确处理 multi-account 下的 `groups`：当配置了多个账号时，channel-level `groups` 不会被没有 `groups` 覆盖的账号继承，避免某个 bot 不在群里却拿到另一个 bot 的群配置；源码行 142-151。
- `resolveTelegramAccount` 通过 `resolveAccountWithDefaultFallback` 处理 default fallback；源码行 206-241。
- `resolveTelegramToken` 对“显式指定非 default accountId，但 accounts 中找不到该账号”的场景拒绝回退到 channel-level token；源码 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/token.ts` 行 41-64。
- OpenClaw 对 allowlist 继承有测试：`accounts.default` 覆盖 top-level；命名账号在没有自身覆盖时可以读 top-level；命名账号不会继承 `accounts.default`；测试在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/accounts.test.ts` 行 250-316。

结论：OpenClaw 的关键不是“所有字段无条件复制”，而是有一个明确的 effective account config resolver，并且有源码测试约束 default、top-level、named account 的优先级。

### 2.2 OpenClaw 单账号迁移为多账号的依据

OpenClaw 公共 setup helper 在 `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/channels/plugins/setup-helpers.ts`。

- 公共账号迁移字段包含 `dmPolicy`、`allowFrom`、`groupPolicy`、`groupAllowFrom` 等；源码行 390-409。
- 当 single-account 配置升级为 multi-account 时，OpenClaw 会把 top-level 账号字段移动到 `accounts.default`，确保原账号继续工作，同时避免 channel root 上保留重复账号值；源码行 545-597。

结论：当系统从单 bot 进入多 bot 时，应有清晰的“原 default bot 配置归属”动作。Metis 当前 `agents add --telegram/--feishu/--qq` 只新增命名账号，不处理 default/top-level 安全字段归属，因此容易让用户误判“新账号继承了旧账号准入策略”。

### 2.3 OpenClaw-Lark / Feishu 多账号依据

OpenClaw-Lark 的账号管理在 `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/accounts.ts`。

- 文件头部说明账号 override 位于 `cfg.channels.feishu.accounts`，每个账号可以覆盖 top-level Feishu config，未设置字段回退 top-level；源码行 5-9。
- `mergeAccountConfig` 执行 base + account override 合并，并对普通对象做一层 deep merge；源码行 45-68。
- `getLarkAccount` 返回当前 account 的 merged config；源码行 121-145。

OpenClaw-Lark 的运行侧也基于账号：

- `monitorFeishuProvider` 在未指定 `opts.accountId` 时，会启动所有 enabled Feishu accounts；源码 `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/monitor.ts` 行 130-180。
- 入站 gate 使用 `accountFeishuCfg.dmPolicy` 和 `accountFeishuCfg.allowFrom` 做 DM 准入；源码 `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/gate.ts` 行 431-470。
- 入站 handler 会构造 account-scoped config，把 `cfg.channels.feishu` 替换成当前 account 的 merged config，确保下游 SDK 读取的是当前账号配置；源码 `/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/handler.ts` 行 70-85。
- group command authorization 也使用 account-scoped `allowFrom`、`groupAllowFrom` 和 per-group allowFrom；源码同文件行 158-198。

结论：Feishu/Lark 的正确架构不是只在配置里存多个账号，而是 runtime、gate、handler、下游 SDK 调用都必须以当前 account 的 effective config 为准。

### 2.4 Metis Telegram 当前问题依据

Metis Telegram adapter 当前在 `/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/channels/telegram/telegram_adapter.cj`。

- `resolveTelegramToken` 只对 token 做 account override 查找；源码行 1305-1331。
- `resolveTelegramAccountConfig` 只返回 raw `accounts.<accountId>` JsonObject，没有产生完整 effective config；源码行 1334-1350。
- DM 准入直接读取 `this.config.dmPolicy` 和 `this.config.allowFrom`；源码行 7886-7915。
- group 准入直接读取 `this.config.groups`、`this.config.groupPolicy`、`this.config.groupAllowFrom` 和 `this.config.allowFrom`；源码行 7938-8035。

结论：即使 `agents add` 写入了 `gateway.telegram.accounts.tg-writer.botToken`，Telegram adapter 处理安全策略时仍可能读顶层 `gateway.telegram.allowFrom`。这就是用户担心的“新 bot 继承 default allowFrom”问题。

### 2.5 Metis Feishu 当前问题依据

Metis Feishu 账号解析在 `/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/channels/feishu/feishu_accounts.cj`。

- `gatewayFeishuListAccountIds` 会列出 default + accounts map；源码行 43-61。
- `gatewayFeishuResolveAccount` 已经合并 account override 和 top-level 配置；源码行 63-129。
- 但 `groupPolicy`、`groupAllowFrom`、`groups` 当前默认从 top-level 继承；源码行 82-107。
- Metis Feishu 目前没有像 OpenClaw-Lark 那样完整支持 DM `dmPolicy` / `allowFrom` 的 account-scoped gate。

结论：Feishu 已有 resolver 基础，但需要补上安全字段归属、account-scoped runtime/handler 使用、DM 准入能力以及多账号启动/展示。

### 2.6 Metis QQ 当前问题依据

Metis QQ 账号解析在 `/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/channels/qq/qq_accounts.cj`。

- `gatewayQqListAccountIds` 会列出 default + accounts map；源码行 49-67。
- `gatewayQqResolveAccount` 对“accounts 已存在但请求的命名账号不存在”有 `missingAccount` 保护；源码行 69-99。
- 但当账号存在却缺少 `appId/appSecret` 时，当前实现仍会从 top-level fallback；源码行 101-118。

结论：QQ 没有 allowFrom 继承问题，但有“命名账号 credentials 不应误用 top-level credentials”的同类账号隔离问题。

### 2.7 Metis adapter 注册和 agent 写配置问题依据

Metis built-in adapter profiles 在 `/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/config/gateway_adapter_registration_profiles.cj`。

- 当前只注册 `feishu:default`、`qq:default`、`telegram:default`；源码行 53-95。

Metis Gateway runtime factory 在 `/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_config_factory.cj`。

- 当前构造一个 `FeishuAdapter(config: cfg.feishu)` 和一个 `QQAdapter(config: cfg.qq)`；源码行 135-136。
- Telegram 在 profile 循环里创建 `TelegramAdapter(config: cfg.telegram, ...)`，但 profile 本身只有 `telegram:default`；源码行 137-170。

Metis `agents add` 的 channel credential 写入在 `/Users/l3gi0n/work/workspace_cangjie/Metis/src/gateway/runtime/gateway_server_methods_agents.cj`。

- Telegram 写入 `accounts.<accountId>.botToken/tokenFile`，自动增加 `telegram:<accountId>` binding；源码行 1281-1324。
- Feishu 写入 `accounts.<accountId>.appId/appSecret`，自动增加 `feishu:<accountId>` binding；源码行 1327-1360。
- QQ 写入 `accounts.<accountId>.appId/appSecret`，自动增加 `qq:<accountId>` binding；源码行 1363-1396。
- `agents.add` 会先应用 channel credentials，再解析 auto binding，最后写 agent workspace；源码行 1662-1744。

结论：`agents add` 已经能写账号凭据和绑定关系，但没有写安全隔离默认值，也没有保证 Gateway 注册并启动对应 account 的 adapter。

## 3. 目标设计原则

### 3.1 effective account config 是唯一运行时输入

Telegram、Feishu、QQ 都必须有明确的 account resolver。运行时 adapter、gate、send path、status、diagnostics、native command authorization 都只能读取 resolver 输出的 effective account config，不能在业务逻辑中直接读 top-level channel config。

验收标准：代码中新增或调整的 Telegram/Feishu/QQ 入站准入逻辑必须能在测试中注入一个 channel config + accountId，然后断言最终读取的是 resolver 产出的字段。

### 3.2 agent-created 命名账号默认安全隔离

OpenClaw 源码允许“命名账号未设置 allowFrom 时 fallback top-level”，但 OpenClaw 同时有 single-account promotion helper，把原 single-account 字段移动到 `accounts.default`。Metis 当前没有这个 promotion 动作，且用户通过 `agents add --telegram-bot-token` 创建的是独立 bot 账号。

因此 Metis 的落地策略是：

- 对历史手工配置，resolver 可以保留与 OpenClaw 类似的 top-level fallback，用于兼容老配置。
- 对 `agents add` 自动创建的命名账号，必须写入 account-local 安全字段，阻断它隐式继承 default/top-level 的安全策略。
- Telegram agent-created 账号默认写入 `dmPolicy: "pairing"`、`allowFrom: []`、`groupPolicy: "disabled"`、`groupAllowFrom: []`。如用户显式传入 allowlist/group policy，则写入用户显式值。
- Feishu agent-created 账号默认写入 group 侧隔离字段；当 Feishu DM `dmPolicy/allowFrom` 补齐后，也按 account-local 规则写入。
- QQ agent-created 账号没有 allowFrom 字段，但必须保证命名账号不会因为缺少自身 credentials 而使用 top-level credentials。

验收标准：在包含顶层 `gateway.telegram.allowFrom=["old-user"]` 的配置下，执行 `agents add --agent tg-writer --telegram-bot-token fake` 后，`gateway.telegram.accounts.tg-writer.allowFrom` 必须是显式空数组或显式用户传入值，`tg-writer` 的 resolver 不得把 `old-user` 当成有效 allowlist。

### 3.3 explicit accountId 不能误回退到 default 账号

参考 OpenClaw Telegram token resolver 对 multi-bot 场景拒绝未知 account fallback 的逻辑：显式请求 `telegram:tg-writer`、`feishu:feishu-writer`、`qq:qq-writer` 时，如果账号不存在或 credentials 不完整，不得使用 default/top-level credentials 假装成功。

验收标准：配置存在 `accounts.default` 或 top-level credentials，但 `accounts.tg-writer` 不存在时，请求 `telegram:tg-writer` 必须得到 `missing-account` 或 `unconfigured` 诊断，不能得到 default token。

### 3.4 多账号必须注册和启动多个 adapter 实例

参考 OpenClaw-Lark `monitorFeishuProvider` 同时启动所有 enabled accounts 的设计。Metis Gateway 应按 account list 注册 `telegram:<id>`、`feishu:<id>`、`qq:<id>`，并用对应 accountId 构造 adapter 或 account-scoped config。

验收标准：配置三个 agent `tg-writer`、`feishu-writer`、`qq-writer` 后，`gateway channel get telegram/feishu/qq` 必须显示对应账号；Gateway runtime registry 必须存在对应 `channel:accountId` profile；给对应 bot 的 inbound event 进入时，日志必须能看到当前 accountId。

### 3.5 状态展示必须区分 local、inherited、effective

用户不能通过大 JSON 猜配置含义。`gateway channel get telegram/feishu/qq` 的人类可读输出要显示：

- accountId
- 是否 default
- enabled/configured/running
- credential source
- security source：account-local、top-level-inherited、default-account-inherited、explicit-empty、not-supported
- allow/group allow 的 local count 和 effective count
- live readiness 和 lastError

验收标准：无 `--json` 时不能直接打印 `toJsonString()`；`--json` 时才输出完整结构化字段。

## 4. 分阶段补齐方案

### Phase 0：补齐源码事实矩阵和回归用例清单

目标：把本文件作为实现入口，确认 OpenClaw、OpenClaw-Lark、Metis 三方源码事实，避免后续实现时凭记忆修改。

实现步骤：

1. 在本文件维护 `2. 源码依据` 和 `6. 验收矩阵`。
2. 对每个需要修改的 Metis 文件，在实现前补充对应 OpenClaw / OpenClaw-Lark 源码依据。
3. 把 Telegram、Feishu、QQ 分别列出：resolver、credential fallback、security policy、adapter registration、runtime startup、status output、agents add 写配置。

验收项：

1. 开发者打开本文件，能看到每个结论对应的源码路径和行号。
2. 开发者执行 `rg "allowFrom|groupAllowFrom|dmPolicy|defaultAccount|accounts" src/gateway/channels src/gateway/runtime src/gateway/config`，能把结果归类到本文的各个阶段。
3. 本阶段不修改 `src/`，只允许修改 `develop_steps/`。

### Phase 1：建立 Metis 三通道 effective account resolver 合同

目标：为 Telegram、Feishu、QQ 定义统一的 resolver 语义，后续运行时全部依赖 resolver。

实现步骤：

1. Telegram 新增或重构 `gatewayTelegramResolveAccount(config, accountId)`，输出：
   - `accountId`
   - `config`
   - `explicitAccount`
   - `missingAccount`
   - `credentialSource`
   - `securitySources`
   - `inheritanceDiagnostics`
2. Feishu 在已有 `gatewayFeishuResolveAccount` 基础上补充：
   - `missingAccount`
   - `securitySources`
   - `local vs effective groupPolicy/groupAllowFrom/groups`
   - 后续 DM `dmPolicy/allowFrom` 字段的 source 信息
3. QQ 在已有 `gatewayQqResolveAccount` 基础上补充：
   - `missingCredential`
   - 当 `accountId` 是命名账号且 accounts map 存在时，账号自身没有 `appId/appSecret` 就不得使用 top-level credential。
4. resolver 必须区分四类来源：
   - `account-local`：字段来自 `accounts.<id>`。
   - `top-level-inherited`：字段来自 channel root，用于兼容历史手工配置。
   - `default-account`：字段来自 `accounts.default`，只能用于 default account，命名账号不能继承。
   - `explicit-empty`：字段在 account 上显式配置为空数组或空对象，用于阻断 fallback。

函数级验收项：

1. 调用 `gatewayTelegramResolveAccount`，输入：
   - top-level `allowFrom=["old"]`
   - `accounts.default.allowFrom=["default"]`
   - `accounts.tgWriter.botToken="123:writer"`
   - accountId=`tgWriter`
   预期：`effective.allowFrom` 不包含 `default`；如果 `tgWriter.allowFrom` 显式为空，则也不包含 `old`；`securitySources.allowFrom="explicit-empty"`。
2. 调用 `gatewayTelegramResolveAccount`，输入：
   - top-level `allowFrom=["old"]`
   - 无 `accounts.tgWriter.allowFrom`
   - accountId=`tgWriter`
   预期：为了兼容手工老配置，可以显示 `effective.allowFrom=["old"]`，但 `securitySources.allowFrom="top-level-inherited"`，status 必须提示这是继承值。
3. 调用 `gatewayFeishuResolveAccount`，输入：
   - top-level `groupAllowFrom=["oc_default"]`
   - `accounts.feishuWriter.groupAllowFrom=[]`
   - accountId=`feishuWriter`
   预期：effective groupAllowFrom 为空，source=`explicit-empty`。
4. 调用 `gatewayQqResolveAccount`，输入：
   - top-level `appId/appSecret` 均存在
   - `accounts.qqWriter={}`
   - accountId=`qqWriter`
   预期：`configured=false`，`credentialSource` 包含 `missing-account-credential`，不能 fallback top-level。

### Phase 2：修复 Telegram 入站准入、发送、命令授权的账号隔离

目标：Telegram runtime 不再直接读取顶层 `TelegramConfig` 安全字段，而是读取当前 account 的 effective config。

实现步骤：

1. `TelegramAdapter` 构造时携带明确 accountId，或者构造 account-scoped `TelegramConfig`。
2. `resolveTelegramToken` 改为读取 resolver 输出，避免显式命名账号误回退 default token。
3. `directInboundRejectReason` 使用 effective `dmPolicy` 和 effective `allowFrom`。
4. `groupInboundRejectReason`、`groupIsAllowed`、`effectiveGroupSenderPolicy`、`effectiveGroupAllowFrom` 使用 effective `groups/groupPolicy/groupAllowFrom/allowFrom`。
5. Telegram native commands authorization 也使用相同 effective account config，不能继续读 top-level `user.telegram.allowFrom`。
6. Pairing store 已经按 `accountId` 存储，保持该设计，但所有调用都必须传当前 accountId。

命令级验收项：

1. 开发者设置临时环境：
   ```bash
   export METIS_HOME=/tmp/metis-agent-channel-inheritance-phase2
   ```
2. 开发者写入测试配置：top-level `gateway.telegram.allowFrom=["old-user"]`，再通过 CLI 创建命名账号：
   ```bash
   cjpm run --skip-build --name metis --run-args "agents add --agent tg-writer --name TG Writer --telegram-bot-token 123456:fake"
   ```
3. 开发者执行：
   ```bash
   cjpm run --skip-build --name metis --run-args "gateway channel get telegram"
   ```
   预期人类可读输出包含 `tg-writer`，并显示 `allow(local)=0`、`allow(effective)=0`、`security=explicit-empty` 或等价描述；不能显示 `old-user` 对 `tg-writer` 生效。
4. 单元测试构造一条 senderId=`old-user` 的 Telegram DM inbound message，accountId=`tg-writer`，预期 `directInboundRejectReason` 返回 `dm_pairing_required` 或 `dm_sender_not_allowed`，不能因为 top-level `allowFrom` 通过。
5. 单元测试构造 accountId=`default`，且 `accounts.default.allowFrom=["old-user"]`，预期 default account 仍允许 `old-user`，证明没有破坏 default 账号。

### Phase 3：修复 Feishu account-scoped 安全策略和 DM 准入能力

目标：Feishu 对齐 OpenClaw-Lark 的 account-scoped config 思路，并避免 agent-created 命名账号继承 default/top-level group 或 DM 安全策略。

实现步骤：

1. 在 Feishu user settings / model config 中补齐 DM `dmPolicy` 和 `allowFrom` 字段，字段语义参考 OpenClaw-Lark gate：
   - `dmPolicy=disabled|pairing|allowlist|open`
   - `allowFrom` 是 DM sender allowlist
2. `gatewayFeishuResolveAccount` 输出 account-scoped Feishu config，并记录 `dmPolicy/allowFrom/groupPolicy/groupAllowFrom/groups` 的来源。
3. Feishu adapter 入站 gate 使用当前 account 的 resolved config，而不是顶层 `cfg.feishu`。
4. 保持 Metis 当前 group admission 语义时必须明确命名：
   - `groupAllowFrom` 当前在 Metis 表示允许哪些群/chat id。
   - 如果后续要引入 OpenClaw-Lark 的 sender-level `groupSenderAllowFrom`，必须作为独立字段，不允许悄悄改变 `groupAllowFrom` 的含义。
5. `agents add --feishu` 创建命名账号时写入 account-local 默认安全字段：
   - `dmPolicy="pairing"`
   - `allowFrom=[]`
   - `groupPolicy="disabled"`
   - `groupAllowFrom=[]`
   - `groups={}`
6. Feishu send path 和 reply path 必须携带 accountId，确保回复使用触发消息的 bot。

函数级验收项：

1. 调用 `gatewayFeishuResolveAccount`，输入 top-level `groupAllowFrom=["oc_old"]`，`accounts.feishuWriter.groupAllowFrom=[]`，accountId=`feishuWriter`，预期 effective `groupAllowFrom=[]`，source=`explicit-empty`。
2. 调用 Feishu DM gate，输入 accountId=`feishuWriter`、sender=`ou_old`，top-level `allowFrom=["ou_old"]`，account-local `allowFrom=[]`，预期不通过，且返回 pairing/allowlist 相关拒绝原因。
3. 调用 Feishu group gate，输入 chatId=`oc_old`，accountId=`feishuWriter`，top-level `groupAllowFrom=["oc_old"]`，account-local `groupAllowFrom=[]`，预期不通过。
4. 调用 Feishu group gate，输入 account-local `groupAllowFrom=["oc_writer"]`、chatId=`oc_writer`，预期通过。

命令级验收项：

1. 开发者执行：
   ```bash
   export METIS_HOME=/tmp/metis-agent-channel-inheritance-phase3
   cjpm run --skip-build --name metis --run-args "agents add --agent feishu-writer --name Feishu Writer --feishu cli_fake:secret_fake"
   cjpm run --skip-build --name metis --run-args "gateway channel get feishu"
   ```
2. 预期输出包含 `feishu-writer`，显示 appId 已配置但 secret 已脱敏，`groupPolicy=disabled`，`dmPolicy=pairing`，`security=explicit-empty` 或等价描述。

### Phase 4：修复 QQ 命名账号凭据隔离和状态展示

目标：QQ 虽没有 allowFrom，但必须避免命名账号缺凭据时 fallback default/top-level credentials。

实现步骤：

1. 调整 `gatewayQqResolveAccount`：
   - `accounts` map 存在且 accountId 是命名账号时，只有 account-local `appId/appSecret` 才能让该账号 configured。
   - account 存在但缺 `appId/appSecret` 时，返回 `missingCredential=true`，而不是 fallback top-level。
2. QQ adapter start 时读取 resolver 输出，遇到 `missingAccount` 或 `missingCredential` 要给出清晰 `lastError`。
3. `gateway channel get qq` 展示每个 account 的 credential source 和 configured 状态。

函数级验收项：

1. 调用 `gatewayQqResolveAccount`，输入 top-level `appId=top`、`appSecret=top-secret`、`accounts.qqWriter={}`，accountId=`qqWriter`，预期 `configured=false`、`credentialSource=missing-account-credential`。
2. 调用 `gatewayQqResolveAccount`，输入 `accounts.qqWriter.appId=writer`、`accounts.qqWriter.appSecret=writer-secret`，预期 `configured=true`、credential source 全部为 `account-local`。

命令级验收项：

1. 开发者执行：
   ```bash
   export METIS_HOME=/tmp/metis-agent-channel-inheritance-phase4
   cjpm run --skip-build --name metis --run-args "agents add --agent qq-writer --name QQ Writer --qqbot 1024:qq_secret_fake"
   cjpm run --skip-build --name metis --run-args "gateway channel get qq"
   ```
2. 预期输出包含 `qq-writer`，显示 `configured=yes`、`credential=account-local`。
3. 手工删除 `accounts.qq-writer.appSecret` 后再次执行 `gateway channel get qq`，预期 `qq-writer configured=no` 且 lastError 或 readiness 显示缺少 account-local appSecret，不能显示为使用 top-level secret。

### Phase 5：按 account 注册并启动 Telegram / Feishu / QQ adapter

目标：解决“配置了多个 bot，但 Gateway 只注册 default adapter”的结构性问题。

实现步骤：

1. 改造 `gatewayBuiltinAdapterRegistrationProfiles`：
   - Telegram 使用 `gatewayTelegramListAccountIds`。
   - Feishu 使用 `gatewayFeishuListAccountIds`。
   - QQ 使用 `gatewayQqListAccountIds`。
   - 每个账号生成一个 profile：`telegram:<id>`、`feishu:<id>`、`qq:<id>`。
2. profile 的 `configured` 必须来自对应 account resolver，不得只看 top-level appId/botToken。
3. 改造 `gateway_config_factory`：
   - 每个 Telegram account 创建一个 `TelegramAdapter` 或 account-scoped config。
   - 每个 Feishu account 创建一个 `FeishuAdapter` 或 account-scoped config。
   - 每个 QQ account 创建一个 `QQAdapter` 或 account-scoped config。
4. 如果当前 adapter 类不能安全复用，则每个 account 必须有独立 adapter 实例，避免 `lastSendError`、pairing state、runtime metadata 互相覆盖。

函数级验收项：

1. 构造 user settings：`telegram.accounts.tgWriter`、`feishu.accounts.feishuWriter`、`qq.accounts.qqWriter` 均存在。
2. 调用 `gatewayBuiltinAdapterRegistrationProfiles(user, true)`。
3. 预期返回至少包含：
   - `telegram:tgWriter`
   - `feishu:feishuWriter`
   - `qq:qqWriter`
4. 每个 profile 的 `configured` 与 resolver 判断一致，不能只等于 default/top-level 状态。

运行级验收项：

1. 开发者启动 Gateway：
   ```bash
   export METIS_HOME=/tmp/metis-agent-channel-inheritance-phase5
   cjpm run --skip-build --name metis --run-args "gateway run"
   ```
2. 在另一个 shell 执行：
   ```bash
   cjpm run --skip-build --name metis --run-args "gateway channel get telegram"
   cjpm run --skip-build --name metis --run-args "gateway channel get feishu"
   cjpm run --skip-build --name metis --run-args "gateway channel get qq"
   ```
3. 预期每个 channel 都展示 default 与命名账号，命名账号有独立 running/configured/lastError。

### Phase 6：修复 agents add 的一键 IM 配置写入策略

目标：`agents add` 继续复用既有 channel/account 写配置函数，但必须写入 account-local 隔离默认值，并支持显式传入安全参数。

实现步骤：

1. Telegram credential writer 在写入 `botToken/tokenFile` 时，同时写入：
   - 若用户未显式传入 `--telegram-dm-policy`：`dmPolicy="pairing"`
   - 若用户未显式传入 `--telegram-allow-from`：`allowFrom=[]`
   - 若用户未显式传入 `--telegram-group-policy`：`groupPolicy="disabled"`
   - 若用户未显式传入 `--telegram-group-allow-from`：`groupAllowFrom=[]`
2. Feishu credential writer 在写入 `appId/appSecret` 时，同时写入：
   - `dmPolicy="pairing"`、`allowFrom=[]`，前提是 Phase 3 已补齐 Feishu DM 字段。
   - `groupPolicy="disabled"`、`groupAllowFrom=[]`、`groups={}`。
3. QQ credential writer 只写 `appId/appSecret`，并写入足够的 status metadata，不引入不存在的 allowFrom 概念。
4. 所有写配置逻辑必须复用已有 `gatewayAgentApplyTelegramCredential`、`gatewayAgentApplyFeishuCredential`、`gatewayAgentApplyQqCredential` 路径，禁止另起一套独立写配置逻辑。
5. 如果后续新增 `agents channel set` 或 `gateway channel account set`，也必须调用同一组底层函数。

命令级验收项：

1. 开发者执行：
   ```bash
   export METIS_HOME=/tmp/metis-agent-channel-inheritance-phase6
   cjpm run --skip-build --name metis --run-args "agents add --agent tg-writer --name TG Writer --telegram-bot-token 123456:fake"
   ```
2. 开发者检查配置，不要求看 secret 明文，可通过 status 命令：
   ```bash
   cjpm run --skip-build --name metis --run-args "gateway channel get telegram"
   ```
3. 预期 `tg-writer` 显示 `dmPolicy=pairing`、`allow(local)=0`、`groupPolicy=disabled`。
4. 开发者执行：
   ```bash
   cjpm run --skip-build --name metis --run-args "agents add --agent tg-open --name TG Open --telegram-bot-token 123456:fake2 --telegram-dm-policy allowlist --telegram-allow-from 10001"
   ```
5. 预期 `tg-open` 显示 `allow(local)=1`、`allow(effective)=1`，effective allowlist 包含 `10001`，且不包含 default/top-level allowlist。

### Phase 7：修复 channel get/list/status 的人类可读输出

目标：用户执行 `gateway channel get telegram/feishu/qq` 时，不再看到难理解的大 JSON，也不会误以为 default 状态代表所有账号。

实现步骤：

1. Telegram status 行展示：
   - `accountId`
   - `default`
   - `enabled`
   - `configured`
   - `running`
   - `tokenSource`
   - `dmPolicy`
   - `allow(local/effective/source)`
   - `groupPolicy`
   - `groupAllow(local/effective/source)`
   - `groups(local/effective/source)`
2. Feishu status 行展示：
   - `accountId`
   - `default`
   - `enabled`
   - `configured`
   - `running`
   - `appIdSource/appSecretSource`
   - `dmPolicy/allow`，如果 Phase 3 已补齐
   - `groupPolicy/groupAllow/groups`
3. QQ status 行展示：
   - `accountId`
   - `default`
   - `enabled`
   - `configured`
   - `running`
   - `appIdSource/appSecretSource`
   - `missingAccount/missingCredential`
4. 无 `--json` 时统一走 `gatewayFormatCommandOutput` 或同类 human formatter，禁止直接打印 `toJsonString()`。
5. `--json` 输出保留完整字段，供自动化测试和 control-ui 使用。

命令级验收项：

1. 开发者执行：
   ```bash
   cjpm run --skip-build --name metis --run-args "gateway channel get telegram"
   ```
   预期输出是表格或分组文本，不能是以 `{` 开头的大 JSON。
2. 开发者执行：
   ```bash
   cjpm run --skip-build --name metis --run-args "gateway channel get telegram --json"
   ```
   预期输出是 JSON，且每个账号包含 `securitySources` 或等价结构化字段。
3. 同样验收 `feishu` 和 `qq`。

### Phase 8：补齐 agent binding 与 runtime account 的一致性诊断

目标：用户配置 agent 与 IM account 后，系统能明确说明“agent 绑定了哪个 channel account，Gateway 是否启动了这个 account，消息会不会路由到该 agent”。

实现步骤：

1. 在 `agents list` / `agents describe` / `agents channel` 相关输出中展示每个 agent 的 route bindings：
   - `channel`
   - `accountId`
   - `tenantId`
   - `session scope`
2. 增加诊断：
   - binding 指向的 account 不存在：报 `binding-account-missing`
   - account 存在但未 configured：报 `binding-account-unconfigured`
   - account configured 但 adapter 未 registered：报 `binding-account-not-registered`
   - account registered 但 runtime 未 running：报 `binding-account-not-running`
3. 诊断必须同时覆盖 Telegram、Feishu、QQ。

命令级验收项：

1. 开发者执行：
   ```bash
   cjpm run --skip-build --name metis --run-args "agents add --agent tg-writer --name TG Writer --telegram-bot-token 123456:fake"
   cjpm run --skip-build --name metis --run-args "agents list"
   ```
2. 预期 `tg-writer` 行能看到 `telegram:tg-writer` 或等价 binding 信息。
3. 开发者删除 `gateway.telegram.accounts.tg-writer.botToken` 后执行同一诊断命令。
4. 预期显示 `binding-account-unconfigured`，不能只显示 generic “Gateway agent failed”。

### Phase 9：自动化测试、手工验收文档和构建验证

目标：把本问题变成可重复验证的问题，避免后续再出现“新增 agent account 后误继承 default 配置”。

自动化测试要求：

1. resolver 单元测试：
   - Telegram default override。
   - Telegram named account 不继承 `accounts.default`。
   - Telegram agent-created explicit empty allowFrom 阻断 top-level fallback。
   - Feishu groupAllowFrom explicit empty 阻断 top-level fallback。
   - Feishu DM allowFrom explicit empty 阻断 top-level fallback。
   - QQ named account 缺 credentials 不 fallback top-level。
2. adapter registration 测试：
   - 三个通道均按 accounts list 生成 profiles。
   - profiles configured 使用 resolver 判断。
3. agents add 测试：
   - Telegram/Feishu/QQ 一键配置写入 account-local credentials。
   - Telegram/Feishu 写入 account-local 安全隔离默认值。
   - auto binding 指向同名 account。
4. human output 测试：
   - `gateway channel get telegram/feishu/qq` 无 `--json` 不输出 raw JSON。
   - 输出包含 local/effective/source 字段。

统一验证命令：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm clean
cjpm build -i
cjpm test
```

手工验收要求：

1. 使用临时 `METIS_HOME`，避免污染真实配置：
   ```bash
   export METIS_HOME=/tmp/metis-agent-channel-inheritance-manual
   ```
2. 创建三个 agent：
   ```bash
   cjpm run --skip-build --name metis --run-args "agents add --agent tg-writer --name TG Writer --telegram-bot-token 123456:fake"
   cjpm run --skip-build --name metis --run-args "agents add --agent feishu-writer --name Feishu Writer --feishu cli_fake:secret_fake"
   cjpm run --skip-build --name metis --run-args "agents add --agent qq-writer --name QQ Writer --qqbot 1024:qq_secret_fake"
   ```
3. 查看三个通道状态：
   ```bash
   cjpm run --skip-build --name metis --run-args "gateway channel get telegram"
   cjpm run --skip-build --name metis --run-args "gateway channel get feishu"
   cjpm run --skip-build --name metis --run-args "gateway channel get qq"
   ```
4. 预期：
   - 输出是人类可读格式。
   - 每个通道展示对应命名账号。
   - 命名账号 credential source 是 account-local。
   - Telegram/Feishu 命名账号安全字段不继承 default/top-level。
   - QQ 命名账号不 fallback top-level credentials。
5. 启动 Gateway：
   ```bash
   cjpm run --skip-build --name metis --run-args "gateway run"
   ```
6. 查看日志：
   - 预期能看到 `telegram:tg-writer`、`feishu:feishu-writer`、`qq:qq-writer` 对应 profile 注册或启动日志。
   - 如果 fake token 导致启动失败，lastError 必须落在对应账号行，不能污染 default 账号。

## 5. 需要同步修改的模块清单

| 模块 | 修改目的 | 依据 |
| --- | --- | --- |
| `src/gateway/channels/telegram/*` | 增加 effective resolver，并让 adapter/gate/native command 使用 account-scoped config | OpenClaw Telegram `accounts.ts`、`token.ts`、`accounts.test.ts` |
| `src/gateway/channels/feishu/*` | 补齐 Feishu account-scoped DM/group 安全策略和 resolver 来源诊断 | OpenClaw-Lark `core/accounts.ts`、`inbound/gate.ts`、`inbound/handler.ts` |
| `src/gateway/channels/qq/*` | 阻断命名账号 credentials fallback，并补齐账号状态 | OpenClaw Telegram token fallback 语义，Metis QQ resolver 现状 |
| `src/gateway/config/gateway_adapter_registration_profiles.cj` | 按账号生成 profile，不再只生成 default | OpenClaw-Lark monitor all accounts |
| `src/gateway/runtime/gateway_config_factory.cj` | 按账号创建 adapter/runtime 实例 | OpenClaw-Lark `monitorFeishuProvider` |
| `src/gateway/runtime/gateway_server_methods_agents.cj` | `agents add` 写入 account-local 隔离默认值，并复用既有 credential writer | Metis 当前 `agents.add` 写配置路径 |
| CLI output formatter | `gateway channel get/list/status` 输出人类可读表格 | 前置整改规则：无 `--json` 禁止 raw `toJsonString()` |
| tests | 覆盖 resolver、agent add、adapter registration、human output | 本文 Phase 9 |

## 6. 验收矩阵

| 场景 | 操作人 | 操作 | 预期结果 |
| --- | --- | --- | --- |
| Telegram 命名账号不继承 default allowFrom | 开发者 | 单元测试调用 `gatewayTelegramResolveAccount(config, "tg-writer")` | effective allowFrom 不包含 `accounts.default.allowFrom` |
| Telegram agent-created 账号阻断 top-level allowFrom | 开发者 | `agents add --agent tg-writer --telegram-bot-token fake` 后调用 resolver | `allowFrom=[]` 且 source=`explicit-empty` |
| Feishu 命名账号不继承 default groupAllowFrom | 开发者 | 单元测试调用 `gatewayFeishuResolveAccount(config, "feishu-writer")` | effective groupAllowFrom 不包含 default/top-level，除非账号显式配置 |
| Feishu DM 使用 account allowFrom | 开发者 | 构造 Feishu DM inbound gate，accountId=`feishu-writer` | sender 只按 `accounts.feishu-writer.allowFrom` 和 pairing store 判断 |
| QQ 命名账号不继承 top-level appSecret | 开发者 | 单元测试调用 `gatewayQqResolveAccount(config, "qq-writer")` | account 缺 appSecret 时 `configured=false` |
| 多账号注册 | 开发者 | 调用 `gatewayBuiltinAdapterRegistrationProfiles` | 返回 `telegram:tg-writer`、`feishu:feishu-writer`、`qq:qq-writer` |
| 多账号 runtime 启动 | 开发者 | `metis gateway run` | 日志和 status 中每个 account 独立 running/lastError |
| 人类可读状态 | 用户 | `metis gateway channel get telegram` | 非 JSON 输出，并显示 local/effective/source |
| 结构化状态 | 用户 | `metis gateway channel get telegram --json` | JSON 输出，包含每个账号的 sources 和 readiness |
| agent binding 诊断 | 用户 | `metis agents list` 或后续诊断命令 | 能看到 agent 绑定到哪个 channel account，以及 account 是否 missing/unconfigured/not-running |

## 7. 不接受的实现方式

1. 不允许只在 `agents add` 里复制 token/appSecret，而不修 runtime adapter registration。
2. 不允许 Telegram 修了 allowFrom，Feishu/QQ 保持 default-only 注册。
3. 不允许在 adapter 内部散落读取 top-level config，必须通过 resolver。
4. 不允许把 `accounts.default` 的 allowFrom/groupAllowFrom 继承给命名账号。
5. 不允许无 `--json` 时直接把 `toJsonString()` 打印给用户。
6. 不允许测试使用真实 Telegram bot token、Feishu appSecret、QQ appSecret 或真实 `~/.metis`。

## 8. 实施顺序建议

建议按 Phase 1 到 Phase 5 先完成架构修复，再做 Phase 6 的 `agents add` 写入策略，否则会出现“配置写对了但 Gateway 没启动账号”的假成功。

推荐工作拆分：

1. Worker A：Telegram resolver + adapter/gate/native command + tests。
2. Worker B：Feishu resolver + DM/group account-scoped gate + tests。
3. Worker C：QQ resolver + credential fallback + tests。
4. Worker D：adapter registration/runtime factory + status formatter + tests。
5. 主工作区：合并后统一跑 `cjpm clean && cjpm build -i && cjpm test`，再做手工临时 `METIS_HOME` 验收。

所有 worker 必须使用 git worktree，且每个 worker 只能修改自己负责的模块。合并前必须确认没有重复实现同一个 resolver 或重复写配置路径。
