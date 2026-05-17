# Metis IM Multi-Account Runtime Autostart Source-Backed Landing Plan

日期：2026-05-17

## 0. 2026-05-18 OpenClaw 对齐复核结论

结论：本文档的主方向是参考 OpenClaw / OpenClaw-Lark 的，但原文只充分引用了 OpenClaw-Lark Feishu 多账号实现，对 OpenClaw core gateway account runtime、OpenClaw Telegram account adapter、运行时 start/stop 机制的引用不够完整。因此在执行本文档前，必须以本节作为修正版依据。

### 0.1 已经直接对齐 OpenClaw 的部分

1. 多账号配置结构对齐。
   - OpenClaw-Lark 把 Feishu 多账号放在 `cfg.channels.feishu.accounts` 下，account override 覆盖 top-level 配置；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/accounts.ts:5-9`、`45-68`、`121-145`。
   - Metis 当前也已经有 `gateway.feishu.accounts`、`gateway.qq.accounts`、`gateway.telegram.accounts`，并有 Feishu/QQ resolver 基础；源码：`src/gateway/channels/feishu/feishu_accounts.cj:43-129`、`src/gateway/channels/qq/qq_accounts.cj:49-130`。

2. 按账号枚举 runtime 对齐。
   - OpenClaw-Lark `getLarkAccountIds` 会枚举所有 Feishu account，包含 default 与命名账号；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/accounts.ts:80-108`。
   - OpenClaw Telegram 也通过 channel config adapter 暴露 `listAccountIds`、`resolveAccount`、`defaultAccountId`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/shared.ts:102-113`。
   - Metis 方案中 Phase 2 要求 `gatewayBuiltinAdapterRegistrationProfiles` 不再硬编码 default，而是枚举 Telegram/Feishu/QQ accounts，这一点是 OpenClaw 设计的直接对应。

3. 按账号启动 runtime 对齐。
   - OpenClaw-Lark `monitorFeishuProvider` 在未指定 `accountId` 时通过 `getEnabledLarkAccounts` 获取全部 enabled/configured accounts，并发启动；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/monitor.ts:130-180`。
   - OpenClaw core gateway 的 `startChannelInternal` 也不是只启动 default：未传 accountId 时调用 `plugin.config.listAccountIds(cfg)`，逐个账号 resolve、检查 enabled/configured，然后调用 `startAccount`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-374`。
   - Metis 方案中 Phase 4 “Gateway 启动时 autostart 所有 account runtimes”是对 OpenClaw core gateway 机制的直接对齐。

4. account-scoped client / adapter 对齐。
   - OpenClaw-Lark `LarkClient` 以 accountId 作为 cache key，并在 credentials 变化时替换旧实例；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/lark-client.ts:85-86`、`177-203`。
   - OpenClaw-Lark `monitorSingleAccount` 为每个 account 创建独立 `LarkClient` 和 context；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/monitor.ts:45-124`。
   - Metis 方案中 Phase 3 要求每个 IM account 独立构造 adapter，禁止多个 account 共享同一个可变 adapter 实例，这是直接对齐 OpenClaw 的 account-scoped runtime 设计。

5. account 粒度状态快照对齐。
   - OpenClaw-Lark plugin status 按 account 构建 snapshot，字段包含 `accountId`、`enabled`、`configured`、`running`、`lastStartAt`、`lastStopAt`、`lastError`、`probe`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:276-311`。
   - OpenClaw core gateway 维护 `channelId + accountId` 粒度 runtime store；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:237-252`。
   - Metis 方案中 Phase 8 的 `gateway channel get/runtime` 账号级状态展示是对这个机制的直接对齐。

6. route binding 使用 `channel + accountId` 对齐。
   - OpenClaw-Lark 多账号隔离检查使用 `match.channel === 'feishu'` 与 `match.accountId` 判定账号是否绑定到独立 agent；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/security-check.ts:35-68`。
   - 生成隔离修复命令时也为每个 account 生成 `{match:{channel:'feishu', accountId}, agentId}`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/security-check.ts:160-179`。
   - Metis 当前 `agents add` 自动生成 `telegram:<accountId>`、`feishu:<accountId>`、`qq:<accountId>` binding，方向是对齐的，但 runtime profile 还没跟上。

### 0.2 原文证据不足或需要修正的部分

1. 原文 Phase 5 “运行中配置变更后的 reconciliation”不是 OpenClaw-Lark 某个同名函数的直接照搬。
   - OpenClaw 的直接源码事实是：plugin 声明 `reload: { configPrefixes: ['channels.feishu'] }`，并提供 `gateway.startAccount` / `gateway.stopAccount`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:150-153`、`318-337`。
   - OpenClaw core gateway 提供 `startChannel`、`stopChannel`，并以 accountId 为单位 start/stop；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:454-510`。
   - 因此 Metis 的 reconciliation 是“基于 OpenClaw start/stop/reload 机制，在 Metis Gateway 架构中的等价落地”，不能宣称是 OpenClaw 的同名实现。

2. 原文缺少“指定账号启动/停止”作为独立 GAP。
   - OpenClaw `ChannelManager` 类型直接暴露 `startChannel(channel, accountId?)`、`stopChannel(channel, accountId?)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:144-149`。
   - OpenClaw `startChannelInternal` 传入 `accountId` 时只启动该账号，未传时才枚举 `plugin.config.listAccountIds(cfg)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-274`。
   - OpenClaw `stopChannel` 传入 `accountId` 时只停止该账号；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:458-514`。
   - Metis 当前 `GatewayChannelManager` 只有整体 `startChannels()` / `stopChannels()`，且 `startChannels()` 有 `started` 总开关，已启动后再次调用直接返回；源码：`src/gateway/core/gateway_channel_manager.cj:426-495`。
   - Metis `GatewayService` 当前只暴露整体 start/stop，没有主 runtime 的 `startChannel(channel, accountId)` 入口；源码：`src/gateway/core/gateway_service.cj:49-113`。
   - 因此本文新增 Phase 4.5，单独补齐“指定账号启动/停止”能力。它不能只作为 Phase 5 热重载的内部实现细节，否则后续 CLI、Control UI、health monitor、agent IM 自动启用都会缺少可验收的公共运行时入口。

3. 原文缺少 OpenClaw Telegram 对照。
   - 已补充依据：OpenClaw Telegram `telegramConfigAdapter` 明确暴露 `listAccountIds` / `resolveAccount` / `inspectAccount` / `defaultAccountId`，并且 runtime monitor 用 `resolveTelegramAccount({cfg, accountId})` 启动指定账号；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/shared.ts:102-113`、`/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/monitor.ts:130-155`。
   - 因此本文 Phase 2 / Phase 3 / Phase 4 必须同时覆盖 Telegram，不允许只按 Feishu 实现。

4. 原文的“纯 account id”结论需要保留兼容层。
   - OpenClaw plugin runtime 的 `accountId` 是纯 ID，channel 单独作为 `channelId` 传递；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-374`。
   - Metis 现有 profile 使用过 `feishu:default`、`telegram:default`、`qq:default`；源码：`src/gateway/config/gateway_adapter_registration_profiles.cj:53-95`。
   - 因此 Phase 1 必须既规范化到纯 ID，又保留 `channel:default` 旧形态的读取兼容，不能一次性破坏历史状态、binding 展示或 control-ui 展示。

5. 原文 Phase 6 “agent 模型配置用户友好入口”不是 IM runtime autostart 的 OpenClaw 对齐项。
   - 这部分来自 Metis 当前用户问题：agent 有 IM account 但 model 为 null 时需要能单独配置模型。
   - 它应继续保留在计划中，但必须标记为 Metis agent UX 补齐项，不应作为 OpenClaw IM runtime autostart 的源码依据。

### 0.3 修正后的执行原则

1. 所有 IM runtime autostart 实现都必须先实现 account resolver，再实现 profile 枚举，再实现 account-scoped adapter，最后实现启动/状态/诊断。
2. 不允许只在 `agents add` 写配置后提示用户重启来规避问题；OpenClaw 的目标语义是 account 成为 runtime 一等实体，Metis 也必须做到。
3. 不允许 Feishu 做多账号 runtime，而 Telegram/QQ 仍停留在 default-only。
4. 不允许把 `channel:accountId` 展示格式直接当成 runtime 内部 accountId。内部使用纯 accountId，展示和 binding 可保留 `channel:accountId`。
5. 指定账号启动/停止是运行时一等能力，必须单独实现并单独验收；热重载、health monitor、Control UI 单账号操作、agent IM 自动启用都只能调用这条公共能力，不能各自手写启动逻辑。
6. 运行中 reconciliation 属于 Metis 架构落地项，必须复用同一套 profile enumeration 和 adapter factory，不能新增第二套启动逻辑。

### 0.4 OpenClaw 中 account 什么时候被启动为一等 runtime

OpenClaw 里，“已启用、已配置的 account 变成 runtime”不是发生在配置文件里出现 `accounts.<id>` 的瞬间，而是发生在 ChannelManager 执行 channel start 的时候。完整调用链如下。

#### 0.4.1 Gateway 正常启动时

1. Gateway server 创建 ChannelManager。
   - `server.impl.ts` 创建 `channelManager = createChannelManager(...)`，并把 `loadConfig`、channel logs、runtime env 传进去；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:721-731`。
   - 随后从 `channelManager` 解构出 `startChannels/startChannel/stopChannel/getRuntimeSnapshot`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:880-881`。

2. Gateway 启动 sidecars 时调用 `startChannels`。
   - `server.impl.ts` 在 `starting channels and sidecars...` 阶段调用 `startGatewaySidecars({ ..., startChannels, ... })`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:1413-1423`。
   - `server-startup.ts` 在启动流程里，如果没有设置 `OPENCLAW_SKIP_CHANNELS` 或 `OPENCLAW_SKIP_PROVIDERS`，会先预热 primary model，然后调用 `params.startChannels()`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-startup.ts:149-160`。

3. `startChannels` 启动每个 channel plugin。
   - `server-channels.ts` 的 `startChannels` 遍历 `listChannelPlugins()`，对每个 plugin 调用 `startChannel(plugin.id)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:516-526`。

