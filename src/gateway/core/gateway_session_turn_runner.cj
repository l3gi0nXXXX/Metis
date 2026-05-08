package metis.gateway.core

import metis.core.{GatewayToolRuntimeContext, gatewayMediaUnderstandingFirstText, gatewayMediaUnderstandingForRecord}
import metis.core.config.GatewayUserSettings
import metis.gateway.session.{GatewaySessionContext, GatewaySessionRequest, gatewayResolveSessionContext}
import std.collection.ArrayList
import std.fs.{Path, exists}
import stdx.encoding.json.{JsonArray, JsonObject}

private func gatewayJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayJsonBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayMediaRecords(mediaContext: JsonObject): JsonArray {
    match (mediaContext.get("records")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayMediaReadableTextMime(mime: String, fileName: String): Bool {
    let normalizedMime = mime.trimAscii().toAsciiLower()
    let normalizedName = fileName.trimAscii().toAsciiLower()
    if (normalizedMime.startsWith("text/") || normalizedMime == "application/json" || normalizedMime == "application/xml") {
        return true
    }
    normalizedName.endsWith(".txt") ||
        normalizedName.endsWith(".md") ||
        normalizedName.endsWith(".json") ||
        normalizedName.endsWith(".xml") ||
        normalizedName.endsWith(".csv") ||
        normalizedName.endsWith(".cj") ||
        normalizedName.endsWith(".ts") ||
        normalizedName.endsWith(".js") ||
        normalizedName.endsWith(".py")
}

private func gatewayMediaContextStructuredSummary(mediaContext: JsonObject): String {
    let ctx = match (mediaContext.get("context")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    if (ctx.size() == 0) {
        return ""
    }
    let lines = ArrayList<String>()
    match (ctx.get("replyTo")) {
        case Some(v) =>
            let obj = try { v.asObject() } catch (_e: Exception) { JsonObject() }
            lines.add("ReplyTo=${obj.toJsonString()}")
        case None => ()
    }
    match (ctx.get("forwarded")) {
        case Some(v) =>
            let obj = try { v.asObject() } catch (_e: Exception) { JsonObject() }
            lines.add("Forwarded=${obj.toJsonString()}")
        case None => ()
    }
    match (ctx.get("location")) {
        case Some(v) =>
            let obj = try { v.asObject() } catch (_e: Exception) { JsonObject() }
            lines.add("Location=${obj.toJsonString()}")
        case None => ()
    }
    match (ctx.get("venue")) {
        case Some(v) =>
            let obj = try { v.asObject() } catch (_e: Exception) { JsonObject() }
            lines.add("Venue=${obj.toJsonString()}")
        case None => ()
    }
    match (ctx.get("contact")) {
        case Some(v) =>
            let obj = try { v.asObject() } catch (_e: Exception) { JsonObject() }
            lines.add("Contact=${obj.toJsonString()}")
        case None => ()
    }
    match (ctx.get("telegramRoute")) {
        case Some(v) =>
            let obj = try { v.asObject() } catch (_e: Exception) { JsonObject() }
            lines.add("TelegramRoute=${obj.toJsonString()}")
        case None => ()
    }
    String.join(lines.toArray(), delimiter: "\n")
}

public func gatewayBuildMediaContextPrompt(mediaContext: JsonObject): String {
    let records = gatewayMediaRecords(mediaContext)
    let structuredSummary = gatewayMediaContextStructuredSummary(mediaContext)
    if (records.size() == 0 && structuredSummary.isEmpty()) {
        return ""
    }
    let lines = ArrayList<String>()
    let paths = ArrayList<String>()
    let types = ArrayList<String>()
    lines.add("## Current Message Media")
    lines.add("The current inbound message has structured media resources from the gateway. Use these local paths when the user asks to save, inspect, transcribe, or reason about the attached media. Do not parse media out of the visible chat text.")
    lines.add("For image/photo/sticker understanding requests, call telegram_image_analyze before answering. Do not claim that the image cannot be seen when downloaded=true and a MediaPath is present; if no vision model is configured, say that explicitly and keep the saved path available.")
    lines.add("For voice/audio requests, use AudioTranscript when present; otherwise call telegram_audio_transcribe before answering. If ASRStatus=not_configured, say that transcription is unavailable instead of guessing.")
    if (!structuredSummary.isEmpty()) {
        lines.add("StructuredTelegramContext:")
        lines.add(structuredSummary)
    }
    for (item in records.getItems()) {
        let record = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let mediaId = gatewayJsonString(record, "mediaId")
        let kind = gatewayJsonString(record, "mediaKind")
        let mime = gatewayJsonString(record, "mimeType")
        let localPath = gatewayJsonString(record, "localPath")
        let fileName = gatewayJsonString(record, "originalFileName")
        let relation = gatewayJsonString(record, "relation")
        let downloaded = gatewayJsonBool(record, "downloaded")
        let skipped = gatewayJsonString(record, "skippedReason")
        let understanding = if (downloaded && !localPath.isEmpty() && exists(Path(localPath))) {
            gatewayMediaUnderstandingForRecord(record)
        } else {
            JsonObject()
        }
        let understandingStatus = gatewayJsonString(understanding, "status")
        let understandingCapability = gatewayJsonString(understanding, "capability")
        let understandingText = gatewayMediaUnderstandingFirstText(understanding)
        let transcript = if (understandingCapability == "audio") { understandingText } else { "" }
        let imageDescription = if (understandingCapability == "image") { understandingText } else { "" }
        let stickerDescription = if (understandingCapability == "sticker") { understandingText } else { "" }
        let videoDescription = if (understandingCapability == "video") { understandingText } else { "" }
        let filePreview = if (understandingCapability == "document") { understandingText } else { "" }
        if (!localPath.isEmpty()) {
            paths.add(localPath)
        }
        if (!kind.isEmpty()) {
            types.add(kind)
        }
        let row = ArrayList<String>()
        if (!mediaId.isEmpty()) { row.add("mediaId=${mediaId}") }
        if (!kind.isEmpty()) { row.add("MediaType=${kind}") }
        if (!mime.isEmpty()) { row.add("mimeType=${mime}") }
        if (!fileName.isEmpty()) { row.add("fileName=${fileName}") }
        if (!relation.isEmpty()) { row.add("relation=${relation}") }
        if (!localPath.isEmpty()) { row.add("MediaPath=${localPath}") }
        row.add("downloaded=${downloaded}")
        if (!skipped.isEmpty()) { row.add("skippedReason=${skipped}") }
        if (!understandingStatus.isEmpty()) { row.add("MediaUnderstandingStatus=${understandingStatus}") }
        if (!understandingCapability.isEmpty()) { row.add("MediaUnderstandingCapability=${understandingCapability}") }
        if (!transcript.isEmpty()) {
            row.add("AudioTranscript=${transcript}")
        } else if ((kind == "voice" || kind == "audio") && downloaded) {
            row.add("ASRStatus=not_configured")
            row.add("ASRAction=use telegram_audio_transcribe")
        }
        if ((kind == "photo" || kind == "image" || kind == "sticker" || mime.startsWith("image/")) && downloaded) {
            row.add("visionInputReady=true")
            row.add("visionRuntimeAvailable=unknown")
            row.add("visionAction=use telegram_image_analyze")
            if (!imageDescription.isEmpty()) {
                row.add("ImageDescription=${imageDescription}")
            }
            if (!stickerDescription.isEmpty()) {
                row.add("StickerDescription=${stickerDescription}")
            }
        }
        if ((kind == "video" || kind == "video-note" || kind == "video_note" || mime.startsWith("video/")) && downloaded) {
            if (!videoDescription.isEmpty()) {
                row.add("VideoDescription=${videoDescription}")
            } else {
                row.add("VideoUnderstandingStatus=not_configured")
                row.add("VideoAction=use telegram_video_describe")
            }
        }
        if (!filePreview.isEmpty()) {
            row.add("FileContentPreview=${filePreview}")
        } else if (kind == "document" && downloaded) {
            row.add("DocumentExtractStatus=metadata_only")
            row.add("DocumentAction=use telegram_document_extract")
        }
        lines.add("- " + String.join(row.toArray(), delimiter: "; "))
    }
    if (paths.size > 0) {
        lines.add("MediaPaths=${String.join(paths.toArray(), delimiter: ", ")}")
    }
    if (types.size > 0) {
        lines.add("MediaTypes=${String.join(types.toArray(), delimiter: ", ")}")
    }
    String.join(lines.toArray(), delimiter: "\n")
}

public class GatewayResolvedSessionTurnResult {
    public let context: GatewaySessionContext
    public let execution: GatewaySessionExecutionResult

    public init(context: GatewaySessionContext, execution: GatewaySessionExecutionResult) {
        this.context = context
        this.execution = execution
    }
}

public func gatewayStreamingEnabledForUserChannel(user: GatewayUserSettings, channelName: String): Bool {
    let normalized = channelName.trimAscii().toAsciiLower()
    if (normalized == "telegram" || normalized == "feishu" || normalized == "qq") {
        let (mode, blocked) = if (normalized == "telegram") {
            (user.telegram.streaming.trimAscii().toAsciiLower(), user.telegram.blockStreaming)
        } else if (normalized == "feishu") {
            (user.feishu.streaming.trimAscii().toAsciiLower(), user.feishu.blockStreaming)
        } else {
            (user.qq.streaming.trimAscii().toAsciiLower(), user.qq.blockStreaming)
        }
        if (blocked) {
            return false
        }
        return !(mode.isEmpty() || mode == "off" || mode == "false" || mode == "disabled" || mode == "none")
    }
    return normalized == "control-ui" || normalized == "dashboard" || normalized == "cli"
}

public func gatewayBridgeForSessionRequest(user: GatewayUserSettings, request: GatewaySessionRequest): AgentBridge {
    let store = gatewaySessionStoreForResolvedRequest(user, request)
    AgentBridge(sessionStore: store)
}

public func gatewayExecuteSessionRequestTurn(
    bridge: AgentBridge,
    request: GatewaySessionRequest,
    prompt: String,
    deliver!: Bool = false,
    extraSystemPrompt!: String = "",
    timeoutSeconds!: Int64 = 0,
    bestEffortDeliver!: Bool = false,
    replyToMessageId!: Option<String> = None,
    replyInThread!: Bool = false,
    deliverHook!: Option<(String, String, String, String, Option<String>, Bool) -> String> = None<(String, String, String, String, Option<String>, Bool) -> String>,
    transcriptHook!: Option<(GatewaySessionContext, Int64, String, String) -> Unit> = None<(GatewaySessionContext, Int64, String, String) -> Unit>,
    streamHook!: Option<(GatewaySessionContext, String) -> Unit> = None<(GatewaySessionContext, String) -> Unit>,
    streamingEnabled!: Bool = false,
    lifecycleHook!: Option<(String) -> Unit> = None<(String) -> Unit>
): GatewayResolvedSessionTurnResult {
    let context = gatewayResolveSessionContext(request)
    let toolRuntimeContext = GatewayToolRuntimeContext(
        context.sourceLabel,
        channelName: context.channelName,
        sessionKey: context.sessionKey,
        senderId: request.senderId,
        declaredUser: request.declaredUser,
        operatorScopes: request.operatorScopes,
        prompt: prompt,
        mediaContext: request.mediaContext,
        lifecycleHook: lifecycleHook
    )
    let mediaPrompt = gatewayBuildMediaContextPrompt(request.mediaContext)
    let mergedExtraSystemPrompt = if (mediaPrompt.trimAscii().isEmpty()) {
        extraSystemPrompt
    } else if (extraSystemPrompt.trimAscii().isEmpty()) {
        mediaPrompt
    } else {
        extraSystemPrompt + "\n\n" + mediaPrompt
    }
    match (context.deliveryTarget) {
        case Some(target) =>
            // Persist the latest real delivery/binding target so later catalog views do not need to infer
            // conversation/thread/reply metadata from the session key alone.
            bridge.getSessionStore().appendBindingSnapshot(context.sessionKey, target)
        case None => ()
    }
    let execution = gatewayExecuteSessionTurn(
        bridge,
        context,
        prompt,
        deliver: deliver,
        extraSystemPrompt: mergedExtraSystemPrompt,
        timeoutSeconds: timeoutSeconds,
        toolRuntimeContext: Some(toolRuntimeContext),
        bestEffortDeliver: bestEffortDeliver,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        deliverHook: deliverHook,
        transcriptHook: transcriptHook,
        streamHook: streamHook,
        streamingEnabled: streamingEnabled,
        lifecycleHook: lifecycleHook
    )
    GatewayResolvedSessionTurnResult(context, execution)
}

public func gatewayExecuteSessionRequestTurnForUser(
    user: GatewayUserSettings,
    request: GatewaySessionRequest,
    prompt: String,
    deliver!: Bool = false,
    extraSystemPrompt!: String = "",
    timeoutSeconds!: Int64 = 0,
    bestEffortDeliver!: Bool = false,
    replyToMessageId!: Option<String> = None,
    replyInThread!: Bool = false,
    deliverHook!: Option<(String, String, String, String, Option<String>, Bool) -> String> = None<(String, String, String, String, Option<String>, Bool) -> String>,
    transcriptHook!: Option<(GatewaySessionContext, Int64, String, String) -> Unit> = None<(GatewaySessionContext, Int64, String, String) -> Unit>,
    streamHook!: Option<(GatewaySessionContext, String) -> Unit> = None<(GatewaySessionContext, String) -> Unit>,
    lifecycleHook!: Option<(String) -> Unit> = None<(String) -> Unit>
): GatewayResolvedSessionTurnResult {
    let bridge = gatewayBridgeForSessionRequest(user, request)
    let context = gatewayResolveSessionContext(request)
    gatewayExecuteSessionRequestTurn(
        bridge,
        request,
        prompt,
        deliver: deliver,
        extraSystemPrompt: extraSystemPrompt,
        timeoutSeconds: timeoutSeconds,
        bestEffortDeliver: bestEffortDeliver,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        deliverHook: deliverHook,
        transcriptHook: transcriptHook,
        streamHook: streamHook,
        streamingEnabled: gatewayStreamingEnabledForUserChannel(user, context.channelName),
        lifecycleHook: lifecycleHook
    )
}
