package metis.core.speech_tests

import metis.core.*

import std.collection.ArrayList
import std.fs.{Directory, File, Path}
import std.env.{getVariable, setVariable}
import std.time.*
import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func asrTestTempRoot(label: String): Path {
    let root = Path("/tmp/metis-speech-asr-runtime-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
    Directory.create(root, recursive: true)
    root
}

private func asrTestProvider(command: Array<String>, timeoutMs!: Int64 = 3000): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("command"))
    let commandJson = JsonArray()
    for (part in command) {
        commandJson.add(JsonString(part))
    }
    provider.put("command", commandJson)
    provider.put("timeoutMs", JsonInt(timeoutMs))
    provider
}

private func asrTestOpenAICompatibleProvider(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("openai-compatible"))
    provider.put("apiKey", JsonString("test-asr-api-key"))
    provider.put("baseUrl", JsonString("https://asr.example.invalid/v1/"))
    provider.put("model", JsonString("whisper-1"))
    provider.put("language", JsonString("zh"))
    provider.put("timeoutMs", JsonInt(12000))
    provider.put("maxBytes", JsonInt(8192))
    provider
}

private func asrTestOpenRouterProvider(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("openai-compatible"))
    provider.put("baseUrl", JsonString("https://openrouter.ai/api/v1"))
    provider.put("apiKey", JsonString("test-openrouter-key"))
    provider.put("model", JsonString("openai/whisper-large-v3-turbo"))
    provider.put("requestFormat", JsonString("openrouter-input-audio-json"))
    provider.put("language", JsonString("zh"))
    provider.put("timeoutMs", JsonInt(12000))
    provider.put("maxBytes", JsonInt(8192))
    provider.put("insecureSkipTlsVerify", JsonBool(true))
    provider
}

private func asrTestOpenRouterProviderWithoutRequestFormat(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("openai-compatible"))
    provider.put("baseUrl", JsonString("https://openrouter.ai/api/v1"))
    provider.put("apiKey", JsonString("test-openrouter-key"))
    provider.put("model", JsonString("openai/whisper-large-v3-turbo"))
    provider.put("language", JsonString(""))
    provider.put("timeoutMs", JsonInt(12000))
    provider.put("maxBytes", JsonInt(8192))
    provider.put("insecureSkipTlsVerify", JsonBool(true))
    provider
}

private func asrTestConfig(providerId: String, provider: JsonObject): JsonObject {
    let config = JsonObject()
    let providers = JsonObject()
    providers.put(providerId, provider)
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString(providerId))
    config.put("providers", providers)
    config
}

private func asrTestObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func asrTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func asrTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

@Test
public class GatewaySpeechAsrRuntimeTest {
    @TestCase
    public func commandProviderCanReturnTranscriptViaStdout(): Unit {
        let root = asrTestTempRoot("stdout")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        let provider = asrTestProvider(["sh", "-c", "printf 'stdout transcript'"])
        let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("local", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 8192)

        @Expect(asrTestBool(result, "ok"), true)
        @Expect(asrTestString(result, "status"), "ok")
        @Expect(asrTestString(result, "transcript"), "stdout transcript")
        @Expect(asrTestString(result, "providerKind"), "command")
    }

    @TestCase
    public func commandProviderCanReturnTranscriptViaOutputFile(): Unit {
        let root = asrTestTempRoot("output")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        let provider = asrTestProvider(["sh", "-c", "printf 'file transcript' > \"$1\"", "metis-asr", "{output}"])
        let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("local", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 8192)

        @Expect(asrTestBool(result, "ok"), true)
        @Expect(asrTestString(result, "transcript"), "file transcript")
    }

    @TestCase
    public func commandProviderNonZeroExitDoesNotExposeStderrSecrets(): Unit {
        let root = asrTestTempRoot("nonzero")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        let provider = asrTestProvider(["sh", "-c", "echo \"$METIS_ASR_SECRET\" >&2; exit 8"])
        let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("local", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 8192)

        @Expect(asrTestBool(result, "ok"), false)
        @Expect(asrTestString(result, "status"), "provider_error")
        @Expect(asrTestString(result, "message").contains("asr-secret-value"), false)
        @Expect(asrTestString(result, "stderr").contains("asr-secret-value"), false)
    }

    @TestCase
    public func commandProviderTimeoutReturnsTimeoutStatus(): Unit {
        let root = asrTestTempRoot("timeout")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        let provider = asrTestProvider(["sh", "-c", "sleep 2"], timeoutMs: 1)
        let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("local", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 8192)

        @Expect(asrTestBool(result, "ok"), false)
        @Expect(asrTestString(result, "status"), "timeout")
    }

