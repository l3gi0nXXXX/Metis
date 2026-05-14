package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.{GatewayToolRuntimeContext, gatewayCurrentToolRuntimeContext}
import metis.io.PrintUtils

import std.collection.ArrayList
import std.fs.{Directory, File, Path, exists}
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

public class GatewayFeishuHistoricalResourceResult {
    public let ok: Bool
    public let status: String
    public let bytes: Array<Byte>
    public let contentType: String
    public let fileName: String
    public let error: String

    public init(
        ok!: Bool = false,
        status!: String = "not_configured",
        bytes!: Array<Byte> = [],
        contentType!: String = "",
        fileName!: String = "",
        error!: String = ""
    ) {
        this.ok = ok
        this.status = if (status.trimAscii().isEmpty()) { if (ok) { "ok" } else { "error" } } else { status.trimAscii() }
        this.bytes = bytes
        this.contentType = contentType.trimAscii()
        this.fileName = fileName.trimAscii()
        this.error = error.trimAscii()
    }
}

private var gatewayFeishuHistoricalResourceRunnerForTest: Option<(JsonObject) -> GatewayFeishuHistoricalResourceResult> =
    None<(JsonObject) -> GatewayFeishuHistoricalResourceResult>

public func setGatewayFeishuHistoricalResourceRunnerForTest(runner: Option<(JsonObject) -> GatewayFeishuHistoricalResourceResult>): Unit {
    gatewayFeishuHistoricalResourceRunnerForTest = runner
}

private func feishuMediaToolString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func feishuMediaToolBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func feishuMediaToolInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { v.asInt().getValue() } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func feishuMediaToolCurrentContext(): Option<GatewayToolRuntimeContext> {
    match (gatewayCurrentToolRuntimeContext()) {
        case Some(ctx) =>
            let channel = if (!ctx.channelName.isEmpty()) { ctx.channelName } else { ctx.sourceLabel }
            let mediaChannel = feishuMediaToolString(ctx.mediaContext, "channel")
            if (channel == "feishu" || mediaChannel == "feishu") {
                return Some(ctx)
            }
            None<GatewayToolRuntimeContext>
        case None => None<GatewayToolRuntimeContext>
    }
}

