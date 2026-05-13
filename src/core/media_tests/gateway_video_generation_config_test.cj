package metis.core.media_tests

import metis.core.*

import metis.core.config.GatewayUserSettings

import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func videoConfigTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func videoConfigTestObj(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func videoConfigTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func videoConfigTestProvider(kind: String, model!: String = "wan2.5-t2v-preview"): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString(kind))
    provider.put("baseUrl", JsonString("https://dashscope.aliyuncs.com"))
    provider.put("apiKey", JsonString("test-video-key"))
    provider.put("model", JsonString(model))
    provider.put("timeoutMs", JsonInt(120000))
    provider
}

private func videoConfigTestConfig(provider: String, providerId: String, providerObj: JsonObject): JsonObject {
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
public class GatewayVideoGenerationConfigTest {
    @TestCase
    public func sharedVideoGenerationConfigIsUsedForTelegramWhenChannelMissing(): Unit {
        var user = GatewayUserSettings()
        user.media.videoGeneration = videoConfigTestConfig(
            "shared-wan",
            "shared-wan",
            videoConfigTestProvider("dashscope-qwen-video-generation")
        )

        let resolved = gatewayMediaResolveVideoGenerationConfig(user, channel: "telegram")
        let provider = videoConfigTestObj(videoConfigTestObj(resolved, "providers"), "shared-wan")

        @Expect(videoConfigTestString(resolved, "provider"), "shared-wan")
        @Expect(videoConfigTestString(provider, "kind"), "dashscope-qwen-video-generation")
    }

    @TestCase
    public func telegramVideoGenerationProviderOverridesSharedAndKeepsSharedProviders(): Unit {
        var user = GatewayUserSettings()
        user.media.videoGeneration = videoConfigTestConfig(
            "shared-wan",
            "shared-wan",
            videoConfigTestProvider("dashscope-qwen-video-generation", model: "wan-shared")
        )
        user.telegram.videoGeneration = videoConfigTestConfig(
            "telegram-wan",
            "telegram-wan",
            videoConfigTestProvider("dashscope-qwen-video-generation", model: "wan-telegram")
        )

        let resolved = gatewayMediaResolveVideoGenerationConfig(user, channel: "telegram")
        let providers = videoConfigTestObj(resolved, "providers")

        @Expect(videoConfigTestString(resolved, "provider"), "telegram-wan")
        @Expect(videoConfigTestString(videoConfigTestObj(providers, "shared-wan"), "model"), "wan-shared")
        @Expect(videoConfigTestString(videoConfigTestObj(providers, "telegram-wan"), "model"), "wan-telegram")
    }

    @TestCase
    public func channelProviderDeepMergesSameNamedSharedProvider(): Unit {
        var user = GatewayUserSettings()
        user.media.videoGeneration = videoConfigTestConfig(
            "wan",
            "wan",
            videoConfigTestProvider("dashscope-qwen-video-generation", model: "wan-shared")
        )
        let overrideProvider = JsonObject()
        overrideProvider.put("model", JsonString("wan-channel"))
        user.telegram.videoGeneration = videoConfigTestConfig("wan", "wan", overrideProvider)

        let provider = videoConfigTestObj(videoConfigTestObj(gatewayMediaResolveVideoGenerationConfig(user, channel: "telegram"), "providers"), "wan")

        @Expect(videoConfigTestString(provider, "kind"), "dashscope-qwen-video-generation")
        @Expect(videoConfigTestString(provider, "model"), "wan-channel")
        @Expect(videoConfigTestString(provider, "apiKey"), "test-video-key")
    }

    @TestCase
    public func missingVideoGenerationConfigReturnsEmptyProviders(): Unit {
        let resolved = gatewayMediaResolveVideoGenerationConfig(GatewayUserSettings(), channel: "telegram")

        @Expect(videoConfigTestString(resolved, "provider"), "")
        @Expect(videoConfigTestObj(resolved, "providers").size(), 0)
    }

    @TestCase
    public func unknownChannelCanUseChannelsExtraVideoGenerationOverride(): Unit {
        var user = GatewayUserSettings()
        user.media.videoGeneration = videoConfigTestConfig(
            "shared-wan",
            "shared-wan",
            videoConfigTestProvider("dashscope-qwen-video-generation", model: "wan-shared")
        )
        let extra = JsonObject()
        let custom = JsonObject()
        custom.put("videoGeneration", videoConfigTestConfig(
            "custom-wan",
            "custom-wan",
            videoConfigTestProvider("dashscope-qwen-video-generation", model: "wan-custom")
        ))
        extra.put("custom", custom)
        user.channelsExtra = Some<JsonObject>(extra)

        let resolved = gatewayMediaResolveVideoGenerationConfig(user, channel: "custom")

        @Expect(videoConfigTestString(resolved, "provider"), "custom-wan")
        @Expect(videoConfigTestString(videoConfigTestObj(videoConfigTestObj(resolved, "providers"), "custom-wan"), "model"), "wan-custom")
    }

    @TestCase
    public func telegramVideoGenerationInheritsTelegramNetworkContextWhenProviderDoesNotOverrideIt(): Unit {
        var user = GatewayUserSettings()
        user.media.videoGeneration = videoConfigTestConfig(
            "shared-wan",
            "shared-wan",
            videoConfigTestProvider("dashscope-qwen-video-generation")
        )
        user.telegram.proxy = "http://user:secret@127.0.0.1:7897"
        user.telegram.network.envProxyEnabled = true
        user.telegram.network.insecureSkipTlsVerify = true

        let resolved = gatewayMediaResolveVideoGenerationConfig(user, channel: "telegram")
        let provider = videoConfigTestObj(videoConfigTestObj(resolved, "providers"), "shared-wan")

        @Expect(videoConfigTestString(provider, "proxy"), "http://user:secret@127.0.0.1:7897")
        @Expect(videoConfigTestBool(provider, "envProxyEnabled"), true)
        @Expect(videoConfigTestBool(provider, "insecureSkipTlsVerify"), true)
    }

    @TestCase
    public func nonTelegramVideoGenerationDoesNotInheritTelegramProxy(): Unit {
        var user = GatewayUserSettings()
        user.media.videoGeneration = videoConfigTestConfig(
            "shared-wan",
            "shared-wan",
            videoConfigTestProvider("dashscope-qwen-video-generation")
        )
        user.telegram.proxy = "http://user:secret@127.0.0.1:7897"
        user.telegram.network.envProxyEnabled = true
        user.telegram.network.insecureSkipTlsVerify = true

        let resolved = gatewayMediaResolveVideoGenerationConfig(user, channel: "feishu")
        let provider = videoConfigTestObj(videoConfigTestObj(resolved, "providers"), "shared-wan")

        @Expect(provider.get("proxy").isNone(), true)
        @Expect(provider.get("envProxyEnabled").isNone(), true)
        @Expect(provider.get("insecureSkipTlsVerify").isNone(), true)
    }
}
