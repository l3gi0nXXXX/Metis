package metis.core.media_tests

import metis.core.*

import metis.core.config.GatewayUserSettings

import std.unittest.*
import stdx.encoding.json.{JsonBool, JsonInt, JsonObject, JsonString}

private func mediaConfigTestProvider(kind: String, model: String): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString(kind))
    provider.put("model", JsonString(model))
    provider
}

private func mediaConfigTestConfig(providerId: String, provider: JsonObject): JsonObject {
    let providers = JsonObject()
    providers.put(providerId, provider)
    let config = JsonObject()
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString(providerId))
    config.put("providers", providers)
    return config
}

private func mediaConfigString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func mediaConfigObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

@Test
public class GatewayMediaConfigTest {
    @TestCase
    public func sharedVideoConfigIsUsedWhenChannelOverrideMissing(): Unit {
        var user = GatewayUserSettings()
        user.media.video = mediaConfigTestConfig("shared-gemini", mediaConfigTestProvider("gemini-inline-video", "gemini-shared"))

        let config = gatewayMediaResolveVideoConfig(user, channel: "telegram")
        @Expect(mediaConfigString(config, "provider"), "shared-gemini")
        @Expect(mediaConfigString(mediaConfigObject(mediaConfigObject(config, "providers"), "shared-gemini"), "model"), "gemini-shared")
    }

    @TestCase
    public func telegramVideoConfigOverridesSharedProviderAndMergesProviderMap(): Unit {
        var user = GatewayUserSettings()
        user.media.video = mediaConfigTestConfig("shared-gemini", mediaConfigTestProvider("gemini-inline-video", "gemini-shared"))
        user.media.video.put("maxBytes", JsonInt(1000))
        user.telegram.video = mediaConfigTestConfig("telegram-gemini", mediaConfigTestProvider("gemini-inline-video", "gemini-telegram"))
        user.telegram.video.put("maxBytes", JsonInt(500))

        let config = gatewayMediaResolveVideoConfig(user, channel: "telegram")
        let providers = mediaConfigObject(config, "providers")
        @Expect(mediaConfigString(config, "provider"), "telegram-gemini")
        @Expect(mediaConfigString(mediaConfigObject(providers, "shared-gemini"), "model"), "gemini-shared")
        @Expect(mediaConfigString(mediaConfigObject(providers, "telegram-gemini"), "model"), "gemini-telegram")
        @Expect(config.get("maxBytes").getOrThrow().asInt().getValue(), 500)
    }

    @TestCase
    public func missingVideoProviderDoesNotLookConfigured(): Unit {
        let config = gatewayMediaResolveVideoConfig(GatewayUserSettings(), channel: "telegram")
        @Expect(mediaConfigString(config, "provider"), "")
        @Expect(mediaConfigObject(config, "providers").size(), 0)
    }
}
