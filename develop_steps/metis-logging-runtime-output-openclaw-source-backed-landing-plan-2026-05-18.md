# Metis 项目日志整改：OpenClaw 源码对标与落地方案

创建日期：2026-05-18

状态：方案已落盘，尚未修改 Metis 源码。

## 1. 目标与边界

### 1.1 目标

本整改把 Metis 的运行时输出统一拆成四类边界清晰的信息表面：

| 表面 | 面向对象 | 必须承载的信息 | 明确禁止 |
| --- | --- | --- | --- |
| Shell stdout | 正在运行 `metis gateway run`、`metis logs`、`metis gateway ...` 的用户 | 启动进度、就绪摘要、命令执行结果、可读的运行状态 | 直接打印大段 JSON、打印 token/secret、打印完整用户消息正文 |
| Shell stderr | 用户可见的错误/诊断 | 启动失败、配置错误、不可恢复错误、sidecar 诊断 | 正常协议帧、机器可解析 JSON stdout 被污染 |
| 文件日志 JSONL | 排障、审计、Control UI Logs、`metis logs` | Gateway 生命周期、IM adapter 启停、inbound/outbound 摘要、发送结果、模型调用摘要、错误堆栈、耗时、账号维度 | 未脱敏 secret、默认 info 级完整用户消息正文 |
| 协议 stdout | JS sidecar / plugin host / 兼容 host 的机器协议 | 一行一个 JSON frame | 人类提示、日志前缀、颜色控制字符 |

### 1.2 非目标

本文件只制定方案，不改代码。

本轮不改变 IM、Agent、模型调用的业务行为；只规范运行时输出、文件日志、日志查询与测试门禁。

本轮不要求真实 Telegram、Feishu、QQ 网络调用；验收测试必须使用 fake adapter、临时 `METIS_HOME`、假 token、假 app secret。

## 2. OpenClaw 输出体系的源码事实

### 2.1 两类日志表面：console 与 file

| 事实 | OpenClaw 依据 | 可迁移结论 |
| --- | --- | --- |
| OpenClaw 明确把日志拆成文件日志和 console 输出两个 surface。 | `openclaw/docs/logging.md:12-18`、`openclaw/docs/gateway/logging.md:13-17` | Metis 必须明确“用户看见的 shell 输出”和“文件日志”不是同一个东西，不能用同一批 `LogUtils.info("...")` 同时承担。 |
| 文件日志默认按日期滚动，默认位置是 `/tmp/openclaw/openclaw-YYYY-MM-DD.log`，可由 `logging.file` 配置。 | `openclaw/docs/logging.md:20-35`、`openclaw/src/logging/logger.ts:33-45`、`openclaw/src/logging/logger.ts:340-342` | Metis 当前按毫秒 timestamp 新建日志文件，后续需要稳定的“当前 gateway 日志文件”语义，避免 `logs.tail` 找错文件。 |
| console 有单独的 `logging.consoleLevel` 与 `logging.consoleStyle`。 | `openclaw/docs/gateway/logging.md:48-52`、`openclaw/src/logging/console.ts:40-90` | Metis 需要把 file level 和 console level 分开；比如 file 记录 info/debug，console 只显示 info/warn/error 摘要。 |
| `--verbose` 只影响 console / WS 输出细节，不改变文件日志 level。 | `openclaw/docs/gateway/logging.md:35-41` | Metis 的 `--verbose` 后续应只增加用户可见运行时细节，不应突然改变文件日志的审计完整性。 |

### 2.2 统一 logger、subsystem、console capture

| 事实 | OpenClaw 依据 | 可迁移结论 |
| --- | --- | --- |
| `logger.ts` 负责统一解析 logger settings、创建 JSONL 文件 logger、限制最大文件大小、允许测试 transport。 | `openclaw/src/logging/logger.ts:53-59`、`openclaw/src/logging/logger.ts:96-136`、`openclaw/src/logging/logger.ts:157-215`、`openclaw/src/logging/logger.ts:299-327` | Metis 需要一个 Gateway 专用 logger facade，而不是直接散落使用 CangjieMagic `LogUtils`。 |
| `console.ts` patch `console.log/info/warn/error/debug/trace`，继续输出到 stdout/stderr，同时写入文件日志。 | `openclaw/src/logging/console.ts:189-313` | Metis 的 JS sidecar/compat host 如果存在 console 输出，需要通过统一约束进入 stderr 或文件日志，协议 stdout 不应混入日志。 |
| `routeLogsToStderr` 用来保持 stdout 干净，避免 RPC/JSON 被普通日志污染。 | `openclaw/src/logging/console.ts:113-117` | Metis 的命令如果输出 JSON，必须保证其他日志不写 stdout；sidecar stdout 也只能写协议帧。 |
| subsystem logger 支持 `trace/debug/info/warn/error/fatal/raw/child`，并独立判断 console/file level。 | `openclaw/src/logging/subsystem.ts:18-38`、`openclaw/src/logging/subsystem.ts:302-319` | Metis Gateway 应提供 `gateway`, `gateway/channel/telegram`, `gateway/channel/feishu`, `gateway/model`, `gateway/http`, `gateway/control-ui` 等 subsystem。 |
| subsystem console 行有 pretty/compact/json 三种样式，带 prefix、level、timestamp、meta。 | `openclaw/src/logging/subsystem.ts:187-229` | Metis shell 输出要统一格式，不允许每个模块自行决定前缀、颜色和字段。 |
| subsystem logger 支持 `consoleMessage`：文件日志保留结构化 meta，console 可以显示更短的人类摘要。 | `openclaw/src/logging/subsystem.ts:320-630` | Metis inbound/outbound 可以在文件中记录结构化字段，在 console 只显示一行摘要。 |
| `raw()` 用于少数必须无前缀输出的交互内容，同时仍写文件日志。 | `openclaw/src/logging/subsystem.ts:632-647` | Metis 只有 QR、配对链接、一次性授权提示等可用 raw 输出，其他都走标准格式。 |

### 2.3 Gateway run 与 Gateway logs 的做法

| 事实 | OpenClaw 依据 | 可迁移结论 |
| --- | --- | --- |
| `openclaw gateway run` 有 `--verbose`、`--ws-log auto|compact|full`、`--compact` 等运行时输出选项。 | `openclaw/src/cli/gateway-cli/run.ts:239-252`、`openclaw/src/cli/gateway-cli/run.ts:558-600` | Metis `gateway run` 需要明确哪些输出由普通模式显示，哪些只有 verbose 显示。 |
| Gateway 启动阶段使用 subsystem logger 输出 `loading configuration`、`resolving authentication`、`starting...` 等阶段。 | `openclaw/src/cli/gateway-cli/run.ts:265-277`、`openclaw/src/cli/gateway-cli/run.ts:391-392`、`openclaw/src/cli/gateway-cli/run.ts:499-510` | Metis `gateway run` 需要统一启动阶段输出，而不是只打印 `[gateway] model` 和 `[gateway] log file`。 |
| Gateway ready 日志输出 agent model、ready、plugin count、duration、log file，并对危险配置做 warn。 | `openclaw/src/gateway/server-startup-log.ts:19-46` | Metis ready 摘要应至少包含：model、HTTP/Control UI 地址、日志文件、已配置/已运行 IM account、启动耗时、危险配置警告。 |
| `logs.tail` RPC 从当前配置的日志文件读取 cursor/limit/maxBytes，返回 file/cursor/size/lines/truncated/reset。 | `openclaw/src/gateway/server-methods/logs.ts:10-39`、`openclaw/src/logging/log-tail.ts:12-19`、`openclaw/src/logging/log-tail.ts:149-162` | Metis `logs.tail` 应基于真正的当前运行日志文件，支持 cursor 和大小限制，而不是读取一个新生成的 timestamp 文件。 |
| `openclaw logs` 支持 `--follow`、`--json`、`--plain`、`--no-color`、`--local-time`，JSON 模式输出 `meta/log/notice/raw` type。 | `openclaw/docs/cli/logs.md:11-27`、`openclaw/docs/logging.md:40-75`、`openclaw/src/cli/logs-cli.ts:243-360` | Metis `metis logs` 要成为用户排障入口，不应只返回“log output is truncated in local flow mode”。 |

