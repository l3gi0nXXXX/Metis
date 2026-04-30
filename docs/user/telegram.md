# Telegram 使用与配置

本文说明 Metis 内置 Telegram channel 的配置、收发消息格式、媒体能力和排障方式。Telegram 与 CLI、control-ui、其他 IM channel 一样，都通过 Gateway 进入统一 session/runtime，不应绕过 Gateway 单独调用 agent。

## 基本配置

Telegram 配置写在 `~/.metis/metis.json` 的 `gateway.telegram` 下。最小 polling 配置如下：

```json
{
  "gateway": {
    "telegram": {
      "enabled": true,
      "tokenFile": "~/.metis/secrets/telegram-bot-token",
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist"
    }
  }
}
```

推荐使用 `tokenFile`，不要把 bot token 直接写入可共享的配置文件。`botToken` 仍可用，但更适合本地临时验证。

常用字段：

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `enabled` | `false` | 是否启用 Telegram channel。 |
| `botToken` | `""` | Telegram Bot API token。推荐改用 `tokenFile`。 |
| `tokenFile` | `""` | bot token 文件路径。 |
| `apiRoot` | `https://api.telegram.org` | Telegram Bot API 根地址。 |
| `proxy` | `""` | HTTP/HTTPS 代理，例如 `http://127.0.0.1:7897` 或 `https://127.0.0.1:7897`。 |
| `timeoutSeconds` | `30` | Bot API 请求超时秒数。 |
| `defaultTo` | `""` | 默认发送目标，通常由 Gateway session 自动推断。 |

## 启动

修改配置后重启 Gateway：

```bash
cjpm run --skip-build --name metis --run-args "gateway restart"
```

查看运行状态：

```bash
cjpm run --skip-build --name metis --run-args "gateway status"
cjpm run --skip-build --name metis --run-args "doctor"
```

## DM 与群聊策略

私聊由 `dmPolicy` 控制：

| 值 | 行为 |
|---|---|
| `pairing` | 默认值。首次私聊会收到 pairing 提示，执行 `metis pairing approve telegram <code>` 后放行。 |
| `allowlist` | 只允许 `allowFrom` 中的 sender id。 |
| `open` | 仅当 `allowFrom` 包含 `"*"` 时开放所有私聊。 |
| `disabled` | 禁用私聊入站。 |

示例：

```json
{
  "gateway": {
    "telegram": {
      "enabled": true,
      "tokenFile": "~/.metis/secrets/telegram-bot-token",
      "dmPolicy": "allowlist",
      "allowFrom": ["873****810"]
    }
  }
}
```

群聊由 `groupPolicy`、`groupAllowFrom` 和 `groups` 控制：

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `groupPolicy` | `allowlist` | 群聊 sender 策略。可用 `open`、`allowlist`、`disabled`。 |
| `groupAllowFrom` | `[]` | 群聊允许的 sender id。为空时回退到 `allowFrom`。 |
| `groups` | `null` | 群 id 级别配置。没有配置 `groups` 时，只有 `groupPolicy=open` 才允许群入站。 |

群 topic 示例：

```json
{
  "gateway": {
    "telegram": {
      "enabled": true,
      "tokenFile": "~/.metis/secrets/telegram-bot-token",
      "groupPolicy": "allowlist",
      "groups": {
        "-1001234567890": {
          "requireMention": false,
          "allowFrom": ["873****810"]
        }
      }
    }
  }
}
```

`allowFrom` 支持纯数字 id，也兼容 `tg:<id>` 形式。群聊默认要求提及 bot；可用 `groups.<chatId>.requireMention=false` 关闭。

## Polling 与 Webhook

默认未配置 `webhookUrl` 时使用 polling：

```json
{
  "gateway": {
    "telegram": {
      "enabled": true,
      "tokenFile": "~/.metis/secrets/telegram-bot-token"
    }
  }
}
```

配置 `webhookUrl` 后进入 webhook 模式：

