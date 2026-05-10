# Metis DashScope/Qwen TTS Provider 分阶段落地方案 2026-05-10

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Metis 新增 DashScope/Qwen TTS 原生 provider，使 `qwen3-tts-flash` 不再误走 OpenAI-compatible `/audio/speech`，并能在 Telegram voice 自动回复和 `/tts audio` 中生成可投递语音。

**Architecture:** 保留现有 `fake`、`command`、`openai-compatible` TTS provider，不改 Telegram/IM 投递边界。新增 provider kind `dashscope-qwen-tts`，只负责调用 DashScope Qwen TTS API、解析音频、落盘为 Metis `[voice]`/`[audio]` payload；Telegram 仍只负责发送 `[voice]`/`[audio]`。

**Tech Stack:** Cangjie, `stdx.net.http`, `stdx.net.tls`, `stdx.encoding.json`, Metis Gateway speech runtime, Telegram Gateway native command/tool tests.

---

## 参考源码和依据

### OpenClaw

| 证据 | 源码位置 | 结论 |
|---|---|---|
| OpenAI TTS request shape | `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/tts.ts:107-166` | OpenClaw 的 OpenAI TTS 明确调用 `${baseUrl}/audio/speech`，body 是 `model/input/voice/response_format`。这证明 Metis 当前 `openai-compatible` provider 的实现方向本身正确，但不能拿它硬套 DashScope Qwen TTS 官方 endpoint。 |
| 自定义 baseUrl 放宽 model/voice 校验 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/tts.ts:39-58` | 自定义 endpoint 可以放宽 model/voice 校验，但 endpoint 形态仍必须匹配 `/audio/speech`。 |
| Provider plugin 负责合成音频并返回格式 | `/Users/l3gi0n/work/workspace_cangjie/openclaw/extensions/openai/speech-provider.ts:126-201` | provider 返回 `audioBuffer`、`outputFormat`、`fileExtension`、`voiceCompatible`，说明 provider 的职责是“生成音频和格式元数据”，不是直接调用 IM API。 |

### OpenClaw-China

| 证据 | 源码位置 | 结论 |
|---|---|---|
| QQBot 出站音频识别为 voice 并记录 transcriptSource | `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/qqbot/src/outbound.ts:189-234` | TTS 生成后的音频在 IM 出站层被识别为 voice，并可记录 `transcriptSource="tts"`。Metis 应保持 provider 生成音频、通道投递 voice 的边界。 |
| QQBot 清理 TTS/internal directive | `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/qqbot/src/bot.ts:1423-1432` | 内部 `[[tts:text]]`、`[[audio_as_voice]]` 等 directive 不能泄露给用户。Metis 现有 message/TTS tool 也应继续保持这一点。 |
| WeCom App voice 转码和 fallback | `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/wecom-app/src/channel.ts:537-572` | 通道层根据平台格式要求决定 voice/file fallback；provider 不应知道 WeCom/Telegram/QQ 的具体发送 API。 |
| WeCom App voice helper tests | `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/extensions/wecom-app/src/voice.test.ts:10-43` | 平台 voice 格式治理需要测试覆盖，不应只靠真实 IM 手测。 |

### Hermes

| 证据 | 源码位置 | 结论 |
|---|---|---|
| 多 provider TTS 架构 | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:91-142` | Hermes 为不同 provider 设置独立默认值和长度限制，不强行把所有 provider 统一成一个 HTTP 形态。 |
| OpenAI TTS 是 provider-specific 实现 | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:349-390` | Hermes OpenAI TTS 走 OpenAI SDK `audio.speech.create`，支持 `base_url`，但这仍是 OpenAI audio.speech 形态。 |
| 非 OpenAI endpoint 单独实现 | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:397-410` | Hermes 对 xAI 等非 OpenAI audio.speech 的 provider 单独实现。DashScope/Qwen TTS 也应作为独立 provider kind，而不是伪装成 `openai-compatible`。 |
| Telegram voice 输出格式 | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/tts_tool.py:954-974` | Telegram 场景优先选择 `.ogg`/Opus；provider 或后续处理应尽量产出 voice-compatible 音频。 |
| Gateway 平台投递 | `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/gateway/platforms/base.py:1237-1269`、`/Users/l3gi0n/work/workspace_cangjie/hermes-agent/gateway/platforms/telegram.py:1722-1760` | 平台 adapter 负责 `send_voice`/`send_audio`，`.ogg`/`.opus` 优先作为 Telegram voice。Metis 不应把 Telegram Bot API 写入 TTS provider。 |

### Metis 当前扩展点

| 证据 | 源码位置 | 结论 |
|---|---|---|
| provider kind 判断 | `src/core/gateway_speech_tts_runtime.cj:140-155` | 新增 `dashscope-qwen-tts` 应接入这里，不能破坏 `fake`、`command`、`openai-compatible`。 |
| OpenAI-compatible body | `src/core/gateway_speech_tts_runtime.cj:202-230` | 当前 `/audio/speech` body 只适合 OpenAI-compatible provider。 |
| synthesize dispatch | `src/core/gateway_speech_tts_runtime.cj:464-595` | 新 provider 应在这里分支处理，复用 status、limit、outputDir、payload、attempts、degradeMessage 机制。 |
| 共享配置 + 通道覆盖 | `src/core/gateway_speech_config.cj:151-198` | `gateway.telegram.speech.tts` 覆盖优先级已经存在；新增 provider 只需服从最终合并后的 TTS config。 |

### 官方接口依据

Alibaba Cloud Model Studio Qwen TTS 文档说明 `qwen3-tts-flash` 使用 DashScope multimodal-generation endpoint，而不是 OpenAI `/audio/speech`：

```text
https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
```

官方请求体核心形态：

```json
{
  "model": "qwen3-tts-flash",
  "input": {
    "text": "要合成的文本",
    "voice": "Chelsie",
    "language_type": "Chinese"
  }
}
```

## 目标配置形态

保留已有配置不删除；新增推荐配置：

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
            "kind": "dashscope-qwen-tts",
            "baseUrl": "https://dashscope.aliyuncs.com/api/v1",
            "apiKey": "${DASHSCOPE_API_KEY}",
            "model": "qwen3-tts-flash",
            "voice": "Chelsie",
            "languageType": "Chinese",
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

说明：

1. `baseUrl` 仍只保存 host + `/api/v1`，runtime 拼接 `/services/aigc/multimodal-generation/generation`，避免用户配置长 endpoint 时重复拼路径。
2. `languageType` 同时兼容 `language_type`，运行时请求统一写为 DashScope 官方字段 `language_type`。
3. 如果用户继续配置 `kind=openai-compatible`，Metis 仍按 `/audio/speech` 调用，不做隐式改写；避免破坏已有真正 OpenAI-compatible provider。

## Phase 0：锁定失败复现和边界

**目标：** 让后续实现有明确失败基线，避免“看起来修好了”的误判。

**修改文件：**

- Modify: `develop_steps/metis-speech-tts-failure-debug-2026-05-10.md`
- Modify: `develop_steps/metis-speech-dashscope-qwen-tts-provider-plan-2026-05-10.md`

**步骤：**

- [ ] 记录当前 `kind=openai-compatible + baseUrl=https://dashscope.aliyuncs.com/api/v1` 调 `/audio/speech` 返回 404 的事实。
- [ ] 记录日志证据：ASR `understandingStatus=ok`，模型回复成功，TTS 返回 `payloadKind=text`。
- [ ] 明确不改 Telegram adapter、不改 ASR、不删除 `openai-compatible`。