### 2.4 IM adapter 与插件输出做法

| 事实 | OpenClaw / Feishu Claw 依据 | 可迁移结论 |
| --- | --- | --- |
| Gateway server 创建 `gateway/channels` 等子 logger，并把 channel logger/runtime env 传给 ChannelManager。 | `openclaw/src/gateway/server.impl.ts:170-203`、`openclaw/src/gateway/server-channels.ts:95-137` | Metis ChannelManager 启动 IM adapter 时要注入同一个日志上下文，不应让 adapter 自己直接 `LogUtils.info`。 |
| ChannelManager 在 `startAccount` 时按 account 维度记录 configured/enabled/running/failure，并捕获退出、重启失败。 | `openclaw/src/gateway/server-channels.ts:258-406`、`openclaw/src/gateway/channel-health-monitor.ts:77-205` | Metis 多账号场景必须把 channel、accountId、phase、failure count 放进日志事件。 |
| plugin runtime 暴露 `logging.getChildLogger`，插件能拿到结构化 logger。 | `openclaw/src/plugins/runtime/types-core.ts:104-110` | Metis 兼容 OpenClaw plugin / sidecar 时也应提供受控 logger，而不是让插件随意写 stdout。 |
| runtime helper 可把普通 RuntimeEnv 的 `log/error/writeStdout/writeJson` 适配到 logger。 | `openclaw/src/plugin-sdk/runtime-logger.ts:10-31` | Metis 需要类似 runtime logger adapter，给 sidecar/plugin/工具调用统一出口。 |
| Feishu Claw 的 lark logger 会从 runtime 获取 child logger，fallback 才写 console，并带 account/message/chat/sender 上下文。 | `openclaw-lark/src/core/lark-logger.ts:24-30`、`openclaw-lark/src/core/lark-logger.ts:60-66`、`openclaw-lark/src/core/lark-logger.ts:76-132` | Metis Feishu/Telegram/QQ adapter 的日志必须带 accountId 与消息上下文摘要，但不能默认打印完整正文。 |
| Feishu outbound 只记录 target、textLength、mediaCount、hasCard、路由分支，不记录完整发送内容。 | `openclaw-lark/src/messaging/outbound/outbound.ts:160-310`、`openclaw-lark/src/messaging/outbound/deliver.ts:242-253` | Metis outbound info 日志应记录 textLen/mediaCount/status，而不是完整 reply 文本。 |
| Feishu monitor 启动时记录账号数、WS 连接启动、bot open_id、dedup/dispatch 状态。 | `openclaw-lark/src/channel/monitor.ts:45-73`、`openclaw-lark/src/channel/monitor.ts:97-123`、`openclaw-lark/src/channel/monitor.ts:134-181` | Metis Gateway run 普通模式应该能看到每个 IM adapter 是否启动、哪个 account 启动、是否进入 polling/WS。 |

### 2.5 WebSocket / RPC 输出做法

| 事实 | OpenClaw 依据 | 可迁移结论 |
| --- | --- | --- |
| WS 日志支持 normal/compact/full；normal 只记录错误和慢响应，compact 记录请求/响应箭头和耗时。 | `openclaw/docs/logging.md:113-120`、`openclaw/src/gateway/ws-log.ts:319-440` | Metis Gateway RPC/Control UI WebSocket 不应默认刷屏；普通模式只显示失败/慢请求，verbose 才显示完整请求/响应摘要。 |
| WS 日志统一走 redaction 和 truncate。 | `openclaw/src/gateway/ws-log.ts:10-15`、`openclaw/src/gateway/ws-log.ts:103-157` | Metis 所有 RPC 参数、channel diagnostic、adapter error 都需要统一脱敏和截断。 |

## 3. Metis 当前状态的源码事实

### 3.1 当前已有基础

| 事实 | Metis / 依赖源码依据 | 结论 |
| --- | --- | --- |
| Metis CLI 已有 `PrintUtils`，根据交互模式选择 plain/colorful printer。 | `Metis/src/io/print_utils.cj:10-33`、`Metis/src/io/plain_printer.cj:23-30`、`Metis/src/io/colorful_printer.cj:33-44` | Shell 输出已有统一入口，但 Gateway runtime 没有完整使用它来表达运行时事件。 |
| 本地命令已有 `localPrintCommandResult`，默认输出 human，只有 `--json` 才打印 `toJsonString()`。 | `Metis/src/program/cli_local_flows.cj:48-65`、`Metis/src/program/cli_local_flows.cj:179-184` | 命令结果层已经有“默认人类可读、`--json` 才机器输出”的原则，日志整改应复用该原则。 |
| CangjieMagic `LogUtils` 支持 trace/debug/info/error，底层用 `Config.logFile` 写 stdout/stderr/file。 | `CangjieMagic/src/log/log_utils.cj:11-76`、`CangjieMagic/src/log/log_utils_impl.cj:61-76`、`CangjieMagic/src/log/log_utils_impl.cj:97-132` | 现有 `LogUtils` 是字符串 logger，不支持 structured meta、subsystem、console/file level 分离、统一脱敏。 |
| `parse_args` 会设置 `Config.logLevel`，并把 `Config.logFile` 指到 `CliConfig.logFile`。 | `Metis/src/parse_args.cj:121-131` | 目前文件日志来自全局 `Config.logFile`，但没有 Gateway 级 settings。 |
| `CliConfig.logsDir` 位于 `~/.metis/logs`；`CliConfig.logFile` 每次 getter 都生成当前毫秒 timestamp 文件名；`cleanupLogs` 有保留天数和最大文件数逻辑。 | `Metis/src/core/config/cli_config.cj:72-97`、`Metis/src/core/config/cli_config.cj:524-591` | 需要保留已有清理机制，但要修正“当前日志文件”不可稳定引用的问题。 |
| `gateway run` 前台只打印 model 和 log file，然后进入 `runGatewayService`。 | `Metis/src/gateway/runtime/gateway_cli.cj:385-390` | Shell 启动摘要不足，无法像 OpenClaw 一样直接看到 adapter 启动状态。 |
| `runGatewayService` 文件日志包含 Gateway.serve 阶段、HTTP/Control UI 启动、poll loop、heartbeat。 | `Metis/src/gateway/runtime/demo.cj:105-233` | Gateway 生命周期已有日志点，但输出形态是散落字符串，缺少结构化事件与 console 摘要标准。 |
| `logs.status/logs.get/logs.tail` RPC 已存在。 | `Metis/src/gateway/runtime/gateway_server_methods_ops.cj:489-557`、`Metis/src/gateway/runtime/gateway_server_methods_ops.cj:1795-1814` | 可以复用方法名，但需要修正读取目标、cursor/limit/maxBytes 和输出格式。 |
| Feishu sidecar 当前 stdout 写协议 JSON，stderr 写 `[feishu-monitor]` 诊断，并对协议值做 secret redaction。 | `Metis/scripts/feishu-ws-sidecar.mjs:35-76` | sidecar stdout/stderr 边界已经有局部实现，后续应抽成所有 sidecar 共用规则。 |

### 3.2 当前主要缺口