```json
{
  "gateway": {
    "telegram": {
      "enabled": true,
      "tokenFile": "~/.metis/secrets/telegram-bot-token",
      "webhookUrl": "https://example.com/telegram-webhook",
      "webhookSecret": "change-me",
      "webhookHost": "127.0.0.1",
      "webhookPort": 8787,
      "webhookPath": "/telegram-webhook"
    }
  }
}
```

Webhook 字段：

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `webhookUrl` | `""` | 公开可访问的 Telegram webhook URL。为空时使用 polling。 |
| `webhookSecret` | `""` | Telegram `X-Telegram-Bot-Api-Secret-Token` 校验值。建议生产环境配置。 |
| `webhookHost` | `127.0.0.1` | 本地 webhook server 监听 host。 |
| `webhookPort` | `8787` | 本地 webhook server 监听端口。 |
| `webhookPath` | `/telegram-webhook` | 本地 webhook path。 |

## 输出与动作开关

出站动作由 `actions` 控制。默认只启用普通文本和 reaction，其他高风险或媒体动作默认关闭。

```json
{
  "gateway": {
    "telegram": {
      "actions": {
        "sendMessage": true,
        "reactions": true,
        "inlineKeyboard": true,
        "callbackQuery": true,
        "photo": true,
        "document": true,
        "audio": true,
        "voice": true
      }
    }
  }
}
```

字段说明：

| 字段 | 默认值 | Bot API / 行为 |
|---|---:|---|
| `sendMessage` | `true` | `sendMessage` 普通文本。 |
| `reactions` | `true` | `setMessageReaction`。 |
| `poll` | `false` | `sendPoll`。 |
| `deleteMessage` | `false` | `deleteMessage`。 |
| `editMessage` | `false` | `editMessageText`。 |
| `photo` | `false` | `sendPhoto`。 |
| `document` | `false` | `sendDocument`。 |
| `audio` | `false` | `sendAudio`。 |
| `voice` | `false` | `sendVoice`。 |
| `video` | `false` | `sendVideo`。 |
| `videoNote` | `false` | `sendVideoNote`。 |
| `sticker` | `false` | `sendSticker`。 |
| `createForumTopic` | `false` | `createForumTopic`。 |
| `editForumTopic` | `false` | `editForumTopic`。 |
| `inlineKeyboard` | `false` | 带 `reply_markup.inline_keyboard` 的 `sendMessage`。 |
| `callbackQuery` | `false` | 接收 `callback_query` 入站事件。 |

## 文本与回复

文本出站由 Gateway 自动调用，不需要用户手写特殊格式。

长文本配置：

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `textChunkLimit` | `4000` | 单条 Telegram 文本分片长度。 |
| `chunkMode` | `length` | 分片方式。当前支持按长度；`newline` 可按段落倾向切分。 |
| `replyToMode` | `off` | 回复目标使用方式。常用值：`off`、`first`、`all`、`thread`。 |
| `linkPreview` | `true` | 是否允许链接预览。 |
| `silent` | `false` | 是否静默发送。 |

## 图片、文件、语音与其他媒体

### 入站媒体

Telegram 入站媒体会先映射为结构化文本，再进入 Gateway session。支持：

- `photo`
- `document`
- `audio`
- `voice`
- `video`
- `video_note`
- `sticker`

图片示例：

```text
[photo]
fileId=<telegram-file-id>
fileUniqueId=<telegram-file-unique-id>
fileSize=123456
mediaGroupId=<album-id>
albumPolicy=single-largest
caption=hello
```

文件示例：

```text
[document]
fileId=<telegram-file-id>
fileUniqueId=<telegram-file-unique-id>
mimeType=application/pdf
fileSize=1024
fileName=report.pdf
caption=report
```

语音示例：

```text
[voice]
fileId=<telegram-file-id>
mimeType=audio/ogg
fileSize=20480
```

### 入站媒体下载

