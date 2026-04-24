package metis.gateway.runtime

import magic.jsonable.*

import metis.gateway.protocol.{GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED, GATEWAY_ERROR_REMOTE_UNAVAILABLE, GatewayConnectParams, GatewayProtocolRequest, gatewayProtocolDefaultConnect}

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let gatewayClientRuntimeLock = Mutex()
private var gatewayClientRequestSequence: Int64 = 0
private var gatewayClientConnectedById = HashMap<String, Bool>()
private var gatewayClientConnectCountById = HashMap<String, Int64>()
private var gatewayClientReconnectCountById = HashMap<String, Int64>()
private var gatewayClientLastConnectAtById = HashMap<String, Int64>()
private var gatewayClientLastDisconnectAtById = HashMap<String, Int64>()
private var gatewayClientLastRequestIdById = HashMap<String, String>()
private var gatewayClientLastRequestMethodById = HashMap<String, String>()
private var gatewayClientLastRequestAtById = HashMap<String, Int64>()
private var gatewayClientLastResponseAtById = HashMap<String, Int64>()
private var gatewayClientLastErrorById = HashMap<String, String>()
private var gatewayClientLastErrorCodeById = HashMap<String, String>()
private var gatewayClientPendingRequestMethodById = HashMap<String, String>()
private var gatewayClientPendingRequestClientById = HashMap<String, String>()
private var gatewayClientPendingRequestStartedAtById = HashMap<String, Int64>()
private var gatewayClientTimeoutCountById = HashMap<String, Int64>()
private var gatewayClientCancelCountById = HashMap<String, Int64>()
private var gatewayClientChallengeAckCountById = HashMap<String, Int64>()
private var gatewayClientStreamCountById = HashMap<String, Int64>()
private var gatewayClientLastStreamAtById = HashMap<String, Int64>()
private var gatewayClientLastStreamCursorById = HashMap<String, String>()

public class GatewayClient {
    public let clientName: String
    public let mode: String
    public let transport: String
    public let gatewayUrl: String
    public let timeoutMs: Int64
    public let sessionKey: String
    public let sessionHint: String
    public let connectionId: String
    public let capabilities: Array<String>
    public let operatorScopes: Array<String>
    public let authToken: String
    public let authPassword: String
    public let deviceId: String
    public let deviceToken: String
    public let declaredUser: String
    private var connected: Bool = false
    private let connectParams: GatewayConnectParams
    private let transportAdapter: GatewayTransportAdapter

    public init(
        clientName!: String = "cli",
        mode!: String = "local-cli",
        transport!: String = "local",
        gatewayUrl!: String = "local://gateway",
        timeoutMs!: Int64 = 3000,
        sessionKey!: String = "",
        sessionHint!: String = "",
        connectionId!: String = "",
        capabilities!: Array<String> = [],
        operatorScopes!: Array<String> = [],
        authToken!: String = "",
        authPassword!: String = "",
        deviceId!: String = "",
        deviceToken!: String = "",
        declaredUser!: String = ""
    ) {
        this.clientName = clientName
        this.mode = mode
        this.transport = transport
        this.gatewayUrl = gatewayUrl
        this.timeoutMs = timeoutMs
        this.sessionKey = sessionKey
        this.sessionHint = sessionHint
        this.connectionId = connectionId
        this.capabilities = capabilities
        this.operatorScopes = operatorScopes
        this.authToken = authToken
        this.authPassword = authPassword
        this.deviceId = deviceId
        this.deviceToken = deviceToken
        this.declaredUser = declaredUser
        this.transportAdapter = gatewayTransportAdapterForName(
            transport,
            gatewayUrl: gatewayUrl,
            authToken: authToken,
            authPassword: authPassword
        )
        this.connectParams = gatewayProtocolDefaultConnect(
            clientName,
            mode: mode,
            transport: transport,
            gatewayUrl: gatewayUrl,
            timeoutMs: timeoutMs,
            sessionKey: sessionKey,
            sessionHint: sessionHint,
            connectionId: connectionId,
            capabilities: capabilities,
            operatorScopes: operatorScopes,
            authToken: authToken,
            authPassword: authPassword,
            deviceId: deviceId,
            deviceToken: deviceToken,
            declaredUser: declaredUser
        )
    }

