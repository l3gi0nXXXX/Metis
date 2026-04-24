package metis.gateway.core

import magic.jsonable.*

import metis.gateway.session.{GatewayDeliveryTarget, GatewaySessionContext}

import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

public let GATEWAY_CONTROL_UI_CLIENT_NAME = "metis-control-ui"
public let GATEWAY_CONTROL_UI_ALTERNATE_CLIENT_NAME = "metis-control-ui"

public func gatewayChatEventShouldPublishToClient(clientName: String, clientMode: String): Bool {
    let normalizedName = clientName.trimAscii().toAsciiLower()
    let normalizedMode = clientMode.trimAscii().toAsciiLower()
    normalizedName == GATEWAY_CONTROL_UI_CLIENT_NAME ||
        normalizedName == GATEWAY_CONTROL_UI_ALTERNATE_CLIENT_NAME ||
        normalizedMode == "webchat" ||
        normalizedMode == "control-ui-browser"
}

public func gatewayBuildChatEventMessage(role: String, text: String, tsMs: Int64): JsonObject {
    let content = JsonArray([])
    let textItem = JsonObject()
    textItem.put("type", JsonString("text"))
    textItem.put("text", JsonString(text))
    content.add(textItem)
    let message = JsonObject()
    message.put("role", JsonString(role))
    message.put("content", content)
    message.put("timestamp", tsMs.toJsonValue())
    message
}

public func gatewayBuildChatEventPayload(
    sessionKey: String,
    runId: String,
    state: String,
    message: JsonObject,
    conversation!: Option<GatewaySessionConversationView> = None<GatewaySessionConversationView>,
    deliveryTarget!: Option<GatewayDeliveryTarget> = None<GatewayDeliveryTarget>,
    errorMessage!: String = ""
): JsonObject {
    let payload = JsonObject()
    payload.put("sessionKey", JsonString(sessionKey.trimAscii()))
    payload.put("runId", JsonString(runId.trimAscii()))
    payload.put("state", JsonString(state.trimAscii()))
    payload.put("message", message)
    payload.put("ts", (DateTime.now().toUnixTimeStamp().toMilliseconds()).toJsonValue())
    let normalizedError = errorMessage.trimAscii()
    if (!normalizedError.isEmpty()) {
        payload.put("errorMessage", JsonString(normalizedError))
    }
    match (conversation) {
        case Some(view) =>
            payload.put("agentId", JsonString(view.agentId))
            payload.put("displayName", JsonString(view.displayName))
            payload.put("channel", JsonString(view.channel))
            payload.put("chatType", JsonString(view.chatType))
            payload.put("peer", JsonString(view.peer))
            payload.put("sessionId", JsonString(view.sessionId))
            payload.put("origin", view.origin)
            payload.put("delivery", gatewayBuildEffectiveDeliveryProjection(view, deliveryTarget))
            payload.put("binding", gatewayBuildEffectiveBindingProjection(view, deliveryTarget))
        case None => ()
    }
    payload
}

public func gatewayBuildSessionEventPayload(
    sessionKey: String,
    state: String,
    conversation!: Option<GatewaySessionConversationView> = None<GatewaySessionConversationView>,
    deliveryTarget!: Option<GatewayDeliveryTarget> = None<GatewayDeliveryTarget>,
    runId!: String = "",
    detail!: String = "",
    errorMessage!: String = ""
): JsonObject {
    let payload = JsonObject()
    payload.put("sessionKey", JsonString(sessionKey.trimAscii()))
    payload.put("state", JsonString(state.trimAscii()))
    payload.put("ts", (DateTime.now().toUnixTimeStamp().toMilliseconds()).toJsonValue())
    let normalizedRunId = runId.trimAscii()
    if (!normalizedRunId.isEmpty()) {
        payload.put("runId", JsonString(normalizedRunId))
    }
    let normalizedDetail = detail.trimAscii()
    if (!normalizedDetail.isEmpty()) {
        payload.put("detail", JsonString(normalizedDetail))
    }
    let normalizedError = errorMessage.trimAscii()
    if (!normalizedError.isEmpty()) {
        payload.put("errorMessage", JsonString(normalizedError))
    }
    match (conversation) {
        case Some(view) =>
            payload.put("agentId", JsonString(view.agentId))
            payload.put("displayName", JsonString(view.displayName))
            payload.put("channel", JsonString(view.channel))
            payload.put("chatType", JsonString(view.chatType))
            payload.put("peer", JsonString(view.peer))
            payload.put("sessionId", JsonString(view.sessionId))
            payload.put("origin", view.origin)
            payload.put("delivery", gatewayBuildEffectiveDeliveryProjection(view, deliveryTarget))
            payload.put("binding", gatewayBuildEffectiveBindingProjection(view, deliveryTarget))
        case None => ()
    }
    payload
}

public func gatewayBuildSessionTranscriptEventPayload(
    sessionKey: String,
    entryKind: String,
    conversation!: Option<GatewaySessionConversationView> = None<GatewaySessionConversationView>,
    deliveryTarget!: Option<GatewayDeliveryTarget> = None<GatewayDeliveryTarget>,
    runId!: String = "",
    detail!: String = "",
    delta!: Int64 = 0,
    lastRole!: String = ""
): JsonObject {
    let payload = gatewayBuildSessionEventPayload(
        sessionKey,
        "transcript-updated",
        conversation: conversation,
        deliveryTarget: deliveryTarget,
        runId: runId,
        detail: detail
    )
    payload.put("entryKind", JsonString(entryKind.trimAscii()))
    if (delta > 0) {
        payload.put("delta", delta.toJsonValue())
    }
    let normalizedLastRole = lastRole.trimAscii()
    if (!normalizedLastRole.isEmpty()) {
        payload.put("lastRole", JsonString(normalizedLastRole))
    }
    payload
}

