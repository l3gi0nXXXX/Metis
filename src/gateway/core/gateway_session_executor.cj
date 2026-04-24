package metis.gateway.core

import metis.core.{GatewayToolRuntimeContext, gatewayWithToolRuntimeContext}
import metis.core.renderGatewayEditText
import metis.gateway.session.GatewaySessionContext

import magic.log.LogUtils
import std.core.Duration
import std.time.DateTime

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
    streamingEnabled!: Bool = false
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
    let answer = gatewayReplyWithTimeout(
        bridge,
        context,
        prompt,
        extraSystemPrompt,
        timeoutSeconds,
        toolRuntimeContext: toolRuntimeContext,
        streamingEnabled: streamingEnabled,
        streamChunkHook: Some({ currentText =>
            let normalized = currentText.trimAscii()
            if (normalized.isEmpty()) {
                return
            }
            match (streamHook) {
                case Some(notify) => notify(context, currentText)
                case None => ()
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
                                currentText,
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
                                if (useEditMessages) { renderGatewayEditText(currentText) } else { currentText },
                                Some(streamingState.messageId),
                                false
                            )
                        }
                        streamingState.lastSentAtMs = nowMs
                        streamingState.lastText = currentText
                    } catch (ex: Exception) {
                        streamingState.failed = true
                        LogUtils.info("Gateway streaming fallback: channel=${context.channelName}, reason=${ex.message}")
                    }
                case None => ()
            }
        })
    )
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
                        if (!streamingState.messageId.isEmpty() && !streamingState.failed) {
                            if (answer != streamingState.lastText) {
                                let _ = send(
                                    target.channelName,
                                    target.accountId,
                                    target.peerId,
                                    if (useEditMessages) { renderGatewayEditText(answer) } else { answer },
                                    Some(streamingState.messageId),
                                    false
                                )
                            }
                            LogUtils.info("Gateway streaming finish: channel=${context.channelName}, session=${context.sessionKey}, messageId=${streamingState.messageId}")
                            return GatewaySessionExecutionResult(
                                answer,
                                delivered: true,
                                deliveryStatus: "delivered",
                                deliveryMessageId: streamingState.messageId
                            )
                        }
                        let sentMessageId = send(target.channelName, target.accountId, target.peerId, answer, effectiveReplyToMessageId, effectiveReplyInThread)
                        return GatewaySessionExecutionResult(
                            answer,
                            delivered: true,
                            deliveryStatus: "delivered",
                            deliveryMessageId: sentMessageId
                        )
                    } catch (ex: Exception) {
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
