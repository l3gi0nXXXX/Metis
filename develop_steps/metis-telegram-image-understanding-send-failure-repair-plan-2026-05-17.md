# Metis Telegram 图片解析无回复与发送适配器不可用修复方案

日期：2026-05-17

## 1. 目标与约束

本方案只覆盖当前两个已定位问题：

1. Telegram 图片解析失败后，Gateway 试图回复用户时出现 `no adapter for channel='telegram' peer=... lastReason=adapter not found for accountId=default`，导致错误信息也无法发给用户。
2. 图片解析模型返回 `401 invalid_api_key` 等 provider 错误时，Metis 必须把错误稳定转成用户可见回复，不能静默，也不能把 provider 凭据错误误导成“模型不支持图片”。

约束：

- 修复必须保持 Metis 现有 gateway/channel/session 架构边界。
- Telegram 代理、轮询、发送等网络细节只允许留在 Telegram channel transport 或 Gateway channel 管理层，不进入 agent 主逻辑。
- 测试不得使用真实 Telegram 网络、真实 bot token、真实 provider API key、真实 `~/.metis` 文件。
- 日志和用户可见回复不得泄露 API key、Authorization header、bot token、代理密码。
- 每轮代码改动后必须执行 `cjpm clean && cjpm build -i && cjpm test`。

## 2. 源码依据

### 2.1 OpenClaw 对 accountId 的设计依据

OpenClaw 将 channel 与 accountId 作为两个独立维度处理：

- `openclaw/src/routing/account-id.ts`
  - `DEFAULT_ACCOUNT_ID = "default"`。
  - `normalizeAccountId(undefined/null/"")` 返回 `"default"`。
  - accountId 是规范化后的账号标识，不带 channel 前缀。
- `openclaw/src/channels/conversation-binding-context.ts`
  - `resolveBindingAccountId()` 从事件、插件默认账号配置中解析 accountId，最后回退到 `"default"`。
  - `ConversationBindingContext` 同时保存 channel 与 accountId，说明两者不是同一个字段。
- `openclaw/src/channels/plugins/configured-binding-match.ts`
  - binding 记录里的 `conversation.accountId` 会经 `normalizeAccountId()` 规范化。
  - 空 binding account 只匹配实际默认账号。
- `openclaw/src/infra/outbound/deliver.test.ts`
  - `deliverOutboundPayloads` 测试中，发送路径向 channel adapter 传入的是 `accountId: "default"`，不是 `telegram:default`。

结论：Metis 的修复应对齐 OpenClaw 语义，即 `channel=telegram` 与 `accountId=default` 分开表达；`telegram:default` 只能作为兼容旧配置/旧注册值的别名，不能成为内部路由比较的唯一标准。

### 2.2 OpenClaw 对 media understanding 的设计依据

OpenClaw 将媒体解析放在独立 runtime 中，按能力、模型和 provider 分层处理：

- `openclaw/src/media-understanding/runner.ts`
  - `buildProviderRegistry()` 建立 provider 注册表。
  - `providerSupportsCapability()` 判断 provider 是否支持 image/audio/video/file 等能力。
  - `resolveConfiguredKeyProviderOrder()` 与 `resolveAutoImageModelId()` 做配置模型与自动模型选择。
  - `runCapability()` 执行能力调用，并记录 provider/model 结果。
- `openclaw/src/media-understanding/apply.ts`
  - `applyMediaUnderstanding()` 返回 `outputs`、`decisions`、`appliedImage` 等结果，而不是让异常直接吞掉用户回复。
- `openclaw/src/media-understanding/echo-transcript.ts`
  - `sendTranscriptEcho()` 通过 `deliverOutboundPayloads()` 做 best-effort 回复。
  - delivery 失败被 catch 并记录日志，不让媒体解析主流程崩溃。
  - 传递的是 `ctx.AccountId`，channel 与 accountId 仍然分开。

结论：Metis 应保留独立 image understanding runtime，并把 provider 错误作为结构化结果返回到 Gateway/agent/tool 层；发送失败和 provider 失败必须分别记录，不能互相掩盖。

### 2.3 Metis 当前问题依据

当前 Metis 中存在 accountId 语义不一致：

- `src/gateway/config/gateway_adapter_registration_profiles.cj`
  - 内置 Telegram adapter 注册值使用 `accountId = "telegram:default"`。
