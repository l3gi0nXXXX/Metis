# Metis OpenRouter ASR Request Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留现有 OpenAI-compatible ASR 行为的前提下，新增 OpenRouter ASR `input_audio` base64 JSON 请求格式适配，使 Telegram voice/audio 可以通过 `https://openrouter.ai/api/v1/audio/transcriptions` 正常转写。

**Architecture:** Metis 继续保持 Gateway shared speech config + channel override 的架构边界，不把 OpenRouter 特例写入 Telegram adapter 或 session runner。请求格式选择放在 `src/core/gateway_speech_asr_runtime.cj` 的 ASR provider runtime 内，通过 provider 配置显式选择或按 `baseUrl` 安全推断。测试全部使用 runner override，不访问真实 OpenRouter、真实 Telegram、真实用户文件或真实 API key。

**Tech Stack:** Cangjie, `stdx.encoding.json`, `stdx.encoding.base64.toBase64String`, `stdx.net.http`, `cjpm test`, Metis Gateway speech config/runtime。

---

## 现场问题记录

用户修改 provider 级 `insecureSkipTlsVerify=true` 后，TLS 错误已消失，最新日志变为 OpenRouter 400：

```text
OpenAI-compatible ASR API error (400): {"success":false,"error":{"name":"ZodError","message":"... \"path\": [\"input_audio\"] ... \"Invalid input: expected object, received undefined\" ..."}}
```

这说明当前问题不是 ASR 未配置，也不是 Telegram 入站失败，而是 Metis OpenAI-compatible ASR 请求体与 OpenRouter ASR 接口不兼容。

## 源码依据

### Hermes

1. `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/transcription_tools.py:5-18`
   - Hermes 明确把 voice transcription 作为跨 Telegram、Discord、WhatsApp、Slack、Signal 的 shared STT 能力。
   - 支持输入格式包含 `ogg`，与 Telegram voice 的 `audio/ogg` 匹配。

2. `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/transcription_tools.py:448-471`
   - Groq STT 使用 OpenAI SDK，调用 `client.audio.transcriptions.create(model, file, response_format="text")`。
   - 这是 Whisper-compatible 文件上传形态，不是把本地 `filePath` 发给远端。

3. `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/transcription_tools.py:500-528`
   - OpenAI STT 同样打开本地音频文件，把文件对象作为 `file` 传入 `audio.transcriptions.create`。
   - `response_format` 根据模型选择 `text` 或 `json`。

4. `/Users/l3gi0n/work/workspace_cangjie/hermes-agent/tools/transcription_tools.py:596-625`
   - xAI STT 注释明确使用 REST endpoint + `multipart/form-data`。
   - 说明 Hermes 对不同 STT provider 接口形态分别适配，不把所有 provider 都强行归一为一个 JSON 形态。

### OpenClaw-China

1. `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/packages/shared/src/asr/tencent-flash.ts:16-23`
   - Tencent Flash ASR 配置独立建模，字段为 `appId`、`secretId`、`secretKey`、`engineType`、`voiceFormat`、`timeoutMs`。

2. `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/packages/shared/src/asr/tencent-flash.ts:40-50`
   - Tencent Flash query 按 provider 规则排序和编码。

3. `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/packages/shared/src/asr/tencent-flash.ts:73-104`
   - Tencent Flash 使用原始音频 bytes 作为 `application/octet-stream` body，并按腾讯规则签名。
   - 这证明 provider runtime 应按 provider 协议生成请求体，而不是由 IM adapter 处理。

4. `/Users/l3gi0n/work/workspace_cangjie/openclaw-china/packages/shared/src/asr/tencent-flash.ts:106-130`
   - 响应先解析 JSON，再映射 HTTP/auth/provider 错误。
   - Metis 当前 Tencent Flash helper 已复用这个方向，应让 OpenRouter ASR 也保持同等错误映射。

### OpenClaw

1. `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/media/input-files.fetch-guard.test.ts:145-158`
   - OpenClaw 对 base64 media source 有明确测试，验证转换后的 base64 数据和 MIME。

2. `/Users/l3gi0n/work/workspace_cangjie/openclaw/src/media/input-files.fetch-guard.test.ts:274-318`
   - OpenClaw 对 base64 输入有 size guard，并验证超限时不会执行 `Buffer.from(..., "base64")` 解码。
   - Metis OpenRouter ASR 适配必须保持先检查原始音频 `maxBytes`，再 base64 编码，避免扩容后才拒绝。

