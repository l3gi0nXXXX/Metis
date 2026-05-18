# Metis Agent Team Series 26: 最新手工测试矩阵

日期：2026-05-18

本文基于 `develop_steps/metis-agent-team-series-24-manual-test-checklist-2026-05-17.md` 的手工测试章节，并结合当前 `main` 分支最新能力重新整理。本文只描述手工验收步骤，不新增设计，不修改代码。

## 1. 当前命令边界

| 项目 | 当前结论 |
| --- | --- |
| 单 agent 创建 | 使用 `metis agents add --agent <id> ...`。支持 `--model`、`--telegram-bot-token`、`--telegram-account`、`--feishu`、`--feishu-account`、`--qqbot`、`--qqbot-account`、`--channel-overwrite`。 |
| 单 agent 修改 | 使用 `metis agents update --agent <id> --model <ref>`，也支持 `--name`、`--workspace`。 |
| 单 agent 查看 | 当前没有 `metis agents get` 命令。查看 agent 应使用 `metis agents list`、`metis agents bindings --agent <id>`、Control UI Agents 页面，或 Gateway RPC。 |
| 内置能力查看 | `metis agents capabilities` 展示内置 agent 能力，不展示手工新增的 custom agent；custom agent 应通过 `metis agents list` 查看。 |
| team CRUD | 使用 `metis agents team list|get|create|update|delete`。 |
| channel 账号查看 | 使用 `metis gateway channel get <telegram|feishu|qq>` 查看配置账号摘要。该命令不支持 `--account`。 |
| channel 指定账号启动 | 使用 `metis gateway channel start|stop|restart <telegram|feishu|qq> --account <accountId>`。 |
| channel runtime | 使用 `metis gateway channel runtime <telegram|feishu|qq>` 查看 live runtime adapter 状态。 |

## 2. 通用前置步骤

