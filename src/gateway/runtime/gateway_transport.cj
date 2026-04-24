package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{CliConfig, CliSettingManager}
import metis.core.config.GatewayUserSettings

import metis.gateway.{gatewayRuntimeEffectiveAuthPassword, gatewayRuntimeEffectiveAuthToken}
import metis.gateway.protocol.{GATEWAY_ERROR_INVALID_RESPONSE, GATEWAY_ERROR_REMOTE_UNAVAILABLE, GatewayClientInfo, GatewayConnectParams, GatewayProtocolRequest, GatewayProtocolResponse}
import magic.utils.http.HttpUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{File, exists}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let gatewayTransportRuntimeLock = Mutex()
private var gatewayRemoteConnectCountByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteRequestCountByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteRetryCountByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteFailureCountByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastFailureAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastSuccessAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastBackoffMsByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastErrorByEndpoint = HashMap<String, String>()
private var gatewayRemoteLastConnectAttemptAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastRequestAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastReconnectAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastDisconnectAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteConnectedByEndpoint = HashMap<String, Bool>()
private var gatewayRemoteReconnectStateByEndpoint = HashMap<String, String>()
private var gatewayRemoteNextRetryAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastProtocolVersionByEndpoint = HashMap<String, String>()
private var gatewayRemoteLifecycleByEndpoint = HashMap<String, ArrayList<JsonObject>>()
private var gatewayRemoteTransitionCountByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteLastTransitionAtByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteConsecutiveFailureCountByEndpoint = HashMap<String, Int64>()
private var gatewayRemoteStableConnectedAtByEndpoint = HashMap<String, Int64>()
private var gatewayTransportRuntimeLoaded = false
private let gatewayRemoteStableWindowMs: Int64 = 1500

public interface GatewayTransportAdapter {
    func connect(params: GatewayConnectParams): Bool
    func request(req: GatewayProtocolRequest): GatewayProtocolResponse
    func stopAndWait(clientId: String, timeoutMs: Int64): Bool
    func transportName(): String
}

public class LocalGatewayTransportAdapter <: GatewayTransportAdapter {
    public init() {}

    public func connect(params: GatewayConnectParams): Bool {
        GatewayServer.defaultServer().connect(params)
    }

    public func request(req: GatewayProtocolRequest): GatewayProtocolResponse {
        GatewayServer.defaultServer().request(req)
    }

    public func stopAndWait(clientId: String, timeoutMs: Int64): Bool {
        GatewayServer.defaultServer().stopAndWait(clientId: clientId, timeoutMs: timeoutMs)
    }

    public func transportName(): String {
        "local"
    }
}

public class RemoteGatewayTransportAdapter <: GatewayTransportAdapter {
    private let endpoint: String
    private let timeoutMs: Int64
    private let authToken: String
    private let authPassword: String

    public init(
        endpoint: String,
        timeoutMs!: Int64 = 3000,
        authToken!: String = "",
        authPassword!: String = ""
    ) {
        this.endpoint = endpoint
        this.timeoutMs = timeoutMs
        this.authToken = authToken
        this.authPassword = authPassword
    }

    public func connect(params: GatewayConnectParams): Bool {
        synchronized(gatewayTransportRuntimeLock) {
            gatewayEnsureTransportStateLoadedLocked()
        }
        let cooldownRemaining = synchronized(gatewayTransportRuntimeLock) {
            gatewayRemoteCooldownRemainingMsUnlocked(this.endpoint)
        }
        if (cooldownRemaining > 0) {
            return false
        }
        let reconnecting = synchronized(gatewayTransportRuntimeLock) {
            gatewayTransportIntOr(this.endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0) > 0
        }
        gatewayRemoteSetState(this.endpoint, if (reconnecting) { "reconnecting" } else { "connecting" })
        gatewayRemoteRecordConnectAttempt(this.endpoint)
        let probe = GatewayProtocolRequest("connect", params, requestId: "remote-connect-${params.client.id}")
        let res = this.sendRemoteRequest(probe)
        gatewayRemoteRecordConnectResult(this.endpoint, res)
        res.ok
    }