| 缺口 | Metis 依据 | 风险 |
| --- | --- | --- |
| Gateway/Channel 没有统一 structured logger，只能散落 `LogUtils.info/error` 拼字符串。 | `Metis/src/gateway/core/gateway_service.cj:201-230`、`Metis/src/gateway/core/gateway_channel_manager.cj:160-170`、`Metis/src/gateway/core/gateway_channel_manager.cj:613-659` | 后续无法稳定筛选 inbound/outbound、账号、耗时、错误类型；也无法让 Control UI 做结构化日志视图。 |
| `Gateway.inbound` info 日志直接打印 `text='${message.text}'`。 | `Metis/src/gateway/core/gateway_service.cj:222-230` | 默认 info 日志会泄露用户消息正文，不符合 OpenClaw “outbound 只打 textLength/target” 的做法。 |
| 发送日志记录 peer/rawAccount/canonicalAccount 和错误，但没有统一事件字段，也没有统一 redaction/truncate。 | `Metis/src/gateway/core/gateway_service.cj:3910-3985` | 不同 channel 的错误格式不可比较，敏感字段或长错误可能刷屏。 |
| ChannelManager 启动路径在 info 级记录多条 timing 步骤。 | `Metis/src/gateway/core/gateway_channel_manager.cj:613-659` | 普通 Gateway run 可能过于噪声；应改为 debug 细节 + info 摘要。 |
| `gatewayLogTailJson` 使用 `CliConfig.logFile` getter 读取当前文件，而该 getter 每次生成新 timestamp 文件名。 | `Metis/src/core/config/cli_config.cj:93-97`、`Metis/src/gateway/runtime/gateway_server_methods_ops.cj:526-557` | `logs.tail` 可能读取不到真正运行中的 `Config.logFile`，导致用户看不到日志。 |
| 本地 `metis logs tail/show` 当前只输出“log output is truncated in local flow mode”，没有真正读取日志。 | `Metis/src/program/cli_local_flows.cj:3025-3059` | 用户无法像 `openclaw logs --follow` 一样直接排障。 |
| `gateway channel`、`gateway call` 等 runtime 命令有 human formatter，但运行时日志没有同级 formatter。 | `Metis/src/gateway/runtime/gateway_cli_human_output.cj:1-320`、`Metis/src/gateway/runtime/gateway_cli.cj:395-441` | 命令输出和 runtime 输出风格不一致。 |

## 4. Metis 目标输出标准

### 4.1 日志级别语义

| Level | Shell 默认是否显示 | 文件日志是否记录 | 典型内容 |
| --- | --- | --- | --- |
| trace | 否 | 仅 level<=trace | 单步解析、循环内部细节、HTTP body 片段摘要 |
| debug | `--verbose` 才显示 | 仅 level<=debug | polling 细节、路由候选、fallback 决策、耗时拆分 |
| info | 是，但必须是摘要 | 是 | gateway ready、adapter started、inbound accepted summary、outbound delivered summary |
| warn | 是，stderr | 是 | 配置降级、权限未授权、重试、fallback、生效但有风险 |
| error | 是，stderr | 是 | 启动失败、发送失败、模型调用失败、sidecar 崩溃 |
| fatal | 是，stderr | 是 | 无法继续运行的错误 |

### 4.2 文件日志事件字段标准

所有 Gateway 文件日志后续统一为 JSONL，一行一个对象。字段必须稳定。本节字段按三类标注，避免把 OpenClaw 的实现细节和 Metis 必须适配的业务字段混为一谈：

| 分类 | 含义 | 本方案处理 |
| --- | --- | --- |
| OpenClaw 原样采用 | OpenClaw 文件日志已经稳定使用，Metis 没有必要改名 | `time`、`level`、`subsystem`、`event`、`message` |
| OpenClaw 原则对齐但 Metis 适配 | 结构化、可筛选、脱敏、摘要化原则对齐 OpenClaw，但字段来自 Metis Gateway/IM 运行时 | `channel`、`accountId`、`agentId`、`sessionKey`、`peerId`、`messageId`、`direction`、`status`、`durationMs`、`textLen`、`mediaCount`、`errorKind`、`error` |
| Metis 扩展 | Metis 为 Control UI、会话、渠道兼容性增加的字段；新增前必须写入事件字典和验收项 | 后续新增字段 |

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `time` | 是 | ISO 时间戳；对齐 OpenClaw 文件日志字段名，不使用 `ts` |
| `level` | 是 | `trace/debug/info/warn/error/fatal` |
| `subsystem` | 是 | 例如 `gateway`, `gateway/channel/telegram`, `gateway/model`, `gateway/control-ui` |
| `event` | 是 | 稳定事件名，例如 `message.inbound`, `message.outbound`, `channel.started` |
| `message` | 是 | 人类可读短摘要 |
| `channel` | 视事件 | `telegram/feishu/qq/...` |
| `accountId` | 视事件 | channel account |
| `agentId` | 视事件 | agent id |
| `sessionKey` | 视事件 | 会话 key，可截断或 hash |
| `peerId` | 视事件 | IM peer id，默认脱敏或 hash；debug 可显示 redacted 摘要 |
| `messageId` | 视事件 | IM message id |
| `direction` | 视事件 | `inbound/outbound` |
| `status` | 视事件 | `started/ok/failed/skipped/degraded` |
| `durationMs` | 视事件 | 耗时 |
| `textLen` | 视事件 | 正文长度，不是正文内容 |
| `mediaCount` | 视事件 | 媒体数量 |
| `errorKind` | 视事件 | 规范化错误类型 |
| `error` | 视事件 | 脱敏、截断后的错误摘要 |

禁止在 info 级默认写入完整 `message.text`、完整模型 prompt、完整模型 response、bot token、authorization header、app secret、proxy password。

### 4.3 Shell 输出标准

`metis gateway run` 普通模式只显示：

1. 正在读取配置。
2. 认证/控制面状态。
3. 当前主模型与图片/语音/PDF 等关键能力配置摘要。
4. 日志文件路径。
5. Control UI / HTTP 地址。
6. IM adapter account 启动摘要：`telegram/default running`、`feishu/feishu-writer waiting-authorization`、`qq/qq-writer running`。
7. ready 耗时。
8. warn/error 级别诊断。

`--verbose` 才显示：

1. 每个 adapter start 的详细阶段。
2. 每个 inbound/outbound 的摘要行。
3. Gateway RPC 慢请求和失败请求详情。
4. config reload、health monitor、backoff 重试详情。

`--json` 命令输出必须保持 stdout 只有机器 JSON；所有日志必须走 stderr 或文件。

## 5. 分阶段落地方案

### Phase 0：冻结证据与建立输出清单

#### Phase 0.1 建立 OpenClaw 对标清单

执行内容：

1. 在 `develop_steps` 中新增或更新本文件的证据表，列出 OpenClaw logging、gateway run、logs CLI、ChannelManager、Feishu outbound/inbound logger、WS log 的源码路径和行号。
2. 将 OpenClaw 的做法归类为：console/file 分离、subsystem logger、plugin runtime logger、logs CLI、redaction/truncate、sidecar stdout/stderr 边界。

依据：

1. `openclaw/docs/logging.md:12-18` 证明 OpenClaw 有 file log 与 console output 两个 surface。
2. `openclaw/src/logging/subsystem.ts:18-38` 证明 OpenClaw 有统一 subsystem logger API。
3. `openclaw/src/cli/logs-cli.ts:243-360` 证明 OpenClaw 有用户可用的 logs CLI。

验收项：

1. 审阅本文件第 2 章，确认每一类 OpenClaw 输出行为都有源码路径和行号。
2. 执行 `rg -n "createSubsystemLogger|logs.tail|consoleLevel|consoleStyle|redactSensitiveText" /Users/l3gi0n/work/workspace_cangjie/openclaw/src /Users/l3gi0n/work/workspace_cangjie/openclaw/docs`，确认第 2 章列出的关键符号仍能查到。

#### Phase 0.2 建立 Metis 当前输出清单

执行内容：

1. 列出 `src/gateway`、`src/program`、`src/io`、`scripts` 中所有直接输出点：`PrintUtils.printLine`、`println`、`print`、`eprintln`、`LogUtils.info/error/debug/trace`、`process.stdout.write`、`process.stderr.write`。
2. 将输出点分类为：命令输出、Gateway 生命周期日志、Channel adapter 日志、sidecar 协议帧、sidecar 诊断、Control UI log tail。
3. 对每个输出点标记：允许保留、需要迁移到 logger、需要迁移到 shell reporter、需要脱敏、需要降级到 debug。