4. `startChannel(channelId)` 枚举该 channel 下所有 account。
   - `startChannel` 调用 `startChannelInternal(channelId)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:454-456`。
   - `startChannelInternal` 如果没有传入指定 `accountId`，会执行 `plugin.config.listAccountIds(cfg)`，这一步就是把 default account 和命名 accounts 全部取出来；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-274`。

5. 对每个 account 做 enabled/configured 判断，然后调用 plugin 的 `startAccount`。
   - `startChannelInternal` 对每个 account 调用 `plugin.config.resolveAccount(cfg, id)`，再判断 `isEnabled` 和 `isConfigured`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:300-331`。
   - 只有 enabled 且 configured 的 account 才会被标记为 `running: true`，并调用 `plugin.gateway.startAccount({ cfg, accountId: id, account, ... })`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:351-374`。

6. 以 Feishu/Lark 为例，plugin 的 `startAccount` 会把 accountId 传给 provider monitor。
   - OpenClaw-Lark Feishu plugin 的 `gateway.startAccount` 会先 `getLarkAccount(ctx.cfg, ctx.accountId)`，再调用 `monitorFeishuProvider({ accountId: ctx.accountId })`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:318-330`。
   - `monitorFeishuProvider` 收到 `opts.accountId` 时只启动该账号；未指定时才启动所有 enabled accounts；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/monitor.ts:147-180`。

因此，OpenClaw 正常启动时的语义是：

```text
gateway run/start
  -> startGatewayServer
  -> createChannelManager
  -> startGatewaySidecars / server-startup
  -> startChannels()
  -> for each channel plugin: startChannel(channel)
  -> accountIds = plugin.config.listAccountIds(cfg)
  -> for each accountId:
       resolveAccount(cfg, accountId)
       if enabled && configured:
         plugin.gateway.startAccount({ accountId, account, ... })
```

#### 0.4.2 OpenClaw 配置热重载时

这里的“热重载”指：Gateway 进程不整体退出，运行中的进程检测到配置变化，计算哪些 channel 受影响，然后对受影响 channel 执行 stop + start。它是 OpenClaw 的能力，不是 Metis 当前已有能力。

OpenClaw 支持运行中配置变化后重启受影响 channel。

1. Channel plugin 声明哪些配置前缀变化需要重启 channel。
   - OpenClaw-Lark Feishu 声明 `reload: { configPrefixes: ['channels.feishu'] }`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:150-153`。
   - OpenClaw Telegram 声明 `reload: { configPrefixes: ["channels.telegram"] }`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/shared.ts:157`。

2. Gateway reload plan 把这些 channel config 变化转换为 `restart-channel:<id>`。
   - `config-reload-plan.ts` 会从所有 channel plugin 的 `plugin.reload.configPrefixes` 生成 hot reload rule，并把动作记录到 `plan.restartChannels`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload-plan.ts:120-128`、`175-194`。

3. reload handler 对受影响 channel 执行 stop + start。
   - `server-reload-handlers.ts` 对 `plan.restartChannels` 中的 channel 执行 `stopChannel(name)` 再 `startChannel(name)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-reload-handlers.ts:118-135`。
   - 因为 `startChannel(name)` 不传 accountId，所以它会再次走 `plugin.config.listAccountIds(cfg)`，重新枚举并启动所有 enabled/configured accounts。

因此，运行中的 OpenClaw 在 `channels.<channel>` 配置发生热重载时，新的 account 会通过 channel restart 被纳入 runtime；不是凭空监听 `accounts` 某个字段直接 new runtime，而是复用同一条 `stopChannel -> startChannel -> listAccountIds -> startAccount` 路径。

#### 0.4.3 指定账号启动时

OpenClaw 也有指定单个账号启动的路径。

1. `startChannel(channelId, accountId)` 传入 accountId 时，`startChannelInternal` 只启动该账号；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-274`。
2. 某些 Gateway web 方法在账号登录成功后会调用 `context.startChannel(provider.id, accountId)`，只启动刚登录成功的账号；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-methods/web.ts:103-112`。
3. health monitor 检测到需要恢复的账号时，也会对具体账号执行 `stopChannel(channelId, accountId)` 和 `startChannel(channelId, accountId)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/channel-health-monitor.ts:164-167`。

#### 0.4.4 对 Metis 方案的直接要求

Metis 要参考 OpenClaw，就不能只在 `agents add` 后写配置。正确落地应是：

1. Gateway 启动时，枚举 Telegram/Feishu/QQ 所有 configured/enabled accounts 并注册/启动对应 runtime。
2. Gateway 运行中，`agents add` 或 channel account 配置变更后，如果目标是“不重启即可可用”，Metis 需要新增显式 channel runtime reconcile 能力；这个能力不是 Metis 当前已有热重载，而是参考 OpenClaw `stopChannel -> startChannel` 的等价落地。
3. 手工启动单个账号时，应支持 `startChannel(channel, accountId)` 等价路径，便于后续 CLI/control-ui 做单账号重启。
4. 状态快照必须按 `channelId + accountId` 展示，而不是只看 default account。

### 0.5 Metis 当前没有 OpenClaw 式热重载

Metis 当前代码里没有 OpenClaw 那种配置文件 watcher + reload plan + channel restart 的完整链路。

当前 Metis 已有的是：

1. Gateway 启动时一次性注册并启动 adapter。
   - `GatewayService.registerAdapter` 注释说明适配器一般在 `start()` 前完成注册；源码：`src/gateway/core/gateway_service.cj:49-52`。
   - `GatewayService.start()` 调用 `this.channelManager.startChannels()`；源码：`src/gateway/core/gateway_service.cj:93-102`。
   - `GatewayChannelManager.startChannels()` 遍历已经注册好的 adapters，逐个调用 `entry.adapter.start()`；源码：`src/gateway/core/gateway_channel_manager.cj:426-468`。

2. adapter 注册发生在 Gateway 构建阶段。
   - `gateway_config_factory.cj` 通过 `gatewayBuiltinAdapterRegistrationProfiles(...)` 得到 profile，然后调用 `gateway.registerAdapter(...)`；源码：`src/gateway/runtime/gateway_config_factory.cj:135-185`。
   - 当前 profile 还存在 default-only 问题，导致多账号没有被注册成多个 runtime adapter。

3. Metis 有 `gateway.reload` 配置字段，但当前没有看到它驱动“配置变更后重启 channel account”的 OpenClaw 式机制。
   - `GatewayUserSettings` 里存在 `reload` 字段；源码：`src/core/config/gateway_user_settings.cj:582`。
   - 但 `rg` 没有发现类似 OpenClaw `startGatewayConfigReloader`、`buildGatewayReloadPlan`、`restartChannels` 的 Metis 实现。

4. Metis 当前文案也承认配置写入后需要重启运行中的 Gateway 才能加载设置。
   - `gatewayPluginHelpLines` 写着：`Plugin configuration writes update metis.json; restart gateway serve if the running process must reload settings.`；源码：`src/gateway/runtime/gateway_cli.cj:571-586`。

所以，本文后续 Phase 5 不能写成“利用 Metis 已有热重载”。更准确的落地描述应是：

- Phase 4：先补齐 Gateway 启动时多账号 autostart。这是当前 Metis 架构最自然、最小风险的闭环。
- Phase 4.5：补齐 OpenClaw 对齐的指定账号启动/停止能力，形成 `startChannel(channel, accountId)` / `stopChannel(channel, accountId)` 公共运行时入口。
- Phase 5：如果要求运行中的 Gateway 在 `agents add` 后立即可用，则新增“显式 channel runtime reconcile / hot reload”能力，复用 Phase 2/3/4/4.5 的 account 枚举、adapter factory 与指定账号启动能力。它不是已有热重载，必须作为 Metis 新能力实现。
- 如果 Phase 5 暂不实现，那么验收标准必须明确为“配置后重启 Gateway 可用”，不能宣称“配置后当前进程自动可用”。

## 1. 结论

用户执行 `metis agents add` 并传入 `--feishu`、`--telegram-bot-token`、`--qqbot` 后，合理产品语义应该是：

1. 对应 agent 被创建。
2. 对应 IM account 被写入 channel 配置。
3. 对应 route binding 被写入。
4. Gateway 下一次启动时会把这些已启用、已配置的 account 作为一等 runtime adapter 启动。
5. 如果配置写入动作发生在正在运行的 Gateway RPC 内，Gateway 应执行 channel runtime reconciliation，使新增 account 在同一进程内进入运行状态。

当前 Metis 已完成第 1、2、3 步，但第 4、5 步未完整闭环。结果是用户能在配置和 `gateway channel get feishu` 中看到 `feishu-writer`，但 Gateway 实际只启动 `feishu/default`，因此发给 `feishu-writer` 这个飞书机器人时不会进入对应 runtime。

这不是用户需要改绑定或换账号的问题，也不是单纯模型配置问题。模型配置与 IM runtime 启动是两个独立链路：

- `tg-writer`、`feishu-writer`、`qq-writer` 当前 `model` 为 `null`，语义是继承 `agents.defaults.model.primary`。
- Feishu 不回复的直接原因是 `feishu-writer` account 未作为 runtime adapter 启动。

## 2. 当前配置与日志事实

已核对用户当前配置，敏感字段未记录：

- `agents.list` 中存在 `tg-writer`、`feishu-writer`、`qq-writer`，三个 agent 的 `model` 均为 `null`。
- `bindings` 中存在：
  - `tg-writer <- telegram:tg-writer`
  - `feishu-writer <- feishu:feishu-writer`
  - `qq-writer <- qq:qq-writer`
- channel account 配置中存在：
  - `gateway.telegram.accounts.tg-writer`
  - `gateway.feishu.accounts.feishu-writer`
  - `gateway.qq.accounts.qq-writer`
- 最新 Gateway 日志仅出现 `channel=feishu account=default`、`channel=telegram account=default`、`channel=qq account=default` 的 start/timing 记录，没有 `account=feishu-writer`、`account=tg-writer`、`account=qq-writer` 的 runtime 启动记录。

## 3. OpenClaw / openclaw-lark 依据

### 3.1 账号枚举是 channel config 的基础能力

`openclaw-lark/src/core/accounts.ts`：

- 1-9 行说明 account override 位于 `cfg.channels.feishu.accounts`，每个 account 可覆盖顶层 Feishu 配置，未设置字段继承顶层默认。
- 85-108 行 `getLarkAccountIds(cfg)` 枚举所有账号；没有显式账号时返回默认账号；如果 `accounts` 存在且顶层也有默认机器人凭据，会把 `default` 与显式账号一起返回。
- 121-180 行 `getLarkAccount(cfg, accountId)` 将顶层配置与 account override 合并，计算 `enabled` 和 `configured`。

### 3.2 Gateway / plugin 入口以账号为单位启动

`openclaw-lark/src/channel/plugin.ts`：

- 167-170 行 channel config adapter 暴露 `listAccountIds`、`resolveAccount`、`defaultAccountId`。
- 318-330 行 Gateway `startAccount(ctx)` 以 `ctx.accountId` 为参数解析账号，并调用 `monitorFeishuProvider({ accountId: ctx.accountId })`。
- 276-311 行 status snapshot 以 account 为粒度展示 `running`、`lastStartAt`、`lastStopAt`、`lastError`、`probe`。

### 3.3 运行时支持全部启用账号并发启动

`openclaw-lark/src/channel/monitor.ts`：

