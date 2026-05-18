# Metis 日志整改系列 02：完整差距矩阵与一次性补齐方案

创建日期：2026-05-18

状态：方案落盘，尚未修改源码。

关联文档：

- 系列 01：`develop_steps/metis-logging-series-01-runtime-output-openclaw-source-backed-landing-plan-2026-05-18.md`
- 本文件是系列 01 的源码复核版，修正系列 01 中“尚未修改源码”的过期状态，并建立必须清零的日志整改矩阵。

## 1. 本轮要求与边界

### 1.1 目标

本文件解决四个问题：

1. 重新审视 OpenClaw 源码中的日志与 shell 输出实现，确认 Metis 目标输出标准是否需要调整。
2. 按调整后的目标标准重新审计 Metis 源码，建立完整整改矩阵。
3. 将所有整改项落盘，并按系列文档命名，避免后续每轮只修补一小块。
4. 给出分阶段、可执行、可验收的落地计划；每个结论必须有源码依据，不允许猜测。

### 1.2 非目标

本文件只制定方案，不修改 Metis 源码。

后续实现阶段必须遵守：

1. 不改变 IM、模型、Agent、Control UI 的业务语义，除非对应 phase 明确要求。
2. 不使用真实 Telegram/Feishu/QQ 凭证进行自动化测试。
3. 不把 token、app secret、Authorization header、完整用户消息正文写入默认 info 日志。
4. 不把机器协议 stdout 与人类日志混在一起。

## 2. 复核方法

### 2.1 OpenClaw 复核命令

在本机 OpenClaw 源码目录中使用如下命令定位日志体系、Gateway 运行输出、ChannelManager、logs tail、redaction 与 WS log：

```bash
rg -n "class SubsystemLogger|createSubsystemLogger|raw\\(|DEFAULT_REDACT_PATTERNS|startChannelInternal|logs\\.tail|routeLogsToStderr|consoleLevel|consoleStyle|formatTimestamp" \
  /Users/l3gi0n/work/workspace_cangjie/openclaw/src \
  /Users/l3gi0n/work/workspace_cangjie/openclaw/docs \
  -g'*.ts' -g'*.md'
```

### 2.2 Metis 复核命令

在 Metis 主工作区中使用如下命令审计当前输出点：

```bash
rg -n "LogUtils\\.(trace|debug|info|warn|error)|PrintUtils\\.printLine|println\\(|print\\(|eprintln\\(|process\\.(stdout|stderr)\\.write" \
  src scripts -g'*.cj' -g'*.mjs'
```

按文件统计 Gateway 范围残留：

```bash
rg -n "LogUtils\\.(trace|debug|info|warn|error)" src/gateway/core src/gateway/runtime src/gateway/channels -g'*.cj' \
  | cut -d: -f1 | sort | uniq -c | sort -nr

rg -n "PrintUtils\\.printLine" src/gateway/core src/gateway/runtime src/gateway/channels -g'*.cj' \
  | cut -d: -f1 | sort | uniq -c | sort -nr
```

## 3. OpenClaw 源码事实矩阵