    public func request(req: GatewayProtocolRequest): GatewayProtocolResponse {
        synchronized(gatewayTransportRuntimeLock) {
            gatewayEnsureTransportStateLoadedLocked()
        }
        let rpcUrl = remoteGatewayRpcUrl(this.endpoint)
        if (rpcUrl.isEmpty()) {
            return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Unsupported remote gateway URL.", errorCode: GATEWAY_ERROR_REMOTE_UNAVAILABLE)
        }
        let cooldownRemaining = synchronized(gatewayTransportRuntimeLock) {
            gatewayRemoteCooldownRemainingMsUnlocked(this.endpoint)
        }
        if (cooldownRemaining > 0) {
            let details = JsonObject()
            details.put("cooldownRemainingMs", cooldownRemaining.toJsonValue())
            details.put("phase", JsonString(synchronized(gatewayTransportRuntimeLock) { gatewayRemotePhaseUnlocked(this.endpoint) }))
            return GatewayProtocolResponse(
                false,
                req.method,
                requestId: req.requestId,
                error: "Remote gateway reconnect cooldown is active.",
                errorCode: GATEWAY_ERROR_REMOTE_UNAVAILABLE,
                details: details
            )
        }
        let maxAttempts = 2
        let reconnecting = synchronized(gatewayTransportRuntimeLock) {
            gatewayTransportIntOr(this.endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0) > 0 &&
            !gatewayTransportBoolOr(this.endpoint, gatewayRemoteConnectedByEndpoint, false)
        }
        if (req.method != "connect" &&
            req.method != "disconnect" &&
            synchronized(gatewayTransportRuntimeLock) { gatewayRemoteEligibleForReconnectUnlocked(this.endpoint) } &&
            !synchronized(gatewayTransportRuntimeLock) { gatewayTransportBoolOr(this.endpoint, gatewayRemoteConnectedByEndpoint, false) }) {
            gatewayRemoteSetState(this.endpoint, "reconnecting")
            gatewayRemoteRecordConnectAttempt(this.endpoint)
            let connectResponse = this.sendRemoteRequest(
                GatewayProtocolRequest("connect", req.connect, requestId: "remote-reconnect-${req.connect.client.id}")
            )
            gatewayRemoteRecordConnectResult(this.endpoint, connectResponse)
            if (!connectResponse.ok) {
                return connectResponse
            }
        }
        gatewayRemoteSetState(this.endpoint, if (reconnecting) { "reconnecting" } else { "requesting" })
        var lastResponse = GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Remote gateway request failed.", errorCode: GATEWAY_ERROR_REMOTE_UNAVAILABLE)
        for (attempt in 0..maxAttempts) {
            gatewayRemoteRecordRequestAttempt(this.endpoint)
            lastResponse = this.sendRemoteRequest(req)
            if (!lastResponse.ok && lastResponse.errorCode == GATEWAY_ERROR_REMOTE_UNAVAILABLE && attempt < maxAttempts - 1) {
                gatewayRemoteRecordRetry(this.endpoint, 250 * Int64(attempt + 1), lastResponse.error, lastResponse.errorCode)
                continue
            }
            if (lastResponse.ok) {
                gatewayRemoteRecordResult(this.endpoint, lastResponse)
                return lastResponse
            }
            if (attempt < maxAttempts - 1 && gatewayRemoteRetryable(lastResponse.errorCode)) {
                gatewayRemoteRecordRetry(this.endpoint, 250 * Int64(attempt + 1), lastResponse.error, lastResponse.errorCode)
                continue
            }
            gatewayRemoteRecordResult(this.endpoint, lastResponse)
            return lastResponse
        }
        lastResponse
    }

    private func sendRemoteRequest(req: GatewayProtocolRequest): GatewayProtocolResponse {
        let rpcUrl = remoteGatewayRpcUrl(this.endpoint)
        if (rpcUrl.isEmpty()) {
            return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Unsupported remote gateway URL.", errorCode: GATEWAY_ERROR_REMOTE_UNAVAILABLE)
        }
        let headers = HashMap<String, String>()
        headers["Content-Type"] = "application/json"
        if (!this.authToken.trimAscii().isEmpty()) {
            headers["X-Metis-Gateway-Token"] = this.authToken.trimAscii()
        }
        if (!this.authPassword.trimAscii().isEmpty()) {
            headers["X-Metis-Gateway-Password"] = this.authPassword.trimAscii()
        }
        let rawOpt = try {
            HttpUtils.post(rpcUrl, headers, req.toJson(), verify: false)
        } catch (e: Exception) {
            return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Remote gateway request failed: ${e.message}", errorCode: GATEWAY_ERROR_REMOTE_UNAVAILABLE)
        }
        let raw = match (rawOpt) {
            case Some(v) => v
            case None =>
                return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Empty remote gateway response.", errorCode: GATEWAY_ERROR_REMOTE_UNAVAILABLE)
        }
        parseGatewayProtocolResponse(raw, req.method, req.requestId)
    }