### Metis 当前实现

1. `src/core/gateway_speech_asr_runtime.cj:180-198`
   - 当前 OpenAI-compatible ASR request object 包含 `url`、`authorization`、`filePath`、`fileBytes`、`mime`、`fields`。

2. `src/core/gateway_speech_asr_runtime.cj:213-249`
   - 当前 native post 发送 JSON body：`model`、`language`、`filePath`、`fileBytes`、`mime`。
   - 远端无法读取 Metis 本机路径，因此该形态只适合 mock/占位，不适合 OpenRouter。

3. `src/core/gateway_speech_asr_runtime.cj:255-312`
   - 当前错误映射已覆盖 401/403、408、provider_error、empty_result；OpenRouter 适配应复用这套状态，不增加用户可见的新错误码。

4. `src/core/gateway_speech_asr_runtime_test.cj:149-179`
   - 现有测试固定断言 `filePath` 和 `mime` 出现在 runner request。
   - 新适配必须新增 OpenRouter 测试，同时不能破坏现有 OpenAI-compatible 测试。

5. `src/gateway/tools/gateway_telegram_media_toolset.cj:580-600`
   - Metis 已有读取本地 media bytes、检查大小、base64 编码为 data URL 的成熟模式。
   - OpenRouter ASR 可复用 `stdx.encoding.base64.toBase64String` 的思路，但不得把完整 base64 写进日志或用户可见错误。

### OpenRouter 接口依据

OpenRouter 文档 `Create transcription`：`POST /api/v1/audio/transcriptions`，请求体需要：

```json
{
  "model": "openai/whisper-large-v3",
  "input_audio": {
    "data": "<base64 audio>",
    "format": "wav"
  },
  "language": "en"
}
```

当前线上错误 `input_audio expected object, received undefined` 与该文档一致。文档地址：

```text
https://openrouter.ai/docs/api/api-reference/transcriptions/create-audio-transcriptions
```

## 最终目标形态

1. `kind="openai-compatible"` 保留现有默认行为，继续支持后续补 multipart 的 Whisper-compatible provider。
2. 新增 provider 请求格式字段，推荐：

```json
{
  "kind": "openai-compatible",
  "baseUrl": "https://openrouter.ai/api/v1",
  "apiKey": "${OPENROUTER_API_KEY}",
  "model": "openai/whisper-large-v3-turbo",
  "requestFormat": "openrouter-input-audio-json",
  "timeoutMs": 60000,
  "maxBytes": 26214400,
  "insecureSkipTlsVerify": true
}
```

3. 为降低用户配置成本，当 `baseUrl` host 是 `openrouter.ai` 且未显式配置 `requestFormat` 时，Metis 可以推断为 `openrouter-input-audio-json`；如果显式配置了其他 `requestFormat`，以用户配置为准。
4. OpenRouter 请求体只包含远端可消费的数据：`model`、可选 `language`、`input_audio.data`、`input_audio.format`。
5. `input_audio.format` 从 provider 配置 `audioFormat` 优先读取；未配置时根据 MIME/文件后缀推断：`audio/ogg` 或 `.oga/.ogg/.opus` -> `ogg`，`audio/wav` 或 `.wav` -> `wav`，`audio/mpeg` 或 `.mp3` -> `mp3`，`audio/mp4/.m4a` -> `mp4`，兜底 `ogg`。
6. maxBytes 检查必须在 base64 编码前完成，继续沿用 shared ASR `maxBytes` 和 provider `maxBytes`。
7. 请求和错误日志不得包含 API key、Authorization、完整 base64 音频、真实 Telegram fileId。

## 分阶段落地计划

### Phase 1：OpenRouter 请求构造 TDD

**目标**：只新增请求构造能力和测试，不发真实网络请求。

**修改文件**

- `src/core/gateway_speech_asr_runtime.cj`
- `src/core/gateway_speech_asr_runtime_test.cj`
- `develop_steps/metis-speech-openrouter-asr-request-format-plan-2026-05-10.md`

**实施步骤**

- [ ] 在 `gateway_speech_asr_runtime_test.cj` 新增测试 `openRouterAsrProviderBuildsInputAudioJsonRequest`。
- [ ] 测试配置 provider：