    public func connect(): Bool {
        let hadConnectedBefore = synchronized(gatewayClientRuntimeLock) {
            match (gatewayClientConnectCountById.get(this.connectParams.client.id)) {
                case Some(v) => v > 0
                case None => false
            }
        }
        let ok = this.transportAdapter.connect(this.connectParams)
        this.connected = ok
        gatewayClientRecordConnectResult(this.connectParams.client.id, ok, hadConnectedBefore)
        ok
    }

    public func request(method: String, params!: JsonObject = JsonObject()): GatewayRpcResponse {
        gatewayClientCleanupExpiredPending(this.connectParams.client.id, this.timeoutMs)
        if (!this.connected) {
            let ok = this.connect()
            if (!ok) {
                return GatewayRpcResponse(false, method, error: "Gateway client connect failed.", errorCode: "CONNECT_FAILED")
            }
        }
        let requestId = gatewayClientNextRequestId(this.connectParams.client.id, method)
        let req = GatewayProtocolRequest(
            method,
            this.connectParams,
            params: params,
            requestId: requestId
        )
        gatewayClientRegisterPending(this.connectParams.client.id, requestId, method)
        var res = this.transportAdapter.request(req)
        if (!res.ok && res.errorCode == GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED) {
            let ack = this.acknowledgeConnectChallenge(res.details)
            if (ack.ok) {
                res = this.transportAdapter.request(req)
            }
        } else if (!res.ok && res.errorCode == GATEWAY_ERROR_REMOTE_UNAVAILABLE && this.transport != "local") {
            let ok = this.connect()
            if (ok) {
                res = this.transportAdapter.request(req)
            }
        }
        gatewayClientCompletePending(this.connectParams.client.id, requestId, method, res.ok, res.error, res.errorCode)
        GatewayRpcResponse(
            res.ok,
            res.method,
            requestId: requestId,
            result: res.result,
            error: res.error,
            errorCode: res.errorCode,
            details: res.details
        )
    }

    public func call(method: String, params!: JsonObject = JsonObject()): GatewayRpcResponse {
        this.request(method, params: params)
    }

    public func stopAndWait(timeoutMs!: Int64 = 1000): Bool {
        let ok = this.transportAdapter.stopAndWait(this.connectParams.client.id, timeoutMs)
        if (ok) {
            this.connected = false
            gatewayClientRecordDisconnect(this.connectParams.client.id)
        }
        ok
    }

    public func runtimeSnapshot(): JsonObject {
        gatewayClientRuntimeSnapshot(this.connectParams.client.id)
    }

    public func cancel(requestId: String): GatewayRpcResponse {
        let params = JsonObject()
        params.put("requestId", requestId.trimAscii().toJsonValue())
        let response = this.request("request.cancel", params: params)
        if (response.ok) {
            synchronized(gatewayClientRuntimeLock) {
                gatewayClientCancelCountById[this.connectParams.client.id] =
                    gatewayClientIntOr(this.connectParams.client.id, gatewayClientCancelCountById, 0) + 1
            }
        }
        response
    }

    public func pullEvents(limit!: Int64 = 32): GatewayRpcResponse {
        let params = JsonObject()
        params.put("limit", limit.toJsonValue())
        this.request("events.pull", params: params)
    }