- 45-124 行 `monitorSingleAccount` 为单个 account 创建 `LarkClient` 并启动 WebSocket。
- 147-160 行当指定 `opts.accountId` 时只启动一个账号。
- 163-180 行未指定账号时通过 `getEnabledLarkAccounts(cfg)` 获取所有已启用、已配置账号，并 `Promise.all` 并发启动。
- 169 行会输出 `feishu: starting N account(s): ...`，说明多账号不是只用于展示，而是实际 runtime 语义。

### 3.4 客户端缓存和发送链路以 accountId 隔离

`openclaw-lark/src/core/lark-client.ts`：

- 85-86 行 `LarkClient` cache 按 `accountId` 做 key。
- 177-203 行 `fromCfg/fromAccount` 按 account 解析并缓存客户端，凭据变化会替换旧实例。
- 344-395 行 `startWS` 用该 account 的凭据启动 WebSocket。
- 430-436 行缺少 `appId/appSecret` 会明确抛错。

### 3.5 多账号隔离不是附加功能，而是安全语义

`openclaw-lark/src/core/security-check.ts`：

- 38-68 行 `checkMultiAccountIsolation` 检查多个 Feishu 账号是否通过 bindings 隔离到不同 agent。
- 45-52 行绑定判断使用 `match.channel === 'feishu'` 与 `match.accountId`。
- 164-179 行生成隔离修复命令时，为每个 account 生成 agent 和 binding，并要求 gateway restart。

## 4. Metis 当前代码依据

### 4.1 配置层已有多账号结构

`src/gateway/channels/feishu/feishu_accounts.cj`：

- 34-37 行规范化 Feishu account id。
- 43-61 行 `gatewayFeishuListAccountIds(config)` 能枚举默认账号和 `config.accounts` 中的显式账号。
- 63-129 行 `gatewayFeishuResolveAccount(config, accountId)` 能把顶层配置和 account override 合并为 account-specific `FeishuConfig`。

`src/gateway/channels/qq/qq_accounts.cj`：

- 40-43 行规范化 QQ account id。
- 49-67 行 `gatewayQqListAccountIds(config)` 能枚举默认账号和显式账号。
- 69-130 行 `gatewayQqResolveAccount(config, accountId)` 能解析 account-specific `QQConfig`。

`src/gateway/runtime/gateway_server_methods_channels.cj`：

- 537-562 行 Feishu channel inspect 已能列出 `user.feishu.accounts` 与 default account。
- 1122-1151 行 Telegram channel inspect 已能列出 `user.telegram.accounts` 与 default account。

### 4.2 Feishu / Telegram adapter 已有 account-specific 能力

`src/gateway/channels/feishu/feishu_adapter.cj`：

- 351-364 行 `FeishuAdapter(config, accountId)` 构造函数已支持传入 accountId，并调用 `gatewayFeishuResolveAccount` 得到该账号配置。

`src/gateway/channels/telegram/telegram_adapter.cj`：

- 1297-1309 行 adapter 使用 `config.accountId` 作为 effective account id。
- 1334-1351 行按 `config.accounts[accountId]` 解析 account token。
- 3886-3901 行状态文件路径按 effective account id 分目录，说明 Telegram 已有 account 维度状态隔离。

### 4.3 QQ adapter 还缺少直接 accountId 构造参数

`src/gateway/channels/qq/qq_adapter.cj`：

- 45-49 行 `QQAdapter(config)` 当前只用 `config.accountId` 调用 `gatewayQqResolveAccount(config, config.accountId)`。
- 这意味着要注册 `qq-writer` runtime，必须先构造 account-specific `QQConfig(accountId: "qq-writer")`，或给 `QQAdapter` 增加与 `FeishuAdapter` 一致的 `accountId` 构造参数。

### 4.4 Runtime 注册仍只硬编码 default

`src/gateway/config/gateway_adapter_registration_profiles.cj`：

- 47-119 行 `gatewayBuiltinAdapterRegistrationProfiles` 固定注册一个 Feishu、一个 QQ、一个 Telegram profile。
- 55-56 行 Feishu profile 的 accountId 固定为 `feishu:default`。
- 70-71 行 QQ profile 的 accountId 固定为 `qq:default`。
- 85-86 行 Telegram profile 的 accountId 固定为 `telegram:default`。
- 该函数没有调用 Feishu/QQ/Telegram 的 account list helper，也没有枚举 `user.*.accounts`。

`src/gateway/runtime/gateway_config_factory.cj`：

- 135-136 行只创建一个 `FeishuAdapter(config: cfg.feishu)` 和一个 `QQAdapter(config: cfg.qq)`。
- 137-182 行遍历 profile 注册 adapter；由于 profile 只有 default，最终 runtime 也只有 default。
- 168-182 行 Telegram 虽然每次注册会构造 `TelegramAdapter(config: cfg.telegram, ...)`，但 profile 仍只有 default。

### 4.5 现有模型更新 RPC 存在，但 CLI 缺少一条直观更新命令

`src/gateway/runtime/gateway_server_methods_agents.cj`：

- 1800-1819 行 `gatewayAgentPutModelFromRequest` 支持 string 或 JSON object 模型配置。
- 1835-1925 行 `agents.update` 能更新 agent，并在模型、workspace、agentDir 变化时刷新 runtime model state。
- 3536-3542 行注册了 `agents.update` RPC。
- 3585-3599 行注册了 `agents.models.get/set` RPC。

`src/program/cli_local_flows.cj`：

- 2211-2235 行 `metis agents help` 暴露了 `agents add`、`bind`、`unbind`、`set-identity`、`delete` 等命令。
- 2269-2299 行通用 parser 能识别 `--agent`、`--workspace`、`--model`。
- 2613-2662 行当前只实现了 `set-identity` 和 `delete` 等分支，没有实现 `agents update --agent <id> --model <ref>` 这样的用户友好入口。

## 5. 目标行为

### 5.1 Account 配置后的默认启动语义

1. 如果 Gateway 未运行，用户配置 IM account 后，下一次 `metis gateway run` / `metis gateway serve` 必须枚举并启动所有已启用、已配置的 account。
2. 如果 Gateway 正在运行，且用户通过 Gateway RPC / CLI 创建 agent 并写入 IM account，Gateway 必须对 channel runtime 做 reconciliation：
   - 新增 account：创建并启动对应 adapter。
   - 删除 account：停止对应 adapter。
   - 凭据或启用状态变化：重建或停止对应 adapter。
3. runtime 中的 account id 使用纯 account id，例如 `default`、`feishu-writer`、`tg-writer`、`qq-writer`；CLI 展示和 binding 文案可以显示为 `feishu:feishu-writer`，但内部 registration key 不能混用 `feishu:default` 与 `default` 两套语义。

### 5.2 Agent 模型配置语义

1. 创建 agent 时，`metis agents add --agent feishu-writer --model dashscope:qwen3.6-plus ...` 应写入 agent 专属模型。
2. 已存在 agent 应支持用户友好的更新命令：`metis agents update --agent feishu-writer --model dashscope:qwen3.6-plus`。
3. 该命令必须复用现有 `agents.update` RPC，不新增第二套写配置逻辑。
4. 未显式配置模型的 agent 继续继承 `agents.defaults.model.primary`。

## 6. 分阶段落地方案与验收项

### Phase 0：补充失败刻画与源码对照文档

实施内容：

- 在现有 agent team / IM 文档中补充本文件链接，明确“config/account/binding 存在但 runtime 未启动 account”的故障模式。
- 增加 characterization test，构造包含 `feishu-writer`、`tg-writer`、`qq-writer` 的 `GatewayUserSettings`，证明当前 `gatewayBuiltinAdapterRegistrationProfiles` 只返回 default。

依据：

- Metis profile 硬编码 default：`src/gateway/config/gateway_adapter_registration_profiles.cj:47-119`。
- OpenClaw 枚举账号：`openclaw-lark/src/core/accounts.ts:85-108`。

验收项：

- 测试能在未修复代码上稳定失败，失败信息包含“expected configured account profile”。
- 文档包含 OpenClaw 与 Metis 的路径、行号、差异说明。
- 不读取真实用户 token，不打印真实 appSecret / botToken。

### Phase 1：统一 account id 规范

实施内容：

- 明确 runtime registration 的 `accountId` 只保存纯账号 ID：`default`、`feishu-writer`、`tg-writer`。
- 绑定展示继续使用 `channel:accountId`，例如 `feishu:feishu-writer`。
- 增加兼容读取逻辑，历史 profile 中的 `feishu:default`、`telegram:default`、`qq:default` 在状态查询和绑定匹配时能被规范化到 `default`。

依据：

- OpenClaw binding 使用 `match.channel` + `match.accountId`，其中 `accountId` 是纯账号 ID：`openclaw-lark/src/core/security-check.ts:45-52`。
- Metis 当前 profile 混用了 `feishu:default`：`src/gateway/config/gateway_adapter_registration_profiles.cj:55-56`。
- Metis 当前用户 binding 已是 `{channel:"feishu", accountId:"feishu-writer"}`。

验收项：

- 单元测试覆盖输入 `default`、`feishu:default`、`feishu-writer`、`feishu:feishu-writer` 的规范化。
- `metis gateway channel runtime feishu` 的账号列显示 `default`、`feishu-writer`，不显示 `feishu:default` 作为 runtime account id。
- routing binding 文案仍显示 `feishu:feishu-writer`，用户可读性不降低。

### Phase 2：注册 profile 枚举所有 configured/enabled accounts

实施内容：

- 将 `gatewayBuiltinAdapterRegistrationProfiles` 从固定三条 default 扩展为：
  - Feishu：调用 `gatewayFeishuListAccountIds(user.feishu)`。
  - QQ：调用 `gatewayQqListAccountIds(user.qq)`。
  - Telegram：新增或复用 Telegram account list helper，从 `defaultAccount` 与 `accounts` 中枚举。
- 每个 profile 的 `enabled`、`configured` 必须按 resolved account 计算，而不是只看顶层配置。

依据：

- Feishu list helper 已存在：`src/gateway/channels/feishu/feishu_accounts.cj:43-61`。
- QQ list helper 已存在：`src/gateway/channels/qq/qq_accounts.cj:49-67`。
- Telegram inspect 已能枚举 accounts：`src/gateway/runtime/gateway_server_methods_channels.cj:1122-1151`。
- OpenClaw channel plugin 通过 `listAccountIds` 暴露账号枚举：`openclaw-lark/src/channel/plugin.ts:167-170`。

验收项：

- 单元测试：只有顶层默认配置时，profile 仍包含 default。
- 单元测试：存在 `accounts.feishu-writer` 时，profile 包含 `default` 和 `feishu-writer`；如果 default 未配置且不启用，则只把它标记为 not configured 或不启动，行为要由测试固定。
- 单元测试：account override 中 `enabled:false` 的账号不会被 Gateway autostart，但会在 account status 中显示 disabled。
- 所有 profile 均不包含明文 secret。

