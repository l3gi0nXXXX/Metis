# Metis Agent Team Runbook 中文版

Date: 2026-05-14

## 1. 适用范围

本文面向 Metis Agent Team 的日常启动、配置、团队创建、频道绑定、飞书 OAuth、OAPI 使用和常见故障诊断。所有浏览器 UI 操作都必须通过 Gateway RPC 完成；不要从浏览器直接写 token、secret、本地配置文件或 `~/.metis` 下的认证文件。

## 2. 启动与基础检查

1. 准备 Cangjie 环境：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
```

2. 构建项目：

```bash
cjpm build -i
```

3. 启动 Gateway 时使用本地配置中的 Gateway/Control UI 入口。Control UI 打开后确认页面能看到 Metis 内容，并且浏览器端 `customElements.get("metis-app")` 已注册。涉及 `ui/` 或 `assets/control-ui/` 的改动还需要执行 Control UI build 和浏览器 smoke。

## 3. 配置要求

Agent Team 的核心配置仍由 Gateway RPC 和 Metis 配置管理负责。UI 只提交结构化请求：

- 团队定义：`agents.teams.list/get/create/update/delete`。
- 成员绑定：`agents.bind` 和 `agents.unbind`。
- 每个 agent 的模型文件：`agents.models.get/set`。
- profile 文件：`agents.files.list/get/set`，每个 agent 支持独立的 `AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md`。`BOOTSTRAP.md` 支持显式创建，但不会自动创建。
- 飞书状态和 OAuth：`channels.status` 与 `channels.feishu.auth.start`。

本地 Feishu app id、app secret、token store 和模型凭据必须保持在 Gateway 后端配置或认证存储中。UI 展示层只能显示脱敏摘要。

## 4. 默认协作语义与使用路径

当前默认产品语义是确定性的 Gateway route，加可选的 deterministic fan-out。普通 CLI、Telegram 或 Feishu 入站请求会解析到一个 agent 和一个 agent-scoped session；只有团队配置中 `broadcast.enabled=true` 且 `broadcast.members` 非空时，Gateway 才会把同一个 turn 分发给选中的成员，并为每个成员保留独立 workspace、model、sessions 和状态汇总。

Manager delegation 可以与该模式并存，但目前不是独立产品化 runtime。需要 manager 风格时，把 manager 配成普通成员或 `defaultAgentId`，在 `AGENTS.md`、`SOUL.md` 等 profile 中写清任务拆解和交接规则，并把 CLI/IM route 绑定到该 manager。所有执行仍必须经过现有 Gateway route/session/session runner 边界；Metis 当前还没有自动 manager 任务拆解、跨 agent handoff policy 或绕开 Gateway 的 manager-delegation 引擎。

各入口路径：

- CLI：`metis agents team create/list/get/update/delete` 处理常规团队生命周期；`metis agents bind/unbind` 处理简单 `channel[:account]`；复杂 peer/thread/team/role binding 或 broadcast 用 `metis gateway call agents.teams.update ...`。
- Telegram：先配置内置 Telegram channel，再绑定 `telegram:<accountId>` 或结构化 group/topic route 到成员 agent。`/focus`、`/unfocus`、`/agents`、`/subagents` 等 native command 仍进入统一 Gateway 路由。
- Feishu：先配置 Feishu account/app，优先使用 `/feishu start`、`/feishu doctor`、`/feishu auth`、`/feishu info --all` 做会话内检查；绑定 `feishu:<accountId>` 或结构化 group/thread route 到成员 agent。OAuth/OAPI/card 必须走 Gateway 后端或 native command，不写浏览器本地文件。
- Control UI：进入 Agents -> Teams 创建团队、编辑成员和 alias、预览并应用 binding、编辑允许的 profile 文件、检查模型状态和 Feishu readiness/doctor。浏览器只作为 Gateway RPC client。

## 5. 创建和维护团队

1. 打开 Control UI 的 Agents -> Teams。
2. 新建团队时填写 Team key 和 Display name。
3. 可以使用内置模板创建 PM/Writer/Reviewer，也可以添加自定义 members。
4. 每个 member 至少需要 `agentId`；`role` 和 `name` 是可选展示字段。
5. 默认成员通过 Default member 选择；若选择了不存在的成员，Gateway payload 会回落到第一个有效成员。
6. aliases 用于把 `@writer` 或 `/agent writer` 这类文本映射到团队成员。
7. broadcast 只允许选择当前团队成员，避免把 fan-out 写到团队外 agent。

验收点：

- 创建、更新、删除都走 `agents.teams.*`。
- UI 不直接编辑本地 JSON 文件。
- 保存后重新加载团队详情，确认 members、aliases、defaultAgentId、broadcast 一致。

## 6. 频道绑定

Binding Builder 支持两种路径：

- Simple binding：例如 `feishu:tenant-a` 或 `telegram:bot-a`。
- Structured route binding：可填写 channel、account、peer、thread、group、team、roles 和 comment。

推荐流程：

1. 选择团队 member。
2. 填写 channel 和 accountId。
3. 群聊使用 peer/group；话题或线程使用 thread。
4. 如需团队或角色匹配，填写 team 和 roles。
5. 点击 Preview，确认 apply payload。
6. 点击 Apply Binding 或 Remove Binding。

验收点：

- Preview 是浏览器本地只读 payload 展示，不写配置。
- Apply/Remove 只通过 Gateway RPC。
- 不要绕过 Gateway route/session 体系创建独立 runtime。

## 7. Profile 文件

Control UI 通过 Gateway RPC 编辑 agent workspace profile 文件。每个 agent 的 profile 文件相互独立：

- `AGENTS.md`
- `SOUL.md`
- `TOOLS.md`
- `IDENTITY.md`
- `USER.md`
- `HEARTBEAT.md`
- `BOOTSTRAP.md`
- `MEMORY.md`

`BOOTSTRAP.md` 是显式 setup-state 文件，Metis 不会自动创建；需要时由 operator 通过 `agents.files.set` 或 Control UI 的 Gateway-backed 保存路径创建。

操作流程：

1. 选择团队 member。
2. 点击 List Files。
3. 选择 profile 文件并 Load。
4. 修改内容后 Save。

安全边界：

- UI 只提交文件名和内容给 `agents.files.*`。
- 路径边界由 Gateway 校验。
- UI 不允许输入任意路径，也不允许读取 workspace 外文件。

## 8. 模型配置

Model Editor 使用 `agents.models.get/set` 读写每个 agent 的 `models.json`。

操作流程：

1. 选择团队 member。
2. 点击 Load Model。
3. 检查 provider chips、primary model ref、runtime primary model ref 和 redacted credential source。
4. 修改 `models.json state` 后 Save Model。

注意：

- 不要在 UI 中粘贴 API key 或 Authorization header。
- 如果 Gateway 返回了意外 secret 字段，UI 展示前也会做二次 redaction。
- 真正的凭据来源应保留在后端 auth profiles 或环境配置中。

## 9. 飞书 OAuth 与 OAPI

飞书准备面板应显示：

- accounts 和 default account。
- OAuth/auth status。
- doctor 状态。
- OAPI capability。
- missing setup steps。

OAuth 启动流程：

1. 确认本地 Gateway 配置已有 Feishu app id/app secret。
2. 在 Teams 面板点击 Start OAuth via Gateway。
3. UI 调用 `channels.feishu.auth.start`，显示 verification URL、user code、expiresInSeconds 等 redacted 结果。
4. 用户在飞书授权页完成授权。
5. 再刷新 `channels.status` 或运行 `/feishu auth` 检查 token 状态。

OAPI 使用：

- Agent 工具应通过 Gateway Feishu OAPI toolset 调用，不要从 UI 直接请求飞书 API。
- 缺 token 时应返回 `auth_required`。
- 缺 scope 时应返回 `scope_missing` 或后续更细的 app/user scope 诊断。
- 输出和日志不得包含 access token、refresh token、app secret 或 Authorization header。

## 10. 常见故障诊断

### Teams 面板为空

- 刷新 Agents -> Teams。
- 检查 Gateway RPC `agents.teams.list` 是否返回。
- 若出现 scope 错误，确认 Control UI 连接使用的 operator 权限。

### Binding 没生效

- 先看 Preview payload 是否包含正确 agentId、channel、accountId、peer/thread。
- 确认 apply 后 Gateway 返回 added/skipped/conflicts。
- 对 Feishu 群聊，确认 accountId 与消息来源账号一致。

### 飞书无回复

- 先查日志是否有 `Gateway.inbound: channel=feishu` 或飞书 adapter 入站事件。
- 如果没有入站，优先检查 Feishu account、receive mode、app credentials、event subscription、proxy/network。
- 如果有入站但没有回复，再查 route binding、session runner、model 和 outbound send path。

### OAuth 无法启动

- `missing_app_credentials` 表示 app id/app secret 未配置或账号选择错误。
- `Auth status RPC missing` 表示当前 Gateway status contract 没有返回 auth 对象，可用 `/feishu auth` 辅助检查。
- 不要在浏览器本地创建 token 文件；只通过 Gateway RPC 或 native `/feishu auth`。

### OAPI 报 scope/token 错误

- `auth_required`：先完成 OAuth。
- `scope_missing`：在飞书应用后台补齐 user scope，并重新授权。
- app scope 与 user scope 需要区分；后续 action-specific OAPI 会提供更细诊断。

### Control UI 白屏或按钮无响应

- 运行 `npm --prefix ui run build`。
- 检查 built JS 中没有原始 TypeScript decorator 语法。
- 用浏览器确认 `customElements.get("metis-app")` 注册、页面有可见内容、无 JS/CSS asset 失败。

## 11. 验证命令

AgentTeam fake E2E/回归基线：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm test src/gateway/runtime --filter GatewayServerMethodsAgentsTest.agentTeamFakeImE2eCoversTelegramFeishuRoutesAndBroadcast
scripts/cli-agent-gateway-regression.sh
```

这些命令使用临时 `METIS_HOME` 或 fake route/broadcast payload，不使用真实 Telegram/Feishu 网络，不读取真实 `~/.metis`。

UI 改动至少运行：

```bash
npm --prefix ui run test -- src/ui/controllers/agent-teams.metis.test.ts src/ui/views/agents-panel-teams.metis.test.ts
npm --prefix ui run build
```

如果修改 Cangjie Gateway RPC，运行 targeted runtime 测试：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm test src/gateway/runtime --filter GatewayServerMethodsChannelsTest
```

父 agent 在主工作区合并后还需要统一执行全量 Cangjie 验证和 Control UI 浏览器 smoke。