    public func stopAndWait(clientId: String, timeoutMs: Int64): Bool {
        gatewayRemoteSetState(this.endpoint, "disconnecting")
        let res = this.request(
            GatewayProtocolRequest(
                "disconnect",
                GatewayConnectParams(
                    GatewayClientInfo(clientId, name: clientId, mode: "remote-rpc"),
                    transport: "remote",
                    transportKind: "remote",
                    gatewayUrl: this.endpoint,
                    timeoutMs: timeoutMs,
                    connectionId: clientId
                ),
                requestId: "remote-disconnect-${clientId}"
            )
        )
        if (res.ok) {
            gatewayRemoteSetState(this.endpoint, "disconnected")
            synchronized(gatewayTransportRuntimeLock) {
                gatewayRemoteConnectedByEndpoint[this.endpoint] = false
                gatewayRemoteLastDisconnectAtByEndpoint[this.endpoint] = gatewayTransportNowMs()
                gatewayRemoteAppendLifecycleLocked(this.endpoint, "disconnect", detail: clientId.trimAscii())
                gatewayPersistTransportStateLocked()
            }
        }
        res.ok
    }

    public func transportName(): String {
        "remote"
    }
}

public func gatewayTransportAdapterForName(
    name: String,
    gatewayUrl!: String = "",
    authToken!: String = "",
    authPassword!: String = ""
): GatewayTransportAdapter {
    let normalized = name.trimAscii().toAsciiLower()
    if (normalized == "local" || normalized == "local-rpc" || normalized.isEmpty()) {
        return LocalGatewayTransportAdapter()
    }
    let user = CliSettingManager.readGatewaySettings()
    let resolvedGatewayUrl = if (!gatewayUrl.trimAscii().isEmpty()) {
        gatewayUrl.trimAscii()
    } else {
        gatewayPreferredGatewayUrlFromSettings(user)
    }
    let resolvedAuthToken = if (!authToken.trimAscii().isEmpty()) {
        authToken.trimAscii()
    } else {
        gatewayPreferredAuthTokenFromSettings(user)
    }
    let resolvedAuthPassword = if (!authPassword.trimAscii().isEmpty()) {
        authPassword.trimAscii()
    } else {
        gatewayPreferredAuthPasswordFromSettings(user)
    }
    RemoteGatewayTransportAdapter(
        resolvedGatewayUrl,
        timeoutMs: 3000,
        authToken: resolvedAuthToken,
        authPassword: resolvedAuthPassword
    )
}

public func gatewayPreferredTransportFromSettings(user: GatewayUserSettings): String {
    if (user.remote.enabled && !user.remote.transport.trimAscii().isEmpty()) {
        return user.remote.transport.trimAscii().toAsciiLower()
    }
    "local"
}

public func gatewayPreferredGatewayUrlFromSettings(user: GatewayUserSettings): String {
    if (user.remote.enabled && !user.remote.url.trimAscii().isEmpty()) {
        return user.remote.url.trimAscii()
    }
    "local://gateway"
}

public func gatewayPreferredAuthTokenFromSettings(user: GatewayUserSettings): String {
    if (user.remote.enabled && !user.remote.token.trimAscii().isEmpty()) {
        return user.remote.token.trimAscii()
    }
    let effectiveToken = gatewayRuntimeEffectiveAuthToken(user).trimAscii()
    if (!effectiveToken.isEmpty()) {
        return effectiveToken
    }
    ""
}

public func gatewayPreferredAuthPasswordFromSettings(user: GatewayUserSettings): String {
    if (user.remote.enabled && !user.remote.password.trimAscii().isEmpty()) {
        return user.remote.password.trimAscii()
    }
    let effectivePassword = gatewayRuntimeEffectiveAuthPassword(user).trimAscii()
    if (!effectivePassword.isEmpty()) {
        return effectivePassword
    }
    ""
}

public func gatewayBuildClient(
    clientName: String,
    mode: String,
    sessionKey!: String = "",
    sessionHint!: String = "",
    connectionId!: String = "",
    capabilities!: Array<String> = [],
    operatorScopes!: Array<String> = []
): GatewayClient {
    let user = CliSettingManager.readGatewaySettings()
    GatewayClient(
        clientName: clientName,
        mode: mode,
        transport: gatewayPreferredTransportFromSettings(user),
        gatewayUrl: gatewayPreferredGatewayUrlFromSettings(user),
        sessionKey: sessionKey,
        sessionHint: sessionHint,
        connectionId: connectionId,
        capabilities: capabilities,
        operatorScopes: operatorScopes,
        authToken: gatewayPreferredAuthTokenFromSettings(user),
        authPassword: gatewayPreferredAuthPasswordFromSettings(user)
    )
}

public func gatewayTransportRuntimeSnapshot(user: GatewayUserSettings): JsonObject {
    gatewayTransportRuntimeSnapshotFor(gatewayPreferredTransportFromSettings(user), gatewayPreferredGatewayUrlFromSettings(user))
}

