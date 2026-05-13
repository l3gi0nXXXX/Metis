package metis.core.media_tests

import metis.core.*

import std.collection.ArrayList
import std.fs.{Directory, File, Path}
import std.time.*
import std.unittest.*
import stdx.encoding.base64.toBase64String
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func videoRuntimeTestTempRoot(label: String): Path {
    let root = Path("/tmp/metis-media-video-runtime-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
    Directory.create(root, recursive: true)
    root
}

private func videoRuntimeTestProvider(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("gemini-inline-video"))
    provider.put("apiKey", JsonString("test-gemini-key"))
    provider.put("baseUrl", JsonString("https://gemini.example/v1beta/"))
    provider.put("model", JsonString("gemini-3-flash-preview"))
    provider.put("timeoutMs", JsonInt(1500))
    provider
}

private func videoRuntimeTestQwenProvider(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("qwen-vl-video"))
    provider.put("apiKey", JsonString("test-qwen-key"))
    provider.put("baseUrl", JsonString("https://dashscope.aliyuncs.com/compatible-mode/v1"))
    provider.put("model", JsonString("qwen3-vl-plus"))
    provider.put("timeoutMs", JsonInt(1500))
    provider
}

private func videoRuntimeTestConfig(provider: JsonObject): JsonObject {
    let providers = JsonObject()
    providers.put("gemini", provider)
    let config = JsonObject()
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString("gemini"))
    config.put("providers", providers)
    config.put("maxBytes", JsonInt(8192))
    config.put("maxBase64Bytes", JsonInt(12000))
    return config
}

private func videoRuntimeTestQwenConfig(provider: JsonObject): JsonObject {
    let providers = JsonObject()
    providers.put("qwen", provider)
    let config = JsonObject()
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString("qwen"))
    config.put("providers", providers)
    config.put("maxBytes", JsonInt(8192))
    config.put("maxBase64Bytes", JsonInt(12000))
    return config
}

private func videoRuntimeString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func videoRuntimeObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

@Test
public class GatewayMediaVideoRuntimeTest {
    @TestCase
    public func geminiInlineProviderBuildsRequestAndParsesPartsText(): Unit {
        let root = videoRuntimeTestTempRoot("gemini")
        let clip = root.join("clip.mp4")
        File.writeTo(clip, "video-bytes".toArray())
        let seen = ArrayList<JsonObject>()
        setGatewayMediaVideoHttpRunnerForTest(Some({ request: JsonObject =>
            seen.add(request)
            let body = videoRuntimeObject(request, "body")
            let contents = body.get("contents").getOrThrow().asArray()
            let parts = contents[0].asObject().get("parts").getOrThrow().asArray()
            @Expect(videoRuntimeString(request, "url"), "https://gemini.example/v1beta/models/gemini-3-flash-preview:generateContent")
            @Expect(videoRuntimeString(request, "xGoogApiKey"), "test-gemini-key")
            @Expect(parts[0].asObject().get("text").getOrThrow().asString().getValue(), "Describe the video.")
            let inline = parts[1].asObject().get("inline_data").getOrThrow().asObject()
            @Expect(videoRuntimeString(inline, "mime_type"), "video/mp4")
            @Expect(videoRuntimeString(inline, "data"), toBase64String("video-bytes".toArray()))
            GatewayMediaVideoHttpResult(
                200,
                bodyBytes: "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"first\"},{\"text\":\" second \"},{\"text\":\"\"}]}}]}".toArray(),
                contentType: "application/json"
            )
        }))
        try {
            let result = gatewayMediaVideoDescribePath(videoRuntimeTestConfig(videoRuntimeTestProvider()), clip.toString(), "video/mp4", "", outputRoot: root, maxBytes: 0)
            @Expect(seen.size, 1)
            @Expect(videoRuntimeString(result, "status"), "ok")
            @Expect(videoRuntimeString(result, "description"), "first\nsecond")
            @Expect(videoRuntimeString(result, "providerKind"), "gemini-inline-video")
            @Expect(result.toJsonString().contains("test-gemini-key"), false)
        } finally {
            setGatewayMediaVideoHttpRunnerForTest(None<(JsonObject) -> GatewayMediaVideoHttpResult>)
        }
    }

    @TestCase
    public func geminiInlineProviderEmptyTextIsProviderError(): Unit {
        let root = videoRuntimeTestTempRoot("empty")
        let clip = root.join("clip.mp4")
        File.writeTo(clip, "video".toArray())
        setGatewayMediaVideoHttpRunnerForTest(Some({ _request: JsonObject =>
            GatewayMediaVideoHttpResult(200, bodyBytes: "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"   \"}]}}]}".toArray(), contentType: "application/json")
        }))
        try {
            let result = gatewayMediaVideoDescribePath(videoRuntimeTestConfig(videoRuntimeTestProvider()), clip.toString(), "video/mp4", "", outputRoot: root, maxBytes: 0)
            @Expect(videoRuntimeString(result, "status"), "provider_error")
            @Expect(videoRuntimeString(result, "message").contains("missing text"), true)
        } finally {
            setGatewayMediaVideoHttpRunnerForTest(None<(JsonObject) -> GatewayMediaVideoHttpResult>)
        }
    }