| 编号 | 能力面 | OpenClaw 源码事实 | 源码依据 | Metis 必须吸收的原则 |
| --- | --- | --- | --- | --- |
| OC-01 | 统一 logger API | OpenClaw 使用 `SubsystemLogger`，提供 `trace/debug/info/warn/error/fatal/raw/child`，并分别判断 console/file 是否启用。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/subsystem.ts:18`、`:302` | Metis Gateway 运行时不能继续散落 `LogUtils` 字符串日志；必须以 subsystem logger 作为运行时日志入口。 |
| OC-02 | console/file 分离 | OpenClaw subsystem logger 同一事件可分别进入 console 和 file，console 行有 `pretty/compact/json`。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/subsystem.ts:187`、`:231` | Metis 必须区分“用户 shell 摘要”和“文件 JSONL 排障信息”。 |
| OC-03 | stderr/stdout 边界 | OpenClaw `routeLogsToStderr()` 用来保持 stdout 干净，避免 RPC/JSON 输出被日志污染。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/console.ts:113` | Metis `--json` 命令、sidecar 协议 stdout、plugin stdout 必须保持机器可解析。 |
| OC-04 | console capture | OpenClaw patch `console.log/info/warn/error/debug/trace`，继续输出终端，同时写文件日志。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/console.ts:189`、`:240` | Metis JS sidecar/兼容 host 必须经过统一 helper，不允许随意 `console.log` 污染协议。 |
| OC-05 | redaction | OpenClaw 默认脱敏 env、JSON 字段、CLI flag、Authorization、Bearer、PEM、`sk-`、GitHub token、Slack token、Google API key、Telegram bot token 等。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/redact.ts:15` | Metis 当前脱敏规则必须补齐到同等覆盖面，尤其是 Telegram `/bot<token>/...`、`sk-`、PEM、CLI flags。 |
| OC-06 | token mask | OpenClaw token mask 保留首尾少量字符，短 token 直接 `***`。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/redact.ts:68` | Metis 日志应统一 mask 策略，既能排查“哪个 key”，又不泄露完整凭证。 |
| OC-07 | 时间戳 | OpenClaw long timestamp 包含时区 offset。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/timestamps.ts:55` | Metis JSONL `time` 需要带时区，便于跨 shell、Control UI、日志文件对齐。 |
| OC-08 | 文件日志上限 | OpenClaw file transport 追踪当前文件大小，达到上限后写一次 warning 并停止追加。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/logger.ts:180` | Metis 不能每写一条日志读取整个文件计算 size；必须改为 cached size 或 stat，并有清晰超限诊断。 |
| OC-09 | Gateway 启动摘要 | OpenClaw ready log 包含 agent model、plugin count、duration、log file，并对危险配置 warn。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-startup-log.ts:19` | Metis `gateway run` 普通模式必须输出可读启动摘要与 log file，warn 直接可见。 |
| OC-10 | ChannelManager account runtime | OpenClaw `startChannelInternal` 按 channel/account 启动，记录 enabled/configured/running/lastError/restart。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:258`、`:301` | Metis 多账号 IM 日志必须带 `channel/accountId/phase/status/failure`。 |
| OC-11 | channel logger 注入 | OpenClaw Gateway server 为 channel manager 传入 `channelLogs` 和 runtime env。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-channels.ts:95` | Metis adapter 不应自己直接 print；应该拿到注入的 account scoped logger。 |
| OC-12 | logs.tail RPC | OpenClaw `logs.tail` 返回 `file/cursor/size/lines/truncated/reset`。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/server-methods/logs.ts:10`、`/Users/l3gi0n/work/workspace_cangjie/openclaw/src/logging/log-tail.ts:12` | Metis `logs.tail` 和 `metis logs tail` 必须基于当前运行日志文件，支持 cursor、limit、maxBytes。 |
| OC-13 | WS log | OpenClaw WS 日志 normal 模式只记录 parse error、失败、慢响应；compact/full 才增加请求/响应详情。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/ws-log.ts:319`、`:383` | Metis Control UI/RPC 默认不能刷屏；verbose 才展开请求/响应摘要。 |
| OC-14 | WS redaction/truncate | OpenClaw WS metadata 统一 redaction 和 truncate。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/gateway/ws-log.ts:10`、`:103` | Metis RPC 参数、错误、adapter diagnostic 必须进同一套 redaction/truncate。 |
| OC-15 | `--verbose` 语义 | OpenClaw 文档明确 `consoleLevel` 会在 `--verbose` 时提升到 debug。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/gateway/configuration-reference.md:3248` | Metis `--verbose` 必须真实影响 console logger，而不是只打印一行 verbose 提示。 |
| OC-16 | 环境变量覆盖 | OpenClaw 文档说明 `OPENCLAW_LOG_LEVEL` 覆盖 file 与 console level。 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/help/environment.md:118` | Metis 需要明确 `METIS_LOG_LEVEL` 与 `METIS_CONSOLE_LEVEL` 的优先级，避免用户以为设置已生效但 shell 不变。 |

## 4. Metis 当前状态矩阵

| 编号 | 能力面 | Metis 当前事实 | 源码依据 | 状态 |
| --- | --- | --- | --- | --- |
| MT-01 | Gateway logger facade | 已有 `MetisSubsystemLogger`、`metisCreateSubsystemLogger`、JSONL 写入、console formatter。 | `src/gateway/logging/gateway_logging.cj:312`、`:362` | partial |
| MT-02 | settings | 已有 `level/file/consoleLevel/consoleStyle/maxFileBytes/redactSensitive/redactPatterns`。 | `src/core/config/gateway_user_settings.cj:262` | partial |
| MT-03 | 当前日志文件 | 默认路径为 `metis-gateway-yyyy-MM-dd.log`，`parse_args` 设置 `Config.logFile = gatewayLoggingCurrentLogFile()`。 | `src/gateway/logging/gateway_logging.cj:136`、`src/parse_args.cj:122` | aligned |
| MT-04 | file JSONL | 已写 `time/level/subsystem/event/message/meta`。 | `src/gateway/logging/gateway_logging.cj:386`、`:392` | partial |
| MT-05 | timestamp | `time` 只到毫秒，无 timezone offset。 | `src/gateway/logging/gateway_logging.cj:393`、`:427` | partial |
| MT-06 | file size cap | 每条日志通过 `File.readFrom(path).size` 计算文件大小。 | `src/gateway/logging/gateway_logging.cj:405` | partial |
| MT-07 | redaction | 已有 Authorization/Bearer/Telegram token/app_secret/api_key/URL password 等规则，但少于 OpenClaw 默认覆盖面。 | `src/gateway/logging/gateway_logging.cj:219` | partial |
| MT-08 | Gateway startup shell | 已有 startup intro 与 ready summary lines。 | `src/gateway/runtime/gateway_cli.cj:61`、`:86` | partial |
| MT-09 | `--verbose` | CLI 解析 verbose 并展示 marker，但未证明会统一提升 console logger level。 | `src/gateway/runtime/gateway_cli.cj:1315`、`:1357` | partial |
| MT-10 | event helper | `gatewayLogEventInfo/Debug/Error` 存在，但 meta 只有一个 `fields` 字符串。 | `src/gateway/core/gateway_channel_manager.cj:69`、`:77` | partial |
| MT-11 | inbound info | 核心 inbound 已记录 `textLen/mediaCount/messageId`，不写完整正文。 | `src/gateway/core/gateway_service.cj:253` | partial |
| MT-12 | outbound info | 核心 outbound/sent 路径已记录 textLen/hash/status，不直接写完整 reply。 | `src/gateway/core/gateway_service.cj:3914` | partial |
| MT-13 | legacy LogUtils | Gateway/core/runtime/channels 仍有 145 处 `LogUtils`。 | 见第 5.1 矩阵 | missing |
| MT-14 | runtime direct shell print | Gateway/core/runtime/channels 中存在大量 `PrintUtils.printLine`，尤其是 QQ/Feishu/Telegram adapter。 | 见第 5.2 矩阵 | missing |
| MT-15 | gate coverage | `logging-output-gate.sh` 扫 `println/print/eprintln`，未扫 `PrintUtils.printLine`。 | `scripts/logging-output-gate.sh:95` | missing |
| MT-16 | logs CLI/RPC | `logs.status/logs.tail` 与 `metis logs` 存在。 | `src/gateway/runtime/gateway_server_methods_ops.cj:518`、`src/program/cli_local_flows.cj:569` | partial |
| MT-17 | sidecar stdout/stderr | `metis-sidecar-logger.mjs` 与 Feishu sidecar 已有协议 stdout / 诊断 stderr helper。 | `scripts/lib/metis-sidecar-logger.mjs:67`、`scripts/feishu-ws-sidecar.mjs:77` | partial |
| MT-18 | Control UI WS | `gateway_control_ui_ws.cj` 仍有 16 处 `LogUtils`，尚未对齐 OpenClaw WS normal/compact/full 模式。 | 第 5.1 矩阵 | missing |