    @TestCase
    public func missingProviderReturnsNotConfigured(): Unit {
        let root = asrTestTempRoot("missing")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        let result = gatewaySpeechAsrTranscribeAudioPath(JsonObject(), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 8192)

        @Expect(asrTestBool(result, "ok"), false)
        @Expect(asrTestString(result, "status"), "not_configured")
    }

    @TestCase
    public func maxBytesRejectsBeforeCommandExecution(): Unit {
        let root = asrTestTempRoot("large")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        let provider = asrTestProvider(["sh", "-c", "printf 'should-not-run'"])
        let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("local", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 1)

        @Expect(asrTestBool(result, "ok"), false)
        @Expect(asrTestString(result, "status"), "too_large")
        @Expect(asrTestString(result, "transcript"), "")
    }

    @TestCase
    public func openAICompatibleProviderPostsTranscriptionRequestAndParsesPlainText(): Unit {
        let root = asrTestTempRoot("openai-plain")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio-openai".toArray())
        let sawRequests = ArrayList<String>()
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ request: JsonObject =>
            sawRequests.add("yes")
            let fields = asrTestObject(request, "fields")
            @Expect(asrTestString(request, "url"), "https://asr.example.invalid/v1/audio/transcriptions")
            @Expect(asrTestString(request, "authorization"), "Bearer test-asr-api-key")
            @Expect(asrTestString(request, "filePath"), audio.toString())
            @Expect(asrTestString(request, "mime"), "audio/ogg")
            @Expect(asrTestString(fields, "model"), "whisper-1")
            @Expect(asrTestString(fields, "language"), "zh")
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "plain transcript".toArray(), contentType: "text/plain")
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openai", asrTestOpenAICompatibleProvider()), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)

            @Expect(sawRequests.size, 1)
            @Expect(asrTestBool(result, "ok"), true)
            @Expect(asrTestString(result, "status"), "ok")
            @Expect(asrTestString(result, "provider"), "openai")
            @Expect(asrTestString(result, "providerKind"), "openai-compatible")
            @Expect(asrTestString(result, "transcript"), "plain transcript")
            @Expect(result.toJsonString().contains("test-asr-api-key"), false)
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func openRouterAsrProviderBuildsInputAudioJsonRequest(): Unit {
        let root = asrTestTempRoot("openrouter-json")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-openrouter-audio".toArray())
        let sawRequests = ArrayList<String>()
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ request: JsonObject =>
            sawRequests.add("yes")
            let body = asrTestObject(request, "body")
            let inputAudio = asrTestObject(body, "input_audio")
            let data = asrTestString(inputAudio, "data")
            @Expect(asrTestString(request, "url"), "https://openrouter.ai/api/v1/audio/transcriptions")
            @Expect(asrTestString(request, "authorization"), "Bearer test-openrouter-key")
            @Expect(asrTestString(request, "requestFormat"), "openrouter-input-audio-json")
            @Expect(asrTestString(request, "contentType"), "application/json")
            @Expect(asrTestString(body, "model"), "openai/whisper-large-v3-turbo")
            @Expect(asrTestString(body, "language"), "zh")
            @Expect(asrTestString(inputAudio, "format"), "ogg")
            @Expect(data.isEmpty(), false)
            @Expect(data == audio.toString(), false)
            @Expect(request.toJsonString().contains(audio.toString()), false)
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "{\"text\":\"openrouter transcript\"}".toArray(), contentType: "application/json")
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openrouter", asrTestOpenRouterProvider()), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)

            @Expect(sawRequests.size, 1)
            @Expect(asrTestBool(result, "ok"), true)
            @Expect(asrTestString(result, "transcript"), "openrouter transcript")
            @Expect(result.toJsonString().contains("test-openrouter-key"), false)
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func openRouterAsrProviderInfersRequestFormatFromBaseUrl(): Unit {
        let root = asrTestTempRoot("openrouter-infer")
        let audio = root.join("voice.wav")
        File.writeTo(audio, "fake-openrouter-wav".toArray())
        let provider = asrTestOpenRouterProviderWithoutRequestFormat()
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ request: JsonObject =>
            let body = asrTestObject(request, "body")
            let inputAudio = asrTestObject(body, "input_audio")
            @Expect(asrTestString(request, "requestFormat"), "openrouter-input-audio-json")
            @Expect(asrTestString(body, "language"), "")
            @Expect(asrTestString(inputAudio, "format"), "wav")
            @Expect(request.toJsonString().contains(audio.toString()), false)
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "inferred transcript".toArray(), contentType: "text/plain")
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openrouter", provider), audio.toString(), "audio/wav", outputRoot: root, maxBytes: 0)