    public func streamEvents(limit!: Int64 = 32, waitMs!: Int64 = 0, sinceId!: String = "", close!: Bool = false): GatewayRpcResponse {
        let params = JsonObject()
        params.put("limit", limit.toJsonValue())
        params.put("waitMs", waitMs.toJsonValue())
        if (!sinceId.trimAscii().isEmpty()) {
            params.put("sinceId", sinceId.trimAscii().toJsonValue())
        }
        if (close) {
            params.put("close", true.toJsonValue())
        }
        let response = this.request("events.stream", params: params)
        if (response.ok) {
            synchronized(gatewayClientRuntimeLock) {
                let clientId = this.connectParams.client.id
                gatewayClientStreamCountById[clientId] = gatewayClientIntOr(clientId, gatewayClientStreamCountById, 0) + 1
                gatewayClientLastStreamAtById[clientId] = gatewayClientNowMs()
                let cursor = gatewayClientExtractNextCursor(response.result)
                if (!cursor.isEmpty()) {
                    gatewayClientLastStreamCursorById[clientId] = cursor
                }
            }
        }
        response
    }

    public func closeStream(): GatewayRpcResponse {
        this.streamEvents(limit: 0, waitMs: 0, close: true)
    }

    public func nextStream(waitMs!: Int64 = 0): GatewayRpcResponse {
        let sinceId = synchronized(gatewayClientRuntimeLock) {
            gatewayClientStringOr(this.connectParams.client.id, gatewayClientLastStreamCursorById, "")
        }
        this.streamEvents(limit: 1, waitMs: waitMs, sinceId: sinceId)
    }

    public func attachStream(waitMs!: Int64 = 0): GatewayRpcResponse {
        let params = JsonObject()
        params.put("waitMs", waitMs.toJsonValue())
        params.put("attach", true.toJsonValue())
        let response = this.request("events.stream", params: params)
        if (response.ok) {
            synchronized(gatewayClientRuntimeLock) {
                let clientId = this.connectParams.client.id
                gatewayClientStreamCountById[clientId] = gatewayClientIntOr(clientId, gatewayClientStreamCountById, 0) + 1
                gatewayClientLastStreamAtById[clientId] = gatewayClientNowMs()
            }
        }
        response
    }

    public func detachStream(): GatewayRpcResponse {
        let params = JsonObject()
        params.put("detach", true.toJsonValue())
        this.request("events.stream", params: params)
    }

    private func acknowledgeConnectChallenge(details: JsonValue): GatewayRpcResponse {
        let token = try {
            let obj = details.asObject()
            match (obj.get("challengeToken")) {
                case Some(v) =>
                    try { v.asString().getValue() } catch (_inner: Exception) { "" }
                case None => ""
            }
        } catch (_e: Exception) {
            ""
        }
        let params = JsonObject()
        params.put("challengeToken", token.trimAscii().toJsonValue())
        let response = this.transportAdapter.request(
            GatewayProtocolRequest(
                "connect.ack",
                this.connectParams,
                params: params,
                requestId: gatewayClientNextRequestId(this.connectParams.client.id, "connect.ack")
            )
        )
        if (response.ok) {
            synchronized(gatewayClientRuntimeLock) {
                gatewayClientChallengeAckCountById[this.connectParams.client.id] =
                    gatewayClientIntOr(this.connectParams.client.id, gatewayClientChallengeAckCountById, 0) + 1
            }
        }
        GatewayRpcResponse(
            response.ok,
            response.method,
            requestId: response.requestId,
            result: response.result,
            error: response.error,
            errorCode: response.errorCode,
            details: response.details
        )
    }
}

