package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.core.message.Message
import magic.core.model.ChatRequest
import magic.model.ModelManager
import magic.prelude.*

import metis.core.gatewayCurrentToolRuntimeContext
import metis.core.{renderGatewayAudioText, renderGatewayDeleteText, renderGatewayDocumentText, renderGatewayEditText, renderGatewayPhotoText, renderGatewayPollText, renderGatewayReactionText, renderGatewayStickerText, renderGatewayTopicCreateText, renderGatewayTopicEditText, renderGatewayVideoNoteText, renderGatewayVideoText, renderGatewayVoiceText}
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisPaths}
import metis.core.{gatewayImageUnderstandingCandidateSummary, gatewayMediaUnderstandingFirstText, gatewayMediaUnderstandingForRecord, gatewayMediaUnderstandingOutputs}
import metis.core.model.gatewayImageCapabilityDecisionJson
import metis.io.PrintUtils

import std.collection.{ArrayList, HashSet}
import std.env.getVariable
import std.fs.{Directory, File, Path, copy, exists}
import std.process.executeWithOutput
import std.time.DateTime
import stdx.encoding.base64.toBase64String
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private var telegramMediaToolGatewayCallRunnerOverride: Option<(String, JsonObject) -> JsonObject> = None<(String, JsonObject) -> JsonObject>
private func telegramMediaToolString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func telegramMediaToolBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func telegramMediaToolInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { v.asInt().getValue() } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func telegramMediaToolNormalizeAccountId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) { "default" } else { trimmed }
}

private func telegramMediaToolSafeStateSegment(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return "default"
    }
    let out = StringBuilder()
    for (r in trimmed.runes()) {
        if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'.' || r == r'_' || r == r'-') {
            out.append(r)
        } else {
            out.append(r'_')
        }
    }
    let normalized = out.toString().trimAscii()
    if (normalized.isEmpty()) { "default" } else { normalized }
}

private func telegramMediaToolStatePath(mediaContext: JsonObject, accountId: String): Path {
    let explicit = telegramMediaToolString(mediaContext, "mediaStatePath")
    if (!explicit.isEmpty()) {
        return Path(explicit)
    }
    CliConfig.dotDir
        .join("gateway-telegram")
        .join("accounts")
        .join(telegramMediaToolSafeStateSegment(telegramMediaToolNormalizeAccountId(accountId)))
        .join("media-state.json")
}