            @Expect(asrTestBool(result, "ok"), true)
            @Expect(asrTestString(result, "transcript"), "inferred transcript")
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func openRouterAsrParsesJsonText(): Unit {
        let root = asrTestTempRoot("openrouter-success")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-openrouter-success".toArray())
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ _request: JsonObject =>
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "{\"text\":\"语音测试喽\"}".toArray(), contentType: "application/json")
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openrouter", asrTestOpenRouterProvider()), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)

            @Expect(asrTestBool(result, "ok"), true)
            @Expect(asrTestString(result, "transcript"), "语音测试喽")
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func openRouterAsrMapsInputAudioValidationErrorToProviderError(): Unit {
        let root = asrTestTempRoot("openrouter-400")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-openrouter-validation".toArray())
        let encodedData = ArrayList<String>()
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ request: JsonObject =>
            let body = asrTestObject(request, "body")
            encodedData.add(asrTestString(asrTestObject(body, "input_audio"), "data"))
            GatewaySpeechAsrOpenAICompatibleHttpResult(
                400,
                bodyBytes: "{\"success\":false,\"error\":{\"name\":\"ZodError\",\"message\":\"path input_audio Invalid input: expected object\"}}".toArray(),
                contentType: "application/json"
            )
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openrouter", asrTestOpenRouterProvider()), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)
            let resultJson = result.toJsonString()

            @Expect(asrTestBool(result, "ok"), false)
            @Expect(asrTestString(result, "status"), "provider_error")
            @Expect(asrTestString(result, "message").contains("input_audio"), true)
            @Expect(resultJson.contains("test-openrouter-key"), false)
            @Expect(resultJson.contains("Authorization"), false)
            @Expect(resultJson.contains(audio.toString()), false)
            @Expect(encodedData.size, 1)
            @Expect(resultJson.contains(encodedData[0]), false)
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func openRouterAsrMaxBytesRejectsBeforeBase64RequestBuild(): Unit {
        let root = asrTestTempRoot("openrouter-too-large")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-openrouter-too-large".toArray())
        let sawRequests = ArrayList<String>()
        let provider = asrTestOpenRouterProvider()
        provider.put("maxBytes", JsonInt(1))
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ _request: JsonObject =>
            sawRequests.add("unexpected")
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "should not run".toArray())
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openrouter", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)

            @Expect(sawRequests.size, 0)
            @Expect(asrTestBool(result, "ok"), false)
            @Expect(asrTestString(result, "status"), "too_large")
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func openAICompatibleProviderParsesJsonTextAndResolvesEnvApiKey(): Unit {
        let root = asrTestTempRoot("openai-json-env")
        let audio = root.join("voice.wav")
        File.writeTo(audio, "fake-audio-openai-json".toArray())
        let envKey = "METIS_ASR_TEST_API_KEY_${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
        let old = getVariable(envKey)
        setVariable(envKey, "env-asr-api-key")
        let provider = asrTestOpenAICompatibleProvider()
        provider.put("apiKey", JsonString("$" + "{" + envKey + "}"))
        provider.put("language", JsonString(""))
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ request: JsonObject =>
            let fields = asrTestObject(request, "fields")
            @Expect(asrTestString(request, "authorization"), "Bearer env-asr-api-key")
            @Expect(asrTestString(fields, "model"), "whisper-1")
            @Expect(asrTestString(fields, "language"), "")
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "{\"text\":\"json transcript\"}".toArray(), contentType: "application/json")
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openai", provider), audio.toString(), "audio/wav", outputRoot: root, maxBytes: 0)

            @Expect(asrTestBool(result, "ok"), true)
            @Expect(asrTestString(result, "transcript"), "json transcript")
            @Expect(result.toJsonString().contains("env-asr-api-key"), false)
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
            match (old) {
                case Some(value) => setVariable(envKey, value)
                case None => setVariable(envKey, "")
            }
        }
    }

    @TestCase
    public func openAICompatibleProviderMapsAuthServerTimeoutAndEmptyResponses(): Unit {
        let root = asrTestTempRoot("openai-errors")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio-openai-errors".toArray())
        let config = asrTestConfig("openai", asrTestOpenAICompatibleProvider())

        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ _request: JsonObject =>
            GatewaySpeechAsrOpenAICompatibleHttpResult(401, bodyBytes: "{\"error\":\"bad key\"}".toArray())
        }))
        try {
            let auth = gatewaySpeechAsrTranscribeAudioPath(config, audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)
            @Expect(asrTestBool(auth, "ok"), false)
            @Expect(asrTestString(auth, "status"), "auth_error")
            @Expect(auth.toJsonString().contains("test-asr-api-key"), false)
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }

        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ _request: JsonObject =>
            GatewaySpeechAsrOpenAICompatibleHttpResult(500, bodyBytes: "server failed".toArray())
        }))
        try {
            let server = gatewaySpeechAsrTranscribeAudioPath(config, audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)
            @Expect(asrTestBool(server, "ok"), false)
            @Expect(asrTestString(server, "status"), "provider_error")
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }

        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ _request: JsonObject =>
            GatewaySpeechAsrOpenAICompatibleHttpResult(408, error: "timeout")
        }))
        try {
            let timeout = gatewaySpeechAsrTranscribeAudioPath(config, audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)
            @Expect(asrTestBool(timeout, "ok"), false)
            @Expect(asrTestString(timeout, "status"), "timeout")
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }

        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ _request: JsonObject =>
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "{\"text\":\"   \"}".toArray(), contentType: "application/json")
        }))
        try {
            let empty = gatewaySpeechAsrTranscribeAudioPath(config, audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)
            @Expect(asrTestBool(empty, "ok"), false)
            @Expect(asrTestString(empty, "status"), "empty_result")
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func openAICompatibleProviderMaxBytesRejectsBeforeHttpRequest(): Unit {
        let root = asrTestTempRoot("openai-too-large")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio-openai-too-large".toArray())
        let sawRequests = ArrayList<String>()
        let provider = asrTestOpenAICompatibleProvider()
        provider.put("maxBytes", JsonInt(1))
        setGatewaySpeechAsrOpenAICompatibleRunnerForTest(Some({ _request: JsonObject =>
            sawRequests.add("unexpected")
            GatewaySpeechAsrOpenAICompatibleHttpResult(200, bodyBytes: "should not run".toArray())
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("openai", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)

            @Expect(sawRequests.size, 0)
            @Expect(asrTestBool(result, "ok"), false)
            @Expect(asrTestString(result, "status"), "too_large")
        } finally {
            setGatewaySpeechAsrOpenAICompatibleRunnerForTest(None<(JsonObject) -> GatewaySpeechAsrOpenAICompatibleHttpResult>)
        }
    }

    @TestCase
    public func tencentFlashProviderIsAvailableThroughUnifiedAsrRuntime(): Unit {
        let root = asrTestTempRoot("tencent-runtime")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio-tencent-runtime".toArray())
        let provider = JsonObject()
        provider.put("kind", JsonString("tencent-flash"))
        provider.put("appId", JsonString("123456"))
        provider.put("secretId", JsonString("test-secret-id"))
        provider.put("secretKey", JsonString("test-secret-key"))
        provider.put("engineType", JsonString("16k_zh"))
        let sawRequests = ArrayList<String>()
        setGatewaySpeechAsrTencentFlashRunnerForTest(Some({ request: JsonObject, audioBytes: Array<Byte> =>
            sawRequests.add("yes")
            @Expect(asrTestString(request, "url").startsWith("https://asr.cloud.tencent.com/asr/flash/v1/123456?"), true)
            @Expect(asrTestString(request, "authorization").isEmpty(), false)
            @Expect(audioBytes.size > 0, true)
            GatewaySpeechAsrTencentFlashHttpResult(200, body: "{\"code\":0,\"flash_result\":[{\"text\":\"腾讯转写结果\"}]}")
        }))
        try {
            let result = gatewaySpeechAsrTranscribeAudioPath(asrTestConfig("tencent", provider), audio.toString(), "audio/ogg", outputRoot: root, maxBytes: 0)

            @Expect(sawRequests.size, 1)
            @Expect(asrTestBool(result, "ok"), true)
            @Expect(asrTestString(result, "status"), "ok")
            @Expect(asrTestString(result, "provider"), "tencent")
            @Expect(asrTestString(result, "providerKind"), "tencent-flash")
            @Expect(asrTestString(result, "transcript"), "腾讯转写结果")
            @Expect(result.toJsonString().contains("test-secret-key"), false)
        } finally {
            setGatewaySpeechAsrTencentFlashRunnerForTest(None<(JsonObject, Array<Byte>) -> GatewaySpeechAsrTencentFlashHttpResult>)
        }
    }
}