public func gatewayTransportRuntimeSnapshotFor(preferred: String, gatewayUrl: String): JsonObject {
    let result = JsonObject()
    result.put("preferred", preferred.toJsonValue())
    result.put("gatewayUrl", gatewayUrl.toJsonValue())
    result.put("statePath", JsonString(gatewayTransportStatePath()))
    result.put("runtimeModel", JsonString(if (preferred == "remote" || preferred == "http" || preferred == "https") { "persistent-session-lease" } else { "local-rpc" }))
    if (preferred == "remote" || preferred == "http" || preferred == "https") {
        result.put("remote", gatewayRemoteRuntimeSnapshot(gatewayUrl))
    } else {
        result.put("remote", JsonObject())
    }
    result
}

public func gatewayTransportReconnectPlan(user: GatewayUserSettings): JsonObject {
    gatewayTransportReconnectPlanFor(gatewayPreferredTransportFromSettings(user), gatewayPreferredGatewayUrlFromSettings(user))
}

public func gatewayTransportReconnectPlanFor(preferred: String, gatewayUrl: String): JsonObject {
    let runtime = gatewayTransportRuntimeSnapshotFor(preferred, gatewayUrl)
    let result = JsonObject()
    result.put("preferred", runtime.get("preferred") ?? JsonString("local"))
    result.put("gatewayUrl", runtime.get("gatewayUrl") ?? JsonString(""))
    result.put("runtimeModel", runtime.get("runtimeModel") ?? JsonString("local-rpc"))
    let remote = match (runtime.get("remote")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    result.put("reconnectState", remote.get("reconnectState") ?? JsonString("idle"))
    result.put("nextRetryAtMs", remote.get("nextRetryAtMs") ?? 0.toJsonValue())
    result.put("lastBackoffMs", remote.get("lastBackoffMs") ?? 0.toJsonValue())
    result.put("cooldownRemainingMs", remote.get("cooldownRemainingMs") ?? 0.toJsonValue())
    result.put("eligibleForReconnect", remote.get("eligibleForReconnect") ?? true.toJsonValue())
    result.put("phase", remote.get("phase") ?? JsonString("idle"))
    result.put("policyState", remote.get("policyState") ?? JsonString("idle"))
    result.put("connected", remote.get("connected") ?? false.toJsonValue())
    result.put("lifecycle", remote.get("lifecycle") ?? JsonArray([]))
    result
}

public func gatewayTransportResetReconnectPlan(user: GatewayUserSettings): JsonObject {
    gatewayTransportResetReconnectPlanFor(gatewayPreferredTransportFromSettings(user), gatewayPreferredGatewayUrlFromSettings(user))
}

public func gatewayTransportResetReconnectPlanFor(preferred: String, gatewayUrl: String): JsonObject {
    if (preferred != "remote" && preferred != "http" && preferred != "https") {
        return gatewayTransportReconnectPlanFor(preferred, gatewayUrl)
    }
    synchronized(gatewayTransportRuntimeLock) {
        gatewayEnsureTransportStateLoadedLocked()
        gatewayRemoteReconnectStateByEndpoint[gatewayUrl] = "idle"
        gatewayRemoteNextRetryAtByEndpoint[gatewayUrl] = 0
        gatewayRemoteLastBackoffMsByEndpoint[gatewayUrl] = 0
        gatewayRemoteAppendLifecycleLocked(gatewayUrl, "reconnect.reset", detail: gatewayUrl)
        gatewayPersistTransportStateLocked()
    }
    gatewayTransportReconnectPlanFor(preferred, gatewayUrl)
}

public func gatewayTransportStatePath(): String {
    CliConfig.dotDir.join("gateway-transport-state.json").toString()
}

private func remoteGatewayRpcUrl(endpoint: String): String {
    let trimmed = endpoint.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
        if (trimmed.endsWith("/rpc")) {
            return trimmed
        }
        if (trimmed.endsWith("/")) {
            return trimmed + "rpc"
        }
        return trimmed + "/rpc"
    }
    ""
}

