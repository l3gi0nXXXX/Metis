# Metis Agent Team Series 24: 手工测试项总清单

日期：2026-05-17

本文只整理 Agent Team 当前需要手工测试的项目，不新增功能设计，不修改代码。清单覆盖 CLI、Gateway RPC、Control UI、Telegram、Feishu、QQ channel account、证据包和发布前回归。

## 1. 来源依据

| 来源 | 事实 |
| --- | --- |
| `docs/user/agent-team.md:27-45` | Agent 和 AgentTeam 管理必须先启动 Gateway，并通过 `metis gateway status`、`metis gateway health` 检查。 |
| `docs/user/agent-team.md:48-58` | 用户入口包括 CLI、Telegram、Feishu、Control UI；Telegram/Feishu live 验收是 opt-in。 |
| `docs/user/agent-team.md:75-194` | `metis agents add` 创建单 agent，支持一命令配置 Telegram/Feishu/QQ 凭证，并要求输出脱敏、冲突不半写。 |
| `docs/user/agent-team.md:196-237` | `metis agents team create/list/get/update/delete` 管理 team，删除 team 不删除 member agent 目录。 |
| `docs/user/agent-team.md:239-273` | Control UI 的 Teams 页面支持 team CRUD、member/alias、broadcast、binding preview/apply、profile files、model state、Feishu readiness/doctor。 |
| `docs/user/agent-team.md:275-349` | 每个 agent 支持隔离的 profile files、`models.json`、credential source summary；profile file 只能走 `agents.files.*`。 |
| `docs/user/agent-team.md:351-424` | `metis agents bind/unbind` 支持简单 channel/account binding；broadcast 通过 team update/RPC 配置并返回 aggregate。 |
| `docs/user/agent-team.md:426-526` | Feishu 需要人工创建 app/bot；Metis 提供 status、OAuth/OAPI、CardKit、rich event、resource 相关验收入口。 |
| `docs/user/agent-team.md:528-549` | `metis agents migrate --dry-run` 是只读迁移预览，不能静默改写配置。 |
| `docs/user/agent-team.md:567-613` | manual acceptance gate 必须使用隔离 `METIS_HOME`，生成 redacted evidence pack，并可选择启用 browser smoke 和 live IM gate。 |
| `src/program/cli_local_flows.cj:436-591` | `agents add` 参数解析包含 `--bind`、`--feishu`、`--qqbot`、`--telegram-bot-token`、显式 account、`--channel-overwrite`。 |
| `src/program/cli_local_flows.cj:712-760` | `agents team` 支持 `list/get/create/update/delete`、`--member`、`--alias`、`--bind`。 |
| `src/program/cli_local_flows.cj:971-1039` | `agents add` 和 `agents team` 默认输出是人类可读；只有 `--json` 才输出 JSON。 |
| `src/program/cli_local_flows.cj:2193-2217` | `metis agents` help 暴露当前用户可用的 agent/team/bind/migrate/add/set-identity/delete 子命令。 |
| `src/gateway/runtime/gateway_server_methods_agents.cj:3421-3626` | Gateway agents family 暴露 `agents.*`、`agents.files.*`、`agents.models.*`、`agents.teams.*`、`agents.migration.dryRun`。 |
| `ui/src/ui/navigation.ts:5-43` | Control UI 有独立 `agentTeams` tab，路径为 `/agent-teams`。 |
| `ui/src/ui/views/agents-panel-teams.ts:71-99` | Teams panel 接收 team CRUD、binding、model、workspace、Feishu auth 等回调。 |

## 2. 执行分层

| 层级 | 是否必须 | 目的 | 是否需要真实外部资源 |
| --- | --- | --- | --- |
| L0 本地安全门禁 | 必须 | 确认不会污染真实 `~/.metis`，生成证据包 | 否 |
| L1 CLI/Gateway 本地验收 | 必须 | 验证 agent/team/config/binding/model/profile 的基本行为 | 否 |
| L2 Control UI 浏览器验收 | 必须 | 验证网页真实可打开、可操作、可通过 Gateway RPC 写入 | 否，但需要本地 Gateway/UI |
| L3 Telegram live 验收 | 条件必须 | 验证真实 Telegram bot 的 route、group/topic、broadcast | 是，测试 bot 和测试 chat/group/topic |
| L4 Feishu live 验收 | 条件必须 | 验证真实 Feishu app/bot、OAuth/OAPI、CardKit、rich event | 是，测试 tenant/app/bot/user/resource |
| L5 发布门禁 | 必须 | 完整 clean/build/test、UI build、证据包归档 | 否，live 项可记录 skipped/external-resource-required |

如果没有真实 Telegram 或 Feishu 测试资源，L3/L4 不允许假装通过，只能记录为 `skipped` 或 `external-resource-required`。

## 3. 通用准备

