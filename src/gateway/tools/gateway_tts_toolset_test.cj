package metis.gateway.tools

import metis.core.{GatewaySpeechTtsDashScopeQwenHttpResult, GatewayToolRuntimeContext, gatewayWithToolRuntimeContext, setGatewaySpeechTtsDashScopeQwenRunnerForTest}
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

private func gatewayTtsToolTestHome(label: String): String {
    "/tmp/metis-gateway-tts-toolset-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
}

private func gatewayTtsToolResetEnv(oldHome: Option<String>, home: String): Unit {
    match (oldHome) {
        case Some(value) => setVariable("METIS_HOME", value)
        case None => setVariable("METIS_HOME", "")
    }
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    CliConfig.invalidatePathCache()
    try { remove(Path(home), recursive: true) } catch (_: Exception) { () }
}

private func gatewayTtsToolInstallProviderConfig(home: String): Unit {
    let root = JsonObject()
    let gateway = JsonObject()

    let sharedSpeech = JsonObject()
    let sharedTts = JsonObject()
    sharedTts.put("provider", JsonString("shared"))
    let sharedProviders = JsonObject()
    let sharedProvider = JsonObject()
    sharedProvider.put("kind", JsonString("command"))
    sharedProvider.put("command", JsonArray([
        JsonString("sh"),
        JsonString("-c"),
        JsonString("printf 'shared' > \"$2\""),
        JsonString("metis-tts"),
        JsonString("{text}"),
        JsonString("{output}")
    ]))
    sharedProviders.put("shared", sharedProvider)
    sharedTts.put("providers", sharedProviders)
    sharedSpeech.put("tts", sharedTts)
    gateway.put("speech", sharedSpeech)

    let telegram = JsonObject()
    let telegramSpeech = JsonObject()
    let telegramTts = JsonObject()
    telegramTts.put("provider", JsonString("telegram"))
    let telegramProviders = JsonObject()
    let telegramProvider = JsonObject()
    telegramProvider.put("kind", JsonString("command"))
    telegramProvider.put("outputExtension", JsonString("ogg"))
    telegramProvider.put("command", JsonArray([
        JsonString("sh"),
        JsonString("-c"),
        JsonString("printf 'telegram' > \"$2\""),
        JsonString("metis-tts"),
        JsonString("{text}"),
        JsonString("{output}")
    ]))
    telegramProviders.put("telegram", telegramProvider)
    telegramTts.put("providers", telegramProviders)
    telegramSpeech.put("tts", telegramTts)
    telegramSpeech.put("audioAsVoice", JsonBool(true))
    telegram.put("speech", telegramSpeech)
    gateway.put("telegram", telegram)

    root.put("gateway", gateway)
    MetisConfigManager.writeRoot(root)
    CliSettingManager.invalidate()
    Directory.create(Path(home).join("gateway-tts"), recursive: true)
}

private func gatewayTtsToolInstallDashScopeQwenConfig(home: String, degradeMessage!: String = "语音暂时发送失败，我先打字陪你。"): Unit {
    let root = JsonObject()
    let gateway = JsonObject()
    let speech = JsonObject()
    let tts = JsonObject()
    tts.put("enabled", JsonBool(true))
    tts.put("provider", JsonString("dashscope"))
    tts.put("degradeMessage", JsonString(degradeMessage))
    let providers = JsonObject()
    let provider = JsonObject()
    provider.put("kind", JsonString("dashscope-qwen-tts"))
    provider.put("baseUrl", JsonString("https://dashscope.aliyuncs.com/api/v1"))
    provider.put("apiKey", JsonString("test-dashscope-key"))
    provider.put("model", JsonString("qwen3-tts-flash"))
    provider.put("voice", JsonString("Chelsie"))
    provider.put("languageType", JsonString("Chinese"))
    provider.put("timeoutMs", JsonInt(1000))
    providers.put("dashscope", provider)
    tts.put("providers", providers)
    speech.put("tts", tts)
    gateway.put("speech", speech)

    let telegram = JsonObject()
    let telegramSpeech = JsonObject()
    telegramSpeech.put("audioAsVoice", JsonBool(true))
    telegramSpeech.put("autoReplyToVoice", JsonBool(true))
    telegram.put("speech", telegramSpeech)
    gateway.put("telegram", telegram)

    root.put("gateway", gateway)
    MetisConfigManager.writeRoot(root)
    CliSettingManager.invalidate()
    Directory.create(Path(home).join("gateway-tts"), recursive: true)
}