## 5. Metis 输出点整改矩阵

### 5.1 Gateway `LogUtils` 残留矩阵

当前命令：

```bash
rg -n "LogUtils\\.(trace|debug|info|warn|error)" src/gateway/core src/gateway/runtime src/gateway/channels -g'*.cj' \
  | cut -d: -f1 | sort | uniq -c | sort -nr
```

当前结果：

| 文件 | 命中数 | 风险分类 | 处理要求 | 验收标准 |
| --- | ---: | --- | --- | --- |
| `src/gateway/channels/telegram/telegram_adapter.cj` | 20 | adapter lifecycle / polling / send / command | 迁移到 `gateway/channel/telegram` account scoped logger；info 只保留启动/发送摘要，polling 细节 debug。 | `rg -n "LogUtils\\." src/gateway/channels/telegram/telegram_adapter.cj` 无命中；fake Telegram 测试能看到 `channel.started`、`message.send.failed` JSONL。 |
| `src/gateway/channels/qq/qq_adapter.cj` | 18 | webhook payload / send response / official ws | 迁移到 `gateway/channel/qq`；禁止 info 打 payload preview、response preview、完整 URL secret。 | `rg -n "LogUtils\\.|PrintUtils\\.printLine" src/gateway/channels/qq/qq_adapter.cj` 仅允许明确标注的人类 command 输出；fake QQ webhook 日志只有 len/hash/status。 |
| `src/gateway/runtime/gateway_control_ui_ws.cj` | 16 | Control UI WS / RPC | 迁移到 `gateway/control-ui` 或 `gateway/ws`；实现 normal/compact/full 或等效 verbose 分层。 | 默认模式只记录失败/慢请求；verbose 模式可看到 request/response 摘要；无 raw token。 |
| `src/gateway/runtime/demo.cj` | 16 | gateway serve lifecycle | 迁移到 startup reporter + `gateway` subsystem logger。 | `metis gateway run` 普通模式有 ready 摘要；文件日志有 `gateway.starting`、`gateway.ready`、`gateway.stopped`。 |
| `src/gateway/core/gateway_service.cj` | 15 | inbound/route/reply/send/native command | 全部走结构化 event helper；保留当前不写正文的方向，但把 `fields` 字符串改成 meta。 | `message.inbound/message.routed/message.outbound/message.sent` JSONL 字段可直接按 `channel/accountId/status` 过滤。 |
| `src/gateway/core/agent_bridge.cj` | 15 | model/tool/skill/reply | 迁移到 `gateway/model`、`gateway/tools`、`gateway/agent`；禁止 prompt/response 默认完整落盘。 | 模型失败日志有 provider/model/errorKind/durationMs；不含完整 prompt。 |
| `src/gateway/runtime/cron_runner.cj` | 12 | cron runtime | 迁移到 `gateway/cron`。 | cron job start/end/failure 有 jobId/status/durationMs。 |
| `src/gateway/core/gateway_session_executor.cj` | 5 | streaming / send fallback | 迁移到 `gateway/message`。 | streaming fallback/error 有 sessionKeyHash/status/errorKind。 |
| `src/gateway/runtime/gateway_config_reload_handler.cj` | 4 | config reload | 迁移到 `gateway/config`。 | reload 检测、apply、failure 有 oldHash/newHash/status。 |
| `src/gateway/runtime/gateway_platform_state.cj` | 3 | platform state | 迁移到 `gateway/platform`。 | state mutation/error 有 scope/status。 |
| `src/gateway/runtime/gateway_config_reloader.cj` | 3 | config watcher | 迁移到 `gateway/config`。 | watcher start/reload/failure 可查。 |
| `src/gateway/core/gateway_session_store.cj` | 3 | session storage | 迁移到 `gateway/session`。 | session read/write failure 有 pathHash/errorKind。 |
| `src/gateway/runtime/gateway_external_console.cj` | 2 | external console | 保留 user shell summary，内部诊断入 logger。 | user shell 行不含 JSON；失败进 file log。 |
| `src/gateway/runtime/gateway_config_factory.cj` | 2 | config build | 迁移到 `gateway/config` debug。 | 普通模式不刷屏，debug 有耗时。 |
| `src/gateway/runtime/gateway_cli.cj` | 2 | CLI bootstrap | 命令输出保留，运行诊断进 logger。 | `--json` stdout 干净。 |
| `src/gateway/channels/plugin/legacy_node_plugin_adapter.cj` | 2 | plugin adapter | 迁移到 `gateway/channel/plugin`。 | plugin start/send/pull failure 带 pluginId/accountId。 |
| `src/gateway/channels/plugin/command_plugin_adapter.cj` | 2 | plugin adapter | 同上。 | 同上。 |
| `src/gateway/runtime/gateway_configured_channel_binding_registry.cj` | 1 | binding registry | 迁移到 `gateway/channel/binding`。 | bind apply/failure 可查。 |
| `src/gateway/runtime/gateway_chat_turn_runtime.cj` | 1 | chat turn | 迁移到 `gateway/chat-turn`。 | turn start/end/failure 有 durationMs。 |
| `src/gateway/core/gateway_process_memory.cj` | 1 | memory/process | 迁移到对应 subsystem。 | no legacy `LogUtils`。 |
| `src/gateway/core/gateway_cron_session_reaper.cj` | 1 | session reaper | 迁移到 `gateway/session`。 | reaper count/error 可查。 |
| `src/gateway/channels/feishu/feishu_adapter.cj` | 1 | Feishu adapter | 迁移到 `gateway/channel/feishu`。 | no legacy `LogUtils`。 |

