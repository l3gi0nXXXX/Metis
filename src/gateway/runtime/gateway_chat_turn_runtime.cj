package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings}
import metis.gateway.core.{GatewaySessionStore, gatewayBuildChatEventMessage, gatewayBuildChatEventPayload, gatewayBuildChatTurnResult, gatewayBuildSessionEventPayload, gatewayBuildSessionTranscriptEventPayload, gatewayExecuteSessionRequestTurnForUser, gatewayFindSessionConversationViewForUser, gatewayLogEventInfo, gatewayLogMeta, gatewaySessionStoreForSessionKey}
import metis.gateway.session.{GatewayIngressSource, gatewayBuildSessionRpcParams, gatewayResolveSessionContext, gatewaySessionRequestFromRpcParams}

import std.collection.HashMap
import std.convert.Parsable
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

public let gatewayChatTurnInvokeCache = HashMap<String, JsonObject>()
public let gatewayChatTurnInvokeCacheLock = Mutex()

private func gatewayRuntimeRpcString(params: JsonObject, key: String): String {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayRuntimeRpcInt(params: JsonObject, key: String, fallback: Int64): Int64 {
    match (params.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.asString().getValue())
            } catch (_e: Exception) {
                try {
                    Int64.parse(v.toJsonString())
                } catch (_e2: Exception) {
                    fallback
                }
            }
        case None => fallback
    }
}

private func gatewayRuntimeRpcBool(params: JsonObject, key: String, fallback: Bool): Bool {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) {
                try {
                    let low = v.asString().getValue().trimAscii().toAsciiLower()
                    low == "true" || low == "1" || low == "yes" || low == "on"
                } catch (_e2: Exception) {
                    fallback
                }
            }
        case None => fallback
    }
}

public func gatewayRuntimeSessionStoreForRequest(user: GatewayUserSettings, sessionKey: String, agentId: String): GatewaySessionStore {
    gatewaySessionStoreForSessionKey(user, sessionKey, agentId: agentId)
}

public func gatewayChatTurnRequestParamsFromRpc(
    params: JsonObject,
    fallbackSource!: GatewayIngressSource = GatewayIngressSource.DashboardRpc
): JsonObject {
    let source = gatewayRuntimeRpcString(params, "source").trimAscii()
    gatewayBuildSessionRpcParams(
        if (source.isEmpty()) { fallbackSource } else { GatewayIngressSource.Unknown(source) },
        session: gatewayRuntimeRpcString(params, "session").trimAscii(),
        text: gatewayRuntimeRpcString(params, "text"),
        channel: gatewayRuntimeRpcString(params, "channel").trimAscii(),
        agentId: gatewayRuntimeRpcString(params, "agentId").trimAscii(),
        conversationId: gatewayRuntimeRpcString(params, "conversationId").trimAscii(),
        threadId: gatewayRuntimeRpcString(params, "threadId").trimAscii(),
        sourceMessageId: gatewayRuntimeRpcString(params, "sourceMessageId").trimAscii(),
        to: gatewayRuntimeRpcString(params, "to").trimAscii(),
        lane: gatewayRuntimeRpcString(params, "lane").trimAscii(),
        deliver: gatewayRuntimeRpcBool(params, "deliver", false),
        replyChannel: gatewayRuntimeRpcString(params, "replyChannel").trimAscii(),
        replyTo: gatewayRuntimeRpcString(params, "replyTo").trimAscii(),
        replyAccount: if (!gatewayRuntimeRpcString(params, "replyAccountId").trimAscii().isEmpty()) {
            gatewayRuntimeRpcString(params, "replyAccountId").trimAscii()
        } else {
            gatewayRuntimeRpcString(params, "replyAccount").trimAscii()
        },
        replyToMessageId: gatewayRuntimeRpcString(params, "replyToMessageId").trimAscii(),
        replyInThread: gatewayRuntimeRpcBool(params, "replyInThread", false)
    )
}