- `src/gateway/channels/telegram/telegram_adapter.cj`
  - Telegram 入站媒体上下文通过 `effectiveAccountId()` 写入 `accountId=default`。
  - `normalizeTelegramAccountIdForState()` 会把空值和 `telegram:default` 归一到默认账号。
- `src/gateway/core/gateway_channel_manager.cj`
  - `sendToAdapterName()` 用字符串严格比较 `entry.accountId != requiredAccountId`。
  - 因此注册侧是 `telegram:default`、发送侧是 `default` 时无法匹配 adapter。
- `src/gateway/core/gateway_service.cj`
  - `sendTextToPeerDetailed()` 将 accountId 原样放入 `OutboundMessage`。
  - 发送失败后日志只体现最终 fallback 原因，容易把真实问题压缩成 `adapter not found for accountId=default`。

当前 Metis 中图片解析错误分类也存在不足：

- `src/core/gateway_media_understanding_runtime.cj`
  - `gatewayMediaConfiguredDescribeImagePathForRuntime()` 捕获 provider exception 后把单次 attempt 标记为 `provider_error`。
  - 但所有 candidate 都失败后，顶层状态会变成 `unsupported`，错误文案为 `no configured image understanding model could analyze this image`。
  - 这会把 `401 invalid_api_key` 这类 provider 配置/凭据错误误导成模型能力不支持。
- `src/gateway/core/gateway_session_turn_runner_test.cj`
  - 已有媒体 prompt 和视频错误状态测试，但缺少“图片 provider_error 必须产生用户可见回复”的回归测试。

## 3. 修复设计总览

### 3.1 问题一：Telegram send adapter 不可用

根因是 accountId 在不同层的规范不一致：

- 注册侧：`telegram:default`
- 入站和会话侧：`default`
- ChannelManager 匹配侧：直接字符串比较

修复方向：

1. 引入 Gateway channel routing 层的统一 accountId 规范化/等价匹配函数。
2. 内部 canonical accountId 对齐 OpenClaw：默认账号统一为 `default`。
3. 兼容旧配置和旧注册值：`telegram:default`、`feishu:default`、`qq:default` 等只作为 legacy alias。
4. `GatewayChannelManager` 在 adapter 注册、查找、发送 fallback 时都使用等价匹配，不再直接比较原始字符串。
5. `GatewayService.sendTextToPeerDetailed()` 保留现有架构，只增强诊断：直接 adapter 发送失败、accountId 匹配失败、adapter 未启动必须区分日志和返回原因。

### 3.2 问题二：图片解析 provider 错误没有稳定回复

根因是两个问题叠加：

- 图片解析 provider 返回 `401 invalid_api_key` 后，runtime 顶层状态被归并为 `unsupported`。
- 即使 Gateway/agent 生成了错误回复，Telegram 发送路径又因为 accountId 不匹配失败，导致用户看不到任何回复。

修复方向：

1. 图片解析 runtime 保留 provider 错误顶层语义：
   - 无候选模型：`not_configured`
   - 候选模型能力不支持：`unsupported`
   - provider 请求失败、401、403、5xx、网络错误：`provider_error`
   - 超时：`timeout`
   - 文件太大：`too_large`
2. `provider_error` 结果必须携带可诊断但脱敏的错误摘要。
3. Telegram image analyze 工具/媒体上下文必须把 `provider_error` 交给 agent 或 Gateway fallback 文案，不输出原始 JSON。
4. Gateway turn 层增加 channel-neutral 的兜底回复：当媒体解析失败且 agent 没有可发送文本时，Gateway 根据结构化错误生成用户可读失败回复。
5. 兜底回复仍走现有 `sendTextToPeerDetailed()`，不能绕过 Gateway/channel 架构。

## 4. 分阶段落地方案与验收项

### Phase 0：补齐 source-backed 测试清单

落地内容：

- 在现有测试清单中新增两个回归主题：
  - `accountId default 与 telegram:default 等价匹配`
  - `image provider_error 必须产生用户可见回复`
- 明确这些测试不能访问真实网络、真实 Telegram、真实 provider。
- 为后续修改先定义 mock adapter、mock image model、mock Gateway turn runner 的断言输入输出。

来源依据：

