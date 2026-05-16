# Metis 用户界面命令输出 JSON 审计矩阵

日期：2026-05-17

## 1. 审计规则

铁律：面向用户的 CLI、交互式命令、IM 原生命令、Control UI 命令默认输出不得直接展示 `toJsonString()` 的原始 JSON。允许 JSON 的范围只有：

- 显式机器输出：`--json`，或命令名本身就是机器输出语义，例如 `message json`。
- 显式导出：例如 `gateway sessions export` 的 transcript JSONL。
- 协议/API/持久化/日志/内部 tool 或 RPC payload，不直接作为用户默认展示。

默认展示必须走 `gatewayFormatCommandOutput` / `gatewayPrintCommandOutput` 或等价 human renderer，并用测试证明不会泄露 `"ok"`、`"result"`、`"image"`、`"schedule"`、`"sessions"` 等原始 JSON 键。

## 2. 顶层 CLI 命令矩阵

来源：

- 顶层描述：`src/program_support/command_data.cj:6-27`
- 示例与扩展命令：`src/program_support/command_data.cj:30-180`
- Gateway 转发别名：`src/program/register_gateway_dispatch.cj`
- 本地 flow 注册：`src/program/register_core_dispatch.cj`

| 层级 | 用户命令 | 子命令/别名 | 默认输出策略 | JSON 例外 | 本轮审计结论 |
|---|---|---|---|---|---|
| root | `setup` | 无 | 交互式 human | 无 | 未发现默认 JSON 直出 |
| root | `onboard` | 无 | 交互式 human | 无 | 未发现默认 JSON 直出 |
| root | `configure` | 无 | 交互式 human | 无 | 未发现默认 JSON 直出 |
| root | `interactive` | `tui`、`chat` | 交互 shell human | slash 子命令显式 JSON 例外见第 5 章 | 未发现默认 JSON 直出 |
| root | `status` | 映射 `gateway status` | Gateway status human | 无 | 已走 human action |
| root | `health` | 映射 `gateway health` | `gatewayPrintCommandOutput` | 无 | 已补通用 formatter，未知 RPC 不再裸 JSON |
| root | `doctor` | 映射 `gateway call doctor.remediation` | `gatewayPrintCommandOutput` | `gateway call --json ...` | 已补通用 formatter |
| root | `dashboard` | `--open`、`--no-open` | human URL/asset/token source | 无 | 未发现默认 JSON 直出 |
| root | `agent` | `--message`、`--prompt`、`--local`、`--json` 等 | 默认 assistant human answer | `--json` | JSON 只保留显式 `--json` |
| root | `agents` | 见第 4 章 | 默认 human | `--json` | 已有人类摘要；team fallback raw 已改 |
| root | `mcp` | 见第 4 章 | 默认 human | `show --json` | `show` 默认 JSON 已整改 |
| root | `tasks` | `list`、`show`、`current`、`next` | local summary human | `--json` 由 local renderer 支持 | 未发现默认 JSON 直出 |
| root | `config` | 见第 4 章 | local summary human | `show --json` | JSON 只保留显式 |
| root | `backup` | `state`、`path`、`preview` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `reset` | `state`、`preview`、`targets` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `uninstall` | `preview`、`state`、`path` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `message` | `preview`、`json`、`file` | 默认 preview human | `message json` / `--json` | 命令名显式机器输出，允许 |
| root | `models` | 见第 4 章 | local summary human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `logs` | `path`、`recent`、`current`、`tail`、`show` | human/path/log text | 无 | 未发现默认 JSON 直出 |
| root | `docs` | `open`、`topics`、`search`、`index`、`path` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `system` | `info`、`paths`、`env`、`status`、`doctor` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `approvals` | `list`、`status`、`current`、`open`、`policy`、`json` | human | `approvals json` | 命令名显式机器语义，允许 |
| root | `sandbox` | `status`、`mode`、`rules`、`entry`、`check`、`profile` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `node` | `show`、`current`、`policy`、`audit`、`status`、`history` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `qa` | `status`、`list`、`run`、`scripts`、`report`、`history` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `hooks` | `list`、`status`、`current`、`runbook`、`validate`、`open` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `webhooks` | `list`、`status`、`deliveries`、`endpoints`、`current`、`replay` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `qr` | `show`、`status`、`open`、`payload`、`copy`、`link` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `pairing` | `status`、`list`、`approve`、`current`、`open`、`code`、`sessions` | human，隐藏明细 | `--json` | 未发现默认 JSON 直出 |
| root | `daemon` | `status`、`info`、`logs`、`pid`、`socket`、`restart` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `acp` | `status`、`list`、`current`、`docs`、`mode`、`runtime` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `nodes` | `list`、`policy`、`audit`、`status`、`current` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root | `devices` | `list`、`policy`、`audit`、`status`、`current` | human | `--json` local summary 支持 | 未发现默认 JSON 直出 |
| root alias | `channel` / `channels` | 映射 `gateway channel` | human | 无 | 走 Gateway formatter/actions |
| root alias | `plugin` / `plugins` | 映射 `gateway plugin` | human | 无 | 走 Gateway actions |
| root alias | `sessions` | 映射 `gateway sessions` | human/export | `export` | export 为显式导出 |
| root alias | `subagents` | 映射 `gateway subagents` | `gatewayPrintCommandOutput` | 无 | 已由 subagents renderer 覆盖 |
| root alias | `cron` | 映射 `gateway cron` | human | `--json` | add/update/wake/error/run 已整改 |
| root | `help`、`version` | 无 | human | 无 | 未发现默认 JSON 直出 |

