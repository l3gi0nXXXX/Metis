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
| `network.envProxyEnabled` | `false` | 是否允许 Telegram transport 读取 `HTTPS_PROXY` / `HTTP_PROXY`。显式 `proxy` 优先，`NO_PROXY` / `no_proxy` 可排除目标 host。 |
| `timeoutSeconds` | `30` | Bot API 请求超时秒数。 |
| `defaultTo` | `""` | 默认发送目标，通常由 Gateway session 自动推断。 |
| `configWrites` | `true` | 是否允许 Telegram 原生命令/callback 修改 Gateway 配置。设为 `false` 时，`/models` 选择只返回拒绝提示，不写 `metis.json`。 |

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

群聊 silent ingest 配置：

| 字段 | 默认值 | 说明 |
|---|---:|---|
| `groupHistoryEnabled` | `true` | 未提及 bot 而被 `group_mention_required` 拒绝的群消息，会作为有界上下文暂存，不触发 agent turn。下一条提及 bot 的消息会带上 `mediaContext.context.groupHistory`。 |
| `groupHistoryLimit` | `20` | 每个群/话题最多保留的 silent history 条数。 |

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
| `webhookCertPath` | `""` | 自签 webhook 证书路径。配置后 `setWebhook` 使用 multipart `certificate` 字段上传证书；为空时保持 JSON 注册。 |
| `webhookHost` | `127.0.0.1` | 本地 webhook server 监听 host。 |
| `webhookPort` | `8787` | 本地 webhook server 监听端口。 |
| `webhookPath` | `/telegram-webhook` | 本地 webhook path。 |

运行语义：

- polling 与 webhook 互斥。配置 `webhookUrl` 时不启动 polling runner；未配置时进入 polling，并在启动前调用 `deleteWebhook` 清理远端 webhook。
- polling stop/restart 时会按最后处理的 Telegram update id 做一次 `getUpdates(offset=last+1, limit=1)` 确认，降低重启后重复处理的概率。
- Telegram Bot API 返回 `parameters.retry_after` 时，Metis 会记录 `pollingLastRetryAfterSeconds` 诊断，供后续 backoff 和排障使用。
- `channels health` / runtime diagnostics 会暴露当前模式、webhook/polling 互斥状态、最后确认 offset 和支持的 update type 决策表。

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

媒体组和媒体编辑依赖对应媒体 action：

- `[media-group]` 中包含图片时需要 `actions.photo=true`。
- `[media-group]` 中包含视频、音频或文档时分别需要 `actions.video=true`、`actions.audio=true`、`actions.document=true`。
- `[edit-media]` 需要 `actions.editMessage=true`，并需要目标消息 id。

Poll 格式：

```text
[poll]
Lunch?
1. Rice
2. Noodles
durationSeconds=60
allowMultiselect=true
pollPublic=true
```

`durationSeconds` 支持 `5..600` 秒；`pollPublic=true` 等价于非匿名投票，`pollAnonymous=true` 等价于匿名投票。`durationHours` 与 OpenClaw 保持一致，不做自动换算，使用时会在网络请求前返回明确错误。

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

Telegram HTML 渲染支持常用轻量标记：`**bold**`、`*italic*`、`` `code` ``、`[label](https://...)`、引用行和 `||spoiler||`。Metis 会转义普通 HTML，避免未授权标签直接进入 Bot API。

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

下载成功或降级后，入站消息会附加 `[media-context]` block。该 block 会进入 Gateway session，让 agent 能看到媒体类型、下载路径、MIME、大小、caption 和可处理能力：

```text
[media-context]
channel=telegram
accountId=default
peerId=8734062810
messageId=101
mediaKind=photo
fileId=<telegram-file-id>
localPath=~/.metis/gateway-telegram/accounts/default/media/<file>
mimeType=image/jpeg
fileSize=123456
caption=please inspect this image
safetyStatus=downloaded
eligibleFor=vision
modelHandling=vision-input-ready
```

能力标记：

