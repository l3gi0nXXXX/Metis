package metis.core.media_tests

import metis.core.*

import metis.core.config.GatewayUserSettings

import std.fs.{Directory, File, Path}
import std.time.*
import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func mediaAsrTestTempRoot(label: String): Path {
    let root = Path("/tmp/metis-media-asr-config-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
    Directory.create(root, recursive: true)
    root
}

private func mediaAsrTestRecord(path: String, channel!: String = "telegram"): JsonObject {
    let record = JsonObject()
    record.put("mediaKind", JsonString("voice"))
    record.put("mimeType", JsonString("audio/ogg"))
    record.put("localPath", JsonString(path))
    record.put("downloaded", JsonBool(true))
    record.put("channel", JsonString(channel))
    return record
}

private func mediaVideoTestRecord(path: String, channel!: String = "telegram"): JsonObject {
    let record = JsonObject()
    record.put("mediaKind", JsonString("video"))
    record.put("mimeType", JsonString("video/mp4"))
    record.put("localPath", JsonString(path))
    record.put("downloaded", JsonBool(true))
    record.put("channel", JsonString(channel))
    record
}

private func mediaAsrTestProvider(text: String): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("command"))
    provider.put("command", JsonArray([JsonString("sh"), JsonString("-c"), JsonString("printf '${text}'")]))
    return provider
}

private func mediaAsrTestConfig(providerId: String, provider: JsonObject): JsonObject {
    let providers = JsonObject()
    providers.put(providerId, provider)
    let config = JsonObject()
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString(providerId))
    config.put("providers", providers)
    return config
}