private func telegramMediaToolContextRecords(mediaContext: JsonObject): JsonArray {
    match (mediaContext.get("records")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func telegramMediaToolRecentRecords(mediaContext: JsonObject): JsonArray {
    let accountId = telegramMediaToolNormalizeAccountId(telegramMediaToolString(mediaContext, "accountId"))
    let peerId = telegramMediaToolString(mediaContext, "peerId")
    if (peerId.isEmpty()) {
        return JsonArray([])
    }
    let path = telegramMediaToolStatePath(mediaContext, accountId)
    if (!exists(path)) {
        return JsonArray([])
    }
    let root = try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_e: Exception) {
        return JsonArray([])
    }
    let records = match (root.get("records")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let filtered = ArrayList<JsonObject>()
    for (item in records.getItems()) {
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let recordAccount = telegramMediaToolNormalizeAccountId(telegramMediaToolString(obj, "accountId"))
        let recordPeer = telegramMediaToolString(obj, "peerId")
        if (recordAccount == accountId && recordPeer == peerId) {
            filtered.add(obj)
        }
    }
    let out = JsonArray([])
    if (filtered.size == 0) {
        return out
    }
    var idx = filtered.size - 1
    var added: Int64 = 0
    while (idx >= 0 && added < 20) {
        let obj = filtered[idx]
        obj.put("sourceScope", JsonString("recent"))
        out.add(obj)
        idx -= 1
        added += 1
    }
    out
}

private func telegramMediaToolRecords(): JsonArray {
    match (gatewayCurrentToolRuntimeContext()) {
        case Some(ctx) =>
            let current = telegramMediaToolContextRecords(ctx.mediaContext)
            if (current.size() > 0) {
                return current
            }
            if (ctx.channelName == "telegram" || ctx.sourceLabel == "telegram" || telegramMediaToolString(ctx.mediaContext, "channel") == "telegram") {
                return telegramMediaToolRecentRecords(ctx.mediaContext)
            }
            JsonArray([])
        case None => JsonArray([])
    }
}

private func telegramMediaToolRecordMatches(
    obj: JsonObject,
    mediaId: String,
    messageId: String,
    relation: String
): Bool {
    if (!mediaId.isEmpty()) {
        let idMatch =
            telegramMediaToolString(obj, "mediaId") == mediaId ||
            telegramMediaToolString(obj, "fileId") == mediaId ||
            telegramMediaToolString(obj, "fileUniqueId") == mediaId
        if (!idMatch) {
            return false
        }
    }
    if (!messageId.isEmpty() && telegramMediaToolString(obj, "messageId") != messageId) {
        return false
    }
    if (!relation.isEmpty() && telegramMediaToolString(obj, "relation").toAsciiLower() != relation.toAsciiLower()) {
        return false
    }
    true
}

private func telegramMediaToolRecordByTarget(
    mediaId: String,
    index: Int64,
    messageId!: String = "",
    relation!: String = ""
): Option<JsonObject> {
    let records = telegramMediaToolRecords()
    var i: Int64 = 0
    for (item in records.getItems()) {
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        if (telegramMediaToolRecordMatches(obj, mediaId, messageId, relation)) {
            if (!mediaId.isEmpty() || !messageId.isEmpty() || !relation.isEmpty()) {
                return Some(obj)
            }
            if (i == index) {
                return Some(obj)
            }
        }
        i += 1
    }
    None<JsonObject>
}

private func telegramMediaError(action: String, message: String): String {
    let out = JsonObject()
    out.put("ok", JsonBool(false))
    out.put("status", JsonString("error"))
    out.put("action", JsonString(action))
    out.put("error", JsonString(message))
    out.toJsonString()
}

private func telegramMediaToolReadableMime(mimeType: String, fileName: String): Bool {
    let mime = mimeType.trimAscii().toAsciiLower()
    let name = fileName.trimAscii().toAsciiLower()
    if (mime.startsWith("text/") || mime == "application/json" || mime == "application/xml") {
        return true
    }
    name.endsWith(".txt") || name.endsWith(".md") || name.endsWith(".json") || name.endsWith(".xml") ||
        name.endsWith(".csv") || name.endsWith(".cj") || name.endsWith(".ts") || name.endsWith(".js") ||
        name.endsWith(".py") || name.endsWith(".log")
}

private func telegramMediaToolSafePreview(text: String, maxChars: Int64): (String, Bool) {
    let limit = if (maxChars <= 0) { 8192 } else { maxChars }
    if (text.size <= limit) {
        return (text, false)
    }
    (text[0..limit], true)
}

private func telegramMediaToolFileExtension(name: String): String {
    let trimmed = name.trimAscii()
    var dot: Int64 = -1
    for (i in 0..trimmed.size) {
        if (trimmed[i] == UInt8(46)) {
            dot = i
        }
    }
    if (dot >= 0 && dot < trimmed.size - 1) {
        return trimmed[dot..]
    }
    ""
}

private func telegramMediaToolExtensionFromMime(mimeType: String): String {
    let mime = mimeType.trimAscii().toAsciiLower()
    if (mime == "image/jpeg") { return ".jpg" }
    if (mime == "image/png") { return ".png" }
    if (mime == "image/gif") { return ".gif" }
    if (mime == "image/webp") { return ".webp" }
    if (mime == "audio/ogg") { return ".ogg" }
    if (mime == "audio/mpeg") { return ".mp3" }
    if (mime == "audio/mp4") { return ".m4a" }
    if (mime == "video/mp4") { return ".mp4" }
    if (mime == "application/pdf") { return ".pdf" }
    if (mime == "application/json") { return ".json" }
    if (mime.startsWith("text/")) { return ".txt" }
    ""
}

private func telegramMediaToolDestinationLooksProtected(raw: String): Bool {
    let value = raw.trimAscii()
    let low = value.toAsciiLower()
    value.contains("\u{0}") ||
        low.contains("/.metis/") ||
        low.endsWith("/metis.json") ||
        low == "metis.json" ||
        low.startsWith("/etc/") ||
        low.startsWith("/private/etc/") ||
        low.startsWith("/system/") ||
        low.startsWith("/bin/") ||
        low.startsWith("/sbin/") ||
        low.startsWith("/usr/bin/") ||
        low.startsWith("/var/db/")
}

private func telegramMediaToolLooksLikeImagePlaceholder(raw: String): Bool {
    let value = raw.trimAscii()
    let low = value.toAsciiLower()
    value.isEmpty() ||
        value == "." ||
        low == "current" ||
        low == "default" ||
        (value.startsWith("[Image #") && value.endsWith("]")) ||
        (low.startsWith("[image #") && low.endsWith("]"))
}

private func telegramMediaToolPathInsideOrEqual(path: Path, root: Path): Bool {
    let pathText = path.toString().trimAscii()
    let rootText = root.toString().trimAscii()
    if (pathText.isEmpty() || rootText.isEmpty()) {
        return false
    }
    if (pathText == rootText) {
        return true
    }
    let prefix = if (rootText.endsWith("/")) { rootText } else { rootText + "/" }
    pathText.startsWith(prefix)
}

private func telegramMediaToolPathInsideWorkspace(path: Path): Bool {
    if (telegramMediaToolPathInsideOrEqual(path, CliConfig.cwd)) {
        return true
    }
    match (MetisPaths.projectRoot()) {
        case Some(root) => telegramMediaToolPathInsideOrEqual(path, root)
        case None => false
    }
}

private func telegramMediaToolArchiveDirForRecord(record: JsonObject): Path {
    let sourcePath = telegramMediaToolString(record, "localPath")
    if (!sourcePath.isEmpty()) {
        return Path(sourcePath).parent
    }
    let accountId = telegramMediaToolNormalizeAccountId(telegramMediaToolString(record, "accountId"))
    CliConfig.dotDir
        .join("gateway-telegram")
        .join("accounts")
        .join(telegramMediaToolSafeStateSegment(accountId))
        .join("media")
}

private func telegramMediaToolResolveDestination(destination: String, record: JsonObject): (Bool, Path, String, Bool) {
    let raw = destination.trimAscii()
    let sourcePath = telegramMediaToolString(record, "localPath")
    if (telegramMediaToolLooksLikeImagePlaceholder(raw)) {
        if (sourcePath.isEmpty()) {
            return (false, Path(raw), "media resource has no downloaded localPath", false)
        }
        return (true, Path(sourcePath), "", false)
    }
    if (telegramMediaToolDestinationLooksProtected(raw)) {
        return (false, Path(raw), "destination path is protected", false)
    }
    var dest: Path
    if (raw.startsWith("~/")) {
        let home = match (getVariable("HOME")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (home.isEmpty()) {
            return (false, Path(raw), "HOME is not available for ~/ destination", false)
        }
        dest = Path(home).join(raw[2..])
    } else {
        dest = Path(raw)
        if (!dest.isAbsolute()) {
            if (raw.contains("..") || raw.contains("\\")) {
                return (false, Path(raw), "relative destination is unsafe", false)
            }
            dest = telegramMediaToolArchiveDirForRecord(record).join(raw)
        }
    }
    if (telegramMediaToolPathInsideWorkspace(dest)) {
        return (false, dest, "destination path is inside the Metis workspace; omit destination to keep the Telegram archive path or choose an explicit non-workspace path", false)
    }
    let originalName = telegramMediaToolString(record, "originalFileName")
    let fileName = if (originalName.isEmpty()) { telegramMediaToolString(record, "fileName") } else { originalName }
    let inferredExt = if (!telegramMediaToolFileExtension(dest.toString()).isEmpty()) {
        ""
    } else {
        let fromName = telegramMediaToolFileExtension(fileName)
        if (!fromName.isEmpty()) { fromName } else { telegramMediaToolExtensionFromMime(telegramMediaToolString(record, "mimeType")) }
    }
    if (!inferredExt.isEmpty()) {
        dest = Path(dest.toString() + inferredExt)
    }
    (true, dest, "", true)
}

private func telegramMediaToolProviderFromModelRef(modelRef: String): String {
    let normalized = modelRef.trimAscii()
    if (normalized.contains(":")) {
        return normalized.split(":", 2)[0].trimAscii().toAsciiLower()
    }
    if (normalized.contains("/")) {
        return normalized.split("/", 2)[0].trimAscii().toAsciiLower()
    }
    ""
}

private func telegramMediaToolVisionProviderSupported(modelRef: String): Bool {
    let provider = telegramMediaToolProviderFromModelRef(modelRef)
    if (provider.isEmpty()) {
        // Registered test/local models do not need a provider prefix.
        return !modelRef.trimAscii().isEmpty()
    }
    try {
        return gatewayImageCapabilityDecisionJson(modelRef)
            .get("supported")
            .getOrThrow()
            .asBool()
            .getValue()
    } catch (_: Exception) {
        false
    }
}

private func telegramMediaToolAddVisionCandidate(out: ArrayList<String>, seen: ArrayList<String>, raw: String): Unit {
    let modelRef = raw.trimAscii()
    if (modelRef.isEmpty() || seen.contains(modelRef)) {
        return
    }
    seen.add(modelRef)
    out.add(modelRef)
}

private var telegramMediaToolVisionCandidatesOverride: Option<Array<String>> = None<Array<String>>
private var telegramStickerCacheRootOverride: Option<Path> = None<Path>

public func setGatewayTelegramMediaVisionCandidatesForTest(candidates: Option<Array<String>>): Unit {
    telegramMediaToolVisionCandidatesOverride = candidates
}

public func setGatewayTelegramStickerCacheRootForTest(root: Option<Path>): Unit {
    telegramStickerCacheRootOverride = root
}

private func telegramStickerCacheRoot(): Path {
    match (telegramStickerCacheRootOverride) {
        case Some(root) => root
        case None => CliConfig.dotDir.join("gateway-telegram")
    }
}

private func telegramStickerCachePath(): Path {
    telegramStickerCacheRoot().join("sticker-cache.json")
}

private func telegramStickerCacheLoad(): JsonArray {
    let path = telegramStickerCachePath()
    if (!exists(path)) {
        return JsonArray([])
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
}

private func telegramStickerCacheKey(record: JsonObject): String {
    let uniqueId = telegramMediaToolString(record, "fileUniqueId")
    if (!uniqueId.isEmpty()) {
        return "unique:${uniqueId}"
    }
    let fileId = telegramMediaToolString(record, "fileId")
    if (!fileId.isEmpty()) {
        return "file:${fileId}"
    }
    telegramMediaToolString(record, "mediaId")
}

private func telegramStickerCachePersistCurrentRecords(): JsonArray {
    let existing = telegramStickerCacheLoad()
    let seen = HashSet<String>()
    let merged = JsonArray([])
    for (item in existing.getItems()) {
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let key = telegramStickerCacheKey(obj)
        if (!key.isEmpty() && !seen.contains(key)) {
            seen.add(key)
            merged.add(obj)
        }
    }
    for (item in telegramMediaToolRecords().getItems()) {
        let record = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        if (telegramMediaToolString(record, "mediaKind").toAsciiLower() != "sticker") {
            continue
        }
        let key = telegramStickerCacheKey(record)
        if (key.isEmpty() || seen.contains(key)) {
            continue
        }
        seen.add(key)
        let cached = JsonObject()
        for (field in ["mediaId", "fileId", "fileUniqueId", "emoji", "setName", "description", "analysis", "mimeType", "fileName", "localPath", "downloaded", "createdAtMs"]) {
            match (record.get(field)) {
                case Some(v) => cached.put(field, v)
                case None => ()
            }
        }
        if (telegramMediaToolString(cached, "emoji").isEmpty()) {
            let emoji = telegramMediaToolString(record, "stickerEmoji")
            if (!emoji.isEmpty()) { cached.put("emoji", JsonString(emoji)) }
        }
        if (telegramMediaToolString(cached, "setName").isEmpty()) {
            let setName = telegramMediaToolString(record, "stickerSetName")
            if (!setName.isEmpty()) { cached.put("setName", JsonString(setName)) }
        }
        cached.put("mediaKind", JsonString("sticker"))
        cached.put("cachedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        merged.add(cached)
    }
    let root = telegramStickerCacheRoot()
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    File.writeTo(telegramStickerCachePath(), merged.toJsonString().toArray())
    merged
}

private func telegramStickerCacheUpsertAnalysis(record: JsonObject, analysis: String): Unit {
    let key = telegramStickerCacheKey(record)
    if (key.isEmpty() || analysis.trimAscii().isEmpty()) {
        return
    }
    let existing = telegramStickerCacheLoad()
    let merged = JsonArray([])
    var updated = false
    for (item in existing.getItems()) {
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        if (telegramStickerCacheKey(obj) == key) {
            obj.put("analysis", JsonString(analysis.trimAscii()))
            obj.put("description", JsonString(analysis.trimAscii()))
            obj.put("cachedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
            updated = true
        }
        merged.add(obj)
    }
    if (!updated) {
        let cached = JsonObject()
        for (field in ["mediaId", "fileId", "fileUniqueId", "emoji", "setName", "mimeType", "fileName", "localPath", "downloaded", "createdAtMs"]) {
            match (record.get(field)) {
                case Some(v) => cached.put(field, v)
                case None => ()
            }
        }
        if (telegramMediaToolString(cached, "emoji").isEmpty()) {
            let emoji = telegramMediaToolString(record, "stickerEmoji")
            if (!emoji.isEmpty()) { cached.put("emoji", JsonString(emoji)) }
        }
        if (telegramMediaToolString(cached, "setName").isEmpty()) {
            let setName = telegramMediaToolString(record, "stickerSetName")
            if (!setName.isEmpty()) { cached.put("setName", JsonString(setName)) }
        }
        cached.put("mediaKind", JsonString("sticker"))
        cached.put("analysis", JsonString(analysis.trimAscii()))
        cached.put("description", JsonString(analysis.trimAscii()))
        cached.put("cachedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        merged.add(cached)
    }
    let root = telegramStickerCacheRoot()
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    File.writeTo(telegramStickerCachePath(), merged.toJsonString().toArray())
}

private func telegramMediaToolVisionCandidates(): Array<String> {
    match (telegramMediaToolVisionCandidatesOverride) {
        case Some(candidates) => return candidates
        case None => ()
    }
    let out = ArrayList<String>()
    let seen = ArrayList<String>()
    let settings = CliSettingManager.readGatewaySettings()
    let imageCandidates = gatewayImageUnderstandingCandidateSummary(settings, channel: "telegram")
    for (candidate in imageCandidates.getItems()) {
        try {
            telegramMediaToolAddVisionCandidate(
                out,
                seen,
                candidate.asObject().get("modelRef").getOrThrow().asString().getValue()
            )
        } catch (_: Exception) {
            ()
        }
    }
    telegramMediaToolAddVisionCandidate(out, seen, settings.channelModels.get("telegram") ?? "")
    telegramMediaToolAddVisionCandidate(out, seen, CliConfig.modelOrEmpty())
    for (modelRef in CliConfig.fallbackModels) {
        telegramMediaToolAddVisionCandidate(out, seen, modelRef)
    }
    out.toArray()
}

private func telegramMediaToolDataUrlMime(record: JsonObject): String {
    let mime = telegramMediaToolString(record, "mimeType").trimAscii().toAsciiLower()
    if (mime.startsWith("image/")) {
        return mime
    }
    let name = telegramMediaToolString(record, "fileName").toAsciiLower()
    if (name.endsWith(".png")) { return "image/png" }
    if (name.endsWith(".gif")) { return "image/gif" }
    if (name.endsWith(".webp")) { return "image/webp" }
    "image/jpeg"
}

private func telegramMediaToolDescribeImageWithModel(record: JsonObject, userPrompt: String): JsonObject {
    let out = JsonObject()
    out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
    let sourcePath = telegramMediaToolString(record, "localPath")
    if (sourcePath.isEmpty() || !exists(Path(sourcePath))) {
        out.put("ok", JsonBool(false))
        out.put("status", JsonString("unsupported"))
        out.put("error", JsonString("image localPath is missing or not downloaded"))
        return out
    }
    let bytes = File.readFrom(Path(sourcePath))
    let limit = CliSettingManager.readGatewaySettings().telegram.media.mediaMaxBytes
    if (limit > 0 && Int64(bytes.size) > limit) {
        out.put("ok", JsonBool(false))
        out.put("status", JsonString("unsupported"))
        out.put("error", JsonString("image exceeds configured Telegram mediaMaxBytes"))
        out.put("fileBytes", Int64(bytes.size).toJsonValue())
        out.put("limitBytes", limit.toJsonValue())
        return out
    }
    let candidates = telegramMediaToolVisionCandidates()
    if (candidates.isEmpty()) {
        out.put("ok", JsonBool(false))
        out.put("status", JsonString("unsupported"))
        out.put("error", JsonString("no model is configured for Telegram image understanding"))
        return out
    }
    let errors = JsonArray([])
    let prompt = if (userPrompt.trimAscii().isEmpty()) {
        "Describe this Telegram image clearly and concisely for the current user request."
    } else {
        userPrompt.trimAscii()
    }
    let dataUrl = "data:${telegramMediaToolDataUrlMime(record)};base64,${toBase64String(bytes)}"
    for (modelRef in candidates) {
        if (!telegramMediaToolVisionProviderSupported(modelRef)) {
            let skipped = JsonObject()
            skipped.put("model", JsonString(modelRef))
            skipped.put("status", JsonString("unsupported_model"))
            skipped.put("capability", gatewayImageCapabilityDecisionJson(modelRef).toJsonValue())
            errors.add(skipped)
            continue
        }
        try {
            let model = ModelManager.createChatModel(modelRef)
            let response = model.create(ChatRequest(Message.user(prompt, image: Some(dataUrl)), temperature: Some(0.0), maxTokens: Some(1024)))
            let content = response.message.content.trimAscii()
            if (!content.isEmpty()) {
                out.put("ok", JsonBool(true))
                out.put("status", JsonString("ok"))
                out.put("analysis", JsonString(content))
                out.put("provider", JsonString(model.provider))
                out.put("model", JsonString(model.fullName))
                return out
            }
            let empty = JsonObject()
            empty.put("model", JsonString(modelRef))
            empty.put("status", JsonString("empty_response"))
            errors.add(empty)
        } catch (e: Exception) {
            let err = JsonObject()
            err.put("model", JsonString(modelRef))
            err.put("status", JsonString("provider_error"))
            err.put("error", JsonString(e.message))
            errors.add(err)
        }
    }
    out.put("ok", JsonBool(false))
    out.put("status", JsonString("unsupported"))
    out.put("error", JsonString("no configured vision-capable model could analyze this Telegram image"))
    out.put("attempts", errors)
    out
}

private func telegramMediaToolGatewayBinaryCommand(): (String, Option<Path>) {
    match (MetisPaths.projectRoot()) {
        case Some(root) =>
            let devBinary = root.join("target").join("release").join("bin").join("metis")
            if (exists(devBinary)) {
                return (devBinary.toString(), Some(root))
            }
            return ("metis", Some(root))
        case None => ("metis", None<Path>)
    }
}

private func telegramMediaToolInvokeGatewayCall(method: String, params!: Option<JsonObject> = None<JsonObject>): JsonObject {
    let overrideParams = match (params) {
        case Some(obj) => obj
        case None => JsonObject()
    }
    match (telegramMediaToolGatewayCallRunnerOverride) {
        case Some(runner) => return runner(method, overrideParams)
        case None => ()
    }
    let (command, workDir) = telegramMediaToolGatewayBinaryCommand()
    let args = match (params) {
        case Some(obj) => ["gateway", "call", method, obj.toJsonString()]
        case None => ["gateway", "call", method]
    }
    let (exitCode, stdoutBytes, stderrBytes) = executeWithOutput(command, args, workingDirectory: workDir)
    let stdout = try { String.fromUtf8(stdoutBytes).trimAscii() } catch (_: Exception) { "" }
    let stderr = try { String.fromUtf8(stderrBytes).trimAscii() } catch (_: Exception) { "" }
    if (!stdout.isEmpty()) {
        try {
            let obj = JsonValue.fromStr(stdout).asObject()
            obj.put("exitCode", exitCode.toJsonValue())
            if (!stderr.isEmpty()) {
                obj.put("stderr", JsonString(stderr))
            }
            return obj
        } catch (_: Exception) {
            ()
        }
    }
    let out = JsonObject()
    out.put("ok", JsonBool(exitCode == 0))
    out.put("exitCode", exitCode.toJsonValue())
    out.put("stdout", JsonString(stdout))
    out.put("stderr", JsonString(stderr))
    out
}

private func telegramMediaToolCurrentTarget(): (String, String, String) {
    match (gatewayCurrentToolRuntimeContext()) {
        case Some(ctx) =>
            let channel = if (ctx.channelName.isEmpty()) { ctx.sourceLabel } else { ctx.channelName }
            let sessionKey = ctx.sessionKey.trimAscii()
            if (channel == "telegram" && sessionKey.startsWith("telegram:direct:")) {
                return ("telegram", sessionKey["telegram:direct:".size..], ctx.sessionKey)
            }
            if (channel == "telegram" && sessionKey.startsWith("telegram:group:")) {
                return ("telegram", sessionKey["telegram:group:".size..], ctx.sessionKey)
            }
            return (channel, "", sessionKey)
        case None => ("", "", "")
    }
}

private func telegramMediaToolBuildMediaText(kind: String, media: String, caption: String): String {
    let normalized = kind.trimAscii().toAsciiLower()
    if (normalized == "photo" || normalized == "image") {
        return renderGatewayPhotoText(media, caption: caption)
    }
    if (normalized == "audio") {
        return renderGatewayAudioText(media, caption: caption)
    }
    if (normalized == "voice") {
        return renderGatewayVoiceText(media, caption: caption)
    }
    if (normalized == "video") {
        return renderGatewayVideoText(media, caption: caption)
    }
    if (normalized == "video-note" || normalized == "video_note" || normalized == "videonote") {
        return renderGatewayVideoNoteText(media)
    }
    if (normalized == "sticker") {
        return renderGatewayStickerText(media)
    }
    renderGatewayDocumentText(media, caption: caption)
}

@toolset
public class GatewayTelegramMediaToolset {
    public func debugSetGatewayCallRunnerForTest(runner: Option<(String, JsonObject) -> JsonObject>): Unit {
        telegramMediaToolGatewayCallRunnerOverride = runner
    }

    public func debugTelegramMediaListForTest(): String {
        this.renderTelegramMediaList()
    }

    public func debugTelegramMediaSaveForTest(destination: Option<String>, mediaId: Option<String>, index: Option<Int64>): String {
        this.saveTelegramMedia(destination, mediaId, index)
    }

    public func debugTelegramMediaGetForTest(mediaId: Option<String>, index: Option<Int64>, messageId: Option<String>, relation: Option<String>): String {
        this.getTelegramMedia(mediaId, index, messageId, relation)
    }

    public func debugTelegramMediaReadForTest(mediaId: Option<String>, index: Option<Int64>, maxBytes: Option<Int64>): String {
        this.readTelegramMedia(mediaId, index, maxBytes)
    }

    public func debugTelegramImageAnalyzeForTest(mediaId: Option<String>, index: Option<Int64>, prompt: Option<String>): String {
        this.analyzeTelegramImage(mediaId, index, prompt)
    }

    public func debugTelegramAudioTranscribeForTest(mediaId: Option<String>, index: Option<Int64>): String {
        this.transcribeTelegramAudio(mediaId, index)
    }

    public func debugTelegramVideoDescribeForTest(mediaId: Option<String>, index: Option<Int64>): String {
        this.describeTelegramVideo(mediaId, index)
    }

    public func debugTelegramDocumentExtractForTest(mediaId: Option<String>, index: Option<Int64>, maxBytes: Option<Int64>): String {
        this.extractTelegramDocument(mediaId, index, maxBytes)
    }

    public func debugTelegramTargetListFromAuditForTest(auditEnvelope: JsonObject): String {
        this.renderTelegramTargetListFromAudit(auditEnvelope)
    }

    public func debugTelegramDoctorFromEnvelopeForTest(doctorEnvelope: JsonObject): String {
        this.renderTelegramDoctorFromEnvelope(doctorEnvelope)
    }

    public func debugTelegramTargetWritebackDryRunForTest(target: String, resolvedChatId: Option<String>): String {
        this.telegramTargetWritebackDryRun(target, resolvedChatId)
    }

    public func debugTelegramTargetWritebackApplyForTest(target: String, resolvedChatId: Option<String>): String {
        this.telegramTargetWritebackApply(target, resolvedChatId)
    }

    public func debugTelegramSendToTargetForTest(target: String, message: String, writeback: Option<String>, dryRun: Option<Bool>): String {
        this.telegramSendToTargetResolved(target, message, writeback, dryRun)
    }

    public func debugTelegramStickerSearchForTest(query: String, limit: Option<Int64>): String {
        this.searchTelegramStickers(query, limit)
    }

    public func debugTelegramStickerGetForTest(mediaId: Option<String>, fileUniqueId: Option<String>, fileId: Option<String>): String {
        this.getTelegramSticker(mediaId, fileUniqueId, fileId)
    }

    public func debugTelegramStickerCacheStatsForTest(): String {
        this.telegramStickerCacheStats()
    }

    public func debugTelegramActionForTest(
        action: String,
        target: Option<String>,
        message: Option<String>,
        messageId: Option<String>,
        emoji: Option<String>,
        pollOptions: Option<Array<String>>,
        stickerFileId: Option<String>,
        topicName: Option<String>
    ): String {
        this.telegramAction(action, target, message, messageId, emoji, pollOptions, stickerFileId, topicName)
    }

    private func renderTelegramMediaList(): String {
        let records = telegramMediaToolRecords()
        let out = JsonObject()
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("ok"))
        out.put("count", records.size().toJsonValue())
        out.put("records", records)
        out.toJsonString()
    }

    private func getTelegramMedia(mediaId: Option<String>, index: Option<Int64>, messageId: Option<String>, relation: Option<String>): String {
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetIndex = match (index) {
            case Some(v) => v
            case None => 0
        }
        let targetMessageId = match (messageId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetRelation = match (relation) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let out = JsonObject()
        match (telegramMediaToolRecordByTarget(targetMediaId, targetIndex, messageId: targetMessageId, relation: targetRelation)) {
            case Some(record) =>
                out.put("ok", JsonBool(true))
                out.put("status", JsonString("ok"))
                out.put("media", record)
            case None =>
                out.put("ok", JsonBool(false))
                out.put("status", JsonString("error"))
                out.put("error", JsonString("media resource not found in current turn or recent same-peer Telegram media"))
                if (!targetMediaId.isEmpty()) { out.put("mediaId", JsonString(targetMediaId)) }
                if (!targetMessageId.isEmpty()) { out.put("messageId", JsonString(targetMessageId)) }
                if (!targetRelation.isEmpty()) { out.put("relation", JsonString(targetRelation)) }
        }
        out.toJsonString()
    }

    private func saveTelegramMedia(destination: Option<String>, mediaId: Option<String>, index: Option<Int64>): String {
        let targetPathText = match (destination) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetIndex = match (index) {
            case Some(v) => v
            case None => 0
        }
        let out = JsonObject()
        let record = match (telegramMediaToolRecordByTarget(targetMediaId, targetIndex)) {
            case Some(v) => v
            case None =>
                out.put("ok", JsonBool(false))
                out.put("status", JsonString("error"))
                out.put("error", JsonString("media resource not found in current turn or recent same-peer Telegram media"))
                return out.toJsonString()
        }
        let sourcePath = telegramMediaToolString(record, "localPath")
        if (sourcePath.isEmpty() || !telegramMediaToolBool(record, "downloaded") || !exists(Path(sourcePath))) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("error"))
            out.put("error", JsonString("media resource has no downloaded localPath"))
            out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
            return out.toJsonString()
        }
        let (allowed, dest, reason, shouldCopy) = telegramMediaToolResolveDestination(targetPathText, record)
        if (!allowed) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("denied"))
            out.put("error", JsonString(reason))
            out.put("destination", JsonString(targetPathText))
            return out.toJsonString()
        }
        if (shouldCopy) {
            let parent = dest.parent
            if (!exists(parent)) {
                Directory.create(parent, recursive: true)
            }
            copy(Path(sourcePath), to: dest, overwrite: true)
        }
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("saved"))
        out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
        out.put("mediaKind", JsonString(telegramMediaToolString(record, "mediaKind")))
        out.put("sourcePath", JsonString(sourcePath))
        out.put("archivePath", JsonString(sourcePath))
        out.put("destination", JsonString(dest.toString()))
        out.put("copied", JsonBool(shouldCopy))
        out.put("alreadyArchived", JsonBool(!shouldCopy))
        out.put("savedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        out.toJsonString()
    }

    private func readTelegramMedia(mediaId: Option<String>, index: Option<Int64>, maxBytes: Option<Int64>): String {
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetIndex = match (index) {
            case Some(v) => v
            case None => 0
        }
        let limit = match (maxBytes) {
            case Some(v) => if (v <= 0) { 8192 } else { v }
            case None => 8192
        }
        let out = JsonObject()
        let record = match (telegramMediaToolRecordByTarget(targetMediaId, targetIndex)) {
            case Some(v) => v
            case None =>
                out.put("ok", JsonBool(false))
                out.put("status", JsonString("error"))
                out.put("error", JsonString("media resource not found in current turn or recent same-peer Telegram media"))
                return out.toJsonString()
        }
        let sourcePath = telegramMediaToolString(record, "localPath")
        let fileName = if (!telegramMediaToolString(record, "fileName").isEmpty()) {
            telegramMediaToolString(record, "fileName")
        } else {
            telegramMediaToolString(record, "originalFileName")
        }
        let mimeType = telegramMediaToolString(record, "mimeType")
        out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
        out.put("mediaKind", JsonString(telegramMediaToolString(record, "mediaKind")))
        out.put("mimeType", JsonString(mimeType))
        out.put("fileName", JsonString(fileName))
        if (sourcePath.isEmpty() || !exists(Path(sourcePath))) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("error"))
            out.put("readable", JsonBool(false))
            out.put("error", JsonString("media resource has no downloaded localPath"))
            return out.toJsonString()
        }
        if (!telegramMediaToolReadableMime(mimeType, fileName)) {
            out.put("ok", JsonBool(true))
            out.put("status", JsonString("ok"))
            out.put("readable", JsonBool(false))
            out.put("reason", JsonString("media is not a text-readable file"))
            return out.toJsonString()
        }
        let text = try { String.fromUtf8(File.readFrom(Path(sourcePath))) } catch (_e: Exception) { "" }
        let (preview, truncated) = telegramMediaToolSafePreview(text, limit)
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("ok"))
        out.put("readable", JsonBool(true))
        out.put("content", JsonString(preview))
        out.put("truncated", JsonBool(truncated))
        out.put("maxBytes", limit.toJsonValue())
        out.toJsonString()
    }

    private func analyzeTelegramImage(mediaId: Option<String>, index: Option<Int64>, prompt: Option<String>): String {
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetIndex = match (index) {
            case Some(v) => v
            case None => 0
        }
        let out = JsonObject()
        let record = match (telegramMediaToolRecordByTarget(targetMediaId, targetIndex)) {
            case Some(v) => v
            case None =>
                out.put("ok", JsonBool(false))
                out.put("status", JsonString("error"))
                out.put("error", JsonString("media resource not found in current turn or recent same-peer Telegram media"))
                return out.toJsonString()
        }
        let kind = telegramMediaToolString(record, "mediaKind").toAsciiLower()
        let mime = telegramMediaToolString(record, "mimeType").toAsciiLower()
        if (!(kind == "photo" || kind == "image" || kind == "sticker" || mime.startsWith("image/"))) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("unsupported"))
            out.put("error", JsonString("selected media is not image-like"))
            return out.toJsonString()
        }
        out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
        let promptText = match (prompt) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (!promptText.isEmpty()) { out.put("prompt", JsonString(promptText)) }
        let capability = if (kind == "sticker") { "sticker" } else { "image" }
        let understanding = gatewayMediaUnderstandingForRecord(record, capability: capability, prompt: promptText)
        let analysis = gatewayMediaUnderstandingFirstText(understanding)
        if (!analysis.isEmpty()) {
            out.put("ok", JsonBool(true))
            out.put("status", JsonString("ok"))
            out.put("analysis", JsonString(analysis))
            match (understanding.get("outputs")) {
                case Some(v) => out.put("outputs", v)
                case None => ()
            }
            match (understanding.get("decision")) {
                case Some(v) => out.put("decision", v)
                case None => ()
            }
            match (understanding.get("capability")) {
                case Some(v) => out.put("capability", v)
                case None => ()
            }
            for (key in ["provider", "model", "attempts"]) {
                match (understanding.get(key)) {
                    case Some(v) => out.put(key, v)
                    case None => ()
                }
            }
            let outputs = gatewayMediaUnderstandingOutputs(understanding)
            let source = if (outputs.size() > 0) {
                try { outputs[0].asObject().get("source").getOrThrow().asString().getValue() } catch (_e: Exception) { "media_understanding_runtime" }
            } else {
                "media_understanding_runtime"
            }
            out.put("source", JsonString(source))
            if (kind == "sticker") {
                telegramStickerCacheUpsertAnalysis(record, analysis)
            }
        } else {
            let runtime = telegramMediaToolDescribeImageWithModel(record, promptText)
            for (key in ["ok", "status", "analysis", "provider", "model", "error", "attempts", "fileBytes", "limitBytes"]) {
                match (runtime.get(key)) {
                    case Some(v) => out.put(key, v)
                    case None => ()
                }
            }
            if (!(try { runtime.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false })) {
                out.put("fallback", JsonString("Configure agents.defaults.imageModel.primary or gateway.media.image.models with a vision-capable image understanding model."))
            } else if (kind == "sticker") {
                telegramStickerCacheUpsertAnalysis(record, telegramMediaToolString(runtime, "analysis"))
            }
        }
        out.toJsonString()
    }

    private func transcribeTelegramAudio(mediaId: Option<String>, index: Option<Int64>): String {
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetIndex = match (index) {
            case Some(v) => v
            case None => 0
        }
        let out = JsonObject()
        let record = match (telegramMediaToolRecordByTarget(targetMediaId, targetIndex)) {
            case Some(v) => v
            case None =>
                out.put("ok", JsonBool(false))
                out.put("status", JsonString("error"))
                out.put("error", JsonString("media resource not found in current turn or recent same-peer Telegram media"))
                return out.toJsonString()
        }
        let kind = telegramMediaToolString(record, "mediaKind").toAsciiLower()
        let mime = telegramMediaToolString(record, "mimeType").toAsciiLower()
        if (!(kind == "voice" || kind == "audio" || mime.startsWith("audio/"))) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("unsupported"))
            out.put("error", JsonString("selected media is not audio-like"))
            return out.toJsonString()
        }
        let understanding = gatewayMediaUnderstandingForRecord(record, capability: "audio")
        let transcript = gatewayMediaUnderstandingFirstText(understanding)
        out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
        match (understanding.get("outputs")) {
            case Some(v) => out.put("outputs", v)
            case None => ()
        }
        match (understanding.get("decision")) {
            case Some(v) => out.put("decision", v)
            case None => ()
        }
        match (understanding.get("capability")) {
            case Some(v) => out.put("capability", v)
            case None => ()
        }
        match (understanding.get("ASRStatus")) {
            case Some(v) => out.put("ASRStatus", v)
            case None => ()
        }
        if (transcript.isEmpty()) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("unsupported"))
            if (out.get("ASRStatus").isNone()) {
                out.put("ASRStatus", JsonString("not_configured"))
            }
            let error = telegramMediaToolString(understanding, "error")
            out.put("error", JsonString(if (error.isEmpty()) { "native ASR runtime is not configured and no transcript companion file exists" } else { error }))
        } else {
            out.put("ok", JsonBool(true))
            out.put("status", JsonString("ok"))
            out.put("transcript", JsonString(transcript))
        }
        out.toJsonString()
    }

    private func describeTelegramVideo(mediaId: Option<String>, index: Option<Int64>): String {
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetIndex = match (index) {
            case Some(v) => v
            case None => 0
        }
        let out = JsonObject()
        let record = match (telegramMediaToolRecordByTarget(targetMediaId, targetIndex)) {
            case Some(v) => v
            case None =>
                out.put("ok", JsonBool(false))
                out.put("status", JsonString("error"))
                out.put("error", JsonString("media resource not found in current turn or recent same-peer Telegram media"))
                return out.toJsonString()
        }
        let kind = telegramMediaToolString(record, "mediaKind").toAsciiLower()
        let mime = telegramMediaToolString(record, "mimeType").toAsciiLower()
        if (!(kind == "video" || kind == "video-note" || kind == "video_note" || mime.startsWith("video/"))) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("unsupported"))
            out.put("error", JsonString("selected media is not video-like"))
            return out.toJsonString()
        }
        let understanding = gatewayMediaUnderstandingForRecord(record, capability: "video")
        let description = gatewayMediaUnderstandingFirstText(understanding)
        out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
        match (understanding.get("outputs")) {
            case Some(v) => out.put("outputs", v)
            case None => ()
        }
        match (understanding.get("decision")) {
            case Some(v) => out.put("decision", v)
            case None => ()
        }
        out.put("capability", JsonString("video"))
        if (description.isEmpty()) {
            out.put("ok", JsonBool(false))
            let status = telegramMediaToolString(understanding, "status")
            let normalizedStatus = if (status.isEmpty()) { "not_configured" } else { status }
            out.put("status", JsonString(normalizedStatus))
            out.put("videoUnderstandingStatus", JsonString(normalizedStatus))
            match (understanding.get("provider")) {
                case Some(v) => out.put("provider", v)
                case None => ()
            }
            match (understanding.get("providerKind")) {
                case Some(v) => out.put("providerKind", v)
                case None => ()
            }
            match (understanding.get("model")) {
                case Some(v) => out.put("model", v)
                case None => ()
            }
            match (understanding.get("fileBytes")) {
                case Some(v) => out.put("fileBytes", v)
                case None => ()
            }
            match (understanding.get("limitBytes")) {
                case Some(v) => out.put("limitBytes", v)
                case None => ()
            }
            match (understanding.get("timeoutMs")) {
                case Some(v) => out.put("timeoutMs", v)
                case None => ()
            }
            let error = telegramMediaToolString(understanding, "error")
            let readable = match (normalizedStatus) {
                case "not_configured" => "Video understanding is not configured. Configure gateway.media.video or gateway.telegram.video with a provider before asking Metis to describe videos."
                case "disabled" => "Video understanding is disabled in Gateway configuration."
                case "too_large" => "The selected video is too large for the configured video understanding limit."
                case "timeout" => "The configured video understanding provider timed out before returning a description."
                case "provider_error" => if (error.isEmpty()) { "The configured video understanding provider failed." } else { error }
                case _ => if (error.isEmpty()) { "Video understanding did not return a description." } else { error }
            }
            out.put("error", JsonString(readable))
        } else {
            out.put("ok", JsonBool(true))
            out.put("status", JsonString("ok"))
            out.put("description", JsonString(description))
            match (understanding.get("provider")) {
                case Some(v) => out.put("provider", v)
                case None => ()
            }
            match (understanding.get("model")) {
                case Some(v) => out.put("model", v)
                case None => ()
            }
        }
        out.toJsonString()
    }

    private func extractTelegramDocument(mediaId: Option<String>, index: Option<Int64>, maxBytes: Option<Int64>): String {
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetIndex = match (index) {
            case Some(v) => v
            case None => 0
        }
        let limit = match (maxBytes) {
            case Some(v) => if (v <= 0) { 8192 } else { v }
            case None => 8192
        }
        let out = JsonObject()
        let record = match (telegramMediaToolRecordByTarget(targetMediaId, targetIndex)) {
            case Some(v) => v
            case None =>
                out.put("ok", JsonBool(false))
                out.put("status", JsonString("error"))
                out.put("error", JsonString("media resource not found in current turn or recent same-peer Telegram media"))
                return out.toJsonString()
        }
        let kind = telegramMediaToolString(record, "mediaKind").toAsciiLower()
        if (kind != "document") {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("unsupported"))
            out.put("error", JsonString("selected media is not a document"))
            return out.toJsonString()
        }
        let understanding = gatewayMediaUnderstandingForRecord(record, capability: "document", maxBytes: limit)
        let preview = gatewayMediaUnderstandingFirstText(understanding)
        out.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
        out.put("capability", JsonString("document"))
        match (understanding.get("outputs")) {
            case Some(v) => out.put("outputs", v)
            case None => ()
        }
        match (understanding.get("decision")) {
            case Some(v) => out.put("decision", v)
            case None => ()
        }
        out.put("status", understanding.get("status") ?? JsonString("metadata_only"))
        out.put("ok", understanding.get("ok") ?? JsonBool(false))
        if (!preview.isEmpty()) {
            out.put("content", JsonString(preview))
            out.put("readable", JsonBool(true))
        } else {
            out.put("readable", JsonBool(false))
            out.put("reason", JsonString("document extractor is not configured or media is not text-like"))
        }
        out.toJsonString()
    }

    private func telegramStickerRecordMatchesQuery(record: JsonObject, query: String): Bool {
        let q = query.trimAscii().toAsciiLower()
        if (q.isEmpty()) {
            return true
        }
        let haystack = (
            telegramMediaToolString(record, "fileId") + " " +
            telegramMediaToolString(record, "fileUniqueId") + " " +
            telegramMediaToolString(record, "caption") + " " +
            telegramMediaToolString(record, "emoji") + " " +
            telegramMediaToolString(record, "stickerEmoji") + " " +
            telegramMediaToolString(record, "setName") + " " +
            telegramMediaToolString(record, "stickerSetName") + " " +
            telegramMediaToolString(record, "description") + " " +
            telegramMediaToolString(record, "analysis")
        ).toAsciiLower()
        haystack.contains(q)
    }

    private func searchTelegramStickers(query: String, limit: Option<Int64>): String {
        let max = match (limit) {
            case Some(v) => if (v <= 0) { 10 } else { v }
            case None => 10
        }
        let out = JsonObject()
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("ok"))
        out.put("action", JsonString("telegram_sticker_search"))
        out.put("source", JsonString("current_session_media_context+durable_cache"))
        let stickers = JsonArray([])
        var count: Int64 = 0
        let records = telegramStickerCachePersistCurrentRecords()
        for (item in records.getItems()) {
            if (count >= max) {
                break
            }
            let record = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            let kind = telegramMediaToolString(record, "mediaKind").toAsciiLower()
            if (kind != "sticker") {
                continue
            }
            if (!this.telegramStickerRecordMatchesQuery(record, query)) {
                continue
            }
            let row = JsonObject()
            row.put("mediaId", JsonString(telegramMediaToolString(record, "mediaId")))
            row.put("fileId", JsonString(telegramMediaToolString(record, "fileId")))
            row.put("fileUniqueId", JsonString(telegramMediaToolString(record, "fileUniqueId")))
            row.put("emoji", JsonString(telegramMediaToolString(record, "emoji")))
            row.put("setName", JsonString(telegramMediaToolString(record, "setName")))
            row.put("description", JsonString(telegramMediaToolString(record, "description")))
            stickers.add(row)
            count += 1
        }
        out.put("count", count.toJsonValue())
        out.put("stickers", stickers)
        out.toJsonString()
    }

    private func getTelegramSticker(mediaId: Option<String>, fileUniqueId: Option<String>, fileId: Option<String>): String {
        let targetMediaId = match (mediaId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetUniqueId = match (fileUniqueId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let targetFileId = match (fileId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (targetMediaId.isEmpty() && targetUniqueId.isEmpty() && targetFileId.isEmpty()) {
            return telegramMediaError("telegram_sticker_get", "mediaId, fileUniqueId, or fileId is required")
        }
        let records = telegramStickerCachePersistCurrentRecords()
        for (item in records.getItems()) {
            let record = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            if (telegramMediaToolString(record, "mediaKind").toAsciiLower() != "sticker") {
                continue
            }
            if (!targetMediaId.isEmpty() && telegramMediaToolString(record, "mediaId") != targetMediaId) {
                continue
            }
            if (!targetUniqueId.isEmpty() && telegramMediaToolString(record, "fileUniqueId") != targetUniqueId) {
                continue
            }
            if (!targetFileId.isEmpty() && telegramMediaToolString(record, "fileId") != targetFileId) {
                continue
            }
            let out = JsonObject()
            out.put("ok", JsonBool(true))
            out.put("status", JsonString("ok"))
            out.put("action", JsonString("telegram_sticker_get"))
            out.put("source", JsonString("current_session_media_context+durable_cache"))
            out.put("sticker", record)
            return out.toJsonString()
        }
        let out = JsonObject()
        out.put("ok", JsonBool(false))
        out.put("status", JsonString("error"))
        out.put("action", JsonString("telegram_sticker_get"))
        out.put("error", JsonString("sticker not found in current session context or durable cache"))
        if (!targetMediaId.isEmpty()) { out.put("mediaId", JsonString(targetMediaId)) }
        if (!targetUniqueId.isEmpty()) { out.put("fileUniqueId", JsonString(targetUniqueId)) }
        if (!targetFileId.isEmpty()) { out.put("fileId", JsonString(targetFileId)) }
        out.toJsonString()
    }

    private func telegramStickerCacheStats(): String {
        let out = JsonObject()
        let records = telegramStickerCachePersistCurrentRecords()
        var stickerCount: Int64 = 0
        var describedCount: Int64 = 0
        for (item in records.getItems()) {
            let record = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            if (telegramMediaToolString(record, "mediaKind").toAsciiLower() == "sticker") {
                stickerCount += 1
                if (!telegramMediaToolString(record, "description").isEmpty() || !telegramMediaToolString(record, "analysis").isEmpty()) {
                    describedCount += 1
                }
            }
        }
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("ok"))
        out.put("action", JsonString("telegram_sticker_cache_stats"))
        out.put("source", JsonString("current_session_media_context+durable_cache"))
        out.put("stickerCount", stickerCount.toJsonValue())
        out.put("describedCount", describedCount.toJsonValue())
        out.put("cachePath", JsonString(telegramStickerCachePath().toString()))
        out.toJsonString()
    }

    private func sendTelegramMedia(pathOrUrl: String, caption: Option<String>, kind: Option<String>, forceDocument: Option<Bool>): String {
        let media = pathOrUrl.trimAscii()
        if (media.isEmpty()) {
            return telegramMediaError("telegram_media_send", "pathOrUrl is required")
        }
        let (channel, target, sessionKey) = telegramMediaToolCurrentTarget()
        if (channel != "telegram" || target.isEmpty()) {
            return telegramMediaError("telegram_media_send", "telegram_media_send requires a current Telegram session delivery target")
        }
        let cap = match (caption) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let requestedKind = match (kind) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => "document"
        }
        let actualKind = match (forceDocument) {
            case Some(v) => if (v) { "document" } else { requestedKind }
            case None => requestedKind
        }
        let payload = JsonObject()
        payload.put("id", JsonString("telegram"))
        payload.put("channel", JsonString("telegram"))
        payload.put("peerId", JsonString(target))
        payload.put("to", JsonString(target))
        payload.put("text", JsonString(telegramMediaToolBuildMediaText(actualKind, media, cap)))
        payload.put("message", payload.get("text").getOrThrow())
        let sent = telegramMediaToolInvokeGatewayCall("channels.send", params: Some(payload))
        let result = JsonObject()
        result.put("ok", sent.get("ok") ?? JsonBool(false))
        result.put("status", JsonString(if (try { (sent.get("ok").getOrThrow().asBool().getValue()) } catch (_e: Exception) { false }) { "accepted" } else { "error" }))
        result.put("action", JsonString("telegram_media_send"))
        result.put("channel", JsonString("telegram"))
        result.put("to", JsonString(target))
        result.put("sessionKey", JsonString(sessionKey))
        result.put("kind", JsonString(actualKind))
        result.put("media", JsonString(media))
        result.put("gateway", sent)
        result.toJsonString()
    }

    private func telegramAction(
        action: String,
        target: Option<String>,
        message: Option<String>,
        messageId: Option<String>,
        emoji: Option<String>,
        pollOptions: Option<Array<String>>,
        stickerFileId: Option<String>,
        topicName: Option<String>
    ): String {
        let normalized = this.normalizeTelegramActionName(action)
        if (normalized.isEmpty()) {
            return telegramMediaError("telegram_action", "unsupported telegram action: ${action.trimAscii()}")
        }
        if (normalized == "searchSticker") {
            return this.searchTelegramStickers(message ?? "", None<Int64>)
        }
        let targetText = this.resolveTelegramActionTarget(target)
        if (targetText.isEmpty()) {
            return telegramMediaError("telegram_action", "telegram_action requires a target or current Telegram session")
        }
        let text = match (this.telegramActionPayloadText(normalized, message, emoji, pollOptions, stickerFileId, topicName)) {
            case Some(v) => v
            case None => return telegramMediaError("telegram_action", "telegram_action missing required parameters for ${normalized}")
        }
        let replyTo = messageId ?? ""
        if ((normalized == "react" || normalized == "deleteMessage" || normalized == "editMessage" || normalized == "editForumTopic") && replyTo.trimAscii().isEmpty()) {
            return telegramMediaError("telegram_action", "${normalized} requires messageId")
        }
        let payload = JsonObject()
        payload.put("id", JsonString("telegram"))
        payload.put("channel", JsonString("telegram"))
        payload.put("peerId", JsonString(targetText))
        payload.put("to", JsonString(targetText))
        payload.put("text", JsonString(text))
        payload.put("message", JsonString(text))
        if (!replyTo.trimAscii().isEmpty()) {
            payload.put("replyToMessageId", JsonString(replyTo.trimAscii()))
        }
        let sent = telegramMediaToolInvokeGatewayCall("channels.send", params: Some(payload))
        let ok = telegramMediaToolBool(sent, "ok")
        let out = JsonObject()
        out.put("ok", ok.toJsonValue())
        out.put("status", JsonString(if (ok) { "accepted" } else { "error" }))
        out.put("action", JsonString("telegram_action"))
        out.put("telegramAction", JsonString(normalized))
        out.put("target", JsonString(targetText))
        out.put("gateway", sent)
        if (!ok) {
            let reason = telegramMediaToolString(sent, "reason")
            if (!reason.isEmpty()) {
                out.put("reason", JsonString(reason))
                if (reason.toAsciiLower().contains("disabled")) {
                    out.put("errorCode", JsonString("action_disabled"))
                }
            }
        }
        out.toJsonString()
    }

    private func normalizeTelegramActionName(action: String): String {
        let normalized = action.trimAscii().toAsciiLower().replace("_", "-")
        if (normalized == "send" || normalized == "sendmessage" || normalized == "send-message") { return "sendMessage" }
        if (normalized == "react" || normalized == "reaction") { return "react" }
        if (normalized == "poll") { return "poll" }
        if (normalized == "delete" || normalized == "deletemessage" || normalized == "delete-message") { return "deleteMessage" }
        if (normalized == "edit" || normalized == "editmessage" || normalized == "edit-message") { return "editMessage" }
        if (normalized == "sendsticker" || normalized == "send-sticker" || normalized == "sticker") { return "sendSticker" }
        if (normalized == "searchsticker" || normalized == "search-sticker" || normalized == "sticker-search") { return "searchSticker" }
        if (normalized == "topic-create" || normalized == "createforumtopic" || normalized == "create-forum-topic") { return "createForumTopic" }
        if (normalized == "topic-edit" || normalized == "editforumtopic" || normalized == "edit-forum-topic") { return "editForumTopic" }
        ""
    }

    private func resolveTelegramActionTarget(target: Option<String>): String {
        let explicit = match (target) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (!explicit.isEmpty()) {
            return explicit
        }
        let current = telegramMediaToolCurrentTarget()
        if (current[0] == "telegram") { current[1] } else { "" }
    }

    private func telegramActionPayloadText(
        normalized: String,
        message: Option<String>,
        emoji: Option<String>,
        pollOptions: Option<Array<String>>,
        stickerFileId: Option<String>,
        topicName: Option<String>
    ): Option<String> {
        let msg = message ?? ""
        if (normalized == "sendMessage") {
            return if (msg.trimAscii().isEmpty()) { None<String> } else { Some(msg) }
        }
        if (normalized == "react") {
            let token = emoji ?? msg
            return if (token.trimAscii().isEmpty()) { None<String> } else { Some(renderGatewayReactionText(token)) }
        }
        if (normalized == "poll") {
            let opts = pollOptions ?? []
            if (msg.trimAscii().isEmpty() || opts.isEmpty()) {
                return None<String>
            }
            let parts = ArrayList<String>()
            parts.add(msg.trimAscii())
            for (opt in opts) {
                if (!opt.trimAscii().isEmpty()) {
                    parts.add(opt.trimAscii())
                }
            }
            if (parts.size < 3) {
                return None<String>
            }
            return Some(renderGatewayPollText(String.join(parts.toArray(), delimiter: "|")))
        }
        if (normalized == "deleteMessage") {
            return Some(renderGatewayDeleteText())
        }
        if (normalized == "editMessage") {
            return if (msg.trimAscii().isEmpty()) { None<String> } else { Some(renderGatewayEditText(msg)) }
        }
        if (normalized == "sendSticker") {
            let fileId = stickerFileId ?? msg
            return if (fileId.trimAscii().isEmpty()) { None<String> } else { Some(renderGatewayStickerText(fileId.trimAscii())) }
        }
        if (normalized == "createForumTopic") {
            let title = topicName ?? msg
            return if (title.trimAscii().isEmpty()) { None<String> } else { Some(renderGatewayTopicCreateText(title)) }
        }
        if (normalized == "editForumTopic") {
            let title = topicName ?? msg
            return if (title.trimAscii().isEmpty()) { None<String> } else { Some(renderGatewayTopicEditText(title)) }
        }
        None<String>
    }

    private func renderTelegramTargetListFromAudit(auditEnvelope: JsonObject): String {
        let rows = try {
            auditEnvelope.get("audit").getOrThrow().asObject().get("telegram").getOrThrow().asObject()
                .get("directory").getOrThrow().asObject().get("rows").getOrThrow().asArray()
        } catch (_e: Exception) {
            try {
                auditEnvelope.get("telegram").getOrThrow().asObject().get("directory").getOrThrow().asObject()
                    .get("rows").getOrThrow().asArray()
            } catch (_e2: Exception) {
                JsonArray([])
            }
        }
        let out = JsonObject()
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("ok"))
        out.put("count", rows.size().toJsonValue())
        out.put("targets", rows)
        out.toJsonString()
    }

    private func renderTelegramTargetResolveFromAudit(target: String, auditEnvelope: JsonObject): String {
        let normalizedTarget = target.trimAscii()
        let list = JsonValue.fromStr(this.renderTelegramTargetListFromAudit(auditEnvelope)).asObject()
        let rows = try { list.get("targets").getOrThrow().asArray() } catch (_e: Exception) { JsonArray([]) }
        let out = JsonObject()
        for (item in rows.getItems()) {
            let row = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            if (telegramMediaToolString(row, "id") == normalizedTarget ||
                telegramMediaToolString(row, "displayName") == normalizedTarget ||
                telegramMediaToolString(row, "sessionKey") == normalizedTarget) {
                out.put("ok", JsonBool(true))
                out.put("status", JsonString("ok"))
                out.put("target", row)
                return out.toJsonString()
            }
        }
        out.put("ok", JsonBool(false))
        out.put("status", JsonString("error"))
        out.put("target", JsonString(normalizedTarget))
        out.put("error", JsonString("Unknown or unauthorized Telegram target"))
        out.toJsonString()
    }

    private func renderTelegramDoctorFromEnvelope(doctorEnvelope: JsonObject): String {
        let telegram = try {
            doctorEnvelope.get("doctor").getOrThrow().asObject().get("telegramDiagnostics").getOrThrow().asObject()
        } catch (_e: Exception) {
            try { doctorEnvelope.get("telegramDiagnostics").getOrThrow().asObject() } catch (_e2: Exception) { JsonObject() }
        }
        let out = JsonObject()
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("ok"))
        out.put("telegramDiagnostics", telegram)
        let summary = telegram.get("summary") ?? JsonObject()
        out.put("summary", summary)
        out.toJsonString()
    }

    private func telegramTargetWritebackNormalize(target: String, resolvedChatId: Option<String>): (Bool, String, String) {
        let rawTarget = target.trimAscii()
        let rawResolved = match (resolvedChatId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (rawTarget.isEmpty() && rawResolved.isEmpty()) {
            return (false, "", "target or resolvedChatId is required")
        }
        let candidate = if (!rawResolved.isEmpty()) { rawResolved } else { rawTarget }
        let normalized = candidate.trimAscii()
        if (normalized.startsWith("user:") || normalized.startsWith("group:")) {
            return (true, normalized, "")
        }
        if (normalized.startsWith("-")) {
            return (true, "group:${normalized}", "")
        }
        if (normalized.startsWith("@")) {
            return (false, "", "target writeback for @username requires resolvedChatId from Telegram getChat")
        }
        var numeric = true
        for (r in normalized.runes()) {
            if (!(r >= r'0' && r <= r'9')) {
                numeric = false
                break
            }
        }
        if (numeric && !normalized.isEmpty()) {
            return (true, "user:${normalized}", "")
        }
        (false, "", "target cannot be normalized without resolvedChatId")
    }

    private func telegramTargetLookupFromRaw(raw: String): String {
        var value = raw.trimAscii()
        var linkLike = false
        if (value.startsWith("https://t.me/")) {
            value = value["https://t.me/".size..]
            linkLike = true
        } else if (value.startsWith("http://t.me/")) {
            value = value["http://t.me/".size..]
            linkLike = true
        } else if (value.startsWith("t.me/")) {
            value = value["t.me/".size..]
            linkLike = true
        } else if (value.startsWith("https://telegram.me/")) {
            value = value["https://telegram.me/".size..]
            linkLike = true
        } else if (value.startsWith("http://telegram.me/")) {
            value = value["http://telegram.me/".size..]
            linkLike = true
        } else if (value.startsWith("telegram.me/")) {
            value = value["telegram.me/".size..]
            linkLike = true
        }
        match (value.indexOf("?")) {
            case Some(idx) => value = value[..idx]
            case None => ()
        }
        match (value.indexOf("/")) {
            case Some(idx) => value = value[..idx]
            case None => ()
        }
        let candidate = value.trimAscii()
        if (candidate.startsWith("@")) {
            return candidate
        }
        if (!linkLike || candidate.isEmpty() || candidate == "c" || candidate.startsWith("+")) {
            return ""
        }
        "@" + candidate
    }

    private func telegramTargetResolveViaGetChat(target: String): (Bool, String, String, JsonObject) {
        let lookup = this.telegramTargetLookupFromRaw(target)
        let detail = JsonObject()
        detail.put("lookupTarget", JsonString(lookup))
        if (lookup.isEmpty()) {
            return (false, "", "target cannot be resolved with Telegram getChat", detail)
        }
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        params.put("chatId", JsonString(lookup))
        match (gatewayCurrentToolRuntimeContext()) {
            case Some(ctx) =>
                let accountId = telegramMediaToolString(ctx.mediaContext, "accountId")
                if (!accountId.trimAscii().isEmpty()) {
                    params.put("accountId", JsonString(accountId.trimAscii()))
                }
            case None => ()
        }
        let resolved = telegramMediaToolInvokeGatewayCall("channels.telegram.getChat", params: Some(params))
        detail.put("gateway", resolved)
        let ok = telegramMediaToolBool(resolved, "ok")
        let chatId = telegramMediaToolString(resolved, "chatId")
        if (ok && !chatId.isEmpty()) {
            return (true, chatId, "", detail)
        }
        let reason = telegramMediaToolString(resolved, "reason")
        return (false, "", if (reason.isEmpty()) { "Telegram getChat failed" } else { reason }, detail)
    }

    private func telegramTargetWritebackHasAdminScope(): Bool {
        match (gatewayCurrentToolRuntimeContext()) {
            case Some(ctx) =>
                for (scope in ctx.operatorScopes) {
                    let normalized = scope.trimAscii().toAsciiLower()
                    if (normalized == "operator.admin" || normalized == "gateway.admin" || normalized == "admin") {
                        return true
                    }
                }
                false
            case None => false
        }
    }

    private func telegramTargetConfigPathIsSafe(): Bool {
        let path = MetisConfigManager.configPath().toString()
        path.startsWith("/tmp/") || path.startsWith("/private/tmp/")
    }

    private func telegramTargetWritebackEnvelope(action: String, target: String, resolvedChatId: Option<String>, apply!: Bool): JsonObject {
        let out = JsonObject()
        var effectiveResolvedChatId = resolvedChatId
        let rawTarget = target.trimAscii()
        let lookup = this.telegramTargetLookupFromRaw(rawTarget)
        if (effectiveResolvedChatId.isNone() && !lookup.isEmpty()) {
            let (resolvedOk, chatId, resolvedError, detail) = this.telegramTargetResolveViaGetChat(rawTarget)
            out.put("resolve", detail)
            if (resolvedOk) {
                effectiveResolvedChatId = Some(chatId)
            } else {
                out.put("ok", false.toJsonValue())
                out.put("status", JsonString("error"))
                out.put("action", JsonString(action))
                out.put("target", JsonString(rawTarget))
                out.put("error", JsonString(resolvedError))
                out.put("cronTarget", JsonString("not_applicable"))
                return out
            }
        }
        let (ok, normalized, error) = this.telegramTargetWritebackNormalize(target, effectiveResolvedChatId)
        out.put("ok", ok.toJsonValue())
        out.put("status", JsonString(if (ok) { if (apply) { "applied" } else { "dry_run" } } else { "error" }))
        out.put("action", JsonString(action))
        out.put("target", JsonString(target.trimAscii()))
        match (effectiveResolvedChatId) {
            case Some(v) => out.put("resolvedChatId", JsonString(v.trimAscii()))
            case None => ()
        }
        out.put("cronTarget", JsonString("not_applicable"))
        if (!ok) {
            out.put("error", JsonString(error))
            return out
        }
        let proposed = JsonObject()
        proposed.put("path", JsonString("gateway.telegram.defaultTo"))
        proposed.put("value", JsonString(normalized))
        proposed.put("writeMode", JsonString("metis-config-manager"))
        out.put("proposed", proposed)
        out.put("defaultTo", JsonString(normalized))
        out
    }

    private func telegramTargetWritebackDryRun(target: String, resolvedChatId: Option<String>): String {
        this.telegramTargetWritebackEnvelope("telegram_target_writeback_dry_run", target, resolvedChatId, apply: false).toJsonString()
    }

    private func telegramTargetWritebackApply(target: String, resolvedChatId: Option<String>): String {
        if (!this.telegramTargetWritebackHasAdminScope()) {
            let denied = JsonObject()
            denied.put("ok", JsonBool(false))
            denied.put("status", JsonString("denied"))
            denied.put("action", JsonString("telegram_target_writeback_apply"))
            denied.put("target", JsonString(target.trimAscii()))
            denied.put("cronTarget", JsonString("not_applicable"))
            denied.put("error", JsonString("telegram target writeback requires operator.admin scope"))
            return denied.toJsonString()
        }
        let currentSettings = CliSettingManager.readGatewaySettings()
        if (!currentSettings.telegram.configWrites) {
            let denied = JsonObject()
            denied.put("ok", JsonBool(false))
            denied.put("status", JsonString("denied"))
            denied.put("action", JsonString("telegram_target_writeback_apply"))
            denied.put("target", JsonString(target.trimAscii()))
            denied.put("cronTarget", JsonString("not_applicable"))
            denied.put("error", JsonString("telegram target writeback requires gateway.telegram.configWrites=true"))
            return denied.toJsonString()
        }
        if (!this.telegramTargetConfigPathIsSafe()) {
            let denied = JsonObject()
            denied.put("ok", JsonBool(false))
            denied.put("status", JsonString("denied"))
            denied.put("action", JsonString("telegram_target_writeback_apply"))
            denied.put("target", JsonString(target.trimAscii()))
            denied.put("cronTarget", JsonString("not_applicable"))
            denied.put("configPath", JsonString(MetisConfigManager.configPath().toString()))
            denied.put("error", JsonString("telegram target writeback requires a temporary/explicit safe config path"))
            return denied.toJsonString()
        }
        let envelope = this.telegramTargetWritebackEnvelope("telegram_target_writeback_apply", target, resolvedChatId, apply: true)
        if (!(try { envelope.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false })) {
            return envelope.toJsonString()
        }
        var settings = currentSettings
        settings.telegram.defaultTo = telegramMediaToolString(envelope, "defaultTo")
        match (settings.telegram.accounts) {
            case Some(accounts) =>
                for (key in accounts.getFields().keys()) {
                    let account = try { accounts.get(key).getOrThrow().asObject() } catch (_e: Exception) { JsonObject() }
                    let accountDefault = telegramMediaToolString(account, "defaultTo")
                    if (accountDefault == target.trimAscii() || accountDefault == telegramMediaToolString(envelope, "target")) {
                        account.put("defaultTo", envelope.get("defaultTo").getOrThrow())
                        accounts.put(key, account)
                    }
                }
                settings.telegram.accounts = Some(accounts)
            case None => ()
        }
        MetisConfigManager.setGatewaySettings(settings)
        envelope.put("configPath", JsonString(MetisConfigManager.configPath().toString()))
        envelope.toJsonString()
    }

    private func telegramResolveSendTarget(target: String): JsonObject {
        let raw = target.trimAscii()
        let out = JsonObject()
        out.put("ok", JsonBool(false))
        out.put("target", JsonString(raw))
        if (raw.isEmpty()) {
            out.put("error", JsonString("target is required"))
            return out
        }
        let lookup = this.telegramTargetLookupFromRaw(raw)
        if (!lookup.isEmpty()) {
            let (resolvedOk, chatId, resolvedError, detail) = this.telegramTargetResolveViaGetChat(raw)
            out.put("resolve", detail)
            if (!resolvedOk) {
                out.put("error", JsonString(resolvedError))
                return out
            }
            let (normOk, normalized, normError) = this.telegramTargetWritebackNormalize(raw, Some(chatId))
            if (!normOk) {
                out.put("error", JsonString(normError))
                return out
            }
            out.put("ok", JsonBool(true))
            out.put("resolvedTarget", JsonString(normalized))
            out.put("source", JsonString("getChat"))
            out.put("resolvedChatId", JsonString(chatId))
            return out
        }
        let normalized = this.telegramTargetWritebackNormalize(raw, None<String>)
        if (normalized[0]) {
            out.put("ok", JsonBool(true))
            out.put("resolvedTarget", JsonString(normalized[1]))
            out.put("source", JsonString("literal"))
            return out
        }
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let audit = telegramMediaToolInvokeGatewayCall("channels.audit", params: Some(params))
        let resolved = JsonValue.fromStr(this.renderTelegramTargetResolveFromAudit(raw, audit)).asObject()
        if (telegramMediaToolBool(resolved, "ok")) {
            let row = try { resolved.get("target").getOrThrow().asObject() } catch (_e: Exception) { JsonObject() }
            let id = telegramMediaToolString(row, "id")
            if (!id.isEmpty() && telegramMediaToolBool(row, "canSend")) {
                out.put("ok", JsonBool(true))
                out.put("resolvedTarget", JsonString(id))
                out.put("source", JsonString(telegramMediaToolString(row, "source")))
                out.put("directoryTarget", row)
                return out
            }
        }
        out.put("error", JsonString("Unknown, unauthorized, or blocked Telegram target"))
        out
    }

    private func telegramSendToTargetResolved(target: String, message: String, writeback: Option<String>, dryRun: Option<Bool>): String {
        let targetText = target.trimAscii()
        let msg = message.trimAscii()
        if (targetText.isEmpty() || msg.isEmpty()) {
            return telegramMediaError("telegram_send_to_target", "target and message are required")
        }
        let resolved = this.telegramResolveSendTarget(targetText)
        if (!telegramMediaToolBool(resolved, "ok")) {
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("action", JsonString("telegram_send_to_target"))
            err.put("target", JsonString(targetText))
            err.put("resolve", resolved)
            err.put("error", JsonString(telegramMediaToolString(resolved, "error")))
            return err.toJsonString()
        }
        let resolvedTarget = telegramMediaToolString(resolved, "resolvedTarget")
        let payload = JsonObject()
        payload.put("id", JsonString("telegram"))
        payload.put("channel", JsonString("telegram"))
        payload.put("peerId", JsonString(resolvedTarget))
        payload.put("to", JsonString(resolvedTarget))
        payload.put("text", JsonString(msg))
        payload.put("message", JsonString(msg))
        let sent = telegramMediaToolInvokeGatewayCall("channels.send", params: Some(payload))
        let ok = try { sent.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false }
        let out = JsonObject()
        out.put("ok", ok.toJsonValue())
        out.put("status", JsonString(if (ok) { "accepted" } else { "error" }))
        out.put("action", JsonString("telegram_send_to_target"))
        out.put("target", JsonString(targetText))
        out.put("resolvedTarget", JsonString(resolvedTarget))
        out.put("resolve", resolved)
        out.put("gateway", sent)
        let writebackMode = match (writeback) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => ""
        }
        let dry = match (dryRun) { case Some(v) => v case None => false }
        if (dry || writebackMode == "dry-run" || writebackMode == "dry_run") {
            out.put("writeback", JsonValue.fromStr(this.telegramTargetWritebackDryRun(targetText, Some(this.telegramTargetChatIdForWriteback(resolvedTarget)))).asObject())
        } else if (writebackMode == "apply" || writebackMode == "true" || writebackMode == "on") {
            out.put("writeback", JsonValue.fromStr(this.telegramTargetWritebackApply(targetText, Some(this.telegramTargetChatIdForWriteback(resolvedTarget)))).asObject())
        }
        out.toJsonString()
    }

    private func telegramTargetChatIdForWriteback(resolvedTarget: String): String {
        let target = resolvedTarget.trimAscii()
        if (target.startsWith("user:")) {
            return target["user:".size..]
        }
        if (target.startsWith("group:")) {
            let group = target["group:".size..]
            match (group.indexOf(":topic:")) {
                case Some(idx) => group[..idx]
                case None => group
            }
        } else {
            target
        }
    }

    @tool[
        description: "List structured Telegram media resources attached to the current Gateway session turn. Use this before saving or inspecting an image, file, voice, audio, or reply target media sent by the user.",
        parameters: {}
    ]
    public func telegram_media_list(): String {
        PrintUtils.printTool("telegram_media_list", shortMessage: "current")
        let text = this.renderTelegramMediaList()
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Save one Telegram media resource from the current turn or recent same-peer Telegram media. If destination is omitted or an image placeholder, returns the existing Telegram media archive path. Relative destinations are resolved inside the Telegram media archive, not the workspace. Absolute destinations inside the Metis workspace or protected config paths are denied. Select by mediaId, Telegram fileId/fileUniqueId, or zero-based index; defaults to index 0.",
        parameters: {
            destination: "Optional destination path. Omit to keep and return the existing Telegram media archive path. Relative paths stay inside the Telegram media archive.",
            mediaId: "Optional mediaId returned by telegram_media_list, or a Telegram fileId/fileUniqueId.",
            index: "Optional zero-based media index. Defaults to 0 when mediaId is omitted."
        }
    ]
    public func telegram_media_save(destination: Option<String>, mediaId: Option<String>, index: Option<Int64>): String {
        PrintUtils.printTool("telegram_media_save", shortMessage: "current")
        let text = this.saveTelegramMedia(destination, mediaId, index)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Get one structured Telegram media resource from the current turn or recent same-peer Telegram media. Select by mediaId, Telegram fileId/fileUniqueId, messageId, relation, or zero-based index.",
        parameters: {
            mediaId: "Optional mediaId returned by telegram_media_list, or a Telegram fileId/fileUniqueId.",
            index: "Optional zero-based media index. Defaults to 0 when other selectors are omitted.",
            messageId: "Optional Telegram source message id.",
            relation: "Optional media relation, such as current or replyTarget."
        }
    ]
    public func telegram_media_get(mediaId: Option<String>, index: Option<Int64>, messageId: Option<String>, relation: Option<String>): String {
        PrintUtils.printTool("telegram_media_get", shortMessage: "current")
        let text = this.getTelegramMedia(mediaId, index, messageId, relation)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Read a text-like Telegram media file from the current turn or recent same-peer Telegram media. Binary files return a readable=false result with a clear reason.",
        parameters: {
            mediaId: "Optional mediaId returned by telegram_media_list, or a Telegram fileId/fileUniqueId.",
            index: "Optional zero-based media index. Defaults to 0 when mediaId is omitted.",
            maxBytes: "Optional maximum preview bytes/chars. Defaults to 8192."
        }
    ]
    public func telegram_media_read(mediaId: Option<String>, index: Option<Int64>, maxBytes: Option<Int64>): String {
        PrintUtils.printTool("telegram_media_read", shortMessage: "current")
        let text = this.readTelegramMedia(mediaId, index, maxBytes)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Analyze an image-like Telegram media resource from the current turn or recent same-peer Telegram media. Uses configured/mock vision sidecar when available; otherwise returns unsupported instead of guessing.",
        parameters: {
            mediaId: "Optional mediaId returned by telegram_media_list, or a Telegram fileId/fileUniqueId.",
            index: "Optional zero-based media index.",
            prompt: "Optional analysis prompt."
        }
    ]
    public func telegram_image_analyze(mediaId: Option<String>, index: Option<Int64>, prompt: Option<String>): String {
        PrintUtils.printTool("telegram_image_analyze", shortMessage: "current")
        let text = this.analyzeTelegramImage(mediaId, index, prompt)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Transcribe a voice/audio Telegram media resource from the current turn or recent same-peer Telegram media. Reads transcript sidecar when present; otherwise returns ASRStatus=not_configured.",
        parameters: {
            mediaId: "Optional mediaId returned by telegram_media_list, or a Telegram fileId/fileUniqueId.",
            index: "Optional zero-based media index."
        }
    ]
    public func telegram_audio_transcribe(mediaId: Option<String>, index: Option<Int64>): String {
        PrintUtils.printTool("telegram_audio_transcribe", shortMessage: "current")
        let text = this.transcribeTelegramAudio(mediaId, index)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Describe a Telegram video/video-note media resource from the current turn or recent same-peer Telegram media. Reads configured companion/runtime output when present; otherwise returns videoUnderstandingStatus=not_configured.",
        parameters: {
            mediaId: "Optional mediaId returned by telegram_media_list, or a Telegram fileId/fileUniqueId.",
            index: "Optional zero-based media index."
        }
    ]
    public func telegram_video_describe(mediaId: Option<String>, index: Option<Int64>): String {
        PrintUtils.printTool("telegram_video_describe", shortMessage: "current")
        let text = this.describeTelegramVideo(mediaId, index)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Extract text/preview from a Telegram document media resource from the current turn or recent same-peer Telegram media. Text-like files are read directly; extracted companion files are used when available; unsupported documents return metadata_only.",
        parameters: {
            mediaId: "Optional mediaId returned by telegram_media_list, or a Telegram fileId/fileUniqueId.",
            index: "Optional zero-based media index.",
            maxBytes: "Optional maximum preview bytes/chars. Defaults to 8192."
        }
    ]
    public func telegram_document_extract(mediaId: Option<String>, index: Option<Int64>, maxBytes: Option<Int64>): String {
        PrintUtils.printTool("telegram_document_extract", shortMessage: "current")
        let text = this.extractTelegramDocument(mediaId, index, maxBytes)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Search sticker media seen in the current Telegram session context by emoji, set name, file id, or cached description.",
        parameters: {
            query: "Sticker search query. Empty returns recent stickers from the current session context.",
            limit: "Optional maximum number of results. Defaults to 10."
        }
    ]
    public func telegram_sticker_search(query: String, limit: Option<Int64>): String {
        PrintUtils.printTool("telegram_sticker_search", shortMessage: query)
        let text = this.searchTelegramStickers(query, limit)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Get one sticker seen in the current Telegram session context by mediaId, fileUniqueId, or fileId.",
        parameters: {
            mediaId: "Optional mediaId returned by telegram_media_list or telegram_sticker_search.",
            fileUniqueId: "Optional Telegram sticker file_unique_id.",
            fileId: "Optional Telegram sticker file_id."
        }
    ]
    public func telegram_sticker_get(mediaId: Option<String>, fileUniqueId: Option<String>, fileId: Option<String>): String {
        PrintUtils.printTool("telegram_sticker_get", shortMessage: "current")
        let text = this.getTelegramSticker(mediaId, fileUniqueId, fileId)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Return sticker cache/search stats for the current Telegram session context.",
        parameters: {}
    ]
    public func telegram_sticker_cache_stats(): String {
        PrintUtils.printTool("telegram_sticker_cache_stats", shortMessage: "current")
        let text = this.telegramStickerCacheStats()
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Send a local file, Telegram file_id, or controlled URL as Telegram media to the current Telegram session through Gateway channels.send.",
        parameters: {
            pathOrUrl: "Local path, Telegram file_id, or controlled URL to send.",
            caption: "Optional caption.",
            kind: "Optional media kind: photo, document, audio, voice, video, or video-note.",
            forceDocument: "Optional. When true, send as document."
        }
    ]
    public func telegram_media_send(pathOrUrl: String, caption: Option<String>, kind: Option<String>, forceDocument: Option<Bool>): String {
        PrintUtils.printTool("telegram_media_send", shortMessage: "current")
        let text = this.sendTelegramMedia(pathOrUrl, caption, kind, forceDocument)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Run a Telegram channel action through Gateway channels.send. Supports sendMessage, react, poll, delete, edit, sendSticker, searchSticker, topic-create, and topic-edit.",
        parameters: {
            action: "Telegram action name or alias.",
            target: "Optional Telegram target. Defaults to the current Telegram session target.",
            message: "Message text, poll question, sticker query, or topic title depending on action.",
            messageId: "Target message id for react, delete, edit, and topic-edit.",
            emoji: "Reaction emoji for react.",
            pollOptions: "Poll option labels for poll.",
            stickerFileId: "Sticker file_id for sendSticker.",
            topicName: "Forum topic name for topic-create or topic-edit."
        }
    ]
    public func telegram_action(
        action: String,
        target: Option<String>,
        message: Option<String>,
        messageId: Option<String>,
        emoji: Option<String>,
        pollOptions: Option<Array<String>>,
        stickerFileId: Option<String>,
        topicName: Option<String>
    ): String {
        PrintUtils.printTool("telegram_action", shortMessage: action)
        let text = this.telegramAction(action, target, message, messageId, emoji, pollOptions, stickerFileId, topicName)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "List known Telegram targets from Gateway channels.audit. This is read-only and does not expand permissions.",
        parameters: {}
    ]
    public func telegram_target_list(): String {
        PrintUtils.printTool("telegram_target_list", shortMessage: "audit")
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let audit = telegramMediaToolInvokeGatewayCall("channels.audit", params: Some(params))
        let text = this.renderTelegramTargetListFromAudit(audit)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Resolve one known Telegram target from Gateway channels.audit. Unknown or unauthorized targets are rejected.",
        parameters: {
            target: "Target id, display name, or session key from telegram_target_list."
        }
    ]
    public func telegram_target_resolve(target: String): String {
        PrintUtils.printTool("telegram_target_resolve", shortMessage: target)
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let audit = telegramMediaToolInvokeGatewayCall("channels.audit", params: Some(params))
        let text = this.renderTelegramTargetResolveFromAudit(target, audit)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Preview a controlled Telegram target writeback for gateway.telegram.defaultTo. This is read-only and never changes metis.json.",
        parameters: {
            target: "Raw target, numeric chat id, user:<id>, group:<id>, or @username.",
            resolvedChatId: "Optional numeric chat id resolved by Telegram getChat for @username targets."
        }
    ]
    public func telegram_target_writeback_dry_run(target: String, resolvedChatId: Option<String>): String {
        PrintUtils.printTool("telegram_target_writeback_dry_run", shortMessage: target)
        let text = this.telegramTargetWritebackDryRun(target, resolvedChatId)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Apply a controlled Telegram target writeback to gateway.telegram.defaultTo through MetisConfigManager. Requires operator.admin scope.",
        parameters: {
            target: "Raw target, numeric chat id, user:<id>, group:<id>, or @username.",
            resolvedChatId: "Optional numeric chat id resolved by Telegram getChat for @username targets."
        }
    ]
    public func telegram_target_writeback_apply(target: String, resolvedChatId: Option<String>): String {
        PrintUtils.printTool("telegram_target_writeback_apply", shortMessage: target)
        let text = this.telegramTargetWritebackApply(target, resolvedChatId)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Send a text message to a Telegram target through Gateway channels.send. Supports known directory/display targets and @username getChat resolution; target writeback is optional and policy-gated.",
        parameters: {
            target: "Target id, display name, session key from telegram_target_list, numeric chat id, user:<id>, group:<id>, t.me link, or @username.",
            message: "Message text to send.",
            writeback: "Optional target writeback mode: off, dry-run, or apply. apply requires operator.admin, configWrites=true, and a safe config path.",
            dryRun: "Optional. When true, previews writeback only and never mutates config."
        }
    ]
    public func telegram_send_to_target(target: String, message: String, writeback: Option<String>, dryRun: Option<Bool>): String {
        PrintUtils.printTool("telegram_send_to_target", shortMessage: target)
        let text = this.telegramSendToTargetResolved(target, message, writeback, dryRun)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Read Telegram-specific Gateway doctor diagnostics. This is read-only and never changes metis.json.",
        parameters: {
            liveProbe: "Optional. When true, request Gateway doctor/runtime live probe where supported."
        }
    ]
    public func telegram_doctor(liveProbe: Option<Bool>): String {
        PrintUtils.printTool("telegram_doctor", shortMessage: "read-only")
        let doctor = telegramMediaToolInvokeGatewayCall("doctor")
        let text = this.renderTelegramDoctorFromEnvelope(doctor)
        PrintUtils.printToolResult(text)
        return text
    }

    @tool[
        description: "Explain effective Telegram configuration through Gateway channels.audit without exposing token or proxy credentials.",
        parameters: {}
    ]
    public func telegram_config_explain(): String {
        PrintUtils.printTool("telegram_config_explain", shortMessage: "audit")
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let audit = telegramMediaToolInvokeGatewayCall("channels.audit", params: Some(params))
        PrintUtils.printToolResult(audit.toJsonString())
        return audit.toJsonString()
    }

    @tool[
        description: "Audit Telegram targets, allowlist, pairing, and directory state through Gateway channels.audit. Read-only.",
        parameters: {}
    ]
    public func telegram_audit_targets(): String {
        PrintUtils.printTool("telegram_audit_targets", shortMessage: "audit")
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let audit = telegramMediaToolInvokeGatewayCall("channels.audit", params: Some(params))
        let text = this.renderTelegramTargetListFromAudit(audit)
        PrintUtils.printToolResult(text)
        return text
    }
}