private func parseGatewayProtocolResponse(raw: String, fallbackMethod: String, fallbackRequestId: String): GatewayProtocolResponse {
    let root = try {
        JsonValue.fromStr(raw).asObject()
    } catch (_e: Exception) {
        return GatewayProtocolResponse(false, fallbackMethod, requestId: fallbackRequestId, error: "Invalid remote gateway response.", errorCode: GATEWAY_ERROR_INVALID_RESPONSE)
    }
    let protocolVersion = match (root.get("protocolVersion")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    let ok = match (root.get("ok")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let method = match (root.get("method")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { fallbackMethod }
        case None => fallbackMethod
    }
    let requestId = match (root.get("requestId")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { fallbackRequestId }
        case None => fallbackRequestId
    }
    if (ok) {
        return GatewayProtocolResponse(
            true,
            method,
            protocolVersion: protocolVersion,
            requestId: requestId,
            result: root.get("result") ?? JsonObject()
        )
    }
    let error = match (root.get("error")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "Remote gateway error." }
        case None => "Remote gateway error."
    }
    let errorCode = match (root.get("errorCode")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { GATEWAY_ERROR_INVALID_RESPONSE }
        case None => GATEWAY_ERROR_INVALID_RESPONSE
    }
    let details = root.get("details") ?? JsonObject()
    GatewayProtocolResponse(
        false,
        method,
        protocolVersion: protocolVersion,
        requestId: requestId,
        error: error,
        errorCode: errorCode,
        details: details
    )
}

private func gatewayRemoteRetryable(errorCode: String): Bool {
    errorCode == GATEWAY_ERROR_REMOTE_UNAVAILABLE || errorCode == GATEWAY_ERROR_INVALID_RESPONSE
}

private func gatewayRemoteRuntimeSnapshot(endpoint: String): JsonObject {
    synchronized(gatewayTransportRuntimeLock) {
        gatewayEnsureTransportStateLoadedLocked()
        gatewayRemoteRuntimeSnapshotUnlocked(endpoint)
    }
}

private func gatewayEnsureTransportStateLoadedLocked(): Unit {
    if (gatewayTransportRuntimeLoaded) {
        return
    }
    gatewayTransportRuntimeLoaded = true
    let path = CliConfig.dotDir.join("gateway-transport-state.json")
    if (!exists(path)) {
        return
    }
    let root = try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_e: Exception) {
        return
    }
    let endpoints = match (root.get("endpoints")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..endpoints.size()) {
        let endpointJson = endpoints[i]
        let snapshot = try {
            endpointJson.asObject()
        } catch (_e: Exception) {
            continue
        }
        let endpoint = gatewayTransportJsonString(snapshot, "endpoint", "")
        if (endpoint.isEmpty()) {
            continue
        }
        gatewayRemoteConnectCountByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "connectCount")
        gatewayRemoteRequestCountByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "requestCount")
        gatewayRemoteRetryCountByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "retryCount")
        gatewayRemoteFailureCountByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "failureCount")
        gatewayRemoteLastFailureAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastFailureAtMs")
        gatewayRemoteLastSuccessAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastSuccessAtMs")
        gatewayRemoteLastBackoffMsByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastBackoffMs")
        gatewayRemoteLastErrorByEndpoint[endpoint] = gatewayTransportJsonString(snapshot, "lastError", "")
        gatewayRemoteLastConnectAttemptAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastConnectAttemptAtMs")
        gatewayRemoteLastRequestAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastRequestAtMs")
        gatewayRemoteLastReconnectAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastReconnectAtMs")
        gatewayRemoteLastDisconnectAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastDisconnectAtMs")
        gatewayRemoteConnectedByEndpoint[endpoint] = gatewayTransportJsonBool(snapshot, "connected")
        gatewayRemoteReconnectStateByEndpoint[endpoint] = gatewayTransportJsonString(snapshot, "reconnectState", "idle")
        gatewayRemoteNextRetryAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "nextRetryAtMs")
        gatewayRemoteLastProtocolVersionByEndpoint[endpoint] = gatewayTransportJsonString(snapshot, "lastProtocolVersion", "")
        gatewayRemoteTransitionCountByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "transitionCount")
        gatewayRemoteLastTransitionAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "lastTransitionAtMs")
        gatewayRemoteConsecutiveFailureCountByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "consecutiveFailureCount")
        gatewayRemoteStableConnectedAtByEndpoint[endpoint] = gatewayTransportJsonInt(snapshot, "stableConnectedAtMs")
        let lifecycle = ArrayList<JsonObject>()
        let lifecycleJson = match (snapshot.get("lifecycle")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        for (j in 0..lifecycleJson.size()) {
            let item = try {
                lifecycleJson[j].asObject()
            } catch (_e: Exception) {
                continue
            }
            lifecycle.add(item)
        }
        gatewayRemoteLifecycleByEndpoint[endpoint] = lifecycle
    }
}

private func gatewayTransportJsonString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayTransportJsonInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayTransportJsonBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayRemoteRecordConnectAttempt(endpoint: String): Unit {
    synchronized(gatewayTransportRuntimeLock) {
        gatewayRemoteConnectCountByEndpoint[endpoint] = gatewayTransportIntOr(endpoint, gatewayRemoteConnectCountByEndpoint, 0) + 1
        gatewayRemoteLastConnectAttemptAtByEndpoint[endpoint] = gatewayTransportNowMs()
        gatewayRemoteAppendLifecycleLocked(endpoint, "connect.attempt", detail: endpoint)
        gatewayPersistTransportStateLocked()
    }
}