public func gatewayClientRuntimeSnapshot(clientId: String): JsonObject {
    synchronized(gatewayClientRuntimeLock) {
        let normalized = clientId.trimAscii()
        let result = JsonObject()
        result.put("clientId", JsonString(normalized))
        result.put("connected", gatewayClientBoolOr(normalized, gatewayClientConnectedById, false).toJsonValue())
        result.put("connectCount", gatewayClientIntOr(normalized, gatewayClientConnectCountById, 0).toJsonValue())
        result.put("reconnectCount", gatewayClientIntOr(normalized, gatewayClientReconnectCountById, 0).toJsonValue())
        result.put("lastConnectAtMs", gatewayClientIntOr(normalized, gatewayClientLastConnectAtById, 0).toJsonValue())
        result.put("lastDisconnectAtMs", gatewayClientIntOr(normalized, gatewayClientLastDisconnectAtById, 0).toJsonValue())
        result.put("lastRequestId", JsonString(gatewayClientStringOr(normalized, gatewayClientLastRequestIdById, "")))
        result.put("lastRequestMethod", JsonString(gatewayClientStringOr(normalized, gatewayClientLastRequestMethodById, "")))
        result.put("lastRequestAtMs", gatewayClientIntOr(normalized, gatewayClientLastRequestAtById, 0).toJsonValue())
        result.put("lastResponseAtMs", gatewayClientIntOr(normalized, gatewayClientLastResponseAtById, 0).toJsonValue())
        result.put("lastError", JsonString(gatewayClientStringOr(normalized, gatewayClientLastErrorById, "")))
        result.put("lastErrorCode", JsonString(gatewayClientStringOr(normalized, gatewayClientLastErrorCodeById, "")))
        result.put("timeoutCount", gatewayClientIntOr(normalized, gatewayClientTimeoutCountById, 0).toJsonValue())
        result.put("cancelCount", gatewayClientIntOr(normalized, gatewayClientCancelCountById, 0).toJsonValue())
        result.put("challengeAckCount", gatewayClientIntOr(normalized, gatewayClientChallengeAckCountById, 0).toJsonValue())
        result.put("streamCount", gatewayClientIntOr(normalized, gatewayClientStreamCountById, 0).toJsonValue())
        result.put("lastStreamAtMs", gatewayClientIntOr(normalized, gatewayClientLastStreamAtById, 0).toJsonValue())
        result.put("lastStreamCursor", JsonString(gatewayClientStringOr(normalized, gatewayClientLastStreamCursorById, "")))
        let pending = JsonArray([])
        var pendingCount: Int64 = 0
        for ((requestId, pendingClientId) in gatewayClientPendingRequestClientById) {
            if (pendingClientId != normalized) {
                continue
            }
            let row = JsonObject()
            row.put("requestId", JsonString(requestId))
            row.put("method", JsonString(gatewayClientStringOr(requestId, gatewayClientPendingRequestMethodById, "")))
            row.put("startedAtMs", gatewayClientIntOr(requestId, gatewayClientPendingRequestStartedAtById, 0).toJsonValue())
            pending.add(row)
            pendingCount += 1
        }
        result.put("pendingRequestCount", pendingCount.toJsonValue())
        result.put("pendingRequests", pending)
        result
    }
}

private func gatewayClientExtractNextCursor(value: JsonValue): String {
    try {
        let root = value.asObject()
        match (root.get("pull")) {
            case Some(v) =>
                try {
                    let pull = v.asObject()
                    match (pull.get("nextCursor")) {
                        case Some(cursor) =>
                            try { cursor.asString().getValue().trimAscii() } catch (_inner: Exception) { "" }
                        case None => ""
                    }
                } catch (_inner: Exception) {
                    ""
                }
            case None => ""
        }
    } catch (_e: Exception) {
        ""
    }
}

private func gatewayClientCleanupExpiredPending(clientId: String, timeoutMs: Int64): Unit {
    synchronized(gatewayClientRuntimeLock) {
        let now = gatewayClientNowMs()
        let expired = ArrayList<String>()
        for ((requestId, startedAt) in gatewayClientPendingRequestStartedAtById) {
            if (gatewayClientStringOr(requestId, gatewayClientPendingRequestClientById, "") != clientId) {
                continue
            }
            if (timeoutMs > 0 && now - startedAt > timeoutMs) {
                expired.add(requestId)
            }
        }
        for (requestId in expired) {
            gatewayClientPendingRequestClientById.remove(requestId)
            gatewayClientPendingRequestMethodById.remove(requestId)
            gatewayClientPendingRequestStartedAtById.remove(requestId)
        }
        if (!expired.isEmpty()) {
            gatewayClientTimeoutCountById[clientId] = gatewayClientIntOr(clientId, gatewayClientTimeoutCountById, 0) + Int64(expired.size)
            gatewayClientLastErrorById[clientId] = "request-timeout-cleanup"
            gatewayClientLastErrorCodeById[clientId] = "REQUEST_TIMEOUT"
        }
    }
}