依据：

1. `Metis/src/program/cli_local_flows.cj:179-184` 证明命令输出已经有默认 human / `--json` 机器输出分支。
2. `Metis/src/gateway/core/gateway_service.cj:222-230` 证明 inbound 当前直接把正文写入 info 日志。
3. `Metis/scripts/feishu-ws-sidecar.mjs:71-76` 证明 sidecar 已有 stdout JSON / stderr 诊断的局部边界。

验收项：

1. 执行：

   ```bash
   rg -n "LogUtils\\.(trace|debug|info|error)|PrintUtils\\.printLine|println\\(|print\\(|eprintln\\(|process\\.(stdout|stderr)\\.write" src scripts -g'*.cj' -g'*.mjs'
   ```

2. 输出点清单必须覆盖上述命令返回的每一类文件；如果暂不迁移，必须写明理由和所属 allowlist。

#### Phase 0.3 Metis 当前输出点审计清单（2026-05-18）

审计命令均在 `/Users/l3gi0n/work/workspace_cangjie/Metis/.worktrees/logging-docs-20260518` 执行，使用 `rg`，未调用 pager，未修改配置。

| 扫描面 | 命令 | 当前结论 |
| --- | --- | --- |
| Gateway `LogUtils` | `rg -c "LogUtils\\.(trace|debug|info|error)" src/gateway -g'*.cj'` | 25 个 Gateway 文件仍有直接 `LogUtils` 调用，需要 Phase 2-6 逐步迁移到 Gateway logger facade。 |
| Gateway/Program/IO 用户输出 | `rg -c "PrintUtils\\.printLine|println\\(|print\\(|eprintln\\(" src/gateway src/program src/io -g'*.cj'` | `PrintUtils.printLine` 是现有 CLI human 输出入口；Gateway adapter 中仍有 QQ/Feishu/Telegram 启动、诊断、命令输出混用，需要迁移到 shell reporter 或 logger。 |
| JS stdout/stderr | `rg -c "process\\.(stdout|stderr)\\.write|console\\.(log|error|warn|info|debug)" scripts -g'*.mjs'` | 9 个 JS 脚本有 stdout/stderr/console 输出；协议 sidecar 和兼容工具需要显式 allowlist，新增 sidecar 应改走 helper。 |
| 用户文档日志描述 | `rg -n "Gateway\\.inbound|Gateway\\.reply|Gateway\\.send|logs|log" docs/user README.md -g'*.md'` | `docs/user/gateway-im-plugins.md` 已有日志位置和 inbound/outbound 排查，但没有统一 `metis logs` 命令说明。 |

Gateway `LogUtils` 当前文件矩阵：

| 文件 | 命中数 | 分类 | Phase 处理 |
| --- | ---: | --- | --- |
| `src/gateway/core/gateway_service.cj` | 29 | Gateway 生命周期、route、inbound、reply、send | Phase 4 优先迁移；`Gateway.inbound` 正文输出必须改为 `textLen`/摘要。 |
| `src/gateway/channels/telegram/telegram_adapter.cj` | 20 | Telegram polling/webhook/命令/配对/发送诊断 | Phase 5 迁移到 channel/account logger，错误统一 redaction。 |
| `src/gateway/channels/qq/qq_adapter.cj` | 18 | QQ ingest/send/official ws/heartbeat | Phase 5 迁移；heartbeat ack 降到 debug。 |
| `src/gateway/runtime/demo.cj` | 16 | Gateway serve 生命周期 | Phase 3/4 迁移到 startup reporter + `gateway.*` 事件。 |
| `src/gateway/runtime/gateway_control_ui_ws.cj` | 16 | Control UI WS 连接/帧诊断 | Phase 7 迁移到 `gateway/rpc` 与 `gateway/control-ui`。 |
| `src/gateway/core/agent_bridge.cj` | 15 | 模型、技能、prompt、reply | Phase 4 迁移到 `gateway/model` 和 `message.reply.generated`，避免 prompt/response 泄露。 |
| `src/gateway/runtime/cron_runner.cj` | 12 | cron runtime | Phase 4 后补 `gateway/cron` 子系统。 |
| `src/gateway/core/gateway_channel_manager.cj` | 7 | channel start/stop/pull | Phase 5 优先迁移；普通模式只保留 account 摘要。 |
| `src/gateway/core/gateway_session_executor.cj` | 5 | streaming send fallback | Phase 4 迁移到 message outbound/send event。 |
| `src/gateway/config/gateway_channel_plugin.cj` | 5 | plugin discover | Phase 6 迁移到 plugin/channel logger。 |
| `src/gateway/runtime/gateway_config_reload_handler.cj` | 4 | config reload | Phase 4/7 迁移到 `gateway/config`。 |
| `src/gateway/core/gateway_session_store.cj` | 3 | session store error | Phase 4 后补 `gateway/session`。 |
| `src/gateway/runtime/gateway_config_reloader.cj` | 3 | config reload | Phase 4/7 迁移到 `gateway/config`。 |
| `src/gateway/runtime/gateway_platform_state.cj` | 3 | platform state | Phase 7 Control UI/RPC 迁移。 |
| `src/gateway/runtime/gateway_cli.cj` | 2 | CLI timing/bootstrap | Phase 3 迁移到 shell reporter。 |
| `src/gateway/runtime/gateway_config_factory.cj` | 2 | config factory timing | Phase 3/4 降级 debug 或 structured event。 |
| `src/gateway/runtime/gateway_external_console.cj` | 2 | external console launch | Phase 3 迁移到 shell reporter。 |
| `src/gateway/channels/plugin/command_plugin_adapter.cj` | 2 | plugin adapter pull/start failure | Phase 6 迁移到 plugin logger。 |
| `src/gateway/channels/plugin/legacy_node_plugin_adapter.cj` | 2 | legacy plugin adapter failure | Phase 6 迁移到 plugin logger。 |
| `src/gateway/startup_auth.cj` | 1 | startup auth | Phase 3 迁移到 startup reporter/logger。 |
| `src/gateway/runtime/gateway_chat_turn_runtime.cj` | 1 | chat turn runtime | Phase 4 迁移。 |
| `src/gateway/runtime/gateway_configured_channel_binding_registry.cj` | 1 | binding registry | Phase 5/7 迁移。 |
| `src/gateway/channels/feishu/feishu_adapter.cj` | 1 | Feishu adapter | Phase 5 迁移。 |
| `src/gateway/core/gateway_cron_session_reaper.cj` | 1 | cron session reaper | Phase 4 后补 `gateway/session`。 |
| `src/gateway/core/gateway_process_memory.cj` | 1 | process memory | Phase 4 后补 `gateway/runtime`。 |

JS stdout/stderr 当前 allowlist：

| 文件 | 当前用途 | 允许条件 | 后续任务 |
| --- | --- | --- | --- |
| `scripts/feishu-ws-sidecar.mjs` | stdout 写协议 JSON frame；stderr 写 `[feishu-monitor]` 诊断；console patched 到 stderr | 暂时允许；不得新增裸 stdout human 文本 | Phase 6 抽 `writeProtocol`/`writeDiagnostic` helper。 |
| `scripts/openclaw-compat-host.mjs` | 兼容 host 机器输出 | 暂时允许；stdout 只能是一行 JSON frame | Phase 6 迁移 helper。 |
| `scripts/openclaw-plugin-sidecar.mjs` | plugin sidecar RPC JSON 输出 | 暂时允许；stdout 只能是 JSON response | Phase 6 迁移 helper。 |
| `scripts/legacy-channel-host.mjs` | legacy host 透传子进程 stdout | 暂时允许；需要协议边界复核 | Phase 6 迁移或收窄。 |
| `scripts/openclaw-compat-*.mjs`、`scripts/openclaw-plugin-inventory.mjs` | CLI/测试报告 JSON 输出 | 仅作为显式命令输出允许 | 不属于 Gateway runtime sidecar；保留 CLI human/JSON 契约测试。 |

