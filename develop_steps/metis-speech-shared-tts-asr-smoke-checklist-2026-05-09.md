# Metis Speech Shared TTS/ASR Smoke Checklist 2026-05-09

## Scope

This checklist verifies Phase 6 documentation and the shared Gateway Speech target:

- `gateway.speech.tts/asr` provides shared defaults for IM channels.
- `gateway.<channel>.speech.tts/asr` overrides shared defaults; Telegram uses `gateway.telegram.speech.tts/asr`.
- TTS/ASR provider logic stays in Gateway Speech runtime; IM adapters only download, store, and send platform media.
- Smoke tests must not use real Telegram tokens, real bot network, real cloud credentials, or real user files under `~/.metis` unless the manual test explicitly says the operator has provided a disposable test setup.

Evidence used for this checklist:

- OpenClaw TTS docs: `/Users/l3gi0n/work/workspace_cangjie/openclaw/docs/tts.md` documents `messages.tts.providers.<id>`, provider fallback, OpenAI-compatible base URL behavior, `/tts` commands, and voice-note format guidance.
- OpenClaw OpenAI TTS source: `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/tts.ts:107-166` shows `/audio/speech` request shape; `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/speech-provider.ts:126-201` keeps provider synthesis separate from IM delivery.
- Hermes TTS source: `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:91-142`, `:349-390`, `:397-410`, and `:954-974` show provider-specific implementations and Telegram-friendly output selection.
- Hermes Telegram delivery source: `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/gateway/platforms/telegram.py:1722-1760` sends voice/audio at platform layer.
- OpenClaw-China outbound sources: `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/qqbot/src/outbound.ts:189-234` and `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/wecom-app/src/channel.ts:537-572` keep provider audio generation separate from channel-specific voice handling.
- OpenClaw-China QQBot ASR docs: `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/doc/guides/qqbot/configuration.md` documents Tencent Flash ASR (`asr/flash/v1`) and required `appId`, `secretId`, `secretKey`.
- Hermes config example: `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/cli-config.yaml.example` documents messaging STT providers including local, Groq, OpenAI, and Mistral.
- Metis source: `src/core/gateway_speech_config.cj` resolves shared speech config and channel speech overrides; `src/core/gateway_speech_tts_runtime.cj` handles `openai-compatible`, `command`, fallback attempts, `too_large`, `auth_error`, `timeout`, `provider_error`, and `degraded`; `src/core/gateway_speech_asr_runtime.cj` handles command ASR, `too_large`, `timeout`, and provider errors.

## Required Test Configuration Shape

Use placeholders only. Never paste real keys into this file, test fixtures, logs, or chat.

```json
{
  "gateway": {
    "speech": {
      "tts": {
        "enabled": true,
        "provider": "dashscope",
        "fallbackProviders": ["edge-command"],
        "providers": {
          "dashscope": {
            "kind": "dashscope-qwen-tts",
            "baseUrl": "https://dashscope.aliyuncs.com/api/v1",
            "apiKey": "${DASHSCOPE_API_KEY}",
            "model": "qwen3-tts-flash",
            "voice": "Chelsie",
            "languageType": "Chinese",
            "timeoutMs": 60000
          },
          "openai-tts-compatible": {
            "kind": "openai-compatible",
            "baseUrl": "https://api.openai.com/v1",
            "apiKey": "${OPENAI_TTS_API_KEY}",
            "model": "gpt-4o-mini-tts",
            "voice": "coral",
            "responseFormat": "opus",
            "timeoutMs": 60000
          },
          "edge-command": {
            "kind": "command",
            "command": ["edge-tts", "--text", "{text}", "--write-media", "{output}"],
            "outputExtension": "mp3",
            "timeoutMs": 10000
          }
        },
        "degradeMessage": "语音暂时发送失败，我先打字陪你。"
      },
      "asr": {
        "enabled": true,
        "provider": "openai-asr",
        "fallbackProviders": ["tencent-flash", "local-command"],
        "maxBytes": 26214400,
        "providers": {
          "openai-asr": {
            "kind": "openai-compatible",
            "baseUrl": "https://api.openai.com/v1",
            "apiKey": "${OPENAI_ASR_API_KEY}",
            "model": "whisper-1",
            "timeoutMs": 60000
          },
          "openrouter-whisper": {
            "kind": "openai-compatible",
            "baseUrl": "https://openrouter.ai/api/v1",
            "apiKey": "${OPENROUTER_API_KEY}",
            "model": "openai/whisper-large-v3-turbo",
            "requestFormat": "openrouter-input-audio-json",
            "timeoutMs": 60000,
            "maxBytes": 26214400
          },
          "tencent-flash": {
            "kind": "tencent-flash",
            "appId": "${TENCENT_ASR_APP_ID}",
            "secretId": "${TENCENT_ASR_SECRET_ID}",
            "secretKey": "${TENCENT_ASR_SECRET_KEY}",
            "engineType": "16k_zh",
            "timeoutMs": 60000,
            "maxBytes": 26214400
          },
          "local-command": {
            "kind": "command",
            "command": ["python3", "/tmp/metis-test-transcribe.py", "{input}"],
            "timeoutMs": 60000
          }
        }
      }
    },
    "telegram": {
      "speech": {
        "tts": {
          "provider": "dashscope"
        },
        "asr": {
          "provider": "tencent-flash"
        },
        "audioAsVoice": true,
        "autoReplyToVoice": true
      }
    }
  }
}
```