### Phase 3：构造 account-scoped adapter

实施内容：

- Feishu：注册每个 profile 时构造 `FeishuAdapter(config: cfg.feishu, accountId: profile.accountId)`。
- Telegram：为每个 profile 构造 account-specific `TelegramConfig(accountId: profile.accountId, accounts: cfg.telegram.accounts, ...)`，保持现有 account token 解析逻辑。
- QQ：给 `QQAdapter` 增加 `accountId` 构造参数，内部调用 `gatewayQqResolveAccount(config, requestedAccountId)`；或构造 account-specific `QQConfig(accountId: profile.accountId)`。优先采用与 Feishu 一致的构造参数，减少调用方复制配置字段。

依据：

- Feishu adapter 构造参数已支持 `accountId`：`src/gateway/channels/feishu/feishu_adapter.cj:351-364`。
- Telegram adapter 用 `config.accountId` 解析 account token：`src/gateway/channels/telegram/telegram_adapter.cj:1297-1351`。
- QQ adapter 目前只读取 `config.accountId`：`src/gateway/channels/qq/qq_adapter.cj:45-49`。
- OpenClaw `LarkClient.fromAccount(account)` 为每个 account 创建独立客户端：`openclaw-lark/src/core/lark-client.ts:186-203`。

验收项：

- Gateway config factory 测试断言 `feishu-writer` runtime 的 adapter 内部 account id 为 `feishu-writer`。
- Telegram account state path 使用 `/accounts/tg-writer/`，不落到 `/accounts/default/`。
- QQ `qq-writer` 缺凭据时错误信息包含 `qq-writer`，不是 default。
- 多个 account 不能共享同一个可变 adapter 实例，避免 running 状态、token cache、inbound queue 串扰。

### Phase 4：Gateway 启动时 autostart 所有 account runtimes

实施内容：

- `gateway_config_factory.cj` 遍历扩展后的 profile，为每个 configured/enabled account 注册 adapter。
- `startChannels` 应对所有 configured/enabled profile 调用 start。
- runtime/status 日志必须包含 channel 与 account，例如 `channel=feishu account=feishu-writer`。

依据：

- Metis 当前注册点：`src/gateway/runtime/gateway_config_factory.cj:135-182`。
- OpenClaw 启动所有 enabled accounts：`openclaw-lark/src/channel/monitor.ts:163-180`。

验收项：

- 使用隔离 `METIS_HOME` 构造三个账号后启动 Gateway，日志出现：
  - `channel=telegram account=tg-writer`
  - `channel=feishu account=feishu-writer`
  - `channel=qq account=qq-writer`
- `metis gateway channel runtime feishu` 显示 `default` 与 `feishu-writer` 两行，并且能区分 running / configured / enabled。
- 没有配置凭据的 account 不会假装 running。

### Phase 4.5：补齐指定账号启动/停止能力

本 Phase 是新增的 OpenClaw 对表 GAP。它必须独立于 Phase 5 热重载存在，因为“指定账号启动/停止”不是热重载私有实现，而是 Gateway runtime 的公共能力。后续热重载、health monitor、Control UI 单账号操作、CLI 单账号操作、agent 配置 IM 入口后的自动启用，都应该调用这一条公共能力。

#### Phase 4.5.0：确认 GAP 与边界

实施内容：

- 明确 OpenClaw 已支持指定账号启动/停止，Metis 主 runtime 当前不支持。
- 明确 Metis 现有 `channels.start` / `channels.stop` RPC 不是本 GAP 的解决方案，因为它走的是 host-backed legacy plugin forwarder，不是 Telegram/Feishu/QQ native Gateway runtime 的 account adapter 生命周期入口。
- 明确本 Phase 只补 Gateway native runtime 的 `channel + accountId` 启停能力，不在 `agents.add`、`agents.update` 中直接 new adapter 或直接启动 adapter。

OpenClaw 源码依据：

- OpenClaw `ChannelManager` 类型直接暴露 `startChannel(channel, accountId?)`、`stopChannel(channel, accountId?)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:144-149`。
- OpenClaw server 从 channel manager 解构 `startChannels/startChannel/stopChannel`，并把 `startChannel/stopChannel` 注入 reload handler；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:880-881`、`1439-1460`。
- OpenClaw health monitor 对单个账号执行 `stopChannel(channelId, accountId)`、`startChannel(channelId, accountId)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/channel-health-monitor.ts:158-167`。

Metis 当前源码依据：

- Metis `GatewayChannelManager` 当前只有 `startChannels()` 和 `stopChannels()`，没有 `startChannel(channelId, accountId)`、`stopChannel(channelId, accountId)`；源码：`src/gateway/core/gateway_channel_manager.cj:426-495`。
- Metis `GatewayService` 当前只暴露整体 `start()` / `stop()`，没有单 channel/account lifecycle 入口；源码：`src/gateway/core/gateway_service.cj:93-113`。
- Metis `channels.start` / `channels.stop` 当前调用 `gatewayChannelActionByPlugin(..., "start"|"stop")`，内部依赖 `gatewayHostCompatiblePluginForChannel` 与 legacy host；源码：`src/gateway/runtime/gateway_server_methods_channels.cj:1462-1504`、`2513-2528`。这不是 native `GatewayChannelManager` 的指定账号启动能力。

验收项：

- 文档验收：本 Phase 必须把 OpenClaw `startChannel(channel, accountId?)` 与 Metis 缺失点并排列出，不能只写“后续热重载会处理”。
- 单元测试验收：新增一个 characterization test，在实现前能说明 Metis 没有可调用的 native `startChannel(channel, accountId)` API；实现后该测试改为验证 API 存在并可启动指定 fake account。
- 边界验收：`agents.add` / `agents.update` 不允许直接调用 adapter.start，不允许绕过 GatewayChannelManager。

#### Phase 4.5.1：定义 native ChannelManager 单账号生命周期 API

实施内容：

- 在 `GatewayChannelManager` 增加 native API：
  - `startChannel(channelId: String, accountId!: String = "")`
  - `stopChannel(channelId: String, accountId!: String = "", reason!: String = "manual-stop", manualStop!: Bool = true)`
  - `restartChannel(channelId: String, accountId!: String = "", reason!: String = "restart")`
- `accountId` 为空时表示该 channel 下所有已注册 account；`accountId` 非空时只处理该账号。
- 所有 account id 进入 ChannelManager 前都必须走 `gatewayCanonicalChannelAccountId(channelId, rawAccountId)`，内部 runtime key 使用纯 account id。
- `startChannel(channelId, accountId)` 不能被 `started` 总开关挡住。`started` 只能表达“整体 startChannels 是否执行过”，不能阻止运行中新增账号启动。

OpenClaw 源码依据：

- OpenClaw `startChannelInternal(channelId, accountId?)` 传入 accountId 时 `accountIds = [accountId]`，未传时 `plugin.config.listAccountIds(cfg)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-274`。
- OpenClaw `stopChannel(channelId, accountId?)` 传入 accountId 时清空 knownIds 后只加入该 account；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:458-475`。

Metis 当前源码依据：

- Metis `GatewayRegisteredAdapter` 已经保存 canonical `channelId/accountId/rawAccountId`，具备实现单账号 lifecycle 的数据基础；源码：`src/gateway/core/gateway_channel_manager.cj:73-115`。
- Metis 当前 `startChannels()` 在 426-468 行整体遍历 adapters，并在 467 行设置 `started=true`，因此新增 `startChannel` 必须绕开整体 guard，仅检查目标 entry 的运行状态。

验收项：

- 单元测试：注册 `telegram/default`、`telegram/tg-writer`、`feishu/default` 三个 fake adapters 后，调用 `startChannel("telegram", accountId: "tg-writer")` 只启动 `tg-writer`。
- 单元测试：调用 `startChannel("telegram")` 启动 Telegram 下所有已注册 accounts，不启动 Feishu。
- 单元测试：调用 `startChannels()` 后再注册 `telegram/tg-live`，再调用 `startChannel("telegram", accountId: "tg-live")`，`tg-live.start()` 被调用一次。
- 单元测试：`startChannel("telegram", accountId: "telegram:tg-writer")` 与 `startChannel("telegram", accountId: "tg-writer")` 等价，runtime 中显示纯 `tg-writer`。

#### Phase 4.5.2：补齐单账号 stop/restart 与状态语义

实施内容：

- `stopChannel(channelId, accountId)` 只停止指定 account adapter，并更新 live runtime state：
  - `running=false`
  - `connected=false`
  - `lastError=""` 或 sanitized stop reason
  - runtime state 标记 stopped
- `restartChannel(channelId, accountId)` 必须等价于 `stopChannel(channelId, accountId, manualStop:false)` 后 `startChannel(channelId, accountId)`。
- 单账号 stop 不能把整个 ChannelManager 的 `started` 置为 false；只有整体 `stopChannels()` 才能改变整体 started 状态。
- stop/restart 失败必须记录到指定 account，不得污染同 channel 的其他 accounts。

OpenClaw 源码依据：

- OpenClaw `stopChannel` 按 account 遍历并调用 plugin `stopAccount`，然后 `setRuntime(channelId, id, { running:false, lastStopAt })`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:477-514`。
- OpenClaw health monitor 单账号恢复路径是：如果该账号 running，先 stop；再 reset restart attempts；再 start 同一个 account；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/channel-health-monitor.ts:158-167`。

Metis 当前源码依据：

- Metis `stopChannels()` 当前会遍历全部 adapters，最后 `this.started=false`；源码：`src/gateway/core/gateway_channel_manager.cj:471-495`。单账号 stop 必须避免复用这个整体语义导致误停其他 account。
- Metis `gatewayChannelRuntimeMarkStopped` 已按 `channelId/accountId` 记录 runtime stopped；当前 `stopChannels()` 已调用该函数；源码：`src/gateway/core/gateway_channel_manager.cj:477-483`。

验收项：

- 单元测试：`stopChannel("telegram", accountId: "tg-writer")` 只调用 `tg-writer.stop()`，`telegram/default` 仍 running。
- 单元测试：`restartChannel("telegram", accountId: "tg-writer")` 调用顺序必须是 `tg-writer.stop()` 后 `tg-writer.start()`。
- 单元测试：`stopChannel("telegram", accountId: "missing")` 返回清晰的 `account-not-registered` 或同等诊断，不影响其他 accounts。
- 状态验收：`gateway channel runtime telegram` 中 `tg-writer.running=false`，default 不变。

#### Phase 4.5.3：补齐指定账号 adapter 注册与按需构造

实施内容：

- `startChannel(channelId, accountId)` 如果目标 account adapter 已注册，则直接启动已注册 adapter。
- 如果目标 account adapter 未注册，但配置中存在该 account，则调用 Phase 2/3 的 profile enumeration 与 adapter factory 构造该 account adapter，再注册并启动。
- 如果配置中不存在该 account，返回 `account-not-configured`。
- 如果 account 存在但 disabled，更新 runtime row 为 disabled，不调用 adapter.start。
- 如果 account 存在但凭据不完整，更新 runtime row 为 configured=false 或 start failed，错误信息必须 sanitized。