```cangjie
provider.put("kind", JsonString("openai-compatible"))
provider.put("baseUrl", JsonString("https://openrouter.ai/api/v1"))
provider.put("apiKey", JsonString("test-openrouter-key"))
provider.put("model", JsonString("openai/whisper-large-v3-turbo"))
provider.put("requestFormat", JsonString("openrouter-input-audio-json"))
provider.put("language", JsonString("zh"))
provider.put("maxBytes", JsonInt(8192))
provider.put("insecureSkipTlsVerify", JsonBool(true))
```

- [ ] 测试写入本地临时音频 bytes：`File.writeTo(audio, "fake-openrouter-audio".toArray())`。
- [ ] runner 断言 request：
  - `url == "https://openrouter.ai/api/v1/audio/transcriptions"`
  - `authorization == "Bearer test-openrouter-key"`
  - `contentType == "application/json"`
  - `body.model == "openai/whisper-large-v3-turbo"`
  - `body.language == "zh"`
  - `body.input_audio.format == "ogg"`
  - `body.input_audio.data` 非空，且不等于本地 `filePath`
  - request JSON 不包含真实 `filePath`
- [ ] 先运行测试，预期失败，因为当前实现没有 `input_audio`。

**验收项**

| 验收项 | 验收命令 | 预期 |
| --- | --- | --- |
| OpenRouter request shape 测试先红后绿 | `source /Users/l3gi0n/cangjie100/envsetup.sh && cjpm test src/core --no-color --no-progress --show-all-output` | 新增测试最终通过 |
| 不破坏现有 OpenAI-compatible 测试 | 同上 | `openAICompatibleProviderPostsTranscriptionRequestAndParsesPlainText` 仍通过 |
| 不泄露路径和密钥 | 同上 | result/request 断言不包含 API key；OpenRouter body 不含 `filePath` |

### Phase 2：实现请求格式选择和 base64 body

**目标**：在 ASR runtime 内按 provider 配置生成 OpenRouter JSON body，并保留默认行为。

**修改文件**

- `src/core/gateway_speech_asr_runtime.cj`
- `src/core/gateway_speech_asr_runtime_test.cj`

**实施步骤**

- [ ] 在 `gateway_speech_asr_runtime.cj` 引入 `stdx.encoding.base64.toBase64String`。
- [ ] 新增私有函数 `speechAsrOpenAICompatibleRequestFormat(providerConfig: JsonObject, baseUrl: String): String`：
  - 先读 `requestFormat`
  - 兼容 `request_format`
  - 如果为空且 baseUrl host 包含 `openrouter.ai`，返回 `openrouter-input-audio-json`
  - 否则返回 `generic-json`
- [ ] 新增私有函数 `speechAsrOpenRouterAudioFormat(inputPath: String, mime: String, providerConfig: JsonObject): String`：
  - 优先读 `audioFormat`
  - 然后按 MIME/后缀推断
  - 兜底 `ogg`
- [ ] 修改 `speechAsrOpenAICompatibleRequest`，让 request 中包含：
  - `requestFormat`
  - `contentType`
  - `body`
- [ ] 当 requestFormat 是 `openrouter-input-audio-json` 时：
  - 使用已经读取的音频 bytes 或在构造前传入 bytes
  - `body.input_audio.data = toBase64String(inputBytes)`
  - `body.input_audio.format = inferredFormat`
  - `body.model = model`
  - 可选 `body.language = language`
- [ ] 当 requestFormat 是 `generic-json` 时，保留现有 `filePath/fileBytes/mime` body，避免破坏现有测试。
- [ ] 修改 `speechAsrOpenAICompatibleNativePost`，优先使用 request 内 `body` 和 `contentType`，不要重新硬编码 `filePath/fileBytes/mime`。
- [ ] runner override 仍接收 request object，方便测试所有请求体，不做真实网络。

**验收项**

| 验收项 | 验收命令 | 预期 |
| --- | --- | --- |
| OpenRouter 显式格式通过 | `cjpm test src/core --no-color --no-progress --show-all-output` | OpenRouter 测试通过 |
| OpenRouter host 自动推断通过 | 同上 | 新增 `openRouterAsrProviderInfersRequestFormatFromBaseUrl` 通过 |
| generic-json 向后兼容 | 同上 | 既有 OpenAI-compatible 测试通过 |
| maxBytes 在 base64 前生效 | 同上 | 新增测试确认超限时 runner 不被调用 |