| 媒体 | `eligibleFor` | 说明 |
|---|---|---|
| `photo` | `vision` | 图片可作为视觉上下文；模型不支持视觉时保留路径和元数据。 |
| `voice` / `audio` | `transcription` | 语音/音频可作为转写输入；未配置 ASR 时保留元数据。 |
| `video` / `video_note` | `video-understanding` | 视频可作为视频理解输入；未配置视频理解时保留本地路径和元数据。 |
| `document` | `file-context` | 文本类文件直接预览；PDF/Office 等依赖 extractor 或 companion extract；不可读时保留元数据。 |
| `sticker` | `vision` / `metadata-only` | sticker 按 image-like 流程理解；描述会进入 sticker durable cache。 |

### 入站媒体理解工具

Gateway 会把当前 Telegram turn 的媒体对象注入 `mediaContext`。Agent 可以通过这些工具读取，不需要从可见聊天文本中解析 `fileId`：

| 工具 | 用途 | 无 provider 时行为 |
|---|---|---|
| `telegram_media_list` | 列出当前 turn 的结构化媒体对象。 | 返回空列表。 |
| `telegram_media_save` | 保存已下载媒体到用户指定路径。 | 未下载或路径受保护时返回错误，不写真实配置。 |
| `telegram_media_read` | 读取 text-like 文件。 | 二进制文件返回 `readable=false`。 |
| `telegram_image_analyze` | 图片/sticker 理解。 | 返回 `vision provider is not configured` 或建议配置视觉模型。 |
| `telegram_audio_transcribe` | voice/audio 转写。 | 返回 `ASRStatus=not_configured`。 |
| `telegram_video_describe` | video/video-note 描述。 | 返回 `videoUnderstandingStatus=not_configured`。 |
| `telegram_document_extract` | 文档抽取或预览。 | 返回 `metadata_only`。 |
| `telegram_sticker_search/get/cache_stats` | 查询当前上下文和 durable sticker cache。 | cache 为空时返回空结果。 |

当前 native runtime 会优先读取媒体记录中的已知字段和本地 companion 文件：

| 类型 | companion 文件 |
|---|---|
| 音频 | `<localPath>.transcript.txt`、`<localPath>.txt`、`<localPath>.transcript` |
| 图片/sticker | `<localPath>.analysis.txt`、`<localPath>.vision.txt`、`<localPath>.description.txt` |
| 视频 | `<localPath>.video.txt`、`<localPath>.analysis.txt`、`<localPath>.description.txt` |
| 文档 | text-like 文件直接读取；否则读取 `<localPath>.extract.txt`、`<localPath>.text.txt`、`<localPath>.preview.txt` |

这部分不引入 Node sidecar，也不绕过 Gateway/channel/session 架构。真正的 ASR、vision、video、document provider 未配置时，Metis 会明确返回 `not_configured` / `metadata_only`，不会猜测媒体内容。

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

### 出站媒体组

需要开启对应媒体类型的 action。媒体组会调用 Telegram Bot API `sendMediaGroup`，支持 2 到 10 个媒体项：

```text
[media-group]
item=photo|<telegram-file-id-or-local-path>|first caption
item=photo|<telegram-file-id-or-local-path>|second caption
```

也可以使用分块字段：

```text
[media-group]
type=photo
fileId=<telegram-file-id-or-local-path>
caption=first
---
type=photo
fileId=<telegram-file-id-or-local-path>
caption=second
```

当媒体项是白名单内本地路径时，Metis 会在 Telegram transport 内生成多文件 `multipart/form-data`，并在 `media` 数组中使用 `attach://fileN` 引用，不会通过 curl 或 sidecar 上传。

### 编辑媒体消息

需要开启 `actions.editMessage=true` 和对应媒体 action。编辑媒体会调用 Telegram Bot API `editMessageMedia`：

```text
[edit-media]
type=photo
fileId=<telegram-file-id-or-local-path>
caption=updated caption
```

目标消息 id 来自当前 `OutboundMessage.replyToMessageId`。如果没有目标消息 id，发送会在网络请求前失败并返回明确错误。

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
- 媒体组和媒体编辑中的本地文件同样遵守本地路径白名单，不允许裸露任意本机路径。

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

Metis 会对收到的 callback 调用 Telegram Bot API `answerCallbackQuery`，避免 Telegram 客户端按钮一直处于加载状态。审批 callback 被接受后，Metis 会尝试通过 `editMessageReplyMarkup` 清理原消息上的审批按钮，避免用户重复点击。

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

