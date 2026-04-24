package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.core.gatewayFindSessionConversationViewForUser
import metis.gateway.protocol.{GATEWAY_PROTOCOL_VERSION, gatewayClientIdForName}

import std.convert.Parsable

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func gatewayRpcStringParam(obj: JsonObject, keys: Array<String>): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    ""
}

private func gatewayRpcIntParam(obj: JsonObject, keys: Array<String>, defaultValue: Int64): Int64 {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    return Int64.parse(v.toJsonString())
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayRpcBoolParam(obj: JsonObject, keys: Array<String>, defaultValue: Bool): Bool {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    return v.asBool().getValue()
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayFilterRows(rows: JsonArray, clientId: String, sessionKey: String, requestId: String): JsonArray {
    if (clientId.isEmpty() && sessionKey.isEmpty() && requestId.isEmpty()) {
        return rows
    }
    let filtered = JsonArray([])
    for (i in 0..rows.size()) {
        let item = rows[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let rowClientId = gatewayRpcStringParam(obj, ["clientId", "id"])
        let rowSessionKey = gatewayRpcStringParam(obj, ["sessionKey"])
        let rowRequestId = gatewayRpcStringParam(obj, ["requestId"])
        if (!clientId.isEmpty() && rowClientId != clientId) {
            continue
        }
        if (!sessionKey.isEmpty() && rowSessionKey != sessionKey) {
            continue
        }
        if (!requestId.isEmpty() && rowRequestId != requestId) {
            continue
        }
        filtered.add(obj)
    }
    filtered
}

private func gatewayConnectRows(rpc: JsonObject, key: String): JsonArray {
    match (rpc.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

func gatewayConnectObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

func gatewayConnectFirstRow(rows: JsonArray): JsonObject {
    if (rows.size() <= 0) {
        return JsonObject()
    }
    try { rows[0].asObject() } catch (_e: Exception) { JsonObject() }
}

func gatewayConnectStreamSummary(streamRows: JsonArray): JsonObject {
    let first = gatewayConnectFirstRow(streamRows)
    let summary = JsonObject()
    summary.put("streamCount", streamRows.size().toJsonValue())
    summary.put("active", first.get("active") ?? false.toJsonValue())
    summary.put("state", first.get("state") ?? JsonString("idle"))
    summary.put("phase", first.get("phase") ?? JsonString("idle"))
    summary.put("sessionMode", first.get("sessionMode") ?? JsonString(""))
    summary.put("runtimeModel", first.get("runtimeModel") ?? JsonString(""))
    summary.put("attachable", first.get("attachable") ?? false.toJsonValue())
    summary.put("resumable", first.get("resumable") ?? false.toJsonValue())
    summary.put("serverPushCapable", first.get("serverPushCapable") ?? false.toJsonValue())
    summary.put("leaseState", first.get("leaseState") ?? JsonString(""))
    summary.put("streamId", first.get("streamId") ?? JsonString(""))
    summary.put("sessionGeneration", first.get("sessionGeneration") ?? 0.toJsonValue())
    summary.put("attachCount", first.get("attachCount") ?? 0.toJsonValue())
    summary.put("waiterCount", first.get("waiterCount") ?? 0.toJsonValue())
    summary
}

func gatewayConnectSubscriptionSummary(subscriptionRows: JsonArray): JsonObject {
    let first = gatewayConnectFirstRow(subscriptionRows)
    let summary = JsonObject()
    summary.put("subscriptionCount", subscriptionRows.size().toJsonValue())
    summary.put("streamState", first.get("streamState") ?? JsonString("idle"))
    summary.put("streamPhase", first.get("streamPhase") ?? JsonString("idle"))
    summary.put("sessionMode", first.get("sessionMode") ?? JsonString(""))
    summary.put("runtimeModel", first.get("runtimeModel") ?? JsonString(""))
    summary.put("attachable", first.get("attachable") ?? false.toJsonValue())
    summary.put("resumable", first.get("resumable") ?? false.toJsonValue())
    summary.put("leaseState", first.get("leaseState") ?? JsonString(""))
    summary.put("streamId", first.get("streamId") ?? JsonString(""))
    summary.put("sessionGeneration", first.get("sessionGeneration") ?? 0.toJsonValue())
    summary.put("attachCount", first.get("attachCount") ?? 0.toJsonValue())
    summary.put("waiterCount", first.get("waiterCount") ?? 0.toJsonValue())
    summary
}

func gatewayConnectRemoteSummary(transport: JsonObject): JsonObject {
    let remote = gatewayConnectObject(transport, "remote")
    let summary = JsonObject()
    summary.put("connected", remote.get("connected") ?? false.toJsonValue())
    summary.put("phase", remote.get("phase") ?? JsonString("idle"))
    summary.put("policyState", remote.get("policyState") ?? JsonString("idle"))
    summary.put("runtimeModel", remote.get("runtimeModel") ?? JsonString(""))
    summary.put("resumable", remote.get("resumable") ?? false.toJsonValue())
    summary.put("attachable", remote.get("attachable") ?? false.toJsonValue())
    summary.put("serverPushCapable", remote.get("serverPushCapable") ?? false.toJsonValue())
    summary.put("lastError", remote.get("lastError") ?? JsonString(""))
    summary.put("lastProtocolVersion", remote.get("lastProtocolVersion") ?? JsonString(""))
    summary.put("lifecycle", remote.get("lifecycle") ?? JsonArray([]))
    summary
}

func gatewayConnectReconnectSummary(transport: JsonObject): JsonObject {
    let remote = gatewayConnectObject(transport, "remote")
    let summary = JsonObject()
    summary.put("reconnectState", remote.get("reconnectState") ?? JsonString("idle"))
    summary.put("nextRetryAtMs", remote.get("nextRetryAtMs") ?? 0.toJsonValue())
    summary.put("cooldownRemainingMs", remote.get("cooldownRemainingMs") ?? 0.toJsonValue())
    summary.put("eligibleForReconnect", remote.get("eligibleForReconnect") ?? true.toJsonValue())
    summary.put("transitionCount", remote.get("transitionCount") ?? 0.toJsonValue())
    summary.put("lastTransitionAtMs", remote.get("lastTransitionAtMs") ?? 0.toJsonValue())
    summary.put("consecutiveFailureCount", remote.get("consecutiveFailureCount") ?? 0.toJsonValue())
    summary.put("lastFailureAtMs", remote.get("lastFailureAtMs") ?? 0.toJsonValue())
    summary.put("lastSuccessAtMs", remote.get("lastSuccessAtMs") ?? 0.toJsonValue())
    summary.put("lastBackoffMs", remote.get("lastBackoffMs") ?? 0.toJsonValue())
    summary.put("phase", remote.get("phase") ?? JsonString("idle"))
    summary.put("policyState", remote.get("policyState") ?? JsonString("idle"))
    summary.put("connected", remote.get("connected") ?? false.toJsonValue())
    summary
}

private func gatewayConnectFilteredRows(
    rpc: JsonObject,
    key: String,
    clientId: String,
    sessionKey: String,
    requestId: String
): JsonArray {
    gatewayFilterRows(gatewayConnectRows(rpc, key), clientId, sessionKey, requestId)
}

func gatewayConnectSessionKeyForClient(rpc: JsonObject, clientId: String): String {
    let normalizedClientId = clientId.trimAscii()
    if (normalizedClientId.isEmpty()) {
        return ""
    }
    let rows = match (rpc.get("sessionBindings")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..rows.size()) {
        let row = try {
            rows[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let ids = match (row.get("clientIds")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        for (j in 0..ids.size()) {
            let candidate = try {
                ids[j].asString().getValue().trimAscii()
            } catch (_e: Exception) {
                ""
            }
            if (candidate == normalizedClientId) {
                return gatewayRpcStringParam(row, ["sessionKey"])
            }
        }
    }
    ""
}

func gatewayConnectAppendSessionProjection(row: JsonObject, sessionKey: String): Unit {
    let normalized = sessionKey.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    let user = GatewayUserSettings()
    match (gatewayFindSessionConversationViewForUser(user, normalized)) {
        case Some(view) =>
            row.put("sessionKey", JsonString(normalized))
            row.put("agentId", JsonString(view.agentId))
            row.put("displayName", JsonString(view.displayName))
            row.put("channel", JsonString(view.channel))
            row.put("chatType", JsonString(view.chatType))
            row.put("peer", JsonString(view.peer))
            row.put("sessionId", JsonString(view.sessionId))
            row.put("origin", view.origin)
            row.put("delivery", view.delivery)
            row.put("binding", view.binding)
        case None => ()
    }
}

func gatewayConnectAppendProjectionForClient(rpc: JsonObject, row: JsonObject, clientId: String): Unit {
    gatewayConnectAppendSessionProjection(row, gatewayConnectSessionKeyForClient(rpc, clientId))
}

func gatewayConnectProjectedSessionKey(
    requestedSessionKey: String,
    streamRows: JsonArray,
    subscriptionRows: JsonArray
): String {
    let requested = requestedSessionKey.trimAscii()
    if (!requested.isEmpty()) {
        return requested
    }
    for (rows in [streamRows, subscriptionRows]) {
        if (rows.size() == 0) {
            continue
        }
        let row = try {
            rows[0].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let candidate = gatewayRpcStringParam(row, ["sessionKey"])
        if (!candidate.isEmpty()) {
            return candidate
        }
    }
    ""
}

func gatewayConnectAppendProjectionForFirstRow(result: JsonObject, rows: JsonArray, requestedSessionKey: String): Unit {
    let projected = gatewayConnectProjectedSessionKey(requestedSessionKey, rows, JsonArray([]))
    gatewayConnectAppendSessionProjection(result, projected)
}

func gatewayConnectAppendProjectionForRows(
    result: JsonObject,
    requestedSessionKey: String,
    streamRows!: JsonArray = JsonArray([]),
    subscriptionRows!: JsonArray = JsonArray([]),
    fallbackRows!: JsonArray = JsonArray([])
): Unit {
    gatewayConnectAppendSessionProjection(
        result,
        gatewayConnectProjectedSessionKey(
            requestedSessionKey,
            if (streamRows.size() > 0) { streamRows } else { fallbackRows },
            subscriptionRows
        )
    )
    if (result.get("sessionKey").isNone() && fallbackRows.size() > 0) {
        gatewayConnectAppendProjectionForFirstRow(result, fallbackRows, requestedSessionKey)
    }
}

func gatewayConnectActionsJson(rpc: JsonObject, clientId: String, sessionKey: String, requestId: String): JsonArray {
    let actions = JsonArray([])
    let clients = gatewayConnectFilteredRows(rpc, "clients", clientId, sessionKey, requestId)
    let streams = gatewayConnectFilteredRows(rpc, "eventStreams", clientId, sessionKey, requestId)
    let challenges = gatewayConnectFilteredRows(rpc, "challengeRegistry", clientId, sessionKey, requestId)
    let hasClient = clients.size() > 0
    if (!hasClient) {
        let row = JsonObject()
        row.put("action", JsonString("reconnect"))
        row.put("method", JsonString("connect.reconnect"))
        row.put("policyState", JsonString("disconnected"))
        let params = JsonObject()
        if (!clientId.isEmpty()) {
            params.put("clientId", JsonString(clientId))
        }
        row.put("params", params)
        gatewayConnectAppendSessionProjection(row, sessionKey)
        actions.add(row)
    }
    if (challenges.size() > 0) {
        let challenge = try {
            challenges[0].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let pending = match (challenge.get("pending")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        if (pending) {
            let row = JsonObject()
            row.put("action", JsonString("ack-challenge"))
            row.put("method", JsonString("connect.ack"))
            row.put("policyState", JsonString("challenge-pending"))
            let params = JsonObject()
            params.put("clientId", JsonString(gatewayRpcStringParam(challenge, ["clientId", "id"])))
            params.put("token", challenge.get("token") ?? JsonString(""))
            row.put("params", params)
            gatewayConnectAppendProjectionForClient(rpc, row, gatewayRpcStringParam(challenge, ["clientId", "id"]))
            actions.add(row)
        }
    }
    if (streams.size() == 0 || !hasClient) {
        let row = JsonObject()
        row.put("action", JsonString("open-stream"))
        row.put("method", JsonString("connect.stream.open"))
        row.put("policyState", JsonString(if (hasClient) { "ready" } else { "connect-required" }))
        let params = JsonObject()
        if (!clientId.isEmpty()) {
            params.put("clientId", JsonString(clientId))
        }
        row.put("params", params)
        gatewayConnectAppendSessionProjection(row, sessionKey)
        actions.add(row)
    } else {
        let stream = try {
            streams[0].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let streamPhase = gatewayRpcStringParam(stream, ["phase", "streamPhase"])
        let row = JsonObject()
        row.put("action", JsonString("keepalive-stream"))
        row.put("method", JsonString("connect.stream.keepalive"))
        row.put("policyState", JsonString(streamPhase))
        row.put("stream", stream)
        let params = JsonObject()
        let streamClientId = gatewayRpcStringParam(stream, ["clientId", "id"])
        if (!streamClientId.isEmpty()) {
            params.put("clientId", JsonString(streamClientId))
        }
        row.put("params", params)
        gatewayConnectAppendProjectionForClient(rpc, row, streamClientId)
        actions.add(row)
        if (streamPhase == "expired" || streamPhase == "detached" || streamPhase == "queued") {
            let resume = JsonObject()
            resume.put("action", JsonString("resume-stream"))
            resume.put("method", JsonString("connect.stream.resume"))
            resume.put("policyState", JsonString(streamPhase))
            resume.put("stream", stream)
            resume.put("params", params)
            gatewayConnectAppendProjectionForClient(rpc, resume, streamClientId)
            actions.add(resume)
        }
        let close = JsonObject()
        close.put("action", JsonString("close-stream"))
        close.put("method", JsonString("connect.stream.close"))
        close.put("policyState", JsonString(streamPhase))
        close.put("stream", stream)
        close.put("params", params)
        gatewayConnectAppendProjectionForClient(rpc, close, streamClientId)
        actions.add(close)
    }
    actions
}

public func handleGatewayConnectFamily(method: String, request!: Option<GatewayRpcRequest> = None): Option<GatewayRpcResponse> {
    let normalized = method.trimAscii().toAsciiLower()
    let rpc = gatewayServerRuntimeSnapshot()
    let requestValue = match (request) {
        case Some(v) => v
        case None => GatewayRpcRequest(method)
    }
    let clientId = gatewayRpcStringParam(requestValue.params, ["clientId", "client", "id"])
    let sessionKey = gatewayRpcStringParam(requestValue.params, ["sessionKey", "session"])
    let requestId = gatewayRpcStringParam(requestValue.params, ["requestId"])
    if (normalized == "connect.status") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        result.put("rpc", rpc)
        result.put("transport", rpc.get("transport") ?? JsonObject())
        result.put("connections", rpc.get("clients") ?? JsonArray([]))
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.summary") {
        let result = JsonObject()
        let connections = gatewayConnectRows(rpc, "clients")
        let challenges = gatewayConnectRows(rpc, "challengeRegistry")
        let events = gatewayConnectRows(rpc, "eventQueues")
        let requests = gatewayConnectRows(rpc, "activeRequestRegistry")
        let transport = gatewayConnectObject(rpc, "transport")
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        result.put("connectionCount", connections.size().toJsonValue())
        result.put("challengeCount", challenges.size().toJsonValue())
        result.put("eventQueueCount", events.size().toJsonValue())
        let history = gatewayConnectRows(rpc, "eventHistory")
        let subscriptions = gatewayConnectRows(rpc, "eventSubscriptions")
        result.put("eventHistoryCount", history.size().toJsonValue())
        result.put("subscriptionCount", subscriptions.size().toJsonValue())
        result.put("activeRequestCount", requests.size().toJsonValue())
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.ping") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        result.put("ok", true.toJsonValue())
        result.put("serverStarted", rpc.get("serverStarted") ?? false.toJsonValue())
        result.put("clientCount", rpc.get("clientCount") ?? 0.toJsonValue())
        result.put("lastRequestAtMs", rpc.get("lastRequestAtMs") ?? 0.toJsonValue())
        result.put("transport", rpc.get("transport") ?? JsonObject())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.client") {
        let result = JsonObject()
        let filtered = gatewayConnectFilteredRows(rpc, "clients", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForFirstRow(result, filtered, sessionKey)
        let client = if (filtered.size() > 0) { filtered[0] } else { JsonObject() }
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        result.put("client", client)
        result.put("connections", filtered)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.challenge") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filtered = gatewayConnectFilteredRows(rpc, "challengeRegistry", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForFirstRow(result, filtered, sessionKey)
        result.put("challengeRegistry", filtered)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.events") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let pull = GatewayServer.defaultServer().pullEvents(
            targetClientId,
            limit: gatewayRpcIntParam(requestValue.params, ["limit"], 32),
            sinceId: gatewayRpcStringParam(requestValue.params, ["sinceId", "cursor", "lastEventId"]),
            peek: gatewayRpcBoolParam(requestValue.params, ["peek"], true)
        )
        let filteredQueues = gatewayConnectFilteredRows(rpc, "eventQueues", clientId, sessionKey, requestId)
        let filteredHistory = gatewayConnectFilteredRows(rpc, "eventHistory", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForRows(result, sessionKey, fallbackRows: filteredHistory)
        if (result.get("sessionKey").isNone()) {
            gatewayConnectAppendProjectionForRows(result, sessionKey, fallbackRows: filteredQueues)
        }
        result.put("eventQueues", filteredQueues)
        result.put("eventHistory", filteredHistory)
        result.put("pull", pull)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.subscriptions") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filtered = gatewayConnectFilteredRows(rpc, "eventSubscriptions", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForFirstRow(result, filtered, sessionKey)
        result.put("eventSubscriptions", filtered)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream" || normalized == "connect.stream.open") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let stream = GatewayServer.defaultServer().streamEvents(
            targetClientId,
            limit: gatewayRpcIntParam(requestValue.params, ["limit"], 32),
            sinceId: gatewayRpcStringParam(requestValue.params, ["sinceId", "cursor", "lastEventId"]),
            waitMs: gatewayRpcIntParam(requestValue.params, ["waitMs"], 0),
            close: gatewayRpcBoolParam(requestValue.params, ["close"], false)
        )
        gatewayConnectAppendProjectionForClient(rpc, stream, targetClientId)
        result.put("stream", stream)
        result.put("opened", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.attach") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let stream = GatewayServer.defaultServer().attachStream(
            targetClientId,
            waitMs: gatewayRpcIntParam(requestValue.params, ["waitMs"], 0)
        )
        gatewayConnectAppendProjectionForClient(rpc, stream, targetClientId)
        result.put("stream", stream)
        result.put("attached", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.detach") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let stream = GatewayServer.defaultServer().detachStream(targetClientId)
        gatewayConnectAppendProjectionForClient(rpc, stream, targetClientId)
        result.put("stream", stream)
        result.put("detached", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.close") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let stream = GatewayServer.defaultServer().streamEvents(
            targetClientId,
            limit: 0,
            sinceId: gatewayRpcStringParam(requestValue.params, ["sinceId", "cursor", "lastEventId"]),
            waitMs: 0,
            close: true
        )
        gatewayConnectAppendProjectionForClient(rpc, stream, targetClientId)
        result.put("stream", stream)
        result.put("closed", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.keepalive") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let stream = GatewayServer.defaultServer().keepaliveStream(targetClientId)
        gatewayConnectAppendProjectionForClient(rpc, stream, targetClientId)
        result.put("stream", stream)
        result.put("keepalive", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.resume") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let resumed = GatewayServer.defaultServer().resumeStream(
            targetClientId,
            limit: gatewayRpcIntParam(requestValue.params, ["limit"], 32),
            waitMs: gatewayRpcIntParam(requestValue.params, ["waitMs"], 0)
        )
        match (resumed.get("stream")) {
            case Some(v) =>
                try {
                    gatewayConnectAppendProjectionForClient(rpc, v.asObject(), targetClientId)
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        result.put("stream", resumed.get("stream") ?? JsonObject())
        result.put("pull", resumed.get("pull") ?? JsonObject())
        result.put("resumed", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.next") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let next = GatewayServer.defaultServer().nextStream(
            targetClientId,
            waitMs: gatewayRpcIntParam(requestValue.params, ["waitMs"], 0)
        )
        match (next.get("stream")) {
            case Some(v) =>
                try {
                    gatewayConnectAppendProjectionForClient(rpc, v.asObject(), targetClientId)
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        result.put("stream", next.get("stream") ?? JsonObject())
        result.put("pull", next.get("pull") ?? JsonObject())
        result.put("next", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.push") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let targetClientId = if (clientId.isEmpty()) { gatewayClientIdForName(requestValue.clientName) } else { clientId }
        let pushed = GatewayServer.defaultServer().pushStream(
            targetClientId,
            kind: gatewayRpcStringParam(requestValue.params, ["kind", "eventKind"]),
            detail: gatewayRpcStringParam(requestValue.params, ["detail", "message"])
        )
        gatewayConnectAppendProjectionForClient(rpc, pushed, targetClientId)
        result.put("stream", pushed)
        result.put("pushed", true.toJsonValue())
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.streams") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filtered = gatewayConnectFilteredRows(rpc, "eventStreams", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForFirstRow(result, filtered, sessionKey)
        result.put("eventStreams", filtered)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.status") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filteredStreams = gatewayConnectFilteredRows(rpc, "eventStreams", clientId, sessionKey, requestId)
        let filteredSubscriptions = gatewayConnectFilteredRows(rpc, "eventSubscriptions", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForRows(result, sessionKey, streamRows: filteredStreams, subscriptionRows: filteredSubscriptions)
        result.put("stream", if (filteredStreams.size() > 0) { filteredStreams[0] } else { JsonObject() })
        result.put("subscription", if (filteredSubscriptions.size() > 0) { filteredSubscriptions[0] } else { JsonObject() })
        result.put("streamSummary", gatewayConnectStreamSummary(filteredStreams))
        result.put("subscriptionSummary", gatewayConnectSubscriptionSummary(filteredSubscriptions))
        result.put("eventStreams", filteredStreams)
        result.put("eventSubscriptions", filteredSubscriptions)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.stream.session") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filteredStreams = gatewayConnectFilteredRows(rpc, "eventStreams", clientId, sessionKey, requestId)
        let filteredSubscriptions = gatewayConnectFilteredRows(rpc, "eventSubscriptions", clientId, sessionKey, requestId)
        let session = JsonObject()
        gatewayConnectAppendProjectionForRows(session, sessionKey, streamRows: filteredStreams, subscriptionRows: filteredSubscriptions)
        session.put("stream", if (filteredStreams.size() > 0) { filteredStreams[0] } else { JsonObject() })
        session.put("subscription", if (filteredSubscriptions.size() > 0) { filteredSubscriptions[0] } else { JsonObject() })
        session.put("streamSummary", gatewayConnectStreamSummary(filteredStreams))
        session.put("subscriptionSummary", gatewayConnectSubscriptionSummary(filteredSubscriptions))
        result.put("session", session)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.lifecycle") {
        let result = JsonObject()
        let transport = gatewayConnectObject(rpc, "transport")
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filteredHistory = gatewayConnectFilteredRows(rpc, "eventHistory", clientId, sessionKey, requestId)
        let filteredSubscriptions = gatewayConnectFilteredRows(rpc, "eventSubscriptions", clientId, sessionKey, requestId)
        let filteredStreams = gatewayConnectFilteredRows(rpc, "eventStreams", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForRows(result, sessionKey, streamRows: filteredStreams, subscriptionRows: filteredSubscriptions, fallbackRows: filteredHistory)
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        result.put("eventHistory", filteredHistory)
        result.put("eventSubscriptions", filteredSubscriptions)
        result.put("eventStreams", filteredStreams)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.actions") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        result.put("actions", gatewayConnectActionsJson(rpc, clientId, sessionKey, requestId))
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.bindings") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filtered = gatewayConnectFilteredRows(rpc, "sessionBindings", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForFirstRow(result, filtered, sessionKey)
        result.put("sessionBindings", filtered)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.requests") {
        let result = JsonObject()
        result.put("protocolVersion", rpc.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        let filtered = gatewayConnectFilteredRows(rpc, "activeRequestRegistry", clientId, sessionKey, requestId)
        gatewayConnectAppendProjectionForFirstRow(result, filtered, sessionKey)
        result.put("activeRequestRegistry", filtered)
        return Some(GatewayRpcResponse(true, normalized, result: result))
    }
    if (normalized == "connect.reconnect") {
        let result = JsonObject()
        let targetClientId = if (clientId.isEmpty()) { "cli" } else { clientId }
        let disconnected = GatewayServer.defaultServer().stopAndWait(clientId: targetClientId, timeoutMs: 1000)
        let runtimeAfter = gatewayServerRuntimeSnapshot()
        result.put("clientId", JsonString(targetClientId))
        result.put("reconnected", disconnected.toJsonValue())
        result.put("protocolVersion", runtimeAfter.get("protocolVersion") ?? JsonString(GATEWAY_PROTOCOL_VERSION))
        result.put("transport", runtimeAfter.get("transport") ?? JsonObject())
        result.put("rpc", runtimeAfter)
        return Some(GatewayRpcResponse(disconnected, normalized, result: result, error: if (disconnected) { "" } else { "Failed to recycle client connection." }))
    }
    if (normalized == "connect.disconnect") {
        let result = JsonObject()
        let targetClientId = if (clientId.isEmpty()) { "cli" } else { clientId }
        let ok = GatewayServer.defaultServer().stopAndWait(clientId: targetClientId, timeoutMs: 1000)
        result.put("clientId", JsonString(targetClientId))
        result.put("disconnected", ok.toJsonValue())
        result.put("protocolVersion", JsonString(GATEWAY_PROTOCOL_VERSION))
        return Some(GatewayRpcResponse(ok, normalized, result: result, error: if (ok) { "" } else { "Failed to disconnect client." }))
    }
    None
}