**验收项：**

1. `develop_steps/metis-speech-tts-failure-debug-2026-05-10.md` 包含日志证据、配置证据、404 复现证据。
2. 本计划包含 OpenClaw、OpenClaw-China、Hermes、Metis、官方文档证据。

## Phase 1：DashScope Qwen TTS request/response 单元测试

**目标：** 先用 TDD 固化 provider 请求格式、响应解析和错误映射。

**修改文件：**

- Modify: `src/core/gateway_speech_tts_runtime_test.cj`
- Modify: `src/core/gateway_speech_tts_runtime.cj`

**新增测试建议：**

1. `dashScopeQwenTtsBuildsMultimodalGenerationRequest`
   - 配置 `kind="dashscope-qwen-tts"`、`baseUrl="https://dashscope.aliyuncs.com/api/v1"`、`model="qwen3-tts-flash"`、`voice="Chelsie"`、`languageType="Chinese"`。
   - runner override 捕获 request。
   - 断言 URL 为 `/services/aigc/multimodal-generation/generation`。
   - 断言 header 使用 `Authorization: Bearer <key>`。
   - 断言 body 为 `model` + `input.text` + `input.voice` + `input.language_type`。
   - 断言 request/body 不包含 `apiKey`、本地输出路径、Telegram 信息。