## Automated Tests

| ID | Area | Test | Expected result | Evidence to record |
|---|---|---|---|---|
| AUTO-SPEECH-01 | Config priority | Unit test resolves `gateway.telegram.speech.tts.provider` over `gateway.speech.tts.provider` while preserving shared providers. | Telegram provider wins; shared provider map remains available for fallback. | Test name and output. |
| AUTO-SPEECH-02 | Config priority | Unit test resolves `gateway.telegram.speech.asr.provider` over `gateway.speech.asr.provider`. | Telegram ASR provider wins; shared providers remain available. | Test name and output. |
| AUTO-SPEECH-03 | TTS DashScope Qwen | Fake HTTP runner receives `POST https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation` for `qwen3-tts-flash`; body contains `input.text`, `input.voice=Chelsie`, and `input.language_type=Chinese`. | Returns `[voice]` or `[audio]` payload and writes temp audio bytes; request/body contain no Telegram fields or API key. | Fake server assertions; no API key in logs. |
| AUTO-SPEECH-03B | TTS OpenAI-compatible | Fake HTTP runner receives `POST ${baseUrl}/audio/speech` for a real `/audio/speech` compatible provider such as `openai-tts-compatible`. | Existing OpenAI-compatible provider still returns `[voice]` payload and writes `.opus` audio bytes. | Fake server assertions; no API key in logs. |
| AUTO-SPEECH-04 | TTS auth | Fake HTTP runner returns 401/403. | Status is `auth_error`; `${DASHSCOPE_API_KEY}` value is not logged or returned. | Test output and redaction assertion. |
| AUTO-SPEECH-05 | TTS timeout/provider error | Fake runner or command timeout and 500 path. | Status is `timeout` or `provider_error`; attempts include provider, kind, outcome, reasonCode, latency. | Test output. |
| AUTO-SPEECH-06 | TTS fallback/degraded | Primary provider fails; fallback command succeeds, then all providers fail with `degradeMessage`. | First case sends fallback audio; second case returns text payload with status `degraded`. | Test output. |
| AUTO-SPEECH-07 | TTS too large | Input exceeds `maxChars`. | Status is `too_large`; no provider network or command call happens. | Test output. |
| AUTO-SPEECH-08 | ASR OpenAI-compatible | Fake transcription endpoint receives media file and model. | Transcript is returned; empty transcript maps to `empty_result` after provider support lands. | Test output; no `${OPENAI_ASR_API_KEY}` value in logs. |
| AUTO-SPEECH-09 | ASR Tencent Flash | Fake Tencent Flash endpoint validates signing inputs without using real credentials. | Request path matches `asr/flash/v1`; auth failure maps to `auth_error`; server failure maps to `provider_error`. | Test output; no `${TENCENT_ASR_SECRET_KEY}` value in logs. |
| AUTO-SPEECH-10 | ASR command fallback | Local command fixture receives `{input}`, `{mime}`, `{output}`, `{outputDir}`. | Transcript is returned from stdout or output file; timeout maps to `timeout`; too large maps to `too_large`. | Test output. |
| AUTO-SPEECH-11 | Media tool | Telegram `telegram_audio_transcribe` uses resolved shared ASR and Telegram override ASR. | Voice/audio/file inputs route through Gateway ASR runtime, not model guessing. | Test output. |
| AUTO-SPEECH-12 | Message/TTS tool | Model-visible `tts` tool returns structured voice/audio payload and marks visible reply delivered. | No duplicate text reply after successful voice/audio send. | Test output. |
| AUTO-SPEECH-13 | Restart recovery | Persisted Telegram TTS/session prefs survive Gateway restart in temp config. | `/tts status` after restart shows expected provider, enabled state, limit, and summary preference. | Test output using temp config path. |
| AUTO-SPEECH-14 | Docs guard | Run `rg -n "gateway\\.speech\\.tts|gateway\\.telegram\\.speech\\.tts|dashscope-qwen-tts|openai-compatible|tencent-flash|qwen3-tts-flash|DASHSCOPE_API_KEY|TENCENT_ASR" docs/user/telegram.md develop_steps`. | Required strings are present; matches contain placeholders only, not real keys. | Command output. |

## Manual Tests

