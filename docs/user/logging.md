# Metis 日志与排障

Metis 的运行日志默认在 `~/.metis/logs/`。如果设置了 `METIS_HOME`，日志目录会位于 `$METIS_HOME/logs/`。

## 常用命令

```bash
metis logs path
metis logs recent
metis logs current
metis logs tail
metis logs tail --limit 100
metis logs show <log-file> --limit 200
```

- `path`：显示日志目录。
- `recent`：列出最近日志文件。
- `current`：显示当前 Gateway 日志文件。
- `tail`：查看最新日志；排障时通常先用它。
- `show`：一次性查看某个日志文件的最后若干行。

需要脚本处理时使用显式 JSON 输出模式：

```bash
metis logs tail --limit 50 --json
```

默认输出面向人阅读；只有显式 `--json` 时才应把 stdout 当作机器输出。

## verbose

普通 Gateway 输出只显示启动、ready、渠道账号状态、警告和错误摘要。需要更多运行细节时启动 verbose：

```bash
metis gateway run --verbose
```

verbose 适合临时排障，例如查看渠道启动阶段、入站/出站摘要、慢请求或失败请求。不要在公开日志里粘贴 token、app secret、authorization header 或完整用户消息正文。

## 排查 IM 无回复

先确认消息是否进入 Gateway：

```bash
metis logs tail --limit 200
```

查找这些关键词：

- `Gateway.inbound` 或后续结构化日志中的 `message.inbound`
- `Gateway.reply` 或后续结构化日志中的 `message.reply.generated`
- `Gateway.send`、`message.outbound`、`message.sent`、`message.send_failed`

判断路径：

1. 没有 inbound：优先检查渠道连接、账号启用、Webhook/polling/sidecar 是否运行、凭证是否正确。
2. 有 inbound 但没有 reply：检查路由、会话、模型调用、技能或工具执行错误。
3. 有 reply 但没有 send/sent：检查渠道发送配置、目标 peer、权限、网络和限流。
4. 有 send_failed：查看同一行的错误摘要，再检查对应渠道配置。

Telegram 排障时，如果没有 inbound，优先检查 bot token、代理、polling/webhook 状态和账号绑定。Feishu/QQ 排障时，先确认账号启用状态、授权状态、长连接或官方网关连接是否正常。
