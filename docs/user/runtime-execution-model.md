# Runtime Execution Model

本文档说明当前 `Metis` 中，哪些入口默认走统一 Gateway 主运行时，哪些只在显式 `--local` 下走 embedded runtime。

## 1. 当前默认运行模型

当前产品对外的默认口径是：

1. `CLI chat / interactive / agent --message` 默认走 **统一 Gateway 主运行时**。
2. `QQ / Feishu / Control UI / Dashboard` 默认也走 **统一 Gateway 主运行时**。
3. `embedded runtime` 只在显式 `--local` 或后续明确 fallback 时进入。

当前默认入口优先收敛到 Gateway 长驻进程，而不是把主路径留给本地 embedded agent。

当前这条主轨的“统一核心工具基线”已经抽成共享 profile，用来同时约束：

- Gateway 默认主运行时
- embedded rich runtime

这样后续继续收敛时，不会再出现两边各自维护一套核心能力清单。

当前已经有正式可观测面可以检查这条主轨的覆盖情况：

- Gateway RPC:
  - `agents.runtime`
  - `agents.runtime.profile`
  - `agents.runtime.audit`
- Dashboard consumer:
  - `dashboard.agents.runtime`
  - `dashboard.agents.runtime.audit`
- Control UI / HTTP consumer:
  - `/api/agents/runtime`
  - `/api/agents/runtime/audit`
- Control UI / WS compat:
  - `agents.runtime.profile`
  - `agents.runtime.audit`
- Control UI:
  - `/api/agents/runtime`
  - `/api/agents/runtime/audit`
  - WebSocket `agents.runtime.profile`
  - WebSocket `agents.runtime.audit`

其中：

- `requiredCoreTools / missingCoreTools`
  用来观察统一 Gateway 主轨的核心工程能力基线
- `currentTools / effectiveTools`
  用来区分：
  - 哪些工具已统一注册到主轨
  - 哪些工具在当前 policy 下会真实进入执行期
  当前已经应能看到：
  - `process`
  - `gateway`
- `extendedSurfaceTools / missingExtendedSurfaceTools`
  用来观察更重的主轨收敛目标：
  - `process`
  - `gateway`
  - `cron`
  - `message`
  - `sessions_spawn`
  - `subagents`
- `ingresses`
  用来观察默认入口是否共享同一套 Gateway 主 agent。
  当前会列出：
  - `cli`
  - `qq`
  - `feishu`
  - `control-ui`
  - `dashboard`
  每个 ingress 还会带：
  - `tools`
  - `capabilities`
  - `capabilityScope`
  - `promptProfile`
  - `authorizationProfile`

  约束是：
  - `tools` 必须一致，表示共享同一套 Gateway 主 runtime
  - `capabilities` 可以不同，但只允许反映真实 delivery / reply / approval 差异
  - `promptProfile` 必须一致，只允许：
    - `channel-label`
    - `delivery-capabilities`
    这两类真实渠道差异
  - `authorizationProfile` 也必须一致，表示统一主轨下：
    - 工具是否注册，与是否授权执行是两件事
    - `enforcementStage = runtime-tool-filter`
    - 高风险操作依赖 `tools.allow/tools.deny`、channel policy、approval、sandbox
    - policy 拒绝时应返回清晰原因，而不是假装工具不存在

- `agents.runtime.audit`
  用来做统一 Gateway 主运行时的阶段性收口审计。当前会输出：
  - `summary`
  - `runtime`
  - `acceptance`
  - `remaining`
  - `remainingSummary`

  其中：
  - `summary.closure`
    用来说明这条主轨已经收住的关键约束
  - `summary.consumers`
    用来说明哪些 consumer 已共享同一份 audit surface
  - `acceptanceCount / remainingCount`
    用来快速看当前收口与剩余尾项规模

## 构建并发说明

当前仓库的 `cjpm build` 仍然不适合无保护地并行共享同一套 `target/`
和 `build-script-cache/`。

在未串行化时，已经观察到的症状包括：

- `Array contains empty value: []`
- `library not found for -lmetis.program`

这些问题更像是共享构建产物目录的竞争，而不是 `metis.program`
源码本身缺失。为此，回归脚本现在统一通过：

- `scripts/build_lock.sh`

来串行化 `cjpm clean` / `cjpm build`。

## 2. 当前 Metis 里实际存在的两条运行路径

### 2.1 Gateway 默认聊天路径

当前 Gateway 默认聊天 agent 是：

- `GatewayP1ChatAgent`

代码：

- `src/gateway/core/agent_bridge.cj`

这条路径当前已经是统一 Gateway 主运行时，而不再是早期的弱化聊天分支：

- 当前已经接入第一批统一核心工具：
  - `GatewayFSToolset`
  - `GatewayMemoryToolset`
  - `GatewayWeatherToolset`
  - `GatewayShellToolset`
  - `GatewayPlanToolset`
  - `GatewaySessionTranscriptToolset`
  - `GatewayGatewayToolset`
  - `GatewayCronToolset`
  - `GatewayMessageToolset`
  - `GatewayManagedSessionsToolset`