## 3. Gateway 命令矩阵

来源：`src/gateway/runtime/gateway_cli.cj:163-188`、`src/gateway/runtime/gateway_cli.cj:342-378`、`src/gateway/runtime/gateway_cli.cj:427-470`、`src/gateway/runtime/gateway_cli.cj:500-523`

| 层级 | 用户命令 | 子命令/选项 | 默认输出策略 | JSON 例外 | 本轮审计结论 |
|---|---|---|---|---|---|
| gateway | `gateway help` | 无 | human help | 无 | OK |
| gateway | `gateway run` / `serve` | 无 | runtime log/human | 无 | OK |
| gateway | `gateway status` | 无 | `gatewayActionsPrintStatus` human | 无 | OK |
| gateway | `gateway health` | 无 | `gatewayPrintCommandOutput` | 无 | 通用 RPC fallback 已补 |
| gateway | `gateway probe` | 无 | human + formatted health/status | 无 | 通用 RPC fallback 已补 |
| gateway | `gateway discover` | 无 | discover renderer | 无 | OK |
| gateway | `gateway call` | `[--json] <method> [json]` | 默认 formatted human | `--json` | 已新增 `--json` 显式机器输出，默认不再裸 JSON |
| gateway | `gateway usage-cost` | 无 | `gatewayPrintCommandOutput` | 无 | 通用 RPC fallback 已补 |
| gateway | `gateway master` | `on`、`off` | human mutation | 无 | OK |
| gateway | `gateway stop` | 无 | human process status | 无 | OK |
| gateway | `gateway restart` | 无 | human process status | 无 | OK |
| gateway channel | `gateway channel list` | 无 | channel help/action human | 无 | OK |
| gateway channel | `gateway channel health` | `[id]` | channels.health renderer | 无 | OK |
| gateway channel | `gateway channel runtime` | `[id]` | channels.runtime renderer | 无 | OK |
| gateway channel | `gateway channel get` | `<id>` | channels.get renderer | 无 | OK |
| gateway channel | `gateway channel audit` | `[id]` | channels.audit renderer | 无 | `remaining` raw JSON 摘要已整改 |
| gateway channel | `gateway channel enable/disable` | `<id>` | human mutation | 无 | OK |
| gateway channel | `gateway channel set` | `<feishu|qq> <key> <value...>` | human mutation | 无 | OK |
| gateway media image | `status` | `--channel shared|telegram|feishu|qq` | image status renderer | 无 | 已整改为 human |
| gateway media image | `set` | `--provider <id> --model <model> [--channel ...]` | image mutation renderer | 无 | 已整改为 human |
| gateway media image | `add-model` | 同上 | image mutation renderer | 无 | 已整改为 human |
| gateway media image | `remove-model` | 同上 | image mutation renderer | 无 | 已整改为 human |
| gateway plugin | `list` | 无 | human | 无 | OK |
| gateway plugin | `list-supported` | 无 | human | 无 | OK |
| gateway plugin | `install` | `<name> [--app-id] [--app-secret] [--force]` | human | 无 | OK |
| gateway plugin | `enable/disable` | `<id>` | human | 无 | OK |
| gateway plugin | `set` | `<id> <key> <value...>` | human | 无 | OK |
| gateway sessions | `path` | 无 | path text | 无 | OK |
| gateway sessions | `list` | 无 | human list | 无 | OK |
| gateway sessions | `show` | `<key> [--limit n]` | human transcript preview | 无 | OK |
| gateway sessions | `export` | `<key>` | raw JSONL transcript | explicit export | 允许 |
| gateway sessions | `clear/delete/remove` | `<key>` | human mutation | 无 | OK |
| gateway subagents | `list/status/logs/info/kill/send/steer/spawn/help` | 由 `/subagents` 统一处理 | `gatewayPrintCommandOutput` subagents renderer | 无 | OK |
| gateway cron | `path` | 无 | path text | 无 | OK |
| gateway cron | `status` | `[--json]` | human | `--json` | OK |
| gateway cron | `list` | `[--json] [--all] [--offset] [--limit]` | human | `--json` | OK |
| gateway cron | `add/create` | `--name --every/--at/--cron --session --message ... [--json]` | human | `--json` | 本轮从 default JSON 改为 human |
| gateway cron | `remove/rm/delete` | `<id>` / `--id` / `--job-id` | human | 无 | OK |
| gateway cron | `enable/disable` | `<id>` | human | 无 | OK |
| gateway cron | `edit` | `<jobId> --enabled/--message` | human | 无 | OK |
| gateway cron | `update` | `--job-id ... [--json]` | human | `--json` | 本轮从 default JSON 改为 human |
| gateway cron | `run` | `<id>` / `--job-id <id> [--due] [--json]` | human | `--json` | 本轮 runtime hook 默认改为 human |
| gateway cron | `runs` | `[--json] [--job-id] [--limit] [--offset]` | human | `--json` | OK |
| gateway cron | `wake` | `[--job-id] [--mode now|next-heartbeat] --text <hint> [--json]` | human | `--json` | 本轮从 default JSON 改为 human |

