# Metis Speech TTS Failure Debug Record 2026-05-10

## 用户反馈

用户通过 Telegram 发送语音后，Metis 已能识别语音内容，但回复为：

```text
语音暂时发送失败，我先打字陪你。
```

需要确认是否 TTS 挂了。

## 排查结论

TTS 没有卡死；当前行为是 TTS provider 调用失败后，Metis 按 `gateway.speech.tts.degradeMessage` 降级为文本。

直接原因是当前配置把 DashScope `qwen3-tts-flash` 配成 `kind=openai-compatible`，Metis 因此调用：

```text
https://dashscope.aliyuncs.com/api/v1/audio/speech
```

但该 endpoint 返回 404。`qwen3-tts-flash` 的 DashScope 官方 API 不是 OpenAI `/audio/speech` 形态，而是 DashScope multimodal-generation endpoint：

```text
https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
```

国际站 endpoint 对应：

```text
https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
```

## 本机日志证据

最新 Gateway 日志：

```text
Gateway.inbound: channel=telegram ... text='[voice] ... understandingStatus=ok ... modelHandling=asr-input-ready'
Gateway model timing: channel=telegram ... status=success ... answerChars=74
Telegram auto TTS reply synthesized: payloadKind=text
```

含义：

1. Telegram 入站语音已进入 Gateway。
2. ASR 成功，`understandingStatus=ok`。
3. 模型正常生成回复。
4. 自动 TTS 运行了，但返回 `payloadKind=text`，说明进入了 TTS 降级分支，而不是生成 `[voice]` payload。

## 配置证据

脱敏后的当前配置核心字段：

```json
{
  "gateway": {
    "speech": {
      "tts": {
        "enabled": true,
        "provider": "dashscope",
        "degradeMessage": "语音暂时发送失败，我先打字陪你。",
        "providers": {
          "dashscope": {
            "kind": "openai-compatible",
            "baseUrl": "https://dashscope.aliyuncs.com/api/v1",
            "model": "qwen3-tts-flash",
            "voice": "Chelsie",
            "responseFormat": "opus",
            "timeoutMs": 60000,
            "insecureSkipTlsVerify": true
          }
        }
      }
    },
    "telegram": {
      "speech": {
        "tts": { "provider": "dashscope" },
        "audioAsVoice": true,
        "autoReplyToVoice": true
      }
    }
  }
}
```

## 复现命令结果

使用当前配置的 `baseUrl`，按 Metis openai-compatible TTS runtime 的拼接规则请求：

```bash
POST https://dashscope.aliyuncs.com/api/v1/audio/speech
```

结果：

```text
format=opus http=404 size=0
format=mp3 http=404 size=0
```

将 `baseUrl` 临时改为 OpenAI-compatible 常见 DashScope endpoint 后请求：

```bash
POST https://dashscope.aliyuncs.com/compatible-mode/v1/audio/speech
```

结果：

```text
format=opus http=404 size=0
format=mp3 http=404 size=0
```

这说明 `qwen3-tts-flash` 当前不能通过 Metis 已实现的 `/audio/speech` TTS path 使用。

## 参考项目证据

| 来源 | 位置 | 结论 |
|---|---|---|
| OpenClaw OpenAI TTS | `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/tts.ts:107-166` | OpenAI-compatible TTS 明确 `POST ${baseUrl}/audio/speech`，body 为 `model/input/voice/response_format`。 |
| OpenClaw 自定义 endpoint | `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/tts.ts:39-58` | 自定义 `baseUrl` 放宽 model/voice 校验，但 endpoint 仍必须兼容 `/audio/speech`。 |
| OpenClaw speech provider 边界 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/speech-provider.ts:126-201` | provider 负责生成音频 buffer 和格式元数据，不直接调用 IM adapter。 |
| Hermes 多 provider | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:91-142` | 不同 provider 有独立默认值和限制，不应强行统一为一个 HTTP 形态。 |
| Hermes OpenAI TTS | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:349-390` | OpenAI TTS 走 OpenAI `audio.speech.create` 形态。 |
| Hermes 非 OpenAI endpoint | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:397-410` | xAI 等非 OpenAI audio.speech endpoint 单独实现；DashScope/Qwen TTS 也应是独立 kind。 |
| Hermes Telegram voice | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:954-974` | Telegram 场景优先 `.ogg`/Opus，但 provider 选择和平台投递仍分层。 |
| Hermes Telegram adapter | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/gateway/platforms/telegram.py:1722-1760` | 平台 adapter 根据扩展名发送 voice/audio。 |
| OpenClaw-China QQBot outbound | `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/qqbot/src/outbound.ts:189-234` | 音频在出站层识别为 voice 并可记录 `transcriptSource="tts"`。 |
| OpenClaw-China WeCom channel | `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/wecom-app/src/channel.ts:537-572` | 通道层负责平台 voice 转码和 fallback，provider 不应知道平台发送 API。 |
| Metis TTS runtime | `src/core/gateway_speech_tts_runtime.cj:147-155`、`:213-244`、`:489-503`、`:590` | 当前 `openai-compatible` 只构造 `/audio/speech` 请求；失败且有 `degradeMessage` 时会返回 `payloadKind=text`。 |