OpenClaw 源码依据：

- OpenClaw `startChannelInternal` 启动前会 `plugin.config.resolveAccount(cfg, id)`，再检查 enabled/configured；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:300-331`。
- OpenClaw configured 且 enabled 后才调用 `startAccount({ cfg, accountId: id, account, ... })`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:351-374`。

Metis 当前源码依据：

- Metis adapter 构造集中在 `gateway_config_factory.cj`，当前启动时通过 profiles 注册 adapters；源码：`src/gateway/runtime/gateway_config_factory.cj:135-185`。
- 本文 Phase 2/3 要把 profile enumeration 与 adapter factory 抽成可复用能力；Phase 4.5 必须使用这套能力，不能在 ChannelManager 中手写 Telegram/Feishu/QQ 构造细节。

验收项：

- 单元测试：配置中存在 `gateway.telegram.accounts.tg-writer`，但启动时未注册 adapter；调用 `startChannel("telegram", accountId:"tg-writer")` 后，factory 被调用一次，adapter 被注册并启动。
- 单元测试：配置中不存在 `tg-missing` 时，返回 `account-not-configured`，不创建空 adapter。
- 单元测试：disabled account 不启动 adapter，runtime 显示 disabled。
- 复用验收：代码 review 或测试必须证明单账号按需构造调用的是统一 adapter factory，不出现第二套 `TelegramAdapter/FeishuAdapter/QQAdapter` 构造路径。

#### Phase 4.5.4：暴露 Gateway RPC、CLI 与 Control UI 可用的指定账号启停入口

实施内容：

- 新增 native Gateway RPC：
  - `channels.start` 支持 native Telegram/Feishu/QQ，参数 `channelId`、`accountId`。
  - `channels.stop` 支持 native Telegram/Feishu/QQ，参数 `channelId`、`accountId`。
  - `channels.restart` 或 `channels.reload` 支持 native Telegram/Feishu/QQ，参数 `channelId`、`accountId`。
- 现有 legacy host-backed plugin forwarder 继续保留，但 native channel 应优先走 native GatewayChannelManager，不再返回 `channel-not-legacy-compatible`。
- CLI 增加用户可读命令：
  - `metis gateway channel start telegram --account tg-writer`
  - `metis gateway channel stop telegram --account tg-writer`
  - `metis gateway channel restart telegram --account tg-writer`
- 默认输出必须是人类可读摘要；`--json` 才输出完整结构化结果。
- Control UI 后续可以调用同一 RPC，不需要再新增第二套 browser-only 启停逻辑。

OpenClaw 源码依据：

- OpenClaw server 将 `startChannel/stopChannel` 作为 gateway server 能力注入 reload handler 和其他 runtime consumer；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:880-881`、`1439-1460`。
- OpenClaw `ChannelManager` 单账号 API 是公共 runtime 能力，不绑定某个 CLI 命令；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:144-149`。

Metis 当前源码依据：

- Metis Gateway HTTP surface 已暴露 `gateway.channels.start`、`gateway.channels.stop`，但描述为 host-backed runtime forwarder；源码：`src/gateway/runtime/gateway_http_surface.cj:432-433`。
- Metis `gateway channel` CLI 帮助当前没有 start/stop/restart 命令；源码：`src/gateway/runtime/gateway_cli.cj:481-493`。
- Metis `channels.start/stop` 当前走 `gatewayChannelActionByPlugin` legacy path；源码：`src/gateway/runtime/gateway_server_methods_channels.cj:2513-2528`、`1462-1504`。

验收项：

- CLI 验收：`metis gateway channel start telegram --account tg-writer` 输出：
  - `Channel: telegram`
  - `Account: tg-writer`
  - `Action: start`
  - `Result: started` 或明确失败原因
- CLI 验收：默认输出不是大 JSON；`--json` 时包含 `channelId/accountId/action/runtime`。
- RPC 验收：`channels.start` 对 `telegram/tg-writer` 返回 native runtime kind，不返回 `channel-not-legacy-compatible`。
- Control UI 契约验收：同一 RPC 参数可被 Control UI 调用，结果结构包含足够字段用于按钮状态展示。

#### Phase 4.5.5：指定账号启动与 agent 配置 IM 入口自动启用的关系

实施内容：

- 明确 `metis agents add --agent tg-writer --telegram-bot-token ...` 的完整链路：
  1. `agents.add` 写入 agent entry。
  2. `agents.add` 写入 `gateway.telegram.accounts.tg-writer` 或指定 `--telegram-account` 的 account。
  3. `agents.add` 写入 route binding：`{ channel:"telegram", accountId:"tg-writer", agentId:"tg-writer" }`。
  4. 如果 Gateway 未运行，Phase 4 的启动时 autostart 在下一次 `gateway run` 时启动该 account。
  5. 如果 Gateway 正在运行，Phase 5 的 hot reload/reconcile 检测到 `gateway.telegram.accounts.tg-writer` 变化后，调用 Phase 4.5 的 `startChannel("telegram", accountId:"tg-writer")` 或 `reconcileChannel("telegram", ...)`。
- `agents.add` 不能直接启动 adapter。它只能写配置；运行时自动启用必须通过 Phase 5 reloader/reconcile 调用 Phase 4.5 公共能力。
- 单纯 `agents.bind/unbind` 只改变 route，不代表 channel account 凭据变化，不应该触发 channel account start；除非 binding 操作同时创建了新的 channel account 配置。
- 指定账号启动能力是 agent IM 入口自动启用的执行器，热重载是触发器，配置写入是来源。三者职责必须分开。

OpenClaw 源码依据：

- OpenClaw config reload plan 把 channel config prefix 变化转换成 `restart-channel:<id>`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload-plan.ts:120-128`、`175-235`。
- OpenClaw reload handler 对 affected channel 调用 `stopChannel(name)`、`startChannel(name)`，而不是在配置写入命令里直接启动 provider；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-reload-handlers.ts:118-135`。
- OpenClaw `startChannel(name)` 最终仍走同一套 account list/resolve/startAccount 逻辑；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-374`。

Metis 当前源码依据：

- Metis `agents.add` 当前已在一个事务式流程里写入 agent、channel credentials、binding，并最终调用 `MetisConfigManager.writeRoot(root)`；源码：`src/gateway/runtime/gateway_server_methods_agents.cj:1622-1724`。
- Metis `agents.bind/unbind` 当前只写 route binding，并调用 `MetisConfigManager.writeRoot`；源码：`src/gateway/runtime/gateway_server_methods_agents.cj:1568-1574`、`1608-1613`。
- Metis 当前没有 reloader，因此 `agents.add` 写配置后正在运行的 Gateway 不会自动启动新增 account；这一点在 0.5 节和 Phase 5 中已经确认。

验收项：

- 手工验收：Gateway 未运行时执行 `agents add --agent tg-writer --telegram-bot-token fake:token`，然后启动 Gateway，`gateway channel runtime telegram` 出现 `tg-writer`。
- 手工验收：Gateway 正在运行且 `gateway.reload.mode=hybrid` 时执行同一命令，无需重启，`gateway channel runtime telegram` 出现 `tg-writer`；fake token 可以启动失败，但不能是 account runtime 缺失。
- 单元测试：`agents.add` 不直接调用 `adapter.start()`，只触发 `writeRoot`；reloader/reconcile 才调用 `startChannel`。
- 单元测试：只执行 `agents bind --agent tg-writer --bind telegram:tg-writer` 时，如果没有新增或修改 `gateway.telegram.accounts.tg-writer`，不调用 `startChannel("telegram","tg-writer")`。
- 诊断验收：自动启用失败时，CLI/RPC 输出必须区分：
  - 配置写入成功但 reload disabled。
  - reload 触发但 account not configured。
  - account configured 但 adapter start failed。
  - account started 但 route binding 缺失。

### Phase 5：新增 Metis 配置热重载与运行中 channel runtime reconciliation

前置澄清：

1. Metis 当前没有 OpenClaw 式“配置文件 watcher + reload plan + hot reload handler + channel stop/start”的完整链路。Metis 只有配置结构 `gateway.reload.mode/debounceMs/deferralTimeoutMs`，源码：`src/core/config/gateway_user_settings.cj:164-169`、`578-582`，以及运行时配置类 `GatewayReloadConfig`，源码：`src/gateway/model/config.cj:251-264`。
2. 本 Phase 要新增的是 Metis 自己的热重载能力，不是把 OpenClaw TypeScript 代码直接搬进 Cangjie。必须参考 OpenClaw 的语义和边界：配置变化先进入 reloader，reloader 计算 reload plan，hot plan 交给 handler，handler 对受影响 channel 执行 `stopChannel -> startChannel`。
3. 本 Phase 的首要目标是解决“Gateway 正在运行时，`agents add` / `agents update` / channel account 配置写入后，新增或修改的 Telegram/Feishu/QQ account 立即成为 runtime adapter”的问题。对于无法 hot reload 的配置变化，只允许标记为 `restartRequired` 并给出诊断，不允许假装已经热重载成功。
4. 本 Phase 不新增第二套 account/adapter 枚举逻辑，必须复用 Phase 2/3/4 的 profile enumeration 与 adapter factory。OpenClaw 同样复用 `startChannel` 的账号枚举路径，而不是为热重载单独写一套账号启动逻辑；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-274`、`300-374`、`516-526`。

#### Phase 5.0：锁定 OpenClaw 热重载语义与 Metis 边界

实施内容：

- 在本文件保留 OpenClaw 热重载源码证据，作为后续实现和 review 的硬依据。
- 明确 Metis Phase 5 的最小完整闭环是：
  - 读到配置变更。
  - 计算 changed paths。
  - 建立 reload plan。
  - 对 Telegram/Feishu/QQ 的 channel account 变化执行 channel restart/reconcile。
  - 把成功、跳过、失败、需要重启等结果记录到 runtime status。
- 明确暂不实现 OpenClaw 的 hooks、cron、gmail watcher 等非 IM runtime 热重载动作，只在 plan 中保留 `restartGateway/restartRequired` 诊断位置，防止后续误判。

OpenClaw 源码依据：