### 5.2 Gateway `PrintUtils.printLine` 残留矩阵

当前命令：

```bash
rg -n "PrintUtils\\.printLine" src/gateway/core src/gateway/runtime src/gateway/channels -g'*.cj' \
  | cut -d: -f1 | sort | uniq -c | sort -nr
```

当前结果：

| 文件 | 命中数 | 判定 | 处理要求 | 验收标准 |
| --- | ---: | --- | --- | --- |
| `src/gateway/runtime/gateway_cli.cj` | 130 | 多数是命令 human 输出，允许保留；`--json` 分支需审计。 | 建立 CLI output allowlist；`--json` 只允许 JSON，不允许额外日志。 | `metis gateway channel get telegram` 默认人类可读；`--json` 只输出 JSON。 |
| `src/gateway/runtime/gateway_settings_actions.cj` | 67 | 命令 human 输出，允许保留。 | 纳入 allowlist；禁止打印 secret 原值。 | 修改 app secret/token 的命令输出必须 masked。 |
| `src/gateway/runtime/gateway_sessions_cli.cj` | 29 | 命令 human 输出，部分 export/raw 需要标注。 | `export` 明确是 raw transcript；普通 show 做摘要。 | 默认 show 不打印超长原始 JSON；export 文档标注 raw。 |
| `src/gateway/channels/feishu/feishu_adapter.cj` | 23 | runtime adapter 直接 shell 输出，必须整改。 | 迁移到 channel logger；必要的人类启动提示通过 startup reporter 统一输出。 | `rg -n "PrintUtils\\.printLine" src/gateway/channels/feishu/feishu_adapter.cj` 清零或只剩明确注释的 reporter 调用。 |
| `src/gateway/channels/qq/qq_adapter.cj` | 16 | runtime adapter 直接 shell 输出，必须整改；包含 payload/response preview 风险。 | 迁移到 channel logger；preview 改为 textLen/bodyHash/status。 | fake QQ webhook/send 测试证明不输出 payload preview。 |
| `src/gateway/runtime/gateway_external_console.cj` | 7 | user shell 操作提示，允许但要归入 shell reporter。 | 统一 wording，错误入 logger。 | shell 输出不含 JSON 和 secret。 |
| `src/gateway/runtime/demo.cj` | 7 | demo/serve 混合，serve 运行时部分需要迁移。 | P0/P1 demo 可以保留；生产 serve 走 startup reporter/logger。 | `runGatewayService` 生产路径不直接 print 内部状态。 |
| `src/gateway/channels/telegram/telegram_adapter.cj` | 2 | runtime adapter 启动直接输出，必须迁移。 | 由 ChannelManager/startup summary 输出 `telegram/account running`。 | Telegram adapter 内不直接 print started。 |
| `src/gateway/channels/builtin/generic_builtin_channel_adapter.cj` | 2 | stub adapter 直接输出。 | 迁移到 `gateway/channel/<id>` info 或 startup summary。 | no direct adapter print。 |
| `src/gateway/runtime/gateway_cron_cli.cj` | 1 | 命令 human 输出，允许。 | allowlist。 | no action。 |
| `src/gateway/runtime/gateway_cli_human_output.cj` | 1 | formatter 输出，允许。 | allowlist。 | no action。 |
| `src/gateway/core/agent_bridge.cj` | 1 | runtime 运行提示，需审计。 | 若为用户必须看到的 tool/skill notice，走 shell reporter；否则 logger。 | 不破坏用户提示，同时文件日志有结构化事件。 |

### 5.3 `toJsonString()` 用户输出矩阵

当前发现：