`media.downloadEnabled=true` 时，Metis 会通过 Telegram `getFile` 和 file download API 下载媒体内容。状态保存在：

```text
~/.metis/gateway-telegram/accounts/<accountId>/media-state.json
~/.metis/gateway-telegram/accounts/<accountId>/media/
```

媒体下载配置：

```json
{
  "gateway": {
    "telegram": {
      "media": {
        "downloadEnabled": true,
        "mediaMaxBytes": 20971520,
        "allowedMimes": ["image/*", "application/pdf", "audio/*"],
        "albumPolicy": "single-largest"
      }
    }
  }
}
```

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `downloadEnabled` | `true` | 是否下载入站媒体。关闭后仍会保留结构化 `fileId` 文本。 |
| `mediaMaxBytes` | `20971520` | 最大下载大小，默认 20 MiB。 |
| `allowedMimes` | `[]` | 允许下载的 MIME。为空表示不按 MIME 限制；支持 `image/*` 和 `*`。 |
| `albumPolicy` | `single-largest` | album/media group 策略。支持 `single-largest`、`first`、`metadata-only`。 |

### 出站图片

需要开启：

```json
{
  "gateway": {
    "telegram": {
      "actions": {
        "photo": true
      }
    }
  }
}
```

发送格式：

```text
[photo]
fileId=<telegram-file-id>
caption=hello
```

### 出站文件

需要开启：

```json
{
  "gateway": {
    "telegram": {
      "actions": {
        "document": true
      }
    }
  }
}
```

发送格式：

```text
[document]
fileId=<telegram-file-id>
caption=report
```

### 出站语音

需要开启：

```json
{
  "gateway": {
    "telegram": {
      "actions": {
        "voice": true
      }
    }
  }
}
```

发送格式：

```text
[voice]
fileId=<telegram-file-id>
caption=memo
```

### 出站音频

需要开启 `actions.audio=true`：

```text
[audio]
fileId=<telegram-file-id>
caption=podcast
```

### 出站媒体引用限制

默认只建议使用 Telegram `file_id`。URL 和本地路径有额外限制：

```json
{
  "gateway": {
    "telegram": {
      "media": {
        "outboundAllowUrl": false,
        "outboundAllowLocalPath": false,
        "outboundLocalRoots": []
      }
    }
  }
}
```

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `outboundAllowUrl` | `false` | 是否允许出站媒体引用 `http://` 或 `https://` URL。 |
| `outboundAllowLocalPath` | `false` | 是否允许本地路径引用。 |
| `outboundLocalRoots` | `[]` | 允许的本地路径根目录。 |

当前限制：

- URL 只在 `outboundAllowUrl=true` 时允许。
- 本地路径只在 `outboundAllowLocalPath=true` 且路径位于 `outboundLocalRoots` 白名单内时允许；通过校验后会使用 Telegram Bot API multipart/form-data 上传。
- `video-note` 不支持 URL 媒体引用。

## Inline Keyboard 与 Callback

开启：

```json
{
  "gateway": {
    "telegram": {
      "actions": {
        "inlineKeyboard": true,
        "callbackQuery": true
      }
    }
  }
}
```

发送格式：

```text
[inline-keyboard]
text=Choose
button=Approve|callback:approve-1
button=Docs|url:https://example.com
```

callback 入站会转成结构化文本，例如包含：

```text
[telegram-callback]
data=approve-1
```

审批按钮可使用 `[approval]` 格式发送。该格式会生成两枚 inline button，callback 数据会携带审批 id、决策和过期时间。必须开启 `actions.inlineKeyboard`；接收入站审批结果时还必须开启 `actions.callbackQuery`。

```text
[approval]
id=tool-call-123
text=Allow this tool call?
allowLabel=Allow
denyLabel=Deny
allow=allow-once
deny=deny
expiresAtMs=1770000000000
```

审批 callback 入站会转成结构化文本：

```text
[telegram-approval]
approvalId=tool-call-123
decision=allow-once
```