执行所有手工测试前，在**当前终端窗口**复制执行下面整段命令。这里的 `export METIS_HOME=...` 就是把 Metis 的测试 home 目录指定到 `/tmp/metis-agentteam-manual-acceptance`；这个设置只对当前终端窗口和它启动的子进程有效，关闭终端或换一个终端窗口后需要重新执行。

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"
```

说明：

- `source /Users/l3gi0n/cangjie100/envsetup.sh` 是 Cangjie SDK 环境初始化，应该使用 `source`，因为它需要把 SDK 环境变量加载到当前 shell。
- `export METIS_HOME="..."` 是告诉 Metis 本轮测试使用临时目录，避免写真实 `~/.metis`。
- `export METIS_AGENTTEAM_REPORT_DIR="..."` 是告诉 evidence pack 写到哪里。
- 这些 `export` 不是永久配置，只影响当前终端窗口。

启动 Gateway：

```bash
cjpm run --skip-build --name metis --run-args "gateway run"
```

另开 shell 检查 Gateway：

```bash
metis gateway status
metis gateway health
```

基础证据包：

`scripts/agentteam-manual-acceptance-gate.sh` 不是一条业务功能测试命令，它是“验收前置检查 + 脱敏证据目录生成脚本”。它会检查 `METIS_HOME` 是否安全、检查文档/矩阵是否存在、执行 `git diff --check`，并把验收记录文件写到 `METIS_AGENTTEAM_REPORT_DIR` 指定的目录。按本文的准备命令，目录就是：

```text
/tmp/metis-agentteam-manual-acceptance-report
```

脚本会在这个目录下写两个文件：

```text
/tmp/metis-agentteam-manual-acceptance-report/report.json
/tmp/metis-agentteam-manual-acceptance-report/manual-acceptance-template.md
```

脚本内部使用 `exit` 返回成功或失败状态，所以**绝对不要用 `source scripts/agentteam-manual-acceptance-gate.sh` 或 `. scripts/agentteam-manual-acceptance-gate.sh` 执行**，否则失败时会退出当前 shell。

脚本内部会禁用交互式 pager：`GIT_PAGER=cat`、`PAGER=cat`、`LESS=-F -X`。因此，正确执行时不应该进入 `less`，也不应该需要按 `q` 才能回到 shell。如果你看到 `less` 页面或需要按 `q`，这不是验收步骤，而是脚本缺陷，需要先修脚本。

正确执行方式：

```bash
bash scripts/agentteam-manual-acceptance-gate.sh
```

如果要直接执行，也必须作为独立进程运行：

```bash
./scripts/agentteam-manual-acceptance-gate.sh
```

错误执行方式：

```bash
source scripts/agentteam-manual-acceptance-gate.sh
. scripts/agentteam-manual-acceptance-gate.sh
```

通用验收标准：

- 不使用真实 `~/.metis`。
- 不使用生产 bot、生产 tenant、生产群、生产用户、生产文件。
- 不记录 bot token、appSecret、access token、refresh token、Authorization header、proxy password、provider API key。
- 失败项必须记录原始操作、预期、实际结果、脱敏日志路径。

## 4. L0 本地安全门禁

### L0-01 隔离 home

目的：确认本轮手工验收使用临时目录，不写真实 `~/.metis`。

执行命令：

```bash
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"
bash scripts/agentteam-manual-acceptance-gate.sh
```

通过标准：

- 命令执行后没有退出当前 shell。
- 命令执行过程中不进入 `less`，不需要按 `q` 退出。
- 输出里出现临时 `METIS_HOME`，路径是 `/tmp/metis-agentteam-manual-acceptance`。
- 输出里出现：

```text
[agentteam-gate] manual acceptance gate completed
[agentteam-gate] report JSON: /tmp/metis-agentteam-manual-acceptance-report/report.json
[agentteam-gate] manual template: /tmp/metis-agentteam-manual-acceptance-report/manual-acceptance-template.md
```

- 输出里没有提示正在使用真实 `~/.metis`。

### L0-02 真实 home 拦截

目的：确认脚本会拒绝真实 `~/.metis`，防止手工测试污染真实配置。

执行命令：

```bash
export METIS_HOME="$HOME/.metis"
bash scripts/agentteam-manual-acceptance-gate.sh
```

通过标准：

- 命令必须失败。
- 终端里必须出现类似“`METIS_HOME points at the real home`”或“Use an isolated test home”的错误。
- 当前 shell 不退出。

完成后恢复临时目录：

```bash
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"
```

### L0-03 evidence pack 文件生成

目的：确认 gate 把验收记录文件写到了你能找到的目录。

执行命令：

```bash
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"
bash scripts/agentteam-manual-acceptance-gate.sh