## 4. 本地功能命令矩阵

来源：`src/program/cli_local_flows.cj` 中各 `cliRun*Flow`。

| 命令 | 子命令全集 | 默认输出策略 | JSON 例外 | 本轮审计结论 |
|---|---|---|---|---|
| `config` | `path`、`show`、`workspace`、`defaults`、`validate`、`get <key>`、`set <field> <value...>` | human/local summary | `show --json`，local summary `--json` | OK |
| `backup` | `state`、`path`、`preview` | human/local summary | `--json` | OK |
| `reset` | `state`、`preview`、`targets` | human/local summary | `--json` | OK |
| `uninstall` | `preview`、`state`、`path` | human/local summary | `--json` | OK |
| `message` | `preview`、`json`、`file <path>` | preview human | `json` / `--json` | 显式机器输出允许 |
| `agent` | `--message/--prompt`、`--session-id`、`--to`、`--agent`、`--thinking`、`--verbose`、`--timeout`、`--deliver`、`--best-effort-deliver`、`--lane`、`--run-id`、`--extra-system-prompt`、`--reply-*`、`--json`、`--local` | answer human | `--json` | OK |
| `agents` | `list`、`summary`、`health`、`capabilities`、`bindings`、`bind`、`unbind`、`team`、`migrate`、`add`、`set-identity`、`delete` | human | `--json` | fallback raw JSON 已整改 |
| `agents team` | `list`、`get`、`create`、`update`、`delete` | human | `--json` | OK |
| `agents migrate` | `--dry-run` | human | `--json` | OK |
| `mcp` | `serve`、`list`、`show [name]`、`set <name> <json>`、`unset <name>` | human | `show --json` | `show` 默认 raw JSON 已整改 |
| `tasks` | `list`、`show`、`current`、`next` | human | `--json` | OK |
| `models` | `list`、`current`、`providers`、`auth`、`resolve`、`set`、`set-image`、`image-fallbacks add/remove/clear`、`status`、`search` | human | `--json` | OK |
| `logs` | `path`、`recent`、`current`、`tail`、`show` | human/log text | 无 | OK |
| `docs` | `open`、`topics`、`search`、`index`、`path` | human | `--json` | OK |
| `system` | `info`、`paths`、`env`、`status`、`doctor` | human | `--json` | OK |
| `approvals` | `list`、`status`、`current`、`open`、`policy`、`json` | human | `json` / `--json` | 显式机器输出允许 |
| `sandbox` | `status`、`mode`、`rules`、`entry`、`check`、`profile` | human | `--json` | OK |
| `node` | `show`、`current`、`policy`、`audit`、`status`、`history` | human | `--json` | OK |
| `qa` | `status`、`list`、`run`、`scripts`、`report`、`history` | human | `--json` | OK |
| `hooks` | `list`、`status`、`current`、`runbook`、`validate`、`open` | human | `--json` | OK |
| `webhooks` | `list`、`status`、`deliveries`、`endpoints`、`current`、`replay` | human | `--json` | OK |
| `qr` | `show`、`status`、`open`、`payload`、`copy`、`link` | human | `--json` | OK |
| `pairing` | `status`、`list`、`approve`、`current`、`open`、`code`、`sessions` | human | `--json` | OK |
| `daemon` | `status`、`info`、`logs`、`pid`、`socket`、`restart` | human | `--json` | OK |
| `acp` | `status`、`list`、`current`、`docs`、`mode`、`runtime` | human | `--json` | OK |
| `nodes` | `list`、`policy`、`audit`、`status`、`current` | human | `--json` | OK |
| `devices` | `list`、`policy`、`audit`、`status`、`current` | human | `--json` | OK |

