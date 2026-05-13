package metis.core.media_tests

import metis.core.*

import metis.core.config.GatewayUserSettings

import std.unittest.*
import stdx.encoding.json.{JsonBool, JsonInt, JsonObject, JsonString}

private func imageConfigTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func imageConfigTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func imageConfigTestObj(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func imageConfigTestProvider(kind: String, model!: String = "gpt-image-1"): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString(kind))
    provider.put("baseUrl", JsonString("https://api.openai.com/v1"))
    provider.put("apiKey", JsonString("test-image-key"))
    provider.put("model", JsonString(model))
    provider.put("timeoutMs", JsonInt(120000))
    provider
}

private func imageConfigTestConfig(provider: String, providerId: String, providerObj: JsonObject): JsonObject {
    let config = JsonObject()
    let providers = JsonObject()
    providers.put(providerId, providerObj)
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString(provider))
    config.put("providers", providers)
    config.put("maxPromptChars", JsonInt(4000))
    config
}

@Test
public class GatewayImageGenerationConfigTest {
    @TestCase
    public func sharedImageGenerationConfigIsUsedForTelegram(): Unit {
        var user = GatewayUserSettings()
        user.media.imageGeneration = imageConfigTestConfig(
            "shared-openai",
            "shared-openai",
            imageConfigTestProvider("openai-images")
        )

        let resolved = gatewayMediaResolveImageGenerationConfig(user, channel: "telegram")
        let provider = imageConfigTestObj(imageConfigTestObj(resolved, "providers"), "shared-openai")

        @Expect(imageConfigTestString(resolved, "provider"), "shared-openai")
        @Expect(imageConfigTestString(provider, "kind"), "openai-images")
    }

    @TestCase
    public func telegramImageGenerationOverridesSharedAndInheritsNetworkContext(): Unit {
        var user = GatewayUserSettings()
        user.media.imageGeneration = imageConfigTestConfig(
            "shared-openai",
            "shared-openai",
            imageConfigTestProvider("openai-images", model: "shared-model")
        )
        user.telegram.imageGeneration = imageConfigTestConfig(
            "telegram-openai",
            "telegram-openai",
            imageConfigTestProvider("openai-images", model: "telegram-model")
        )
        user.telegram.proxy = "http://user:secret@127.0.0.1:7897"
        user.telegram.network.envProxyEnabled = true
        user.telegram.network.insecureSkipTlsVerify = true

        let resolved = gatewayImageGenerationResolveConfig(user, channel: "telegram")
        let providers = imageConfigTestObj(resolved, "providers")
        let provider = imageConfigTestObj(providers, "telegram-openai")

        @Expect(imageConfigTestString(resolved, "provider"), "telegram-openai")
        @Expect(imageConfigTestString(imageConfigTestObj(providers, "shared-openai"), "model"), "shared-model")
        @Expect(imageConfigTestString(provider, "model"), "telegram-model")
        @Expect(imageConfigTestString(provider, "proxy"), "http://user:secret@127.0.0.1:7897")
        @Expect(imageConfigTestBool(provider, "envProxyEnabled"), true)
        @Expect(imageConfigTestBool(provider, "insecureSkipTlsVerify"), true)
    }

    @TestCase
    public func unknownChannelCanUseChannelsExtraImageGeneration(): Unit {
        var user = GatewayUserSettings()
        let extra = JsonObject()
        let custom = JsonObject()
        custom.put("imageGeneration", imageConfigTestConfig(
            "custom-openai",
            "custom-openai",
            imageConfigTestProvider("openai-images", model: "custom-model")
        ))
        extra.put("custom", custom)
        user.channelsExtra = Some<JsonObject>(extra)

        let resolved = gatewayImageGenerationResolveConfig(user, channel: "custom")

        @Expect(imageConfigTestString(resolved, "provider"), "custom-openai")
        @Expect(imageConfigTestString(imageConfigTestObj(imageConfigTestObj(resolved, "providers"), "custom-openai"), "model"), "custom-model")
    }
}
