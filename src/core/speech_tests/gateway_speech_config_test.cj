package metis.core.speech_tests

import metis.core.*

import metis.core.config.GatewayUserSettings

import std.convert.*
import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func speechTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func speechTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func speechTestInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { Int64.parse(v.toJsonString()) } catch (_: Exception) { 0 }
        case None => 0
    }
}

private func speechTestObj(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func speechTestCommandProvider(kind: String, outputExtension!: String = "mp3"): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString(kind))
    provider.put("command", JsonArray([JsonString("speech-bin"), JsonString("{text}"), JsonString("{output}")]))
    provider.put("outputExtension", JsonString(outputExtension))
    provider.put("timeoutMs", JsonInt(10000))
    provider
}

private func speechTestConfig(provider: String, providerId: String, providerObj: JsonObject): JsonObject {
    let config = JsonObject()
    let providers = JsonObject()
    providers.put(providerId, providerObj)
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString(provider))
    config.put("providers", providers)
    config
}

@Test
public class GatewaySpeechConfigTest {
    @TestCase
    public func ttsChannelProviderOverridesSharedAndKeepsSharedProviderConfig(): Unit {
        var user = GatewayUserSettings()
        user.speech.tts = speechTestConfig(
            "shared-edge",
            "shared-edge",
            speechTestCommandProvider("command", outputExtension: "mp3")
        )
        user.telegram.speech.tts = speechTestConfig("telegram-edge", "telegram-edge", JsonObject())

        let resolved = gatewaySpeechResolveTtsConfig(user, channel: "telegram")
        let providers = speechTestObj(resolved, "providers")
        let shared = speechTestObj(providers, "shared-edge")
        let telegram = speechTestObj(providers, "telegram-edge")

        @Expect(speechTestString(resolved, "provider"), "telegram-edge")
        @Expect(speechTestString(shared, "kind"), "command")
        @Expect(telegram.get("kind").isNone(), true)
    }

    @TestCase
    public func ttsChannelProviderDeepMergesSharedProviderFields(): Unit {
        var user = GatewayUserSettings()
        user.speech.tts = speechTestConfig(
            "edge",
            "edge",
            speechTestCommandProvider("command", outputExtension: "mp3")
        )
        let overrideProvider = JsonObject()
        overrideProvider.put("outputExtension", JsonString("ogg"))
        let overrideConfig = speechTestConfig("edge", "edge", overrideProvider)
        user.telegram.speech.tts = overrideConfig

        let provider = speechTestObj(speechTestObj(gatewaySpeechResolveTtsConfig(user, channel: "telegram"), "providers"), "edge")
        let command = provider.get("command").getOrThrow().asArray()

        @Expect(speechTestString(provider, "kind"), "command")
        @Expect(speechTestString(provider, "outputExtension"), "ogg")
        @Expect(command.size(), 3)
    }

    @TestCase
    public func asrChannelProviderOverridesSharedProvider(): Unit {
        var user = GatewayUserSettings()
        user.speech.asr = speechTestConfig(
            "shared-local",
            "shared-local",
            speechTestCommandProvider("command", outputExtension: "txt")
        )
        user.telegram.speech.asr = speechTestConfig(
            "telegram-local",
            "telegram-local",
            speechTestCommandProvider("command", outputExtension: "txt")
        )

        let resolved = gatewaySpeechResolveAsrConfig(user, channel: "telegram")

        @Expect(speechTestString(resolved, "provider"), "telegram-local")
        @Expect(speechTestObj(speechTestObj(resolved, "providers"), "telegram-local").get("command").isSome(), true)
    }

    @TestCase
    public func ttsFallsBackToSharedWhenChannelOverrideIsEmpty(): Unit {
        var user = GatewayUserSettings()
        user.speech.tts = speechTestConfig(
            "shared-edge",
            "shared-edge",
            speechTestCommandProvider("command", outputExtension: "mp3")
        )

        let resolved = gatewaySpeechResolveTtsConfig(user, channel: "telegram")

        @Expect(speechTestString(resolved, "provider"), "shared-edge")
        @Expect(speechTestObj(speechTestObj(resolved, "providers"), "shared-edge").get("command").isSome(), true)
    }

    @TestCase
    public func legacyTelegramTtsIsOnlyUsedWhenSharedAndChannelAreMissing(): Unit {
        var user = GatewayUserSettings()
        let extraRoot = JsonObject()
        let legacy = JsonObject()
        legacy.put("provider", JsonString("legacy-command"))
        legacy.put("command", JsonArray([JsonString("legacy-tts"), JsonString("{text}"), JsonString("{output}")]))
        legacy.put("outputExtension", JsonString("wav"))
        extraRoot.put("telegramTts", legacy)
        user.channelsExtra = Some<JsonObject>(extraRoot)

        let legacyResolved = gatewaySpeechResolveTtsConfig(user, channel: "telegram")
        @Expect(speechTestString(legacyResolved, "provider"), "legacy-command")
        @Expect(speechTestBool(legacyResolved, "legacy"), true)

        user.speech.tts = speechTestConfig(
            "shared-edge",
            "shared-edge",
            speechTestCommandProvider("command", outputExtension: "mp3")
        )
        let sharedResolved = gatewaySpeechResolveTtsConfig(user, channel: "telegram")
        @Expect(speechTestString(sharedResolved, "provider"), "shared-edge")
        @Expect(speechTestBool(sharedResolved, "legacy"), false)
    }

    @TestCase
    public func deliveryPrefsPreferTypedChannelSpeechThenChannelsExtraSpeech(): Unit {
        var user = GatewayUserSettings()
        let extraRoot = JsonObject()
        let telegramExtra = JsonObject()
        let speechExtra = JsonObject()
        speechExtra.put("audioAsVoice", JsonBool(false))
        speechExtra.put("autoReplyToVoice", JsonBool(false))
        telegramExtra.put("speech", speechExtra)
        extraRoot.put("telegram", telegramExtra)
        user.channelsExtra = Some<JsonObject>(extraRoot)

        var extraResolved = gatewaySpeechResolveDeliveryPrefs(user, channel: "telegram")
        @Expect(speechTestBool(extraResolved, "audioAsVoice"), false)
        @Expect(speechTestBool(extraResolved, "autoReplyToVoice"), false)

        user.telegram.speech.audioAsVoice = Some<Bool>(true)
        user.telegram.speech.autoReplyToVoice = Some<Bool>(true)
        extraResolved = gatewaySpeechResolveDeliveryPrefs(user, channel: "telegram")
        @Expect(speechTestBool(extraResolved, "audioAsVoice"), true)
        @Expect(speechTestBool(extraResolved, "autoReplyToVoice"), true)
    }

    @TestCase
    public func invalidProviderConfigReturnsEmptyProvidersWithoutThrowing(): Unit {
        var user = GatewayUserSettings()
        let invalid = JsonObject()
        invalid.put("enabled", JsonBool(true))
        invalid.put("provider", JsonString("missing"))
        user.speech.tts = invalid

        let resolved = gatewaySpeechResolveTtsConfig(user, channel: "telegram")

        @Expect(speechTestString(resolved, "provider"), "missing")
        @Expect(speechTestObj(resolved, "providers").size(), 0)
        @Expect(speechTestInt(resolved, "maxChars"), 0)
    }
}
