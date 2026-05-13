package metis.core.media_tests

import metis.core.*

import std.collection.ArrayList
import std.convert.*
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.*
import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func videoRuntimeTempRoot(label: String): Path {
    let root = Path("/tmp/metis-video-generation-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
    Directory.create(root, recursive: true)
    root
}

private func videoGenerationRuntimeTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func videoRuntimeBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func videoRuntimeInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { Int64.parse(v.toJsonString()) } catch (_: Exception) { 0 }
        case None => 0
    }
}

private func videoRuntimeObj(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func videoRuntimeArr(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func videoRuntimeFirstObj(arr: JsonArray): JsonObject {
    try { arr[0].asObject() } catch (_: Exception) { JsonObject() }
}

private func videoRuntimeDashScopeProvider(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("dashscope-qwen-video-generation"))
    provider.put("baseUrl", JsonString("https://dashscope.aliyuncs.com"))
    provider.put("apiKey", JsonString("video-secret-key"))
    provider.put("model", JsonString("wan2.5-t2v-preview"))
    provider.put("timeoutMs", JsonInt(120000))
    provider.put("pollIntervalMs", JsonInt(0))
    provider.put("maxPollSeconds", JsonInt(3))
    provider.put("maxVideoBytes", JsonInt(1024 * 1024))
    provider
}

private func videoRuntimeConfig(providerId: String, providerObj: JsonObject, outputRoot!: Path = videoRuntimeTempRoot("default")): JsonObject {
    let config = JsonObject()
    let providers = JsonObject()
    providers.put(providerId, providerObj)
    config.put("enabled", JsonBool(true))
    config.put("provider", JsonString(providerId))
    config.put("providers", providers)
    config.put("outputRoot", JsonString(outputRoot.toString()))
    config.put("allowedOutputRoots", JsonArray([JsonString(outputRoot.toString())]))
    config.put("maxPromptChars", JsonInt(4000))
    config
}

private func videoRuntimeRequest(prompt: String): JsonObject {
    let request = JsonObject()
    request.put("prompt", JsonString(prompt))
    request.put("filename", JsonString("demo clip.mp4"))
    request.put("aspectRatio", JsonString("16:9"))
    request.put("durationSeconds", JsonInt(5))
    request
}

@Test
public class GatewayVideoGenerationRuntimeTest {
    @TestCase
    public func runtimeReturnsNotConfiguredWhenProviderMissing(): Unit {
        let result = gatewayVideoGenerationGenerate(JsonObject(), videoRuntimeRequest("make a video"))

        @Expect(videoRuntimeBool(result, "ok"), false)
        @Expect(videoGenerationRuntimeTestString(result, "status"), "not_configured")
        @Expect(videoRuntimeArr(result, "videos").size(), 0)
    }

    @TestCase
    public func runtimeRejectsDisabledAndInvalidPromptBeforeProvider(): Unit {
        let config = videoRuntimeConfig("wan", videoRuntimeDashScopeProvider())
        config.put("enabled", JsonBool(false))
        let disabled = gatewayVideoGenerationGenerate(config, videoRuntimeRequest("make a video"))
        @Expect(videoGenerationRuntimeTestString(disabled, "status"), "disabled")

        config.put("enabled", JsonBool(true))
        let blank = gatewayVideoGenerationGenerate(config, videoRuntimeRequest("   "))
        @Expect(videoGenerationRuntimeTestString(blank, "status"), "invalid_request")

        config.put("maxPromptChars", JsonInt(4))
        let tooLong = gatewayVideoGenerationGenerate(config, videoRuntimeRequest("12345"))
        @Expect(videoGenerationRuntimeTestString(tooLong, "status"), "invalid_request")
    }

    @TestCase
    public func runtimeRejectsUnsafeOutputRoot(): Unit {
        let config = videoRuntimeConfig("wan", videoRuntimeDashScopeProvider())
        config.put("outputRoot", JsonString("/Users/l3gi0n/work/workspace_cangjie/Metis"))
        config.put("allowedOutputRoots", JsonArray([]))

        let result = gatewayVideoGenerationGenerate(config, videoRuntimeRequest("make a video"))

        @Expect(videoGenerationRuntimeTestString(result, "status"), "invalid_request")
        @Expect(videoGenerationRuntimeTestString(result, "message").contains("outputRoot"), true)
    }

    @TestCase
    public func dashScopeProviderSubmitsPollsDownloadsAndWritesVideo(): Unit {
        let root = videoRuntimeTempRoot("dashscope-ok")
        let submitRequests = ArrayList<String>()
        let pollRequests = ArrayList<String>()
        let downloadRequests = ArrayList<String>()
        setGatewayVideoGenerationDashScopeRunnerForTest(Some({ request: JsonObject =>
            submitRequests.add(request.toJsonString())
            let body = videoRuntimeObj(request, "body")
            let input = videoRuntimeObj(body, "input")
            let parameters = videoRuntimeObj(body, "parameters")
            @Expect(videoGenerationRuntimeTestString(request, "url"), "https://dashscope.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis")
            @Expect(videoGenerationRuntimeTestString(request, "authorization"), "Bearer video-secret-key")
            @Expect(videoGenerationRuntimeTestString(body, "model"), "wan2.5-t2v-preview")
            @Expect(videoGenerationRuntimeTestString(input, "prompt"), "make a beach video")
            @Expect(videoGenerationRuntimeTestString(parameters, "aspect_ratio"), "16:9")
            @Expect(videoRuntimeInt(parameters, "duration"), 5)
            @Expect(request.toJsonString().contains("apiKey"), false)
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"request_id\":\"req-1\",\"output\":{\"task_id\":\"task-1\",\"task_status\":\"PENDING\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopePollerForTest(Some({ request: JsonObject =>
            pollRequests.add(request.toJsonString())
            @Expect(videoGenerationRuntimeTestString(request, "url"), "https://dashscope.aliyuncs.com/api/v1/tasks/task-1")
            @Expect(videoGenerationRuntimeTestString(request, "authorization"), "Bearer video-secret-key")
            if (pollRequests.size == 1) {
                GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_status\":\"RUNNING\"}}".toArray())
            } else {
                GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_status\":\"SUCCEEDED\",\"results\":[{\"video_url\":\"https://cdn.example.invalid/out/demo.mp4?token=secret-query\"}]}}".toArray())
            }
        }))
        setGatewayVideoGenerationDashScopeDownloaderForTest(Some({ url: String, _timeoutMs: Int64, _maxBytes: Int64, _providerConfig: JsonObject =>
            downloadRequests.add(url)
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "FAKE-MP4".toArray(), contentType: "video/mp4")
        }))
        try {
            let result = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", videoRuntimeDashScopeProvider(), outputRoot: root), videoRuntimeRequest("make a beach video"))
            let video = videoRuntimeFirstObj(videoRuntimeArr(result, "videos"))
            let videoPath = Path(videoGenerationRuntimeTestString(video, "path"))

            @Expect(videoRuntimeBool(result, "ok"), true)
            @Expect(videoGenerationRuntimeTestString(result, "status"), "ok")
            @Expect(videoGenerationRuntimeTestString(result, "provider"), "wan")
            @Expect(videoGenerationRuntimeTestString(result, "providerKind"), "dashscope-qwen-video-generation")
            @Expect(videoGenerationRuntimeTestString(video, "mimeType"), "video/mp4")
            @Expect(videoGenerationRuntimeTestString(video, "fileName"), "demo-clip.mp4")
            @Expect(exists(videoPath), true)
            @Expect(String.fromUtf8(File.readFrom(videoPath)), "FAKE-MP4")
            @Expect(submitRequests.size, 1)
            @Expect(pollRequests.size, 2)
            @Expect(downloadRequests.size, 1)
        } finally {
            setGatewayVideoGenerationDashScopeRunnerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopePollerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopeDownloaderForTest(None<(String, Int64, Int64, JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
        }
    }

    @TestCase
    public func dashScopeProviderNormalizesCompatibleModeBaseUrlForAigcVideoApi(): Unit {
        let root = videoRuntimeTempRoot("dashscope-compatible-mode")
        let provider = videoRuntimeDashScopeProvider()
        provider.put("baseUrl", JsonString("https://dashscope.aliyuncs.com/compatible-mode/v1"))
        setGatewayVideoGenerationDashScopeRunnerForTest(Some({ request: JsonObject =>
            @Expect(videoGenerationRuntimeTestString(request, "url"), "https://dashscope.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis")
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_id\":\"task-compatible\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopePollerForTest(Some({ request: JsonObject =>
            @Expect(videoGenerationRuntimeTestString(request, "url"), "https://dashscope.aliyuncs.com/api/v1/tasks/task-compatible")
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_status\":\"SUCCEEDED\",\"video_url\":\"https://cdn.example.invalid/out/demo.mp4\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopeDownloaderForTest(Some({ _url: String, _timeoutMs: Int64, _maxBytes: Int64, _providerConfig: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "FAKE-MP4".toArray(), contentType: "video/mp4")
        }))
        try {
            let result = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", provider, outputRoot: root), videoRuntimeRequest("make a compatible mode video"))

            @Expect(videoRuntimeBool(result, "ok"), true)
            @Expect(videoGenerationRuntimeTestString(result, "status"), "ok")
        } finally {
            setGatewayVideoGenerationDashScopeRunnerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopePollerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopeDownloaderForTest(None<(String, Int64, Int64, JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
        }
    }

    @TestCase
    public func dashScopeProviderMapsFailureTimeoutTooLargeAndRedactsSecrets(): Unit {
        let root = videoRuntimeTempRoot("dashscope-errors")
        setGatewayVideoGenerationDashScopeRunnerForTest(Some({ _request: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(500, bodyBytes: "server failed video-secret-key".toArray())
        }))
        try {
            let providerError = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", videoRuntimeDashScopeProvider(), outputRoot: root), videoRuntimeRequest("make a video"))
            @Expect(videoGenerationRuntimeTestString(providerError, "status"), "provider_error")
            @Expect(providerError.toJsonString().contains("video-secret-key"), false)
        } finally {
            setGatewayVideoGenerationDashScopeRunnerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
        }

        setGatewayVideoGenerationDashScopeRunnerForTest(Some({ _request: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_id\":\"task-timeout\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopePollerForTest(Some({ _request: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_status\":\"RUNNING\"}}".toArray())
        }))
        try {
            let provider = videoRuntimeDashScopeProvider()
            provider.put("maxPollSeconds", JsonInt(0))
            let timeout = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", provider, outputRoot: root), videoRuntimeRequest("make a video"))
            @Expect(videoGenerationRuntimeTestString(timeout, "status"), "timeout")
        } finally {
            setGatewayVideoGenerationDashScopeRunnerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopePollerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
        }

        setGatewayVideoGenerationDashScopeRunnerForTest(Some({ _request: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_id\":\"task-large\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopePollerForTest(Some({ _request: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_status\":\"SUCCEEDED\",\"video_url\":\"https://cdn.example.invalid/out/demo.webm?token=secret-query\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopeDownloaderForTest(Some({ _url: String, _timeoutMs: Int64, _maxBytes: Int64, _providerConfig: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "TOO-LARGE".toArray(), contentType: "video/webm")
        }))
        try {
            let provider = videoRuntimeDashScopeProvider()
            provider.put("maxVideoBytes", JsonInt(4))
            let tooLarge = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", provider, outputRoot: root), videoRuntimeRequest("make a video"))
            @Expect(videoGenerationRuntimeTestString(tooLarge, "status"), "too_large")
            @Expect(tooLarge.toJsonString().contains("secret-query"), false)
        } finally {
            setGatewayVideoGenerationDashScopeRunnerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopePollerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopeDownloaderForTest(None<(String, Int64, Int64, JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
        }
    }

    @TestCase
    public func dashScopeRequestsCarryProviderHttpRouteForSubmitPollAndDownload(): Unit {
        let root = videoRuntimeTempRoot("dashscope-route")
        let provider = videoRuntimeDashScopeProvider()
        provider.put("proxy", JsonString("http://user:secret@127.0.0.1:7897"))
        let seenDownloadProxy = ArrayList<String>()
        setGatewayVideoGenerationDashScopeRunnerForTest(Some({ request: JsonObject =>
            let route = videoRuntimeObj(request, "transportRoute")
            @Expect(videoGenerationRuntimeTestString(route, "mode"), "httpConnectTunnel")
            @Expect(videoGenerationRuntimeTestString(route, "proxySource"), "explicit")
            @Expect(videoGenerationRuntimeTestString(route, "redactedProxy"), "http://[redacted]@127.0.0.1:7897")
            @Expect(route.toJsonString().contains("secret"), false)
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_id\":\"task-route\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopePollerForTest(Some({ request: JsonObject =>
            let route = videoRuntimeObj(request, "transportRoute")
            @Expect(videoGenerationRuntimeTestString(route, "mode"), "httpConnectTunnel")
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_status\":\"SUCCEEDED\",\"video_url\":\"https://cdn.example.invalid/out/demo.mp4\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopeDownloaderForTest(Some({ _url: String, _timeoutMs: Int64, _maxBytes: Int64, providerConfig: JsonObject =>
            seenDownloadProxy.add(videoGenerationRuntimeTestString(providerConfig, "proxy"))
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "FAKE-MP4".toArray(), contentType: "video/mp4")
        }))
        try {
            let result = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", provider, outputRoot: root), videoRuntimeRequest("make a routed video"))

            @Expect(videoRuntimeBool(result, "ok"), true)
            @Expect(seenDownloadProxy.size, 1)
            @Expect(seenDownloadProxy[0], "http://user:secret@127.0.0.1:7897")
            @Expect(result.toJsonString().contains("secret"), false)
        } finally {
            setGatewayVideoGenerationDashScopeRunnerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopePollerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopeDownloaderForTest(None<(String, Int64, Int64, JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
        }
    }

    @TestCase
    public func dashScopeOmitsDurationForKnownUnsupportedTurboModel(): Unit {
        let root = videoRuntimeTempRoot("dashscope-duration")
        let provider = videoRuntimeDashScopeProvider()
        provider.put("model", JsonString("wanx2.1-t2v-turbo"))
        setGatewayVideoGenerationDashScopeRunnerForTest(Some({ request: JsonObject =>
            let body = videoRuntimeObj(request, "body")
            let parameters = videoRuntimeObj(body, "parameters")
            @Expect(videoGenerationRuntimeTestString(body, "model"), "wanx2.1-t2v-turbo")
            @Expect(parameters.get("duration").isNone(), true)
            @Expect(videoGenerationRuntimeTestString(parameters, "aspect_ratio"), "16:9")
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_id\":\"task-duration\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopePollerForTest(Some({ _request: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "{\"output\":{\"task_status\":\"SUCCEEDED\",\"video_url\":\"https://cdn.example.invalid/out/demo.mp4\"}}".toArray())
        }))
        setGatewayVideoGenerationDashScopeDownloaderForTest(Some({ _url: String, _timeoutMs: Int64, _maxBytes: Int64, _providerConfig: JsonObject =>
            GatewayVideoGenerationDashScopeHttpResult(200, bodyBytes: "FAKE-MP4".toArray(), contentType: "video/mp4")
        }))
        try {
            let result = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", provider, outputRoot: root), videoRuntimeRequest("make a 3s eagle video"))

            @Expect(videoRuntimeBool(result, "ok"), true)
        } finally {
            setGatewayVideoGenerationDashScopeRunnerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopePollerForTest(None<(JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
            setGatewayVideoGenerationDashScopeDownloaderForTest(None<(String, Int64, Int64, JsonObject) -> GatewayVideoGenerationDashScopeHttpResult>)
        }
    }

    @TestCase
    public func dashScopeReportsUnsupportedHttpsProxyBeforeNetworkRequest(): Unit {
        let root = videoRuntimeTempRoot("dashscope-https-proxy")
        let provider = videoRuntimeDashScopeProvider()
        provider.put("proxy", JsonString("https://user:secret@127.0.0.1:7897"))

        let result = gatewayVideoGenerationGenerate(videoRuntimeConfig("wan", provider, outputRoot: root), videoRuntimeRequest("make a video"))

        @Expect(videoRuntimeBool(result, "ok"), false)
        @Expect(videoGenerationRuntimeTestString(result, "status"), "provider_error")
        @Expect(videoGenerationRuntimeTestString(result, "message").contains("true HTTPS proxy is not implemented"), true)
        @Expect(result.toJsonString().contains("secret"), false)
    }

    @TestCase
    public func defaultOutputRootUsesMetisHomeWithoutTouchingRealHomeInTest(): Unit {
        let testHome = videoRuntimeTempRoot("home").toString()
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        try {
            let config = videoRuntimeConfig("wan", videoRuntimeDashScopeProvider(), outputRoot: Path("/tmp/metis-unused"))
            config.put("outputRoot", JsonString(""))
            let resolved = gatewayVideoGenerationResolveOutputRoot(config)

            @Expect(resolved.toString().startsWith(Path(testHome).join("gateway-video-generation").toString()), true)
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
        }
    }
}