审批 callback 会在 GatewayService 中解析并写入 Gateway approval store。TelegramAdapter 只负责把 Bot API callback 转成 `[telegram-approval]` 入站事件，不直接修改审批状态。

## Draft / Preview

开启 `actions.editMessage=true` 后，可用 `[draft]` 先发送预览文本，再通过 `editMessageText` 收敛为最终文本。该能力用于长任务或长回复的预览/最终态收口。

```text
[draft]
preview=Working...
final=Done
```

如果 `final` 为空，或未开启 `actions.editMessage`，发送会在网络请求前失败并返回明确错误。

Gateway delivery streaming 会把 answer 和 reasoning 分成两条 lane：

| Lane | 行为 |
|---|---|
| `answer` | 可发送 preview update，并通过 edit 收敛成最终答案。Telegram 发送失败时，应 fallback 为普通最终消息。 |
| `reasoning` | 只在当前 session 配置允许 reasoning 可见时发送；默认不把隐藏 reasoning 暴露到 Telegram。 |

`streaming` / `blockStreaming` 配置用于控制是否发送中间态。即使 streaming 失败，最终回复也不能丢失。测试应使用 fake Gateway delivery event 和 TelegramAdapter mock 验证，不需要真实 Telegram 网络。

## Reactions

配置：