### Phase 3：响应解析和错误诊断收敛

**目标**：OpenRouter 成功/错误响应能映射到 Metis 已有 ASR status，用户不再看到误导性的 TLS 或配置错误。

**修改文件**

- `src/core/gateway_speech_asr_runtime.cj`
- `src/core/gateway_speech_asr_runtime_test.cj`
- `src/gateway/tools/gateway_telegram_media_toolset_test.cj`（只在需要验证工具层输出时修改）

**实施步骤**

- [ ] 复用 `speechAsrOpenAICompatibleTextFromJson` 解析 OpenRouter 成功响应 `{ "text": "..." }`。
- [ ] 如果 OpenRouter 返回 400 且 body 包含 `input_audio`，仍映射 `provider_error`，message 保留前 300 字符并 redaction。
- [ ] 新增测试 `openRouterAsrMapsInputAudioValidationErrorToProviderError`：
  - runner 返回 400 + OpenRouter ZodError JSON
  - 断言 status=`provider_error`
  - 断言 message 包含 `input_audio`
  - 断言 message 不包含 API key 和 base64 data
- [ ] 新增测试 `openRouterAsrParsesJsonText`：
  - runner 返回 200 + `{ "text": "语音测试喽" }`
  - 断言 transcript 正确。

**验收项**

| 验收项 | 验收命令 | 预期 |
| --- | --- | --- |
| 成功响应解析 | `cjpm test src/core --no-color --no-progress --show-all-output` | transcript 为 OpenRouter JSON text |
| 400 诊断准确 | 同上 | status 为 `provider_error`，message 指向 `input_audio` |
| secret/base64 不泄露 | 同上 | result JSON 不包含 API key，不包含完整 base64 |

### Phase 4：文档、配置示例和 smoke 清单更新

**目标**：用户知道 OpenRouter ASR 必须使用 `requestFormat=openrouter-input-audio-json`，也知道 OpenAI/Groq/Mistral 类接口不是同一请求格式。

**修改文件**

- `docs/user/telegram.md`
- `develop_steps/metis-speech-shared-tts-asr-smoke-checklist-2026-05-09.md`
- `develop_steps/metis-speech-openrouter-asr-request-format-plan-2026-05-10.md`

**实施步骤**

- [ ] 在 `docs/user/telegram.md` 的 speech 配置示例中新增 OpenRouter ASR provider：

```json
"openrouter-whisper": {
  "kind": "openai-compatible",
  "baseUrl": "https://openrouter.ai/api/v1",
  "apiKey": "${OPENROUTER_API_KEY}",
  "model": "openai/whisper-large-v3-turbo",
  "requestFormat": "openrouter-input-audio-json",
  "timeoutMs": 60000,
  "maxBytes": 26214400
}
```

- [ ] 文档明确：
  - OpenRouter ASR 是 JSON base64 `input_audio` 形态。
  - OpenAI/Groq/Hermes 参考实现是文件上传/multipart 形态，本轮不把 multipart 伪装成 OpenRouter。
  - `insecureSkipTlsVerify` 是 provider 级调试开关，不是 Telegram network 开关。
- [ ] 在 smoke checklist 增加手动项：
  - 配置 OpenRouter ASR provider。
  - 发送 Telegram voice。
  - 预期 `understandingStatus=ok`，回复内容不再出现 `input_audio` 错误。
  - 再问“我刚才说了什么”，预期工具可读到 transcript。

**验收项**

| 验收项 | 验收命令 | 预期 |
| --- | --- | --- |
| 文档包含 OpenRouter ASR 配置 | `rg -n "openrouter-input-audio-json|OPENROUTER_API_KEY|input_audio" docs/user/telegram.md develop_steps` | 有命中 |
| 文档不包含真实 key | `rg -n "sk-[A-Za-z0-9]|OPENROUTER_API_KEY\\\":\\s*\\\"[^$]" docs/user/telegram.md develop_steps` | 无真实 key |
| smoke checklist 覆盖 Telegram voice | `rg -n "OpenRouter ASR|Telegram voice|understandingStatus=ok|input_audio" develop_steps/metis-speech-shared-tts-asr-smoke-checklist-2026-05-09.md` | 有命中 |

