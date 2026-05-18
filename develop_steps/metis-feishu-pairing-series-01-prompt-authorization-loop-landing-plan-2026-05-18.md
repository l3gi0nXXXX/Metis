# Metis Feishu Pairing Prompt And Authorization Loop Landing Plan

日期：2026-05-18

## 1. 目标

补齐 Metis Feishu 私聊 `dmPolicy="pairing"` 下的提示与授权闭环。当前 Feishu 入站消息已经能进入 Gateway，并且账号解析、路由绑定、DM gate 都已生效；缺口是未授权用户触发 `pairing` 策略时，Metis 只把消息拒绝为 `dm_pairing_required`，没有生成 pairing code、没有向飞书会话回发可操作提示、也没有提供 Feishu 维度的 `metis pairing approve` 授权入口。

本方案只描述实施计划和验收项，不修改代码。

## 2. 源码事实依据

### 2.1 Metis 当前事实

1. Feishu 顶层配置默认 `dmPolicy="pairing"`，`allowFrom=[]`。
   证据：`src/core/config/gateway_user_settings.cj:470-471`。

2. Gateway 运行时 `FeishuConfig` 同样默认 `dmPolicy="pairing"`，`allowFrom=[]`。
   证据：`src/gateway/model/config.cj:997-998`。

3. Feishu account 配置会继承顶层 Feishu 配置；账号字段优先，账号未配置 `dmPolicy` / `allowFrom` 时从顶层 `config.dmPolicy` / `config.allowFrom` 读取。
   证据：`src/gateway/channels/feishu/feishu_accounts.cj:88-100`。

4. `metis agents add --feishu ...` 当前给新 Feishu account 写入 `dmPolicy="pairing"` 与空 `allowFrom`。
   证据：`src/gateway/runtime/gateway_server_methods_agents.cj:1535-1539`；测试期望见 `src/gateway/runtime/gateway_server_methods_agents_test.cj:871-872`。

5. Feishu adapter 当前 DM gate 逻辑为：`disabled` 拒绝，`open` 放行，`allowFrom` 命中放行，`allowlist` 未命中拒绝，其他情况拒绝为 `dm_pairing_required`。
   证据：`src/gateway/channels/feishu/feishu_adapter.cj:1738-1751`。

6. Gate 拒绝后 Gateway 只记录 `Gateway.route: accepted=false` 并返回，不会继续调用模型，也不会发送业务回复。
   证据：`src/gateway/core/router.cj:97-112` 读取 `feishuGate.triggerAgent`；`src/gateway/core/gateway_service.cj:234-238` 拒绝后直接 `return`。

7. 当前 Feishu gate 测试只断言 `dm_pairing_required`，没有断言 pairing code、pending store、提示消息或 approve 后放行。
   证据：`src/gateway/channels/feishu/feishu_adapter_test.cj:1601-1628`。

8. Metis Telegram 已有完整的本地 pairing store 与提示路径：未授权用户触发 `pairing` 时生成 pending code，发送提示 `metis pairing approve telegram <CODE>`，approve 后写入 approved sender。
   证据：`src/gateway/channels/telegram/telegram_adapter.cj:7904-7935`；`src/gateway/channels/telegram/telegram_pairing_store.cj:56-137`。

9. Metis CLI 的 `metis pairing approve` 当前只支持 `telegram`，不支持 `feishu`。
   证据：`src/program/cli_local_flows.cj:3431-3502`。

10. 当前 `gateway channel set feishu` 只支持 app、webhook、domain、thread 等字段，不支持 `dmPolicy` / `allowFrom`。
    证据：`src/gateway/runtime/gateway_settings_actions.cj:355-415`。

### 2.2 openclaw-lark 事实

1. openclaw-lark 的 Feishu/Lark account 也是“顶层配置 + account override”合并模型；账号字段优先，未设置字段回退顶层。
   证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/core/accounts.ts:1-10`、`:115-145`。

2. openclaw-lark 的 DM gate 同样默认 `dmPolicy ?? "pairing"`，并在 `pairing` 策略下合并配置 allowFrom 与 pairing store allowFrom。
   证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/gate.ts:431-465`。