2. `dashScopeQwenTtsParsesAudioUrlResponse`
   - fake response 返回 JSON，包含音频 URL 字段。
   - 测试只使用 runner override + fake downloader，不访问真实网络。
   - 断言最终写出音频文件，payload 以 `[voice]` 开头，caption 为 `TTS (dashscope)`。

3. `dashScopeQwenTtsParsesBase64AudioResponse`
   - fake response 返回 base64 audio。
   - 断言落盘字节与输入一致。

4. `dashScopeQwenTtsMapsErrorsAndDegrades`
   - 400/500 映射 `provider_error`。
   - 401/403 映射 `auth_error`。
   - 408 或超时映射 `timeout`。
   - 配置 `degradeMessage` 时 `gatewaySpeechTtsSynthesize` 返回 `payloadKind=text` 且 attempts 包含失败 provider。

**验收项：**

1. 新测试在实现前失败，失败原因是 `dashscope-qwen-tts` 不存在或 request shape 不匹配。
2. 所有测试不得访问真实 DashScope、真实 Telegram、真实 `~/.metis`。
3. 错误 detail 截断且不泄露 Authorization/API key/base64 全量音频。

## Phase 2：实现 DashScope/Qwen TTS provider kind

**目标：** 在 core speech runtime 内实现 provider-specific DashScope/Qwen TTS，不影响已有 provider。

**修改文件：**

- Modify: `src/core/gateway_speech_tts_runtime.cj`
- Modify: `src/core/gateway_speech_tts_runtime_test.cj`

**实现要点：**

1. `speechTtsProviderKind` 支持：

```text
dashscope-qwen-tts
dashscope
qwen-tts
```

内部统一规范为 `dashscope-qwen-tts`，但状态输出保留明确 providerKind。

2. 新增请求构造函数：

```text
speechTtsDashScopeQwenBaseUrl(providerConfig)
speechTtsDashScopeQwenEndpoint(providerConfig)
speechTtsDashScopeQwenRequestBody(providerConfig, text)
speechTtsDashScopeQwenHttpRequest(providerConfig, text, timeoutMs)
```

3. endpoint 拼接规则：

- `baseUrl=https://dashscope.aliyuncs.com/api/v1` -> `${baseUrl}/services/aigc/multimodal-generation/generation`
- `baseUrl` 已包含 `/services/aigc/multimodal-generation/generation` 时不重复拼接。

4. 字段规则：

- `model` 默认 `qwen3-tts-flash`
- `voice` 默认不猜官方 voice；缺失则返回 `not_configured`，避免发送无效 voice。
- `languageType` / `language_type` 二选一，写入 `language_type`。
- 可选保留 `emotion`、`speed` 等字段，但只有官方文档和当前配置确认的字段先入实现；不凭空设计额外字段。

5. response 解析：

- 优先解析音频 URL，然后下载音频。
- 支持 base64 音频字段，便于后续兼容流式/非流式响应和测试。
- 若响应是二进制音频，按 body bytes 直接落盘。
- 若没有音频，返回 `empty_result`。

6. 输出扩展：

- 如果 provider 返回 URL 后可从 URL path 推断 `.mp3/.wav/.ogg/.opus`，使用推断扩展。
- 如果无法推断，默认 `.mp3`。
- Telegram `audioAsVoice=true` 时仍输出 `[voice]` payload；后续是否能作为 Telegram voice 成功，由 Telegram adapter/格式阶段处理。

**验收项：**

1. `gatewaySpeechTtsStatus` 对 `dashscope-qwen-tts` 且有 apiKey/voice 时返回 `ok`。
2. 缺少 apiKey 或 voice 时返回 `not_configured` 和明确 message。
3. `gatewaySpeechTtsSynthesize` 能通过 fake runner 生成 `[voice]` 或 `[audio]` payload。
4. `openai-compatible` 现有测试全部继续通过。

## Phase 3：下载音频 URL 与安全边界