Metis 会拒绝过期或重复消费的审批 callback，并在入站策略诊断中记录 `approval_callback_expired` 或 `approval_callback_replayed`。

## Draft / Preview

开启 `actions.editMessage=true` 后，可用 `[draft]` 先发送预览文本，再通过 `editMessageText` 收敛为最终文本。该能力用于长任务或长回复的预览/最终态收口。

```text
[draft]
preview=Working...
final=Done
```

如果 `final` 为空，或未开启 `actions.editMessage`，发送会在网络请求前失败并返回明确错误。

## Reactions

配置：

```json
{
  "gateway": {
    "telegram": {
      "reactionNotifications": "all",
      "reactionLevel": "ack",
      "ackReaction": "👀",
      "actions": {
        "reactions": true
      }
    }
  }
}
```

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `reactionNotifications` | `off` | 是否接收 Telegram reaction update。`all` 会加入 allowed updates。 |
| `reactionLevel` | `ack` | 自动 ack reaction 策略。`off` 可关闭。 |
| `ackReaction` | `👀` | ack 使用的 emoji。 |

出站 reaction 格式：

```text
[reaction]
token=👍
render=👍
```

## Native Commands

`commandsNative` 控制 Telegram bot command menu：

| 值 | 行为 |
|---|---|
| `auto` | 默认。启动时按内置和自定义命令同步。 |
| `off` | 不同步 Telegram command menu。 |

自定义命令：

```json
{
  "gateway": {
    "telegram": {
      "commandsNative": "auto",
      "customCommands": [
        {
          "command": "status",
          "description": "Show Metis status"
        }
      ]
    }
  }
}
```

Telegram 中 `/subagents` 等命令仍走 Gateway 统一命令路径，不在 Telegram adapter 内单独执行 agent 逻辑。

## Topic、Thread 与 Subagent

Telegram topic 会映射到 topic-scoped session，例如：

```text
telegram:group:<chatId>:topic:<threadId>
```

可选配置：

```json
{
  "gateway": {
    "telegram": {
      "threadBindings": {
        "enabled": true,
        "spawnSubagentSessions": true,
        "spawnAcpSessions": false
      }
    }
  }
}
```

字段：

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `enabled` | `false` | 是否启用 Telegram thread binding 相关投影。 |
| `spawnSubagentSessions` | `false` | subagent spawn 是否记录 topic/thread 绑定。 |
| `spawnAcpSessions` | `false` | ACP session 是否记录 topic/thread 绑定。 |

群配置支持 topic 级覆盖。topic 配置会优先于群配置生效，可覆盖 `requireMention`、`groupPolicy`、`allowFrom`：

```json
{
  "gateway": {
    "telegram": {
      "groupPolicy": "allowlist",
      "groups": {
        "-1001234567890": {
          "requireMention": true,
          "allowFrom": ["111"],
          "topics": {
            "42": {
              "requireMention": false,
              "allowFrom": ["222"]
            }
          }
        }
      }
    }
  }
}
```

上例中 topic `42` 会允许 sender `222` 不提及 bot 直接入站；sender `111` 仍只匹配群级配置，不匹配该 topic 的覆盖规则。

Subagent 用法见 `docs/user/subagents.md`。

## 多账号

`accountId` 默认为 `default`。可以通过 `accounts` 为不同账号配置独立 token。运行状态会按账号隔离 offset、media、pairing：

```json
{
  "gateway": {
    "telegram": {
      "accountId": "work",
      "accounts": {
        "work": {
          "tokenFile": "~/.metis/secrets/telegram-work-token"
        },
        "personal": {
          "tokenFile": "~/.metis/secrets/telegram-personal-token"
        }
      }
    }
  }
}
```

账号状态目录：

```text
~/.metis/gateway-telegram/accounts/<accountId>/
```

## Setup、Directory 与 Account Ops