本审计清单落在 `develop_steps`，该目录被 `.gitignore` 忽略；本次提交需要用 `git add -f` 强制纳入。

### Phase 1：日志配置模型与当前日志文件语义

#### Phase 1.1 增加 Gateway logging 配置结构

执行内容：

1. 在 Metis 配置模型中增加 Gateway 专用 logging 配置，建议字段：
   - `gateway.logging.level`
   - `gateway.logging.file`
   - `gateway.logging.consoleLevel`
   - `gateway.logging.consoleStyle`
   - `gateway.logging.maxFileBytes`
   - `gateway.logging.redactSensitive`
   - `gateway.logging.redactPatterns`
2. 支持环境变量覆盖：
   - `METIS_LOG_LEVEL`
   - `METIS_LOG_FILE`
   - `METIS_CONSOLE_LEVEL`
   - `METIS_CONSOLE_STYLE`
3. 保留现有 `Config.logFile` 对 CangjieMagic 的兼容，但 Gateway 内部统一从新配置解析出 effective settings。

依据：

1. OpenClaw `LoggerSettings` 包含 `level/file/maxFileBytes/consoleLevel/consoleStyle`，见 `openclaw/src/logging/logger.ts:53-59`。
2. OpenClaw docs 明确 `logging.level/file/consoleLevel/consoleStyle/redactSensitive/redactPatterns`，见 `openclaw/docs/logging.md:130-152`。
3. Metis 当前只有 CangjieMagic `Config.logLevel/logFile`，见 `CangjieMagic/src/config/config.cj:59-98`。

验收项：

1. 新增测试使用临时配置 JSON，验证缺省值、用户配置、环境变量覆盖的优先级。
2. 测试非法 level/style 不会 crash，返回清晰错误或 fallback，并在 stderr/文件日志中有 warn。
3. 测试不读取、不写入真实 `~/.metis`，必须设置临时 `METIS_HOME=/tmp/metis-logging-config-test`。

#### Phase 1.2 修正“当前日志文件”稳定引用

执行内容：

1. 引入 `MetisResolvedLogSettings.currentFile` 或同等结构，在进程启动时解析一次当前 Gateway 日志文件。
2. `Config.logFile`、Gateway startup shell 输出、`logs.status`、`logs.tail`、Control UI Logs 都读取同一个 `currentFile`。
3. 保留 `CliConfig.cleanupLogs()`，但不能在 `logs.tail` 时重新调用会生成新文件名的 `CliConfig.logFile` getter。

依据：

1. Metis `CliConfig.logFile` getter 每次调用都会使用 `DateTime.now()` 生成新文件名，见 `Metis/src/core/config/cli_config.cj:93-97`。
2. Metis `gatewayLogTailJson` 当前用 `CliConfig.logFile` 判断存在并读取，见 `Metis/src/gateway/runtime/gateway_server_methods_ops.cj:535-557`。
3. OpenClaw `readConfiguredLogTail` 从 resolved logger settings 的文件读取，见 `openclaw/src/logging/log-tail.ts:149-162`。

验收项：

1. 在测试中固定 fake log file，调用 `logs.status` 和 `logs.tail`，两者返回的 file 必须一致。
2. 写入 fake log file 三行内容，`logs.tail` 必须返回这三行，不允许返回空数组。
3. 连续调用两次 `logs.tail`，不得生成两个不同 timestamp 的目标文件。

### Phase 2：核心 logger facade 与脱敏能力

#### Phase 2.1 新增 Metis Gateway logger facade

执行内容：

1. 新建 Gateway 日志模块，提供：
   - `MetisLogLevel`
   - `MetisLogEvent`
   - `MetisLogger`
   - `MetisSubsystemLogger`
   - `metisGetLogger()`
   - `metisCreateSubsystemLogger(subsystem: String)`
   - `logger.child(segment: String)`
2. API 至少支持：
   - `trace(event, message, meta)`
   - `debug(event, message, meta)`
   - `info(event, message, meta)`
   - `warn(event, message, meta)`
   - `error(event, message, meta)`
   - `fatal(event, message, meta)`
   - `raw(message, meta)`
3. 文件 sink 写 JSONL；console sink 输出 human compact 行；两者按各自 level 判断。

依据：

1. OpenClaw subsystem API 见 `openclaw/src/logging/subsystem.ts:18-38`。
2. OpenClaw 文件与 console 分开判断是否启用，见 `openclaw/src/logging/subsystem.ts:302-319`。
3. Metis 现有 `LogUtils` 只有字符串级别接口，见 `CangjieMagic/src/log/log_utils.cj:11-76`。

验收项：

1. fake file sink 测试：写入一条 info 事件，文件内容必须是一行合法 JSON，包含 `time/level/subsystem/event/message`。
2. fake console sink 测试：console level 为 warn 时，info 不显示，warn 显示。
3. child logger 测试：`gateway` 的 child `channel/telegram` 输出 subsystem 为 `gateway/channel/telegram`。

#### Phase 2.2 统一 redaction 与 truncate

执行内容：

1. 实现统一 redaction：
   - bot token
   - app secret
   - authorization header
   - bearer token
   - proxy password
   - api key
   - 用户配置中的 secret 值
2. 实现字段长度限制：
   - `message` 最大 500 字符
   - `error` 最大 1000 字符
   - `meta` 中字符串默认最大 1000 字符
3. 所有 logger 写文件、写 console 前都先 redaction/truncate。

依据：

1. OpenClaw WS log 统一 redaction/truncate，见 `openclaw/src/gateway/ws-log.ts:10-15`、`openclaw/src/gateway/ws-log.ts:103-157`。
2. OpenClaw plugin SDK 暴露 `redactSensitiveText`，见 `openclaw/src/plugin-sdk/logging-core.ts:1-3`。
3. Metis Feishu sidecar 当前局部替换 secret，见 `Metis/scripts/feishu-ws-sidecar.mjs:35-56`。

验收项：

1. 使用 fake token `123456:telegram_secret`、fake app secret `app_secret_xxx`、fake bearer token 写日志，文件和 console 中均只能出现 `[redacted]`。
2. 写入 2000 字符错误，文件日志中的 `error` 字段必须被截断并带截断标记。
3. `rg -n "telegram_secret|app_secret_xxx|Bearer secret" /tmp/metis-logging-redaction-test` 必须无结果。

### Phase 3：Shell 输出标准化

#### Phase 3.1 建立 Gateway shell reporter

执行内容：

1. 新增 Gateway shell reporter，所有 `gateway run` 前台输出统一走 reporter。
2. reporter 只负责用户可读 stdout/stderr，不负责文件日志。
3. reporter 支持普通模式和 verbose 模式。
4. 普通模式启动摘要至少包含：
   - config loaded
   - auth mode
   - model
   - log file
   - HTTP / Control UI URL
   - channel account runtime summary
   - ready duration

依据：

1. OpenClaw startup 使用 subsystem logger 分阶段输出，见 `openclaw/src/cli/gateway-cli/run.ts:265-277`、`openclaw/src/cli/gateway-cli/run.ts:391-392`、`openclaw/src/cli/gateway-cli/run.ts:499-510`。
2. OpenClaw ready 摘要包含 model、ready、log file，见 `openclaw/src/gateway/server-startup-log.ts:19-35`。
3. Metis 当前 `gateway run` 只打印 `[gateway] model` 和 `[gateway] log file`，见 `Metis/src/gateway/runtime/gateway_cli.cj:385-390`。

验收项：

1. 新增 formatter 单元测试，构造 fake startup snapshot，输出必须包含 `model`、`log file`、`Control UI`、每个 channel account 的 running/waiting/failed 状态。
2. 普通模式输出不得包含完整 JSON 对象。
3. 如果 `--json` 命令路径存在，stdout 必须只包含 JSON；启动日志不允许污染 stdout。