    @TestCase
    public func base64PayloadLimitRejectsBeforeProviderCall(): Unit {
        let root = videoRuntimeTestTempRoot("base64")
        let clip = root.join("clip.mp4")
        File.writeTo(clip, "video-bytes".toArray())
        let config = videoRuntimeTestConfig(videoRuntimeTestProvider())
        config.put("maxBase64Bytes", JsonInt(4))
        let seen = ArrayList<String>()
        setGatewayMediaVideoHttpRunnerForTest(Some({ _request: JsonObject =>
            seen.add("called")
            GatewayMediaVideoHttpResult(200, bodyBytes: "{}".toArray())
        }))
        try {
            let result = gatewayMediaVideoDescribePath(config, clip.toString(), "video/mp4", "", outputRoot: root, maxBytes: 0)
            @Expect(seen.size, 0)
            @Expect(videoRuntimeString(result, "status"), "too_large")
            @Expect(result.get("base64Bytes").isSome(), true)
            @Expect(result.get("limitBytes").isSome(), true)
        } finally {
            setGatewayMediaVideoHttpRunnerForTest(None<(JsonObject) -> GatewayMediaVideoHttpResult>)
        }
    }

    @TestCase
    public func qwenVlVideoProviderBuildsOpenAICompatibleRequestAndParsesStringContent(): Unit {
        let root = videoRuntimeTestTempRoot("qwen")
        let clip = root.join("clip.mp4")
        File.writeTo(clip, "qwen-video".toArray())
        let seen = ArrayList<JsonObject>()
        setGatewayMediaVideoHttpRunnerForTest(Some({ request: JsonObject =>
            seen.add(request)
            @Expect(videoRuntimeString(request, "url"), "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
            @Expect(videoRuntimeString(request, "authorization"), "Bearer test-qwen-key")
            let body = videoRuntimeObject(request, "body")
            @Expect(videoRuntimeString(body, "model"), "qwen3-vl-plus")
            let messages = body.get("messages").getOrThrow().asArray()
            let content = messages[0].asObject().get("content").getOrThrow().asArray()
            @Expect(videoRuntimeString(content[0].asObject(), "type"), "text")
            @Expect(videoRuntimeString(content[0].asObject(), "text"), "Describe the video in detail.")
            @Expect(videoRuntimeString(content[1].asObject(), "type"), "video_url")
            let videoUrl = content[1].asObject().get("video_url").getOrThrow().asObject()
            @Expect(videoRuntimeString(videoUrl, "url"), "data:video/mp4;base64,${toBase64String("qwen-video".toArray())}")
            GatewayMediaVideoHttpResult(
                200,
                bodyBytes: "{\"choices\":[{\"message\":{\"content\":\"qwen sees a short clip\"}}]}".toArray(),
                contentType: "application/json"
            )
        }))
        try {
            let result = gatewayMediaVideoDescribePath(videoRuntimeTestQwenConfig(videoRuntimeTestQwenProvider()), clip.toString(), "video/mp4", "", outputRoot: root, maxBytes: 0)
            @Expect(seen.size, 1)
            @Expect(videoRuntimeString(result, "status"), "ok")
            @Expect(videoRuntimeString(result, "description"), "qwen sees a short clip")
            @Expect(videoRuntimeString(result, "providerKind"), "qwen-vl-video")
            @Expect(videoRuntimeString(result, "model"), "qwen3-vl-plus")
            @Expect(result.toJsonString().contains("test-qwen-key"), false)
        } finally {
            setGatewayMediaVideoHttpRunnerForTest(None<(JsonObject) -> GatewayMediaVideoHttpResult>)
        }
    }

    @TestCase
    public func qwenVlVideoProviderParsesArrayTextParts(): Unit {
        let root = videoRuntimeTestTempRoot("qwen-parts")
        let clip = root.join("clip.mp4")
        File.writeTo(clip, "video".toArray())
        setGatewayMediaVideoHttpRunnerForTest(Some({ _request: JsonObject =>
            GatewayMediaVideoHttpResult(
                200,
                bodyBytes: "{\"choices\":[{\"message\":{\"content\":[{\"text\":\"first\"},{\"text\":\" second \"},{\"text\":\"\"}]}}]}".toArray(),
                contentType: "application/json"
            )
        }))
        try {
            let result = gatewayMediaVideoDescribePath(videoRuntimeTestQwenConfig(videoRuntimeTestQwenProvider()), clip.toString(), "video/mp4", "", outputRoot: root, maxBytes: 0)
            @Expect(videoRuntimeString(result, "status"), "ok")
            @Expect(videoRuntimeString(result, "description"), "first\nsecond")
            @Expect(videoRuntimeString(result, "providerKind"), "qwen-vl-video")
        } finally {
            setGatewayMediaVideoHttpRunnerForTest(None<(JsonObject) -> GatewayMediaVideoHttpResult>)
        }
    }
}
