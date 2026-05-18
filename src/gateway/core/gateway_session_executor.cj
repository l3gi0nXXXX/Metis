package metis.gateway.core

import metis.core.{GatewayToolRuntimeContext, gatewaySpeechResolveDeliveryPrefs, gatewaySpeechResolveTtsConfig, gatewaySpeechTtsSynthesize, gatewayWithToolRuntimeContext}
import metis.core.renderGatewayEditText
import metis.core.config.{CliConfig, CliSettingManager}
import metis.gateway.session.GatewaySessionContext

import std.core.Duration
import std.fs.{Directory, File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

public class GatewaySessionExecutionResult {
    public let answer: String
    public let delivered: Bool
    public let deliveryStatus: String
    public let deliveryError: String
    public let deliveryMessageId: String

    public init(
        answer: String,
        delivered!: Bool = false,
        deliveryStatus!: String = "not-requested",
        deliveryError!: String = "",
        deliveryMessageId!: String = ""
    ) {
        this.answer = answer
        this.delivered = delivered
        this.deliveryStatus = deliveryStatus.trimAscii()
        this.deliveryError = deliveryError
        this.deliveryMessageId = deliveryMessageId.trimAscii()
    }
}

private class GatewayStreamingDeliveryState {
    public var messageId: String = ""
    public var lastText: String = ""
    public var failed: Bool = false
    public var lastSentAtMs: Int64 = 0
}

private func gatewayChannelSupportsMessageEdit(channelName: String): Bool {
    let normalized = channelName.trimAscii().toAsciiLower()
    normalized == "telegram" || normalized == "feishu"
}

private func gatewayStripTaggedReasoning(raw: String): String {
    var text = raw
    while (true) {
        let startOpt = text.indexOf("<think>")
        if (startOpt.isNone()) {
            break
        }
        let start = startOpt.getOrThrow()
        let afterStart = start + "<think>".size
        match (text[afterStart..].indexOf("</think>")) {
            case Some(endRel) =>
                let end = afterStart + endRel + "</think>".size
                text = text[..start] + text[end..]
            case None =>
                text = text[..start]
                break
        }
    }
    match (text.indexOf("<final>")) {
        case Some(start) =>
            let afterStart = start + "<final>".size
            match (text[afterStart..].indexOf("</final>")) {
                case Some(endRel) => return text[afterStart..afterStart + endRel].trimAscii()
                case None => return text[afterStart..].trimAscii()
            }
        case None => text.trimAscii()
    }
}

private func gatewayVisibleDeliveryText(channelName: String, raw: String): String {
    let visible = if (channelName.trimAscii().toAsciiLower() == "telegram") {
        gatewayStripTaggedReasoning(raw)
    } else {
        raw
    }
    gatewayStripInternalDeliveryDirectives(visible)
}

private func gatewayIsSilentReplyText(text: String): Bool {
    let normalized = text.trimAscii().toAsciiLower()
    normalized == "<silent_reply>" || normalized == "silent_reply"
}

private func gatewayIsInternalDeliveryDirective(tag: String): Bool {
    let normalized = tag.trimAscii().toAsciiLower().replace(" ", "")
    normalized == "reply_to_current" ||
        normalized.startsWith("reply_to:") ||
        normalized == "tts" ||
        normalized == "tts:text" ||
        normalized == "/tts" ||
        normalized == "/tts:text" ||
        normalized == "audio_as_voice"
}

private func gatewayStripInternalDeliveryDirectives(raw: String): String {
    var cursor: Int64 = 0
    let out = StringBuilder()
    while (cursor < raw.size) {
        match (raw.indexOf("[[", cursor)) {
            case Some(start) =>
                out.append(raw[cursor..start])
                match (raw.indexOf("]]", start + 2)) {
                    case Some(end) =>
                        let tag = raw[start + 2..end]
                        if (!gatewayIsInternalDeliveryDirective(tag)) {
                            out.append(raw[start..end + 2])
                        }
                        cursor = end + 2
                    case None =>
                        out.append(raw[start..])
                        cursor = raw.size
                }
            case None =>
                out.append(raw[cursor..])
                cursor = raw.size
        }
    }
    out.toString().trimAscii()
}

private func gatewaySessionJsonBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func gatewaySessionJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func gatewaySessionMediaRecords(mediaContext: JsonObject): JsonArray {
    match (mediaContext.get("records")) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayMediaFallbackImageLike(record: JsonObject, capability: String): Bool {
    let normalizedCapability = capability.trimAscii().toAsciiLower()
    if (normalizedCapability == "image" || normalizedCapability == "sticker") {
        return true
    }
    let kind = gatewaySessionJsonString(record, "mediaKind").toAsciiLower()
    let mime = gatewaySessionJsonString(record, "mimeType").toAsciiLower()
    kind == "photo" || kind == "image" || kind == "sticker" || mime.startsWith("image/")
}

private func gatewayMediaFallbackStatusMessage(status: String): String {
    match (status.trimAscii().toAsciiLower()) {
        case "not_configured" => "图片解析模型未配置。"
        case "unsupported" => "当前图片解析模型不支持图片输入。"
        case "provider_error" => "图片解析服务调用失败。"
        case "too_large" => "图片过大，无法解析。"
        case "timeout" => "图片解析服务超时。"
        case _ => ""
    }
}

private func gatewayMediaFallbackRedactAfterMarker(raw: String, marker: String): String {
    let lower = raw.toAsciiLower()
    match (lower.indexOf(marker)) {
        case Some(start) =>
            let keepEnd = start + marker.size
            raw[..keepEnd] + "[redacted]"
        case None => raw
    }
}

private func gatewayMediaFallbackRedactDetail(raw: String): String {
    var text = raw.trimAscii().replace("\r", " ").replace("\n", " ")
    text = gatewayMediaFallbackRedactAfterMarker(text, "bearer ")
    text = gatewayMediaFallbackRedactAfterMarker(text, "api_key=")
    text = gatewayMediaFallbackRedactAfterMarker(text, "api key=")
    text = gatewayMediaFallbackRedactAfterMarker(text, "token=")
    text = gatewayMediaFallbackRedactAfterMarker(text, "key=")
    text = text.replace("Authorization", "[redacted-header]").replace("authorization", "[redacted-header]")
    text = text.replace("DASHSCOPE_API_KEY", "API key")
    while (text.contains("  ")) {
        text = text.replace("  ", " ")
    }
    if (text.size > 180) {
        return text[..180].trimAscii()
    }
    text
}

private func gatewayMediaFailureFallbackText(toolRuntimeContext: Option<GatewayToolRuntimeContext>): String {
    let mediaContext = match (toolRuntimeContext) {
        case Some(ctx) => ctx.mediaContext
        case None => return ""
    }
    for (item in gatewaySessionMediaRecords(mediaContext).getItems()) {
        let record = try { item.asObject() } catch (_: Exception) { JsonObject() }
        let status = gatewaySessionJsonString(record, "mediaUnderstandingStatus").toAsciiLower()
        if (!(status == "provider_error" || status == "not_configured" || status == "unsupported" || status == "too_large" || status == "timeout")) {
            continue
        }
        if (!gatewayMediaFallbackImageLike(record, gatewaySessionJsonString(record, "mediaUnderstandingCapability"))) {
            continue
        }
        let base = gatewayMediaFallbackStatusMessage(status)
        if (base.isEmpty()) {
            continue
        }
        let detail = gatewayMediaFallbackRedactDetail(gatewaySessionJsonString(record, "mediaUnderstandingError"))
        if (status == "provider_error" && !detail.isEmpty()) {
            return "${base}诊断：${detail}"
        }
        return base
    }
    ""
}

private func gatewayShouldUseMediaFailureFallback(visibleText: String, toolRuntimeContext: Option<GatewayToolRuntimeContext>): Bool {
    match (toolRuntimeContext) {
        case Some(ctx) =>
            if (ctx.hasVisibleReplyDelivered()) {
                return false
            }
        case None => ()
    }
    let normalized = visibleText.trimAscii()
    normalized.isEmpty() || gatewayIsSilentReplyText(normalized)
}

private func gatewayTelegramTtsDir(): Path {
    let dir = CliConfig.dotDir.join("gateway-telegram").join("tts")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func gatewayTelegramReadTtsState(): JsonObject {
    let path = gatewayTelegramTtsDir().join("state.json")
    if (!exists(path)) {
        let out = JsonObject()
        out.put("enabled", JsonBool(true))
        out.put("provider", JsonString(""))
        out.put("limit", JsonInt(4000))
        return out
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
}

private func gatewayLooksLikeVoiceOrAudioInput(text: String): Bool {
    let normalized = text.trimAscii()
    normalized.startsWith("[voice]") ||
        normalized.startsWith("[audio]") ||
        normalized.contains("\nmediaKind=voice") ||
        normalized.contains("\nmediaKind=audio") ||
        normalized.contains("\nmimeType=audio/")
}

private func gatewayShouldAutoSynthesizeTelegramReply(
    channelName: String,
    prompt: String,
    toolRuntimeContext: Option<GatewayToolRuntimeContext>
): Bool {
    if (channelName.trimAscii().toAsciiLower() != "telegram") {
        return false
    }
    let runtimePrompt = match (toolRuntimeContext) {
        case Some(ctx) => ctx.prompt
        case None => ""
    }
    if (!(gatewayLooksLikeVoiceOrAudioInput(runtimePrompt) || gatewayLooksLikeVoiceOrAudioInput(prompt))) {
        return false
    }
    let user = CliSettingManager.readGatewaySettings()
    let prefs = gatewaySpeechResolveDeliveryPrefs(user, channel: "telegram")
    gatewaySessionJsonBool(prefs, "autoReplyToVoice", false) &&
        gatewaySessionJsonBool(prefs, "audioAsVoice", false)
}

private func gatewayMaybeSynthesizeTelegramFinalReply(
    channelName: String,
    prompt: String,
    text: String,
    toolRuntimeContext: Option<GatewayToolRuntimeContext>
): String {
    let speakable = text.trimAscii()
    if (speakable.isEmpty() ||
        speakable.startsWith("[voice]") ||
        speakable.startsWith("[audio]") ||
        gatewayIsSilentReplyText(speakable) ||
        !gatewayShouldAutoSynthesizeTelegramReply(channelName, prompt, toolRuntimeContext)) {
        return text
    }
    let user = CliSettingManager.readGatewaySettings()
    let result = gatewaySpeechTtsSynthesize(
        gatewaySpeechResolveTtsConfig(user, channel: "telegram"),
        gatewaySpeechResolveDeliveryPrefs(user, channel: "telegram"),
        gatewayTelegramReadTtsState(),
        speakable,
        outputRoot: gatewayTelegramTtsDir()
    )
    match (result.get("payload")) {
        case Some(v) =>
            try {
                let payload = v.asString().getValue().trimAscii()
                if (!payload.isEmpty()) {
                    return payload
                }
            } catch (_: Exception) {
                ()
            }
        case None => ()
    }
    text
}

private func gatewayExtractTaggedReasoning(raw: String): String {
    match (raw.indexOf("<think>")) {
        case Some(start) =>
            let afterStart = start + "<think>".size
            match (raw[afterStart..].indexOf("</think>")) {
                case Some(endRel) => raw[afterStart..afterStart + endRel].trimAscii()
                case None => raw[afterStart..].trimAscii()
            }
        case None => ""
    }
}

private func gatewayReasoningLaneEnabled(bridge: AgentBridge, context: GatewaySessionContext): Bool {
    if (context.channelName.trimAscii().toAsciiLower() != "telegram") {
        return false
    }
    let indexRoot = bridge.getSessionStore().readSessionsIndexRoot()
    let entry = match (indexRoot.get(context.sessionKey)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let mode = GatewaySessionStore.sessionIndexString(entry, "reasoningVisibility").toAsciiLower()
    mode == "on" || mode == "stream" || mode == "true" || mode == "visible"
}

public func gatewayDebugTelegramStreamingLanesForTest(raw: String, reasoningEnabled!: Bool = false): JsonObject {
    let out = JsonObject()
    out.put("answer", JsonString(gatewayVisibleDeliveryText("telegram", raw)))
    out.put("reasoning", JsonString(if (reasoningEnabled) { gatewayExtractTaggedReasoning(raw) } else { "" }))
    out
}

private func gatewayNotifySessionLifecycle(
    lifecycleHook: Option<(String) -> Unit>,
    status: String
): Unit {
    let normalized = status.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) {
        return
    }
    match (lifecycleHook) {
        case Some(hook) =>
            try {
                hook(normalized)
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
}

private func gatewayReplyWithTimeout(
    bridge: AgentBridge,
    context: GatewaySessionContext,
    prompt: String,
    extraSystemPrompt: String,
    timeoutSeconds: Int64,
    toolRuntimeContext!: Option<GatewayToolRuntimeContext> = None<GatewayToolRuntimeContext>,
    streamingEnabled!: Bool = false,
    streamChunkHook!: Option<(String) -> Unit> = None<(String) -> Unit>
): String {
    if (timeoutSeconds <= 0) {
        return match (toolRuntimeContext) {
            case Some(runtimeContext) =>
                gatewayWithToolRuntimeContext(runtimeContext, { =>
                    bridge.reply(
                        context.sessionKey,
                        prompt,
                        channelName: context.channelName,
                        agentId: context.agentId,
                        extraSystemPrompt: extraSystemPrompt,
                        streamingEnabled: streamingEnabled,
                        streamChunkHook: streamChunkHook,
                        turnContext: Some(context.turnContext)
                    )
                })
            case None =>
                bridge.reply(
                    context.sessionKey,
                    prompt,
                    channelName: context.channelName,
                    agentId: context.agentId,
                    extraSystemPrompt: extraSystemPrompt,
                    streamingEnabled: streamingEnabled,
                    streamChunkHook: streamChunkHook,
                    turnContext: Some(context.turnContext)
                )
        }
    }
    let timeoutMs = timeoutSeconds * 1000
    let fut = spawn {
        match (toolRuntimeContext) {
            case Some(runtimeContext) =>
                gatewayWithToolRuntimeContext(runtimeContext, { =>
                    bridge.reply(
                        context.sessionKey,
                        prompt,
                        channelName: context.channelName,
                        agentId: context.agentId,
                        extraSystemPrompt: extraSystemPrompt,
                        streamingEnabled: streamingEnabled,
                        streamChunkHook: streamChunkHook,
                        turnContext: Some(context.turnContext)
                    )
                })
            case None =>
                bridge.reply(
                    context.sessionKey,
                    prompt,
                    channelName: context.channelName,
                    agentId: context.agentId,
                    extraSystemPrompt: extraSystemPrompt,
                    streamingEnabled: streamingEnabled,
                    streamChunkHook: streamChunkHook,
                    turnContext: Some(context.turnContext)
                )
        }
    }
    let watchdog = spawn {
        sleep(Duration.millisecond * timeoutMs)
        fut.cancel()
    }
    try {
        let out = fut.get()
        watchdog.cancel()
        return out
    } catch (e: Exception) {
        try {
            watchdog.cancel()
        } catch (_: Exception) {
            ()
        }
        throw e
    }
}

public func gatewayExecuteSessionTurn(
    bridge: AgentBridge,
    context: GatewaySessionContext,
    prompt: String,
    deliver!: Bool = false,
    extraSystemPrompt!: String = "",
    timeoutSeconds!: Int64 = 0,
    toolRuntimeContext!: Option<GatewayToolRuntimeContext> = None<GatewayToolRuntimeContext>,
    bestEffortDeliver!: Bool = false,
    replyToMessageId!: Option<String> = None,
    replyInThread!: Bool = false,
    deliverHook!: Option<(String, String, String, String, Option<String>, Bool) -> String> = None<(String, String, String, String, Option<String>, Bool) -> String>,
    transcriptHook!: Option<(GatewaySessionContext, Int64, String, String) -> Unit> = None<(GatewaySessionContext, Int64, String, String) -> Unit>,
    streamHook!: Option<(GatewaySessionContext, String) -> Unit> = None<(GatewaySessionContext, String) -> Unit>,
    streamingEnabled!: Bool = false,
    lifecycleHook!: Option<(String) -> Unit> = None<(String) -> Unit>
): GatewaySessionExecutionResult {
    let effectiveReplyToMessageId = match (context.deliveryTarget) {
        case Some(target) =>
            match (replyToMessageId) {
                case Some(existing) => Some(existing)
                case None =>
                    if (!target.replyToMessageId.isEmpty()) {
                        Some(target.replyToMessageId)
                    } else {
                        None<String>
                    }
            }
        case None => replyToMessageId
    }
    let effectiveReplyInThread = match (context.deliveryTarget) {
        case Some(target) => replyInThread || target.replyInThread
        case None => replyInThread
    }
    let canStreamToPeer = deliver &&
        streamingEnabled &&
        (
            context.channelName == "telegram" ||
            context.channelName == "feishu" ||
            context.channelName == "qq"
        ) &&
        context.deliveryTarget.isSome() &&
        deliverHook.isSome()
    let useEditMessages = gatewayChannelSupportsMessageEdit(context.channelName)
    let streamingState = GatewayStreamingDeliveryState()
    let reasoningStreamingState = GatewayStreamingDeliveryState()
    let reasoningLaneEnabled = gatewayReasoningLaneEnabled(bridge, context)
    gatewayNotifySessionLifecycle(lifecycleHook, "thinking")
    var answer = ""
    try {
        answer = gatewayReplyWithTimeout(
            bridge,
            context,
            prompt,
            extraSystemPrompt,
            timeoutSeconds,
            toolRuntimeContext: toolRuntimeContext,
            streamingEnabled: streamingEnabled,
            streamChunkHook: Some({ currentText =>
            let visibleText = gatewayVisibleDeliveryText(context.channelName, currentText)
            let normalized = visibleText.trimAscii()
            match (streamHook) {
                case Some(notify) => notify(context, currentText)
                case None => ()
            }
            let reasoningText = if (reasoningLaneEnabled) { gatewayExtractTaggedReasoning(currentText) } else { "" }
            if (!reasoningText.trimAscii().isEmpty() && canStreamToPeer && !reasoningStreamingState.failed && reasoningText.trimAscii() != reasoningStreamingState.lastText.trimAscii()) {
                let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
                let shouldSendReasoningNow = reasoningStreamingState.messageId.isEmpty() ||
                    nowMs - reasoningStreamingState.lastSentAtMs >= 500 ||
                    reasoningText.size - reasoningStreamingState.lastText.size >= 96
                if (shouldSendReasoningNow) {
                    match (deliverHook) {
                        case Some(send) =>
                            try {
                                let laneText = "Reasoning\n${reasoningText}"
                                if (reasoningStreamingState.messageId.isEmpty()) {
                                    reasoningStreamingState.messageId = send(
                                        context.deliveryTarget.getOrThrow().channelName,
                                        context.deliveryTarget.getOrThrow().accountId,
                                        context.deliveryTarget.getOrThrow().peerId,
                                        laneText,
                                        effectiveReplyToMessageId,
                                        effectiveReplyInThread
                                    )
                                    if (reasoningStreamingState.messageId.trimAscii().isEmpty()) {
                                        reasoningStreamingState.failed = true
                                    }
                                } else {
                                    let _ = send(
                                        context.deliveryTarget.getOrThrow().channelName,
                                        context.deliveryTarget.getOrThrow().accountId,
                                        context.deliveryTarget.getOrThrow().peerId,
                                        if (useEditMessages) { renderGatewayEditText(laneText) } else { laneText },
                                        Some(reasoningStreamingState.messageId),
                                        false
                                    )
                                }
                                reasoningStreamingState.lastSentAtMs = nowMs
                                reasoningStreamingState.lastText = reasoningText
                            } catch (_ex: Exception) {
                                reasoningStreamingState.failed = true
                            }
                        case None => ()
                    }
                }
            }
            if (normalized.isEmpty()) {
                return
            }
            if (!canStreamToPeer || streamingState.failed || normalized == streamingState.lastText.trimAscii()) {
                return
            }
            let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
            let shouldSendNow = streamingState.messageId.isEmpty() ||
                nowMs - streamingState.lastSentAtMs >= 500 ||
                currentText.size - streamingState.lastText.size >= 96
            if (!shouldSendNow) {
                return
            }
            match (deliverHook) {
                case Some(send) =>
                    try {
                        if (streamingState.messageId.isEmpty()) {
                            streamingState.messageId = send(
                                context.deliveryTarget.getOrThrow().channelName,
                                context.deliveryTarget.getOrThrow().accountId,
                                context.deliveryTarget.getOrThrow().peerId,
                                visibleText,
                                effectiveReplyToMessageId,
                                effectiveReplyInThread
                            )
                            if (streamingState.messageId.trimAscii().isEmpty()) {
                                streamingState.failed = true
                                gatewayLogEventWarn(
                                    "gateway/session",
                                    "message.send.failed",
                                    "streaming delivery fallback",
                                    meta: gatewayLogMeta()
                                        .string("channel", context.channelName)
                                        .identityHash("sessionHash", context.sessionKey)
                                        .string("reason", "missing-message-id")
                                        .object()
                                )
                                return
                            }
                            gatewayLogEventInfo(
                                "gateway/session",
                                "message.outbound",
                                "streaming delivery started",
                                meta: gatewayLogMeta()
                                    .string("channel", context.channelName)
                                    .identityHash("sessionHash", context.sessionKey)
                                    .identityHash("messageHash", streamingState.messageId)
                                    .object()
                            )
                        } else {
                            let _ = send(
                                context.deliveryTarget.getOrThrow().channelName,
                                context.deliveryTarget.getOrThrow().accountId,
                                context.deliveryTarget.getOrThrow().peerId,
                                if (useEditMessages) { renderGatewayEditText(visibleText) } else { visibleText },
                                Some(streamingState.messageId),
                                false
                            )
                        }
                        streamingState.lastSentAtMs = nowMs
                        streamingState.lastText = visibleText
                    } catch (ex: Exception) {
                        streamingState.failed = true
                        gatewayLogEventWarn(
                            "gateway/session",
                            "message.send.failed",
                            "streaming delivery fallback",
                            meta: gatewayLogMeta()
                                .string("channel", context.channelName)
                                .identityHash("sessionHash", context.sessionKey)
                                .rawString("reason", ex.message)
                                .object()
                        )
                    }
                case None => ()
            }
            })
        )
    } catch (ex: Exception) {
        let fallbackText = gatewayMediaFailureFallbackText(toolRuntimeContext)
        if (deliver && !fallbackText.isEmpty()) {
            match (context.deliveryTarget) {
                case Some(target) =>
                    match (deliverHook) {
                        case Some(send) =>
                            try {
                                let sentMessageId = send(target.channelName, target.accountId, target.peerId, fallbackText, effectiveReplyToMessageId, effectiveReplyInThread)
                                gatewayNotifySessionLifecycle(lifecycleHook, "done")
                                return GatewaySessionExecutionResult(
                                    fallbackText,
                                    delivered: true,
                                    deliveryStatus: "delivered-fallback",
                                    deliveryMessageId: sentMessageId
                                )
                            } catch (_sendEx: Exception) {
                                ()
                            }
                        case None => ()
                    }
                case None => ()
            }
        }
        gatewayNotifySessionLifecycle(lifecycleHook, "error")
        throw ex
    }
    match (transcriptHook) {
        case Some(notify) => notify(context, 2, "turn", "assistant")
        case None => ()
    }
    if (!deliver) {
        return GatewaySessionExecutionResult(answer)
    }
    match (context.deliveryTarget) {
        case Some(target) =>
            match (deliverHook) {
                case Some(send) =>
                    try {
                        let visibleAnswer = gatewayMaybeSynthesizeTelegramFinalReply(
                            context.channelName,
                            prompt,
                            gatewayVisibleDeliveryText(context.channelName, answer),
                            toolRuntimeContext
                        )
                        let fallbackText = gatewayMediaFailureFallbackText(toolRuntimeContext)
                        let deliveryText = if (!fallbackText.isEmpty() && gatewayShouldUseMediaFailureFallback(visibleAnswer, toolRuntimeContext)) {
                            fallbackText
                        } else {
                            visibleAnswer
                        }
                        match (toolRuntimeContext) {
                            case Some(runtimeContext) =>
                                if (runtimeContext.hasVisibleReplyDelivered() && gatewayIsSilentReplyText(visibleAnswer)) {
                                    gatewayNotifySessionLifecycle(lifecycleHook, "done")
                                    return GatewaySessionExecutionResult(
                                        answer,
                                        delivered: true,
                                        deliveryStatus: "delivered-by-tool"
                                    )
                                }
                            case None => ()
                        }
                        if (!streamingState.messageId.isEmpty() && !streamingState.failed) {
                            if (deliveryText != streamingState.lastText) {
                                let finalEditMessageId = send(
                                    target.channelName,
                                    target.accountId,
                                    target.peerId,
                                    if (useEditMessages) { renderGatewayEditText(deliveryText) } else { deliveryText },
                                    Some(streamingState.messageId),
                                    false
                                )
                                if (finalEditMessageId.trimAscii().isEmpty()) {
                                    gatewayLogEventWarn(
                                        "gateway/session",
                                        "message.send.failed",
                                        "streaming final edit fallback",
                                        meta: gatewayLogMeta()
                                            .string("channel", context.channelName)
                                            .identityHash("sessionHash", context.sessionKey)
                                            .identityHash("messageHash", streamingState.messageId)
                                            .object()
                                    )
                                    let fallbackMessageId = send(target.channelName, target.accountId, target.peerId, deliveryText, effectiveReplyToMessageId, effectiveReplyInThread)
                                    gatewayNotifySessionLifecycle(lifecycleHook, "done")
                                    return GatewaySessionExecutionResult(
                                        answer,
                                        delivered: true,
                                        deliveryStatus: "delivered",
                                        deliveryMessageId: fallbackMessageId
                                    )
                                }
                            }
                            gatewayLogEventInfo(
                                "gateway/session",
                                "message.sent",
                                "streaming delivery finished",
                                meta: gatewayLogMeta()
                                    .string("channel", context.channelName)
                                    .identityHash("sessionHash", context.sessionKey)
                                    .identityHash("messageHash", streamingState.messageId)
                                    .object()
                            )
                            gatewayNotifySessionLifecycle(lifecycleHook, "done")
                            return GatewaySessionExecutionResult(
                                answer,
                                delivered: true,
                                deliveryStatus: "delivered",
                                deliveryMessageId: streamingState.messageId
                            )
                        }
                        let sentMessageId = send(target.channelName, target.accountId, target.peerId, deliveryText, effectiveReplyToMessageId, effectiveReplyInThread)
                        gatewayNotifySessionLifecycle(lifecycleHook, "done")
                        return GatewaySessionExecutionResult(
                            answer,
                            delivered: true,
                            deliveryStatus: "delivered",
                            deliveryMessageId: sentMessageId
                        )
                    } catch (ex: Exception) {
                        gatewayNotifySessionLifecycle(lifecycleHook, "error")
                        if (bestEffortDeliver) {
                            return GatewaySessionExecutionResult(
                                answer,
                                delivered: false,
                                deliveryStatus: "best-effort-failed",
                                deliveryError: ex.message
                            )
                        }
                        throw ex
                    }
                case None =>
                    if (bestEffortDeliver) {
                        return GatewaySessionExecutionResult(
                            answer,
                            delivered: false,
                            deliveryStatus: "best-effort-delivery-hook-missing",
                            deliveryError: "delivery hook is unavailable"
                        )
                    }
                    throw Exception("delivery hook is unavailable")
            }
        case None =>
            if (bestEffortDeliver) {
                return GatewaySessionExecutionResult(
                    answer,
                    delivered: false,
                    deliveryStatus: "best-effort-missing-target",
                    deliveryError: "reply target could not be resolved"
                )
            }
            throw Exception("reply target could not be resolved")
    }
}