## 官方接口证据

Alibaba Cloud Model Studio 官方 Qwen TTS API 文档说明，`qwen3-tts-flash` 调用 endpoint 为：

```text
https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
```

中国内地北京区域替换为：

```text
https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
```

官方请求体形态包含：

```json
{
  "model": "qwen3-tts-flash",
  "input": {
    "text": "...",
    "voice": "...",
    "language_type": "..."
  }
}
```

因此 Metis 当前 `openai-compatible` TTS provider 的请求形态不适配 `qwen3-tts-flash`。

## 后续建议

1. 短期配置修正：如果继续使用 Metis 当前 `openai-compatible` provider，应换成真正支持 `/audio/speech` 的 TTS 服务和 baseUrl。
2. 完整实现：新增 DashScope/Qwen TTS provider kind，例如 `dashscope-qwen-tts`，按官方 `multimodal-generation/generation` 请求形态实现。
3. 不能把当前问题归因到 Telegram sendVoice 或 ASR；日志已经证明 ASR、模型回复、自动 TTS 触发都正常，失败点在 TTS provider 请求。
4. 后续代码落地必须新增测试：DashScope Qwen TTS request body、404/provider_error、degradeMessage、Telegram voice input 自动 TTS、以及不得泄露 API key。

## 2026-05-10 10:16 Telegram voice 复测排查记录

用户在 Telegram 发送 voice 后仍收到：

```text
语音暂时发送失败，我先打字陪你。
```

### 证据

1. 最新入站日志存在，说明 Telegram polling、下载、ASR 和模型回复链路均进入 Gateway：

```text
~/.metis/logs/2026_05_10-10_16_31_804012000.log:208
Gateway.inbound: channel=telegram ... text='[voice] ... mediaKind=voice ... telegramFilePath=voice/file_27.oga'
```

2. 模型调用成功：

```text
~/.metis/logs/2026_05_10-10_16_31_804012000.log:302
Gateway model timing: channel=telegram ... status=success ... answerChars=54
```

3. 自动 TTS 被触发，但输出为降级文本：

```text
~/.metis/logs/2026_05_10-10_16_31_804012000.log:305
Telegram auto TTS reply synthesized: payloadKind=text
```

4. 运行二进制不是旧构建产物。`strings target/release/bin/metis` 可检索到：

```text
dashscope-qwen-tts
/services/aigc/multimodal-generation/generation
```

5. 实际运行配置仍把 `qwen3-tts-flash` 配成 `openai-compatible`：

```json
{
  "gateway": {
    "speech": {
      "tts": {
        "provider": "dashscope",
        "providers": {
          "dashscope": {
            "kind": "openai-compatible",
            "baseUrl": "https://dashscope.aliyuncs.com/api/v1",
            "model": "qwen3-tts-flash"
          }
        }
      }
    }
  }
}
```

### 根因

代码已包含 DashScope/Qwen TTS provider，但用户本机 `~/.metis/metis.json` 仍使用旧配置：

```text
gateway.speech.tts.providers.dashscope.kind=openai-compatible
```

因此运行时仍会把 `qwen3-tts-flash` 当作 OpenAI-compatible `/audio/speech` provider 调用，失败后按配置返回 `degradeMessage`，最终 Telegram 收到文本：

```text
语音暂时发送失败，我先打字陪你。
```

### 已执行修正

已备份用户配置：

```text
~/.metis/metis.json.bak.20260510101853
```

并将运行配置改为：

```json
{
  "kind": "dashscope-qwen-tts",
  "baseUrl": "https://dashscope.aliyuncs.com/api/v1",
  "model": "qwen3-tts-flash",
  "voice": "Chelsie",
  "languageType": "Chinese"
}
```

随后重启 Gateway，新进程：

```text
2026-05-10T10:19:20
/Users/l3gi0n/work/workspace_cangjie/Metis/target/release/bin/metis gateway serve
```

新日志文件：

```text
~/.metis/logs/2026_05_10-10_19_20_181310000.log
```

### 验收项

1. Telegram 发送 `/tts status`，应看到当前 provider kind 为 `dashscope-qwen-tts`，且 status 为 `ok`。
2. Telegram 发送 `/tts audio 你好，这是 Metis 的 Qwen TTS 测试`，应收到 voice/audio，不应收到 degradeMessage。
3. Telegram 发送 voice，ASR 成功后自动回复应为 voice；日志应出现：

```text
Telegram auto TTS reply synthesized: payloadKind=voice
```

4. 若仍失败，优先查看新日志中的 DashScope provider reasonCode，而不是继续排查 Telegram sendVoice 或 ASR。