#### Phase 3.2 统一命令错误输出

执行内容：

1. Gateway runtime command 错误输出统一走现有 `printGatewayRpcFailure` 或新的同等 formatter。
2. 如果错误来自用户输入或配置校验，不再附带“Start gateway run”误导提示。
3. 错误文本必须先 redaction。

依据：

1. Metis 已有 `printGatewayRpcFailure`，且会根据错误类型判断是否提示启动 Gateway，见 `Metis/src/program/cli_local_flows.cj:194-216`。
2. OpenClaw logs CLI 在 Gateway 不可达时输出 human hint 或 JSON error，见 `openclaw/src/cli/logs-cli.ts:202-241`。

验收项：

1. 对 “already exists/not found/invalid” 类错误，CLI 只显示业务错误，不提示启动 Gateway。
2. 对 Gateway unreachable 错误，CLI 显示明确的启动提示。
3. 错误包含 fake secret 时，输出必须 redacted。

### Phase 4：Gateway 事件分类与主流程集成

#### Phase 4.1 定义 Gateway 事件字典

执行内容：

定义并使用以下稳定事件名：

| event | subsystem | 触发点 |
| --- | --- | --- |
| `gateway.starting` | `gateway` | `runGatewayService` 进入启动 |
| `gateway.ready` | `gateway` | HTTP、Control UI、channel 启动完成 |
| `gateway.shutdown` | `gateway` | finally/stop |
| `channel.registered` | `gateway/channel` | adapter 注册 |
| `channel.starting` | `gateway/channel/<name>` | account 启动前 |
| `channel.started` | `gateway/channel/<name>` | account 启动成功 |
| `channel.failed` | `gateway/channel/<name>` | start/pull/send 失败 |
| `channel.stopped` | `gateway/channel/<name>` | account 停止 |
| `message.inbound` | `gateway/message` | 收到 IM inbound |
| `message.routed` | `gateway/message` | route accepted/rejected |
| `message.reply.generated` | `gateway/message` | Agent 生成回复 |
| `message.outbound` | `gateway/message` | 准备发出 |
| `message.sent` | `gateway/message` | 发送成功 |
| `message.send_failed` | `gateway/message` | 发送失败 |
| `model.request` | `gateway/model` | 模型调用前 |
| `model.response` | `gateway/model` | 模型成功返回 |
| `model.failed` | `gateway/model` | 模型失败 |
| `rpc.slow` | `gateway/rpc` | RPC 慢请求 |
| `rpc.failed` | `gateway/rpc` | RPC 失败 |

依据：

1. OpenClaw docs 有 diagnostics event catalog，例如 `model.usage`、`webhook.received/processed/error`、`message.queued/processed`、`session.state`，见 `openclaw/docs/logging.md:176-217`。
2. Metis 当前已有 `Gateway.serve`、`Gateway.inbound`、`Gateway.reply`、`Gateway.send` 字符串事件，见 `Metis/docs/user/gateway-im-plugins.md:159-167`。

验收项：

1. 新增事件字典测试，所有 Gateway logger 调用必须使用字典中的 event 或测试 allowlist 中的 event。
2. 文档中列出的 event 名称必须与测试中的 event 名称一致。

#### Phase 4.2 替换 inbound / route / reply / send 关键路径

执行内容：

1. `handleInbound`：
   - info 级记录 `message.inbound`，包含 channel/accountId/chatType/senderHash/peerHash/textLen/mediaCount/messageId。
   - debug 级可记录 redacted/truncated text preview，但默认不显示。
2. `logInboundTurnOutcome`：
   - `message.routed` 记录 sessionKey、matchedBy、agentId、accepted/reason。
   - `message.reply.generated` 记录 answerChars、model、durationMs。
   - `message.sent` 或 `message.send_failed` 记录 deliveryStatus。
3. `sendTextToPeerDetailed`：
   - 发送前记录 `message.outbound`。
   - 成功记录 `message.sent`。
   - 失败记录 `message.send_failed`，统一 `errorKind/error`。

依据：

1. Metis 当前 inbound 直接写 text 正文，见 `Metis/src/gateway/core/gateway_service.cj:222-230`。
2. Metis 当前发送路径记录 peer/account/reason，见 `Metis/src/gateway/core/gateway_service.cj:3910-3985`。
3. OpenClaw Feishu outbound 记录 target 和 textLength，不记录正文，见 `openclaw-lark/src/messaging/outbound/outbound.ts:169-188`。

验收项：

1. fake inbound 文本为 `secret message body`，执行 fake gateway turn 后，info 级日志不得包含该完整正文。
2. 同一测试中日志必须包含 `message.inbound`、`message.routed`、`message.reply.generated`、`message.sent` 或 `message.send_failed`。
3. 发送失败测试必须产生 `errorKind`，并且用户侧仍能得到失败回复或可观测错误。

### Phase 5：IM adapter 输出与多账号运行态标准化

#### Phase 5.1 ChannelManager 注入 logger context

执行内容：

1. ChannelManager 注册 adapter 时，为每个 `channel/accountId` 构造 child logger。
2. Adapter start/pull/send 的所有日志都带 channel、accountId、phase。
3. `startChannels` 普通模式只记录每个 account 一条摘要；具体 timing 步骤降到 debug。

依据：

1. OpenClaw Gateway 创建 channel child logger 并传给 ChannelManager，见 `openclaw/src/gateway/server.impl.ts:170-203`、`openclaw/src/gateway/server-channels.ts:95-137`。
2. Metis ChannelManager 当前 info 级记录多条 timing，见 `Metis/src/gateway/core/gateway_channel_manager.cj:613-659`。

验收项：

1. fake 两个 telegram accounts 启动后，文件日志包含两条 `channel.started`，accountId 分别正确。
2. 普通 shell 输出只显示两条 account 摘要，不显示 `can-start-checked/marked-starting` 等内部 timing。
3. debug level 文件日志仍能看到 timing 细节。

#### Phase 5.2 Telegram/Feishu/QQ adapter 统一 inbound/outbound 摘要

执行内容：

1. Telegram：
   - polling start/stop/getUpdates failure/accepted count 统一事件。
   - `setMyCommands`、pairing prompt、send failure 统一 redaction。
2. Feishu：
   - WS sidecar start/account count/event received/send result/authorization required 统一事件。
   - pairing prompt 与授权闭环输出必须归入 warn/info 事件。
3. QQ：
   - official ws token acquired/hello/heartbeat ack/dispatch/send result 统一事件。
   - heartbeat ack 只能 debug，不能长期 info 刷屏。

依据：

1. Metis Telegram adapter 当前有 `getUpdates accepted`、`setMyCommands failed`、pairing prompt failed 等散落日志，见 `Metis/src/gateway/channels/telegram/telegram_adapter.cj:1990-2047`、`Metis/src/gateway/channels/telegram/telegram_adapter.cj:5232-5275`、`Metis/src/gateway/channels/telegram/telegram_adapter.cj:7944`。
2. Metis QQ adapter 当前 heartbeat ack 是 info，见 `Metis/src/gateway/channels/qq/qq_adapter.cj:933-968`。
3. OpenClaw Feishu monitor 记录 account/WS/bot 状态，见 `openclaw-lark/src/channel/monitor.ts:69-123`。

验收项：

1. fake Telegram polling 返回 2 条消息，日志包含 `channel.pull` inboundCount=2 和两条 `message.inbound`。
2. fake Feishu 未授权事件，shell 显示 pairing/authorization 提示，文件日志包含 `channel.authorization_required`。
3. fake QQ heartbeat 连续 3 次，普通 info 日志不出现 3 条 heartbeat ack；debug 日志可看到。

### Phase 6：JS sidecar / plugin host stdout-stderr 协议边界

#### Phase 6.1 抽取 JS sidecar logger helper

执行内容：