所有本地手工测试都必须使用隔离目录。下面命令需要在当前终端执行；如果重新打开终端，需要重新执行。

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"
export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"
```

启动 Gateway 时，必须在同一个 `METIS_HOME` 下启动：

```bash
cjpm run --skip-build --name metis --run-args "gateway run"
```

如果下面矩阵里的命令用 `metis ...` 形式执行失败，可以统一改成：

```bash
cjpm run --skip-build --name metis --run-args "<去掉 metis 前缀后的命令>"
```

例如：

```bash
cjpm run --skip-build --name metis --run-args "agents list"
```

## 3. 手工测试矩阵

| 编号 | 测试项 | 前置条件 | 测试步骤 | 验收标准 | 测试结果记录 |
| --- | --- | --- | --- | --- | --- |
| L0-01 | 隔离 `METIS_HOME` 和 gate 脚本基础运行 | 当前终端已执行通用前置步骤。 | 1. 执行 `echo "$METIS_HOME"`。<br>2. 执行 `bash scripts/agentteam-manual-acceptance-gate.sh`，不要使用 `source`。<br>3. 观察终端输出和当前 shell 是否仍可继续输入命令。 | 1. `METIS_HOME` 必须是 `/tmp/metis-agentteam-manual-acceptance`。<br>2. gate 脚本必须输出 `manual acceptance gate completed`。<br>3. 终端不应进入 `less`，不应需要按 `q`，当前 shell 不应退出。 | 待记录：通过/失败/跳过；记录时间、命令输出摘要、异常现象。 |
| L0-02 | 真实 `~/.metis` 拦截 | 不需要启动 Gateway。 | 1. 执行 `export METIS_HOME="$HOME/.metis"`。<br>2. 执行 `bash scripts/agentteam-manual-acceptance-gate.sh`。<br>3. 执行 `export METIS_HOME="/tmp/metis-agentteam-manual-acceptance"` 恢复隔离目录。 | 1. gate 脚本必须失败。<br>2. 输出必须提示真实 home 被拒绝，或提示必须使用 isolated test home。<br>3. 当前 shell 不应退出。 | 待记录：通过/失败/跳过；记录错误摘要。 |
| L0-03 | evidence pack 生成位置清晰 | 已恢复隔离 `METIS_HOME`。 | 1. 执行 `export METIS_AGENTTEAM_REPORT_DIR="/tmp/metis-agentteam-manual-acceptance-report"`。<br>2. 执行 `bash scripts/agentteam-manual-acceptance-gate.sh`。<br>3. 执行 `ls -l "$METIS_AGENTTEAM_REPORT_DIR/report.json" "$METIS_AGENTTEAM_REPORT_DIR/manual-acceptance-template.md"`。 | 1. 必须生成 `report.json`。<br>2. 必须生成 `manual-acceptance-template.md`。<br>3. 两个文件必须位于 `/tmp/metis-agentteam-manual-acceptance-report`。 | 待记录：通过/失败/跳过；记录 report 目录。 |
| L0-04 | evidence pack 脱敏扫描 | 已完成 L0-03。 | 1. 执行 `rg -n '"redactionScan"|"rawSensitiveValuesRecorded"|"forbiddenIdentifiersAbsent"' "$METIS_AGENTTEAM_REPORT_DIR/report.json"`。<br>2. 执行 `rg -n -i 'appSecret|accessToken|refreshToken|Authorization|bot[ _-]?token|bearer[[:space:]]+|sk-[A-Za-z0-9_-]{16,}|[0-9]{5,}:[A-Za-z0-9_-]{20,}' "$METIS_AGENTTEAM_REPORT_DIR" && echo FAIL || echo PASS`。<br>3. 如果出现 `FAIL`，打开命中的文件，只记录脱敏后的字段名和文件路径，不记录真实敏感值。 | 1. `report.json` 中应能看到脱敏扫描字段。<br>2. `rawSensitiveValuesRecorded` 应为 `false`。<br>3. `forbiddenIdentifiersAbsent` 应为 `true`，敏感词扫描应输出 `PASS`。 | 待记录：通过/失败/跳过；记录命中文件或 PASS。 |
| L0-05 | 当前 CLI 命令边界确认 | 不需要启动 Gateway。 | 1. 执行 `metis agents help`。<br>2. 执行 `metis agents team help`。<br>3. 执行 `metis gateway channel help`。 | 1. `agents help` 必须包含 `add`、`update`、`delete`、`bindings`、`bind`、`unbind`、`team`。<br>2. `agents help` 不应宣称存在 `agents get`。<br>3. `gateway channel help` 必须包含 `start|stop|restart <id> [--account <accountId>]`，且 `get <id>` 不带 `--account`。 | 待记录：通过/失败/跳过；记录实际帮助输出差异。 |
| L1-01 | Gateway 使用隔离 home 启动 | 已执行通用前置步骤。 | 1. 在终端 A 执行 `cjpm run --skip-build --name metis --run-args "gateway run"`。<br>2. 在终端 B 执行同一组通用前置步骤。<br>3. 在终端 B 执行 `metis gateway status` 和 `metis gateway health`。 | 1. Gateway 必须能启动。<br>2. `gateway status` 必须能连接到当前 Gateway。<br>3. `gateway health` 不应因为读取真实 `~/.metis` 失败。 | 待记录：通过/失败/跳过；记录 Gateway 端口、status/health 摘要。 |
| L1-02 | 创建普通 custom agent | Gateway 已启动。 | 1. 执行 `metis agents add --agent manual-reviewer --name "Manual Reviewer" --model dashscope:qwen3.6-plus`。<br>2. 执行 `metis agents list`。<br>3. 执行 `ls -la "$METIS_HOME/agents/manual-reviewer/agent"`。 | 1. `agents add` 默认输出必须是人类可读文本，不应是裸 JSON。<br>2. `agents list` 必须能看到 `manual-reviewer`。<br>3. agent 目录必须存在，并包含 profile/model 相关文件或目录。 | 待记录：通过/失败/跳过；记录输出摘要和 agent 目录路径。 |
| L1-03 | 单 agent 独立模型配置 | `manual-reviewer` 已存在。 | 1. 执行 `metis agents update --agent manual-reviewer --model openai:gpt-4o-mini`。<br>2. 执行 `metis agents list`。<br>3. 执行 `rg -n 'manual-reviewer|openai:gpt-4o-mini' "$METIS_HOME/metis.json" "$METIS_HOME/agents/manual-reviewer/agent/models.json"`。 | 1. `agents update` 默认输出必须是人类可读文本，不应是裸 JSON。<br>2. `agents list` 中 `manual-reviewer` 的模型应体现为 `openai:gpt-4o-mini` 或能通过配置文件确认。<br>3. 如果 `models.json` 是自动生成状态，模型应刷新；如果是手工维护状态，应记录刷新被跳过的原因。 | 待记录：通过/失败/跳过；记录模型配置位置和输出摘要。 |
| L1-04 | 一条命令创建 agent 并配置 Telegram/Feishu/QQ 测试账号 | Gateway 已启动；只使用明显 fake credential，不使用生产密钥。 | 1. 执行 `metis agents add --agent omnichannel-writer --name "Omnichannel Writer" --model dashscope:qwen3.6-plus --telegram-account tg-writer --telegram-bot-token "123456789:test_fake_token_for_manual_acceptance" --feishu-account feishu-writer --feishu "cli_fake_app_id:fake_app_secret" --qqbot-account qq-writer --qqbot "102012345:fake_qq_secret"`。<br>2. 执行 `metis agents bindings --agent omnichannel-writer`。<br>3. 执行 `metis gateway channel get telegram`、`metis gateway channel get feishu`、`metis gateway channel get qq`。 | 1. `agents add` 输出必须包含已配置的 channel account 摘要，并且 secret/token 必须脱敏。<br>2. bindings 必须包含 `telegram:tg-writer`、`feishu:feishu-writer`、`qq:qq-writer`。<br>3. 三个 `gateway channel get` 输出必须是人类可读账号摘要，不应直接打印大段 JSON。 | 待记录：通过/失败/跳过；记录三类账号的脱敏摘要。 |
| L1-05 | 一命令配置的凭证不写入 agent markdown | 已完成 L1-04。 | 1. 执行 `find "$METIS_HOME/agents/omnichannel-writer" -type f -maxdepth 4 -print`。<br>2. 执行 `rg -n 'fake_app_secret|fake_qq_secret|test_fake_token_for_manual_acceptance|Authorization|Bearer' "$METIS_HOME/agents/omnichannel-writer" && echo FAIL || echo PASS`。<br>3. 执行 `rg -n 'tg-writer|feishu-writer|qq-writer' "$METIS_HOME/metis.json"`。 | 1. agent markdown/profile 目录不应出现 bot token、appSecret、Authorization、Bearer。<br>2. 扫描 agent 目录应输出 `PASS`。<br>3. IM 凭证和账号信息应落在 Gateway channel account 配置中，而不是 agent markdown 中。 | 待记录：通过/失败/跳过；记录扫描结果。 |
| L1-06 | channel account 继承隔离检查 | 已完成 L1-04。 | 1. 执行 `metis gateway channel get telegram`。<br>2. 执行 `metis gateway channel get feishu`。<br>3. 执行 `metis gateway channel get qq`。 | 1. `tg-writer` 应显示 account-local credential/source；安全字段应能看到 effective count/source 信息。<br>2. `feishu-writer` 应显示账号级配置、route/live readiness/credential source，不应暴露 secret。<br>3. `qq-writer` 应显示 account-local credential/source，不应继承 top-level secret 到一个缺失凭证的命名账号。 | 待记录：通过/失败/跳过；记录每个账号的 credentialSource/securitySource 摘要。 |
| L1-07 | 命名账号缺失凭证不回退 top-level 凭证 | Gateway 已启动；可手工编辑隔离 `metis.json`，不得编辑真实配置。 | 1. 在 `$METIS_HOME/metis.json` 中为 Telegram/Feishu/QQ 各新增一个空命名账号，例如 `tg-empty`、`feishu-empty`、`qq-empty`，不要写 token/secret。<br>2. 执行 `metis gateway channel get telegram`、`metis gateway channel get feishu`、`metis gateway channel get qq`。<br>3. 执行 `metis gateway channel start telegram --account tg-empty`、`metis gateway channel start feishu --account feishu-empty`、`metis gateway channel start qq --account qq-empty`。 | 1. 空命名账号必须显示 `configured=false` 或 missing credential 类诊断。<br>2. 空命名账号不应借用 default/top-level token 或 secret。<br>3. 指定空账号启动时必须给出清晰的缺失凭证诊断，不应伪装成已启动。 | 待记录：通过/失败/跳过；记录三个 channel 的诊断文本。 |
| L1-08 | `agents capabilities` 与 custom agent 展示边界 | 至少已创建 `manual-reviewer`。 | 1. 执行 `metis agents capabilities`。<br>2. 执行 `metis agents list`。<br>3. 对比两个输出。 | 1. `agents capabilities` 应展示内置 agent 能力，例如 `main`、`cangjie`、`reviewer` 等。<br>2. `agents capabilities` 不要求展示 `manual-reviewer`。<br>3. `manual-reviewer` 必须通过 `agents list` 展示。 | 待记录：通过/失败/跳过；记录是否符合边界。 |
| L1-09 | agent binding 增删 | `manual-reviewer` 已存在。 | 1. 执行 `metis agents bind --agent manual-reviewer --bind telegram:tg-writer`。<br>2. 执行 `metis agents bindings --agent manual-reviewer`。<br>3. 执行 `metis agents unbind --agent manual-reviewer --bind telegram:tg-writer` 后再次执行 bindings。 | 1. bind 输出必须是人类可读文本。<br>2. 第一次 bindings 必须能看到 `telegram:tg-writer -> manual-reviewer` 或等价路由摘要。<br>3. unbind 后该绑定不应继续存在，且不应删除 agent 本身。 | 待记录：通过/失败/跳过；记录绑定前后摘要。 |
| L1-10 | team 模板创建 | Gateway 已启动。 | 1. 执行 `metis agents team create --team content-manual --template pm-writer-reviewer`。<br>2. 执行 `metis agents team list`。<br>3. 执行 `metis agents team get --team content-manual`。 | 1. create/list/get 默认输出必须是人类可读文本，不应是裸 JSON。<br>2. `content-manual` 必须出现在 team list。<br>3. get 输出必须包含成员、alias、defaultAgent/manager 语义摘要；manager 不应被描述成独立自治 runtime。 | 待记录：通过/失败/跳过；记录 team 成员摘要。 |
| L1-11 | team 成员和 alias 更新 | `content-manual` 已存在。 | 1. 执行 `metis agents team update --team content-manual --name "Content Manual" --member manual-reviewer:reviewer:"Manual Reviewer" --alias reviewer=manual-reviewer`。<br>2. 执行 `metis agents team get --team content-manual`。<br>3. 执行 `metis agents list`。 | 1. update 输出必须是人类可读文本。<br>2. get 输出必须显示 `manual-reviewer` 成员和 `reviewer=manual-reviewer` alias。<br>3. `manual-reviewer` 仍应作为独立 custom agent 存在。 | 待记录：通过/失败/跳过；记录更新后 team 摘要。 |
| L1-12 | team 删除不删除成员 agent | `content-manual` 已存在。 | 1. 执行 `metis agents team delete --team content-manual`。<br>2. 执行 `metis agents team list`。<br>3. 执行 `metis agents list`。 | 1. `content-manual` 不应继续出现在 team list。<br>2. team 删除不应删除 `manual-reviewer`、`content-pm`、`content-writer`、`content-reviewer` 等 member agent 目录。<br>3. 如果存在 team route binding，删除 team 不应误删已保存的独立 route binding；需要记录实际 binding 保留情况。 | 待记录：通过/失败/跳过；记录删除前后列表。 |
| L1-13 | team 迁移 dry-run 不写配置 | Gateway 已启动。 | 1. 执行 `cp "$METIS_HOME/metis.json" "$METIS_HOME/metis.before-migrate.json"`。<br>2. 执行 `metis agents migrate --dry-run`。<br>3. 执行 `diff "$METIS_HOME/metis.before-migrate.json" "$METIS_HOME/metis.json"`。 | 1. migrate 默认输出必须是人类可读 dry-run 摘要。<br>2. 输出必须说明 dry-run 或预览语义。<br>3. `diff` 不应显示配置被改写。 | 待记录：通过/失败/跳过；记录 diff 结果。 |
| L1-14 | channel 指定账号 runtime/start/stop 命令边界 | 已有 `tg-writer`、`feishu-writer`、`qq-writer`；如果凭证是 fake，启动失败属于预期诊断。 | 1. 执行 `metis gateway channel runtime telegram`、`metis gateway channel runtime feishu`、`metis gateway channel runtime qq`。<br>2. 执行 `metis gateway channel start telegram --account tg-writer`，再执行 `metis gateway channel stop telegram --account tg-writer`。<br>3. 对 Feishu/QQ 分别执行同类 start/stop 命令。 | 1. runtime 输出必须区分 live adapter state 和 configured accounts。<br>2. fake 凭证导致启动失败时，必须给出明确诊断，不应无响应、不应裸 JSON。<br>3. 指定 `--account` 的 start/stop/restart 不应影响其他账号的配置摘要。 | 待记录：通过/失败/跳过；记录每个账号 start/stop 结果。 |
| L2-01 | Control UI 可打开且 Agents/Teams 可见 | Gateway 已启动；浏览器使用 Gateway 输出的 Control UI URL。 | 1. 打开 Gateway Control UI URL。<br>2. 完成 token/bootstrap 登录。<br>3. 点击左侧或顶部的 `Agents`，再点击 `Teams` 子 tab。 | 1. 页面必须有可见 Metis UI，不应白屏。<br>2. 浏览器控制台不应出现 JavaScript 语法错误或资源 404。<br>3. `Agents` 页面必须能看到 `Teams` 子 tab 和 Agent Teams 内容。 | 待记录：通过/失败/跳过；记录 URL、截图路径、控制台错误。 |
| L2-02 | Control UI team CRUD | 已打开 `Agents -> Teams`。 | 1. 在 Teams 页面创建一个测试 team。<br>2. 修改 team 名称、成员、alias 后保存。<br>3. 删除该测试 team，并刷新页面。 | 1. 创建后列表中必须出现该 team。<br>2. 修改后详情区必须显示最新成员和 alias。<br>3. 删除后列表中不应出现该 team，成员 agent 不应被删除。 | 待记录：通过/失败/跳过；记录截图和操作结果。 |
| L2-03 | Control UI agent 文件、模型、binding 面板 | 已打开 `Agents -> Teams`，且存在 `manual-reviewer`。 | 1. 在 Teams/Agents 相关面板选择 `manual-reviewer`。<br>2. 查看 profile files、model state、binding preview/apply 区域。<br>3. 修改允许编辑的 profile 文件或模型草稿，并保存一次测试值；保存后恢复原值。 | 1. UI 只能通过 Gateway RPC 读写允许的 profile 文件，不应让浏览器直接写任意本地路径。<br>2. 模型区域应显示 agent 专属模型或模型状态。<br>3. binding 预览/应用应显示 channel/account，不应暴露 token/secret。 | 待记录：通过/失败/跳过；记录保存项、恢复项、截图路径。 |
| L3-01 | Telegram live：测试 bot 指定账号启动 | 只使用测试 Telegram bot；设置 `METIS_AGENTTEAM_LIVE_TELEGRAM=1`、`METIS_AGENTTEAM_TELEGRAM_ACCOUNT_ID`、`METIS_AGENTTEAM_TELEGRAM_TEST_CHAT_ID`。 | 1. 使用真实测试 bot token 创建 `tg-live-writer`：`metis agents add --agent tg-live-writer --name "TG Live Writer" --model <测试模型> --telegram-account <测试账号ID> --telegram-bot-token "<测试botToken>"`。<br>2. 执行 `metis gateway channel restart telegram --account <测试账号ID>`。<br>3. 执行 `metis gateway channel runtime telegram` 和 `metis gateway channel get telegram`。 | 1. 指定账号应出现在 configured accounts。<br>2. runtime 应显示该账号 adapter 已注册/运行，或显示可理解的启动失败原因。<br>3. 输出和日志不得暴露 bot token。 | 待记录：通过/失败/跳过；记录脱敏 accountId、chatId、runtime 状态。 |
| L3-02 | Telegram live：消息路由到指定 agent | 已完成 L3-01，测试 chat/group 已可给 bot 发消息。 | 1. 在测试 Telegram chat 给该 bot 发送一条普通文本。<br>2. 查看 Gateway 日志是否出现 `Gateway.inbound: channel=telegram`，并记录脱敏 accountId/peerId。<br>3. 查看 bot 是否回复，并用 `metis agents bindings --agent tg-live-writer` 或日志确认 route 到 `tg-live-writer`。 | 1. Gateway 必须收到 inbound。<br>2. 回复必须发送回同一测试 chat/thread。<br>3. 如果模型或发送失败，用户仍应收到明确错误回复，不应静默无响应。 | 待记录：通过/失败/跳过；记录消息时间、脱敏 chatId、日志摘要。 |
| L3-03 | Telegram live：群/topic 与 allowlist 行为 | 测试 bot 已加入测试群/topic；不得使用生产群。 | 1. 配置测试群或 topic route binding 到 `tg-live-writer`。<br>2. 使用允许的 sender 发送消息。<br>3. 使用未允许的 sender 发送消息，或临时移除 allowlist 后发送。 | 1. 允许 sender 的消息应进入对应 agent session。<br>2. 未授权 sender 不应进入 agent；日志应显示授权/策略拒绝原因。<br>3. 账号级 allowlist/group policy 不应被 default 账号的 allowFrom 意外放开。 | 待记录：通过/失败/跳过；记录群/topic、sender 脱敏 ID、策略结果。 |
| L4-01 | Feishu live：测试 app/bot 指定账号启动 | 只使用测试 Feishu app/bot；设置 `METIS_AGENTTEAM_LIVE_FEISHU=1` 和测试 tenant/chat/thread 变量。 | 1. 使用测试 appId/appSecret 创建 `feishu-live-writer`：`metis agents add --agent feishu-live-writer --name "Feishu Live Writer" --model <测试模型> --feishu-account <测试账号ID> --feishu "<appId>:<appSecret>"`。<br>2. 执行 `metis gateway channel restart feishu --account <测试账号ID>`。<br>3. 执行 `metis gateway channel get feishu` 和 `metis gateway channel runtime feishu`。 | 1. Feishu 测试账号必须出现在 configured accounts。<br>2. appSecret 必须脱敏。<br>3. runtime/live readiness 必须能区分 missing credentials、disabled、stopped、running、scope/auth blocker。 | 待记录：通过/失败/跳过；记录脱敏 accountId、tenant、runtime 状态。 |
| L4-02 | Feishu live：消息和 thread 路由 | Feishu 测试 app/bot 已接入测试群或 thread。 | 1. 在测试 Feishu 群或 thread 给 bot 发送消息。<br>2. 查看 Gateway 日志是否出现 Feishu inbound，并记录脱敏 accountId/chatId/threadId。<br>3. 验证回复是否落回同一群或 thread。 | 1. inbound 必须被 Gateway 接收。<br>2. route 必须命中目标 agent 或明确给出未命中原因。<br>3. 回复失败时必须有明确错误或 fallback，不应静默丢失。 | 待记录：通过/失败/跳过；记录消息时间、脱敏 threadId、日志摘要。 |
| L4-03 | Feishu OAuth/OAPI/Card/rich event 手工验收 | 具备测试 Feishu tenant、测试用户、测试文档/日历/任务/多维表格/消息资源。 | 1. 在 Control UI Teams 页面或 Gateway Feishu 相关 status/doctor 入口查看 OAuth/OAPI readiness。<br>2. 对测试资源执行只读 OAPI smoke；写操作只允许在测试资源上执行。<br>3. 触发 CardKit/streaming card/rich event 测试消息。 | 1. 缺 scope/token 时必须返回 `auth_required` 或 `scope_missing` 等结构化诊断。<br>2. CardKit/streaming 失败时必须 fallback 到文本或明确错误，不应无响应。<br>3. 验收记录不得包含 appSecret、access token、refresh token、Authorization header。 | 待记录：通过/失败/跳过；记录测试资源脱敏 ID、scope 诊断、card 状态。 |
| L5-01 | QQ live：测试 QQ bot 指定账号启动 | 只使用测试 QQ bot；如果没有 QQ 测试资源，本项记录为跳过。 | 1. 使用测试 appId/appSecret 创建 `qq-live-writer`：`metis agents add --agent qq-live-writer --name "QQ Live Writer" --model <测试模型> --qqbot-account <测试账号ID> --qqbot "<appId>:<appSecret>"`。<br>2. 执行 `metis gateway channel restart qq --account <测试账号ID>`。<br>3. 执行 `metis gateway channel get qq` 和 `metis gateway channel runtime qq`。 | 1. QQ 测试账号必须出现在 configured accounts。<br>2. appSecret 必须脱敏。<br>3. 指定账号启动失败时必须说明原因，不应回退 default/top-level credential。 | 待记录：通过/失败/跳过；记录脱敏 accountId 和 runtime 状态。 |
| L6-01 | 发布前 Cangjie 全量验证 | 停止不需要的本地 Gateway 进程；保持代码工作区不含无关改动。 | 1. 执行 `cjpm clean`。<br>2. 执行 `cjpm build -i`。<br>3. 执行 `cjpm test -j1 --no-progress`。 | 1. build 必须通过。<br>2. test 必须通过，`ERROR=0`、`FAILED=0`。<br>3. 如果默认并发 `cjpm test` 出现 exit 9，需要记录默认命令结果，并以 `cjpm test -j1 --no-progress` 作为最终串行验收结果。 | 待记录：通过/失败/跳过；记录 TOTAL/PASSED/ERROR/FAILED。 |
| L6-02 | Control UI 构建与浏览器 smoke | Node 依赖已安装；Gateway 可服务 Control UI。 | 1. 执行 `npm --prefix ui test`。<br>2. 执行 `npm --prefix ui run build`。<br>3. 打开 Control UI，检查 `customElements.get("metis-app")`、可见页面内容、控制台错误和静态资源请求。 | 1. UI 单测和 build 必须通过。<br>2. 浏览器中 `metis-app` 必须注册。<br>3. 页面必须显示 Metis UI，不得白屏；JS/CSS 请求不应失败。 | 待记录：通过/失败/跳过；记录测试输出、截图、控制台摘要。 |
| L6-03 | 最终证据包归档 | 完成 L0-L6 已执行项。 | 1. 重新执行 `bash scripts/agentteam-manual-acceptance-gate.sh`。<br>2. 把本矩阵中每一行的“测试结果记录”填为通过/失败/跳过，并写入 `manual-acceptance-template.md` 或验收报告。<br>3. 执行敏感词扫描并保存脱敏后的日志路径。 | 1. 每个跳过项必须有原因，例如 `external-resource-required`。<br>2. 每个失败项必须有操作命令、预期、实际、脱敏日志路径。<br>3. 证据包和报告不得包含真实 token、secret、Authorization header、真实生产资源 ID。 | 待记录：通过/失败/跳过；记录 evidence pack 路径和最终结论。 |

## 4. 结果记录建议格式

每一行的“测试结果记录”建议按下面格式填写：

```text
结果：通过 / 失败 / 跳过
执行人：
执行时间：
命令或页面：
实际输出摘要：
证据路径：
脱敏说明：
遗留问题：
```

## 5. 关键注意事项

1. `agents get` 当前不存在，不要把它写入手工测试步骤。
2. `agents capabilities` 只用于内置 agent 能力，不用于证明 custom agent 是否创建成功。
3. `gateway channel get <id>` 是账号配置摘要，不带 `--account`；指定账号 start/stop/restart 使用 `--account`。
4. 本地 fake credential 只能验证配置、脱敏、路由、诊断和命令边界；不能证明真实 IM 可收发。
5. Telegram、Feishu、QQ live 验收必须使用测试 bot/app/tenant/chat/group/thread，不能使用生产资源。
6. 任何手工验收日志、截图、报告都不能包含 bot token、appSecret、access token、refresh token、Authorization header、provider API key、proxy password。