## 5. 交互式与 IM 命令矩阵

来源：

- CLI shell：`src/cliapp/metis_command.cj`
- CLI shell command dispatcher：`src/cliapp/process_input.cj`
- CLI shell memory commands：`src/cliapp/memory_command.cj`
- CLI shell skills commands：`src/core/skills/skills_command_ops.cj`
- Telegram catalog：`src/gateway/core/gateway_telegram_native_command_catalog.cj:64-109`
- Telegram human renderer：`src/gateway/core/gateway_service.cj`

| 表面 | 命令 | 子命令/菜单 | 默认输出策略 | JSON 例外 | 本轮审计结论 |
|---|---|---|---|---|---|
| CLI shell | `/Metis` | menu | human | 无 | OK |
| CLI shell | `/status` / `status` | 无 | token/session usage human | 无 | OK |
| CLI shell | `/models` | `help`、`status`、`set-image`、`image-fallbacks add/remove/clear`、provider browse/set | human | 无 | OK |
| CLI shell | `/dashboard` | open/status shortcut | human | 无 | OK |
| CLI shell | `/skills` | `list`、`info`、`check`、`search`、`install`、`update` | human | `check --json`、`search --json` | 显式 `--json` 保留；默认由 skills human formatter/外部 CLI 文本负责 |
| CLI shell | `/memory` | `status`、`index`、`search`、`promote`、`promote explain`、`promote-explain`、`rem-harness`、`dreaming` | 默认 human | `status --json`、`search --json`、`promote --json`、`promote explain --json`、`rem-harness --json`、`dreaming status --json` | `/memory search` 与 `/memory dreaming status` 默认 raw JSON 已整改 |
| CLI shell | `/memory dreaming` | `status`、`reconcile`、`register [light|rem|deep|all]`、`sweep [light|rem|deep|all]` | human | `status --json` | `status` 默认 raw JSON 已整改 |
| CLI shell | `/mcp` | `add`、`add-sse`、`remove`、`list` | human | 无 | OK |
| CLI shell | `/conversation` | conversation manager 子命令 | human | 无 | 未发现默认 JSON 直出 |
| CLI shell | `/cmd` | custom command manager 子命令 | human | 无 | 未发现默认 JSON 直出 |
| CLI shell | `/agents` | list custom agents | human | 无 | OK |
| CLI shell | `/init` | AGENTS.md 初始化向导 | human | 无 | OK |
| CLI shell | `/channel` | `list`、`enable`、`disable`、`set` | Gateway channel human | 无 | OK |
| CLI shell | `/plugin` | plugin 子命令 | Gateway plugin human | 无 | OK |
| CLI shell | `/sessions` | sessions 子命令 | Gateway sessions human/export | `export` | OK |
| CLI shell | `/subagents` | subagents 子命令 | subagents renderer | 无 | OK |
| CLI shell | `/cron` | cron 子命令 | cron human | `--json` | add/update/wake/error/run 已整改 |
| Telegram | `/help`、`/status`、`/activation`、`/pair` | 无 | `renderTelegramNativeHumanReply` | 无 | `/help` 等直接发送 JSON 已整改 |
| Telegram | `/commands`、`/tools`、`/whoami`、`/context`、`/tasks` | 无 | human renderer | 无 | OK |
| Telegram | `/allowlist` | `list`、`dm`、`group` | human summary | 无 | 数组 raw JSON 已改摘要 |
| Telegram | `/approve` | `<id> <decision>` | human/approval diagnostic | 无 | OK |
| Telegram | `/export-session` / `/export` | `[path]` | human export path | 文件内容为导出物 | OK |
| Telegram | `/tts` | `status`、`on`、`off`、`provider`、`limit`、`summary`、`audio`、`help` | human | 无 | OK |
| Telegram | `/session`、`/sessions` | `list`、`path`、`preview` | human | 无 | OK |
| Telegram | `/subagents` | `list`、`kill`、`log/info`、`send`、`steer`、`spawn` | subagents renderer | 无 | OK |
| Telegram | `/acp` | `status`、`sessions`、`doctor`、`help` | not-applicable human | 无 | OK |
| Telegram | `/focus`、`/unfocus`、`/agents` | thread binding | human summary | 无 | bindings raw JSON 已改摘要 |
| Telegram | `/kill`、`/steer` / `/tell` | subagent control | human | 无 | OK |
| Telegram | `/config` | `show`、`get`、`set`、`unset` | show/get human，mutation approval human | 无 | config value raw JSON 已改摘要 |
| Telegram | `/mcp` | `show/get/set/unset` | show/get human，mutation approval human | 无 | mcpServers raw JSON 已改摘要 |
| Telegram | `/plugins` / `/plugin` | `list`、`show`、`enable`、`disable` | human | 无 | OK |
| Telegram | `/debug` | `show`、`set`、`unset`、`reset` | human/approval human | 无 | OK |
| Telegram | `/usage` | `off`、`tokens`、`full`、`cost` | human | 无 | OK |
| Telegram | `/stop`、`/restart`、`/send`、`/reset`、`/new`、`/compact` | session/runtime operations | human | 无 | OK |
| Telegram | `/think` / `/thinking` / `/t` | `off`、`minimal`、`low`、`medium`、`high`、`xhigh` | human | 无 | OK |
| Telegram | `/verbose` / `/v` | `on`、`off` | human | 无 | OK |
| Telegram | `/fast` | `status`、`on`、`off` | human | 无 | OK |
| Telegram | `/reasoning` / `/reason` | `on`、`off`、`stream` | human | 无 | OK |
| Telegram | `/elevated` / `/elev` | `on`、`off`、`ask`、`full` | human | 无 | OK |
| Telegram | `/exec` | `sandbox`、`gateway`、`node` | human | 无 | OK |
| Telegram | `/model`、`/models` | provider/model display | human | 无 | OK |
| Telegram | `/queue` | `steer`、`interrupt`、`followup`、`collect`、`steer-backlog` | human | 无 | OK |
| Telegram | `/bash` | `<command>` | approval human | 无 | OK |
| Telegram | `/skill` | `<name> <input>` | human / skill path | 无 | OK |
| Telegram | `/btw` | `<question>` | not-applicable human | 无 | OK |