- OpenClaw `account-id.ts` 将默认账号定义为 `default`。
- OpenClaw `deliver.test.ts` 出站发送使用 `accountId: "default"`。
- Metis 当前 `gateway_adapter_registration_profiles.cj` 与 `telegram_adapter.cj` 存在注册值和入站值不一致。

验收项：

- 测试计划中至少覆盖：
  - 注册 `telegram:default`，发送 `default`，应匹配成功。
  - 注册 `default`，发送 `telegram:default`，应匹配成功。
  - 注册命名账号 `work`，发送 `default`，不得误匹配。
  - image model 抛出 `401 invalid_api_key`，顶层状态必须是 `provider_error`。
  - provider_error 场景必须触发一次 mock Telegram send。

### Phase 1：统一 Gateway accountId 规范化与等价匹配

落地内容：

- 在 Gateway channel/routing 边界新增统一 helper：
  - 输入：`channelId`、`rawAccountId`
  - 输出：canonical accountId
  - 规则：
    - 空值、空白、`default`、`${channelId}:default` 均归一为 `default`。
    - 非默认命名账号保留账号名，例如 `work`。
    - `${channelId}:work` 可作为 legacy alias 归一为 `work`。
    - 其他 channel 前缀的账号不得跨 channel 误匹配。
- `GatewayChannelManager.sendToAdapterName()` 改为使用 helper 判断 registered account 与 outbound account 是否等价。
- 保留原始 accountId 用于兼容日志，但日志同时输出 canonical accountId，方便排查。

来源依据：

- OpenClaw `normalizeAccountId()` 不把 channel 写入 accountId。
- OpenClaw `ConversationBindingContext` 分开保存 channel 和 accountId。
- Metis 当前发送失败正是由 raw string compare 导致。

验收项：

- 单元测试通过：
  - `telegram:default` vs `default` 等价。
  - `telegram:work` vs `work` 等价。
  - `telegram:work` vs `default` 不等价。
  - `feishu:default` 在 telegram channel 下不应作为 telegram default 偷偷匹配，除非明确按同 channel legacy alias 解析。
- 日志中不出现 token/API key。
- 不改动 agent、session manager、CLI、Control UI 中不相关路径。

### Phase 2：修复 Gateway send 诊断，避免真实原因被掩盖

落地内容：

- `GatewayService.sendTextToPeerDetailed()` 保持当前先直接 adapter、再 channel manager fallback 的流程。
- 增强错误聚合：
  - direct adapter 存在但发送失败：保留 direct send 错误。
  - fallback 找不到 adapter：保留 fallback 匹配错误。
  - 最终返回/日志中区分：
    - adapter 未注册
    - adapter 已注册但账号不匹配
    - adapter 已注册但未运行/发送失败
- `Gateway.sendTextToPeer` 日志中增加 channel、peer、rawAccountId、canonicalAccountId、adapterName，但不记录消息正文中的敏感信息。

来源依据：

- OpenClaw `sendTranscriptEcho()` 对 delivery failure 做 best-effort 记录，避免媒体主流程被掩盖。
- Metis 当前日志只体现 `adapter not found for accountId=default`，无法说明 adapter 是未注册还是账号别名不匹配。

验收项：

- mock adapter 发送异常时，错误信息包含 direct send failure 摘要。
- accountId 不匹配时，错误信息包含 raw/canonical accountId。
- adapter 不存在时，错误信息明确为 adapter not registered。
- 单元测试验证日志/错误消息不包含 token、Authorization、API key。

### Phase 3：修复图片解析错误状态分类

落地内容：

- 调整 `gatewayMediaConfiguredDescribeImagePathForRuntime()` 的最终状态聚合逻辑：
  - 如果至少一个 candidate 真正调用 provider 并返回 exception，最终状态优先为 `provider_error`。
  - 如果所有 candidate 都因为 capability 不支持而跳过，最终状态为 `unsupported`。
  - 如果没有任何 candidate，最终状态为 `not_configured`。
  - 如果 provider 超时，最终状态为 `timeout` 或在 `provider_error` 中明确 `timeout` 子原因，按现有枚举能力选择最小侵入方案。
- 保留 `attempts` 明细，但顶层 `status/error` 必须能让 agent 和用户理解真实原因。
- 增加错误脱敏函数，至少处理：
  - `Authorization`
  - `Bearer ...`
  - `api_key`
  - `DASHSCOPE_API_KEY`
  - URL query 中的 key/token