public func gatewayExecuteChatTurnFromRpc(
    params: JsonObject,
    fallbackSource!: GatewayIngressSource = GatewayIngressSource.DashboardRpc
): JsonObject {
    let rawSessionKey = gatewayRuntimeRpcString(params, "session").trimAscii()
    let question = gatewayRuntimeRpcString(params, "text")
    let deliver = gatewayRuntimeRpcBool(params, "deliver", false)
    let thinking = gatewayRuntimeRpcString(params, "thinking").trimAscii()
    let extraSystemPrompt = gatewayRuntimeRpcString(params, "extraSystemPrompt").trimAscii()
    let replyChannel = gatewayRuntimeRpcString(params, "replyChannel").trimAscii()
    let replyTo = gatewayRuntimeRpcString(params, "replyTo").trimAscii()
    let replyAccount = gatewayRuntimeRpcString(params, "replyAccount").trimAscii()
    let replyToMessageId = gatewayRuntimeRpcString(params, "replyToMessageId").trimAscii()
    let agentId = gatewayRuntimeRpcString(params, "agentId").trimAscii()
    let to = gatewayRuntimeRpcString(params, "to").trimAscii()
    let lane = gatewayRuntimeRpcString(params, "lane").trimAscii()
    let idempotencyKey = gatewayRuntimeRpcString(params, "idempotencyKey").trimAscii()
    let verbose = gatewayRuntimeRpcString(params, "verbose").trimAscii()
    let timeoutSeconds = gatewayRuntimeRpcInt(params, "timeout", 0)
    let bestEffortDeliver = gatewayRuntimeRpcBool(params, "bestEffortDeliver", false)
    let replyAccountId = gatewayRuntimeRpcString(params, "replyAccountId").trimAscii()
    let replyInThread = gatewayRuntimeRpcBool(params, "replyInThread", false)
    if (question.trimAscii().isEmpty()) {
        let err = JsonObject()
        err.put("error", JsonString("text must be non-empty"))
        return err
    }
    let requestParams = gatewayChatTurnRequestParamsFromRpc(params, fallbackSource: fallbackSource)
    let request = gatewaySessionRequestFromRpcParams(requestParams, fallbackSource: fallbackSource)
    let context = gatewayResolveSessionContext(request)
    if (!idempotencyKey.isEmpty()) {
        synchronized(gatewayChatTurnInvokeCacheLock) {
            match (gatewayChatTurnInvokeCache.get(idempotencyKey)) {
                case Some(cached) =>
                    let replay = JsonValue.fromStr(cached.toJsonString()).asObject()
                    replay.put("idempotentReplay", true.toJsonValue())
                    replay.put("runId", JsonString(idempotencyKey))
                    return replay
                case None => ()
            }
        }
    }
    let user = CliSettingManager.readGatewaySettings()
    let turn = try {
        gatewayExecuteSessionRequestTurnForUser(
            user,
            request,
            question,
            deliver: deliver,
            extraSystemPrompt: extraSystemPrompt,
            timeoutSeconds: timeoutSeconds,
            bestEffortDeliver: bestEffortDeliver,
            replyToMessageId: if (replyToMessageId.isEmpty()) { None<String> } else { Some(replyToMessageId) },
            replyInThread: replyInThread,
            deliverHook: match (gatewayActiveService()) {
                case Some(service) =>
                    Some({ channelName, accountId, peerId, text, replyToMessageId, replyInThread =>
                        service.sendTextToPeerDetailed(
                            channelName,
                            peerId,
                            text,
                            replyToMessageId: replyToMessageId,
                            replyInThread: replyInThread,
                            accountId: accountId
                        )
                    })
                case None => None<(String, String, String, String, Option<String>, Bool) -> String>
            },
            transcriptHook: Some({ context, delta, entryKind, lastRole =>
                let conversation = gatewayFindSessionConversationViewForUser(user, context.sessionKey)
                let transcriptEventPayload = gatewayBuildSessionTranscriptEventPayload(
                    context.sessionKey,
                    entryKind,
                    conversation: conversation,
                    deliveryTarget: context.deliveryTarget,
                    runId: if (idempotencyKey.isEmpty()) { "" } else { idempotencyKey },
                    detail: "chat-turn-transcript-appended",
                    delta: delta,
                    lastRole: lastRole
                )
                let _ = gatewayServerPublishSessionTranscriptEvent(
                    transcriptEventPayload,
                    detail: "chat-turn-transcript-appended"
                )
                let _ = gatewayServerPublishSessionMessageEvent(
                    context.sessionKey,
                    detail: "chat-turn-transcript-appended"
                )
            }),
            streamHook: Some({ context, partialText =>
                let conversation = gatewayFindSessionConversationViewForUser(user, context.sessionKey)
                let streamPayload = gatewayBuildChatEventPayload(
                    context.sessionKey,
                    if (idempotencyKey.isEmpty()) { "" } else { idempotencyKey },
                    "streaming",
                    gatewayBuildChatEventMessage("assistant", partialText, DateTime.now().toUnixTimeStamp().toMilliseconds()),
                    conversation: conversation,
                    deliveryTarget: context.deliveryTarget
                )
                let _ = gatewayServerPublishChatEvent(streamPayload, detail: "streaming")
                let sessionPayload = gatewayBuildSessionEventPayload(
                    context.sessionKey,
                    "streaming",
                    conversation: conversation,
                    deliveryTarget: context.deliveryTarget,
                    runId: if (idempotencyKey.isEmpty()) { "" } else { idempotencyKey },
                    detail: "chat-turn-streaming"
                )
                let _ = gatewayServerPublishSessionEvent(sessionPayload, detail: "chat-turn-streaming")
            })
        )
    } catch (ex: Exception) {
        let err = JsonObject()
        err.put("error", JsonString(ex.message))
        return err
    }
    let execution = turn.execution
    let conversation = gatewayFindSessionConversationViewForUser(user, context.sessionKey)
    let result = gatewayBuildChatTurnResult(
        turn.context,
        question,
        execution,
        to,
        thinking,
        verbose,
        timeoutSeconds,
        lane,
        idempotencyKey,
        extraSystemPrompt,
        deliver,
        bestEffortDeliver,
        replyChannel,
        replyTo,
        replyAccount,
        replyAccountId,
        conversation: conversation
    )
    if (!idempotencyKey.isEmpty()) {
        synchronized(gatewayChatTurnInvokeCacheLock) {
            gatewayChatTurnInvokeCache[idempotencyKey] = result
        }
    }
    let eventPayload = gatewayBuildChatEventPayload(
        context.sessionKey,
        if (idempotencyKey.isEmpty()) { "" } else { idempotencyKey },
        "final",
        gatewayBuildChatEventMessage("assistant", execution.answer, DateTime.now().toUnixTimeStamp().toMilliseconds()),
        conversation: conversation,
        deliveryTarget: turn.context.deliveryTarget
    )
    let published = gatewayServerPublishChatEvent(eventPayload, detail: "final")
    let sessionEventPayload = gatewayBuildSessionEventPayload(
        context.sessionKey,
        "updated",
        conversation: conversation,
        deliveryTarget: turn.context.deliveryTarget,
        runId: if (idempotencyKey.isEmpty()) { "" } else { idempotencyKey },
        detail: "chat-turn-completed",
        errorMessage: execution.deliveryError
    )
    let sessionPublished = gatewayServerPublishSessionEvent(sessionEventPayload, detail: "chat-turn-completed")
    gatewayLogEventInfo(
        "gateway/chat-turn",
        "chat_turn.published",
        "chat turn events published",
        meta: gatewayLogMeta()
            .identityHash("sessionHash", context.sessionKey)
            .identityHash("runHash", if (idempotencyKey.isEmpty()) { "<empty>" } else { idempotencyKey })
            .int("chatClients", published)
            .int("sessionClients", sessionPublished)
            .object()
    )
    result
}
