package metis.gateway.session

import magic.jsonable.*

import metis.core.config.{MetisAgentScope, MetisConfigManager, MetisPaths}
import metis.gateway.model.ChatType
import metis.gateway.model.{InboundMessage, channelToString}
import std.collection.ArrayList
import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}

private func gatewaySessionSanitizeAgentId(raw: String): String {
    var s = raw.trimAscii().replace("/", "_").replace("\\", "_").replace("..", "_").replace(":", "_")
    if (s.isEmpty()) {
        return "main"
    }
    s
}

private func gatewayNormalizeDmScope(raw: String): String {
    let s = raw.trimAscii().toAsciiLower()
    if (s == "main" || s == "per-peer" || s == "per-channel-peer") {
        return s
    }
    "per-chat"
}

private func gatewayRouteAgentIdFromMediaContext(mediaContext: JsonObject): String {
    let route = gatewayRouteFromMediaContext(mediaContext)
    match (route.get("agentId")) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayRouteFromMediaContext(mediaContext: JsonObject): JsonObject {
    let context = match (mediaContext.get("context")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let route = match (context.get("imRoute")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let channelRoute = gatewayChannelPolicyRouteFromContext(context)
    gatewayMergeRoutePolicyFields(route, channelRoute)
    if (route.size() > 0) {
        return route
    }
    channelRoute
}

public func gatewayRuntimeRouteContextFromMediaContext(mediaContext: JsonObject): JsonObject {
    gatewayRouteFromMediaContext(mediaContext)
}

private func gatewayChannelPolicyRouteFromContext(context: JsonObject): JsonObject {
    match (context.get("imRoute")) {
        case Some(_) => ()
        case None => ()
    }
    for (key in ["telegramRoute", "feishuRoute", "larkRoute", "routePolicy", "groupPolicy"]) {
        match (context.get(key)) {
            case Some(v) =>
                let obj = try { v.asObject() } catch (_e: Exception) { JsonObject() }
                if (obj.size() > 0) {
                    return obj
                }
            case None => ()
        }
    }
    JsonObject()
}

private func gatewayMergeRoutePolicyFields(target: JsonObject, source: JsonObject): Unit {
    if (source.size() == 0) {
        return
    }
    for (key in ["agentId", "systemPrompt", "skills", "tools", "groupPolicy", "policy", "runtimePolicy", "disableAudioPreflight"]) {
        if (target.get(key).isNone()) {
            match (source.get(key)) {
                case Some(value) => target.put(key, value)
                case None => ()
            }
        }
    }
}

private func gatewayNormalizeChannelName(raw: String, source: GatewayIngressSource): String {
    let channel = raw.trimAscii().toAsciiLower()
    if (!channel.isEmpty()) {
        return channel
    }
    match (source) {
        case GatewayIngressSource.Cli => "cli"
        case GatewayIngressSource.ControlUi => "control-ui"
        case GatewayIngressSource.DashboardRpc => "dashboard"
        case GatewayIngressSource.GatewayRpc => "gateway-rpc"
        case GatewayIngressSource.Channel(name) => name.trimAscii().toAsciiLower()
        case GatewayIngressSource.Cron => "cron"
        case GatewayIngressSource.Unknown(label) => label.trimAscii().toAsciiLower()
    }
}

private func gatewayHintedAgentId(sessionHint: String): String {
    let raw = sessionHint.trimAscii().toAsciiLower()
    if (!raw.startsWith("agent:")) {
        return ""
    }
    let parts = raw.split(":")
    if (parts.size < 3) {
        return ""
    }
    parts[1].trimAscii()
}

private func gatewaySessionJsonString(params: JsonObject, key: String): String {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewaySessionJsonBool(params: JsonObject, key: String, fallback: Bool): Bool {
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

private func gatewaySessionJsonStringArray(params: JsonObject, key: String): Array<String> {
    match (params.get(key)) {
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
            } catch (_e: Exception) {
                []
            }
        case None => []
    }
}

private func gatewaySessionJsonObject(params: JsonObject, key: String): JsonObject {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewaySessionMediaContextObject(mediaContext: JsonObject): JsonObject {
    match (mediaContext.get("context")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewaySessionScopeRoot(): JsonObject {
    match (MetisConfigManager.rawConfig()) {
        case Some(root) => root
        case None => JsonObject()
    }
}

private func gatewaySessionImRouteContext(mediaContext: JsonObject): JsonObject {
    let context = gatewaySessionMediaContextObject(mediaContext)
    match (context.get("imRoute")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewaySessionRouteString(route: JsonObject, key: String): String {
    match (route.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewaySessionScopeString(scope: JsonObject, key: String): String {
    match (scope.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayBuildTurnRouteContext(
    route: JsonObject,
    agentId: String,
    channelName: String,
    accountId: String,
    sessionKey: String,
    mainSessionKey: String,
    matchedBy: String,
    lastRoutePolicy: String
): JsonObject {
    let out = try {
        JsonValue.fromStr(route.toJsonString()).asObject()
    } catch (_: Exception) {
        JsonObject()
    }
    out.put("agentId", JsonString(agentId))
    out.put("channel", JsonString(channelName))
    out.put("accountId", JsonString(accountId))
    out.put("sessionKey", JsonString(sessionKey))
    out.put("mainSessionKey", JsonString(mainSessionKey))
    out.put("matchedBy", JsonString(matchedBy))
    if (!lastRoutePolicy.trimAscii().isEmpty()) {
        out.put("lastRoutePolicy", JsonString(lastRoutePolicy.trimAscii()))
    }
    out
}

public func gatewayIngressSourceFromString(raw: String, fallback!: GatewayIngressSource = GatewayIngressSource.Unknown("")): GatewayIngressSource {
    let low = raw.trimAscii().toAsciiLower()
    if (low == "cli") {
        return GatewayIngressSource.Cli
    }
    if (low == "control-ui" || low == "control_ui") {
        return GatewayIngressSource.ControlUi
    }
    if (low == "dashboard") {
        return GatewayIngressSource.DashboardRpc
    }
    if (low == "gateway-rpc" || low == "gateway_rpc") {
        return GatewayIngressSource.GatewayRpc
    }
    if (low == "cron") {
        return GatewayIngressSource.Cron
    }
    if (!low.isEmpty()) {
        return GatewayIngressSource.Unknown(low)
    }
    fallback
}

public func gatewayBuildChannelSessionKey(
    channelName: String,
    chatType: ChatType,
    peerId: String,
    senderId: String,
    conversationId!: String = "",
    dmScope!: String = "per-chat"
): String {
    let ch = channelName.trimAscii().toAsciiLower()
    let normalizedPeer = peerId.trimAscii()
    let normalizedSender = senderId.trimAscii()
    let conversationPeer = if (!conversationId.trimAscii().isEmpty()) { conversationId.trimAscii() } else { normalizedPeer }
    let scope = gatewayNormalizeDmScope(dmScope)
    match (chatType) {
        case ChatType.Group =>
            if (scope == "per-peer") {
                return "gateway:peer:${normalizedSender}"
            }
            if (scope == "per-channel-peer") {
                return "${ch}:group:${conversationPeer}:u:${normalizedSender}"
            }
            "${ch}:group:${conversationPeer}"
        case ChatType.Direct =>
            match (scope) {
                case "main" => "gateway:dm:main"
                case "per-peer" => "gateway:dm:u:${normalizedSender}"
                case "per-channel-peer" => "${ch}:dm:u:${normalizedSender}"
                case _ => "${ch}:direct:${conversationPeer}"
            }
    }
}

private func gatewayResolveAgentSessionKey(agentId: String, sessionHint: String, to: String, lane: String): String {
    let normalizedAgentId = gatewaySessionSanitizeAgentId(agentId)
    let explicit = sessionHint.trimAscii().toAsciiLower()
    let peer = to.trimAscii().toAsciiLower()
    var base = ""
    if (!explicit.isEmpty()) {
        if (explicit.startsWith("agent:") ||
            explicit.startsWith("gateway:") ||
            explicit.contains(":direct:") ||
            explicit.contains(":group:") ||
            explicit.contains(":dm:")) {
            base = explicit
        } else if (explicit == "main") {
            base = "agent:${normalizedAgentId}:main"
        } else {
            base = "agent:${normalizedAgentId}:explicit:${explicit}"
        }
    } else if (!peer.isEmpty()) {
        base = "agent:${normalizedAgentId}:direct:${peer}"
    } else {
        base = "agent:${normalizedAgentId}:main"
    }
    let laneName = lane.trimAscii().toAsciiLower()
    if (laneName.isEmpty() || base.contains(":lane:")) {
        return base
    }
    "${base}:lane:${laneName}"
}

private func gatewayInferDeliveryTargetFromSessionKey(sessionKey: String, accountId: String): Option<GatewayDeliveryTarget> {
    let sk = sessionKey.trimAscii()
    if (sk.startsWith("feishu:direct:")) {
        return Some(GatewayDeliveryTarget("feishu", sk["feishu:direct:".size..], accountId: accountId))
    }
    if (sk.startsWith("feishu:group:")) {
        let rest = sk["feishu:group:".size..]
        let idx = rest.indexOf(":topic:")
        let peerId = if (let Some(pos) <- idx) { rest[0..pos] } else { rest }
        return Some(GatewayDeliveryTarget("feishu", peerId, accountId: accountId))
    }
    if (sk.startsWith("qq:direct:")) {
        return Some(GatewayDeliveryTarget("qq", sk["qq:direct:".size..], accountId: accountId))
    }
    if (sk.startsWith("qq:group:")) {
        let rest = sk["qq:group:".size..]
        let idx = rest.indexOf(":sender:")
        let peerId = if (let Some(pos) <- idx) { rest[0..pos] } else { rest }
        return Some(GatewayDeliveryTarget("qq", peerId, accountId: accountId))
    }
    if (sk.startsWith("telegram:direct:")) {
        return Some(GatewayDeliveryTarget("telegram", sk["telegram:direct:".size..], accountId: accountId))
    }
    if (sk.startsWith("telegram:group:")) {
        let peerId = sk["telegram:group:".size..]
        var threadId = ""
        match (peerId.indexOf(":topic:")) {
            case Some(idx) => threadId = peerId[idx + ":topic:".size..].trimAscii()
            case None => ()
        }
        return Some(
            GatewayDeliveryTarget(
                "telegram",
                peerId,
                accountId: accountId,
                conversationId: peerId,
                threadId: threadId,
                replyInThread: !threadId.isEmpty()
            )
        )
    }
    None
}

public func gatewayResolveDeliveryTarget(
    request: GatewaySessionRequest,
    sessionKey: String,
    preferredAccountId!: String = ""
): Option<GatewayDeliveryTarget> {
    if (!request.replyChannel.isEmpty() && !request.replyTo.isEmpty()) {
        return Some(
            GatewayDeliveryTarget(
                request.replyChannel,
                request.replyTo,
                accountId: if (!request.replyAccountId.isEmpty()) { request.replyAccountId } else { preferredAccountId },
                conversationId: request.conversationId,
                threadId: request.threadId,
                sourceMessageId: request.sourceMessageId,
                replyToMessageId: request.replyToMessageId,
                replyInThread: request.replyInThread
            )
        )
    }
    match (request.source) {
        case GatewayIngressSource.Channel(_channel) =>
            let channelName = gatewayNormalizeChannelName(request.channelName, request.source)
            if (!channelName.isEmpty() && !request.peerId.isEmpty()) {
                let accountId = if (!request.replyAccountId.isEmpty()) {
                    request.replyAccountId
                } else if (!preferredAccountId.isEmpty()) {
                    preferredAccountId
                } else {
                    request.accountId
                }
                return Some(
                    GatewayDeliveryTarget(
                        channelName,
                        request.peerId,
                        accountId: accountId,
                        conversationId: request.conversationId,
                        threadId: request.threadId,
                        sourceMessageId: request.sourceMessageId,
                        replyToMessageId: request.replyToMessageId,
                        replyInThread: request.replyInThread
                    )
                )
            }
        case _ => ()
    }
    gatewayInferDeliveryTargetFromSessionKey(
        sessionKey,
        if (!preferredAccountId.isEmpty()) { preferredAccountId } else { request.accountId }
    )
}

public func gatewaySessionRequestFromInbound(
    message: InboundMessage,
    dmScope!: String = "per-chat",
    accountId!: String = "",
    routeRoot!: JsonObject = JsonObject()
): GatewaySessionRequest {
    let replyToMessageId = match (message.replyTargetMessageId) {
        case Some(msgId) => msgId
        case None => message.messageId
    }
    let imRoute = gatewaySessionImRouteContext(message.mediaContext)
    GatewaySessionRequest(
        GatewayIngressSource.Channel(channelToString(message.channel)),
        channelName: channelToString(message.channel),
        sessionHint: "",
        agentId: gatewayRouteAgentIdFromMediaContext(message.mediaContext),
        text: message.text,
        accountId: if (!accountId.trimAscii().isEmpty()) { accountId } else { message.accountId },
        peerId: message.peerId,
        senderId: message.senderId,
        conversationId: message.conversationId ?? "",
        threadId: message.threadId ?? "",
        sourceMessageId: message.messageId,
        chatType: Some(message.chatType),
        dmScope: dmScope,
        replyToMessageId: replyToMessageId,
        replyInThread: message.replyInThread,
        deliver: true,
        mediaContext: message.mediaContext,
        routeRoot: routeRoot,
        routeAccountId: gatewaySessionJsonString(imRoute, "accountId"),
        routeDefaultAccountId: gatewaySessionJsonString(imRoute, "defaultAccountId"),
        routePeerKind: gatewaySessionJsonString(imRoute, "peerKind"),
        routePeerId: gatewaySessionJsonString(imRoute, "peerId"),
        routeParentPeerKind: gatewaySessionJsonString(imRoute, "parentPeerKind"),
        routeParentPeerId: gatewaySessionJsonString(imRoute, "parentPeerId")
    )
}

public func gatewaySessionRequestFromInbound(
    message: InboundMessage,
    sessionHint!: String,
    dmScope!: String = "per-chat",
    accountId!: String = "",
    routeRoot!: JsonObject = JsonObject()
): GatewaySessionRequest {
    let replyToMessageId = match (message.replyTargetMessageId) {
        case Some(msgId) => msgId
        case None => message.messageId
    }
    let imRoute = gatewaySessionImRouteContext(message.mediaContext)
    GatewaySessionRequest(
        GatewayIngressSource.Channel(channelToString(message.channel)),
        channelName: channelToString(message.channel),
        sessionHint: sessionHint,
        agentId: gatewayRouteAgentIdFromMediaContext(message.mediaContext),
        text: message.text,
        accountId: if (!accountId.trimAscii().isEmpty()) { accountId } else { message.accountId },
        peerId: message.peerId,
        senderId: message.senderId,
        conversationId: message.conversationId ?? "",
        threadId: message.threadId ?? "",
        sourceMessageId: message.messageId,
        chatType: Some(message.chatType),
        dmScope: dmScope,
        replyToMessageId: replyToMessageId,
        replyInThread: message.replyInThread,
        deliver: true,
        mediaContext: message.mediaContext,
        routeRoot: routeRoot,
        routeAccountId: gatewaySessionJsonString(imRoute, "accountId"),
        routeDefaultAccountId: gatewaySessionJsonString(imRoute, "defaultAccountId"),
        routePeerKind: gatewaySessionJsonString(imRoute, "peerKind"),
        routePeerId: gatewaySessionJsonString(imRoute, "peerId"),
        routeParentPeerKind: gatewaySessionJsonString(imRoute, "parentPeerKind"),
        routeParentPeerId: gatewaySessionJsonString(imRoute, "parentPeerId")
    )
}

public func gatewaySessionRequestFromRpcParams(
    params: JsonObject,
    fallbackSource!: GatewayIngressSource = GatewayIngressSource.DashboardRpc
): GatewaySessionRequest {
    let replyAccountId = gatewaySessionJsonString(params, "replyAccountId")
    let replyAccount = gatewaySessionJsonString(params, "replyAccount")
    GatewaySessionRequest(
        gatewayIngressSourceFromString(gatewaySessionJsonString(params, "source"), fallback: fallbackSource),
        channelName: gatewaySessionJsonString(params, "channel"),
        sessionHint: gatewaySessionJsonString(params, "session"),
        agentId: gatewaySessionJsonString(params, "agentId"),
        text: gatewaySessionJsonString(params, "text"),
        accountId: gatewaySessionJsonString(params, "accountId"),
        declaredUser: gatewaySessionJsonString(params, "declaredUser"),
        operatorScopes: gatewaySessionJsonStringArray(params, "operatorScopes"),
        conversationId: gatewaySessionJsonString(params, "conversationId"),
        threadId: gatewaySessionJsonString(params, "threadId"),
        sourceMessageId: gatewaySessionJsonString(params, "sourceMessageId"),
        to: gatewaySessionJsonString(params, "to"),
        lane: gatewaySessionJsonString(params, "lane"),
        replyChannel: gatewaySessionJsonString(params, "replyChannel"),
        replyTo: gatewaySessionJsonString(params, "replyTo"),
        replyAccountId: if (!replyAccountId.isEmpty()) { replyAccountId } else { replyAccount },
        replyToMessageId: gatewaySessionJsonString(params, "replyToMessageId"),
        replyInThread: gatewaySessionJsonBool(params, "replyInThread", false),
        deliver: gatewaySessionJsonBool(params, "deliver", false),
        mediaContext: gatewaySessionJsonObject(params, "mediaContext")
    )
}

public func gatewayBuildChatSendRpcParams(
    source: GatewayIngressSource,
    session!: String = "",
    text!: String = "",
    deliver!: Bool = false,
    thinking!: String = "",
    conversationId!: String = "",
    threadId!: String = "",
    sourceMessageId!: String = "",
    replyChannel!: String = "",
    replyTo!: String = "",
    replyAccount!: String = "",
    replyToMessageId!: String = "",
    replyInThread!: Bool = false,
    idempotencyKey!: String = ""
): JsonObject {
    gatewayBuildSessionRpcParams(
        source,
        session: session,
        text: text,
        deliver: deliver,
        thinking: thinking,
        conversationId: conversationId,
        threadId: threadId,
        sourceMessageId: sourceMessageId,
        replyChannel: replyChannel,
        replyTo: replyTo,
        replyAccount: replyAccount,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        idempotencyKey: idempotencyKey
    )
}

public func gatewayBuildChatHistoryRpcParams(session!: String = ""): JsonObject {
    let out = JsonObject()
    let normalizedSession = session.trimAscii()
    if (!normalizedSession.isEmpty()) {
        out.put("session", JsonString(normalizedSession))
    }
    out
}

public func gatewayBuildSessionsDeleteRpcParams(keys!: String = ""): JsonObject {
    let out = JsonObject()
    let normalizedKeys = keys.trimAscii()
    if (!normalizedKeys.isEmpty()) {
        out.put("keys", JsonString(normalizedKeys))
    }
    out
}

public func gatewayBuildSessionRpcParams(
    source: GatewayIngressSource,
    session!: String = "",
    text!: String = "",
    channel!: String = "",
    agentId!: String = "",
    accountId!: String = "",
    conversationId!: String = "",
    threadId!: String = "",
    sourceMessageId!: String = "",
    to!: String = "",
    lane!: String = "",
    deliver!: Bool = false,
    thinking!: String = "",
    verbose!: String = "",
    timeoutSeconds!: Int64 = 0,
    bestEffortDeliver!: Bool = false,
    replyChannel!: String = "",
    replyTo!: String = "",
    replyAccount!: String = "",
    replyToMessageId!: String = "",
    replyInThread!: Bool = false,
    extraSystemPrompt!: String = "",
    idempotencyKey!: String = "",
    declaredUser!: String = "",
    operatorScopes!: Array<String> = []
): JsonObject {
    let out = JsonObject()
    out.put("source", JsonString(gatewayIngressSourceLabel(source)))
    let normalizedSession = session.trimAscii()
    let normalizedText = text
    let normalizedChannel = channel.trimAscii().toAsciiLower()
    let normalizedAgentId = agentId.trimAscii()
    let normalizedAccountId = accountId.trimAscii()
    let normalizedConversationId = conversationId.trimAscii()
    let normalizedThreadId = threadId.trimAscii()
    let normalizedSourceMessageId = sourceMessageId.trimAscii()
    let normalizedTo = to.trimAscii()
    let normalizedLane = lane.trimAscii()
    let normalizedThinking = thinking.trimAscii()
    let normalizedVerbose = verbose.trimAscii()
    let normalizedReplyChannel = replyChannel.trimAscii()
    let normalizedReplyTo = replyTo.trimAscii()
    let normalizedReplyAccount = replyAccount.trimAscii()
    let normalizedReplyToMessageId = replyToMessageId.trimAscii()
    let normalizedExtraSystemPrompt = extraSystemPrompt.trimAscii()
    let normalizedIdempotencyKey = idempotencyKey.trimAscii()
    let normalizedDeclaredUser = declaredUser.trimAscii()
    if (!normalizedSession.isEmpty()) {
        out.put("session", JsonString(normalizedSession))
    }
    if (!normalizedText.trimAscii().isEmpty()) {
        out.put("text", JsonString(normalizedText))
    }
    if (!normalizedChannel.isEmpty()) {
        out.put("channel", JsonString(normalizedChannel))
    }
    if (!normalizedAgentId.isEmpty()) {
        out.put("agentId", JsonString(normalizedAgentId))
    }
    if (!normalizedAccountId.isEmpty()) {
        out.put("accountId", JsonString(normalizedAccountId))
    }
    if (!normalizedConversationId.isEmpty()) {
        out.put("conversationId", JsonString(normalizedConversationId))
    }
    if (!normalizedThreadId.isEmpty()) {
        out.put("threadId", JsonString(normalizedThreadId))
    }
    if (!normalizedSourceMessageId.isEmpty()) {
        out.put("sourceMessageId", JsonString(normalizedSourceMessageId))
    }
    if (!normalizedTo.isEmpty()) {
        out.put("to", JsonString(normalizedTo))
    }
    if (!normalizedLane.isEmpty()) {
        out.put("lane", JsonString(normalizedLane))
    }
    out.put("deliver", JsonBool(deliver))
    if (!normalizedThinking.isEmpty()) {
        out.put("thinking", JsonString(normalizedThinking))
    }
    if (!normalizedVerbose.isEmpty()) {
        out.put("verbose", JsonString(normalizedVerbose))
    }
    if (timeoutSeconds > 0) {
        out.put("timeout", timeoutSeconds.toJsonValue())
    }
    out.put("bestEffortDeliver", JsonBool(bestEffortDeliver))
    if (!normalizedReplyChannel.isEmpty()) {
        out.put("replyChannel", JsonString(normalizedReplyChannel))
    }
    if (!normalizedReplyTo.isEmpty()) {
        out.put("replyTo", JsonString(normalizedReplyTo))
    }
    if (!normalizedReplyAccount.isEmpty()) {
        out.put("replyAccount", JsonString(normalizedReplyAccount))
    }
    if (!normalizedReplyToMessageId.isEmpty()) {
        out.put("replyToMessageId", JsonString(normalizedReplyToMessageId))
    }
    if (replyInThread) {
        out.put("replyInThread", JsonBool(true))
    }
    if (!normalizedExtraSystemPrompt.isEmpty()) {
        out.put("extraSystemPrompt", JsonString(normalizedExtraSystemPrompt))
    }
    if (!normalizedIdempotencyKey.isEmpty()) {
        out.put("idempotencyKey", JsonString(normalizedIdempotencyKey))
    }
    if (!normalizedDeclaredUser.isEmpty()) {
        out.put("declaredUser", JsonString(normalizedDeclaredUser))
    }
    if (!operatorScopes.isEmpty()) {
        out.put("operatorScopes", operatorScopes.toJsonValue())
    }
    out
}

public func gatewayResolveSessionContext(request: GatewaySessionRequest): GatewaySessionContext {
    let sourceLabel = gatewayIngressSourceLabel(request.source)
    let channelName = gatewayNormalizeChannelName(request.channelName, request.source)
    let explicitSessionHint = request.sessionHint.trimAscii().toAsciiLower()
    let hintedAgentId = gatewayHintedAgentId(explicitSessionHint)
    let mediaRoute = gatewayRouteFromMediaContext(request.mediaContext)
    let routedAgentId = gatewaySessionRouteString(mediaRoute, "agentId")
    let agentId = gatewaySessionSanitizeAgentId(
        if (!request.agentId.trimAscii().isEmpty()) {
            request.agentId
        } else if (!routedAgentId.isEmpty()) {
            routedAgentId
        } else {
            hintedAgentId
        }
    )
    let derivedSessionKey = match (request.chatType) {
        case Some(chatType) =>
            if (!explicitSessionHint.isEmpty()) {
                explicitSessionHint
            } else {
                gatewayBuildChannelSessionKey(
                    channelName,
                    chatType,
                    request.peerId,
                    request.senderId,
                    conversationId: request.conversationId,
                    dmScope: request.dmScope
                )
            }
        case None =>
            gatewayResolveAgentSessionKey(agentId, explicitSessionHint, request.to, request.lane)
    }
    let routeSessionKey = gatewaySessionRouteString(mediaRoute, "sessionKey")
    let sessionKey = if (!routeSessionKey.isEmpty()) { routeSessionKey } else { derivedSessionKey }
    let routeMainSessionKey = gatewaySessionRouteString(mediaRoute, "mainSessionKey")
    let mainSessionKey = if (!routeMainSessionKey.isEmpty()) {
        routeMainSessionKey
    } else {
        gatewayResolveAgentSessionKey(agentId, "main", "", "")
    }
    let routeMatchedBy = gatewaySessionRouteString(mediaRoute, "matchedBy")
    let matchedBy = if (!routeMatchedBy.isEmpty()) {
        routeMatchedBy
    } else if (!request.agentId.trimAscii().isEmpty()) {
        "request.agentId"
    } else if (!routedAgentId.isEmpty()) {
        "route.agentId"
    } else if (!hintedAgentId.isEmpty()) {
        "sessionHint"
    } else {
        "default"
    }
    let lastRoutePolicy = gatewaySessionRouteString(mediaRoute, "lastRoutePolicy")
    let scope = MetisAgentScope.resolve(
        gatewaySessionScopeRoot(),
        agentId: agentId,
        homeRoot: MetisPaths.homeRootReadOnly(),
        defaultWorkspace: MetisPaths.workspaceRootReadOnly()
    )
    let turnRoute = gatewayBuildTurnRouteContext(
        mediaRoute,
        agentId,
        channelName,
        request.accountId,
        sessionKey,
        mainSessionKey,
        matchedBy,
        lastRoutePolicy
    )
    let turnContext = GatewayTurnContext(
        agentId,
        workspaceDir: gatewaySessionScopeString(scope, "workspaceDir"),
        agentDir: gatewaySessionScopeString(scope, "agentDir"),
        modelsJsonPath: gatewaySessionScopeString(scope, "modelsJsonPath"),
        authProfilesPath: gatewaySessionScopeString(scope, "authProfilesPath"),
        legacyAuthPath: gatewaySessionScopeString(scope, "legacyAuthPath"),
        sessionsDir: gatewaySessionScopeString(scope, "sessionsDir"),
        sessionKey: sessionKey,
        mainSessionKey: mainSessionKey,
        matchedBy: matchedBy,
        lastRoutePolicy: lastRoutePolicy,
        modelRef: gatewaySessionScopeString(scope, "modelRef"),
        channelName: channelName,
        accountId: request.accountId,
        peerId: request.peerId,
        threadId: request.threadId,
        route: turnRoute,
        agentScope: scope
    )
    let deliveryTarget = gatewayResolveDeliveryTarget(request, sessionKey)
    GatewaySessionContext(
        request.source,
        sourceLabel,
        channelName,
        sessionKey,
        agentId,
        accountId: request.accountId,
        lane: request.lane,
        deliveryTarget: deliveryTarget,
        turnContext: Some(turnContext)
    )
}