来源依据：

- OpenClaw `runner.ts` 明确 provider capability 与 provider execution 是两个阶段。
- Metis 当前 attempt 已有 `provider_error`，但顶层误归类为 `unsupported`。

验收项：

- mock image model 抛 `Http status: 401 ... invalid_api_key`：
  - 顶层 `status == "provider_error"`。
  - `attempts[0].status == "provider_error"`。
  - 用户可见错误摘要包含 `401` 和 `invalid_api_key` 或等价脱敏含义。
  - 不包含真实 key/token。
- mock candidate capability 不支持：
  - 顶层 `status == "unsupported"`。
- 没有 imageModel 配置：
  - 顶层 `status == "not_configured"`。

### Phase 4：让图片解析失败稳定形成用户可见回复

落地内容：

- 在 Telegram image analyze 工具结果和 Gateway media failure fallback 中，统一生成用户可读文案：
  - `not_configured`：提示图片解析模型未配置。
  - `unsupported`：提示当前选择的图片解析模型不支持图片输入。
  - `provider_error`：提示图片解析服务调用失败，并带脱敏错误摘要，例如 `401 invalid_api_key`。
  - `timeout`：提示图片解析服务超时。
  - `too_large`：提示图片过大。
- 该文案必须是普通文本，不允许把 `toJsonString()` 原样打印给用户。
- 如果 agent 已基于工具结果生成了可发送文本，则不重复发送兜底文案。
- 如果 agent 生成失败、空回复或工具失败导致 turn 中断，则 Gateway 使用兜底文案发给用户。

来源依据：

- OpenClaw `applyMediaUnderstanding()` 把 media understanding 结果结构化加入上下文，而不是直接静默。
- OpenClaw `sendTranscriptEcho()` 体现媒体处理失败/输出可以通过 channel delivery 回到用户。
- Metis 已经有 `gatewayFormatCommandOutput` 类整改规则，用户可见命令/错误不应裸露 JSON。

验收项：

- Telegram mock inbound 图片 + image model 401：
  - 最终 mock send adapter 收到一条文本回复。
  - 文案明确说明图片解析服务调用失败。
  - 文案包含脱敏的 401/invalid_api_key 诊断。
  - 文案不包含 JSON 大对象。
- mock agent 生成了正常错误回复时，不额外发送第二条 fallback。
- mock agent 无回复时，fallback 必须发送。

### Phase 5：跨 channel 保持一致，不写 Telegram 专用 agent 逻辑

落地内容：

- 把 provider error 到用户可见文案的转换放在 Gateway media/tool/session 边界，而不是写进 Telegram bot 特有代码。
- Telegram adapter 只负责：
  - 接收图片
  - 生成 media record/context
  - 发送 outbound text/media
- Feishu/QQ/CLI 后续复用同一套 media failure 结果和文案生成逻辑。

来源依据：

- OpenClaw media understanding 是独立 runtime，不绑定具体 IM channel。
- Metis 现有架构中 `gateway_media_understanding_runtime.cj` 已是 channel-neutral 的核心能力。

验收项：

- 新增/修改的核心错误分类测试不依赖 Telegram adapter。
- Telegram 只增加必要的 accountId 路由测试和 send path 测试。
- Feishu/QQ 编译不受影响。

### Phase 6：增加端到端回归测试

落地内容：

- 新增 Gateway turn runner 级测试：
  - 构造 Telegram 图片 inbound record。
  - 设置 imageModel candidate。
  - mock provider 返回 401。
  - mock send adapter 断言收到失败回复。
- 新增 ChannelManager 级测试：
  - adapter 注册账号为 `telegram:default`，outbound 账号为 `default`，发送成功。
  - adapter 注册账号为 `default`，outbound 账号为 `telegram:default`，发送成功。
  - 命名账号不误匹配。
- 新增 media runtime 级测试：
  - provider_error 顶层状态保持。
  - unsupported/not_configured 与 provider_error 分离。

来源依据：

- Metis 目前已有 `gateway_session_turn_runner_test.cj`、`telegram_adapter_test.cj`，应在现有测试风格内补齐，不另起测试框架。
- OpenClaw `deliver.test.ts` 以 mock send adapter 验证 outbound 行为，可参考其断言方式。

