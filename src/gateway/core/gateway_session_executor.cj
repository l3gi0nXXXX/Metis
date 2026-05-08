package metis.gateway.core

import metis.core.{GatewayToolRuntimeContext, gatewayWithToolRuntimeContext}
import metis.core.renderGatewayEditText
import metis.gateway.session.GatewaySessionContext

import magic.log.LogUtils
import std.core.Duration
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonString}

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
    channelName.trimAscii().toAsciiLower() == "telegram"
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
    if (channelName.trimAscii().toAsciiLower() == "telegram") {
        return gatewayStripTaggedReasoning(raw)
    }
    raw
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
                        streamChunkHook: streamChunkHook
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
                    streamChunkHook: streamChunkHook
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
                        streamChunkHook: streamChunkHook
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
                    streamChunkHook: streamChunkHook
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
                                LogUtils.info("Gateway streaming fallback: channel=${context.channelName}, reason=missing-message-id")
                                return
                            }
                            LogUtils.info("Gateway streaming start: channel=${context.channelName}, session=${context.sessionKey}, messageId=${streamingState.messageId}")
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
                        LogUtils.info("Gateway streaming fallback: channel=${context.channelName}, reason=${ex.message}")
                    }
                case None => ()
            }
            })
        )
    } catch (ex: Exception) {
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
                        let visibleAnswer = gatewayVisibleDeliveryText(context.channelName, answer)
                        if (!streamingState.messageId.isEmpty() && !streamingState.failed) {
                            if (visibleAnswer != streamingState.lastText) {
                                let finalEditMessageId = send(
                                    target.channelName,
                                    target.accountId,
                                    target.peerId,
                                    if (useEditMessages) { renderGatewayEditText(visibleAnswer) } else { visibleAnswer },
                                    Some(streamingState.messageId),
                                    false
                                )
                                if (finalEditMessageId.trimAscii().isEmpty()) {
                                    LogUtils.info("Gateway streaming final fallback: channel=${context.channelName}, session=${context.sessionKey}, messageId=${streamingState.messageId}")
                                    let fallbackMessageId = send(target.channelName, target.accountId, target.peerId, visibleAnswer, effectiveReplyToMessageId, effectiveReplyInThread)
                                    gatewayNotifySessionLifecycle(lifecycleHook, "done")
                                    return GatewaySessionExecutionResult(
                                        answer,
                                        delivered: true,
                                        deliveryStatus: "delivered",
                                        deliveryMessageId: fallbackMessageId
                                    )
                                }
                            }
                            LogUtils.info("Gateway streaming finish: channel=${context.channelName}, session=${context.sessionKey}, messageId=${streamingState.messageId}")
                            gatewayNotifySessionLifecycle(lifecycleHook, "done")
                            return GatewaySessionExecutionResult(
                                answer,
                                delivered: true,
                                deliveryStatus: "delivered",
                                deliveryMessageId: streamingState.messageId
                            )
                        }
                        let sentMessageId = send(target.channelName, target.accountId, target.peerId, visibleAnswer, effectiveReplyToMessageId, effectiveReplyInThread)
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