private func gatewayRemoteRecordRequestAttempt(endpoint: String): Unit {
    synchronized(gatewayTransportRuntimeLock) {
        gatewayRemoteRequestCountByEndpoint[endpoint] = gatewayTransportIntOr(endpoint, gatewayRemoteRequestCountByEndpoint, 0) + 1
        gatewayRemoteLastRequestAtByEndpoint[endpoint] = gatewayTransportNowMs()
        gatewayPersistTransportStateLocked()
    }
}

private func gatewayRemoteRecordRetry(endpoint: String, backoffMs: Int64, error: String, errorCode: String): Unit {
    synchronized(gatewayTransportRuntimeLock) {
        gatewayRemoteRetryCountByEndpoint[endpoint] = gatewayTransportIntOr(endpoint, gatewayRemoteRetryCountByEndpoint, 0) + 1
        gatewayRemoteConsecutiveFailureCountByEndpoint[endpoint] =
            gatewayTransportIntOr(endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0) + 1
        gatewayRemoteLastBackoffMsByEndpoint[endpoint] = backoffMs
        gatewayRemoteNextRetryAtByEndpoint[endpoint] = gatewayTransportNowMs() + backoffMs
        gatewayRemoteLastErrorByEndpoint[endpoint] = error
        gatewayRemoteReconnectStateByEndpoint[endpoint] = "backoff"
        gatewayRemoteConnectedByEndpoint[endpoint] = false
        gatewayRemoteLastReconnectAtByEndpoint[endpoint] = gatewayTransportNowMs()
        gatewayRemoteAppendLifecycleLocked(endpoint, "retry", detail: errorCode)
        gatewayPersistTransportStateLocked()
    }
}

private func gatewayRemoteRecordResult(endpoint: String, response: GatewayProtocolResponse): Unit {
    synchronized(gatewayTransportRuntimeLock) {
        let previousFailures = gatewayTransportIntOr(endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0)
        if (response.ok) {
            let wasConnected = gatewayTransportBoolOr(endpoint, gatewayRemoteConnectedByEndpoint, false)
            let now = gatewayTransportNowMs()
            gatewayRemoteLastSuccessAtByEndpoint[endpoint] = gatewayTransportNowMs()
            gatewayRemoteLastErrorByEndpoint[endpoint] = ""
            gatewayRemoteLastBackoffMsByEndpoint[endpoint] = 0
            gatewayRemoteNextRetryAtByEndpoint[endpoint] = 0
            gatewayRemoteConnectedByEndpoint[endpoint] = true
            gatewayRemoteConsecutiveFailureCountByEndpoint[endpoint] = 0
            if (!wasConnected || previousFailures > 0) {
                gatewayRemoteStableConnectedAtByEndpoint[endpoint] = now
            }
            gatewayRemoteReconnectStateByEndpoint[endpoint] =
                if (previousFailures > 0 && now - gatewayTransportIntOr(endpoint, gatewayRemoteStableConnectedAtByEndpoint, now) < gatewayRemoteStableWindowMs) { "recovering" } else { "connected" }
            gatewayRemoteLastProtocolVersionByEndpoint[endpoint] = response.protocolVersion
            gatewayRemoteAppendLifecycleLocked(endpoint, "request.ok", detail: response.method)
        } else {
            gatewayRemoteFailureCountByEndpoint[endpoint] = gatewayTransportIntOr(endpoint, gatewayRemoteFailureCountByEndpoint, 0) + 1
            gatewayRemoteConsecutiveFailureCountByEndpoint[endpoint] =
                gatewayTransportIntOr(endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0) + 1
            gatewayRemoteLastFailureAtByEndpoint[endpoint] = gatewayTransportNowMs()
            gatewayRemoteLastErrorByEndpoint[endpoint] = response.error
            gatewayRemoteConnectedByEndpoint[endpoint] = false
            gatewayRemoteReconnectStateByEndpoint[endpoint] = "error"
            gatewayRemoteLastProtocolVersionByEndpoint[endpoint] = response.protocolVersion
            gatewayRemoteAppendLifecycleLocked(endpoint, "request.error", detail: response.errorCode)
        }
        gatewayPersistTransportStateLocked()
    }
}

private func gatewayRemoteRecordConnectResult(endpoint: String, response: GatewayProtocolResponse): Unit {
    synchronized(gatewayTransportRuntimeLock) {
        let wasConnected = gatewayTransportBoolOr(endpoint, gatewayRemoteConnectedByEndpoint, false)
        let previousFailures = gatewayTransportIntOr(endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0)
        let now = gatewayTransportNowMs()
        gatewayRemoteLastProtocolVersionByEndpoint[endpoint] = response.protocolVersion
        gatewayRemoteConnectedByEndpoint[endpoint] = response.ok
        gatewayRemoteReconnectStateByEndpoint[endpoint] = if (response.ok) {
            if (previousFailures > 0) { "recovering" } else { "connected" }
        } else {
            "error"
        }
        if (response.ok) {
            gatewayRemoteConsecutiveFailureCountByEndpoint[endpoint] = 0
            gatewayRemoteLastSuccessAtByEndpoint[endpoint] = now
            if (!wasConnected || previousFailures > 0) {
                gatewayRemoteStableConnectedAtByEndpoint[endpoint] = now
            }
            gatewayRemoteAppendLifecycleLocked(endpoint, "connect.ok", detail: response.method)
        } else {
            gatewayRemoteConsecutiveFailureCountByEndpoint[endpoint] =
                gatewayTransportIntOr(endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0) + 1
            gatewayRemoteAppendLifecycleLocked(endpoint, "connect.error", detail: response.errorCode)
        }
        gatewayPersistTransportStateLocked()
    }
}