### Phase 5：统一验证

**目标**：本轮修改遵守项目要求，完成构建和测试。

**实施步骤**

- [ ] 执行 core 测试：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm test src/core --no-color --no-progress --show-all-output
```

- [ ] 执行 Telegram media/tooling 相关测试：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm test src/gateway/tools --no-color --no-progress --show-all-output
```

- [ ] 执行项目强制验证：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm clean && cjpm build -i && cjpm test
```

- [ ] 如果全量 `cjpm test` 仍出现包级 `exit code = 9` 聚合运行漂移，必须单跑失败包并记录结果，不得把聚合漂移误报为业务断言失败。

**验收项**

| 验收项 | 验收命令 | 预期 |
| --- | --- | --- |
| core ASR/TTS 测试通过 | `cjpm test src/core --no-color --no-progress --show-all-output` | 通过 |
| Telegram media/tooling 测试通过 | `cjpm test src/gateway/tools --no-color --no-progress --show-all-output` | 通过 |
| 全量 clean/build/test 已执行 | `cjpm clean && cjpm build -i && cjpm test` | clean/build 成功；test 结果记录到本文档 |
| 不访问真实外部服务 | 检查测试 runner override | 所有新增测试不使用真实 OpenRouter、Telegram 或真实 `~/.metis` |

### Phase 5 追加验收检查建议（独立复核，2026-05-10）

**baseline 结果**

- 复核 worktree：`/Users/l3gi0n/.config/superpowers/worktrees/Metis/openrouter-asr-verify-20260510`
- 已执行 baseline 命令：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm test src/core --no-color --no-progress --show-all-output
```

- 结果：未进入 `src/core` 单测断言阶段。pre-build 尝试拉取 `https://gitcode.com/gh_mirrors/tr/tree-sitter.git/` 时发生 `LibreSSL SSL_connect: SSL_ERROR_SYSCALL in connection to gitcode.com:443`，随后 `cjpm test` 报 `please execute 'cjpm build -i' successfully first`。
- 结论：该 worktree baseline 被依赖下载/构建脚本阻塞，不能据此判断 ASR 改动通过或失败。合并验收前必须在依赖已就绪或网络可用环境中复跑 core 单包测试。

**合并后必须运行的验证命令**

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm build -i
cjpm test src/core --no-color --no-progress --show-all-output
cjpm test src/gateway/tools --no-color --no-progress --show-all-output
cjpm test
```

如全量 `cjpm test` 出现包级 `exit code = 9` 聚合漂移，必须从输出中定位失败包并单包复跑，例如：

```bash
cjpm test <failed/package/path> --no-color --no-progress --show-all-output
```

验收记录应区分三类结果：真实业务断言失败、包级聚合漂移、依赖下载/构建脚本失败。

**重点风险复核项**

- generic-json 兼容：未显式配置 `requestFormat` 且非 OpenRouter baseUrl 时，现有 OpenAI-compatible runner request 仍应保留 `filePath`、`fileBytes`、`mime`、`fields`，既有 `openAICompatibleProviderPostsTranscriptionRequestAndParsesPlainText` 等测试必须继续通过。
- OpenRouter request body：`openrouter-input-audio-json` 的 native HTTP body 只能包含远端可消费字段，如 `model`、可选 `language`、`input_audio.data`、`input_audio.format`；不得包含本机 `filePath`、`fileBytes`、API key、`Authorization` 或其他密钥字段。
- runner request 泄露面：测试 runner 可接收 `authorization` 以验证 header 组装，但 result、error message、日志和 OpenRouter body 断言不得包含 API key、完整 base64 音频或真实 Telegram fileId。
- maxBytes 顺序：必须先读取原始音频字节并用 shared/provider `maxBytes` 拦截，再执行 base64 编码；超限测试应断言 runner 未被调用，并尽量断言不会生成 `input_audio.data`。
- provider 级 TLS：`provider.insecureSkipTlsVerify=true` 仍必须只影响 ASR provider native HTTP client TLS 配置，不能依赖或传播 `gateway.telegram.network.insecureSkipTlsVerify`。
- 自动推断边界：`baseUrl` 为 `https://openrouter.ai/api/v1` 时可推断 OpenRouter 格式；其他 OpenAI/Groq/Mistral 类 provider 不应被误判为 OpenRouter，避免破坏 generic-json 向后兼容。
- 错误映射：OpenRouter 400/ZodError 仍应映射为 `provider_error`，401/403 为 `auth_error`，408 为 `timeout`，空 text 为 `empty_result`；错误 detail 保持 300 字符截断并做 secret/base64 redaction。
- 文档和 smoke：`docs/user/telegram.md` 与 `develop_steps/metis-speech-shared-tts-asr-smoke-checklist-2026-05-09.md` 必须覆盖 OpenRouter ASR 配置、Telegram voice 手动 smoke、`understandingStatus=ok` 或等价成功信号、以及不把 OpenAI multipart/generic-json 与 OpenRouter `input_audio` JSON 混用。
- 外部服务隔离：自动测试只能使用 runner override、临时文件和假 token；不得访问真实 OpenRouter、真实 Telegram、真实 `~/.metis` 或真实 API key。