| 文件/行 | 当前行为 | 判定 | 处理要求 | 验收标准 |
| --- | --- | --- | --- | --- |
| `src/gateway/runtime/gateway_cli.cj:657` | `--json` 分支直接 `PrintUtils.printLine(res.toJson().toJsonString())`。 | 允许，但必须只在显式 `--json`。 | 保留或改走统一 `gatewayPrintCommandOutput` 的 JSON 模式。 | 不带 `--json` 时输出 human；带 `--json` 时 stdout 只有 JSON。 |
| `src/gateway/runtime/gateway_cli.cj:728` | `gateway channel get --json` 直接打印 JSON。 | 允许，但需 gate 识别。 | 标注 allowlist。 | 同上。 |
| `src/program/cli_local_flows.cj:50`、`:55` | helper 用于 JSON 模式。 | 允许，但必须只被 JSON 分支调用。 | 保留并补测试/说明。 | 之前“不允许给用户大 JSON”的整改规则继续生效：默认 human，`--json` 才 JSON。 |
| `src/gateway/core/gateway_service.cj:2183`、`:2207` | Telegram native command 先构造 JSON，再 `renderTelegramNativeHumanReply`。 | 需要持续看护。 | 确保实际发给 Telegram 的文本是 human renderer，不是裸 JSON。 | Telegram native command 测试断言回复不以 `{` 开头。 |

### 5.4 JS sidecar / plugin stdout-stderr 矩阵

| 文件 | 当前行为 | 判定 | 处理要求 | 验收标准 |
| --- | --- | --- | --- | --- |
| `scripts/lib/metis-sidecar-logger.mjs` | `writeProtocol` 写 stdout JSON frame；`writeDiagnostic` 写 stderr。 | aligned | 作为所有 sidecar/helper 标准入口。 | sidecar 单测证明 stdout 只有 JSON frame，stderr 只有诊断。 |
| `scripts/feishu-ws-sidecar.mjs` | 已调用 helper 并 patch console。 | partial | 保持并补 gate。 | `node --test scripts/metis-sidecar-logger.test.mjs` 通过。 |
| `scripts/legacy-channel-host.mjs` | `process.stdout.write(result.stdout)` 透传子进程 stdout。 | partial | 需要明确这是 plugin 协议透传还是人类输出；若协议透传，必须在 host 边界记录 stderr/file 诊断。 | gate allowlist 有注释，测试覆盖 stdout 不混日志。 |
| `scripts/openclaw-compat-*.mjs` | 多为 CLI 工具 JSON report 输出。 | allowed | 允许作为命令工具 stdout，但不能作为 runtime sidecar 标准。 | gate 区分 runtime sidecar 与 CLI report 工具。 |

## 6. 修订后的 Metis 目标输出标准

### 6.1 必须保留的目标

1. 文件日志统一为 JSONL。
2. Gateway 运行时日志必须有 `time/level/subsystem/event/message`。
3. IM 与消息相关事件必须有结构化字段：`channel/accountId/agentId/sessionKey/peerHash/messageId/direction/status/durationMs/textLen/mediaCount/errorKind/error`。
4. 默认 info 不记录完整用户消息正文、完整 prompt、完整 response、完整 token、完整 app secret。
5. 命令默认输出 human；显式 `--json` 才输出 JSON。
6. JS sidecar stdout 只能输出协议 frame；诊断走 stderr 或文件日志。

### 6.2 本轮新增修订

| 修订项 | 原因 | OpenClaw 依据 | Metis 落地要求 |
| --- | --- | --- | --- |
| `event` 是 Metis 增强项，不是 OpenClaw 原样字段 | OpenClaw 常用 subsystem/message/meta，不要求所有日志都有 event。 | `openclaw/src/logging/subsystem.ts:330` 起各 level 方法接收 message/meta。 | Metis 保留 `event` 以提高可检索性，但文档必须写清楚这是 Metis 适配。 |
| gate 必须扫描 `PrintUtils.printLine` | Metis 的运行时 shell 输出主要通过 `PrintUtils.printLine`，当前 gate 漏扫。 | OpenClaw 通过 console capture/route 控制输出边界。 | `logging-output-gate.sh` 增加 `PrintUtils.printLine` 分类和 allowlist。 |
| redaction 补齐 OpenClaw 默认规则 | 当前 Metis 脱敏少于 OpenClaw。 | `openclaw/src/logging/redact.ts:15` | 增加 env/JSON/CLI/PEM/common token prefixes/Telegram bot URL patterns。 |
| timestamp 带 timezone offset | 便于跨系统排障。 | `openclaw/src/logging/timestamps.ts:55` | `time` 从 `yyyy-MM-dd'T'HH:mm:ss.SSS` 升级为含 offset 格式。 |
| file size cap 不读全文件 | 当前每条日志 `File.readFrom(path)` 会随文件变大而变慢。 | `openclaw/src/logging/logger.ts:180` | logger 初始化时 stat 或缓存 size，追加时累加；超限写一次 warning。 |
| `--verbose` 必须提升 console 细节 | 当前只看到 verbose marker，不足以表达真实 debug 输出。 | `openclaw/docs/gateway/configuration-reference.md:3248` | `gateway run --verbose` 将 consoleLevel 解析为 debug，文件 level 不被意外降低。 |
| console style 默认策略需明确 | OpenClaw TTY 默认 pretty，非 TTY compact；Metis 当前默认 compact。 | `openclaw/src/logging/console.ts:50` | 可选择实现 TTY-aware；若不实现，文档必须说明 Metis 固定 compact 是刻意差异。 |

## 7. 一次性补齐分阶段方案

### Phase 0：冻结矩阵与防止继续漏扫

执行内容：