3. openclaw-lark 在未配对时不只是拒绝消息；它会创建 pairing request 并调用 `sendPairingReply` 通知用户，然后返回 `pairing_pending`。
   证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/gate.ts:473-486`。

4. openclaw-lark 的 `sendPairingReply` 使用 channel-neutral pairing runtime：`upsertPairingRequest(channel="feishu", id=senderId, accountId=...)`，再构造 pairing reply，并用 Feishu 账号上下文发回原会话。
   证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/messaging/inbound/gate-effects.ts:26-54`。

5. openclaw-lark 明确把 Feishu pairing 的标识展示为 `feishuUserId`，并提供 approval 通知能力。
   证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/plugin.ts:89-102`。

6. openclaw-lark onboarding 也把 Feishu `dmPolicy` 的默认展示值设为 `pairing`。
   证据：`/Users/l3gi0n/work/workspace_cangjie/openclaw-lark/src/channel/onboarding.ts:178-185`。

## 3. 用户侧两种解决方式

### 3.1 方式 A：直接配置放行

适用场景：测试环境、单人自用 bot、已确认当前 Feishu bot 只面向可信用户。

当前 Metis 已支持 `dmPolicy="open"` 或 `allowFrom` 策略，但没有专门的 CLI 子命令设置 Feishu account 的 `dmPolicy` / `allowFrom`，因此现阶段操作方式是编辑 `~/.metis/metis.json` 后重启或重启指定账号。

操作：

1. 查看 Feishu account id：

```bash
metis gateway channel get feishu
```

2. 在 `~/.metis/metis.json` 中找到目标账号，例如 `gateway.feishu.accounts.feishu-writer`。

3. 测试环境允许所有私聊用户时，将该 account 设置为：

```json
"gateway": {
  "feishu": {
    "accounts": {
      "feishu-writer": {
        "dmPolicy": "open",
        "allowFrom": ["*"]
      }
    }
  }
}
```

4. 只允许指定用户时，将该 account 设置为：

```json
"gateway": {
  "feishu": {
    "accounts": {
      "feishu-writer": {
        "dmPolicy": "allowlist",
        "allowFrom": ["ou_xxx"]
      }
    }
  }
}
```

5. 重启指定 Feishu account：

```bash
metis gateway channel restart feishu --account feishu-writer
```

6. 再从该 Feishu 用户向 bot 发送测试消息。

验收标准：

1. 日志出现 `Gateway.inbound: channel=feishu, account=feishu-writer`。
2. 日志不再出现该消息对应的 `Gateway.route: accepted=false, reason=dm_pairing_required`。
3. 日志继续出现模型调用与 `Gateway.send` / Feishu send 成功记录。
4. 用户在 Feishu 私聊中收到业务回复。

风险：

1. `dmPolicy="open"` 会允许所有能私聊该 bot 的用户触发 agent。
2. `allowFrom=["*"]` 是明确放开私聊来源的信号，应只用于测试或可信边界内。
3. 生产环境优先使用方式 B。

### 3.2 方式 B：正式 pairing 授权闭环

适用场景：生产环境、多用户团队、多个 Feishu bot/account 映射到不同 agent 的场景。

这是本方案要补齐的正式能力。补齐完成后，用户操作应为：

1. 保持目标 account 的默认策略：

```json
"gateway": {
  "feishu": {
    "accounts": {
      "feishu-writer": {
        "dmPolicy": "pairing",
        "allowFrom": []
      }
    }
  }
}
```

2. 启动或重启目标 account：

```bash
metis gateway channel restart feishu --account feishu-writer
```

3. 未授权用户从 Feishu 私聊 bot，发送任意消息。

4. Metis 立即在同一个 Feishu 私聊中回复 pairing 提示，提示内容必须包含：

```text
Pairing required.
Approve this Feishu DM with:
metis pairing approve feishu <CODE> --account feishu-writer
```

5. 管理员在本机执行：

```bash
metis pairing approve feishu <CODE> --account feishu-writer
```

6. 用户重新向同一个 Feishu bot 发送消息。

7. 这次消息进入 Gateway 路由和 agent，不再被 `dm_pairing_required` 拦截。

验收标准：

1. 第一次未授权消息只触发 pairing 提示，不触发模型调用。
2. 同一 account、同一 sender 再次发送未授权消息时，仍能看到 pairing 提示；pending code 可复用或更新，但不能产生多个互相冲突的授权记录。
3. `metis pairing list feishu --account feishu-writer` 能列出 pending count 和 approved sender count 的人类可读摘要；`--json` 输出保留结构化明细。
4. `metis pairing approve feishu <CODE> --account feishu-writer` 成功后，approved sender 写入 account-scoped pairing store。
5. approve 后同一 sender 的消息进入 agent，并收到业务回复。
6. 另一个 account 的同名 sender 不会被误放行，证明 account 隔离有效。
7. Telegram 既有 `metis pairing approve telegram <CODE>` 行为不回退。

## 4. 目标架构

### 4.1 运行时流程

```text
Feishu user DM
  -> FeishuAdapter ingest
  -> resolve accountId by event app_id/header
  -> resolve account config from gateway.feishu + gateway.feishu.accounts.<accountId>
  -> DM gate
       dmPolicy=open      -> accept
       dmPolicy=allowlist -> config allowFrom or pairing store allowFrom hit -> accept
       dmPolicy=pairing   -> config allowFrom or pairing store allowFrom hit -> accept
       dmPolicy=pairing   -> no hit -> upsert pending code -> send Feishu pairing prompt -> reject as pairing_pending
  -> Gateway router
       accepted=true  -> model/session/send
       accepted=false -> no model call; prompt already sent by adapter