## Phase 1-3 执行记录（2026-05-10）

- Phase 1-3 已在 `src/core/gateway_speech_asr_runtime.cj` 和 `src/core/gateway_speech_asr_runtime_test.cj` 落地。
- TDD RED：新增 OpenRouter ASR 测试后，`openRouterAsrProviderBuildsInputAudioJsonRequest`、`openRouterAsrProviderInfersRequestFormatFromBaseUrl`、`openRouterAsrMapsInputAudioValidationErrorToProviderError` 按预期失败，原因是 request 缺少 `requestFormat`、`body.input_audio`，且旧 request 仍包含本地 `filePath`。
- GREEN：实现 `requestFormat="openrouter-input-audio-json"`、OpenRouter host 自动推断、base64 `input_audio` body、格式推断、native post body 复用和错误 redaction 后，`src/core` 测试通过。
- 验证命令：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh && export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH" && cjpm test src/core --no-color --no-progress --show-all-output
```

- 验证结果：`TOTAL: 125, PASSED: 125, SKIPPED: 0, ERROR: 0, FAILED: 0`。
- 测试边界：新增测试全部使用 ASR runner override 和临时音频文件；未访问真实 OpenRouter、Telegram、真实 `~/.metis` 或真实 API key。

## Phase 4 执行记录

执行日期：2026-05-10

修改范围：

- `docs/user/telegram.md`
- `develop_steps/metis-speech-shared-tts-asr-smoke-checklist-2026-05-09.md`
- 本计划文件仅追加 Phase 4 执行记录

执行内容：

1. 在 Telegram speech 配置示例中新增 OpenRouter ASR provider：`kind=openai-compatible`、`baseUrl=https://openrouter.ai/api/v1`、`apiKey=${OPENROUTER_API_KEY}`、`model=openai/whisper-large-v3-turbo`、`requestFormat=openrouter-input-audio-json`、`timeoutMs`、`maxBytes`。
2. 文档明确 OpenRouter ASR 使用 JSON base64 `input_audio` 形态；OpenAI/Groq/Hermes 参考实现为文件上传或 multipart 形态；Tencent Flash 为 provider 专用 `application/octet-stream` 形态。
3. 文档明确 provider 级 `insecureSkipTlsVerify` 与 `gateway.telegram.network.insecureSkipTlsVerify` 是不同开关，分别作用于 provider HTTPS 调用和 Telegram Bot API transport。
4. Smoke checklist 新增 Telegram voice OpenRouter ASR 手动测试：发送 voice 后预期 `understandingStatus=ok` 且不再出现 `input_audio` 错误；再问“我刚才说了什么”时预期可读取 transcript。

验证命令：

```bash
rg -n "openrouter-input-audio-json|OPENROUTER_API_KEY|input_audio|OpenRouter ASR|understandingStatus=ok" docs/user/telegram.md develop_steps
rg --pcre2 -n "sk-[A-Za-z0-9]{16,}|apiKey\"\s*:\s*\"(?!\$\{)[^\"]{12,}|secret(Key|Id)?\"\s*:\s*\"(?!\$\{)[^\"]{12,}" docs/user/telegram.md develop_steps/metis-speech-*.md || true
```

## 风险和边界