1. 保留本文件作为系列 02。
2. 将 `scripts/logging-output-gate.sh` 的扫描面扩展到 `PrintUtils.printLine`。
3. 将 gate 分类为四类：CLI human output allowlist、runtime adapter forbidden、JSON mode allowlist、sidecar protocol allowlist。
4. gate 输出必须显示每类 allowed/disallowed 数量。

依据：

- OpenClaw 通过 `routeLogsToStderr` 和 console capture 约束 stdout/stderr：`openclaw/src/logging/console.ts:113`、`:189`。
- Metis 当前 gate 未扫 `PrintUtils.printLine`：`scripts/logging-output-gate.sh:95`。
- Metis adapter 中有 direct `PrintUtils.printLine`：`src/gateway/channels/qq/qq_adapter.cj:198`、`src/gateway/channels/feishu/feishu_adapter.cj:430`、`src/gateway/channels/telegram/telegram_adapter.cj:294`。

验收项：

1. 运行 `bash scripts/logging-output-gate.sh`。
2. 输出中必须包含 `Gateway PrintUtils.printLine` 或等价分类。
3. 在未迁移 adapter 前，gate 必须能报告 QQ/Feishu/Telegram adapter 的 disallowed 输出；完成迁移后 disallowed 为 0。

### Phase 1：补齐 logger core 与 OpenClaw 等价基础能力

执行内容：

1. 补齐 redaction 默认规则到 OpenClaw 覆盖面。
2. `time` 加 timezone offset。
3. file size cap 改为缓存/增量统计，并在首次超限时写 warning。
4. 明确 `METIS_LOG_LEVEL`、`METIS_CONSOLE_LEVEL`、`--verbose` 的优先级。
5. 保留 `event` 字段，但在代码注释/文档说明其为 Metis 检索增强字段。

依据：

- OpenClaw redaction：`openclaw/src/logging/redact.ts:15`。
- OpenClaw timestamp：`openclaw/src/logging/timestamps.ts:55`。
- OpenClaw max file bytes：`openclaw/src/logging/logger.ts:180`。
- Metis 当前 logger：`src/gateway/logging/gateway_logging.cj:148`、`:219`、`:386`。

验收项：

1. 增加 logger 单测：输入 `Authorization: Bearer xxx`、`sk-xxx`、`bot123456:token`、PEM、`--api-key xxx`，输出不包含原文 secret。
2. 日志 JSONL `time` 包含 timezone offset。
3. 构造小 `maxFileBytes`，日志超限后只写一次 warning，后续不反复刷屏。
4. `gateway run --verbose` 下 console debug 事件可见；不带 verbose 时 debug 不显示。

### Phase 2：结构化事件字典与 meta builder

执行内容：

1. 建立 Gateway 事件字典，至少覆盖：
   - `gateway.starting`
   - `gateway.ready`
   - `gateway.stopped`
   - `channel.registered`
   - `channel.starting`
   - `channel.started`
   - `channel.failed`
   - `channel.stopped`
   - `message.inbound`
   - `message.routed`
   - `message.outbound`
   - `message.sent`
   - `message.send.failed`
   - `model.request`
   - `model.response`
   - `model.failed`
   - `rpc.request.failed`
   - `rpc.request.slow`
2. 将 `gatewayLogEventInfo/Debug/Error(fields: String)` 改为结构化 meta builder。
3. 禁止把 `channel=... accountId=...` 拼成一个 `fields` 字符串。

依据：

- OpenClaw subsystem logger 接收 metadata object 并写入文件日志：`openclaw/src/logging/subsystem.ts:330`、`:382`、`:434`。
- Metis 当前把 fields 拼成字符串：`src/gateway/core/gateway_channel_manager.cj:69`、`:77`。

验收项：

1. `message.inbound` JSONL 中 `channel`、`accountId`、`textLen` 是独立字段，不是 `fields` 字符串。
2. `rg -n 'fields: "channel=' src/gateway` 无新增命中；旧命中必须清零或列入迁移清单。
3. 单测解析 JSONL 后可直接读取 `obj.get("channel")`。

### Phase 3：Gateway run shell reporter

执行内容：

1. 引入 Gateway shell reporter，专门负责用户可见启动/就绪/关闭摘要。
2. `gateway run` 普通模式输出：
   - 配置加载结果
   - auth/control mode
   - main model
   - log file
   - HTTP/Control UI URL
   - 每个 configured account 的 `channel/account running|waiting|disabled|failed`
   - ready duration
3. `--verbose` 才显示 adapter start 阶段、config reload、poll/send 摘要。
4. runtime 代码不再直接 `PrintUtils.printLine` 内部诊断。

依据：

- OpenClaw ready summary：`openclaw/src/gateway/server-startup-log.ts:19`。
- OpenClaw channel runtime state：`openclaw/src/gateway/server-channels.ts:301`。
- Metis 当前 startup lines：`src/gateway/runtime/gateway_cli.cj:61`、`:86`。
- Metis 当前 serve 生产路径仍有直接 print：`src/gateway/runtime/demo.cj:117`。

验收项：

1. `metis gateway run` 普通模式出现一屏内可读 ready summary。
2. 普通模式不显示 payload preview、完整消息正文、完整 token。
3. `--verbose` 可以看到更细 channel start/retry 摘要。
4. `rg -n "PrintUtils\\.printLine" src/gateway/runtime/demo.cj` 中生产 serve 路径清零，demo-only 输出可保留并注释。