## 6. 本轮发现与整改清单

| 问题 | 证据 | 整改 | 验收 |
|---|---|---|---|
| `gateway media image status/set/add-model/remove-model` 默认经 `toJsonString()` 进入 CLI 输出，formatter 之前无法覆盖 mutation | `src/gateway/runtime/gateway_cli.cj:342-378` | 在 `gateway_cli_human_output.cj` 增加 image status/mutation renderer | `GatewayCliHumanOutputTest.formatsImageConfigMutationWithoutRawJson` |
| `gateway call <method>` 对未知 RPC 成功结果默认可能裸 JSON | `src/gateway/runtime/gateway_cli.cj:427-439` | 默认走 `gatewayPrintCommandOutput`，并新增 `gateway call --json` 机器输出 | `GatewayCliHumanOutputTest.formatsGenericRpcSuccessWithoutRawJson` |
| `mcp show` 默认打印完整配置 JSON | `src/program/cli_local_flows.cj:968-987` | 默认 human 摘要，`show --json` 才输出 JSON | `CliLocalFlowsMcpTest` |
| `cron add/update/wake/error/run` 默认返回 JSON 字符串 | `src/cron/cron_command.cj:55-123` 与 runtime hook | 默认 human，`--json` 显式保留机器输出 | `CronCommandTest.cronAddUpdateWakeAndErrorsDefaultToHumanText` |
| Telegram `/help`、`/status`、`/activation`、`/pair` 早期路径直接发送 JSON command envelope | `src/gateway/core/gateway_service.cj` native command branch | 统一调用 `renderTelegramNativeHumanReply` | 由 Telegram native renderer 测试覆盖，后续可加端到端断言 |
| Telegram renderer 对 allowlist/mcp/thread binding/config value 使用 `toJsonString()` 作为 human 文本 | `src/gateway/core/gateway_service.cj` renderer | 增加 `telegramJsonValueSummary`，数组/对象改为摘要 | human 输出不再暴露嵌套 JSON |
| Channel audit `remaining` 项使用 raw JSON 摘要 | `src/gateway/runtime/gateway_cli_human_output.cj` | 改为 code/status/message 摘要 | formatter 单元测试覆盖无 `{` 约束 |
| `/memory search` 默认打印 tool JSON | `src/cliapp/memory_command.cj` 调用 `MemoryToolset.runCliSearch`，后者默认返回 JSON | `runCliSearch` 增加 `json` 参数，CLI 默认传 `false` 并渲染 human；工具/测试默认仍保留结构化 JSON | `MemoryToolsetTest.cliSearchCanRenderHumanTextWithoutRawJson` |
| `/memory dreaming status` 默认打印 `buildStatusJson()` | `src/cliapp/memory_command.cj` dreaming status 分支 | 增加 `DreamingPhaseRuntime.buildStatusText()`，默认 human；`--json` 才输出 JSON | `DreamingPhaseRuntimeTest.statusTextIsHumanReadableAndJsonStaysExplicit` |

## 7. 后续红线

任何新增命令必须先回答三个问题：

1. 默认输出是否面向人类？如果是，不允许 `PrintUtils.printLine(x.toJsonString())`。
2. 是否需要机器输出？如果需要，只能显式加 `--json` 或导出类命令。
3. 是否已有测试断言默认输出不包含原始 JSON 键？没有测试不允许合入。