- OpenClaw reloader 入口 `startGatewayConfigReloader` 接收 `initialConfig`、`readSnapshot`、`onHotReload`、`onRestart`、`subscribeToWrites`、`watchPath`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:77-90`。
- OpenClaw reload plan 的核心字段包含 `changedPaths`、`restartGateway`、`restartReasons`、`hotReasons`、`restartChannels`、`noopPaths`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload-plan.ts:6-18`。
- OpenClaw Gateway server 在启动时创建 `createGatewayReloadHandlers`，再把 `applyHotReload/requestGatewayRestart` 传给 `startGatewayConfigReloader`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:1436-1517`。

Metis 当前源码依据：

- Metis adapter 一般在 `GatewayService.start()` 前注册；源码注释：`src/gateway/core/gateway_service.cj:49-52`。
- Metis `GatewayService.start()` 当前只调用一次 `this.channelManager.startChannels()`；源码：`src/gateway/core/gateway_service.cj:93-102`。
- Metis `GatewayChannelManager.startChannels()` 当前有 `started` guard，已启动后再次调用会直接返回；源码：`src/gateway/core/gateway_channel_manager.cj:426-468`。因此 Phase 5 必须新增可重入的 channel/account restart/reconcile API，不能只在热重载时再次调用现有 `startChannels()`。

验收项：

- 文档验收：Phase 5.0 必须列出上述 OpenClaw 和 Metis 源码路径及行号，不允许只写“参考 OpenClaw”。
- 设计验收：任何后续实现 PR 中，如果新增的热重载逻辑没有经过 changed paths -> reload plan -> apply hot reload/restart required 这三段，就判定为偏离 OpenClaw 语义。
- 范围验收：Phase 5 只负责 Gateway 配置热重载与 IM channel runtime reconciliation，不把模型调用、Control UI 页面、agent prompt 文件编辑混入本阶段。

#### Phase 5.1：新增 Metis reload snapshot、diff 与 mode 语义

实施内容：

- 新增 Cangjie 侧的 reload snapshot 数据结构，至少包含：
  - `exists: Bool`
  - `valid: Bool`
  - `config: JsonObject`
  - `hash: String`
  - `issues: Array<String>`
  - `path: String`
- 新增 changed paths 计算函数，对比当前 snapshot 与下一份 snapshot，输出类似 `gateway.telegram.accounts.tg-writer.botToken`、`gateway.feishu.accounts.feishu-writer.appSecret`、`agents.bindings` 的路径。
- 使用既有 `gateway.reload.mode` 字段承接 OpenClaw mode 语义：
  - `off`：检测到变化但不执行热重载。
  - `hot`：只执行 hot reload；遇到必须重启的路径时记录 warning，不自动重启。
  - `restart`：不执行 hot reload，直接标记 `restartRequired`。
  - `hybrid`：可 hot reload 的路径执行 hot reload；不可 hot reload 的路径标记 `restartRequired`。
- `debounceMs` 使用现有 `gateway.reload.debounceMs`；`deferralTimeoutMs` 保留给后续“繁忙时延迟热重载”使用，本阶段不得删除或改义。

OpenClaw 源码依据：

- OpenClaw reloader 内部维护 `currentConfig`、`settings`、`debounceTimer`、`pending`、`running`、`restartQueued`、`pendingInProcessConfig`、`lastAppliedWriteHash`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:91-100`。
- OpenClaw 用 `scheduleAfter(settings.debounceMs)` 做 debounce；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:102-115`。
- OpenClaw `applySnapshot` 中计算 `diffConfigPaths(currentConfig, nextConfig)`，再按 mode 处理 `off/restart/hot/hybrid` 类语义；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:159-190`。

Metis 当前源码依据：

- `GatewayReloadUserSettings` 已有 `mode`、`debounceMs`、`deferralTimeoutMs`；源码：`src/core/config/gateway_user_settings.cj:164-169`。
- `buildGatewayReloadConfig` 已将用户配置映射到 Gateway runtime config；源码：`src/gateway/config/gateway_config_builder.cj:156-162`。

验收项：

- 单元测试：两个 JsonObject 只差 `gateway.telegram.accounts.tg-writer.botToken` 时，changed paths 精确包含该路径，不把整个 `gateway` 都标记为变化。
- 单元测试：`gateway.reload.mode=off` 时，检测到 channel account 变化后不调用 ChannelManager restart/reconcile，状态里记录 `reloadDisabled` 或同等诊断。
- 单元测试：`mode=restart` 时，channel account 变化不执行 hot reload，而是返回 `restartRequired=true` 与原因路径。
- 单元测试：`mode=hot` 且遇到非 hot path 时，记录 warning，不执行错误的 channel restart。
- 安全验收：diff 日志不得包含 `botToken`、`appSecret`、`apiKey`、authorization header 的明文值，只能包含路径名。

#### Phase 5.2：新增 Metis 配置变更输入源：进程内写入通知与文件变化探测

实施内容：

- 为 `MetisConfigManager.writeRoot(root)` 增加进程内配置写入通知能力：写入成功后通知 reloader “这里有一份已经写入磁盘、同时可直接作为 runtime config 使用的新 root”。
- 通知对象至少包含：
  - `configPath`
  - `sourceRoot`
  - `runtimeRoot`
  - `persistedHash`
  - `writtenAtMs`
- `agents.add`、`agents.update`、`agents.bind`、`agents.unbind`、channel account 配置写入等现有路径不新增第二套写文件逻辑，仍然只调用现有 `MetisConfigManager.writeRoot`，由 `writeRoot` 统一发通知。
- 增加外部文件变化探测。OpenClaw 使用 `chokidar.watch`；Metis 是 Cangjie 项目，不引入 Node/chokidar，采用“配置文件 hash/mtime 轮询 + debounce”的等价方案，触发语义对齐 OpenClaw watcher。
- 对删除、缺失、非法 JSON 的配置快照只记录诊断和重试，不清空当前运行中的配置。

OpenClaw 源码依据：

- OpenClaw `ConfigWriteNotification` 包含 `configPath/sourceConfig/runtimeConfig/persistedHash/writtenAtMs`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/config/io.ts:250-256`。
- OpenClaw 维护 `configWriteListeners` 并提供 `registerConfigWriteListener`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/config/io.ts:2397-2420`。
- OpenClaw reloader 订阅内部写入后，直接使用 `event.runtimeConfig`，并 `scheduleAfter(0)`，避免再读一次磁盘；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:249-257`。
- OpenClaw 同时用 `chokidar.watch` 监听 `add/change/unlink`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:239-261`。
- OpenClaw 对缺失配置做有限重试，对非法配置跳过，不破坏当前运行态；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:133-157`。

Metis 当前源码依据：

- `MetisConfigManager.writeRoot(root)` 是当前集中写入点：写文件、更新 `_raw`、invalidate CLI settings、刷新模型 runtime state；源码：`src/core/config/metis_config_manager.cj:2013-2019`。
- `agents.bind`、`agents.unbind`、`agents.add`、`agents.update` 等路径已经调用 `MetisConfigManager.writeRoot`；源码：`src/gateway/runtime/gateway_server_methods_agents.cj:1570`、`1609`、`1724`、`1905`。

验收项：

- 单元测试：调用 `MetisConfigManager.writeRoot` 后，注册的 reload listener 收到一次通知，通知里的 `configPath` 等于当前隔离 `METIS_HOME` 下的 `metis.json`。
- 单元测试：进程内通知路径下，reloader 不再额外读取磁盘快照；这对齐 OpenClaw `config-reload.test.ts` 中 “internal write event avoids reread” 的断言，源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.test.ts:550-562`。
- 单元测试：外部直接改写 `metis.json` 后，轮询探测在 `debounceMs` 后触发一次 reload，不因同一时间窗口内多次写入重复执行多次。
- 单元测试：配置文件被短暂删除时，reloader 记录 retry/skipped 诊断，不停止已运行的 Telegram/Feishu/QQ adapters；对齐 OpenClaw 缺失快照测试，源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.test.ts:418-443`。
- 安全验收：测试使用隔离 `METIS_HOME`，不得读取真实 `~/.metis/metis.json`。

#### Phase 5.3：新增 Metis reload plan builder，明确哪些配置可热重载

实施内容：

- 新增 `GatewayReloadPlan` 的 Cangjie 等价结构，至少包含：
  - `changedPaths`
  - `restartGateway`
  - `restartReasons`
  - `hotReasons`
  - `restartChannels`
  - `noopPaths`
- 建立第一批 Metis hot reload 规则：
  - `gateway.telegram`、`gateway.telegram.accounts`、`gateway.telegram.accounts.<id>` -> restart channel `telegram`
  - `gateway.feishu`、`gateway.feishu.accounts`、`gateway.feishu.accounts.<id>` -> restart channel `feishu`
  - `gateway.qq`、`gateway.qq.accounts`、`gateway.qq.accounts.<id>` -> restart channel `qq`
  - `agents.bindings`、`agents.list` 中与 channel binding 或 agent model 相关的变化，如果运行时读取是动态的，则可标记为 `noopPaths` 或专门的 agent runtime refresh；不能误触发 IM channel restart，除非同时写入 channel account。
  - 未列入规则的路径默认 `restartGateway=true`，不能静默忽略。
- 如果一次配置变化同时影响多个 IM channel，plan 必须包含多个 `restartChannels`，且 handler 按集合逐个处理。

OpenClaw 源码依据：

- OpenClaw 通过 channel plugin 的 `reload.configPrefixes` 自动生成热重载规则；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload-plan.ts:120-128`。
- OpenClaw `buildGatewayReloadPlan` 遍历 changed paths：未匹配规则则 `restartGateway=true`，匹配 `restart-channel:<id>` 则加入 `plan.restartChannels`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload-plan.ts:175-235`。
- OpenClaw-Lark Feishu 声明 `reload: { configPrefixes: ['channels.feishu'] }`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:149-153`。
- OpenClaw Telegram 声明 `reload: { configPrefixes: ["channels.telegram"] }`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/telegram/src/shared.ts:156-158`。

Metis 当前源码依据：

- Metis 配置结构使用 `gateway.telegram`、`gateway.feishu`、`gateway.qq`，不是 OpenClaw 的 `channels.telegram` 命名；本文规则必须映射到 Metis 现有配置路径，不能照抄路径名。
- Metis channel account 配置已存在于 `gateway.telegram.accounts`、`gateway.feishu.accounts`、`gateway.qq.accounts`，前文第 2 节已核对用户配置事实。

验收项：

- 单元测试：`["gateway.telegram.accounts.tg-writer.botToken"]` 生成 `restartGateway=false`、`restartChannels={"telegram"}`。
- 单元测试：`["gateway.feishu.accounts.feishu-writer.appSecret", "gateway.qq.accounts.qq-writer.appSecret"]` 生成 `restartChannels={"feishu","qq"}`。
- 单元测试：`["gateway.auth.token"]` 生成 `restartGateway=true`，不执行 channel restart。
- 单元测试：`["agents.bindings"]` 不应默认导致所有 IM channel restart；如果实现选择 route runtime refresh，则验收 route refresh 被调用。
- 对照验收：Metis plan builder 必须有一条测试等价 OpenClaw `config-reload.test.ts` 中 provider config prefix 会重启 provider 的用例；OpenClaw 测试源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.test.ts:163-177`。