### Phase 4：Gateway core 消息、模型、会话、cron 迁移

执行内容：

1. 迁移 `gateway_service.cj` 中 message inbound/route/outbound/sent/error。
2. 迁移 `agent_bridge.cj` 中 model/tool/skill 事件。
3. 迁移 session executor/store、cron runner/reaper。
4. info 级只写摘要；debug 级可写 redacted preview；默认不写完整 prompt/response。

依据：

- OpenClaw outbound 记录 target/textLength/mediaCount/status，不默认写完整正文：`openclaw-lark/src/messaging/outbound/outbound.ts:160`、`openclaw-lark/src/messaging/outbound/deliver.ts:242`。
- Metis inbound 已有 textLen 方向但仍是 fields 字符串：`src/gateway/core/gateway_service.cj:253`。
- Metis `agent_bridge.cj` 仍有 15 处 `LogUtils`：第 5.1 矩阵。

验收项：

1. 模拟 inbound 一条文本消息，日志出现 `message.inbound`，包含 `textLen`，不包含原文。
2. 模拟模型调用失败，日志出现 `model.failed`，包含 provider/model/errorKind/durationMs，不含完整 prompt。
3. `rg -n "LogUtils\\." src/gateway/core/gateway_service.cj src/gateway/core/agent_bridge.cj` 清零或只剩明确注释的临时 allowlist。

### Phase 5：IM adapter 与多账号 runtime 迁移

执行内容：

1. Telegram adapter：迁移 polling/webhook/start/send/native command 诊断。
2. Feishu adapter：迁移 long connection/webhook/sidecar/ingest/send/pairing 诊断。
3. QQ adapter：迁移 webhook/official ws/send/heartbeat 诊断；删除 payload/response preview shell 输出。
4. Builtin/plugin adapter：统一 channel logger。
5. 每条 channel runtime 日志必须包含 `channel/accountId/phase/status`。

依据：

- OpenClaw ChannelManager account 启动：`openclaw/src/gateway/server-channels.ts:258`、`:301`。
- OpenClaw channel logger 注入：`openclaw/src/gateway/server-channels.ts:95`。
- Metis QQ 直接打印 payload preview：`src/gateway/channels/qq/qq_adapter.cj:198`。
- Metis QQ 直接打印 send URL/response：`src/gateway/channels/qq/qq_adapter.cj:563`、`:598`。
- Metis Feishu 直接打印启动/ingest/sidecar：`src/gateway/channels/feishu/feishu_adapter.cj:430`、`:675`、`:3415`。
- Metis Telegram 直接打印 started：`src/gateway/channels/telegram/telegram_adapter.cj:294`。

验收项：

1. `rg -n "LogUtils\\.|PrintUtils\\.printLine" src/gateway/channels/telegram src/gateway/channels/feishu src/gateway/channels/qq -g'*.cj'` 无禁止项。
2. fake Telegram/Feishu/QQ account start 测试分别产生 `channel.started`。
3. fake send failure 测试分别产生 `message.send.failed`，含 `channel/accountId/errorKind`。
4. 日志与 shell 输出均不包含 payload preview、response preview、完整 bot token、完整 app secret。

### Phase 6：Control UI / RPC / WS 输出迁移

执行内容：

1. 迁移 `gateway_control_ui_ws.cj` 16 处 `LogUtils`。
2. 实现 OpenClaw 对齐的 WS 输出层级：
   - normal：parse error、failure、slow response
   - verbose/compact：request/response 摘要、duration
   - full/debug：redacted metadata
3. 所有 RPC 参数和响应摘要通过 redaction/truncate。

依据：

- OpenClaw WS normal/compact/full：`openclaw/src/gateway/ws-log.ts:319`、`:383`。
- OpenClaw WS redaction/truncate：`openclaw/src/gateway/ws-log.ts:103`。
- Metis `gateway_control_ui_ws.cj` 仍有 16 处 `LogUtils`：第 5.1 矩阵。

验收项：

1. 默认模式下 Control UI 正常操作不刷大量 RPC 日志。
2. 构造失败 RPC，文件日志出现 `rpc.request.failed`，含 method/duration/errorKind。
3. 构造慢 RPC，文件日志出现 `rpc.request.slow`。
4. `rg -n "LogUtils\\." src/gateway/runtime/gateway_control_ui_ws.cj` 清零。

### Phase 7：sidecar / plugin host stdout-stderr 边界

执行内容：

1. 所有 runtime sidecar 使用 `scripts/lib/metis-sidecar-logger.mjs`。
2. 明确 `process.stdout.write` allowlist：
   - protocol frame
   - CLI report command
   - plugin stdout passthrough
3. 明确 `process.stderr.write` allowlist：
   - diagnostic
   - crash/error
4. 新增 gate：runtime sidecar 不允许 `console.log`，除非已被 helper patch。

依据：

- OpenClaw console capture：`openclaw/src/logging/console.ts:189`。
- OpenClaw plugin runtime logger adapter：`openclaw/src/plugin-sdk/runtime-logger.ts:10`。
- Metis sidecar helper：`scripts/lib/metis-sidecar-logger.mjs:67`。

验收项：

1. `node --test scripts/metis-sidecar-logger.test.mjs` 通过。
2. gate 报告 JS stdout/stderr allowlist，并区分 CLI report 与 runtime sidecar。
3. Feishu sidecar stdout 每行可 JSON parse，stderr 不包含协议 frame。

