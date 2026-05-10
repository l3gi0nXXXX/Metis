package metis.core

import metis.utils.{ShellTimeoutException, ShellUtils}

import magic.jsonable.*

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.env.getVariable
import std.fs.{Directory, File, Path, exists}
import std.time.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonFloat, JsonInt, JsonObject, JsonString, JsonValue}
import stdx.encoding.url.URL
import stdx.net.http.*
import stdx.net.tls.*

public class GatewaySpeechTtsOpenAICompatibleHttpResult {
    public let statusCode: Int64
    public let bodyBytes: Array<Byte>
    public let error: String

    public init(statusCode: Int64, bodyBytes!: Array<Byte> = [], error!: String = "") {
        this.statusCode = statusCode
        this.bodyBytes = bodyBytes
        this.error = error
    }
}

public class GatewaySpeechTtsDashScopeQwenHttpResult {
    public let statusCode: Int64
    public let bodyBytes: Array<Byte>
    public let error: String

    public init(statusCode: Int64, bodyBytes!: Array<Byte> = [], error!: String = "") {
        this.statusCode = statusCode
        this.bodyBytes = bodyBytes
        this.error = error
    }
}

private class SpeechTtsOpenAICompatibleException <: Exception {
    public let status: String

    public init(status: String, message: String) {
        super(message)
        this.status = status
    }
}

private class SpeechTtsDashScopeQwenException <: Exception {
    public let status: String

    public init(status: String, message: String) {
        super(message)
        this.status = status
    }
}

private var speechTtsOpenAICompatibleRunnerOverride: Option<(JsonObject) -> GatewaySpeechTtsOpenAICompatibleHttpResult> =
    None<(JsonObject) -> GatewaySpeechTtsOpenAICompatibleHttpResult>

private var speechTtsDashScopeQwenRunnerOverride: Option<(JsonObject) -> GatewaySpeechTtsDashScopeQwenHttpResult> =
    None<(JsonObject) -> GatewaySpeechTtsDashScopeQwenHttpResult>

private var speechTtsDashScopeQwenDownloaderOverride: Option<(String, Int64, Int64) -> GatewaySpeechTtsDashScopeQwenHttpResult> =
    None<(String, Int64, Int64) -> GatewaySpeechTtsDashScopeQwenHttpResult>

public func setGatewaySpeechTtsOpenAICompatibleRunnerForTest(runner: Option<(JsonObject) -> GatewaySpeechTtsOpenAICompatibleHttpResult>): Unit {
    speechTtsOpenAICompatibleRunnerOverride = runner
}

public func setGatewaySpeechTtsDashScopeQwenRunnerForTest(runner: Option<(JsonObject) -> GatewaySpeechTtsDashScopeQwenHttpResult>): Unit {
    speechTtsDashScopeQwenRunnerOverride = runner
}

public func setGatewaySpeechTtsDashScopeQwenDownloaderForTest(downloader: Option<(String, Int64, Int64) -> GatewaySpeechTtsDashScopeQwenHttpResult>): Unit {
    speechTtsDashScopeQwenDownloaderOverride = downloader
}

private func speechTtsNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func speechTtsString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func speechTtsInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_: Exception) {
                try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { fallback }
            }
        case None => fallback
    }
}

private func speechTtsBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) {
            try {
                let low = v.asString().getValue().trimAscii().toAsciiLower()
                low == "true" || low == "1" || low == "yes" || low == "on"
            } catch (_inner: Exception) { fallback }
        }
        case None => fallback
    }
}

private func speechTtsObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func speechTtsStringArray(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_: Exception) {
                []
            }
        case None => []
    }
}

private func speechTtsContains(items: ArrayList<String>, value: String): Bool {
    for (item in items) {
        if (item == value) {
            return true
        }
    }
    false
}

private func speechTtsSecretString(obj: JsonObject, key: String): String {
    let raw = speechTtsString(obj, key)
    if (raw.startsWith("$" + "{") && raw.endsWith("}") && raw.size > 3) {
        let envKey = raw[2..raw.size - 1].trimAscii()
        if (!envKey.isEmpty()) {
            return getVariable(envKey) ?? ""
        }
    }
    raw
}