@Test
public class GatewayTtsToolsetTest {
    @TestCase
    public func ttsToolUsesTelegramOverrideAndReturnsVoicePayload(): Unit {
        let home = gatewayTtsToolTestHome("telegram-override")
        let oldHome = getVariable("METIS_HOME")
        try { remove(Path(home), recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        setVariable("METIS_HOME", home)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        CliConfig.invalidatePathCache()
        gatewayTtsToolInstallProviderConfig(home)

        try {
            let toolset = GatewayTtsToolset()
            let out = toolset.debugTtsForTest("你好", "telegram", true)
            let result = JsonValue.fromStr(out).asObject()
            @Expect(result.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(result.get("action").getOrThrow().asString().getValue(), "tts")
            @Expect(result.get("channel").getOrThrow().asString().getValue(), "telegram")
            @Expect(result.get("provider").getOrThrow().asString().getValue(), "telegram")
            @Expect(result.get("payloadKind").getOrThrow().asString().getValue(), "voice")
            @Expect(result.get("payload").getOrThrow().asString().getValue().startsWith("[voice]"), true)
            @Expect(result.get("payloadPreview").getOrThrow().asString().getValue().contains("[voice]"), true)
            @Expect(result.get("audioPath").getOrThrow().asString().getValue().startsWith(home), true)
        } finally {
            gatewayTtsToolResetEnv(oldHome, home)
        }
    }

    @TestCase
    public func ttsToolReportsNotConfiguredWithoutProvider(): Unit {
        let home = gatewayTtsToolTestHome("not-configured")
        let oldHome = getVariable("METIS_HOME")
        try { remove(Path(home), recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        setVariable("METIS_HOME", home)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        CliConfig.invalidatePathCache()
        MetisConfigManager.writeRoot(JsonObject())
        CliSettingManager.invalidate()

        try {
            let toolset = GatewayTtsToolset()
            let out = toolset.debugTtsForTest("hello", "telegram", true)
            let result = JsonValue.fromStr(out).asObject()
            @Expect(result.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "not_configured")
            @Expect(result.get("action").getOrThrow().asString().getValue(), "tts")
        } finally {
            gatewayTtsToolResetEnv(oldHome, home)
        }
    }

    @TestCase
    public func ttsToolCanReturnAudioPayloadWhenAsVoiceFalse(): Unit {
        let home = gatewayTtsToolTestHome("audio-payload")
        let oldHome = getVariable("METIS_HOME")
        try { remove(Path(home), recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        setVariable("METIS_HOME", home)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        CliConfig.invalidatePathCache()
        gatewayTtsToolInstallProviderConfig(home)

        try {
            let toolset = GatewayTtsToolset()
            let out = toolset.debugTtsForTest("你好", "telegram", false)
            let result = JsonValue.fromStr(out).asObject()
            @Expect(result.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(result.get("payloadKind").getOrThrow().asString().getValue(), "audio")
            @Expect(result.get("payload").getOrThrow().asString().getValue().startsWith("[audio]"), true)
        } finally {
            gatewayTtsToolResetEnv(oldHome, home)
        }
    }

    @TestCase
    public func ttsToolDeliversThroughCurrentRuntimeContext(): Unit {
        let home = gatewayTtsToolTestHome("deliver")
        let oldHome = getVariable("METIS_HOME")
        try { remove(Path(home), recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        setVariable("METIS_HOME", home)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        CliConfig.invalidatePathCache()
        gatewayTtsToolInstallProviderConfig(home)

        let sentTexts = ArrayList<String>()
        debugSetGatewayTtsToolCallRunnerForTest(Some({ method: String, payload: JsonObject =>
            @Expect(method, "channels.send")
            sentTexts.add(payload.get("text").getOrThrow().asString().getValue())
            let out = JsonObject()
            out.put("ok", JsonBool(true))
            out
        }))
        try {
            let toolset = GatewayTtsToolset()
            let context = GatewayToolRuntimeContext(
                "telegram",
                channelName: "telegram",
                sessionKey: "telegram:direct:user:1"
            )
            let out = gatewayWithToolRuntimeContext(context, { =>
                toolset.debugTtsForTest("你好", "telegram", true)
            })
            let result = JsonValue.fromStr(out).asObject()
            @Expect(result.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(result.get("delivered").getOrThrow().asBool().getValue(), true)
            @Expect(context.hasVisibleReplyDelivered(), true)
            @Expect(sentTexts.size, 1)
            @Expect(sentTexts[0].startsWith("[voice]"), true)
        } finally {
            debugSetGatewayTtsToolCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
            gatewayTtsToolResetEnv(oldHome, home)
        }
    }

    @TestCase
    public func ttsToolDashScopeQwenDeliversVoiceAndMarksSilentReply(): Unit {
        let home = gatewayTtsToolTestHome("dashscope-deliver")
        let oldHome = getVariable("METIS_HOME")
        try { remove(Path(home), recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        setVariable("METIS_HOME", home)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        CliConfig.invalidatePathCache()
        gatewayTtsToolInstallDashScopeQwenConfig(home)

        let sentTexts = ArrayList<String>()
        setGatewaySpeechTtsDashScopeQwenRunnerForTest(Some({ request: JsonObject =>
            @Expect(request.get("url").getOrThrow().asString().getValue().endsWith("/services/aigc/multimodal-generation/generation"), true)
            @Expect(request.get("authorization").getOrThrow().asString().getValue(), "Bearer test-dashscope-key")
            let body = request.get("body").getOrThrow().asObject()
            @Expect(body.get("model").getOrThrow().asString().getValue(), "qwen3-tts-flash")
            let input = body.get("input").getOrThrow().asObject()
            @Expect(input.get("text").getOrThrow().asString().getValue(), "你好")
            @Expect(input.get("voice").getOrThrow().asString().getValue(), "Chelsie")
            @Expect(input.get("language_type").getOrThrow().asString().getValue(), "Chinese")
            GatewaySpeechTtsDashScopeQwenHttpResult(200, bodyBytes: "DASH-AUDIO".toArray())
        }))
        debugSetGatewayTtsToolCallRunnerForTest(Some({ method: String, payload: JsonObject =>
            @Expect(method, "channels.send")
            sentTexts.add(payload.get("text").getOrThrow().asString().getValue())
            let out = JsonObject()
            out.put("ok", JsonBool(true))
            out
        }))
        try {
            let toolset = GatewayTtsToolset()
            let context = GatewayToolRuntimeContext(
                "telegram",
                channelName: "telegram",
                sessionKey: "telegram:direct:user:1"
            )
            let out = gatewayWithToolRuntimeContext(context, { =>
                toolset.debugTtsForTest("你好", "telegram", true)
            })
            let result = JsonValue.fromStr(out).asObject()
            @Expect(result.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(result.get("provider").getOrThrow().asString().getValue(), "dashscope")
            @Expect(result.get("providerKind").getOrThrow().asString().getValue(), "dashscope-qwen-tts")
            @Expect(result.get("payloadKind").getOrThrow().asString().getValue(), "voice")
            @Expect(result.get("delivered").getOrThrow().asBool().getValue(), true)
            @Expect(context.hasVisibleReplyDelivered(), true)
            @Expect(sentTexts.size, 1)
            @Expect(sentTexts[0].startsWith("[voice]"), true)
            @Expect(sentTexts[0].contains("caption=TTS (dashscope)"), true)
        } finally {
            debugSetGatewayTtsToolCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
            setGatewaySpeechTtsDashScopeQwenRunnerForTest(None<(JsonObject) -> GatewaySpeechTtsDashScopeQwenHttpResult>)
            gatewayTtsToolResetEnv(oldHome, home)
        }
    }

    @TestCase
    public func ttsToolDashScopeQwenFailureUsesDegradeMessageWithProviderAttempt(): Unit {
        let home = gatewayTtsToolTestHome("dashscope-degrade")
        let oldHome = getVariable("METIS_HOME")
        try { remove(Path(home), recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        setVariable("METIS_HOME", home)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        CliConfig.invalidatePathCache()
        gatewayTtsToolInstallDashScopeQwenConfig(home, degradeMessage: "语音暂时发送失败，我先打字陪你。")

        setGatewaySpeechTtsDashScopeQwenRunnerForTest(Some({ _request: JsonObject =>
            GatewaySpeechTtsDashScopeQwenHttpResult(404, bodyBytes: "{\"message\":\"not found\"}".toArray())
        }))
        try {
            let toolset = GatewayTtsToolset()
            let out = toolset.debugTtsForTest("你好", "telegram", true)
            let result = JsonValue.fromStr(out).asObject()
            @Expect(result.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(result.get("status").getOrThrow().asString().getValue(), "degraded")
            @Expect(result.get("payloadKind").getOrThrow().asString().getValue(), "text")
            @Expect(result.get("payload").getOrThrow().asString().getValue(), "语音暂时发送失败，我先打字陪你。")
            let attempt = result.get("attempts").getOrThrow().asArray().getItems()[0].asObject()
            @Expect(attempt.get("providerKind").getOrThrow().asString().getValue(), "dashscope-qwen-tts")
            @Expect(attempt.get("reasonCode").getOrThrow().asString().getValue(), "provider_error")
        } finally {
            setGatewaySpeechTtsDashScopeQwenRunnerForTest(None<(JsonObject) -> GatewaySpeechTtsDashScopeQwenHttpResult>)
            gatewayTtsToolResetEnv(oldHome, home)
        }
    }
}