**目标：** 支持 DashScope 返回远端音频 URL 的常见形态，同时避免 SSRF/密钥泄露。

**修改文件：**

- Modify: `src/core/gateway_speech_tts_runtime.cj`
- Modify: `src/core/gateway_speech_tts_runtime_test.cj`

**实现要点：**

1. 新增可测试 downloader override，例如：

```text
setGatewaySpeechTtsDashScopeQwenDownloaderForTest(...)
```

2. 真实下载只允许 `http://` 或 `https://`。
3. 默认不允许下载本地文件路径，不读取用户真实文件。
4. 错误消息中不得包含完整签名 URL query；最多保留 host/path 和状态码。
5. `maxBytes` 或 provider `maxAudioBytes` 先拦截过大响应，防止大文件落盘。

**验收项：**

1. fake downloader 测试覆盖 URL 下载成功。
2. fake downloader 测试覆盖 404/timeout/too_large。
3. 错误 detail 不包含 API key、Authorization、签名 URL query。
4. 自动测试不访问真实网络。

## Phase 4：Telegram 自动语音回复和工具链回归

**目标：** 确保新增 provider 可被 Telegram voice input 自动 TTS 和模型 `tts` tool 使用。

**修改文件：**

- Modify: `src/gateway/core/gateway_service_telegram_native_test.cj`
- Modify: `src/gateway/tools/gateway_tts_toolset_test.cj`
- Modify: `src/gateway/tools/gateway_message_toolset_test.cj`

**测试覆盖：**

1. Telegram voice input：
   - `autoReplyToVoice=true`
   - `audioAsVoice=true`
   - TTS provider 为 `dashscope-qwen-tts`
   - fake runner 返回音频
   - 断言最终发出 `[voice]`，不发 `degradeMessage` 文本。

2. `/tts audio <text>`：
   - fake runner 返回音频
   - 断言输出为 voice/audio payload。

3. 模型调用 `tts` tool：
   - runtime context 为 Telegram
   - fake delivery 捕获 `[voice]`
   - 工具结果包含 `payloadKind=voice`
   - 成功投递后仍要求 silent reply，不重复文本。

4. 失败降级：
   - fake runner 返回 404
   - 断言返回 `degradeMessage`
   - attempts 中 providerKind 为 `dashscope-qwen-tts`，reasonCode 为 `provider_error`。

**验收项：**

1. Telegram 自动 voice 回复链路不再把 provider 成功结果降级成 `payloadKind=text`。
2. `degradeMessage` 只在 provider 确实失败时出现。
3. 不新增真实 Telegram 网络测试。

## Phase 5：文档、配置和 smoke checklist

**目标：** 用户能正确配置 DashScope/Qwen TTS，并知道 `openai-compatible` 和 `dashscope-qwen-tts` 的区别。

**修改文件：**

- Modify: `docs/user/telegram.md`
- Modify: `develop_steps/metis-speech-shared-tts-asr-smoke-checklist-2026-05-09.md`
- Modify: `develop_steps/metis-speech-tts-failure-debug-2026-05-10.md`

**文档内容：**

1. 推荐配置使用：

```json
"kind": "dashscope-qwen-tts",
"baseUrl": "https://dashscope.aliyuncs.com/api/v1",
"model": "qwen3-tts-flash",
"voice": "Chelsie",
"languageType": "Chinese"
```

2. 明确不要把 `qwen3-tts-flash` 配成 `kind=openai-compatible`，因为它不是 `/audio/speech` endpoint。
3. 保留 `openai-compatible` 示例，用于真正兼容 `/audio/speech` 的 provider。
4. smoke checklist 新增：
   - `/tts status` 显示 providerKind `dashscope-qwen-tts` 且 status `ok`
   - `/tts audio 你好，这是 Metis 的 Qwen TTS 测试` 收到语音/音频
   - Telegram 发送 voice 后收到语音回复
   - provider 故障时只收到 degradeMessage，不重复文本和 silent reply

**验收项：**

1. 文档中没有真实 API key。
2. 文档包含 `DASHSCOPE_API_KEY` 环境变量示例。
3. smoke checklist 有手动测试步骤和期望结果。

## Phase 6：全量验证和落盘记录

**目标：** 按项目规则完成构建、测试、记录。