1. 新增 JS helper，例如 `scripts/lib/metis-sidecar-logger.mjs`：
   - `writeProtocol(frame)`：只写 stdout，一行 JSON。
   - `writeDiagnostic(level, message, meta)`：只写 stderr，带 sidecar 前缀。
   - `redactKnownSecrets(value)`：递归 redaction。
2. `feishu-ws-sidecar.mjs`、`openclaw-compat-host.mjs`、`openclaw-plugin-sidecar.mjs` 统一使用 helper。
3. 禁止 `console.log` 写协议 stdout；若必须 console，patch 到 stderr 或 helper。

依据：

1. Metis Feishu sidecar 当前已有 `writeProtocol` 写 stdout 与 `writeStderr` 写 stderr，见 `Metis/scripts/feishu-ws-sidecar.mjs:71-76`。
2. OpenClaw `routeLogsToStderr` 用于保持 stdout 干净，见 `openclaw/src/logging/console.ts:113-117`。
3. OpenClaw console capture 统一处理 console 输出，见 `openclaw/src/logging/console.ts:189-313`。

验收项：

1. 运行 sidecar 单元测试，stdout 每一行都能 `JSON.parse`。
2. stderr 出现 human diagnostic 时，不影响 stdout JSON parse。
3. fake secret 在 stdout/stderr 都被 redacted。

#### Phase 6.2 plugin runtime logger 适配

执行内容：

1. 为 Metis OpenClaw plugin compatibility runtime 增加 `logging.getChildLogger` 或等价适配。
2. plugin 的 `runtime.log/error/writeStdout/writeJson` 统一进入 Metis logger，不直接污染 stdout。
3. 保留协议输出通道只写 JSON frame。

依据：

1. OpenClaw plugin runtime 暴露 `logging.getChildLogger`，见 `openclaw/src/plugins/runtime/types-core.ts:104-110`。
2. OpenClaw runtime helper 把 `writeStdout/writeJson` 适配到 logger，见 `openclaw/src/plugin-sdk/runtime-logger.ts:10-31`。

验收项：

1. fake plugin 调用 `runtime.logging.getChildLogger({subsystem:"test"})`，文件日志 subsystem 必须包含 plugin/test。
2. fake plugin 调用 `writeJson({hello:"world"})`，shell stdout 不出现该 JSON，文件日志可看到 redacted JSON 摘要。

### Phase 7：`metis logs`、Gateway RPC 与 Control UI Logs

#### Phase 7.1 完善 logs RPC

执行内容：

1. `logs.status` 返回：
   - `logsDir`
   - `currentLogFile`
   - `currentLogFileExists`
   - `recentFiles`
   - `level`
   - `consoleLevel`
2. `logs.tail` 支持参数：
   - `cursor`
   - `limit`
   - `maxBytes`
   - `file`
3. 返回：
   - `file`
   - `cursor`
   - `size`
   - `lines`
   - `truncated`
   - `reset`

依据：

1. OpenClaw logs.tail 参数和返回结构见 `openclaw/src/gateway/server-methods/logs.ts:10-39`、`openclaw/src/logging/log-tail.ts:12-19`。
2. Metis 当前 `logs.tail` 固定 80 行且没有 cursor/maxBytes，见 `Metis/src/gateway/runtime/gateway_server_methods_ops.cj:1810-1814`。

验收项：

1. fake log 100 行，`logs.tail limit=10` 返回 10 行。
2. 使用 cursor 续读时，只返回新增行。
3. 文件被轮转或截断后，返回 `reset=true`。

#### Phase 7.2 完善 `metis logs` CLI

执行内容：

1. `metis logs path`：输出日志目录。
2. `metis logs recent`：列出最近日志文件、大小、mtime。
3. `metis logs current`：显示当前 Gateway 日志文件。
4. `metis logs tail [file] --limit N --follow --interval MS`：持续 tail。
5. `metis logs show [file] --limit N`：一次性显示。
6. `--json` 输出 type-tagged JSON lines；默认 human。
7. `--plain`、`--no-color`、`--local-time` 支持终端和脚本场景。

依据：

1. OpenClaw CLI logs 选项见 `openclaw/docs/cli/logs.md:11-27`。
2. OpenClaw JSON mode 输出 `meta/log/notice/raw`，见 `openclaw/docs/logging.md:66-75`。
3. Metis 当前 logs local flow 是占位输出，见 `Metis/src/program/cli_local_flows.cj:3025-3059`。

验收项：

1. 设置 `METIS_HOME=/tmp/metis-logs-cli-test`，写入 fake log，执行 `cjpm run --skip-build --name metis --run-args "logs tail gateway.log --limit 2"`，输出必须是两条 human 日志行。
2. 执行 `cjpm run --skip-build --name metis --run-args "logs tail gateway.log --limit 2 --json"`，stdout 每一行都是 JSON，且有 `type` 字段。
3. 执行 `metis logs follow` 类测试时，测试必须使用短 interval 和可控输入，不阻塞 CI。

#### Phase 7.3 Control UI Logs 统一读取同一日志源

执行内容：

1. Control UI Logs 面板通过 `logs.tail` RPC 读取当前日志。
2. 支持 cursor 增量刷新。
3. UI 不解析时也能显示 raw line；解析成功时展示 level/subsystem/event/message。

依据：

1. OpenClaw docs 说明 Control UI Logs tab tail 文件日志，见 `openclaw/docs/logging.md:12-18`。
2. Metis Control UI 已有 logs tail 数据消费，见 `Metis/src/gateway/runtime/gateway_control_ui_v3_panels.cj:103`。

验收项：

1. Gateway fake logs 写入后，Control UI logs RPC 返回同样行。
2. 浏览器 smoke test 中 Logs 面板可见最新 `gateway.ready` 行。
3. 不允许 Control UI 访问真实用户 secret；显示层也要保留 redaction。

### Phase 8：迁移门禁与禁止项

#### Phase 8.1 迁移 Gateway/Channel 直接 `LogUtils`

执行内容：

1. `src/gateway/core`、`src/gateway/runtime`、`src/gateway/channels` 中新增代码不得直接调用 `LogUtils.info/error`。
2. 迁移顺序：
   - `gateway_service.cj`
   - `gateway_channel_manager.cj`
   - Telegram adapter
   - Feishu adapter
   - QQ adapter
   - plugin adapters
   - Gateway runtime demo/run path
3. 未迁移文件必须写入 allowlist，并说明为什么暂时保留。

依据：

1. Metis 当前 Gateway/Channel 直接 `LogUtils` 分散，`rg -n "LogUtils" src/gateway` 可见大量调用。
2. OpenClaw 统一由 `createSubsystemLogger` 与 child logger 管控，见 `openclaw/src/gateway/server.impl.ts:170-203`。

验收项：

1. 执行：

   ```bash
   scripts/logging-output-gate.sh
   ```

2. 门禁脚本必须报告 `gateway/channel LogUtils: allowed=N disallowed=0`。
3. 新增 `LogUtils` 调用只能出现在 `scripts/logging-output-gate.sh` 中明确 allowlist 的 legacy 文件；新增文件不得默认加入 allowlist。
4. 当 Phase 4/5/6 迁移完成一个文件后，必须从脚本 allowlist 移除该文件。

#### Phase 8.2 禁止直接 stdout/stderr 污染机器输出

执行内容：

1. Cangjie 代码中用户可见输出只允许通过 `PrintUtils` 或新的 shell reporter。
2. JS sidecar 机器协议只允许 `writeProtocol` 写 stdout。
3. `--json` 命令路径必须保证 stdout 无额外 human 行。

依据：

1. Metis 已有 `PrintUtils`，见 `Metis/src/io/print_utils.cj:10-33`。
2. OpenClaw `routeLogsToStderr` 保持 stdout 干净，见 `openclaw/src/logging/console.ts:113-117`。

验收项：

1. 执行：

   ```bash
   scripts/logging-output-gate.sh
   ```