private func feishuMediaToolRecords(): JsonArray {
    match (feishuMediaToolCurrentContext()) {
        case Some(ctx) =>
            match (ctx.mediaContext.get("records")) {
                case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
        case None => JsonArray([])
    }
}

private func feishuMediaToolRecordMatches(record: JsonObject, messageId: String, fileKey: String, resourceType: String): Bool {
    let requestedType = resourceType.trimAscii().toAsciiLower()
    if (!messageId.trimAscii().isEmpty() && feishuMediaToolString(record, "messageId") != messageId.trimAscii()) {
        return false
    }
    if (!fileKey.trimAscii().isEmpty()) {
        let keyMatches =
            feishuMediaToolString(record, "fileKey") == fileKey.trimAscii() ||
            feishuMediaToolString(record, "fileId") == fileKey.trimAscii() ||
            feishuMediaToolString(record, "mediaId") == fileKey.trimAscii()
        if (!keyMatches) {
            return false
        }
    }
    if (!requestedType.isEmpty()) {
        let recordType = feishuMediaToolString(record, "resourceType").toAsciiLower()
        let mediaKind = feishuMediaToolString(record, "mediaKind").toAsciiLower()
        if (!(recordType == requestedType || mediaKind == requestedType || (requestedType == "file" && mediaKind != "image"))) {
            return false
        }
    }
    true
}

private func feishuMediaToolFindRecord(messageId: String, fileKey: String, resourceType: String): Option<JsonObject> {
    let records = feishuMediaToolRecords()
    for (item in records.getItems()) {
        let record = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        if (feishuMediaToolRecordMatches(record, messageId, fileKey, resourceType)) {
            return Some(record)
        }
    }
    None<JsonObject>
}

private func feishuMediaToolError(status: String, messageId: String, fileKey: String, resourceType: String, reason!: String = ""): String {
    let out = JsonObject()
    out.put("ok", JsonBool(false))
    out.put("status", JsonString(status))
    out.put("message_id", JsonString(messageId.trimAscii()))
    out.put("file_key", JsonString(fileKey.trimAscii()))
    out.put("type", JsonString(resourceType.trimAscii()))
    if (!reason.trimAscii().isEmpty()) {
        out.put("reason", JsonString(reason.trimAscii()))
    }
    out.toJsonString()
}

private func feishuMediaToolFetchResource(messageId: String, fileKey: String, resourceType: String): String {
    if (messageId.trimAscii().isEmpty() || fileKey.trimAscii().isEmpty()) {
        return feishuMediaToolError("invalid_request", messageId, fileKey, resourceType, reason: "message_id and file_key are required")
    }
    match (feishuMediaToolFindRecord(messageId, fileKey, resourceType)) {
        case Some(record) =>
            let skippedReason = feishuMediaToolString(record, "skippedReason")
            if (!feishuMediaToolBool(record, "downloaded")) {
                return feishuMediaToolError(
                    if (skippedReason.isEmpty()) { "not_downloaded" } else { skippedReason },
                    messageId,
                    fileKey,
                    resourceType,
                    reason: skippedReason
                )
            }
            let out = JsonObject()
            out.put("ok", JsonBool(true))
            out.put("status", JsonString("ok"))
            out.put("message_id", JsonString(messageId.trimAscii()))
            out.put("file_key", JsonString(fileKey.trimAscii()))
            out.put("type", JsonString(resourceType.trimAscii()))
            out.put("saved_path", JsonString(feishuMediaToolString(record, "localPath")))
            out.put("content_type", JsonString(feishuMediaToolString(record, "mimeType")))
            out.put("size_bytes", JsonInt(feishuMediaToolInt(record, "fileSize")))
            out.put("file_name", JsonString(feishuMediaToolString(record, "fileName")))
            out.toJsonString()
        case None =>
            feishuMediaToolFetchHistoricalResource(messageId, fileKey, resourceType)
    }
}

private func feishuMediaToolFetchHistoricalResource(messageId: String, fileKey: String, resourceType: String): String {
    let ctx = match (feishuMediaToolCurrentContext()) {
        case Some(value) => value
        case None => return feishuMediaToolError("not_found", messageId, fileKey, resourceType, reason: "resource is not present in current Feishu media context")
    }
    let runner = match (gatewayFeishuHistoricalResourceRunnerForTest) {
        case Some(value) => value
        case None => return feishuMediaToolError("not_found", messageId, fileKey, resourceType, reason: "historical Feishu resource fetch is not configured")
    }
    let request = JsonObject()
    request.put("accountId", JsonString(feishuMediaToolAccountId(ctx)))
    request.put("messageId", JsonString(messageId.trimAscii()))
    request.put("fileKey", JsonString(fileKey.trimAscii()))
    request.put("type", JsonString(resourceType.trimAscii()))
    request.put("relation", JsonString("historical"))
    let result = runner(request)
    if (!result.ok) {
        return feishuMediaToolError(result.status, messageId, fileKey, resourceType, reason: result.error)
    }
    let policy = feishuMediaToolHistoricalPolicy(ctx.mediaContext)
    let sizeBytes = Int64(result.bytes.size)
    let maxBytes = feishuMediaToolPolicyMaxBytes(policy)
    if (maxBytes > 0 && sizeBytes > maxBytes) {
        return feishuMediaToolError("download_size_limit_exceeded", messageId, fileKey, resourceType, reason: "downloaded resource exceeds mediaMaxBytes")
    }
    if (!feishuMediaToolMimeAllowed(policy, result.contentType)) {
        return feishuMediaToolError("mime_not_allowed", messageId, fileKey, resourceType, reason: "downloaded resource MIME type is not allowed")
    }
    let savedPath = feishuMediaToolPersistHistoricalResource(policy, result, ctx, messageId, fileKey, resourceType)
    if (savedPath.trimAscii().isEmpty()) {
        return feishuMediaToolError("download_failed", messageId, fileKey, resourceType, reason: "failed to write resource to cache")
    }
    let out = JsonObject()
    out.put("ok", JsonBool(true))
    out.put("status", JsonString("ok"))
    out.put("relation", JsonString("historical"))
    out.put("message_id", JsonString(messageId.trimAscii()))
    out.put("file_key", JsonString(fileKey.trimAscii()))
    out.put("type", JsonString(resourceType.trimAscii()))
    out.put("saved_path", JsonString(savedPath))
    out.put("content_type", JsonString(result.contentType.trimAscii()))
    out.put("size_bytes", JsonInt(sizeBytes))
    out.put("file_name", JsonString(result.fileName.trimAscii()))
    out.toJsonString()
}

private func feishuMediaToolAccountId(ctx: GatewayToolRuntimeContext): String {
    let fromMedia = feishuMediaToolString(ctx.mediaContext, "accountId")
    if (!fromMedia.isEmpty()) {
        return fromMedia
    }
    "default"
}

private func feishuMediaToolHistoricalPolicy(mediaContext: JsonObject): JsonObject {
    let context = match (mediaContext.get("context")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    match (context.get("feishuHistoricalResource")) {
        case Some(v) => try { return v.asObject() } catch (_e: Exception) { () }
        case None => ()
    }
    match (mediaContext.get("feishuHistoricalResource")) {
        case Some(v) => try { return v.asObject() } catch (_e: Exception) { () }
        case None => ()
    }
    JsonObject()
}

private func feishuMediaToolPolicyMaxBytes(policy: JsonObject): Int64 {
    let configured = feishuMediaToolInt(policy, "mediaMaxBytes")
    if (configured > 0) { configured } else { 20 * 1024 * 1024 }
}

private func feishuMediaToolAllowedMimes(policy: JsonObject): Array<String> {
    let out = ArrayList<String>()
    match (policy.get("allowedMimes")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                for (i in 0..arr.size()) {
                    let value = try { arr[i].asString().getValue().trimAscii().toAsciiLower() } catch (_e: Exception) { "" }
                    if (!value.isEmpty()) {
                        out.add(value)
                    }
                }
            } catch (_e: Exception) { () }
        case None => ()
    }
    out.toArray()
}

private func feishuMediaToolMimeAllowed(policy: JsonObject, mimeType: String): Bool {
    let allowedMimes = feishuMediaToolAllowedMimes(policy)
    if (allowedMimes.isEmpty()) {
        return true
    }
    let mime = mimeType.trimAscii().toAsciiLower()
    for (allowed in allowedMimes) {
        if (allowed == "*" || allowed == mime) {
            return true
        }
        if (allowed.endsWith("/*")) {
            let prefix = allowed[0..allowed.size - 1]
            if (mime.startsWith(prefix)) {
                return true
            }
        }
    }
    false
}

private func feishuMediaToolPersistHistoricalResource(
    policy: JsonObject,
    result: GatewayFeishuHistoricalResourceResult,
    ctx: GatewayToolRuntimeContext,
    messageId: String,
    fileKey: String,
    resourceType: String
): String {
    let root = Path(if (!feishuMediaToolString(policy, "cacheRoot").isEmpty()) {
        feishuMediaToolString(policy, "cacheRoot")
    } else if (!feishuMediaToolString(policy, "downloadRoot").isEmpty()) {
        feishuMediaToolString(policy, "downloadRoot")
    } else {
        "/tmp/metis-feishu-media/historical"
    })
    let dir = root
        .join(feishuMediaToolSafeSegment(feishuMediaToolAccountId(ctx)))
        .join(feishuMediaToolSafeSegment(messageId))
    let safeName = feishuMediaToolSafeFileName(fileKey, resourceType: resourceType, fileName: result.fileName, mimeType: result.contentType)
    try {
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        let target = dir.join(safeName)
        File.writeTo(target, result.bytes)
        target.toString()
    } catch (_e: Exception) {
        ""
    }
}

private func feishuMediaToolSafeSegment(raw: String): String {
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
    var value = out.toString().trimAscii()
    while (value.contains("..")) {
        value = value.replace("..", "_")
    }
    while (value.startsWith(".")) {
        value = value[1..]
    }
    if (value.isEmpty()) { "default" } else { value }
}

private func feishuMediaToolSafeFileName(fileKey: String, resourceType!: String, fileName!: String, mimeType!: String): String {
    let candidate = if (!fileName.trimAscii().isEmpty()) {
        fileName.trimAscii()
    } else if (!fileKey.trimAscii().isEmpty()) {
        fileKey.trimAscii()
    } else {
        resourceType.trimAscii()
    }
    var safe = feishuMediaToolSafeSegment(candidate)
    if (!safe.contains(".")) {
        safe += feishuMediaToolExtensionFromMime(mimeType)
    }
    safe
}

private func feishuMediaToolExtensionFromMime(mimeType: String): String {
    let mime = mimeType.trimAscii().toAsciiLower()
    if (mime == "image/jpeg" || mime == "image/jpg") { return ".jpg" }
    if (mime == "image/png") { return ".png" }
    if (mime == "image/gif") { return ".gif" }
    if (mime == "image/webp") { return ".webp" }
    if (mime == "audio/ogg") { return ".ogg" }
    if (mime == "audio/mpeg") { return ".mp3" }
    if (mime == "video/mp4") { return ".mp4" }
    if (mime == "application/pdf") { return ".pdf" }
    if (mime.startsWith("text/")) { return ".txt" }
    ""
}

@toolset
public class GatewayFeishuMediaToolset {
    public init() {}

    public func debugFeishuMediaListForTest(): String {
        let records = feishuMediaToolRecords()
        let out = JsonObject()
        out.put("ok", JsonBool(true))
        out.put("count", JsonInt(records.size()))
        out.put("records", records)
        out.toJsonString()
    }

    public func debugFeishuFetchResourceForTest(messageId: String, fileKey: String, resourceType: Option<String>): String {
        feishuMediaToolFetchResource(messageId, fileKey, resourceType ?? "file")
    }

    @tool[
        description: "List Feishu media resources attached to the current turn. The list contains only metadata and local paths already staged by the Feishu channel runtime."
    ]
    public func feishu_media_list(): String {
        PrintUtils.printTool("feishu_media_list", shortMessage: "current")
        let records = feishuMediaToolRecords()
        let out = JsonObject()
        out.put("ok", JsonBool(true))
        out.put("count", JsonInt(records.size()))
        out.put("records", records)
        out.toJsonString()
    }

    @tool[
        description: "Fetch a Feishu IM message resource from the current turn context. Parameters are message_id, file_key, and type. Use type=image for image resources and type=file for file/audio/video resources. This returns the staged local file path when the Feishu channel already downloaded the resource; otherwise it returns a structured permission or download diagnostic."
    ]
    public func feishu_im_user_fetch_resource(message_id: String, file_key: String, `type`: Option<String>): String {
        PrintUtils.printTool("feishu_im_user_fetch_resource", shortMessage: "current")
        feishuMediaToolFetchResource(message_id, file_key, `type` ?? "file")
    }
}
