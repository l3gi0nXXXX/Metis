package metis.core.media_tests

import metis.core.*
import metis.core.config.{CliConfig, GatewayUserSettings}
import metis.core.model.modelVisionSupportToString

import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func imageUnderstandingTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func imageUnderstandingTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func imageUnderstandingTestObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func imageUnderstandingModel(provider: String, model: String): JsonObject {
    let entry = JsonObject()
    entry.put("provider", JsonString(provider))
    entry.put("model", JsonString(model))
    entry.put("capabilities", JsonArray([JsonString("image")]))
    entry
}

private func imageUnderstandingConfig(provider: String, model: String, providerId!: String = "vision"): JsonObject {
    let providers = JsonObject()
    let providerConfig = JsonObject()
    providerConfig.put("kind", JsonString("chat-vision"))
    providerConfig.put("model", JsonString(model))
    providers.put(providerId, providerConfig)

    let models = JsonArray([])
    models.add(imageUnderstandingModel(provider, model))

    let config = JsonObject()
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString(providerId))
    config.put("providers", providers)
    config.put("models", models)
    config.put("maxBytes", JsonInt(1048576))
    return config
}

@Test
public class GatewayMediaImageConfigTest {
    @TestCase
    public func sharedImageConfigIsUsedForChannelsAndDefaultsAreFilled(): Unit {
        var user = GatewayUserSettings()
        user.media.image = imageUnderstandingConfig("qwen", "qwen-vl-max", providerId: "shared-qwen")

        let resolved = gatewayMediaResolveImageConfig(user, channel: "feishu")

        @Expect(imageUnderstandingTestString(resolved, "provider"), "shared-qwen")
        @Expect(imageUnderstandingTestBool(resolved, "enabled"), true)
        @Expect(imageUnderstandingTestString(imageUnderstandingTestObject(imageUnderstandingTestObject(resolved, "providers"), "shared-qwen"), "model"), "qwen-vl-max")
        @Expect(resolved.get("models").getOrThrow().asArray().size(), 1)
    }

    @TestCase
    public func telegramImageOverrideDeepMergesSharedProvidersAndTransportContext(): Unit {
        var user = GatewayUserSettings()
        user.media.image = imageUnderstandingConfig("qwen", "qwen-vl-max", providerId: "shared-qwen")
        user.telegram.image = imageUnderstandingConfig("openai", "gpt-4o", providerId: "telegram-openai")
        user.telegram.proxy = "http://user:secret@127.0.0.1:7897"
        user.telegram.network.envProxyEnabled = true
        user.telegram.network.insecureSkipTlsVerify = true

        let resolved = gatewayImageUnderstandingResolveConfig(user, channel: "telegram")
        let providers = imageUnderstandingTestObject(resolved, "providers")
        let telegramProvider = imageUnderstandingTestObject(providers, "telegram-openai")

        @Expect(imageUnderstandingTestString(resolved, "provider"), "telegram-openai")
        @Expect(imageUnderstandingTestString(imageUnderstandingTestObject(providers, "shared-qwen"), "model"), "qwen-vl-max")
        @Expect(imageUnderstandingTestString(telegramProvider, "model"), "gpt-4o")
        @Expect(imageUnderstandingTestString(telegramProvider, "proxy"), "http://user:secret@127.0.0.1:7897")
        @Expect(imageUnderstandingTestBool(telegramProvider, "envProxyEnabled"), true)
        @Expect(imageUnderstandingTestBool(telegramProvider, "insecureSkipTlsVerify"), true)
    }

    @TestCase
    public func candidatesPreferImageConfigThenImageModelAndSkipDeepseekLegacyPrimary(): Unit {
        var user = GatewayUserSettings()
        user.media.image = imageUnderstandingConfig("custom", "vision-x", providerId: "shared-custom")
        user.channelModels.add("telegram", "deepseek/deepseek-v4-pro")

        let oldModel = CliConfig.modelOrEmpty()
        let oldFallbacks = CliConfig.fallbackModels
        let oldImageModel = CliConfig.imageModelOrEmpty()
        let oldImageFallbacks = CliConfig.imageFallbackModels
        try {
            CliConfig.model = "deepseek:deepseek-v4-pro"
            CliConfig.fallbackModels = ["openai:gpt-4o"]
            CliConfig.imageModel = "dashscope:qwen-vl-max"
            CliConfig.imageFallbackModels = ["openai:gpt-4.1"]

            let candidates = gatewayImageUnderstandingBuildCandidates(user, channel: "telegram")

            @Expect(candidates.size, 4)
            @Expect(candidates[0].modelRef, "custom:vision-x")
            @Expect(candidates[0].source, "gateway.media.image.models")
            @Expect(candidates[1].modelRef, "dashscope:qwen-vl-max")
            @Expect(candidates[1].source, "agents.defaults.imageModel.primary")
            @Expect(candidates[2].modelRef, "openai:gpt-4.1")
            @Expect(candidates[2].source, "agents.defaults.imageModel.fallbacks")
            @Expect(candidates[3].modelRef, "openai:gpt-4o")
            @Expect(candidates[3].source, "agents.defaults.model.fallbacks")
            @Expect(modelVisionSupportToString(candidates[3].decision.vision), "supported")
        } finally {
            if (oldModel.isEmpty()) {
                CliConfig.clearPrimaryModelForTest()
            } else {
                CliConfig.model = oldModel
            }
            CliConfig.fallbackModels = oldFallbacks
            if (oldImageModel.isEmpty()) {
                CliConfig.clearImageModelForTest()
            } else {
                CliConfig.imageModel = oldImageModel
            }
            CliConfig.imageFallbackModels = oldImageFallbacks
        }
    }

    @TestCase
    public func diagnosticSnapshotIncludesRejectedLegacyTextModelsWithoutSecrets(): Unit {
        var user = GatewayUserSettings()
        user.channelModels.add("telegram", "deepseek/deepseek-v4-pro")

        let oldModel = CliConfig.modelOrEmpty()
        let oldFallbacks = CliConfig.fallbackModels
        let oldImageModel = CliConfig.imageModelOrEmpty()
        let oldImageFallbacks = CliConfig.imageFallbackModels
        try {
            CliConfig.model = "deepseek:deepseek-v4-pro"
            CliConfig.fallbackModels = []
            CliConfig.clearImageModelForTest()
            CliConfig.imageFallbackModels = []

            let snapshot = gatewayImageUnderstandingDiagnosticSnapshot(user, channel: "telegram")

            @Expect(imageUnderstandingTestBool(snapshot, "configured"), false)
            @Expect(snapshot.get("candidates").getOrThrow().asArray().size(), 0)
            @Expect(snapshot.get("rejected").getOrThrow().asArray().size(), 2)
            @Expect(snapshot.toJsonString().contains("deepseek-v4-pro"), true)
            @Expect(snapshot.toJsonString().contains("secret"), false)
        } finally {
            if (oldModel.isEmpty()) {
                CliConfig.clearPrimaryModelForTest()
            } else {
                CliConfig.model = oldModel
            }
            CliConfig.fallbackModels = oldFallbacks
            if (oldImageModel.isEmpty()) {
                CliConfig.clearImageModelForTest()
            } else {
                CliConfig.imageModel = oldImageModel
            }
            CliConfig.imageFallbackModels = oldImageFallbacks
        }
    }
}