2. 门禁脚本必须报告：
   - `gateway/channel direct print: allowed=N disallowed=0`
   - `JS sidecar stdout: allowed=N disallowed=0`
   - `JS sidecar stderr: allowed=N disallowed=0`
3. `scripts/logging-output-gate.sh` 不得调用 `less`、`more`、`clear`、`exit` 用户 shell、修改配置文件或写入项目文件；只允许创建并清理临时目录。
4. 随机抽取 5 个 `--json` CLI 命令，stdout 必须可直接 `jq` 解析。

#### Phase 8.3 安全扫描门禁

执行内容：

1. 新增日志测试专用 fake secret 集合。
2. 每个日志测试完成后，对临时 `METIS_HOME` 执行敏感词扫描。
3. 扫描对象包括 shell capture、file logs、sidecar stdout/stderr capture。

依据：

1. OpenClaw logging docs 强调 redaction 设置，见 `openclaw/docs/logging.md:130-152`。
2. OpenClaw WS log 所有格式化路径都 redaction，见 `openclaw/src/gateway/ws-log.ts:103-157`。

验收项：

1. fake secret 出现在输入配置、fake inbound、fake error 中，但不得出现在任何输出文件。
2. CI 测试失败时必须打印哪个文件泄露了哪个 fake secret 的 redacted key 名称，不打印 secret 原值。

#### Phase 8.4 本轮新增门禁脚本

| 文件 | 作用 | 当前 allowlist 边界 |
| --- | --- | --- |
| `scripts/logging-output-gate.sh` | Phase 8 静态门禁；扫描 Gateway/Channel `LogUtils`、Gateway/Channel 直接 print/eprintln、JS sidecar stdout/stderr | 只允许 Phase 0.3 列出的 legacy 文件；新增文件命中即失败。 |
| `scripts/logging-output-gate-test.sh` | Bash 自测；构造临时 fixture 验证 allowlist 通过、非法 Gateway `LogUtils` 失败、非法 sidecar stdout 失败 | 不依赖 Node，不调用网络，不读写 `~/.metis`。 |

脚本输出示例：

```text
gateway/channel LogUtils: allowed=166 disallowed=0
gateway/channel direct print: allowed=0 disallowed=0
JS sidecar stdout: allowed=23 disallowed=0
JS sidecar stderr: allowed=1 disallowed=0
logging-output-gate: passed
```

脚本设计约束：

1. 只使用 `bash`、`rg`、`mktemp`、`wc`、`sed`、`rm` 等本地工具。
2. 不清屏、不进入 pager、不修改 Metis 配置、不启动 Gateway、不访问真实 IM 网络。
3. 可用 `--root <dir>` 指向临时 fixture，方便 shell 自测。
4. 失败时只打印前 120 行 disallowed 命中，避免刷屏。

### Phase 9：文档、手工验收与总体验证

#### Phase 9.1 内部开发文档

执行内容：

1. 在 `develop_steps` 记录迁移清单、allowlist、已迁移文件、未迁移原因。
2. 维护“事件字典”和“输出表面规则”。

依据：

1. 用户要求所有落地方案与验收项落盘到 `develop_steps`。
2. 本文件即整改主方案。

验收项：

1. 每个迁移 PR/commit 都更新 `develop_steps` 中的日志整改记录。
2. 新增事件必须先出现在事件字典，再进入代码。

#### Phase 9.2 用户文档

执行内容：

1. README / docs 用户文档只说明：
   - 日志在哪里。
   - 如何运行 `metis logs path/recent/current/tail/show`。
   - 如何打开 verbose。
   - 如何确认 Telegram/Feishu/QQ inbound/outbound 是否进入 Gateway。
2. 用户文档不写 OpenClaw/Hermes 等内部源码依据。

依据：

1. 既有用户文档已经说明 `~/.metis/logs/*.log` 和 `Gateway.inbound/Gateway.reply/Gateway.send`，见 `Metis/docs/user/gateway-im-plugins.md:159-167`。
2. 用户此前明确要求用户文档不要暴露内部参考项目依据。

验收项：

1. `rg -n "源码依据|Hermes|openclaw-lark|OpenClaw source|openclaw/src" README.md docs -g'*.md'` 不得出现内部依据描述；兼容性章节允许出现 OpenClaw 兼容的产品描述。
2. README 中的 logs 命令实际存在且可运行。

#### Phase 9.3 手工验收矩阵

| 编号 | 手工验收项 | 操作步骤 | 验收标准 |
| --- | --- | --- | --- |
| L-01 | Gateway 启动摘要 | 1. `export METIS_HOME=/tmp/metis-logging-manual`。2. 启动 `metis gateway run`。 | shell 可见 model、log file、Control UI、IM account 摘要；无大段 JSON；无 secret。 |
| L-02 | inbound 摘要日志 | 1. 使用 fake adapter 或测试 channel 注入一条消息。2. 打开当前日志文件。 | 文件日志有 `message.inbound`；包含 textLen；不包含完整消息正文。 |
| L-03 | outbound 发送成功 | 1. fake adapter 返回 send ok。2. 查看日志。 | 文件日志有 `message.outbound` 与 `message.sent`；包含 channel/accountId/peerHash/status/durationMs。 |
| L-04 | outbound 发送失败 | 1. fake adapter 返回 send failed。2. 查看 shell 与日志。 | shell 显示错误摘要；文件日志有 `message.send_failed`、errorKind、redacted error；用户侧失败可观测。 |
| L-05 | `metis logs tail` | 1. 写入 fake log。2. 执行 `metis logs tail <file> --limit 5`。 | 输出 5 行 human 日志，不是 JSON blob。 |
| L-06 | `metis logs tail --json` | 1. 执行 `metis logs tail <file> --limit 5 --json`。2. 用 `jq` 解析。 | stdout 每一行可解析，有 `type` 字段。 |
| L-07 | sidecar stdout 协议 | 1. 启动 fake sidecar。2. 捕获 stdout/stderr。 | stdout 每一行都是 JSON frame；stderr 可以有人类诊断；两者都无 secret。 |
| L-08 | Control UI Logs | 1. 启动 Gateway 和 Control UI。2. 打开 Logs 页面。 | 可看到最新 `gateway.ready` 与 channel 事件；无空白页；无前端错误。 |
| L-09 | redaction | 1. 配置 fake token/secret。2. 触发错误日志。3. `rg` 扫描临时目录。 | fake secret 原文不出现在 shell capture、日志文件、sidecar capture。 |
| L-10 | 普通/verbose 差异 | 1. 普通模式启动 Gateway。2. verbose 模式启动 Gateway。 | 普通模式只显示摘要；verbose 才显示 inbound/outbound/RPC 细节；文件日志仍完整。 |

#### Phase 9.4 统一构建与测试

执行内容：

1. 每轮代码修改完成后统一执行：

   ```bash
   source /path/to/cangjiesdk/envsetup.sh
   export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
   cjpm clean
   cjpm build -i
   cjpm test
   ```

2. 日志相关测试必须使用临时 `METIS_HOME`，不得读写真实 `~/.metis`。

验收项：

1. `cjpm clean` 成功。
2. `cjpm build -i` 成功。
3. `cjpm test` 成功。
4. 新增日志测试全部通过。
5. 敏感词扫描通过。

## 6. 后续实施顺序建议

必须按以下顺序推进，避免先迁移业务日志后没有稳定 sink：

1. Phase 0：证据与清单。
2. Phase 1：配置与当前日志文件语义。
3. Phase 2：logger facade、redaction、truncate。
4. Phase 3：shell reporter。
5. Phase 4：Gateway 主流程事件化。
6. Phase 5：IM adapter 和多账号运行态事件化。
7. Phase 6：JS sidecar / plugin host 输出边界。
8. Phase 7：`metis logs`、RPC、Control UI Logs。
9. Phase 8：迁移门禁。
10. Phase 9：用户文档、手工验收、clean/build/test。

任何实现阶段如果发现超出本文件的新增输出路径，必须先补充 Phase 0 输出清单和对应验收项，再改代码。