private func speechTtsProviderConfig(config: JsonObject, provider: String): JsonObject {
    if (provider.isEmpty()) {
        return JsonObject()
    }
    let providers = speechTtsObject(config, "providers")
    match (providers.get(provider)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func speechTtsProviderKind(provider: String, providerConfig: JsonObject): String {
    if (provider.isEmpty()) {
        return "missing"
    }
    if (provider == "fake") {
        return "fake"
    }
    let explicit = speechTtsString(providerConfig, "kind").toAsciiLower()
    if (!explicit.isEmpty()) {
        if (explicit == "dashscope" || explicit == "qwen-tts" || explicit == "dashscope-qwen-tts") {
            return "dashscope-qwen-tts"
        }
        return explicit
    }
    if (speechTtsStringArray(providerConfig, "command").size > 0) {
        return "command"
    }
    return "missing"
}

private func speechTtsDashScopeQwenBaseUrl(providerConfig: JsonObject): String {
    var baseUrl = speechTtsString(providerConfig, "baseUrl")
    if (baseUrl.isEmpty()) {
        baseUrl = "https://dashscope.aliyuncs.com/api/v1"
    }
    while (baseUrl.endsWith("/") && baseUrl.size > 1) {
        baseUrl = baseUrl[..baseUrl.size - 1]
    }
    baseUrl
}

private func speechTtsDashScopeQwenEndpoint(providerConfig: JsonObject): String {
    let suffix = "/services/aigc/multimodal-generation/generation"
    let baseUrl = speechTtsDashScopeQwenBaseUrl(providerConfig)
    if (baseUrl.endsWith(suffix)) {
        return baseUrl
    }
    "${baseUrl}${suffix}"
}

private func speechTtsDashScopeQwenLanguageType(providerConfig: JsonObject): String {
    let camel = speechTtsString(providerConfig, "languageType")
    if (!camel.isEmpty()) {
        return camel
    }
    speechTtsString(providerConfig, "language_type")
}

private func speechTtsDashScopeQwenRequestBody(providerConfig: JsonObject, text: String): JsonObject {
    let body = JsonObject()
    let input = JsonObject()
    let model = speechTtsString(providerConfig, "model")
    body.put("model", JsonString(if (model.isEmpty()) { "qwen3-tts-flash" } else { model }))
    input.put("text", JsonString(text))
    input.put("voice", JsonString(speechTtsString(providerConfig, "voice")))
    let languageType = speechTtsDashScopeQwenLanguageType(providerConfig)
    if (!languageType.isEmpty()) {
        input.put("language_type", JsonString(languageType))
    }
    body.put("input", input)
    body
}

private func speechTtsDashScopeQwenHttpRequest(providerConfig: JsonObject, text: String, timeoutMs: Int64): JsonObject {
    let req = JsonObject()
    req.put("url", JsonString(speechTtsDashScopeQwenEndpoint(providerConfig)))
    req.put("authorization", JsonString("Bearer ${speechTtsSecretString(providerConfig, "apiKey")}"))
    req.put("timeoutMs", JsonInt(timeoutMs))
    req.put("body", speechTtsDashScopeQwenRequestBody(providerConfig, text))
    req
}

private func speechTtsOutputExtension(providerConfig: JsonObject): String {
    match (speechTtsString(providerConfig, "outputExtension").toAsciiLower()) {
        case "mp3" => "mp3"
        case "wav" => "wav"
        case "m4a" => "m4a"
        case "opus" => "opus"
        case "oga" => "oga"
        case "ogg" => "ogg"
        case _ => "ogg"
    }
}

private func speechTtsOpenAICompatibleResponseFormat(providerConfig: JsonObject, audioAsVoice: Bool): String {
    let configured = speechTtsString(providerConfig, "responseFormat").toAsciiLower()
    let legacy = speechTtsString(providerConfig, "response_format").toAsciiLower()
    let selected = if (!configured.isEmpty()) { configured } else { legacy }
    match (selected) {
        case "mp3" => "mp3"
        case "opus" => "opus"
        case "pcm" => "pcm"
        case _ => if (audioAsVoice) { "opus" } else { "mp3" }
    }
}

private func speechTtsOpenAICompatibleExtension(responseFormat: String): String {
    match (responseFormat.toAsciiLower()) {
        case "mp3" => "mp3"
        case "opus" => "opus"
        case "pcm" => "pcm"
        case _ => "mp3"
    }
}

private func speechTtsOutputDir(config: JsonObject, providerConfig: JsonObject, outputRoot: Path): Path {
    var selected = speechTtsString(providerConfig, "outputDir")
    if (selected.isEmpty()) {
        selected = speechTtsString(config, "outputDir")
    }
    let dir = if (selected.isEmpty()) { outputRoot } else { Path(selected) }
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func speechTtsOpenAICompatibleBaseUrl(providerConfig: JsonObject): String {
    var baseUrl = speechTtsString(providerConfig, "baseUrl")
    if (baseUrl.isEmpty()) {
        baseUrl = "https://api.openai.com/v1"
    }
    while (baseUrl.endsWith("/") && baseUrl.size > 1) {
        baseUrl = baseUrl[..baseUrl.size - 1]
    }
    baseUrl
}

private func speechTtsOpenAICompatibleRequestBody(providerConfig: JsonObject, text: String, responseFormat: String): JsonObject {
    let body = JsonObject()
    let model = speechTtsString(providerConfig, "model")
    let voice = speechTtsString(providerConfig, "voice")
    body.put("model", JsonString(if (model.isEmpty()) { "gpt-4o-mini-tts" } else { model }))
    body.put("input", JsonString(text))
    body.put("voice", JsonString(if (voice.isEmpty()) { "coral" } else { voice }))
    body.put("response_format", JsonString(responseFormat))
    match (providerConfig.get("speed")) {
        case Some(v) =>
            try {
                body.put("speed", JsonFloat(Float64.parse(v.toJsonString())))
            } catch (_: Exception) {
                try { body.put("speed", JsonFloat(Float64.parse(v.asString().getValue().trimAscii()))) } catch (_inner: Exception) { () }
            }
        case None => ()
    }
    let instructions = speechTtsString(providerConfig, "instructions")
    if (!instructions.isEmpty()) {
        body.put("instructions", JsonString(instructions))
    }
    body
}

private func speechTtsOpenAICompatibleHttpRequest(providerConfig: JsonObject, text: String, audioAsVoice: Bool, timeoutMs: Int64): JsonObject {
    let responseFormat = speechTtsOpenAICompatibleResponseFormat(providerConfig, audioAsVoice)
    let req = JsonObject()
    req.put("url", JsonString("${speechTtsOpenAICompatibleBaseUrl(providerConfig)}/audio/speech"))
    req.put("authorization", JsonString("Bearer ${speechTtsSecretString(providerConfig, "apiKey")}"))
    req.put("timeoutMs", JsonInt(timeoutMs))
    req.put("responseFormat", JsonString(responseFormat))
    req.put("body", speechTtsOpenAICompatibleRequestBody(providerConfig, text, responseFormat))
    req
}

private func speechTtsOpenAICompatibleReadAllBytes(response: HttpResponse): Array<Byte> {
    let out = ArrayList<Byte>()
    let buffer = Array<Byte>(8192, repeat: 0)
    while (true) {
        let n = response.body.read(buffer)
        if (n <= 0) {
            break
        }
        out.add(all: buffer[..n])
    }
    out.toArray()
}

private func speechTtsOpenAICompatibleErrorDetail(bytes: Array<Byte>, fallback: String): String {
    var detail = fallback.trimAscii()
    if (detail.isEmpty()) {
        try { detail = String.fromUtf8(bytes).trimAscii() } catch (_: Exception) { detail = "" }
    }
    if (detail.size > 300) {
        detail = detail[..300]
    }
    detail
}

private func speechTtsOpenAICompatibleResultBytes(result: GatewaySpeechTtsOpenAICompatibleHttpResult): Array<Byte> {
    let status = result.statusCode
    if (status >= 200 && status < 300) {
        return result.bodyBytes
    }
    let detail = speechTtsOpenAICompatibleErrorDetail(result.bodyBytes, result.error)
    let message = if (detail.isEmpty()) { "OpenAI-compatible TTS API error (${status})" } else { "OpenAI-compatible TTS API error (${status}): ${detail}" }
    if (status == 401 || status == 403) {
        throw SpeechTtsOpenAICompatibleException("auth_error", message)
    }
    if (status == 408) {
        throw SpeechTtsOpenAICompatibleException("timeout", message)
    }
    throw SpeechTtsOpenAICompatibleException("provider_error", message)
}

private func speechTtsOpenAICompatibleNativePost(request: JsonObject, providerConfig: JsonObject): GatewaySpeechTtsOpenAICompatibleHttpResult {
    let url = speechTtsString(request, "url")
    let body = speechTtsObject(request, "body")
    let timeoutMs = max(1, speechTtsInt(request, "timeoutMs", speechTtsInt(providerConfig, "timeoutMs", 10000)))
    let headers = HashMap<String, String>()
    headers["Authorization"] = speechTtsString(request, "authorization")
    headers["Content-Type"] = "application/json"
    headers["Accept"] = "*/*"
    let builder = ClientBuilder()
    builder.readTimeout(Duration.millisecond * timeoutMs)
    if (url.startsWith("https")) {
        var tlsConfig = TlsClientConfig()
        if (speechTtsBool(providerConfig, "insecureSkipTlsVerify", false)) {
            tlsConfig.verifyMode = TrustAll
        }
        tlsConfig.domain = URL.parse(url).hostName
        tlsConfig.alpnProtocolsList = ["http/1.1"]
        builder.tlsConfig(tlsConfig)
    }
    let client = builder.build()
    try {
        let reqBuilder = HttpRequestBuilder().url(url).post().body(body.toJsonString())
        for ((key, value) in headers) {
            reqBuilder.header(key, value)
        }
        let response = client.send(reqBuilder.build())
        let status = Int64(response.status)
        let bytes = speechTtsOpenAICompatibleReadAllBytes(response)
        GatewaySpeechTtsOpenAICompatibleHttpResult(status, bodyBytes: bytes)
    } finally {
        client.close()
    }
}

private func speechTtsOpenAICompatiblePost(request: JsonObject, providerConfig: JsonObject): Array<Byte> {
    let result = match (speechTtsOpenAICompatibleRunnerOverride) {
        case Some(runner) => runner(request)
        case None => speechTtsOpenAICompatibleNativePost(request, providerConfig)
    }
    speechTtsOpenAICompatibleResultBytes(result)
}

private func speechTtsDashScopeQwenSafeUrl(url: String): String {
    let trimmed = url.trimAscii()
    match (trimmed.indexOf("?")) {
        case Some(query) => trimmed[..query]
        case None => trimmed
    }
}

private func speechTtsDashScopeQwenExtensionFromUrl(url: String): String {
    let safe = speechTtsDashScopeQwenSafeUrl(url).toAsciiLower()
    if (safe.endsWith(".ogg")) {
        return "ogg"
    }
    if (safe.endsWith(".opus")) {
        return "opus"
    }
    if (safe.endsWith(".wav")) {
        return "wav"
    }
    if (safe.endsWith(".mp3")) {
        return "mp3"
    }
    "mp3"
}

private func speechTtsDashScopeQwenRedact(detail: String, providerConfig: JsonObject): String {
    var out = detail.trimAscii()
    let secret = speechTtsSecretString(providerConfig, "apiKey")
    if (!secret.isEmpty()) {
        out = out.replace(secret, "[redacted]")
    }
    if (out.size > 300) {
        out = out[..300]
    }
    out
}

private func speechTtsDashScopeQwenErrorDetail(bytes: Array<Byte>, fallback: String, providerConfig: JsonObject): String {
    var detail = fallback.trimAscii()
    if (detail.isEmpty()) {
        try { detail = String.fromUtf8(bytes).trimAscii() } catch (_: Exception) { detail = "" }
    }
    speechTtsDashScopeQwenRedact(detail, providerConfig)
}

private func speechTtsDashScopeQwenEnsureSuccess(result: GatewaySpeechTtsDashScopeQwenHttpResult, providerConfig: JsonObject, context: String): Unit {
    let status = result.statusCode
    if (status >= 200 && status < 300) {
        return
    }
    let detail = speechTtsDashScopeQwenErrorDetail(result.bodyBytes, result.error, providerConfig)
    let message = if (detail.isEmpty()) { "${context} error (${status})" } else { "${context} error (${status}): ${detail}" }
    if (status == 401 || status == 403) {
        throw SpeechTtsDashScopeQwenException("auth_error", message)
    }
    if (status == 408) {
        throw SpeechTtsDashScopeQwenException("timeout", message)
    }
    if (status == 413) {
        throw SpeechTtsDashScopeQwenException("too_large", message)
    }
    throw SpeechTtsDashScopeQwenException("provider_error", message)
}

private func speechTtsDashScopeQwenNativePost(request: JsonObject, providerConfig: JsonObject): GatewaySpeechTtsDashScopeQwenHttpResult {
    let url = speechTtsString(request, "url")
    let body = speechTtsObject(request, "body")
    let timeoutMs = max(1, speechTtsInt(request, "timeoutMs", speechTtsInt(providerConfig, "timeoutMs", 60000)))
    let headers = HashMap<String, String>()
    headers["Authorization"] = speechTtsString(request, "authorization")
    headers["Content-Type"] = "application/json"
    headers["Accept"] = "*/*"
    let builder = ClientBuilder()
    builder.readTimeout(Duration.millisecond * timeoutMs)
    if (url.startsWith("https")) {
        var tlsConfig = TlsClientConfig()
        if (speechTtsBool(providerConfig, "insecureSkipTlsVerify", false)) {
            tlsConfig.verifyMode = TrustAll
        }
        tlsConfig.domain = URL.parse(url).hostName
        tlsConfig.alpnProtocolsList = ["http/1.1"]
        builder.tlsConfig(tlsConfig)
    }
    let client = builder.build()
    try {
        let reqBuilder = HttpRequestBuilder().url(url).post().body(body.toJsonString())
        for ((key, value) in headers) {
            reqBuilder.header(key, value)
        }
        let response = client.send(reqBuilder.build())
        let status = Int64(response.status)
        let bytes = speechTtsOpenAICompatibleReadAllBytes(response)
        GatewaySpeechTtsDashScopeQwenHttpResult(status, bodyBytes: bytes)
    } finally {
        client.close()
    }
}

private func speechTtsDashScopeQwenPost(request: JsonObject, providerConfig: JsonObject): GatewaySpeechTtsDashScopeQwenHttpResult {
    match (speechTtsDashScopeQwenRunnerOverride) {
        case Some(runner) => runner(request)
        case None => speechTtsDashScopeQwenNativePost(request, providerConfig)
    }
}

private func speechTtsDashScopeQwenNativeDownload(url: String, timeoutMs: Int64, maxBytes: Int64): GatewaySpeechTtsDashScopeQwenHttpResult {
    let builder = ClientBuilder()
    builder.readTimeout(Duration.millisecond * timeoutMs)
    if (url.startsWith("https")) {
        var tlsConfig = TlsClientConfig()
        tlsConfig.domain = URL.parse(url).hostName
        tlsConfig.alpnProtocolsList = ["http/1.1"]
        builder.tlsConfig(tlsConfig)
    }
    let client = builder.build()
    try {
        let reqBuilder = HttpRequestBuilder().url(url).get()
        let response = client.send(reqBuilder.build())
        let status = Int64(response.status)
        let bytes = speechTtsOpenAICompatibleReadAllBytes(response)
        if (status >= 200 && status < 300 && maxBytes > 0 && Int64(bytes.size) > maxBytes) {
            return GatewaySpeechTtsDashScopeQwenHttpResult(413, error: "downloaded audio exceeds maxAudioBytes")
        }
        GatewaySpeechTtsDashScopeQwenHttpResult(status, bodyBytes: bytes)
    } finally {
        client.close()
    }
}

private func speechTtsDashScopeQwenDownload(url: String, timeoutMs: Int64, maxBytes: Int64): GatewaySpeechTtsDashScopeQwenHttpResult {
    let trimmed = url.trimAscii()
    if (!(trimmed.startsWith("https://") || trimmed.startsWith("http://"))) {
        throw SpeechTtsDashScopeQwenException("provider_error", "DashScope TTS audio URL is not http(s): ${speechTtsDashScopeQwenSafeUrl(trimmed)}")
    }
    let result = match (speechTtsDashScopeQwenDownloaderOverride) {
        case Some(downloader) => downloader(trimmed, timeoutMs, maxBytes)
        case None => speechTtsDashScopeQwenNativeDownload(trimmed, timeoutMs, maxBytes)
    }
    if (result.statusCode >= 200 && result.statusCode < 300 && maxBytes > 0 && Int64(result.bodyBytes.size) > maxBytes) {
        return GatewaySpeechTtsDashScopeQwenHttpResult(413, error: "downloaded audio exceeds maxAudioBytes")
    }
    result
}

private func speechTtsDashScopeQwenJsonString(obj: JsonObject, keys: Array<String>): String {
    for (key in keys) {
        let value = speechTtsString(obj, key)
        if (!value.isEmpty()) {
            return value
        }
    }
    ""
}

private func speechTtsDashScopeQwenFindString(value: JsonValue, keys: Array<String>): String {
    try {
        let obj = value.asObject()
        let direct = speechTtsDashScopeQwenJsonString(obj, keys)
        if (!direct.isEmpty()) {
            return direct
        }
        for ((_, child) in obj.getFields()) {
            let found = speechTtsDashScopeQwenFindString(child, keys)
            if (!found.isEmpty()) {
                return found
            }
        }
    } catch (_: Exception) {
        try {
            let arr = value.asArray()
            for (child in arr.getItems()) {
                let found = speechTtsDashScopeQwenFindString(child, keys)
                if (!found.isEmpty()) {
                    return found
                }
            }
        } catch (_inner: Exception) {
            ()
        }
    }
    ""
}

private func speechTtsDashScopeQwenBase64Value(ch: Byte): Int64 {
    if (ch >= UInt8(65) && ch <= UInt8(90)) {
        return Int64(ch - UInt8(65))
    }
    if (ch >= UInt8(97) && ch <= UInt8(122)) {
        return Int64(ch - UInt8(97)) + 26
    }
    if (ch >= UInt8(48) && ch <= UInt8(57)) {
        return Int64(ch - UInt8(48)) + 52
    }
    if (ch == UInt8(43)) {
        return 62
    }
    if (ch == UInt8(47)) {
        return 63
    }
    -1
}

private func speechTtsDashScopeQwenDecodeBase64(data: String): Array<Byte> {
    let out = ArrayList<Byte>()
    var buffer: Int64 = 0
    var bits: Int64 = 0
    for (ch in data.toArray()) {
        if (ch == UInt8(61)) {
            break
        }
        let value = speechTtsDashScopeQwenBase64Value(ch)
        if (value < 0) {
            continue
        }
        buffer = (buffer << 6) | value
        bits += 6
        if (bits >= 8) {
            bits -= 8
            out.add(UInt8((buffer >> bits) & 255))
        }
    }
    out.toArray()
}

private func speechTtsDashScopeQwenAudioFromJson(bytes: Array<Byte>, providerConfig: JsonObject, timeoutMs: Int64, maxBytes: Int64): (Array<Byte>, String) {
    let raw = String.fromUtf8(bytes).trimAscii()
    let root = JsonValue.fromStr(raw)
    let audioUrl = speechTtsDashScopeQwenFindString(root, ["url", "audio_url", "audioUrl"])
    if (!audioUrl.isEmpty()) {
        let download = speechTtsDashScopeQwenDownload(audioUrl, timeoutMs, maxBytes)
        speechTtsDashScopeQwenEnsureSuccess(download, providerConfig, "DashScope TTS audio download")
        if (download.bodyBytes.isEmpty()) {
            throw SpeechTtsDashScopeQwenException("empty_result", "DashScope TTS audio download returned empty audio.")
        }
        return (download.bodyBytes, speechTtsDashScopeQwenExtensionFromUrl(audioUrl))
    }
    let audioBase64 = speechTtsDashScopeQwenFindString(root, ["data", "audio", "audio_data", "audioData", "base64"])
    if (!audioBase64.isEmpty()) {
        let decoded = speechTtsDashScopeQwenDecodeBase64(audioBase64)
        if (decoded.isEmpty()) {
            throw SpeechTtsDashScopeQwenException("empty_result", "DashScope TTS returned empty base64 audio.")
        }
        return (decoded, "mp3")
    }
    throw SpeechTtsDashScopeQwenException("empty_result", "DashScope TTS response did not contain audio.")
}

private func speechTtsDashScopeQwenResultAudio(result: GatewaySpeechTtsDashScopeQwenHttpResult, providerConfig: JsonObject, timeoutMs: Int64, maxBytes: Int64): (Array<Byte>, String) {
    speechTtsDashScopeQwenEnsureSuccess(result, providerConfig, "DashScope TTS API")
    if (result.bodyBytes.isEmpty()) {
        throw SpeechTtsDashScopeQwenException("empty_result", "DashScope TTS API returned empty audio.")
    }
    let raw = try { String.fromUtf8(result.bodyBytes).trimAscii() } catch (_: Exception) { "" }
    if (raw.startsWith("{") || raw.startsWith("[")) {
        return speechTtsDashScopeQwenAudioFromJson(result.bodyBytes, providerConfig, timeoutMs, maxBytes)
    }
    (result.bodyBytes, "mp3")
}

private func speechTtsCommandArgs(providerConfig: JsonObject, text: String, outputPath: Path): Array<String> {
    let raw = speechTtsStringArray(providerConfig, "command")
    let out = ArrayList<String>()
    for (part in raw) {
        out.add(part.replace("{text}", text).replace("{output}", outputPath.toString()))
    }
    out.toArray()
}

private func speechTtsAudioAsVoice(deliveryPrefs: JsonObject, state: JsonObject): Bool {
    speechTtsBool(state, "audioAsVoice", speechTtsBool(deliveryPrefs, "audioAsVoice", true))
}

private func speechTtsAudioAsVoice(config: JsonObject, deliveryPrefs: JsonObject, state: JsonObject): Bool {
    speechTtsBool(state, "audioAsVoice", speechTtsBool(deliveryPrefs, "audioAsVoice", speechTtsBool(config, "audioAsVoice", true)))
}

private func speechTtsStatusJson(status: String, ok!: Bool = false, message!: String = ""): JsonObject {
    let out = JsonObject()
    out.put("ok", JsonBool(ok))
    out.put("status", JsonString(status))
    if (!message.trimAscii().isEmpty()) {
        out.put("message", JsonString(message.trimAscii()))
    }
    out
}

private func speechTtsPayload(path: Path, provider: String, audioAsVoice: Bool): String {
    if (audioAsVoice) {
        "[voice]\nfileId=${path.toString()}\ncaption=TTS (${provider})"
    } else {
        "[audio]\nfileId=${path.toString()}\ncaption=TTS (${provider})"
    }
}

private func speechTtsProviderOrder(config: JsonObject, state: JsonObject): Array<String> {
    let configProvider = speechTtsString(config, "provider")
    let stateProvider = speechTtsString(state, "provider")
    let primary = if (!stateProvider.isEmpty()) { stateProvider } else { configProvider }
    let out = ArrayList<String>()
    if (!primary.isEmpty()) {
        out.add(primary)
    }
    for (fallback in speechTtsStringArray(config, "fallbackProviders")) {
        if (!speechTtsContains(out, fallback)) {
            out.add(fallback)
        }
    }
    out.toArray()
}

private func speechTtsAttempt(provider: String, providerKind: String, outcome: String, reasonCode: String, startedAtMs: Int64): JsonObject {
    let out = JsonObject()
    out.put("provider", JsonString(provider))
    out.put("providerKind", JsonString(providerKind))
    out.put("outcome", JsonString(outcome))
    if (!reasonCode.trimAscii().isEmpty()) {
        out.put("reasonCode", JsonString(reasonCode.trimAscii()))
    }
    out.put("latencyMs", JsonInt(max(0, speechTtsNowMs() - startedAtMs)))
    out
}

private func speechTtsAttachAttempts(result: JsonObject, attempts: JsonArray): JsonObject {
    result.put("attempts", attempts)
    result
}

private func speechTtsPutConfigDiagnostics(out: JsonObject, config: JsonObject): Unit {
    if (speechTtsBool(config, "legacy", false)) {
        out.put("legacy", JsonBool(true))
    }
    let migrationHint = speechTtsString(config, "migrationHint")
    if (!migrationHint.isEmpty()) {
        out.put("migrationHint", JsonString(migrationHint))
    }
}

private func gatewaySpeechTtsStatusForProvider(config: JsonObject, deliveryPrefs: JsonObject, state: JsonObject, provider: String): JsonObject {
    let enabled = speechTtsBool(state, "enabled", speechTtsBool(config, "enabled", true))
    let providerConfig = speechTtsProviderConfig(config, provider)
    let providerKind = speechTtsProviderKind(provider, providerConfig)
    let status = if (provider.isEmpty()) {
        "not_configured"
    } else if (!enabled) {
        "disabled"
    } else if (providerKind == "fake" || providerKind == "command") {
        "ok"
    } else if (providerKind == "openai-compatible") {
        if (speechTtsSecretString(providerConfig, "apiKey").isEmpty()) { "not_configured" } else { "ok" }
    } else if (providerKind == "dashscope-qwen-tts") {
        if (speechTtsSecretString(providerConfig, "apiKey").isEmpty()) {
            "not_configured"
        } else if (speechTtsString(providerConfig, "voice").isEmpty()) {
            "not_configured"
        } else {
            "ok"
        }
    } else {
        "not_found"
    }

    let out = speechTtsStatusJson(status, ok: status == "ok")
    out.put("enabled", JsonBool(enabled))
    out.put("provider", JsonString(provider))
    out.put("providerKind", JsonString(providerKind))
    out.put("limit", JsonInt(speechTtsInt(state, "limit", speechTtsInt(config, "maxChars", 4000))))
    out.put("audioAsVoice", JsonBool(speechTtsAudioAsVoice(config, deliveryPrefs, state)))
    speechTtsPutConfigDiagnostics(out, config)
    if (provider.isEmpty()) {
        out.put("message", JsonString("No Metis Gateway TTS provider is configured."))
    } else if (status == "not_configured" && providerKind == "openai-compatible") {
        out.put("message", JsonString("Configured OpenAI-compatible TTS provider '${provider}' is missing apiKey."))
    } else if (status == "not_configured" && providerKind == "dashscope-qwen-tts") {
        if (speechTtsSecretString(providerConfig, "apiKey").isEmpty()) {
            out.put("message", JsonString("Configured DashScope Qwen TTS provider '${provider}' is missing apiKey."))
        } else {
            out.put("message", JsonString("Configured DashScope Qwen TTS provider '${provider}' is missing voice."))
        }
    } else if (status == "not_found") {
        out.put("message", JsonString("Configured TTS provider '${provider}' is not available. Configure gateway.speech.tts.providers.${provider} or the channel speech override."))
    }
    out
}

public func gatewaySpeechTtsStatus(config: JsonObject, deliveryPrefs: JsonObject, state: JsonObject): JsonObject {
    let order = speechTtsProviderOrder(config, state)
    let provider = if (order.size > 0) { order[0] } else { "" }
    gatewaySpeechTtsStatusForProvider(config, deliveryPrefs, state, provider)
}

private func speechTtsResultFromStatus(status: JsonObject): JsonObject {
    let out = JsonObject()
    for ((k, v) in status.getFields()) {
        out.put(k, v)
    }
    out
}

private func speechTtsWriteFakeAudio(text: String, outputRoot: Path): Path {
    if (!exists(outputRoot)) {
        Directory.create(outputRoot, recursive: true)
    }
    let path = outputRoot.join("tts-${speechTtsNowMs()}.ogg")
    File.writeTo(path, ("FAKE-OGG\n${text}").toArray())
    path
}

private func gatewaySpeechTtsSynthesizeWithProvider(config: JsonObject, deliveryPrefs: JsonObject, state: JsonObject, text: String, outputRoot: Path, provider: String): JsonObject {
    let status = gatewaySpeechTtsStatusForProvider(config, deliveryPrefs, state, provider)
    let statusText = speechTtsString(status, "status")
    if (statusText != "ok") {
        return speechTtsResultFromStatus(status)
    }
    let limit = speechTtsInt(status, "limit", 4000)
    if (Int64(text.size) > limit) {
        let out = speechTtsStatusJson("too_large", ok: false, message: "TTS input exceeds configured limit.")
        out.put("provider", JsonString(provider))
        out.put("limit", JsonInt(limit))
        return out
    }
    let audioAsVoice = speechTtsBool(status, "audioAsVoice", true)
    let providerKind = speechTtsString(status, "providerKind")
    if (providerKind == "fake") {
        let audioPath = speechTtsWriteFakeAudio(text, outputRoot)
        status.put("audioPath", JsonString(audioPath.toString()))
        status.put("payloadKind", JsonString(if (audioAsVoice) { "voice" } else { "audio" }))
        status.put("payload", JsonString(speechTtsPayload(audioPath, provider, audioAsVoice)))
        return status
    }

    let providerConfig = speechTtsProviderConfig(config, provider)
    let outputDir = speechTtsOutputDir(config, providerConfig, outputRoot)
    if (providerKind == "openai-compatible") {
        let timeoutMs = max(1, speechTtsInt(providerConfig, "timeoutMs", speechTtsInt(config, "timeoutMs", 10000)))
        let request = speechTtsOpenAICompatibleHttpRequest(providerConfig, text, audioAsVoice, timeoutMs)
        let responseFormat = speechTtsString(request, "responseFormat")
        let outputPath = outputDir.join("tts-${speechTtsNowMs()}.${speechTtsOpenAICompatibleExtension(responseFormat)}")
        try {
            let audioBytes = speechTtsOpenAICompatiblePost(request, providerConfig)
            if (audioBytes.isEmpty()) {
                let out = speechTtsStatusJson("provider_error", ok: false, message: "Configured TTS provider returned empty audio.")
                out.put("provider", JsonString(provider))
                return out
            }
            File.writeTo(outputPath, audioBytes)
            status.put("audioPath", JsonString(outputPath.toString()))
            status.put("payloadKind", JsonString(if (audioAsVoice) { "voice" } else { "audio" }))
            status.put("payload", JsonString(speechTtsPayload(outputPath, provider, audioAsVoice)))
            return status
        } catch (e: SpeechTtsOpenAICompatibleException) {
            let out = speechTtsStatusJson(e.status, ok: false, message: e.message)
            out.put("provider", JsonString(provider))
            return out
        } catch (e: Exception) {
            let msg = e.message.toAsciiLower()
            if (msg.contains("timeout") || msg.contains("timed out")) {
                let out = speechTtsStatusJson("timeout", ok: false, message: "Configured TTS provider request timed out.")
                out.put("provider", JsonString(provider))
                out.put("timeoutMs", JsonInt(timeoutMs))
                return out
            }
            let out = speechTtsStatusJson("provider_error", ok: false, message: e.message)
            out.put("provider", JsonString(provider))
            return out
        }
    }

    if (providerKind == "dashscope-qwen-tts") {
        let timeoutMs = max(1, speechTtsInt(providerConfig, "timeoutMs", speechTtsInt(config, "timeoutMs", 60000)))
        let maxBytes = max(1, speechTtsInt(providerConfig, "maxAudioBytes", speechTtsInt(config, "maxAudioBytes", 25000000)))
        let request = speechTtsDashScopeQwenHttpRequest(providerConfig, text, timeoutMs)
        try {
            let result = speechTtsDashScopeQwenPost(request, providerConfig)
            let (audioBytes, extension) = speechTtsDashScopeQwenResultAudio(result, providerConfig, timeoutMs, maxBytes)
            if (audioBytes.isEmpty()) {
                let out = speechTtsStatusJson("empty_result", ok: false, message: "Configured TTS provider returned empty audio.")
                out.put("provider", JsonString(provider))
                out.put("providerKind", JsonString(providerKind))
                return out
            }
            if (Int64(audioBytes.size) > maxBytes) {
                let out = speechTtsStatusJson("too_large", ok: false, message: "Configured TTS provider returned audio larger than maxAudioBytes.")
                out.put("provider", JsonString(provider))
                out.put("providerKind", JsonString(providerKind))
                out.put("maxAudioBytes", JsonInt(maxBytes))
                return out
            }
            let outputPath = outputDir.join("tts-${speechTtsNowMs()}.${extension}")
            File.writeTo(outputPath, audioBytes)
            status.put("audioPath", JsonString(outputPath.toString()))
            status.put("payloadKind", JsonString(if (audioAsVoice) { "voice" } else { "audio" }))
            status.put("payload", JsonString(speechTtsPayload(outputPath, provider, audioAsVoice)))
            return status
        } catch (e: SpeechTtsDashScopeQwenException) {
            let out = speechTtsStatusJson(e.status, ok: false, message: e.message)
            out.put("provider", JsonString(provider))
            out.put("providerKind", JsonString(providerKind))
            return out
        } catch (e: Exception) {
            let msg = e.message.toAsciiLower()
            if (msg.contains("timeout") || msg.contains("timed out")) {
                let out = speechTtsStatusJson("timeout", ok: false, message: "Configured TTS provider request timed out.")
                out.put("provider", JsonString(provider))
                out.put("providerKind", JsonString(providerKind))
                out.put("timeoutMs", JsonInt(timeoutMs))
                return out
            }
            let out = speechTtsStatusJson("provider_error", ok: false, message: speechTtsDashScopeQwenRedact(e.message, providerConfig))
            out.put("provider", JsonString(provider))
            out.put("providerKind", JsonString(providerKind))
            return out
        }
    }

    let outputPath = outputDir.join("tts-${speechTtsNowMs()}.${speechTtsOutputExtension(providerConfig)}")
    let command = speechTtsCommandArgs(providerConfig, text, outputPath)
    if (command.size == 0) {
        let out = speechTtsStatusJson("not_found", ok: false, message: "Configured TTS provider '${provider}' has no command array.")
        out.put("provider", JsonString(provider))
        return out
    }
    let timeoutMs = max(1, speechTtsInt(providerConfig, "timeoutMs", speechTtsInt(config, "timeoutMs", 10000)))
    try {
        let (exitCode, stdout, _stderr) = ShellUtils.execute(command, timeout: Some(Duration.millisecond * timeoutMs), withWrap: false)
        if (exitCode != 0) {
            let out = speechTtsStatusJson("provider_error", ok: false, message: "Configured TTS provider command failed.")
            out.put("provider", JsonString(provider))
            out.put("exitCode", JsonInt(exitCode))
            return out
        }
        if (!exists(outputPath) && !stdout.isEmpty()) {
            File.writeTo(outputPath, stdout.toArray())
        }
        if (!exists(outputPath)) {
            let out = speechTtsStatusJson("provider_error", ok: false, message: "Configured TTS provider command did not create an audio file.")
            out.put("provider", JsonString(provider))
            out.put("outputPath", JsonString(outputPath.toString()))
            return out
        }
        status.put("audioPath", JsonString(outputPath.toString()))
        status.put("payloadKind", JsonString(if (audioAsVoice) { "voice" } else { "audio" }))
        status.put("payload", JsonString(speechTtsPayload(outputPath, provider, audioAsVoice)))
        return status
    } catch (_: ShellTimeoutException) {
        let out = speechTtsStatusJson("timeout", ok: false, message: "Configured TTS provider command timed out.")
        out.put("provider", JsonString(provider))
        out.put("timeoutMs", JsonInt(timeoutMs))
        return out
    } catch (e: Exception) {
        let out = speechTtsStatusJson("provider_error", ok: false, message: e.message)
        out.put("provider", JsonString(provider))
        return out
    }
}

public func gatewaySpeechTtsSynthesize(config: JsonObject, deliveryPrefs: JsonObject, state: JsonObject, text: String, outputRoot!: Path): JsonObject {
    let attempts = JsonArray()
    let order = speechTtsProviderOrder(config, state)
    if (order.size == 0) {
        return gatewaySpeechTtsSynthesizeWithProvider(config, deliveryPrefs, state, text, outputRoot, "")
    }

    var last = JsonObject()
    for (provider in order) {
        let startedAtMs = speechTtsNowMs()
        let result = gatewaySpeechTtsSynthesizeWithProvider(config, deliveryPrefs, state, text, outputRoot, provider)
        let ok = speechTtsBool(result, "ok", false)
        let status = speechTtsString(result, "status")
        let providerKind = speechTtsString(result, "providerKind")
        attempts.add(speechTtsAttempt(provider, providerKind, if (ok) { "ok" } else { "failed" }, if (ok) { "" } else { status }, startedAtMs))
        if (ok) {
            return speechTtsAttachAttempts(result, attempts)
        }
        last = result
    }

    let degradeMessage = speechTtsString(config, "degradeMessage")
    if (!degradeMessage.isEmpty()) {
        let degraded = speechTtsStatusJson("degraded", ok: true, message: "TTS failed; using configured degradeMessage.")
        degraded.put("provider", JsonString(speechTtsString(config, "provider")))
        degraded.put("payloadKind", JsonString("text"))
        degraded.put("payload", JsonString(degradeMessage))
        return speechTtsAttachAttempts(degraded, attempts)
    }
    speechTtsAttachAttempts(last, attempts)
}