#### Phase 5.4：热重载 reconcile 复用 Phase 4.5 指定账号生命周期 API

实施内容：

- Phase 4.5 已经负责新增 `startChannel(channelId, accountId)`、`stopChannel(channelId, accountId)`、`restartChannel(channelId, accountId)`。本节不再重复定义指定账号启停，而是补齐热重载使用的 `reconcileChannel(channelId, profiles)`。
- `reconcileChannel` 必须调用 Phase 4.5 的公共生命周期 API，不能直接调用 adapter.start/stop。
- `reconcileChannel(channelId, profiles)` 处理三类差异：
  - 新 profile：注册并启动。
  - 已存在 profile 但配置签名变化：停止旧 adapter，替换为新 adapter，再启动。
  - 旧 adapter 在新 profile 中不存在或 disabled：停止 adapter，状态标记为 not running。
- `adapterByName` 不能继续只以 channel name 作为唯一 key 覆盖多账号 adapter；需要使用 `channelId + accountId` 作为 runtime key，同时保留按 channel 获取 default adapter 的兼容能力。
- 运行中 reconcile 的行为必须可解释：新增 account 是 `register -> startChannel(channel, account)`；凭据变化是 `stopChannel(channel, account) -> replace adapter -> startChannel(channel, account)`；删除或 disabled 是 `stopChannel(channel, account) -> mark disabled/stopped`。

OpenClaw 源码依据：

- OpenClaw `ChannelManager` 类型直接暴露 `startChannel(channel, accountId?)` 与 `stopChannel(channel, accountId?)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:144-149`。
- OpenClaw `startChannelInternal` 如果未传 accountId 就调用 `plugin.config.listAccountIds(cfg)`，如果传了 accountId 就只处理该账号；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258-274`。
- OpenClaw 启动前会跳过已 running/starting 的 account，避免重复启动；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:277-298`。
- OpenClaw `stopChannel` 会收集 known account ids，并支持传入 accountId 只停止一个账号；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:458-514`。
- OpenClaw health monitor 对单个账号执行 `stopChannel(channelId, accountId)` 和 `startChannel(channelId, accountId)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/channel-health-monitor.ts:158-167`。

Metis 当前源码依据：

- Metis `GatewayChannelManager` 当前保存 `adapters`、`adapterByName`、`liveAccounts`、`started`；源码：`src/gateway/core/gateway_channel_manager.cj:147-153`。
- `GatewayRegisteredAdapter` 已经保存 canonical `channelId/accountId`，说明 account 级 runtime key 有基础；源码：`src/gateway/core/gateway_channel_manager.cj:73-115`。
- 当前 `startChannels()` 只遍历所有 adapters 并在最后设置 `started=true`；源码：`src/gateway/core/gateway_channel_manager.cj:426-468`。
- 当前 `stopChannels()` 只能整体停止；源码：`src/gateway/core/gateway_channel_manager.cj:471-495`。

验收项：

- 单元测试：Gateway 已经 `startChannels()` 后，reconcile 新增 `telegram/tg-writer`，内部调用 Phase 4.5 的 `startChannel("telegram", accountId: "tg-writer")`，新 adapter `start()` 被调用一次。
- 单元测试：reconcile 发现 `telegram/tg-writer` 凭据签名变化，调用顺序为 `stopChannel("telegram","tg-writer")`、replace adapter、`startChannel("telegram","tg-writer")`。
- 单元测试：reconcile 删除或 disabled `telegram/tg-writer` 时，只停止 `tg-writer`，不停止 `telegram/default`。
- 单元测试：同一个 `channelId/accountId` 连续 reconcile 不产生重复 adapter start；对齐 OpenClaw started/starting 去重语义。
- 状态验收：reconcile 后停止的 account `running=false`、`lastError` 不包含敏感信息；重新启动后 `running=true` 且 `lastStartAt` 或等价 timing 状态更新。

#### Phase 5.5：热重载 handler 复用 profile enumeration 与 adapter factory

实施内容：

- 新增 Metis `GatewayHotReloadHandler` 或同等函数，输入 `GatewayReloadPlan` 与下一份 Gateway user settings/root。
- 对 `plan.restartChannels` 中每个 channel 执行：
  - 从下一份配置调用 Phase 2 的 account profile enumeration。
  - 从 profile 调用 Phase 3 的 adapter factory。
  - 调用 Phase 5.4 的 `reconcileChannel(channelId, profiles)`。
- 禁止在 handler 内手写 Telegram/Feishu/QQ adapter 构造细节；adapter 构造只能走 Phase 3 的统一 factory。这样才能避免启动时一套逻辑、热重载另一套逻辑。
- 如果 handler 某个 channel 失败，必须记录该 channel/account 的错误，但不阻止其他 channel 继续处理；最终结果中列出 failed channels。

OpenClaw 源码依据：

- OpenClaw reload handler 对 `plan.restartChannels` 执行 `stopChannel(name)` 再 `startChannel(name)`，没有为每个 provider 重写启动逻辑；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-reload-handlers.ts:118-135`。
- OpenClaw server 把 `startChannel`、`stopChannel` 注入 reload handler；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:1439-1460`。
- OpenClaw server reload 测试断言每个 restart channel 都调用 stop/start；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.reload.test.ts:471-542`。

Metis 当前源码依据：

- Metis adapter 注册发生在 `gateway_config_factory.cj` 中，当前 profile 和 adapter 构造已集中在那里；源码：`src/gateway/runtime/gateway_config_factory.cj:135-185`。
- Phase 2/3 将把该集中点改造为可复用的 profile enumeration 与 adapter factory；Phase 5 handler 必须调用这套能力。

验收项：

- 单元测试：plan 包含 `restartChannels={"telegram"}` 时，handler 只重新枚举 Telegram profiles，不碰 Feishu/QQ。
- 单元测试：plan 同时包含 Telegram/Feishu/QQ 时，三个 channel 都执行 reconcile；其中 Feishu reconcile 失败时，Telegram/QQ 仍完成，结果里 Feishu 标记 failed。
- 复用验收：测试或代码 review 必须能证明热重载 handler 没有直接 `new TelegramAdapter`、`new FeishuAdapter`、`new QQAdapter`；只能调用统一 adapter factory。
- 诊断验收：日志包含 `config hot reload applied` 或同等语义，并列出 changed paths 与 affected channels；不得包含凭证明文。

#### Phase 5.6：GatewayService 集成 reloader 生命周期

实施内容：

- 在 Gateway 启动完成 channel manager 与 adapter factory 初始化之后，创建并启动 Metis config reloader。
- `GatewayService.start()` 成功后 reloader 才开始监听；`GatewayService.stop()` 必须停止 reloader，再停止 channels，避免进程退出时后台线程继续读写配置。
- reloader 初始化时保存当前 root/config hash，防止启动后立刻把已加载配置当成“新变化”重复 reload。
- minimal/test gateway 场景可以注入 no-op reloader，避免单元测试被后台轮询线程干扰。

OpenClaw 源码依据：

- OpenClaw server 创建 ChannelManager 后解构 `startChannels/startChannel/stopChannel`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:722-731`、`880-881`。
- OpenClaw 在 `startGatewaySidecars` 阶段启动 channels；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:1413-1423`。
- OpenClaw 随后创建 `configReloader`，minimal test gateway 使用 no-op；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.impl.ts:1436-1438`。
- OpenClaw `startGatewayConfigReloader` 接收 `initialInternalWriteHash`，用于避免内部写入后的重复处理；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:77-100`。

Metis 当前源码依据：

- Metis `GatewayService.start()` 当前先 `channelManager.startChannels()`，再启动 OpenClaw compat host/plugin sidecar；源码：`src/gateway/core/gateway_service.cj:96-102`。
- Metis `GatewayService.registerAdapter` 当前是启动前注册入口；源码：`src/gateway/core/gateway_service.cj:49-80`。

验收项：

- 单元测试：GatewayService start 后 reloader status 为 running；GatewayService stop 后 reloader status 为 stopped。
- 单元测试：初始化 hash 与当前文件 hash 相同，不触发任何 channel reconcile。
- 单元测试：test gateway/no-op reloader 模式下，不启动后台轮询，不影响 `cjpm test` 稳定性。
- 运行验收：Gateway 日志有一条明确的 `config reload watcher started` 或同等语义，包含 mode 和 debounceMs，不包含 token。

#### Phase 5.7：`agents.add/update/bind/unbind` 写配置后的运行中闭环

实施内容：

- `agents.add` 写入 channel credentials 与 binding 后，通过 Phase 5.2 的 writeRoot 通知触发热重载，而不是在 `agents.add` 中手工启动 adapter。
- `agents.update` 如果只修改 agent model，则走既有模型 runtime refresh；如果同时修改 channel credentials，则触发对应 channel reload plan。
- `agents.bind/unbind` 修改 route binding 后，不应重启 IM channel；应刷新 route/binding runtime 视图或确认当前 route resolver 每次动态读取配置。
- RPC response 中可以包含 `runtimeReload` 摘要，但默认 CLI 输出必须是人类可读文本，不能直接打印大 JSON。

OpenClaw 源码依据：

- OpenClaw 内部写入通知会携带 runtime config，并由 reloader 统一调度，不要求每个业务命令各自调用 hot reload；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/config/io.ts:2397-2420`、`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:249-257`。
- OpenClaw reloader 通过 `running/pending` 串行化 reload，避免多个配置写入并发打乱顺序；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.ts:193-237`。

Metis 当前源码依据：

- `agents.add` 写入 agent、credentials、binding 后调用 `MetisConfigManager.writeRoot(root)`；源码：`src/gateway/runtime/gateway_server_methods_agents.cj:1622-1724`。
- `agents.update` 写入 root 后已有模型刷新逻辑；源码：`src/gateway/runtime/gateway_server_methods_agents.cj:1898-1918`。
- `agents.bind/unbind` 当前也通过 `MetisConfigManager.writeRoot` 写入；源码：`src/gateway/runtime/gateway_server_methods_agents.cj:1568-1574`、`1608-1613`。

验收项：

- 手工验收：Gateway 正在运行时执行 `metis agents add --agent tg-live --name "TG Live" --telegram-bot-token "fake:token"`，命令返回后无需重启，`metis gateway channel runtime telegram` 显示 `tg-live` 已进入 configured runtime 状态；fake token 场景可以是 start failed，但必须出现 account runtime 行和明确错误。
- 手工验收：Gateway 正在运行时执行 `metis agents add --agent feishu-live --name "Feishu Live" --feishu "cli_fake:secret_fake"`，`feishu-live` runtime 行出现；失败原因只能是凭据不可用，不能是 runtime 未注册。
- 单元测试：`agents.bind` 只改 binding 时，不调用 `reconcileChannel("telegram")`、`reconcileChannel("feishu")`、`reconcileChannel("qq")`。
- 单元测试：连续两次 `agents.add/update` 写入配置时，reloader 串行执行，第二次变化不会被吞掉；对齐 OpenClaw `pending` 机制。
- CLI 验收：默认输出包含类似 `Runtime reload: telegram restarted` 或 `Runtime reload: restart required` 的人类可读摘要；只有 `--json` 才输出完整 JSON。