### Phase 8：logs CLI / RPC / Control UI 排障闭环

执行内容：

1. 确认 `metis logs path/current/recent/tail/show` 与 Gateway `logs.status/logs.tail` 使用同一个 current log file。
2. `logs.tail` 返回 `file/cursor/size/lines/truncated/reset`。
3. 本地 `metis logs tail` 默认 human；`--json` 输出机器结构。
4. 文档说明常见排障路径：
   - IM 无回复先看 `message.inbound`
   - 路由问题看 `message.routed`
   - 模型问题看 `model.failed`
   - 发送问题看 `message.send.failed`
   - adapter 启动看 `channel.started/channel.failed`

依据：

- OpenClaw `logs.tail`：`openclaw/src/gateway/server-methods/logs.ts:10`、`openclaw/src/logging/log-tail.ts:12`。
- Metis 当前 logs methods：`src/gateway/runtime/gateway_server_methods_ops.cj:518`、`:571`。
- Metis local logs command：`src/program/cli_local_flows.cj:569`。

验收项：

1. 启动 gateway 后，`metis logs current` 与 `metis gateway logs status` 指向同一文件。
2. `metis logs tail --limit 5` 输出人类可读最近日志。
3. `metis logs tail --limit 5 --json` 输出 JSON，不混入普通日志。
4. Control UI Logs tab 能读取同一文件尾部。

### Phase 9：统一门禁、测试与清零标准

执行内容：

1. 更新 `scripts/logging-output-gate.sh`，覆盖：
   - `LogUtils`
   - `PrintUtils.printLine`
   - raw `println/print/eprintln`
   - JS `stdout/stderr`
   - JS `console.*`
   - direct `toJsonString()` user output
2. 新增/补齐单测：
   - logger redaction
   - timestamp with offset
   - file size cap
   - structured event meta
   - no full message body at info
   - channel adapter fake lifecycle
   - sidecar stdout/stderr
   - logs CLI/RPC
3. 最终统一执行：

```bash
cjpm clean
cjpm build -i
cjpm test
bash scripts/logging-output-gate.sh
```

依据：

- OpenClaw 以 logger tests、gateway tests、WS log tests 等方式守护输出行为；本方案对 Metis 的验收必须可自动化。
- Metis 当前 gate 漏扫 `PrintUtils.printLine`，不能作为完成标准。

验收项：

1. `bash scripts/logging-output-gate.sh` 显示所有 disallowed 为 0。
2. `rg -n "LogUtils\\." src/gateway/core src/gateway/runtime src/gateway/channels -g'*.cj'` 无未解释残留。
3. `rg -n "PrintUtils\\.printLine" src/gateway/channels src/gateway/core -g'*.cj'` 无 runtime adapter 禁止输出。
4. `cjpm clean && cjpm build -i && cjpm test` 全部通过。

## 8. 完成度口径

当前不能用“gate 通过”作为完成依据，因为 gate 未覆盖 `PrintUtils.printLine`。

按本文件矩阵估算：

| 模块 | 当前完成度 | 判断依据 |
| --- | ---: | --- |
| logger facade 基础设施 | 70% | 有 `MetisSubsystemLogger`、JSONL、settings，但 timestamp/redaction/file cap/verbose 仍缺。 |
| Gateway startup shell summary | 55% | 已有 startup/ready lines，但与 adapter runtime、verbose、危险配置 warn 尚未完全闭环。 |
| structured event meta | 45% | 有 event helper，但 meta 仍是 `fields` 字符串。 |
| core message/model/session/cron 迁移 | 45% | inbound/outbound 方向正确，但 `LogUtils` 残留多，模型/session/cron 未清零。 |
| IM adapter 迁移 | 20% | Telegram/Feishu/QQ adapter 仍有直接 `LogUtils` 和 `PrintUtils.printLine`。 |
| WS/RPC 输出 | 25% | Control UI WS 仍有 16 处 `LogUtils`，未对齐 normal/compact/full。 |
| sidecar stdout/stderr | 65% | helper 已有，Feishu sidecar 已接入，但 gate/allowlist 还不完整。 |
| logs CLI/RPC/UI | 65% | 能力已存在，但需要确认 current file、cursor、人类输出、Control UI 同源。 |
| gate 与测试 | 35% | gate 存在但漏扫关键输出封装；测试还需按矩阵补齐。 |

综合完成度：约 48%。

这个百分比不是业务功能完成度，而是“日志整改矩阵清零程度”。之前基础设施已经打下来了，但按 OpenClaw 源码标准看，迁移和门禁仍未清零。

## 9. 不允许再犯的红线

1. 不能只跑 `scripts/logging-output-gate.sh` 就声明日志整改完成；gate 本身必须先补全。
2. 不能只整改一个 adapter 后声明 IM 输出整改完成；Telegram、Feishu、QQ、builtin、plugin adapter 必须同时进入矩阵。
3. 不能默认打印用户消息正文、payload preview、HTTP response preview、完整 URL token。
4. 不能把 `channel=xxx accountId=yyy` 拼成一个 `fields` 字符串冒充结构化日志。
5. 不能在默认 human 命令里直接输出大 JSON；`--json` 分支除外。
6. 不能让 sidecar/plugin runtime 的人类日志污染协议 stdout。
7. 每个新增日志点必须回答：subsystem 是什么、event 是什么、level 是什么、哪些字段脱敏、普通 shell 是否显示、是否有测试。