REPORT_DIR="${METIS_AGENTTEAM_REPORT_DIR:-$METIS_HOME/agentteam-manual-acceptance-report}"
echo "REPORT_DIR=$REPORT_DIR"
ls -l "$REPORT_DIR/report.json" "$REPORT_DIR/manual-acceptance-template.md"
sed -n '1,40p' "$REPORT_DIR/manual-acceptance-template.md"
```

你要检查的目录就是 `echo "REPORT_DIR=$REPORT_DIR"` 打印出来的目录。按上面的命令，应为：

```text
/tmp/metis-agentteam-manual-acceptance-report
```

通过标准：

- 终端输出中有 `REPORT_DIR=/tmp/metis-agentteam-manual-acceptance-report`。
- `ls -l` 能列出两个文件：
  - `report.json`
  - `manual-acceptance-template.md`
- `sed -n '1,40p' ...` 能显示 `manual-acceptance-template.md` 的前 40 行。
- 如果 `ls` 报 `No such file or directory`，说明 gate 没有成功生成 evidence pack，需要先看 gate 前面的错误输出。

### L0-04 evidence pack 脱敏检查

目的：确认 `report.json` 和 `manual-acceptance-template.md` 里没有误写入 token、appSecret、access token、Authorization header 等敏感内容。

先执行这段命令，确认两个文件存在，并查看 `report.json` 里的脱敏检查字段：

```bash
REPORT_DIR="${METIS_AGENTTEAM_REPORT_DIR:-/tmp/metis-agentteam-manual-acceptance-report}"
ls "$REPORT_DIR/report.json" "$REPORT_DIR/manual-acceptance-template.md"
rg -n '"redactionScan"|"rawSensitiveValuesRecorded"|"forbiddenIdentifiersAbsent"' "$REPORT_DIR/report.json"
```

通过标准：

- `ls` 能看到这两个文件：
  - `report.json`
  - `manual-acceptance-template.md`
- `rg` 能看到 `redactionScan` 相关字段。
- `rawSensitiveValuesRecorded` 应为 `false`。
- `forbiddenIdentifiersAbsent` 应为 `true`。

再执行这段命令，扫描 evidence pack 是否包含敏感内容：

```bash
rg -n -i 'appSecret|accessToken|refreshToken|Authorization|bot[ _-]?token|bearer[[:space:]]+|sk-[A-Za-z0-9_-]{16,}|[0-9]{5,}:[A-Za-z0-9_-]{20,}' "$REPORT_DIR" \
  && echo "FAIL: evidence pack contains sensitive-looking text" \
  || echo "PASS: no sensitive-looking text found"
```

通过标准：

- 正常情况应输出 `PASS: no sensitive-looking text found`。
- 如果输出 `FAIL`，说明下面两个文件里可能写入了敏感值，需要删除敏感值后重新运行 L0-03：

```text
/tmp/metis-agentteam-manual-acceptance-report/report.json
/tmp/metis-agentteam-manual-acceptance-report/manual-acceptance-template.md
```

### L0-05 live gate 默认状态

目的：确认不提供真实 Telegram/Feishu 测试资源时，脚本不会把 live 项伪装成通过。

执行命令：

```bash
unset METIS_AGENTTEAM_LIVE_TELEGRAM
unset METIS_AGENTTEAM_LIVE_FEISHU
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"
bash scripts/agentteam-manual-acceptance-gate.sh