private func gatewayRemoteSetState(endpoint: String, state: String): Unit {
    synchronized(gatewayTransportRuntimeLock) {
        let previous = gatewayTransportStringOr(endpoint, gatewayRemoteReconnectStateByEndpoint, "")
        gatewayRemoteReconnectStateByEndpoint[endpoint] = state
        if (previous != state) {
            gatewayRemoteTransitionCountByEndpoint[endpoint] =
                gatewayTransportIntOr(endpoint, gatewayRemoteTransitionCountByEndpoint, 0) + 1
            gatewayRemoteLastTransitionAtByEndpoint[endpoint] = gatewayTransportNowMs()
            gatewayRemoteAppendLifecycleLocked(endpoint, "state.${state}", detail: previous)
        }
        gatewayPersistTransportStateLocked()
    }
}

private func gatewayPersistTransportStateLocked(): Unit {
    let root = JsonObject()
    root.put("updatedAtMs", gatewayTransportNowMs().toJsonValue())
    let endpoints = JsonArray([])
    let seen = HashMap<String, Bool>()
    for ((endpoint, _) in gatewayRemoteConnectCountByEndpoint) {
        seen[endpoint] = true
    }
    for ((endpoint, _) in gatewayRemoteRequestCountByEndpoint) {
        seen[endpoint] = true
    }
    for ((endpoint, _) in gatewayRemoteReconnectStateByEndpoint) {
        seen[endpoint] = true
    }
    for ((endpoint, _) in seen) {
        endpoints.add(gatewayRemoteRuntimeSnapshotUnlocked(endpoint))
    }
    root.put("endpoints", endpoints)
    File.writeTo(CliConfig.dotDir.join("gateway-transport-state.json"), root.toJsonString().toArray())
}