**命令：**

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm clean && cjpm build -i && cjpm test
```

**专项命令：**

```bash
cjpm test src/core --no-color --no-progress --show-all-output
cjpm test src/gateway/tools --no-color --no-progress --show-all-output
cjpm test src/gateway/core --no-color --no-progress --show-all-output
git diff --check
```

**验收项：**

1. 相关单元测试全部通过。
2. 全量 `cjpm clean && cjpm build -i && cjpm test` 已执行；如果出现既有聚合 `exit code = 9`，必须单包复跑并记录。
3. `develop_steps` 中追加执行记录：修改文件、测试命令、结果、剩余手动 smoke。
4. 不提交真实密钥、不访问真实 Telegram、自动测试不修改真实 `~/.metis`。

## 风险和边界

1. 本计划不删除或重命名已有 `openai-compatible` provider。
2. 本计划不把 DashScope 特例塞到 Telegram adapter；provider 只产音频，Telegram 只发送媒体。
3. 本计划不实现完整音频转码系统；若 DashScope 返回 mp3 且 Telegram voice 需要 opus，先按当前 `[voice]` payload 投递规则验证。如果 Telegram Bot API 实测拒绝 mp3 voice，再单独制定“Telegram voice format/transcode”阶段。
4. 本计划不使用真实 API key 做自动测试。真实 DashScope smoke 只放在手动测试。
5. 需要警惕 runtime 日志泄露：Authorization、apiKey、签名音频 URL query、base64 音频都必须 redaction。

## 建议执行顺序

1. Phase 1-2：先完成 core provider request/response 和 status。
2. Phase 3：补 URL 下载和安全边界。
3. Phase 4：接 Telegram 自动 voice、`/tts audio`、tts tool 回归。
4. Phase 5：更新用户文档和 smoke checklist。
5. Phase 6：统一验证并落盘。

## 执行记录 2026-05-10

### Worktree 分工

| Worktree | 分支 | 阶段 | 结果 |
|---|---|---|---|
| `/Users/l3gi0n/.config/superpowers/worktrees/Metis/dashscope-core` | `metis/dashscope-core` | Phase 1-3 | 新增 core provider 和单元测试；我修正下载错误映射顺序后，`cjpm test src/core --no-color --no-progress --show-all-output` 通过，128 passed。 |
| `/Users/l3gi0n/.config/superpowers/worktrees/Metis/dashscope-telegram` | `metis/dashscope-telegram` | Phase 4 | 新增 Telegram 自动 voice、`/tts audio`、tts/message tool 回归测试。subagent 运行 gateway 测试时被 tree-sitter 依赖网络下载失败阻断，未进入测试编译；补丁已合回主工作区，后续在主工作区统一验证。 |
| `/Users/l3gi0n/.config/superpowers/worktrees/Metis/dashscope-docs` | `metis/dashscope-docs` | Phase 0/5 | 更新用户文档、smoke checklist 和失败记录；`git diff --check` 通过，未发现 `sk-` 形式 key。 |

### 已完成代码点

- `dashscope-qwen-tts` provider kind 已新增，并兼容 `dashscope`、`qwen-tts` 别名。
- DashScope 请求 endpoint 为 `/services/aigc/multimodal-generation/generation`，body 为 `model` + `input.text/voice/language_type`。
- 保留 `openai-compatible` 原 `/audio/speech` 行为。
- 新增 DashScope runner/downloader test override，自动测试不访问真实 DashScope、Telegram 或真实 `~/.metis`。
- 支持二进制音频、JSON 音频 URL 下载、base64 音频。
- 下载只允许 `http://` / `https://`，错误 detail 会截断并避免泄露 API key、Authorization、签名 URL query 和 base64 全量音频。
- provider 失败时保留 `degradeMessage` 降级路径，attempts 记录 `providerKind=dashscope-qwen-tts` 和 reasonCode。

### 已完成文档点

- `docs/user/telegram.md` 推荐 `qwen3-tts-flash` 使用 `kind=dashscope-qwen-tts`。
- 文档明确 `qwen3-tts-flash` 不能配置为 `kind=openai-compatible`。
- smoke checklist 增加 `/tts status`、`/tts audio 你好，这是 Metis 的 Qwen TTS 测试`、Telegram voice auto TTS 和 degradeMessage 手动验收项。