1. 本计划不实现 OpenAI/Groq 真 multipart 上传；Hermes 证明这些 provider 使用文件上传形态，但当前用户故障是 OpenRouter `input_audio` JSON 缺失，应先修复 OpenRouter。
2. 本计划不把 OpenRouter 特例写入 Telegram adapter。Telegram 只负责下载 voice/audio 和投递回复，ASR 请求格式属于 core speech runtime。
3. 本计划不把 `gateway.telegram.network.insecureSkipTlsVerify` 传播给 ASR provider。provider TLS 行为必须显式配置，避免通道网络配置意外影响第三方 ASR 服务。
4. 本计划不在日志输出完整 base64 音频、Authorization、API key、Telegram fileId。
5. 手动 smoke 测试需要真实 OpenRouter key，但自动测试不得依赖真实 key。

## 本轮对话落盘记录

1. 用户反馈：加了 provider 级 `insecureSkipTlsVerify=true` 后，Telegram 语音结果仍与上次类似。
2. 排查结果：最新日志证实 TLS 问题已消失，OpenRouter 返回 400，原因是 `input_audio` 缺失。
3. 用户确认：同意新增 OpenRouter ASR 请求格式适配，并要求立即参考 OpenClaw、Hermes、OpenClaw-China 源码制定分阶段落地计划和验收项。
4. 本文档即为该确认后的落地计划，不包含代码改动。

## 主工作区合并验证记录（2026-05-10）

合并范围：

- `src/core/gateway_speech_asr_runtime.cj`
- `src/core/gateway_speech_asr_runtime_test.cj`
- `docs/user/telegram.md`
- `develop_steps/metis-speech-shared-tts-asr-smoke-checklist-2026-05-09.md`
- `develop_steps/metis-speech-openrouter-asr-request-format-plan-2026-05-10.md`

主工作区验证命令和结果：

```bash
git diff --check
```

- 结果：通过，无 whitespace error。

```bash
rg -n "openrouter-input-audio-json|OPENROUTER_API_KEY|input_audio|OpenRouter ASR|understandingStatus=ok" docs/user/telegram.md develop_steps
rg --pcre2 -n "sk-[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-|apiKey\"\s*:\s*\"(?!\$\{)[^\"]{12,}|secret(Key|Id)?\"\s*:\s*\"(?!\$\{)[^\"]{12,}" docs/user/telegram.md develop_steps/metis-speech-*.md src/core/gateway_speech_asr_runtime_test.cj || true
```

- 结果：OpenRouter ASR 文档和 smoke 关键字均可检索；secret scan 仅命中 `${DASHSCOPE_API_KEY}`、`${OPENAI_ASR_API_KEY}`、`${OPENROUTER_API_KEY}`、`${TENCENT_ASR_SECRET_ID}`、`${TENCENT_ASR_SECRET_KEY}` 等占位符，未发现真实密钥。

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm test src/core --no-color --no-progress --show-all-output
cjpm test src/gateway/tools --no-color --no-progress --show-all-output
```

- `src/core` 结果：`TOTAL: 125, PASSED: 125, SKIPPED: 0, ERROR: 0, FAILED: 0`。
- `src/gateway/tools` 结果：`TOTAL: 83, PASSED: 83, SKIPPED: 0, ERROR: 0, FAILED: 0`。

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm clean && cjpm build -i && cjpm test
```

- `cjpm clean`：通过。
- `cjpm build -i`：通过；仅出现 `ffi/libsignature_extractor.dylib` 和 `ffi/librawinput.dylib` 的 macOS target minimum warning。
- 聚合 `cjpm test`：业务测试 `PASSED: 1066, FAILED: 0, SKIPPED: 0`；聚合结果中 `metis.program` 报 `ERROR: 1, REASON: failed to run package (exit code = 9)`，导致 `cjpm test` 总体退出码为 1。

针对聚合错误的单包复核：

```bash
source /Users/l3gi0n/cangjie100/envsetup.sh
export DYLD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$DYLD_LIBRARY_PATH"
cjpm test src/program --no-color --no-progress --show-all-output
```

- 结果：`metis.program` 单包 `TOTAL: 8, PASSED: 8, SKIPPED: 0, ERROR: 0, FAILED: 0`。
- 结论：本轮新增 OpenRouter ASR 适配的直接测试和相关 gateway tool 测试均通过；全量聚合运行存在 `metis.program` 包级运行漂移，但单包复核没有业务断言失败。