验收项：

- 所有新增测试不访问网络。
- 所有新增测试不读写真实配置。
- 所有新增测试稳定通过。
- 失败时能明确指出是 accountId、provider_error 分类还是 fallback send 文案问题。

### Phase 7：配置与诊断输出校验

落地内容：

- 检查 `gateway media image status --channel telegram` 的输出：
  - 保持用户友好格式。
  - 显示 public imageModel、channel override、最终候选模型、capability 判断。
  - 如果 provider key 配置存在但实际请求 401，只在运行时错误中提示凭据无效，不在 status 中泄露 key。
- 检查日志：
  - `Gateway.inbound` 能看到 Telegram 图片进入。
  - image provider failure 能看到脱敏错误摘要。
  - send failure 能看到 raw/canonical accountId。

来源依据：

- 用户已经明确要求 CLI/用户界面命令不能直接打印大 JSON。
- 当前问题排查依赖 `Gateway.inbound`、image status、send adapter 日志。

验收项：

- 命令输出不是 `toJsonString()` 原样结果。
- 日志中没有真实 key/token。
- invalid_api_key 场景日志足够定位 provider 配置问题。

### Phase 8：统一构建与测试验收

落地内容：

- 执行：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
cjpm clean
cjpm build -i
cjpm test
```

- 如果遇到 OpenSSL 动态库问题，再执行：

```bash
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
```

来源依据：

- 项目要求每轮代码修改后统一进行 `cjpm clean & cjpm build -i & cjpm test`。

验收项：

- `cjpm clean` 成功。
- `cjpm build -i` 成功。
- `cjpm test` 成功。
- 若失败，必须定位到具体模块并修复，不能以“部分完成”结束。

### Phase 9：人工验收清单

落地内容：

用户可按以下步骤手工验收：

1. 配置一个错误的 imageModel API key。
   - 操作：重启 Gateway 后，通过 Telegram 给 bot 发送一张图片。
   - 标准：Telegram 在合理时间内收到一条错误回复，说明图片解析服务调用失败，并包含脱敏的 `401 invalid_api_key` 或等价提示。
   - 标准：不出现长 JSON，不出现 token/API key。

2. 配置支持图片输入的有效 imageModel。
   - 操作：通过 Telegram 给 bot 发送一张图片并要求分析。
   - 标准：Telegram 收到基于图片内容的分析回复。
   - 标准：日志中 image understanding status 为 success 或等价成功状态。

3. 不配置 imageModel。
   - 操作：通过 Telegram 给 bot 发送一张图片。
   - 标准：Telegram 收到“图片解析模型未配置”类提示。

4. 使用不支持图片输入的文本模型作为 imageModel。
   - 操作：配置 DeepSeek 文本模型为 imageModel，发送图片。
   - 标准：Telegram 收到“模型不支持图片输入”类提示。
   - 标准：日志中状态是 `unsupported`，不是 `provider_error`。

5. Gateway 重启后再次发送图片。
   - 操作：重启 Gateway，确认 Telegram adapter 已启动后发送图片。
   - 标准：不再出现 `adapter not found for accountId=default`。
   - 标准：如果 provider key 错误，仍能收到错误回复。

6. 命名账号回归。
   - 操作：如配置了非默认 Telegram account，例如 `work`，发送对应账号消息。
   - 标准：`work` 账号只匹配 `work`，不误发到 default。

## 5. 实施顺序建议

建议按以下顺序一次性实施，不拆成多轮降级版本：

1. 先补 accountId 规范化与 ChannelManager 匹配测试。
2. 再修 Gateway send 诊断，确保错误回复有发送通道。
3. 再修 image understanding provider_error 顶层状态。
4. 再补媒体失败用户可见 fallback 文案。
5. 最后补端到端 mock 测试与人工验收。

原因：

- 如果只修 provider_error，不修 send adapter，用户仍然收不到错误回复。
- 如果只修 send adapter，不修 provider_error，用户会继续被误导为“模型不支持图片”。
- 两个问题必须一起闭环，才能解决“模型调用出错也必须回复用户”的真实需求。

## 6. 风险与边界

- 不应把 `telegram:default` 继续扩散到 agent/session 层；它只能作为兼容历史配置的输入别名。
- 不应在 Telegram adapter 中直接调用 image provider；图片解析仍属于 media understanding runtime。
- 不应把 provider 原始响应完整发送给用户；用户只需要可理解的错误摘要。
- 不应为了兜底回复绕过 GatewayService/channelManager；否则会破坏统一 channel 架构。
- 不应把真实 Telegram Bot API 或真实 DashScope/OpenAI provider 纳入自动测试。

## 7. 实施状态记录：work/tg-image-tests-docs-20260517

日期：2026-05-17

本记录只追加本 worker 覆盖的测试、诊断与文档落实，不删除或改写上方原方案。

### Phase 0 状态

- 已补齐本 worker 范围内的回归测试清单落点：
  - `GatewaySessionTurnRunnerTest.telegramImageProviderErrorFallbackSendsUserVisibleTextWhenAgentHasNoAnswer`
  - `GatewaySessionTurnRunnerTest.telegramImageNotConfiguredFallbackIsComputedFromMediaPrompt`
  - `GatewaySessionTurnRunnerTest.telegramImageFallbackDoesNotDuplicateWhenAgentAnswersNormally`
  - `GatewaySessionTurnRunnerTest.telegramImageProviderErrorFallbackSendsWhenAgentTurnThrows`
- 测试均使用 mock agent runner、mock deliver hook 和本地临时假图片文件；不访问真实 Telegram、真实 provider、真实 token 或真实 `~/.metis` 用户文件。
- accountId 等价匹配、provider status 顶层聚合由其他 worker 范围覆盖；本 worker 未修改 ChannelManager account matching，也未修改 media runtime provider status 聚合。

### Phase 4 状态

- 已在 Gateway session 执行层增加 channel-neutral media image failure fallback：
  - 当当前 turn 的 image/sticker media understanding 状态为 `provider_error`、`not_configured`、`unsupported`、`too_large` 或 `timeout`；
  - 且 agent 最终可见文本为空或 `<SILENT_REPLY>`；
  - 且当前工具上下文没有标记已发送用户可见回复；
  - 则通过原有 `deliverHook`/Gateway delivery target 发送普通文本 fallback。
- fallback 文案为普通文本，不输出 `toJsonString()` 或原始 JSON。
- `provider_error` 文案包含脱敏后的诊断摘要，例如 `401 invalid_api_key`；测试覆盖 `api_key=test-secret` 不出现在用户可见文本中。
- 如果 agent 正常生成最终文本，则只发送 agent 文本，不额外发送 fallback。

### Phase 5 状态

- fallback 位于 `src/gateway/core/gateway_session_executor.cj` 的 session 执行边界，依赖 `GatewayToolRuntimeContext.mediaContext` 中的结构化状态，不写 Telegram adapter 专用逻辑。
- `src/gateway/core/gateway_session_turn_runner.cj` 在构建 media prompt 时把本轮 media understanding 的 `status`、`capability`、`error` 写回同一个 turn 的 media record，供 session executor 兜底使用。
- Telegram adapter 仍只负责入站媒体、mediaContext 与 outbound delivery；本改动未进入 Telegram transport、ChannelManager、main agent 或 CLI 路径。

### Phase 6 状态

- 已新增 Gateway turn/session 级 mock 回归：
  - provider_error/401 场景：mock send adapter 收到一条用户可见文本，含 `401 invalid_api_key`，不含 `test-secret`，不含 JSON 大对象。
  - not_configured 场景：通过 `gatewayExecuteSessionRequestTurn` 先生成 media prompt 并写回 media understanding 状态，再在 agent `<SILENT_REPLY>` 时发送“图片解析模型未配置。”。
  - agent 正常回答场景：只发送 agent 文本一次，不重复 fallback。
  - agent turn 抛异常场景：仍通过原有 deliver hook 发送 provider_error fallback，deliveryStatus 为 `delivered-fallback`。
- 未新增真实网络测试；未使用真实 Telegram token、真实 provider key 或真实用户配置。

### Phase 7 状态

- 已检查 `gateway media image status` 路径：
  - `src/gateway/runtime/gateway_cli.cj` 的 status 命令调用 `gatewayPrintCommandOutput(result.toJsonString())`，没有直接 `PrintUtils.printLine(result.toJsonString())`。
  - `src/gateway/runtime/gateway_cli_human_output.cj` 的 `gatewayFormatCommandOutput` 优先调用 `cliRenderImageUnderstandingStatus` 渲染 human output。
  - 既有测试 `GatewayCliHumanOutputTest.formatsImageUnderstandingStatusWithoutRawJson` 验证 image status 输出包含 “Image understanding” 且不包含 `"candidates"` 或 `{`。
- 本 worker 未发现与本任务直接相关的裸 `toJsonString()` 用户输出问题，因此未改 CLI human output 代码。

### Phase 8 验证记录

- 已运行：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && rtk cjpm test --filter GatewaySessionTurnRunnerTest
```

- 结果：通过。
  - `GatewaySessionTurnRunnerTest`：33 passed，171 skipped，0 failed。
  - 整体命令结果：`cjpm test success`，但该过滤命令仍会链接/遍历多个 package 并跳过非匹配用例。
  - 运行期间出现既有 macOS linker warning：`ffi/libsignature_extractor.dylib` 和 `ffi/librawinput.dylib` 版本高于 target minimum 12.0.0。

- 早期一次同命令在新增测试断言过严时失败，原因是脱敏函数把 `invalid_api_key` 中的 `api_key` 改写为 `api key`；已修正为保留 provider 错误码原文、只脱敏实际凭据值，并重新运行通过。

- 已执行完整验收序列：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && rtk cjpm clean && rtk cjpm build -i && rtk cjpm test
```

- 结果：
  - `cjpm clean success`
  - `cjpm build success`
  - 第一次完整 `cjpm test` 失败于既有环境问题：`CryptoException: Can not load openssl library or function SHA1_Init`，触发用例为 `GatewaySpeechAsrRuntimeTest.tencentFlashProviderIsAvailableThroughUnifiedAsrRuntime`。
  - 按方案提示补充 OpenSSL 动态库路径后重跑：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && rtk cjpm test
```

  - 结果：`cjpm test success`，1469 passed，0 skipped，0 error，0 failed。
  - 运行期间仍出现既有 macOS linker warning：`ffi/libsignature_extractor.dylib` 和 `ffi/librawinput.dylib` 版本高于 target minimum 12.0.0。

## 8. 主工作区合并验收记录

日期：2026-05-17

本节记录三个 worker commit 合入 `main` 工作区后的统一验收结果。

### 8.1 默认全量门禁

已按项目要求执行：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm clean && cjpm build -i && cjpm test
```

结果：

- `cjpm clean success`
- `cjpm build success`
- 默认并发 `cjpm test` 复现项目既有 package-level runner 不稳定问题：
  - 第一次观测：`metis.core.config` 报 `failed to run package (exit code = 9)`，没有断言失败用例。
  - 第二次观测：`metis.program`、`metis.gateway.channels.feishu` 报 `failed to run package (exit code = 9)`，没有断言失败用例。
- 本轮新增/修改相关测试在默认并发测试中均通过，包括：
  - `GatewayMediaUnderstandingRuntimeTest`
  - `GatewayChatTurnSharedTest`
  - `GatewayServiceTelegramSendDiagnosticsTest`
  - `GatewaySessionTurnRunnerTest`

### 8.2 报错包定向复跑

已分别定向复跑默认并发中出现 package runner 异常的包：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm test src/core/config -i
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm test src/program -i
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm test src/gateway/channels/feishu -i
```

结果：

- `src/core/config`：59 passed，0 failed，0 error。
- `src/program`：10 passed，0 failed，0 error。
- `src/gateway/channels/feishu`：81 passed，0 failed，0 error。

结论：默认并发失败不是上述包内测试断言失败；与仓库历史记录一致，属于 `cjpm test` 默认并发 package runner 的启动级 `exit code = 9` 不稳定问题。

### 8.3 串行全量确认

已按仓库既有处理方式补跑低并发全量测试：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm test -j 1 --no-progress --no-color
```

结果：

- `cjpm test success`
- TOTAL: 1481
- PASSED: 1481
- SKIPPED: 0
- ERROR: 0
- FAILED: 0

结论：主工作区合入后的代码和测试在串行全量执行下闭环通过；默认并发 runner 风险已按既有项目规则记录，并补充了报错包定向复跑证据。