private func gatewayClientNextRequestId(clientId: String, method: String): String {
    synchronized(gatewayClientRuntimeLock) {
        gatewayClientRequestSequence += 1
        "gw-${clientId}-${method}-${gatewayClientRequestSequence}"
    }
}

private func gatewayClientRecordConnectResult(clientId: String, ok: Bool, reconnect: Bool): Unit {
    synchronized(gatewayClientRuntimeLock) {
        if (ok) {
            gatewayClientConnectedById[clientId] = true
            gatewayClientConnectCountById[clientId] = gatewayClientIntOr(clientId, gatewayClientConnectCountById, 0) + 1
            if (reconnect) {
                gatewayClientReconnectCountById[clientId] = gatewayClientIntOr(clientId, gatewayClientReconnectCountById, 0) + 1
            }
            gatewayClientLastConnectAtById[clientId] = gatewayClientNowMs()
            gatewayClientLastErrorById[clientId] = ""
            gatewayClientLastErrorCodeById[clientId] = ""
        } else {
            gatewayClientConnectedById[clientId] = false
            gatewayClientLastErrorById[clientId] = "connect-failed"
            gatewayClientLastErrorCodeById[clientId] = "CONNECT_FAILED"
        }
    }
}

private func gatewayClientRegisterPending(clientId: String, requestId: String, method: String): Unit {
    synchronized(gatewayClientRuntimeLock) {
        let now = gatewayClientNowMs()
        gatewayClientPendingRequestClientById[requestId] = clientId
        gatewayClientPendingRequestMethodById[requestId] = method
        gatewayClientPendingRequestStartedAtById[requestId] = now
        gatewayClientLastRequestIdById[clientId] = requestId
        gatewayClientLastRequestMethodById[clientId] = method
        gatewayClientLastRequestAtById[clientId] = now
    }
}

private func gatewayClientCompletePending(
    clientId: String,
    requestId: String,
    method: String,
    ok: Bool,
    error: String,
    errorCode: String
): Unit {
    synchronized(gatewayClientRuntimeLock) {
        gatewayClientPendingRequestClientById.remove(requestId)
        gatewayClientPendingRequestMethodById.remove(requestId)
        gatewayClientPendingRequestStartedAtById.remove(requestId)
        gatewayClientLastRequestIdById[clientId] = requestId
        gatewayClientLastRequestMethodById[clientId] = method
        gatewayClientLastResponseAtById[clientId] = gatewayClientNowMs()
        if (ok) {
            gatewayClientLastErrorById[clientId] = ""
            gatewayClientLastErrorCodeById[clientId] = ""
        } else {
            gatewayClientLastErrorById[clientId] = error
            gatewayClientLastErrorCodeById[clientId] = errorCode
        }
    }
}

private func gatewayClientRecordDisconnect(clientId: String): Unit {
    synchronized(gatewayClientRuntimeLock) {
        gatewayClientConnectedById[clientId] = false
        gatewayClientLastDisconnectAtById[clientId] = gatewayClientNowMs()
    }
}

private func gatewayClientNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func gatewayClientStringOr(key: String, map: HashMap<String, String>, fallback: String): String {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func gatewayClientIntOr(key: String, map: HashMap<String, Int64>, fallback: Int64): Int64 {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func gatewayClientBoolOr(key: String, map: HashMap<String, Bool>, fallback: Bool): Bool {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}