```

### 4.2 数据边界

1. Pairing state 必须按 `channel + accountId` 隔离。
2. Pairing state 不能写入 agent markdown 文件。
3. Pairing state 不能写入 route binding。
4. Pairing state 不应写真实环境配置文件；它属于本地 Gateway state，类似当前 Telegram pairing store。
5. 自动化测试必须使用临时 root，不得读写真实 `~/.metis`。
6. 日志与 CLI 默认输出不得暴露 appSecret、botToken、authorization header、真实 token。

## 5. 分阶段落地方案与验收项

### Phase 0：锁定源码事实和用户文档边界

实施内容：

1. 在本文件记录 Metis 与 openclaw-lark 的源码证据。
2. 在 `docs/user/agent-team.md` 增加 Feishu DM 访问策略说明，明确当前可用的配置放行方式和补齐后的 pairing 方式。
3. 文档必须说明当前 `gateway channel set feishu` 还不能设置 account 级 `dmPolicy` / `allowFrom`，避免写不存在的命令。

依据：

1. Metis `gateway channel set feishu` 支持字段见 `src/gateway/runtime/gateway_settings_actions.cj:355-415`。
2. Metis CLI pairing 当前只支持 Telegram，见 `src/program/cli_local_flows.cj:3477-3483`。

验收项：

1. `rg -n "metis pairing approve feishu|dmPolicy|allowFrom|gateway channel set feishu" docs/user/agent-team.md develop_steps/metis-feishu-pairing-series-01-prompt-authorization-loop-landing-plan-2026-05-18.md` 能找到说明。
2. 文档不得声称当前已支持 `metis pairing approve feishu`；必须标注为正式补齐后的操作。
3. 文档不得出现真实 appId、appSecret、bot token、sender open_id。

### Phase 1：抽象 channel/account scoped pairing store

实施内容：

1. 新增 channel-neutral pairing store，例如 `src/gateway/channels/common/gateway_pairing_store.cj` 或 `src/gateway/security/gateway_pairing_store.cj`。
2. Store API 至少包含：
   - `isApproved(senderId: String): Bool`
   - `ensurePending(senderId: String): String`
   - `pendingCodeForSender(senderId: String): String`
   - `approve(code: String): Bool`
   - `pendingRows(): Array<JsonObject>`
   - `approvedSenders(): Array<String>`
   - `rootPath(): Path`
3. Store 构造参数必须包含 `channel`、`accountId`、`rootDir`。
4. Telegram 可继续通过现有 wrapper 使用原路径，避免破坏既有状态；Feishu 使用新 store 或 channel-neutral wrapper。
5. Code TTL、长度、大小写归一可以复用 Telegram 的既有规则：1 小时 TTL、8 位 code、approve 后从 pending 移除并写 approved。

依据：

1. Metis Telegram store API 和数据行为见 `src/gateway/channels/telegram/telegram_pairing_store.cj:56-137`。
2. openclaw-lark 使用 channel/account pairing request，见 `openclaw-lark/src/messaging/inbound/gate-effects.ts:35-39`。

验收项：

1. 新增单测使用临时目录创建 Feishu store，调用 `ensurePending("ou_a")` 返回非空 code。
2. 同一 sender 再次 `ensurePending("ou_a")` 返回同一个未过期 code。
3. `approve(code)` 返回 true，之后 `isApproved("ou_a")` 为 true，`pendingRows()` 不再包含该 code。
4. `accountId="a"` approve 后，`accountId="b"` 的 `isApproved("ou_a")` 仍为 false。
5. 测试不得读写真实 `~/.metis`。

### Phase 2：扩展 `metis pairing` CLI 支持 Feishu

实施内容：

1. 保留现有 `metis pairing approve telegram <CODE>` 兼容行为。
2. 扩展语法：

```bash
metis pairing list feishu --account <accountId>
metis pairing status feishu --account <accountId>
metis pairing approve feishu <CODE> --account <accountId>
```

3. `--account` 对 Feishu 必须支持；缺省可回退 `gateway.feishu.defaultAccount`，但输出必须显示实际 accountId。
4. 默认输出必须是人类可读摘要，不允许直接打印 `toJsonString()` 原始 JSON。
5. `--json` 仍保留结构化输出，且不得包含 secret。

依据：

1. 现有 CLI pairing 入口见 `src/program/cli_local_flows.cj:3431-3502`。
2. 项目已多次要求 CLI 默认输出走 `gatewayPrintCommandOutput` / human output，不直接把 JSON 丢给用户。

验收项：

1. `metis pairing help` 显示 Telegram 与 Feishu 两个 approval target。
2. `metis pairing list feishu --account feishu-writer` 在无 pending 时输出类似 `Feishu pairing: account=feishu-writer pending=0 approved=0`。
3. `metis pairing approve feishu BADCODE --account feishu-writer` 输出清晰失败，不打印 raw JSON。
4. `metis pairing approve feishu <CODE> --account feishu-writer` 成功后输出 approved=true、account=feishu-writer、next step。
5. `metis pairing approve telegram <CODE>` 的原有测试继续通过。

### Phase 3：Feishu DM gate 接入 pairing store 和提示发送

实施内容：

1. 在 `FeishuAdapter` 中增加 account-scoped pairing store 依赖，默认 root 为 `CliConfig.dotDir`，测试可注入临时 root。
2. `dmPolicy="pairing"` 时先检查：
   - account config `allowFrom`
   - account-scoped pairing store approved senders
3. 未命中时调用 `ensurePending(senderId)`。
4. 发送 Feishu pairing 提示到当前 `chatId`，使用当前 accountId 的 Feishu send path。
5. Gate context 中写入：
   - `reason="pairing_pending"`
   - `pairingPromptSent=true|false`
   - `pairingAccountId`
   - `pairingSenderId`
   - 不写明文 secret
6. Router 仍然拒绝本轮消息，不触发模型调用；提示消息由 adapter 已经发出。

依据：

1. Metis Feishu send path 见 `src/gateway/channels/feishu/feishu_adapter.cj:471-499` 和 `:3513-3548`。
2. openclaw-lark 未配对时创建 request 并发送 reply，见 `openclaw-lark/src/messaging/inbound/gate.ts:473-486`、`gate-effects.ts:35-53`。
3. Gateway 当前拒绝后不发送业务回复，见 `src/gateway/core/gateway_service.cj:234-238`，所以提示必须在 adapter gate 中完成。

验收项：

1. Fake Feishu DM 第一次进入时，`pullInbound()` 得到的消息 gate 为 `triggerAgent=false`、`reason=pairing_pending`。
2. Fake `FeishuApiClient` 收到一条文本发送请求，目标 chatId 是原 DM chatId，accountId 是当前 account。
3. 提示文本包含 `metis pairing approve feishu <CODE> --account <accountId>`。
4. 提示文本不包含 appSecret、tenant token、authorization header。
5. approve 后同一 sender 再发消息，gate 为 `triggerAgent=true`。
6. 另一个 account 的同一 sender 仍需要 pairing。

### Phase 4：发送失败诊断与可观测性

实施内容：

1. 如果 pairing prompt 发送失败，不能静默；必须记录 `pairingPromptSent=false` 和 `pairingPromptError` 的脱敏摘要。
2. `Gateway.route` 日志保留拒绝原因，但需要能从 gate context 或 channel runtime 看到 prompt 是否发送成功。
3. `gateway channel get feishu` / `gateway channel runtime feishu` 增加 pending/approved 计数或 advice，帮助用户区分“未授权等待 approve”和“Feishu send adapter 失败”。

依据：

1. 当前用户遇到的问题是事件进来了但无回复；`Gateway.route accepted=false` 本身不足以解释用户侧现象。
2. Telegram pairing prompt 失败已有日志：`src/gateway/channels/telegram/telegram_adapter.cj:7933-7935`。

验收项：

1. Fake send failure 场景下，日志包含 `pairing prompt failed` 或等价脱敏错误，不包含 secret。
2. Gate context 包含 `pairingPromptSent=false`。
3. `metis gateway channel get feishu` 的 human output 能看到 pending/approved 计数或明确 advice。
4. 发送失败不触发模型调用。

### Phase 5：补齐 Feishu native command 中的 pairing 可见性

实施内容：

1. `/feishu start` 输出当前 account 的 DM policy、pending pairing count、approved sender count。
2. `/feishu doctor` 在 `dmPolicy=pairing` 且无 approved sender 时给出明确提示：首次用户消息会收到 pairing code，需要管理员执行 `metis pairing approve feishu <CODE> --account <accountId>`。
3. `/feishu info --all` 输出 accountId、dmPolicy、allowFrom count、pairing pending/approved count；不得输出 sender 明细，除非后续有明确安全设计。

依据：

1. Feishu native commands 入口见 `src/gateway/core/gateway_service.cj:492-545`。
2. 现有 `/feishu start` / `/feishu doctor` 已输出 readiness、account、route、auth 状态，见 `src/gateway/core/gateway_service.cj:549-590`。
3. openclaw-lark pairing plugin 有 approval notification 与 user id label，见 `openclaw-lark/src/channel/plugin.ts:89-102`。

验收项：

1. Fake Feishu `/feishu doctor` 输出包含 `dmPolicy: pairing` 和 `pairing pending=<n> approved=<n>`。
2. 输出不包含 appSecret、token、完整 pending code 列表。
3. 在 `dmPolicy=open` 时 doctor 明确显示开放风险提示。

### Phase 6：Control UI / Gateway RPC 状态展示

实施内容：

1. Gateway RPC 增加或扩展只读 pairing state 摘要：channel、accountId、pendingCount、approvedCount、policy。
2. Control UI 的 Feishu account 卡片展示 DM policy 与 pairing 状态。
3. Control UI 可以显示“需要在 CLI 执行 approve”的命令提示；是否支持 UI 直接 approve 另行受 operator scope 与安全设计约束。

依据：

1. Gateway 已有 operator scopes 包含 `pairing`，见 `src/gateway/runtime/gateway_control_ui_bootstrap.cj:88` 和 `src/gateway/runtime/gateway_control_ui_contract.cj:196`。
2. openclaw-lark 的 pairing 是 channel runtime 能力，不是 agent markdown 能力，见 `gate-effects.ts:35-53`。

验收项：

1. Gateway RPC 返回只读 pairing 摘要时不包含 secret。
2. Control UI build 通过。
3. 浏览器 smoke 打开页面无 JS error、无 asset 404、`customElements.get("metis-app")` 已注册。

### Phase 7：文档与手工验收矩阵

实施内容：

1. 更新 `docs/user/agent-team.md`，保留两种操作方式：
   - 直接配置放行：当前可用，适合测试。
   - pairing 授权闭环：正式推荐，补齐后可用。
2. 更新 agent team 手工测试矩阵，加入 Feishu pairing 测试项。
3. 文档必须明确当前不存在的命令与补齐后命令，避免误导用户。

依据：

1. 当前用户多次指出手工文档命令不准确，因此每条命令必须先由源码或实现计划支撑。
2. `docs/user/agent-team.md` 已是 AgentTeam 和 Feishu 用户侧入口文档。

验收项：

1. 文档中任一“当前可用”命令必须能在源码中找到或已由实现提交提供。
2. 文档中任一“补齐后可用”命令必须明确标注为目标能力，不能写成当前已支持。
3. 手工测试项包含操作步骤、验收标准、测试结果记录列。

### Phase 8：自动化测试和统一验证

实施内容：

1. 新增 pairing store 单测。
2. 新增 Feishu adapter pairing prompt 单测。
3. 新增 Feishu account 隔离单测。
4. 新增 CLI `metis pairing ... feishu` 单测。
5. 新增 human output 单测，确保默认输出不是 raw JSON。
6. 保留 Telegram pairing 既有测试。

验收项：

1. `cjpm clean` 成功。
2. `cjpm build -i` 成功。
3. `cjpm test` 成功。
4. 自动化测试不得使用真实 Feishu 网络、真实 appId/appSecret、真实 `~/.metis`。
5. 日志和测试断言不得包含真实 secret。

### Phase 9：Live opt-in 验收

实施内容：

1. 只在用户明确提供测试 Feishu bot/account 并确认可发测试消息时执行 live smoke。
2. Live smoke 使用测试 account，记录脱敏 evidence：
   - accountId
   - dmPolicy
   - sender open_id 的脱敏摘要
   - pending created
   - prompt sent
   - approve command result
   - approve 后业务回复成功
3. 不把 live smoke 写进默认 `cjpm test`。

验收项：

1. 未授权测试用户第一次私聊 bot，收到 pairing 提示。
2. 管理员执行 `metis pairing approve feishu <CODE> --account <accountId>`。
3. 同一用户再次发送消息，收到 agent 业务回复。
4. 另一个未授权用户仍收到 pairing 提示。
5. Evidence pack 不包含 appSecret、token、authorization header。

## 6. 不做的事情

1. 不把 Feishu pairing 状态写入 agent profile markdown。
2. 不让 route binding 兼任用户授权列表。
3. 不因为当前问题而把 Feishu 默认策略改成 `open`。
4. 不为 Feishu 单独绕过 Gateway router。
5. 不在自动化测试中访问真实 Feishu 网络或真实 `~/.metis`。

## 7. 实施顺序建议

1. 先完成 Phase 1、Phase 2、Phase 3，形成最小但完整的 pairing 闭环。
2. 再完成 Phase 4、Phase 5，让用户看得懂失败原因。
3. 最后完成 Phase 6、Phase 7、Phase 8、Phase 9，完成 UI、文档、测试、live evidence。

这不是降级实现；Phase 1-3 必须一次性打通“收到未授权消息 -> 回发 pairing code -> CLI approve -> 再发消息可进入 agent”的完整链路，否则不能标记为完成。