Manual tests require a disposable Telegram bot, authorized sender, temp Metis config, and explicit operator-provided cloud credentials in environment variables only. Do not write real tokens or keys into this checklist.

| ID | Area | Steps | Expected result | Result |
|---|---|---|---|---|
| MANUAL-SPEECH-01 | Text TTS | Send `发一条语音信息给我，随便说点什么。` to Telegram. | Model calls `tts`; Telegram receives one voice/audio message; no duplicate plain text after success. | Pending |
| MANUAL-SPEECH-02 | `/tts status` | Run `/tts status` with provider `dashscope` configured as `kind=dashscope-qwen-tts`. | Status shows providerKind `dashscope-qwen-tts` and status `ok`; no secret value is printed. | Pending |
| MANUAL-SPEECH-03 | `/tts audio` | Run `/tts audio 你好，这是 Metis 的 Qwen TTS 测试`. | Provider generates audio; Telegram receives voice if `audioAsVoice=true`, audio file otherwise. | Pending |
| MANUAL-SPEECH-04 | Voice input ASR | Send a short Telegram voice message. | Gateway logs inbound media, downloads it, ASR returns transcript, model answers based on transcript. | Pending |
| MANUAL-SPEECH-05 | Audio file ASR | Send an `.ogg`, `.mp3`, or `.m4a` audio file. | File is saved to safe temp/media path, ASR transcript is visible to the session, oversized file returns `too_large`. | Pending |
| MANUAL-SPEECH-06 | Generic file handling | Send a non-audio file and an audio file with ambiguous mime. | Non-audio is not sent to ASR; audio-like file is either transcribed or gets a clear unsupported/diagnostic status. | Pending |
| MANUAL-SPEECH-07 | Subagent | Start a Telegram request that delegates to a subagent and asks for voice output. | Subagent result can be summarized and delivered through the Gateway `tts` tool without bypassing session/tool boundaries. | Pending |
| MANUAL-SPEECH-08 | Restart recovery | Enable TTS, set provider/limit/summary, restart Gateway, then run `/tts status` and send another TTS request. | Configuration and session preference recover from persisted temp config; no stale in-memory-only state is required. | Pending |
| MANUAL-SPEECH-09 | Shared vs Telegram override | Configure shared TTS provider as command and Telegram TTS provider as DashScope, then run `/tts status` and `/tts audio`. | Telegram override wins; removing Telegram override falls back to shared provider. | Pending |
| MANUAL-SPEECH-10 | Shared ASR vs Telegram override | Configure shared ASR as OpenAI-compatible and Telegram ASR as Tencent Flash. | Telegram voice/audio uses Tencent Flash; removing Telegram override falls back to shared OpenAI-compatible ASR. | Pending |
| MANUAL-SPEECH-11 | Telegram voice OpenRouter ASR | Configure Telegram ASR provider as `openrouter-whisper` with `${OPENROUTER_API_KEY}` in the Gateway process environment, send a short Telegram voice message, then ask `我刚才说了什么`. | First turn records `understandingStatus=ok` and no longer shows an OpenRouter `input_audio` error; second turn can read the transcript from session/media context and answer with what was said. | Pending |
| MANUAL-SPEECH-12 | Telegram voice auto TTS | With `autoReplyToVoice=true` and `audioAsVoice=true`, send a short Telegram voice message. | Logs include `Gateway.inbound: channel=telegram` and ASR `understandingStatus=ok`; model answer is converted to one voice/audio reply, not a duplicate text plus voice. | Pending |
| MANUAL-SPEECH-13 | Error diagnostics | Temporarily unset `${DASHSCOPE_API_KEY}`, use bad Tencent secret, force timeout, send oversized media, and force empty ASR result. | User-facing status is one of `not_configured`, `auth_error`, `timeout`, `provider_error`, `too_large`, `empty_result`, or `degraded`; no secret values appear. | Pending |
| MANUAL-SPEECH-14 | TTS degraded reply | Force DashScope provider failure while `degradeMessage` is configured. | User receives only the configured `degradeMessage`; no repeated normal text, empty voice, or extra silent reply is delivered. | Pending |

## Pass Criteria

Phase 6 smoke is complete when:

- Automated tests covering shared config, Telegram overrides, provider status mapping, fallback, and redaction pass.
- Manual Telegram tests cover text, voice/audio media, generic file behavior, subagent delivery, restart recovery, and both TTS/ASR configuration precedence.
- Docs and checklists contain only `${ENV_NAME}` placeholders for secrets.
- Any failed provider call produces an actionable status: `not_configured`, `auth_error`, `timeout`, `provider_error`, `too_large`, `empty_result`, or `degraded`.
- `qwen3-tts-flash` examples use `kind=dashscope-qwen-tts`; `kind=openai-compatible` examples are limited to real `/audio/speech` compatible TTS providers.
