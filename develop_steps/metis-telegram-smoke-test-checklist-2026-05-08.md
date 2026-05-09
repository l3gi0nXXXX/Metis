# Metis Telegram Smoke 测试清单

日期：2026-05-08

目标：在不修改代码、不修改真实配置的前提下，由真实 Telegram bot 侧验证当前 Metis Telegram channel 的用户可见能力是否闭环。测试结果用于判断是否还有运行时配置、网络、adapter 注册、媒体下载/发送、工具调用或通知链路问题。

## 1. 测试前置条件

1. 当前代码为 `main` 分支最新版本，并已完成 `cjpm clean && cjpm build -i && cjpm test`。
2. Gateway 已启动或重启完成。
3. Telegram 配置由你手动确认，不由测试或脚本改写真实配置。
4. Telegram bot 可以收到来自 Gateway 的主动消息，例如 pairing 提示或历史正常回复。
5. 如果使用代理，确认代理地址、协议和端口与 `metis.json` 中 Telegram 配置一致。

建议先执行：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
cjpm run --skip-build --name metis --run-args "gateway status"
cjpm run --skip-build --name metis --run-args "gateway channel list"
cjpm run --skip-build --name metis --run-args "gateway discover"
```

验收：

- Gateway 处于 running。
- `gateway channel list` 中包含内置 `telegram` channel。
- `gateway discover` 输出中 Telegram 的 `enabled=true`、`configured=true`，并能看到当前 `mode`、`network`、`actions`、`media`、`supports` 等运行配置。
- 日志中不应持续出现 `TLS handshake failed`、`adapter not found`、`unauthorized`、`pairing required` 循环。

## 2. 基础文本链路

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-01 | 向 Telegram bot 发送 `你好` | Bot 在合理时间内回复文本 | 待填写 |
| TG-SMOKE-02 | 连续发送 3 条短消息 | 每条消息均有回复，不丢消息，不长期阻塞 | 待填写 |
| TG-SMOKE-03 | 发送一条较长中文需求 | Bot 能正常理解并回复，不截断异常 | 待填写 |
| TG-SMOKE-04 | 发送包含英文、数字、符号的消息 | Bot 正常回复，日志无解析错误 | 待填写 |

失败时记录：

- 发送时间。
- Gateway 日志文件路径。
- 是否出现 `Gateway.inbound: channel=telegram`。
- 是否出现 `Gateway.sendTextToPeer` 错误。

## 3. Pairing 与授权链路

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-05 | 未授权账号发送消息，若当前环境可测 | Bot 返回 pairing approve 提示 | 待填写 |
| TG-SMOKE-06 | 执行 pairing approve 后再次发送消息 | Bot 正常回复，不再要求 pairing | 待填写 |
| TG-SMOKE-07 | 已授权账号重启 gateway 后发送消息 | 授权状态保持，正常回复 | 待填写 |

失败时记录：

- pairing code。
- approve 命令输出。
- 日志中 `Pairing required`、`pairing approve`、`authorized` 相关行。

## 4. Ack / Chat Action 体验

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-08 | 发送普通文本消息 | Telegram 侧出现已读/处理中体验；如配置支持 reaction，应出现小眼睛等 ack reaction | 待填写 |
| TG-SMOKE-09 | 发送会触发较长处理的需求 | Bot 回复前不应无声失败；日志不应出现 chat-action adapter not found | 部分通过/需修复：2026-05-09 12:26:27 收到真实 Telegram 入站并最终有回复，但日志 12:26:29 出现 `Telegram lifecycle chat-action skipped: no adapter for channel='telegram' ... adapter not found for accountId=default` |

失败时记录：

- Telegram 侧是否完全无反馈。
- 日志中 `ackReaction`、`sendChatAction`、`chat-action skipped` 相关行。

## 5. 图片接收、理解、保存

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-10 | 给 bot 发送一张图片，只发图片不带文字 | Gateway 下载图片到 `~/.metis/gateway-telegram/accounts/default/media/` 下的日期目录，不保存到源码目录 | 待填写 |
| TG-SMOKE-11 | 发送图片并附文 `保存这张图片` | Bot 能确认保存成功，并给出真实本地保存路径 | 待填写 |
| TG-SMOKE-12 | 发送图片并要求描述图片内容 | 如模型/vision 配置支持，返回图片理解结果；如不支持，应明确说明当前模型不支持视觉，不影响图片保存 | 待填写 |
| TG-SMOKE-13 | 连续发送两张图片并分别要求保存 | 两张图片保存路径不同，均在 Telegram media 根目录下 | 待填写 |

验收重点：

- 不允许保存到 `[Image #1]`、源码目录、当前工作目录或临时错误路径。
- 日志或工具上下文中图片状态应从 `downloaded=false` 变为可用本地路径。

失败时记录：

- Bot 回复原文。
- 实际保存路径。
- 日志中 `downloaded=false`、`telegram_media_save`、`mediaRoot`、`downloadFile` 相关行。

## 6. 图片发送

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-14 | 要求 bot 把刚保存的图片发回 Telegram | Bot 通过 Telegram 直接发送图片，而不是只返回本地路径 | 待填写 |
| TG-SMOKE-15 | 要求 bot 发送一个明确存在的本地图片路径 | 如果路径在允许的 media/workspace 范围内，Telegram 收到图片 | 待填写 |
| TG-SMOKE-16 | 要求 bot 发送不存在的图片路径 | Bot 返回明确错误，不崩溃，不泄露无关路径 | 待填写 |

失败时记录：

- 是否出现 `channel-not-legacy-compatible`。
- 是否出现 `telegram outbound local media path is disabled`。
- 是否出现 `sendPhoto` / `sendMedia` 相关错误。

## 7. 文件接收、保存、发送

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-17 | 向 bot 发送一个 txt/pdf/doc 文件 | 文件下载到 Telegram media 根目录下，Bot 能识别文件元信息 | 待填写 |
| TG-SMOKE-18 | 要求保存该文件 | Bot 返回保存成功和本地路径 | 待填写 |
| TG-SMOKE-19 | 要求 bot 把该文件发回 Telegram | Telegram 收到文件附件 | 待填写 |

失败时记录：

- 文件名、大小、MIME。
- 日志中 `document`、`downloadFile`、`sendDocument` 相关行。

## 8. 语音、音频、视频

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-20 | 向 bot 发送 Telegram 语音消息 | Gateway 下载 voice 文件；如 ASR 配置支持，应转写；不支持时应明确说明能力限制 | 待填写 |
| TG-SMOKE-21 | 要求保存语音 | Bot 返回保存成功和本地路径 | 待填写 |
| TG-SMOKE-22 | 要求 bot 发送一段语音/音频 | Telegram 收到 voice/audio，或明确说明当前 TTS/voice provider 未配置 | 待填写 |
| TG-SMOKE-23 | 向 bot 发送短视频 | Gateway 下载视频并保存到 media 根目录 | 待填写 |
| TG-SMOKE-24 | 要求 bot 把视频发回 Telegram | Telegram 收到视频，失败时返回明确错误 | 待填写 |

失败时记录：

- 日志中 `voice`、`audio`、`video`、`telegram_media_save`、`sendVoice`、`sendAudio`、`sendVideo` 相关行。

## 9. TTS 命令 Provider

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-25 | 在配置了 TTS provider 的情况下，让 bot 朗读一段中文 | Provider 被调用，Telegram 收到音频/语音 | 待填写 |
| TG-SMOKE-26 | 在未配置 TTS provider 的情况下让 bot 朗读 | Bot 明确说明未配置，不误报成功 | 待填写 |

失败时记录：

- TTS provider 配置项。
- 日志中 `telegramTts`、`/tts`、`sendVoice`、`sendAudio` 相关行。

## 10. Subagent 通知链路

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-27 | 在 Telegram 中要求启动一个短任务 subagent | Bot 返回 subagent 已启动和 runId | 待填写 |
| TG-SMOKE-28 | 等待 subagent 完成 | Telegram 当前会话自动收到完成通知和结果摘要 | 待填写 |
| TG-SMOKE-29 | 使用 `/subagents list active` 或等价能力查询 | 运行中/已完成状态准确，不出现 stale running 伪活跃 | 待填写 |

失败时记录：

- runId。
- `requesterSessionKey`。
- `noticeStatus`。
- 日志中 `subagent`、`notify`、`Telegram send` 相关行。

## 11. Gateway 重启恢复

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-30 | 执行 gateway restart 后立即向 bot 发送消息 | Telegram adapter 自动恢复，消息能进入 Gateway 并回复 | 待填写 |
| TG-SMOKE-31 | 重启后发送图片并保存 | 图片下载和保存能力仍正常 | 待填写 |
| TG-SMOKE-32 | 重启后触发 subagent 完成通知 | 通知仍能通过 Gateway 推送到 Telegram | 待填写 |

失败时记录：

- restart 时间。
- 最新 gateway 日志路径。
- 是否出现 `adapter-started`、`live-updated-running`。
- 是否出现 `no adapter for channel='telegram'`。

## 12. 异常与边界测试

| 编号 | 操作 | 预期结果 | 测试结果 |
|---|---|---|---|
| TG-SMOKE-33 | 发送空消息、表情或 sticker | 不崩溃；能处理或给出合理提示 | 待填写 |
| TG-SMOKE-34 | 发送超大文件，超过 Telegram/Gateway 限制 | 返回明确限制说明，不崩溃 | 待填写 |
| TG-SMOKE-35 | 网络代理短暂断开后恢复 | polling 自动 backoff 并恢复，不进入不可恢复 failed | 待填写 |
| TG-SMOKE-36 | 连续发送多媒体和文本混合消息 | 顺序、上下文、保存路径均正确 | 待填写 |

失败时记录：

- 异常输入类型。
- 是否有进程退出。
- `gateway-background.log` 和最新 `~/.metis/logs/*.log` 中相关错误。

## 13. 测试失败时统一收集信息

如果任一项失败，请收集：

```bash
date
ps aux | grep -E "metis gateway|metis chat" | grep -v grep
tail -200 ~/.metis/gateway-background.log
ls -t ~/.metis/logs | head -5
```

然后针对最新日志执行：

```bash
grep -nE "Gateway.inbound|telegram|Telegram|adapter|sendTextToPeer|downloadFile|sendPhoto|sendDocument|sendVoice|sendVideo|subagent|notify|pairing|TLS|error|failed" ~/.metis/logs/<latest-log-file> | tail -200
```

## 14. 最终通过标准

本轮 smoke 通过需要满足：

1. 文本消息收发稳定。
2. Gateway restart 后 Telegram adapter 自动恢复。
3. 图片、文件、语音/音频、视频的接收保存路径均位于 `~/.metis/gateway-telegram/accounts/default/media/` 下。
4. 支持的媒体类型可以通过 Telegram 回传；不支持或未配置的能力必须返回明确、真实的能力限制。
5. Subagent 完成后能通过 Gateway 主动通知 Telegram 当前会话。
6. 日志中不再出现 accountId 不一致导致的 `adapter not found for accountId=default`。
7. 没有测试或运行逻辑写坏真实 `metis.json`。

## 15. 2026-05-09 本地自动/只读验证记录

已执行，不修改真实 Telegram 配置：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/Users/l3gi0n/cangjie100/runtime/lib/darwin_aarch64_llvm:/Users/l3gi0n/cangjie100/tools/lib:/Users/l3gi0n/work/workspace_cangjie/CangjieMagic/libs/cangjie-stdx-mac-aarch64-1.0.0.1/darwin_aarch64_llvm/dynamic/stdx:/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm run --skip-build --name metis --run-args "gateway status"
cjpm run --skip-build --name metis --run-args "gateway channel list"
cjpm run --skip-build --name metis --run-args "gateway discover"
```

结果：

- `gateway status`：通过，输出为人类可读配置摘要。
- `gateway channel list`：通过，内置 channel 列表包含 `telegram`。
- `gateway discover`：通过，Telegram 显示 `enabled=true`、`configured=true`、`mode=polling`。
- Telegram media 当前运行配置可见：`download=true`、`local-send=true`、`url-send=false`。
- Telegram network 当前运行配置可见：`apiRoot=https://api.telegram.org`、`proxy=true`。

仍需真实 Telegram bot 手工验证的项目见第 2-12 节。真实 bot smoke 的结果应逐项写回对应 `TG-SMOKE-*` 的“测试结果”列。