private func gatewayBuildEffectiveDeliveryProjection(
    view: GatewaySessionConversationView,
    deliveryTarget: Option<GatewayDeliveryTarget>
): JsonObject {
    let out = JsonValue.fromStr(view.delivery.toJsonString()).asObject()
    match (deliveryTarget) {
        case Some(target) =>
            out.put("channel", JsonString(target.channelName))
            out.put("peer", JsonString(target.peerId))
            out.put("replyChannel", JsonString(target.channelName))
            out.put("replyTo", JsonString(target.peerId))
            out.put("accountId", JsonString(target.accountId))
            out.put("conversationId", JsonString(target.conversationId))
            out.put("threadId", JsonString(target.threadId))
            out.put("sourceMessageId", JsonString(target.sourceMessageId))
            out.put("replyToMessageId", JsonString(target.replyToMessageId))
            out.put("replyInThread", target.replyInThread.toJsonValue())
        case None => ()
    }
    out
}

private func gatewayBuildEffectiveBindingProjection(
    view: GatewaySessionConversationView,
    deliveryTarget: Option<GatewayDeliveryTarget>
): JsonObject {
    let out = JsonValue.fromStr(view.binding.toJsonString()).asObject()
    match (deliveryTarget) {
        case Some(target) =>
            out.put("channel", JsonString(target.channelName))
            out.put("peer", JsonString(target.peerId))
            out.put("accountId", JsonString(target.accountId))
            out.put("conversationId", JsonString(target.conversationId))
            out.put("threadId", JsonString(target.threadId))
            out.put("sourceMessageId", JsonString(target.sourceMessageId))
            out.put("replyTargetMessageId", JsonString(target.replyToMessageId))
            out.put("replyInThread", target.replyInThread.toJsonValue())
            out.put("mode", JsonString("delivery-target"))
        case None => ()
    }
    out
}

public func gatewayChatTurnReplyChannel(context: GatewaySessionContext, fallback: String): String {
    match (context.deliveryTarget) {
        case Some(target) => target.channelName
        case None => fallback.trimAscii().toAsciiLower()
    }
}

public func gatewayChatTurnReplyTo(context: GatewaySessionContext, fallback: String): String {
    match (context.deliveryTarget) {
        case Some(target) => target.peerId
        case None => fallback.trimAscii()
    }
}

public func gatewayBuildChatTurnResult(
    context: GatewaySessionContext,
    question: String,
    execution: GatewaySessionExecutionResult,
    to: String,
    thinking: String,
    verbose: String,
    timeoutSeconds: Int64,
    lane: String,
    idempotencyKey: String,
    extraSystemPrompt: String,
    deliver: Bool,
    bestEffortDeliver: Bool,
    replyChannel: String,
    replyTo: String,
    replyAccount: String,
    replyAccountId: String,
    conversation!: Option<GatewaySessionConversationView> = None<GatewaySessionConversationView>
): JsonObject {
    let result = JsonObject()
    result.put("session", JsonString(context.sessionKey))
    result.put("question", JsonString(question))
    result.put("answer", JsonString(execution.answer))
    result.put("agentId", JsonString(context.agentId))
    result.put("channel", JsonString(context.channelName))
    result.put("source", JsonString(context.sourceLabel))
    result.put("to", JsonString(to))
    result.put("thinking", JsonString(thinking))
    result.put("verbose", JsonString(verbose))
    result.put("timeout", timeoutSeconds.toJsonValue())
    result.put("lane", JsonString(lane))
    result.put("idempotencyKey", JsonString(idempotencyKey))
    result.put("extraSystemPrompt", JsonString(extraSystemPrompt))
    result.put("deliver", deliver.toJsonValue())
    result.put("bestEffortDeliver", bestEffortDeliver.toJsonValue())
    result.put("runId", JsonString(if (idempotencyKey.isEmpty()) { "" } else { idempotencyKey }))
    result.put("idempotentReplay", false.toJsonValue())
    result.put("replyChannel", JsonString(gatewayChatTurnReplyChannel(context, replyChannel)))
    result.put("replyTo", JsonString(gatewayChatTurnReplyTo(context, replyTo)))
    result.put("replyAccount", JsonString(if (replyAccount.trimAscii().isEmpty()) { replyAccountId.trimAscii() } else { replyAccount.trimAscii() }))
    result.put("replyAccountId", JsonString(if (replyAccountId.trimAscii().isEmpty()) { replyAccount.trimAscii() } else { replyAccountId.trimAscii() }))
    result.put("replyToMessageId", JsonString(match (context.deliveryTarget) {
        case Some(target) => target.replyToMessageId
        case None => ""
    }))
    result.put("replyInThread", match (context.deliveryTarget) {
        case Some(target) => target.replyInThread.toJsonValue()
        case None => false.toJsonValue()
    })
    result.put("deliveryStatus", JsonString(execution.deliveryStatus))
    result.put("delivered", execution.delivered.toJsonValue())
    result.put("deliveryError", JsonString(execution.deliveryError))
    match (conversation) {
        case Some(view) =>
            result.put("displayName", JsonString(view.displayName))
            result.put("chatType", JsonString(view.chatType))
            result.put("peer", JsonString(view.peer))
            result.put("sessionId", JsonString(view.sessionId))
            result.put("origin", view.origin)
            result.put("delivery", gatewayBuildEffectiveDeliveryProjection(view, context.deliveryTarget))
            result.put("binding", gatewayBuildEffectiveBindingProjection(view, context.deliveryTarget))
        case None => ()
    }
    result
}