也就是说，Gateway 默认聊天路径现在已经不再是单纯的 **weather-only**，而是开始向统一主运行时收敛。

其中：

- `FS / Memory / Shell / Plan / transcript-session tools` 已经通过 Gateway-side wrappers 接入
- `gateway` 现在也已经通过 Gateway-side wrapper 接入默认主轨：
  - 直接开放读状态和发现面：
    - `status`
    - `health`
    - `discover`
    - `discover.detail`
    - `config.get`
    - `config.schema.lookup`
  - 更高风险的控制和 mutation action 现在按 `ownerApproved` / `explicitRequest` 门控
  - `start` / `stop` / `restart` / `master_on` / `master_off` 需要 owner approval
  - `config.patch` / `config.apply` / `update.run` 需要 owner approval 且需要 explicit user request
  - 当工具参数里没有显式传 `ownerApproved` / `explicitRequest` 时，默认主轨会从真实 runtime context 自动推断：
    - `cli`
    - `control-ui`
    - `dashboard`
    - `cron`
    这些入口会自动视作 owner-approved surface
  - `explicitRequest` 会按当前 turn 的 prompt 做保守推断，只覆盖高风险 `gateway` action
  - `config.patch` / `config.apply` 还会拒绝受保护路径，例如：
    - `gateway.controlUi.allowInsecureAuth`
    - `gateway.controlUi.dangerouslyDisableDeviceAuth`
    - `gateway.auth.mode`
    - `gateway.auth.allowTailscale`
  - `agents.runtime.profile` / `agents.runtime.audit` 的 `authorizationProfile.gatewayActionPolicy` 现在会直接暴露这套规则，以及：
    - `autoOwnerApprovedSources`
    - `ownerAuthorizationSignals`
    - `ownerInferenceMode`
    - `explicitRequestInference`
    - `contextIdentityFields`
  - `agents.runtime.audit.summary.closure` 现在也会显式确认：
    - `gatewayActionPolicyExposedAcrossConsumers`
    - `gatewayOwnerAndExplicitInferenceUsesRuntimeContext`
    - `gatewayActionPolicyUsesOperatorScopesAndDeclaredUser`
  - 这意味着 `gateway` 高风险 action 的 owner 推断已经不是只看入口名，而是显式可观测到：
    - `operatorScopes`
    - `declaredUser`
    - `senderId`
    - `sourceLabel`
  - `agents.runtime.audit.remaining` 现在也把后续工作范围压缩到：
    - approval-surface callbacks
    - 更强的 sender identity guarantees
- `process` 现在也已经进入默认主轨，用于后台 managed session/process 的 list/status/poll/logs/kill
- `cron` 也已经通过 Gateway-side wrapper 接入默认主轨
- `message` 现在也已经通过 Gateway-side wrapper 接入默认主轨
- `sessions_spawn / subagents` 现在也已经通过 Gateway-side managed-session toolset 接入默认主轨
- 剩下更厚的 Gateway control / ACP 生态仍可继续打磨，但默认主轨的扩展工具面已经补齐

这正是后续要收敛到统一 Gateway 主运行时的核心改造点。

### 2.2 Embedded rich runtime 路径

当前 embedded rich runtime 主要包括：

1. `GeneralCodeAgent`
2. `CangjieCodeAgent`

这些路径挂了：

- 文件工具
- shell
- memory
- plan
- subagent
- Cangjie/LSP 等 richer toolset

但它们当前不是默认用户主路径。

## 3. CLI 入口怎么分流

当前 CLI 的行为是：

1. `metis interactive`
2. `metis chat`
3. `metis agent --message "..."`

默认都走：

- `unified Gateway main runtime`

只有：

- `metis agent --local --message "..."`

才进入 embedded-only 调试路径。

这条边界已经在命令描述、示例和帮助文案中显式写出。

## 4. 为什么这份文档存在

当前仓库里之前的一个关键问题是：

- 产品默认入口几乎都走 Gateway
- 而 Gateway 默认聊天链过去长期是 weather-only
- embedded rich runtime 反而只在 `--local` 下才可见

这会导致：

1. 用户感知到的默认能力与项目里实际实现的能力脱节。
2. system prompt、tool registry、运行时能力来源更容易漂移。
3. 不同入口之间的行为很难保持一致。

## 5. 后续改造方向

后续统一目标是：

1. **Gateway 成为默认主运行时**
2. **CLI / QQ / Feishu / Control UI / Dashboard 共享同一套 Gateway agent runtime**
3. **embedded 仅保留为 `--local` 或显式 fallback**
4. **安全边界依赖 policy / approval / sandbox，而不是 weather-only 缩容**

也就是说，后续不是取消 embedded，而是取消“默认主路径弱化、embedded 才是强能力路径”的双轨结构。