Telegram 的 setup、directory、account ops 通过 Gateway channel surface 暴露给 CLI、Control UI 和 RPC，不在 Telegram adapter 内直接写配置。

```bash
cjpm run --skip-build --name metis --run-args "gateway channels get telegram"
cjpm run --skip-build --name metis --run-args "gateway channels runtime telegram"
```

`channels get telegram` 会包含：

- `setup`：是否 configured、当前 mode、必填字段、是否可 probe。
- `directory`：`defaultTo`、已配置 groups、accounts、可推断 targets。
- `accountOps`：setup、probe、directory、logout 等操作能力声明。

这些字段是只读投影；真实配置修改仍必须走 Gateway 配置更新路径，测试和运行态都不应直接改写真实 `~/.metis/metis.json`。

## 网络配置

```json
{
  "gateway": {
    "telegram": {
      "proxy": "http://127.0.0.1:7897",
      "network": {
        "autoSelectFamily": true,
        "dnsResultOrder": "ipv4first",
        "dangerouslyAllowPrivateNetwork": false
      }
    }
  }
}
```

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `autoSelectFamily` | `true` | 自动选择地址族。 |
| `dnsResultOrder` | `ipv4first` | DNS 结果偏好。 |
| `dangerouslyAllowPrivateNetwork` | `false` | 是否允许访问私有网络目标。通常不要开启。 |

## 完整示例

```json
{
  "gateway": {
    "telegram": {
      "enabled": true,
      "tokenFile": "~/.metis/secrets/telegram-bot-token",
      "dmPolicy": "pairing",
      "allowFrom": [],
      "groupPolicy": "allowlist",
      "groups": {
        "-1001234567890": {
          "requireMention": false,
          "allowFrom": ["873****810"]
        }
      },
      "commandsNative": "auto",
      "replyToMode": "thread",
      "textChunkLimit": 4000,
      "chunkMode": "length",
      "streaming": "partial",
      "blockStreaming": false,
      "linkPreview": true,
      "silent": false,
      "proxy": "http://127.0.0.1:7897",
      "actions": {
        "sendMessage": true,
        "reactions": true,
        "inlineKeyboard": true,
        "callbackQuery": true,
        "photo": true,
        "document": true,
        "audio": true,
        "voice": true
      },
      "media": {
        "downloadEnabled": true,
        "mediaMaxBytes": 20971520,
        "allowedMimes": ["image/*", "application/pdf", "audio/*"],
        "outboundAllowUrl": false,
        "outboundAllowLocalPath": false,
        "outboundLocalRoots": [],
        "albumPolicy": "single-largest"
      }
    }
  }
}
```

## 排障

常用命令：

```bash
cjpm run --skip-build --name metis --run-args "gateway status"
cjpm run --skip-build --name metis --run-args "doctor"
cjpm run --skip-build --name metis --run-args "gateway channels health"
cjpm run --skip-build --name metis --run-args "gateway channels audit"
```

常见问题：

| 现象 | 检查项 |
|---|---|
| Telegram 没有回复 | 检查 `enabled`、token/tokenFile、proxy、gateway 是否已重启。 |
| 私聊收到 pairing 提示但不回复 | 执行提示中的 `metis pairing approve telegram <code>`，然后重新发消息。 |
| 群聊无响应 | 检查 `groups` 是否包含群 id、是否需要 @ bot、sender 是否在 allowFrom。 |
| 图片/文件/语音无法发送 | 检查对应 `actions.photo/document/audio/voice` 是否开启。 |
| URL 媒体无法发送 | 检查 `media.outboundAllowUrl`。 |
| 本地文件路径无法发送 | 检查 `media.outboundAllowLocalPath`、`media.outboundLocalRoots`、文件是否存在且位于白名单根目录内。 |
| 媒体未下载 | 检查 `media.downloadEnabled`、`mediaMaxBytes`、`allowedMimes`。 |
| Webhook 入站 403 | 检查 `webhookSecret` 与 Telegram 请求头是否一致。 |