private func mediaAsrString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayMediaUnderstandingRuntimeTest {
    @TestCase
    public func recordTranscriptStaysAheadOfConfiguredAsrProvider(): Unit {
        let root = mediaAsrTestTempRoot("record")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        var user = GatewayUserSettings()
        user.speech.asr = mediaAsrTestConfig("shared", mediaAsrTestProvider("configured transcript"))
        let record = mediaAsrTestRecord(audio.toString())
        record.put("transcript", JsonString("record transcript"))

        let result = gatewayMediaUnderstandingForRecordWithSettings(record, user, capability: "audio")
        @Expect(mediaAsrString(result, "ASRStatus"), "transcribed")
        @Expect(mediaAsrString(result, "transcript"), "record transcript")
    }

    @TestCase
    public func testOverrideStaysAheadOfConfiguredAsrProvider(): Unit {
        let root = mediaAsrTestTempRoot("override")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        var user = GatewayUserSettings()
        user.speech.asr = mediaAsrTestConfig("shared", mediaAsrTestProvider("configured transcript"))
        setGatewayMediaAsrRunnerForTest(Some({ _path: String, _mime: String => "override transcript" }))
        try {
            let result = gatewayMediaUnderstandingForRecordWithSettings(mediaAsrTestRecord(audio.toString()), user, capability: "audio")
            @Expect(mediaAsrString(result, "ASRStatus"), "transcribed")
            @Expect(mediaAsrString(result, "transcript"), "override transcript")
        } finally {
            setGatewayMediaAsrRunnerForTest(None<(String, String) -> String>)
        }
    }

    @TestCase
    public func telegramChannelAsrProviderOverridesSharedProvider(): Unit {
        let root = mediaAsrTestTempRoot("channel")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        var user = GatewayUserSettings()
        user.speech.asr = mediaAsrTestConfig("shared", mediaAsrTestProvider("shared transcript"))
        user.telegram.speech.asr = mediaAsrTestConfig("telegram", mediaAsrTestProvider("telegram transcript"))

        let result = gatewayMediaUnderstandingForRecordWithSettings(mediaAsrTestRecord(audio.toString()), user, capability: "audio")
        @Expect(mediaAsrString(result, "ASRStatus"), "transcribed")
        @Expect(mediaAsrString(result, "transcript"), "telegram transcript")
    }

    @TestCase
    public func sharedAsrProviderIsUsedWhenChannelOverrideMissing(): Unit {
        let root = mediaAsrTestTempRoot("shared")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, "fake-audio".toArray())
        var user = GatewayUserSettings()
        user.speech.asr = mediaAsrTestConfig("shared", mediaAsrTestProvider("shared transcript"))

        let result = gatewayMediaUnderstandingForRecordWithSettings(mediaAsrTestRecord(audio.toString()), user, capability: "audio")
        @Expect(mediaAsrString(result, "ASRStatus"), "transcribed")
        @Expect(mediaAsrString(result, "transcript"), "shared transcript")
    }

    @TestCase
    public func sharedAsrMaxBytesOverridesMediaDefaultLimit(): Unit {
        let root = mediaAsrTestTempRoot("maxbytes")
        let audio = root.join("voice.ogg")
        File.writeTo(audio, Array<Byte>(9000, repeat: 65))
        var user = GatewayUserSettings()
        let asr = mediaAsrTestConfig("shared", mediaAsrTestProvider("configured transcript"))
        asr.put("maxBytes", JsonString("26214400"))
        user.speech.asr = asr

        let result = gatewayMediaUnderstandingForRecordWithSettings(mediaAsrTestRecord(audio.toString()), user, capability: "audio")
        @Expect(mediaAsrString(result, "status"), "ok")
        @Expect(mediaAsrString(result, "ASRStatus"), "transcribed")
        @Expect(mediaAsrString(result, "transcript"), "configured transcript")
    }

    @TestCase
    public func configuredGeminiVideoProviderProducesVideoDescriptionOutput(): Unit {
        let root = mediaAsrTestTempRoot("video-gemini")
        let clip = root.join("clip.mp4")
        File.writeTo(clip, "fake-video".toArray())
        var user = GatewayUserSettings()
        let provider = JsonObject()
        provider.put("kind", JsonString("gemini-inline-video"))
        provider.put("apiKey", JsonString("test-video-key"))
        provider.put("baseUrl", JsonString("https://gemini.example/v1beta"))
        provider.put("model", JsonString("gemini-3-flash-preview"))
        let providers = JsonObject()
        providers.put("gemini", provider)
        user.media.video.put("enabled", JsonBool(true))
        user.media.video.put("provider", JsonString("gemini"))
        user.media.video.put("providers", providers)
        setGatewayMediaVideoHttpRunnerForTest(Some({ _request: JsonObject =>
            GatewayMediaVideoHttpResult(200, bodyBytes: "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"a short clip\"}]}}]}".toArray())
        }))
        try {
            let result = gatewayMediaUnderstandingForRecordWithSettings(mediaVideoTestRecord(clip.toString()), user, capability: "video")
            @Expect(mediaAsrString(result, "status"), "ok")
            @Expect(mediaAsrString(result, "videoDescription"), "a short clip")
            @Expect(mediaAsrString(result, "provider"), "gemini")
            let outputs = result.get("outputs").getOrThrow().asArray()
            @Expect(outputs[0].asObject().get("kind").getOrThrow().asString().getValue(), "video.description")
            @Expect(outputs[0].asObject().get("source").getOrThrow().asString().getValue(), "gateway_video_runtime")
        } finally {
            setGatewayMediaVideoHttpRunnerForTest(None<(JsonObject) -> GatewayMediaVideoHttpResult>)
        }
    }

    @TestCase
    public func configuredVideoProviderTooLargeStatusIsPropagated(): Unit {
        let root = mediaAsrTestTempRoot("video-large")
        let clip = root.join("clip.mp4")
        File.writeTo(clip, Array<Byte>(16, repeat: 65))
        var user = GatewayUserSettings()
        user.media.video.put("enabled", JsonBool(true))
        user.media.video.put("provider", JsonString("gemini"))
        let provider = JsonObject()
        provider.put("kind", JsonString("gemini-inline-video"))
        provider.put("apiKey", JsonString("test-video-key"))
        let providers = JsonObject()
        providers.put("gemini", provider)
        user.media.video.put("providers", providers)
        user.media.video.put("maxBytes", JsonString("4"))

        let result = gatewayMediaUnderstandingForRecordWithSettings(mediaVideoTestRecord(clip.toString()), user, capability: "video")
        @Expect(mediaAsrString(result, "status"), "too_large")
        @Expect(mediaAsrString(result, "videoUnderstandingStatus"), "too_large")
        @Expect(result.get("fileBytes").isSome(), true)
    }
}