REPORT_DIR="${METIS_AGENTTEAM_REPORT_DIR:-/tmp/metis-agentteam-manual-acceptance-report}"
rg -n '"phase1"|"phase2"|"phase3"|"skipped"|"external-resource-required"|"operator-record-required"' "$REPORT_DIR/report.json"
```

通过标准：

- `report.json` 里 Telegram/Feishu live 相关 phase 不能是 `local-pass`。
- live 项只能显示 `skipped`、`external-resource-required` 或 `operator-record-required`。

## 5. L1 CLI/Gateway 本地验收

### 5.1 Agent 基础生命周期

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| L1-01 | agent 创建 | `metis agents add --agent manual-reviewer --name "Reviewer" --model dashscope:qwen3.6-plus` | 创建成功；默认输出不是大 JSON；显示 workspace/agentDir/sessionsDir 或等价摘要；不要使用 `reviewer`，因为它是内置 agent ID，不是自定义 agent ID | stdout |
| L1-02 | agent 查询（OpenClaw 对齐） | `metis agents list`，再执行 `metis agents bindings --agent manual-reviewer` | `agents list` 能在 Custom 区看到 `manual-reviewer`；默认输出是人类可读文本，不是裸 JSON；`agents bindings --agent manual-reviewer` 能查询该 agent 的路由绑定或明确提示无绑定 | stdout |
| L1-03 | agent 列表 | `metis agents list` 和 `metis agents summary` | 人类可读；能看到 custom agent 数量变化 | stdout |
| L1-04 | agent 健康 | `metis agents health` | 返回人类可读健康摘要；无 Gateway 401/500 | stdout |
| L1-05 | agent 能力 | `metis agents capabilities` | 展示 capabilities 行，不是裸 JSON | stdout |
| L1-06 | identity 修改 | `metis agents set-identity --agent manual-reviewer --name "Reviewer V2" --theme "review"`，再执行 `metis agents list` | `manual-reviewer` 仍存在；identity 更新；不影响其他 agent | stdout |
| L1-07 | agent 删除 | `metis agents delete --agent manual-reviewer`，再执行 `metis agents list` | `manual-reviewer` 不再出现在 Custom 区；删除行为不影响其他 agent | stdout |

### 5.2 单 agent 一命令配置 IM 凭证

以下示例只能使用测试假值或测试资源。即使使用假值，也要验收配置落点、binding、输出脱敏、失败原子性。

本节和后续 live 项中，凡执行 `metis gateway channel get telegram`、`metis gateway channel get feishu` 或 `metis gateway channel get qq`，通过标准都是查看 configured account 摘要：输出必须包含 `Accounts` 段、具体 `<channel>/<accountId>`、default 标记、`binding=<channel>:<accountId>`，并且 token/appSecret 等 secret 只显示脱敏值。`metis gateway channel get <id>` 不是 live runtime 检查；`metis gateway channel runtime <id>` 只表示 live adapter runtime 状态，不是全部配置账号列表。不能只用通道级 `configured=true` 判定某个 bot/account 配置正确。

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| L1-08 | 只创建单 agent 不建 team | `metis agents add --agent solo --name "Solo" --model dashscope:qwen3.6-plus` | `metis agents team list` 不新增 team；`metis agents bindings --agent solo` 为空或明确无 binding | stdout |
| L1-09 | Telegram shortcut | `metis agents add --agent tg-writer --telegram-bot-token "123456789:fake-telegram-token"`，再执行 `metis agents bindings --agent tg-writer` 和 `metis gateway channel get telegram` | `agents add` 输出包含 `Configured channel accounts` 且显示 `telegram/tg-writer`；存在 `telegram:tg-writer` binding；`gateway channel get telegram` 输出包含 `Accounts` 段、`telegram/tg-writer`、default 标记、`binding=telegram:tg-writer`；token 脱敏且 stdout/stderr 不出现 raw token | stdout、logs |
| L1-10 | Feishu shortcut | `metis agents add --agent feishu-writer --feishu "cli_fake_app_id:fake-feishu-secret"`，再执行 `metis agents bindings --agent feishu-writer` 和 `metis gateway channel get feishu` | `agents add` 输出包含 `Configured channel accounts` 且显示 `feishu/feishu-writer`；存在 `feishu:feishu-writer` binding；`gateway channel get feishu` 输出包含 `Accounts` 段、`feishu/feishu-writer`、default 标记、`binding=feishu:feishu-writer`；appSecret 脱敏 | stdout、logs |
| L1-11 | QQ shortcut | `metis agents add --agent qq-writer --qqbot "1020000000:fake-qq-secret"`，再执行 `metis agents bindings --agent qq-writer` 和 `metis gateway channel get qq` | `agents add` 输出包含 `Configured channel accounts` 且显示 `qq/qq-writer`；存在 `qq:qq-writer` binding；`gateway channel get qq` 输出包含 `Accounts` 段、`qq/qq-writer`、default 标记、`binding=qq:qq-writer`；appSecret 脱敏；不破坏旧顶层 QQ 配置兼容 | stdout、logs |
| L1-12 | 三渠道 shortcut | 一条 `metis agents add --agent zhihu-strategist --feishu ... --qqbot ... --telegram-bot-token ...`，再执行 `metis agents bindings --agent zhihu-strategist`、`metis gateway channel get telegram`、`metis gateway channel get feishu`、`metis gateway channel get qq` | `agents add` 输出包含三个脱敏的 `Configured channel accounts` 行；存在三条 binding；三个 `gateway channel get <id>` 输出均包含 `Accounts` 段、对应 `telegram/zhihu-strategist`、`feishu/zhihu-strategist`、`qq/zhihu-strategist` accountId、default 标记和 `binding=<channel>:zhihu-strategist`；输出不含 raw secret | stdout、bindings 输出、channel get 输出 |
| L1-13 | 显式 accountId | `metis agents add --agent support-router --telegram-account support-test-bot --telegram-bot-token "123456789:fake-telegram-token"` | accountId 是 `support-test-bot`，不是 agentId；binding 为 `telegram:support-test-bot -> support-router` | stdout |
| L1-14 | 显式 `--bind` 去重 | `metis agents add --agent dedupe-demo --bind telegram:dedupe-demo --telegram-bot-token "123456789:fake-telegram-token"` | 只有一条 `telegram:dedupe-demo` binding | bindings 输出 |
| L1-15 | `--telegram` alias | `metis agents add --agent tg-alias --telegram "123456789:fake-telegram-token"` | 行为等价于 `--telegram-bot-token` | stdout |
| L1-16 | Telegram 双 flag 冲突 | 同时传 `--telegram token-a --telegram-bot-token token-b`，再执行 `metis agents list` 和 `metis agents bindings --agent <id>` | 命令失败；提示两个 token 不一致；`agents list` 不出现该 agent；`agents bindings --agent <id>` 无新增绑定 | stderr、stdout |
| L1-17 | 已存在相同 account/credential | 重复创建使用相同 account 和相同 fake credential 的 agent，或按现有语义复用 | 不写重复 account；结果清晰；不泄露 secret | stdout |
| L1-18 | 已存在不同 credential 默认失败 | 使用已有 accountId 但传不同 secret，不带 `--channel-overwrite` | 命令失败；新 agent 不存在；原 account/binding 不变；错误脱敏 | stderr、查询输出 |
| L1-19 | `--channel-overwrite` | 使用已有 accountId，传不同 secret 并加 `--channel-overwrite` | 如果无 route owner 冲突则覆盖成功；若有 binding 冲突则失败且不半写；secret 脱敏 | stdout/stderr |
| L1-20 | `--json` 脱敏 | 任一 shortcut 加 `--json` | JSON 中包含 agent/account 摘要，但不包含 raw token/appSecret；默认输出仍不是 JSON | JSON 输出 |

### 5.3 Binding 与迁移

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| L1-21 | 简单 bind | `metis agents bind --agent solo --bind telegram:bot-a` | 新增 binding；默认输出人类可读 Added/Skipped/Conflicts 摘要 | stdout |
| L1-22 | 多 bind | `metis agents bind --agent solo --bind telegram:bot-a --bind feishu:tenant-a` | 两条 binding 均处理；重复项 skipped，不重复写 | stdout |
| L1-23 | unbind 单条 | `metis agents unbind --agent solo --bind telegram:bot-a` | 指定 binding 移除，其他 binding 保留 | bindings 输出 |
| L1-24 | unbind all | `metis agents unbind --agent solo --all` | 该 agent 的 route binding 清空 | bindings 输出 |
| L1-25 | binding 冲突 | 将同一 `channel:account` 绑定给两个不同 agent | 第二次必须失败或报告 conflict；不能覆盖旧 owner | stdout/stderr |
| L1-26 | migration dry-run | `metis agents migrate --dry-run` | 只读输出；默认不是裸 JSON；不改配置 | stdout、mtime 或后续查询 |
| L1-27 | migration config-file | `metis agents migrate --dry-run --config ./legacy-metis.json --json` | 读取指定文件做预览；不改 active config；输出 secret 脱敏 | JSON 输出 |
| L1-28 | proposed binding dry-run | `metis agents migrate --dry-run --binding-json '{"type":"route","agentId":"solo","match":{"channel":"telegram","accountId":"bot-a"}}'` | 展示 binding apply preview；不真实写入 | stdout/JSON |

### 5.4 Agent profile files 和 model 隔离

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| L1-29 | profile file list | `metis gateway call agents.files.list '{"agentId":"solo"}'` | 返回支持的 `AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`、`MEMORY.md`；`BOOTSTRAP.md` 可为 missing | RPC 输出 |
| L1-30 | profile file set/get | 写入 `SOUL.md` 后读取 | 读回内容一致；只影响该 agent | RPC 输出 |
| L1-31 | profile path traversal 防护 | 尝试 `../x`、绝对路径、`~`、URI scheme | 必须拒绝；不写临时目录外文件 | RPC 错误、文件检查 |
| L1-32 | 双 agent 文件隔离 | 给 `solo` 和 `reviewer2` 写不同 `SOUL.md` | 两边读回内容不同；互不串读 | RPC 输出 |
| L1-33 | model get | `metis gateway call agents.models.get '{"agentId":"solo"}'` | 返回 agent-scoped model state 和 credentialSource summary；secret 脱敏 | RPC 输出 |
| L1-34 | model set | 对 `solo` 写 `primaryModelRef`，再对另一 agent 写不同模型 | 两个 agent 的 `models.json` 独立 | RPC 输出 |
| L1-35 | invalid model state | 写入结构错误的 model state | Gateway 返回清晰错误；旧 model state 不被破坏 | RPC 输出 |
| L1-36 | credential source 隔离 | 检查 agent-local/global/env fallback summary | 不把其他 agent 的 auth profile 当成当前 agent 凭证来源 | RPC 输出 |

### 5.5 Team 生命周期

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| L1-37 | template team create | `metis agents team create --team content --name "Content Team" --template pm-writer-reviewer` | 创建 team；自动存在 `content-pm/content-writer/content-reviewer` member agent | stdout、list/get |
| L1-38 | team list | `metis agents team list` | 默认输出人类可读；能看到 `content` | stdout |
| L1-39 | team get | `metis agents team get --team content` | 能看到 members、defaultAgentId、semantics | stdout |
| L1-40 | team update name | `metis agents team update --team content --name "Content Ops Team"` | displayName 更新 | stdout/get |
| L1-41 | explicit members | `metis agents team create --team support --member support-triage:triage:"Support Triage" --member support-reply:reply:"Support Reply"` | 创建 explicit members；必要 member agent 自动创建 | stdout/get |
| L1-42 | aliases | `metis agents team update --team support --alias "@triage=support-triage" --alias "/agent reply=support-reply"` | aliases 保存；不完整 alias row 被拒绝或清理 | get 输出 |
| L1-43 | default member | 通过 CLI/RPC 设置 default member | 默认成员存在于 members；非法 default member 被拒绝 | get 输出 |
| L1-44 | team-level binding | `metis agents team update --team support --bind telegram:support-bot` | binding 编译到全局 route bindings；冲突时不半写 | bindings 输出 |
| L1-45 | structured binding | 用 `metis gateway call agents.teams.update` 写 peer/thread/team/role match JSON | Gateway 接受合法结构；非法结构返回清晰错误 | RPC 输出 |
| L1-46 | team binding conflict | team binding 与已有 agent binding 冲突 | team update/create 被拒绝；team 和 bindings 不半写 | RPC 输出、bindings |
| L1-47 | broadcast enable | `metis gateway call agents.teams.update '{"id":"content","broadcast":{"enabled":true,"members":["content-writer","content-reviewer"]}}'` | broadcast 持久化；members 去重；未知 member 被过滤或拒绝 | get 输出 |
| L1-48 | broadcast disable | 设置 `broadcast.enabled=false` | Gateway 回到单 route 语义 | get 输出 |
| L1-49 | team delete | `metis agents team delete --team content`，再执行 `metis agents team list` 和 `metis agents list` | 删除 team entry；member agent 仍可在 agent 列表中看到；member workspace/agentDir 不被删除 | stdout |
| L1-50 | team JSON 输出 | team create/list/get/update/delete 分别加 `--json` | JSON 正确；无 secret；默认输出仍人类可读 | JSON/stdout |

## 6. L2 Control UI 浏览器验收

Control UI 需要真实浏览器验收，不能只看 `npm run build`。当前代码有独立 `/agent-teams` 路径，也可以从 Agent 分组进入 Agent Teams/Teams 面板。

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| U-01 | UI build | `npm --prefix ui run build` | build 成功 | 终端输出 |
| U-02 | 浏览器打开 | 启动 Gateway UI，打开 Control UI | 页面不是空白；`customElements.get("metis-app")` 已注册；JS/CSS 无 404 | 浏览器截图、console |
| U-03 | Agent Teams 入口 | 打开 `/agent-teams` 或从 Agent 分组进入 Agent Teams/Teams | 能看到 Agent Team Management 页面 | 截图 |
| U-04 | UI team create | 在页面创建 template-backed team | 创建成功；刷新后仍存在 | 截图、Gateway get |
| U-05 | UI custom members | 添加/编辑 members 的 agentId、role、displayName | 保存成功；空行/不完整行不污染配置 | 截图、get |
| U-06 | UI aliases | 添加 `@writer`、`/agent review` alias | 保存成功；刷新后仍存在 | 截图、get |
| U-07 | UI broadcast | 打开 broadcast，选择成员 | 保存成功；重复/未知成员不会进入最终 selected members | 截图、get |
| U-08 | UI binding preview/apply | 预览 `telegram:bot-a` 和 structured JSON binding，再 apply | apply 前能看到 preview/conflict；apply 后 Gateway bindings 更新 | 截图、bindings |
| U-09 | UI profile files | 从 Teams 页面加载、编辑、保存 `SOUL.md` 或 `MEMORY.md` | 通过 Gateway RPC 保存；刷新后内容仍在；不能写非法文件名 | 截图、RPC 输出 |
| U-10 | UI model state | 加载并保存 selected member 的 model JSON | 只影响该 member；secret-like 字段脱敏 | 截图、RPC 输出 |
| U-11 | UI Feishu setup/doctor | 查看 Feishu setup/repair/auth/doctor panels | 页面明确“链接已有 Feishu app/bot”；不声称自动创建 app/bot；secret 脱敏 | 截图 |
| U-12 | UI readiness/evidence command | 查看 Manual acceptance/evidence pack 面板 | 显示 local/external/operator 分类和 evidence command | 截图 |
| U-13 | UI 错误处理 | 故意制造 Gateway RPC 错误，如 binding conflict | 页面显示清晰错误；不吞错；不泄露 secret | 截图、console |

启用 browser smoke 的 gate：在当前终端先执行 `export METIS_AGENTTEAM_CONTROL_UI_URL=...`，再执行 `bash scripts/agentteam-manual-acceptance-gate.sh`。

```bash
export METIS_AGENTTEAM_CONTROL_UI_URL="http://127.0.0.1:<port>/"
bash scripts/agentteam-manual-acceptance-gate.sh
```

## 7. L3 Telegram live 验收

前置资源：

- 测试 Telegram bot token。
- 测试私聊 chat id。
- 测试 group id。
- 如果验收 topic，需要测试 topic id。
- 不使用生产 bot，不记录 token。

启用 Telegram live gate：在当前终端复制执行下面这些 `export` 命令后，再执行 `bash scripts/agentteam-manual-acceptance-gate.sh`。

```bash
export METIS_AGENTTEAM_LIVE_TELEGRAM=1
export METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID="test-bot-account"
export METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID="redacted-test-chat"
export METIS_AGENTTEAM_TELEGRAM_TEST_GROUP_ID="redacted-test-group"
export METIS_AGENTTEAM_TELEGRAM_TEST_TOPIC_ID="redacted-test-topic"
bash scripts/agentteam-manual-acceptance-gate.sh
```

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| T-01 | Telegram account configured | 用 `metis agents add --agent tg-live --telegram-account test-bot-account --telegram-bot-token "$TEST_TOKEN"` 配置测试 bot，再执行 `metis agents bindings --agent tg-live` 和 `metis gateway channel get telegram` | `agents add` 输出包含脱敏的 `telegram/test-bot-account` account 摘要；binding 指向 `telegram:test-bot-account`；`gateway channel get telegram` 输出包含 `Accounts` 段、`telegram/test-bot-account`、default 标记、`binding=telegram:test-bot-account`；token 不在输出和日志中明文出现 | add 输出、bindings 输出、channel get 输出、日志 |
| T-02 | 私聊 route | 给测试 bot 私聊发送文本 | Gateway 日志有 `Gateway.inbound: channel=telegram`；route 到预期 agent；Telegram 收到回复 | 脱敏日志、截图 |
| T-03 | group route | 在测试群发送消息或 mention | group route 命中预期 agent；不该响应的消息不响应 | 脱敏日志、截图 |
| T-04 | topic session 隔离 | 在不同 topic 发送消息 | session key 区分 topic；上下文不串 | 脱敏日志 |
| T-05 | alias route | 配置 team alias 后用 `/agent writer` 或 `@writer` 触发 | alias 命中对应 member agent | 脱敏日志、截图 |
| T-06 | broadcast | 给启用 broadcast 的 team 发送消息 | aggregate 包含 selected member rows；每个 member 有独立 status/sessionKey；失败 member 有清晰 detail | 脱敏 aggregate |
| T-07 | 错误回复 | 模型/API 出错时发送 Telegram 图片或文本 | 用户仍收到错误回复，不出现“无回复”；错误信息脱敏 | 截图、日志 |

## 8. L4 Feishu live 验收

前置资源：

- 两个测试 Feishu app/bot/account，或一个 app 的两个测试 accountId 配置。
- 测试群、测试话题/thread、测试用户。
- OAuth/OAPI 所需测试 scope。
- 低风险测试资源：doc、wiki、calendar、task、bitable、sheet、message。
- CardKit 测试 chat。
- rich event 测试消息。

Metis 不自动创建 Feishu app/bot。app/bot、事件订阅、权限、发布/安装由 operator 在飞书开发者后台完成。

启用 Feishu live gate：在当前终端复制执行下面这些 `export` 命令后，再执行 `bash scripts/agentteam-manual-acceptance-gate.sh`。

```bash
export METIS_AGENTTEAM_LIVE_FEISHU=1
export METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_A="tenant-a"
export METIS_AGENTTEAM_FEISHU_ACCOUNT_ID_B="tenant-b"
export METIS_AGENTTEAM_FEISHU_TEST_GROUP_ID="redacted-group"
export METIS_AGENTTEAM_FEISHU_TEST_THREAD_ID="redacted-thread"
bash scripts/agentteam-manual-acceptance-gate.sh
```

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| F-01 | Feishu account configured | 用测试 appId/appSecret 配置 account，或用 `metis agents add --agent feishu-live --feishu-account tenant-a --feishu ...` 创建 agent/account，再执行 `metis gateway channel get feishu` | `gateway channel get feishu` 输出包含 `Accounts` 段、`feishu/<accountId>`、default 标记、`binding=feishu:<accountId>`；appSecret 脱敏；如果通过 `agents add` 创建，还要用 `metis agents bindings --agent feishu-live` 验证 route binding | channel get 输出、bindings 输出 |
| F-02 | 两账号 route | 分别从 account A/B 触发 inbound | route 到不同 agent/team；accountId 不串 | 脱敏日志 |
| F-03 | group allow/mention gate | 在测试群测试 mention 和非 mention | 符合 group policy；不该响应时不响应 | 截图、日志 |
| F-04 | thread session | 在测试 thread/topic 中发消息 | session 按 thread 隔离 | 日志 |
| F-05 | `/feishu start` | 在 Feishu 测试会话输入 `/feishu start` | 返回启动/状态信息；无 appSecret/token | 截图 |
| F-06 | `/feishu doctor` | 输入 `/feishu doctor` | 返回配置、事件、scope、OAuth/OAPI/CardKit 诊断；无 secret | 截图 |
| F-07 | `/feishu auth` | 输入 `/feishu auth` | 返回安全 auth 引导或状态；不显示 access/refresh token | 截图 |
| F-08 | `/feishu info --all` | 输入 `/feishu info --all` | 返回 account/status/capabilities 概览；脱敏 | 截图 |
| F-09 | OAuth live smoke skipped | 不设置 `METIS_FEISHU_LIVE_AUTH_SMOKE=1` 调用 `channels.feishu.auth.liveSmoke` | 返回 skipped，并写 redacted report | report |
| F-10 | OAuth live smoke real | 设置测试 tenant/env 后调用 liveSmoke | start/status/poll/complete/refresh/revoke 顺序有结果；token 不落入报告 | report |
| F-11 | OAPI smoke plan | 调用 `feishu_oapi_smoke_plan` | 只生成 plan；不查 token、不发网络、不写文件 | tool result |
| F-12 | OAPI read live | 用测试资源执行低风险 read | 成功或返回明确 auth/scope diagnostic；无 secret | 截图/report |
| F-13 | OAPI write live | 对测试资源执行 create/update 并清理 | 成功或明确 diagnostic；只影响测试资源；有 cleanup 记录 | report |
| F-14 | scope repair action | 故意缺 scope 触发工具 | 返回 redacted `repair_action` 和 `merged_scopes`；不直接写 token/appSecret | tool result |
| F-15 | CardKit streaming | 启用 test chat，设置 card/partial streaming | create、patch、final update、abort、fallback 均有可观察结果 | 截图/log |
| F-16 | Card fallback | 模拟/触发 rate limit、message unavailable 或 table limit | 不丢回复，转 text fallback | 截图/log |
| F-17 | rich event text/post/image/file/audio/video/card | 用测试消息触发事件 replay 或真实事件 | Gateway 归一化 inbound；unsupported/malformed 有清晰处理 | 脱敏日志 |
| F-18 | reaction/quote/merge-forward | 对测试消息做 reaction、quote、合并转发 | 事件包含安全 system-event/metadata，不泄露私密原文 | 脱敏日志 |
| F-19 | resource read | 测试当前 turn media metadata 和历史 resource fetch | 默认不下载真实媒体；启用下载时只写临时 cache；auth/scope 错误清晰 | report |
| F-20 | Feishu app/bot 平台边界 | 检查 UI 和文档提示 | 明确 Metis 不能自动创建 Feishu app/bot，只能指导链接已有 app/bot | 截图 |

## 9. QQ channel account 手工验收

QQ 目前主要验收 per-account 配置、兼容旧顶层配置、binding 和脱敏。真实 QQ live 验收只有在有测试 QQ bot 和测试群/用户时执行。

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| Q-01 | QQ account shortcut | `metis agents add --agent qq-live --qqbot "1020000000:fake-qq-secret"`，再执行 `metis agents bindings --agent qq-live` 和 `metis gateway channel get qq` | 写入 `gateway.qq.accounts.qq-live`；binding 存在；`gateway channel get qq` 输出包含 `Accounts` 段、`qq/qq-live`、default 标记、`binding=qq:qq-live`；appSecret 脱敏 | stdout、bindings 输出、channel get 输出 |
| Q-02 | 显式 QQ account | `metis agents add --agent qq-router --qqbot-account qq-test --qqbot "1020000000:fake-qq-secret"`，再执行 `metis agents bindings --agent qq-router` 和 `metis gateway channel get qq` | `agents add` 输出显示 `qq/qq-test`；binding 指向 `qq-router`；`gateway channel get qq` 输出包含 `Accounts` 段、`qq/qq-test`、default 标记、`binding=qq:qq-test`；appSecret 脱敏 | add 输出、bindings 输出、channel get 输出 |
| Q-03 | 旧配置兼容 | 保留旧顶层 QQ 配置并新增 per-account，然后执行 `metis agents bindings --agent <agent>` 和 `metis gateway channel get qq` | 未破坏旧默认 account 解析；新 per-account 在 add 输出和 bindings 输出中可验证；`gateway channel get qq` 输出包含 `Accounts` 段，旧默认 account 和新增 per-account 可区分，default 标记、对应 `binding=qq:<accountId>`、appSecret 脱敏 | add 输出、bindings 输出、channel get 输出 |
| Q-04 | QQ credential conflict | 同 accountId 不同 secret 且不带 overwrite | 失败且不半写；secret 脱敏 | stderr |
| Q-05 | QQ live smoke | 用测试 QQ bot 触发消息 | 如果资源可用，route 到绑定 agent 并回复；否则记录 external-resource-required | 截图/log |

## 10. L5 发布门禁和证据归档

| ID | 手工测试项 | 操作方法 | 验收标准 | 证据 |
| --- | --- | --- | --- | --- |
| R-01 | Cangjie clean/build/test | `cjpm clean && cjpm build -i && cjpm test` | 全部通过；如并发 flake，额外记录 `cjpm test -j 1`，但不能当成功替代真实失败 | 终端输出 |
| R-02 | Focused AgentTeam tests | `cjpm test src/gateway/runtime --filter GatewayServerMethodsAgentsTest --no-color` 等 touched area tests | 通过 | 终端输出 |
| R-03 | UI tests | `npm --prefix ui test` | 通过 | 终端输出 |
| R-04 | UI build | `npm --prefix ui run build` | 通过 | 终端输出 |
| R-05 | manual gate | `bash scripts/agentteam-manual-acceptance-gate.sh`，不要 `source` | 通过并生成 evidence pack；live 项状态真实；当前 shell 不退出 | report |
| R-06 | browser smoke with URL | 在当前终端执行 `export METIS_AGENTTEAM_CONTROL_UI_URL="http://127.0.0.1:<port>/"` 后，再执行 `bash scripts/agentteam-manual-acceptance-gate.sh` | 浏览器 smoke 通过 | report、截图 |
| R-07 | log redaction review | 搜索本轮日志和 evidence pack | 无 raw bot token、appSecret、Authorization、API key、真实 home path | rg 输出 |
| R-08 | git diff check | `git diff --check` | 无 whitespace/error | 输出 |
| R-09 | 文档一致性 | 阅读 `docs/user/agent-team.md` 和本清单 | 不把单 agent shortcut 写成 team 功能；不声称自动创建 Feishu app/bot | 审阅记录 |

## 11. 快速执行顺序

建议按以下顺序做人工验收：

1. L0-01 到 L0-05，确认测试环境安全。
2. L1-01 到 L1-07，确认 agent 基础生命周期。
3. L1-08 到 L1-20，确认一命令 IM credential shortcut。
4. L1-21 到 L1-28，确认 binding 和 migration dry-run。
5. L1-29 到 L1-36，确认 profile/model/credential isolation。
6. L1-37 到 L1-50，确认 team CRUD、alias、binding、broadcast、delete。
7. U-01 到 U-13，确认 Control UI 真实可用。
8. T-01 到 T-07，使用测试 Telegram 资源验收 live route。
9. F-01 到 F-20，使用测试 Feishu 资源验收 live route/OAuth/OAPI/CardKit/rich events。
10. Q-01 到 Q-05，确认 QQ account 配置和可选 live route。
11. R-01 到 R-09，完成发布门禁和证据归档。

## 12. 完成标准

Agent Team 手工测试可以判定完成，必须同时满足：

- L0、L1、L2、L5 全部通过。
- L3/L4/L5 中需要真实外部资源的项目必须有明确状态：`pass`、`skipped`、`external-resource-required` 或 `operator-record-required`，不能空白。
- 所有失败项都有复现步骤、脱敏日志、影响范围和后续修复项。
- 所有输出和证据包都完成 secret redaction。
- 没有任何测试写入真实 `~/.metis` 或生产 IM/Feishu/QQ 资源。