```json
{
  "gateway": {
    "telegram": {
      "reactionNotifications": "all",
      "reactionLevel": "ack",
      "ackReaction": "👀",
      "removeAckAfterReply": false,
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
| `removeAckAfterReply` | `false` | 回复成功后是否通过空 `setMessageReaction` 移除 ack reaction。失败会降级，不影响正常回复。 |

出站 reaction 格式：

```text
[reaction]
token=👍
render=👍
```

移除 reaction：

```text
[reaction]
remove=true
render=remove
```

状态 reaction 可使用 OpenClaw 同名生命周期字段，Metis 会映射为 Telegram 支持的 emoji 并保留 `available_reactions` fallback：

```text
[reaction]
status=thinking
```

支持的状态名：`queued`、`thinking`、`tool`、`coding`、`web`、`done`、`error`、`stallSoft`、`stallHard`、`compacting`。

入站 reaction 是 session system event，不是普通用户消息。启用 `reactionNotifications=all` 后，Metis 可接收 Telegram `message_reaction` update，记录 reaction 摘要、sender、message id 和授权状态；授权 reaction 不应触发新的 agent turn，也不应让模型对一个 emoji 单独回复。未授权 sender 的 reaction 会被忽略或记录为拒绝诊断。

自动 ack/status reaction 与入站 reaction 语义独立：`reactionLevel=ack` 只控制 Metis 对收到消息设置处理状态，不改变用户 reaction 是否会进入模型。

## Inbound Debounce

Telegram 长文本、转发 burst 和跨 polling 批次到达的相邻消息可能属于同一次用户输入。Metis 的 debounce 目标是按 account/chat/thread/sender/lane 合并这些片段，再生成一次 Gateway inbound turn。

合并边界：

- 同一 sender、同一 chat、同一 topic/thread、同一 debounce lane 才能合并。
- 接近 Telegram 长文本限制的分片可短时间等待后续片段。
- forward burst 使用独立 lane，不和普通文本混合。
- slash command、callback、media group 不应被 debounce 延迟或并入普通文本。

验收必须使用 fake polling batch/timer，不使用真实 Telegram 网络。测试要覆盖跨 polling 批次合并、不同 sender 不合并、`/command` 不延迟、media group 原有合并不回退。

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

Telegram Bot API 对 command menu 有数量和描述长度限制。Metis 同步菜单前会把命令裁剪到 100 条，并把 description 裁剪到 256 字符；同步时会先 `deleteMyCommands` 再 `setMyCommands`，未变化的菜单会按 payload hash 跳过重复同步。如果 Telegram 返回命令过多错误，Metis 会降级裁剪到 80 条后重试一次。被裁剪的配置不会绕过 Gateway 执行，也不会让启动流程因为 `setMyCommands` payload 过大而中断。

内置 command menu 当前包含：

- `/help`
- `/status`
- `/commands`
- `/tools`
- `/whoami`
- `/models`
- `/model`
- `/subagents`
- `/sessions`
- `/session`
- `/new`
- `/reset`
- `/compact`
- `/think`
- `/reasoning`
- `/fast`
- `/verbose`
- `/approvals`
- `/activation`
- `/pair`

Telegram native command 由 Gateway 统一解析、鉴权、回复和记录，不进入大模型对话路径。实现状态按用户可见能力分为以下几类：

| 命令 | 行为 | 权限与安全边界 |
|---|---|---|
| `/help`、`/commands`、`/status`、`/whoami` | 返回 Telegram channel 的帮助、命令清单、运行状态和当前身份。 | 授权 sender 可用；输出会脱敏 token、secret、password、authorization。 |
| `/tools`、`/subagents`、`/activation` | 返回 Gateway 工具、subagent 和激活状态摘要。 | 只读视图，不修改配置。 |
| `/models`、`/model` | 展示和切换 Telegram channel 绑定模型。 | 切换需要授权 sender，且 `configWrites=true`；否则只返回拒绝原因。 |
| `/sessions`、`/session` | 展示 Telegram 可见 session、当前绑定和 transcript 摘要。 | 只返回摘要，不暴露系统提示全文、token 或本机敏感路径。 |
| `/approvals` | 展示 pending approvals 和可用 callback 操作。 | approval id、动作和 requester 可见；敏感参数必须脱敏。 |
| `/allowlist` | 管理 Telegram DM/group allowlist 和 pairing store。 | `list` 可只读返回；`add/remove` 修改持久配置时必须走 Gateway approval，并且测试只能写临时配置。 |
| `/config`、`/mcp`、`/plugins`、`/debug` | 读操作直接返回结构化摘要；写操作创建 Gateway approval。 | 不直接从 Telegram 消息改配置或启停插件；批准后才走 Gateway 配置或 plugin 控制面。 |
| `/bash`、`/restart` | 高风险操作只创建 approval。 | 未批准前不得执行 shell 或重启；批准、拒绝和过期都要有审计记录。 |
| `/stop` | 取消当前 Telegram session 的 active run。 | 只影响当前 session 绑定的 run，不取消其他 channel/session。 |
| `/skill` | 通过 Metis skill registry 运行显式 skill。 | disabled/missing skill 返回确定性错误；不让模型猜测命令。 |
| `/btw` | 运行一次 transient side question。 | 可读取当前上下文，但不把 BTW 问答写回主 session transcript。 |
| `/tts` | 管理 TTS 开关、provider、limit、summary，并在 provider configured 时生成 audio/voice。 | 无 provider 时返回 `not_configured` 诊断；音频文件写入临时目录或用户显式配置目录。 |
| `/new`、`/reset`、`/compact`、`/think`、`/reasoning`、`/fast`、`/verbose`、`/pair` | session 生命周期、上下文压缩、reasoning/verbosity 和 pairing 命令。 | 只对当前 Telegram sender/session 生效；pairing code 不应写入日志。 |

开启 `actions.inlineKeyboard=true` 和 `actions.callbackQuery=true` 后，`/models` 会返回 Telegram inline buttons。点击模型按钮后，Gateway 会校验 sender 是否在 `allowFrom` / `groupAllowFrom` 中；仅当 `configWrites=true` 时，才会通过现有 `gateway.channelModels.telegram` 写入路径切换 Telegram channel 绑定模型。TelegramAdapter 不直接写配置。

### 权限、Approval 与审计

Telegram 入站先经过 `dmPolicy`、`groupPolicy`、`allowFrom`、`groupAllowFrom`、`groups` 和 pairing store 鉴权。未授权 sender 调用 native command 时，Metis 返回拒绝结果或 pairing 提示，不会把原文送入 agent。

需要写配置、运行 shell、重启 Gateway、启停插件或修改 debug/mcp/config 的命令必须创建 Gateway approval。approval callback 使用 Telegram inline keyboard 承载，callback 入站后由 GatewayService 更新 approval store；TelegramAdapter 只负责 `answerCallbackQuery`、清理按钮和发送结果。approval 过期、重复点击或 sender 不匹配时必须拒绝，并记录可排障的审计状态。

所有审计和测试输出都不得记录 Telegram bot token、proxy password、authorization header、approval secret、pairing code 全文或用户真实媒体目录。

### TTS

`/tts` 面向 Telegram native command 使用，不通过模型猜测语音行为。推荐子命令：

| 子命令 | 行为 |
|---|---|
| `/tts status` | 显示 TTS enabled、provider、limit、summary 和 voice/audio 发送能力。 |
| `/tts on` / `/tts off` | 开关当前 Telegram sender/session 的 TTS 偏好。 |
| `/tts provider <name>` | 设置 provider；provider 不存在时返回 `not_configured` 或 `not_found`。 |
| `/tts limit <chars>` | 设置单次输入字符上限。 |
| `/tts summary on|off` | 控制是否对长回复生成摘要语音。 |
| `/tts audio <text>` | provider configured 时生成临时音频，并按配置通过 `sendVoice` 或 `sendAudio` 发送。 |

TTS 生成文件只能写入临时目录、测试 fixture 目录或用户显式配置的安全目录；不得默认写入真实用户媒体归档。无 provider 时应返回可操作诊断，而不是静默失败。

## OpenClaw Plugin Compatibility

OpenClaw 插件兼容使用 Gateway 管理的 Node sidecar，不替换 Telegram transport，不绕过 Gateway/channel/session/ReAct/toolset 架构。未启用 sidecar 时，`plugin:` / `plugin-approval:` callback 会返回明确的 `not_applicable`，不会落入大模型路径。

配置示例：

```json
{
  "gateway": {
    "channelsExtra": {
      "openclawPluginCompatibility": {
        "enabled": true,
        "nodeCommand": "node",
        "scriptPath": "/Users/l3gi0n/work/workspace_cangjie/Metis/scripts/openclaw-plugin-sidecar.mjs",
        "timeoutMs": 10000,
        "plugins": [
          "/absolute/path/to/openclaw-plugin"
        ]
      }
    }
  }
}
```

当前 sidecar bridge 覆盖：

- OpenClaw-style `registerInteractiveHandler`，Telegram `plugin:*` callback 经 Gateway 分发给 sidecar。
- OpenClaw-style plugin approval handler，Telegram `plugin-approval:*` callback 经 Gateway 分发给 sidecar。
- OpenClaw-style plugin command catalog，启用后会合并到 Telegram command menu 和 `/commands`。
- `message_sending` / `message_sent` hooks，发送前可修改或取消文本，发送后只作为观察事件，不允许改发目标 peer。

兼容限制：

- sidecar 是 Metis 的 OpenClaw-style plugin compatibility host，不是 OpenClaw in-process plugin runtime。
- plugin callback 支持 `reply`、`editMessage`、`editButtons`、`clearButtons`、`deleteMessage`、`answerCallbackQuery` 这类 Telegram 交互子集；依赖完整 OpenClaw SDK/runtime object 的插件可能返回 `unsupportedCapability`。
- plugin command 和 hooks 收到的是 Metis Gateway/channel 字段转换后的 payload；内部 delivery progress、完整 runtime config 和未映射 API 不保证等价。
- hook 失败不得阻断普通 Telegram 发送，错误应记录到 Gateway 审计/诊断。
- 所有插件 UI 文案应称为 Metis；不得把用户可见产品名写成 OpenClaw。

测试和生产都必须保证 sidecar 不写真实 `~/.metis/metis.json`。插件输出仍由 Gateway 生成 `OutboundMessage`，再交给 Telegram adapter 发送。

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
- `directory`：`defaultTo`、已配置 groups、accounts、已批准 pairing sender、session/delivery 历史、可推断 targets 与统一 `rows`。
- `accountOps`：setup、probe、directory、logout 等操作能力声明。

`directory.rows` 的统一字段包括：

- `kind`: `user` / `group` / `topic`
- `id`
- `displayName`
- `accountId`
- `source`: `config` / `pairing` / `session-catalog` / `delivery-history`
- `lastSeenAtMs`
- `sessionKey`
- `canSend`
- `policyState`

这些字段是只读投影；真实配置修改仍必须走 Gateway 配置更新路径，测试和运行态都不应直接改写真实 `~/.metis/metis.json`。

### Target writeback

Metis 提供受控的 Telegram target writeback 工具，用来把已确认的 Telegram 目标写入 `gateway.telegram.defaultTo`：

| 工具 | 行为 | 配置写入 |
|---|---|---|
| `telegram_target_writeback_dry_run` | 预览 `gateway.telegram.defaultTo` 将被写成什么。 | 不写入。 |
| `telegram_target_writeback_apply` | 通过 `MetisConfigManager` 写入 `gateway.telegram.defaultTo`。 | 需要 `operator.admin` scope。 |

`@username` 目标必须先解析出 numeric chat id，再把 `resolvedChatId` 传给 writeback 工具。未授权、未解析或无法规范化的 target 会返回 `denied` / `error`，不会改写配置。测试必须使用临时 `METIS_HOME`，禁止读写真实 `~/.metis/metis.json`。

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
| `dnsResultOrder` | `ipv4first` | DNS 结果偏好。该值会传入 Telegram native transport；受 Cangjie stdx socket resolver 能力限制时，`channels health` / diagnostics 会明确提示。 |
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

`channels health` / `channels runtime` 会暴露 Telegram 能力状态，例如：

- `mediaUnderstandingState`
- `approvalResolverState`
- `lastDraftState`
- `directoryAggregationState`
- `modelButtonState`

`doctor` / `channels audit` 会检查 token、webhook secret、proxy、媒体下载限制、本地媒体白名单、高风险 action、approval resolver、streaming draft、directory aggregation 等项。

Telegram audit 还应覆盖 live membership/security 项：

| 项 | 行为 |
|---|---|
| `getMe` | 确认 bot 身份、token 是否有效；错误输出必须脱敏 token。 |
| `getChatMember` | 对配置中的群、topic 目标或已知 target 做 membership probe。`member` / `administrator` 为 ok，`left` / `kicked` 为 warning。 |
| webhook/polling | 检查 webhook 与 polling 互斥、最后 offset、retry_after、allowed updates。 |
| security | 检查 open policy、高风险 action、本地媒体白名单、proxy、private network、approval resolver。 |

真实 Telegram doctor 需要用户显式配置 bot token 和目标 chat。CI 和回归测试必须使用 mock `getMe` / `getChatMember`，不得访问真实 Telegram 网络。

ASR、vision、video、document extractor 都走 Gateway media understanding runtime。没有配置 provider/extractor 时，工具和 prompt 会返回 `not_configured` 或 `metadata_only`，不会绕过 Gateway 直接调用模型，也不会猜测媒体内容。

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

## 回归验收与测试隔离

Telegram 文档和 T53 mock 回归的验收边界：

- 所有自动化测试使用临时 HOME、临时 `METIS_HOME`、临时 Metis config path、fake token、mock Telegram Bot API、mock Gateway/plugin/TTS provider。
- 自动化测试不得读取或写入真实 `~/.metis/metis.json`、真实 `~/.metis/gateway-telegram`、真实 token 文件或真实用户媒体目录。
- 媒体下载、媒体保存、TTS 音频、allowlist 写入、target writeback、plugin sidecar 都必须写临时目录或用户显式配置目录。
- CI 不需要真实 Telegram 网络；真实 bot token smoke test 只能由用户显式配置后手动执行。
- 日志、审计、测试断言不得包含 bot token、proxy password、authorization header、approval secret 或 pairing code 全文。

建议的 mock 回归集合：

| 能力 | 验收方式 |
|---|---|
| native command catalog | `/commands` 中每个 command 都有 handler 状态和确定性回复。 |
| approval | `/allowlist add/remove`、`/config set/unset`、`/mcp set/unset`、`/plugins enable/disable`、`/debug` mutation、`/bash`、`/restart` 未批准前不写配置、不执行。 |
| TTS | 无 provider 返回 `not_configured`；fake provider 写临时 audio 并调用 `sendVoice` / `sendAudio` mock。 |
| reaction | `message_reaction` 只写 system event，不调用 AgentBridge。 |
| streaming | answer/reasoning lane 使用 preview/edit mock 验收，reasoning off 时不发送 reasoning lane。 |
| debounce | 长文本跨 polling 批次合并；slash command、callback、media group 不被延迟。 |
| audit | `getChatMember` member/admin/left/kicked/error 全部 mock 覆盖，错误不泄露 token。 |
| plugin compatibility | fake plugin callback、command、hooks 和 `unsupportedCapability` 都有断言。 |