private func gatewayRemoteRuntimeSnapshotUnlocked(endpoint: String): JsonObject {
    let result = JsonObject()
    result.put("endpoint", endpoint.toJsonValue())
    result.put("connectCount", gatewayTransportIntOr(endpoint, gatewayRemoteConnectCountByEndpoint, 0).toJsonValue())
    result.put("requestCount", gatewayTransportIntOr(endpoint, gatewayRemoteRequestCountByEndpoint, 0).toJsonValue())
    result.put("retryCount", gatewayTransportIntOr(endpoint, gatewayRemoteRetryCountByEndpoint, 0).toJsonValue())
    result.put("failureCount", gatewayTransportIntOr(endpoint, gatewayRemoteFailureCountByEndpoint, 0).toJsonValue())
    result.put("connected", gatewayTransportBoolOr(endpoint, gatewayRemoteConnectedByEndpoint, false).toJsonValue())
    result.put("reconnectState", gatewayTransportStringOr(endpoint, gatewayRemoteReconnectStateByEndpoint, "idle").toJsonValue())
    result.put("nextRetryAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteNextRetryAtByEndpoint, 0).toJsonValue())
    result.put("lastFailureAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastFailureAtByEndpoint, 0).toJsonValue())
    result.put("lastSuccessAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastSuccessAtByEndpoint, 0).toJsonValue())
    result.put("lastBackoffMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastBackoffMsByEndpoint, 0).toJsonValue())
    result.put("lastConnectAttemptAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastConnectAttemptAtByEndpoint, 0).toJsonValue())
    result.put("lastRequestAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastRequestAtByEndpoint, 0).toJsonValue())
    result.put("lastReconnectAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastReconnectAtByEndpoint, 0).toJsonValue())
    result.put("lastDisconnectAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastDisconnectAtByEndpoint, 0).toJsonValue())
    result.put("transitionCount", gatewayTransportIntOr(endpoint, gatewayRemoteTransitionCountByEndpoint, 0).toJsonValue())
    result.put("lastTransitionAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteLastTransitionAtByEndpoint, 0).toJsonValue())
    result.put("consecutiveFailureCount", gatewayTransportIntOr(endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0).toJsonValue())
    result.put("stableConnectedAtMs", gatewayTransportIntOr(endpoint, gatewayRemoteStableConnectedAtByEndpoint, 0).toJsonValue())
    result.put("cooldownRemainingMs", gatewayRemoteCooldownRemainingMsUnlocked(endpoint).toJsonValue())
    let phase = gatewayRemotePhaseUnlocked(endpoint)
    result.put("phase", JsonString(phase))
    let eligibleForReconnect = gatewayRemoteCooldownRemainingMsUnlocked(endpoint) == 0
    result.put("eligibleForReconnect", eligibleForReconnect.toJsonValue())
    result.put("runtimeModel", JsonString("persistent-session-lease"))
    result.put("resumable", true.toJsonValue())
    result.put("attachable", true.toJsonValue())
    result.put("serverPushCapable", true.toJsonValue())
    result.put("policyState", JsonString(
        if (phase == "stable" || phase == "connected") {
            "steady"
        } else if (phase == "cooldown") {
            "cooldown"
        } else if (phase == "recovering" || phase == "reconnecting" || phase == "degraded") {
            "recovering"
        } else if (eligibleForReconnect) {
            "reconnect-eligible"
        } else {
            phase
        }
    ))
    result.put("lastError", gatewayTransportStringOr(endpoint, gatewayRemoteLastErrorByEndpoint, "").toJsonValue())
    result.put("lastProtocolVersion", gatewayTransportStringOr(endpoint, gatewayRemoteLastProtocolVersionByEndpoint, "").toJsonValue())
    let lifecycle = JsonArray([])
    match (gatewayRemoteLifecycleByEndpoint.get(endpoint)) {
        case Some(items) =>
            for (item in items) {
                lifecycle.add(item)
            }
        case None => ()
    }
    result.put("lifecycle", lifecycle)
    result
}

private func gatewayRemoteCooldownRemainingMsUnlocked(endpoint: String): Int64 {
    let nextRetryAt = gatewayTransportIntOr(endpoint, gatewayRemoteNextRetryAtByEndpoint, 0)
    if (nextRetryAt <= 0) {
        return 0
    }
    let remaining = nextRetryAt - gatewayTransportNowMs()
    if (remaining > 0) { remaining } else { 0 }
}

private func gatewayRemoteEligibleForReconnectUnlocked(endpoint: String): Bool {
    gatewayRemoteCooldownRemainingMsUnlocked(endpoint) == 0 &&
    !gatewayTransportBoolOr(endpoint, gatewayRemoteConnectedByEndpoint, false)
}

private func gatewayRemotePhaseUnlocked(endpoint: String): String {
    let connected = gatewayTransportBoolOr(endpoint, gatewayRemoteConnectedByEndpoint, false)
    let state = gatewayTransportStringOr(endpoint, gatewayRemoteReconnectStateByEndpoint, "idle")
    let cooldownRemaining = gatewayRemoteCooldownRemainingMsUnlocked(endpoint)
    let stableConnectedAt = gatewayTransportIntOr(endpoint, gatewayRemoteStableConnectedAtByEndpoint, 0)
    let consecutiveFailures = gatewayTransportIntOr(endpoint, gatewayRemoteConsecutiveFailureCountByEndpoint, 0)
    if (connected) {
        if (stableConnectedAt > 0 && gatewayTransportNowMs() - stableConnectedAt >= gatewayRemoteStableWindowMs && consecutiveFailures == 0) {
            return "stable"
        }
        if (state == "recovering" || consecutiveFailures > 0) {
            return "recovering"
        }
        return "connected"
    }
    if (cooldownRemaining > 0) {
        return "cooldown"
    }
    if (state == "reconnecting" || state == "connecting" || state == "requesting") {
        return "reconnecting"
    }
    if (state == "disconnecting" || state == "disconnected") {
        return state
    }
    if (consecutiveFailures > 0) {
        return "degraded"
    }
    state
}

private func gatewayRemoteAppendLifecycleLocked(endpoint: String, kind: String, detail!: String = ""): Unit {
    let items = match (gatewayRemoteLifecycleByEndpoint.get(endpoint)) {
        case Some(v) => v
        case None =>
            let created = ArrayList<JsonObject>()
            gatewayRemoteLifecycleByEndpoint[endpoint] = created
            created
    }
    let row = JsonObject()
    row.put("kind", JsonString(kind))
    row.put("detail", JsonString(detail))
    row.put("ts", gatewayTransportNowMs().toJsonValue())
    items.add(row)
    while (items.size > 16) {
        items.remove(at: 0)
    }
}

private func gatewayTransportNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func gatewayTransportIntOr(key: String, map: HashMap<String, Int64>, fallback: Int64): Int64 {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func gatewayTransportStringOr(key: String, map: HashMap<String, String>, fallback: String): String {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func gatewayTransportBoolOr(key: String, map: HashMap<String, Bool>, fallback: Bool): Bool {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}
