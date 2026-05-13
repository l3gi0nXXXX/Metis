package metis.core.media_tests

import metis.core.*

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.*
import std.unittest.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private func imageRuntimeTempRoot(label: String): Path {
    let root = Path("/tmp/metis-image-generation-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
    Directory.create(root, recursive: true)
    root
}

private func imageRuntimeString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func imageRuntimeBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func imageRuntimeObj(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func imageRuntimeArr(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func imageRuntimeProvider(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("openai-images"))
    provider.put("baseUrl", JsonString("https://api.openai.com/v1"))
    provider.put("apiKey", JsonString("image-secret-key"))
    provider.put("model", JsonString("gpt-image-1"))
    provider.put("timeoutMs", JsonInt(120000))
    provider.put("maxImageBytes", JsonInt(1024 * 1024))
    provider
}

private func imageRuntimeDashScopeProvider(): JsonObject {
    let provider = JsonObject()
    provider.put("kind", JsonString("dashscope-qwen-image-generation"))
    provider.put("baseUrl", JsonString("https://dashscope.aliyuncs.com/api/v1"))
    provider.put("apiKey", JsonString("dashscope-secret-key"))
    provider.put("model", JsonString("qwen-image-2.0-pro"))
    provider.put("timeoutMs", JsonInt(120000))
    provider.put("maxImageBytes", JsonInt(1024 * 1024))
    provider
}

private func imageRuntimeConfig(providerId: String, providerObj: JsonObject, outputRoot!: Path = imageRuntimeTempRoot("default")): JsonObject {
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

private func imageRuntimeRequest(prompt: String): JsonObject {
    let request = JsonObject()
    request.put("prompt", JsonString(prompt))
    request.put("filename", JsonString("eagle image.png"))
    request.put("size", JsonString("1024x1024"))
    request.put("count", JsonInt(1))
    request
}

@Test
public class GatewayImageGenerationRuntimeTest {
    @TestCase
    public func runtimeReturnsNotConfiguredWhenProviderMissing(): Unit {
        let result = gatewayImageGenerationGenerate(JsonObject(), imageRuntimeRequest("draw an eagle"))

        @Expect(imageRuntimeBool(result, "ok"), false)
        @Expect(imageRuntimeString(result, "status"), "not_configured")
        @Expect(imageRuntimeArr(result, "images").size(), 0)
    }

    @TestCase
    public func runtimeRejectsUnsafeOutputRootBeforeProvider(): Unit {
        let config = imageRuntimeConfig("openai", imageRuntimeProvider())
        config.put("outputRoot", JsonString("/Users/l3gi0n/work/workspace_cangjie/Metis"))
        config.put("allowedOutputRoots", JsonArray([]))

        let result = gatewayImageGenerationGenerate(config, imageRuntimeRequest("draw an eagle"))

        @Expect(imageRuntimeBool(result, "ok"), false)
        @Expect(imageRuntimeString(result, "status"), "invalid_request")
        @Expect(imageRuntimeString(result, "message").contains("outputRoot"), true)
    }

    @TestCase
    public func openAiProviderParsesBase64ImageAndWritesFile(): Unit {
        let root = imageRuntimeTempRoot("openai-b64")
        let requests = ArrayList<String>()
        setGatewayImageGenerationOpenAiRunnerForTest(Some({ request: JsonObject, _providerConfig: JsonObject =>
            requests.add(request.toJsonString())
            let body = imageRuntimeObj(request, "body")
            @Expect(imageRuntimeString(request, "url"), "https://api.openai.com/v1/images/generations")
            @Expect(imageRuntimeString(request, "authorization"), "Bearer image-secret-key")
            @Expect(imageRuntimeString(body, "model"), "gpt-image-1")
            @Expect(imageRuntimeString(body, "prompt"), "draw an eagle")
            @Expect(imageRuntimeString(body, "size"), "1024x1024")
            @Expect(request.toJsonString().contains("apiKey"), false)
            GatewayImageGenerationHttpResult(200, bodyBytes: "{\"data\":[{\"b64_json\":\"SU1BR0U=\"}]}".toArray(), contentType: "application/json")
        }))
        try {
            let result = gatewayImageGenerationGenerate(imageRuntimeConfig("openai", imageRuntimeProvider(), outputRoot: root), imageRuntimeRequest("draw an eagle"))
            let image = imageRuntimeArr(result, "images")[0].asObject()
            let imagePath = Path(imageRuntimeString(image, "path"))

            @Expect(imageRuntimeBool(result, "ok"), true)
            @Expect(imageRuntimeString(result, "status"), "ok")
            @Expect(imageRuntimeString(result, "provider"), "openai")
            @Expect(imageRuntimeString(result, "providerKind"), "openai-images")
            @Expect(imageRuntimeString(image, "mimeType"), "image/png")
            @Expect(imageRuntimeString(image, "fileName"), "eagle-image.png")
            @Expect(exists(imagePath), true)
            @Expect(String.fromUtf8(File.readFrom(imagePath)), "IMAGE")
            @Expect(requests.size, 1)
        } finally {
            setGatewayImageGenerationOpenAiRunnerForTest(None<(JsonObject, JsonObject) -> GatewayImageGenerationHttpResult>)
        }
    }

    @TestCase
    public func dashScopeQwenImageProviderPostsNativeRequestAndDownloadsImage(): Unit {
        let root = imageRuntimeTempRoot("dashscope-qwen")
        let requests = ArrayList<String>()
        let downloads = ArrayList<String>()
        setGatewayImageGenerationDashScopeRunnerForTest(Some({ request: JsonObject, _providerConfig: JsonObject =>
            requests.add(request.toJsonString())
            let body = imageRuntimeObj(request, "body")
            let input = imageRuntimeObj(body, "input")
            let parameters = imageRuntimeObj(body, "parameters")
            let messages = imageRuntimeArr(input, "messages")
            let message = messages[0].asObject()
            let content = imageRuntimeArr(message, "content")
            let text = content[0].asObject()

            @Expect(imageRuntimeString(request, "url"), "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation")
            @Expect(imageRuntimeString(request, "authorization"), "Bearer dashscope-secret-key")
            @Expect(imageRuntimeString(body, "model"), "qwen-image-2.0-pro")
            @Expect(imageRuntimeString(message, "role"), "user")
            @Expect(imageRuntimeString(text, "text"), "draw an eagle")
            @Expect(imageRuntimeString(parameters, "size"), "1024*1024")
            @Expect(parameters.get("n").getOrThrow().asInt().getValue(), 1)
            @Expect(request.toJsonString().contains("apiKey"), false)
            GatewayImageGenerationHttpResult(200, bodyBytes: "{\"output\":{\"choices\":[{\"message\":{\"content\":[{\"image\":\"https://dashscope-result.example/eagle.png\"}]}}]}}".toArray(), contentType: "application/json")
        }))
        setGatewayImageGenerationDownloaderForTest(Some({ url: String, _timeoutMs: Int64, _maxBytes: Int64, _providerConfig: JsonObject =>
            downloads.add(url)
            GatewayImageGenerationHttpResult(200, bodyBytes: "DASH_IMAGE".toArray(), contentType: "image/png")
        }))
        try {
            let result = gatewayImageGenerationGenerate(imageRuntimeConfig("dashscope", imageRuntimeDashScopeProvider(), outputRoot: root), imageRuntimeRequest("draw an eagle"))
            let image = imageRuntimeArr(result, "images")[0].asObject()
            let imagePath = Path(imageRuntimeString(image, "path"))

            @Expect(imageRuntimeBool(result, "ok"), true)
            @Expect(imageRuntimeString(result, "status"), "ok")
            @Expect(imageRuntimeString(result, "provider"), "dashscope")
            @Expect(imageRuntimeString(result, "providerKind"), "dashscope-qwen-image-generation")
            @Expect(imageRuntimeString(result, "model"), "qwen-image-2.0-pro")
            @Expect(imageRuntimeString(image, "mimeType"), "image/png")
            @Expect(imageRuntimeString(image, "fileName"), "eagle-image.png")
            @Expect(exists(imagePath), true)
            @Expect(String.fromUtf8(File.readFrom(imagePath)), "DASH_IMAGE")
            @Expect(requests.size, 1)
            @Expect(downloads.size, 1)
            @Expect(downloads[0], "https://dashscope-result.example/eagle.png")
        } finally {
            setGatewayImageGenerationDashScopeRunnerForTest(None<(JsonObject, JsonObject) -> GatewayImageGenerationHttpResult>)
            setGatewayImageGenerationDownloaderForTest(None<(String, Int64, Int64, JsonObject) -> GatewayImageGenerationHttpResult>)
        }
    }

    @TestCase
    public func dashScopeQwenImageRejectsReferenceImageBeforeProviderCall(): Unit {
        let root = imageRuntimeTempRoot("dashscope-reference")
        let ref = root.join("ref.png")
        File.writeTo(ref, "PNG".toArray())
        let request = imageRuntimeRequest("edit this image")
        request.put("referenceImage", JsonString(ref.toString()))
        let requests = ArrayList<String>()
        setGatewayImageGenerationDashScopeRunnerForTest(Some({ requestObj: JsonObject, _providerConfig: JsonObject =>
            requests.add(requestObj.toJsonString())
            GatewayImageGenerationHttpResult(200, bodyBytes: "{}".toArray(), contentType: "application/json")
        }))
        try {
            let result = gatewayImageGenerationGenerate(imageRuntimeConfig("dashscope", imageRuntimeDashScopeProvider(), outputRoot: root), request)

            @Expect(imageRuntimeBool(result, "ok"), false)
            @Expect(imageRuntimeString(result, "status"), "provider_unsupported")
            @Expect(imageRuntimeString(result, "providerKind"), "dashscope-qwen-image-generation")
            @Expect(imageRuntimeString(result, "message").contains("referenceImage"), true)
            @Expect(requests.size, 0)
        } finally {
            setGatewayImageGenerationDashScopeRunnerForTest(None<(JsonObject, JsonObject) -> GatewayImageGenerationHttpResult>)
        }
    }

    @TestCase
    public func providerRejectsUnsupportedReferenceImageWithoutNetwork(): Unit {
        let root = imageRuntimeTempRoot("reference-unsupported")
        let ref = root.join("ref.png")
        File.writeTo(ref, "PNG".toArray())
        let request = imageRuntimeRequest("edit this eagle")
        request.put("referenceImage", JsonString(ref.toString()))
        let provider = imageRuntimeProvider()
        provider.put("supportsEdit", JsonBool(false))

        let result = gatewayImageGenerationGenerate(imageRuntimeConfig("openai", provider, outputRoot: root), request)

        @Expect(imageRuntimeBool(result, "ok"), false)
        @Expect(imageRuntimeString(result, "status"), "provider_unsupported")
        @Expect(imageRuntimeString(result, "message").contains("referenceImage"), true)
    }

    @TestCase
    public func defaultOutputRootUsesMetisHome(): Unit {
        let testHome = imageRuntimeTempRoot("home").toString()
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        try {
            let config = imageRuntimeConfig("openai", imageRuntimeProvider(), outputRoot: Path("/tmp/metis-unused"))
            config.put("outputRoot", JsonString(""))
            let resolved = gatewayImageGenerationResolveOutputRoot(config)

            @Expect(resolved.toString().startsWith(Path(testHome).join("gateway-image-generation").toString()), true)
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
        }
    }
}