#### Phase 5.8：热重载状态、诊断与用户可见命令

实施内容：

- 新增或扩展 Gateway status 输出，展示：
  - reload mode
  - debounceMs
  - watcher/poller 状态
  - lastReloadAt
  - lastChangedPaths
  - lastPlan
  - lastResult
  - lastError
- `metis gateway channel get <channel>` 与 `metis gateway channel runtime <channel>` 必须能区分：
  - 配置存在但 reload mode off。
  - 配置存在但该 path 需要 gateway restart。
  - 配置存在且 hot reload 成功。
  - 配置存在但 adapter start failed。
- 默认用户输出必须是可读文本，不能把 `toJsonString()` 原样丢给用户；`--json` 是显式机器可读模式。

OpenClaw 源码依据：

- OpenClaw hot reload handler 在成功后记录 `config hot reload applied (...)`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-reload-handlers.ts:142-145`。
- OpenClaw account snapshot 显示 `accountId/enabled/configured/running/lastStartAt/lastStopAt/lastError/probe`；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:298-311`。
- OpenClaw reload 测试断言 hot reload 会调用 channel stop/start，可作为 Metis 诊断测试的参考；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.reload.test.ts:531-542`。

Metis 当前源码依据：

- Metis `GatewayChannelManager.liveSnapshotJson()` 已基于 live accounts 生成 runtime snapshot，live account 字段包含 `configured/running/connected/lastInboundAt/lastError`；源码：`src/gateway/core/gateway_channel_manager.cj:181-225`。
- 本项目已有 CLI 输出整改要求：默认输出不得直接打印大 JSON；因此新增 reload/channel 诊断也必须走人类可读 formatter。

验收项：

- `metis gateway status` 或对应 status 子命令能显示 reload mode 与 last reload 摘要。
- `metis gateway channel runtime telegram` 对 `tg-live` 显示 `configured=true`、`running=false`、`lastError=<sanitized error>` 时，用户能判断是凭据问题还是 runtime 未启动问题。
- `gateway.reload.mode=off` 时，用户执行 `agents add --telegram-bot-token ...` 后命令输出必须明确提示“配置已保存，但 reload disabled，需要重启 Gateway 或开启 reload”。
- 敏感信息验收：输出和日志都不得包含完整 bot token、appSecret、apiKey、authorization header。

#### Phase 5.9：自动化验证、手工验收与回归保护

实施内容：

- 增加 reload plan、write notification、ChannelManager start/stop/reconcile、GatewayService reloader lifecycle、CLI 人类可读输出的自动化测试。
- 增加手工验收脚本或文档片段，明确 `METIS_HOME` 如何设置、Gateway 如何启动、如何执行 `agents add`、如何查看 runtime、如何判断成功或失败。
- 所有测试必须使用 fake adapter/fake token/fake appId，不访问真实 Telegram/Feishu/QQ 网络，不读写真实 `~/.metis`。
- 最终验证仍执行项目统一要求：
  - `source /Users/l3gi0n/cangjie100/envsetup.sh`
  - `export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"`
  - `cjpm clean`
  - `cjpm build -i`
  - `cjpm test`

OpenClaw 源码依据：

- OpenClaw `config-reload.test.ts` 覆盖 provider config prefix 生成 restartChannels；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.test.ts:163-177`。
- OpenClaw `config-reload.test.ts` 覆盖配置缺失重试与恢复；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.test.ts:418-443`。
- OpenClaw `config-reload.test.ts` 覆盖内部写入通知不重复读磁盘；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/config-reload.test.ts:550-562`。
- OpenClaw `server.reload.test.ts` 覆盖 hot reload handler 对多个 channels 调用 stop/start；源码：`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server.reload.test.ts:471-542`。

验收项：

- 自动化测试至少覆盖以下矩阵：
  - mode：`off`、`hot`、`restart`、`hybrid`
  - channel：`telegram`、`feishu`、`qq`
  - account：`default`、命名 account
  - 变更来源：进程内 `writeRoot`、外部文件改写
  - 结果：hot reload success、adapter start failed、restart required、reload disabled
- 手工验收文档必须给出完整命令，例如：
  - `export METIS_HOME=/tmp/metis-hot-reload-acceptance`
  - `cjpm run --skip-build --name metis --run-args "gateway run"`
  - `cjpm run --skip-build --name metis --run-args "agents add --agent tg-live --name TG --telegram-bot-token fake:token"`
  - `cjpm run --skip-build --name metis --run-args "gateway channel runtime telegram"`
- 回归验收：`cjpm clean && cjpm build -i && cjpm test` 全部通过。
- 质量验收：任一失败必须能定位到 snapshot、plan、handler、channel manager、adapter start、route binding、send path 中的具体阶段，不能只输出“Gateway failed”。

### Phase 6：补齐 agent 模型配置的用户友好入口

实施内容：

- 新增 `metis agents update --agent <id> --model <modelRef>`。
- 该命令只作为 CLI wrapper 调用现有 `agents.update` RPC，不直接写 `metis.json`。
- 输出使用人类可读格式，例如：
  - `Updated agent: feishu-writer`
  - `model: dashscope:qwen3.6-plus`
  - `modelsRefresh: ok`

依据：

- `agents.update` RPC 已支持 `model`：`src/gateway/runtime/gateway_server_methods_agents.cj:1800-1819`、`1835-1925`。
- CLI 当前 help 暴露 `--model` 解析，但没有 `update` 分支：`src/program/cli_local_flows.cj:2269-2299`、`2613-2662`。
- 既有原则：新增 CLI 功能必须复用现有 RPC，避免同一配置逻辑多实现。

验收项：

- `metis agents update --agent feishu-writer --model dashscope:qwen3.6-plus` 成功后，`agents.list` / `agents.models.get` 能看到该 agent 专属模型。
- `--json` 时输出 JSON；默认输出不能打印原始 `toJsonString()` 大对象。
- 单元测试断言 CLI 调用的是 `agents.update`，而不是直接写配置。
- 未指定 `--model` 且无其他更新字段时，输出清晰的 missing argument。

### Phase 7：路由、入站、出站按 account 闭环

实施内容：

- 入站事件必须带上纯 account id，route resolver 根据 `{channel, accountId}` 命中对应 agent。
- 出站回复必须使用同一 account 的 adapter 发送，不能回落到 default。
- Telegram/Feishu/QQ 三个 channel 都要覆盖 direct/group 场景的最小 fake event 测试。

依据：

- OpenClaw security check 以 `match.channel + match.accountId` 判定隔离：`openclaw-lark/src/core/security-check.ts:45-52`。
- OpenClaw Lark runtime context 中保存 `accountId`：`openclaw-lark/src/channel/monitor.ts:84-95`。
- Metis 当前用户 binding 已按 account id 写入。

验收项：

- 构造 Feishu fake inbound：`accountId=feishu-writer`，最终 agent id 为 `feishu-writer`。
- 构造 Telegram fake inbound：`accountId=tg-writer`，最终 agent id 为 `tg-writer`。
- 构造 QQ fake inbound：`accountId=qq-writer`，最终 agent id 为 `qq-writer`。
- 出站 adapter lookup 命中同一 account，不命中 default。

### Phase 8：诊断与用户输出补齐

实施内容：

- `metis gateway channel get <channel>` 展示账号数量、默认账号、每个账号的 configured/enabled/running/credentialSource。
- `metis gateway channel runtime <channel>` 明确区分“配置存在但 runtime 未启动”和“未配置”。
- 当存在 binding 指向某 account，但该 account runtime 未启动时，输出明确诊断。

依据：

- OpenClaw status snapshot 是 account 粒度：`openclaw-lark/src/channel/plugin.ts:276-311`。
- Metis 已有 Feishu/QQ account describe 函数：`src/gateway/channels/feishu/feishu_accounts.cj:131-187`、`src/gateway/channels/qq/qq_accounts.cj:142-218`。
- Metis 已有 CLI 人类可读输出整改规则，默认不能输出原始 JSON。

验收项：

- `metis gateway channel get feishu` 多账号输出中能直接看出哪个账号 running。
- 当 `feishu-writer` configured=true 但 running=false 时，输出包含“runtime not started for configured account feishu-writer”同等含义的诊断。
- 敏感字段一律 redacted，不展示 appSecret、botToken、authorization header。
- 默认输出非 JSON，`--json` 才输出 JSON。

### Phase 9：统一验证与手工验收

实施内容：

- 自动验证：
  - `source /Users/l3gi0n/cangjie100/envsetup.sh`
  - `export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"`
  - `cjpm clean`
  - `cjpm build -i`
  - `cjpm test`
- 手工验收：
  - 使用隔离 `METIS_HOME` 创建三个 agent + 三个 IM account。
  - 启动 Gateway。
  - 检查 runtime 三个账号都出现。
  - 对 Feishu 测试机器人发送消息，日志应出现 inbound、route agent、model request、send success 四段闭环。

依据：

- 项目构建测试规则要求每轮代码修改后统一 clean/build/test。
- Telegram/Feishu/QQ account runtime 本质是 Gateway 行为，必须通过 runtime status 与入站/出站闭环验收，不能只看配置文件。

验收项：

- `cjpm clean && cjpm build -i && cjpm test` 全部通过。
- 隔离环境不读取真实 `~/.metis`。
- 手工验收文档给出逐条命令、预期输出和失败解释。
- 任何失败都能定位到 config、runtime、route、model、send 的具体阶段。

## 7. 用户当前该如何理解模型配置

当前三个 agent 的 `model` 为 `null`，这不是错误，表示继承默认模型。如果希望每个 agent 使用不同模型，完整目标命令应该是：

```bash
metis agents update --agent feishu-writer --model dashscope:qwen3.6-plus
metis agents update --agent tg-writer --model dashscope:qwen3.6-plus
metis agents update --agent qq-writer --model dashscope:qwen3.6-plus
```

这条 `agents update` 需要按 Phase 6 补齐。补齐前，底层 RPC 已存在，但用户体验不完整。

## 8. 不接受的处理方向

本需求的目标是让已配置 account 成为 Gateway 一等 runtime，并完成配置、运行、路由、模型、发送的闭环。不接受以下处理方向：

- 让用户把所有 IM 凭据移到 default account。
- 让用户手工改绑定到 default。
- 只修文档，不修 runtime。
- 新增第二套 IM 配置写入逻辑，不使用已有 bind/account 配置结构。
- 只做 Feishu，不考虑 Telegram 和 QQ 的一致性。
