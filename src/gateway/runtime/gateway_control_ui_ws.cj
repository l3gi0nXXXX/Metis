package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.CliConfig
import metis.core.config.MetisConfigManager
import metis.core.config.CliSettingManager
import metis.core.memory.{MemoryRuntimeRegistry, parseAgentSessionKey}
import metis.core.skills.{SkillsPrompt, skillsSourceTagForLocation}
import metis.cron.{CronJob, computeJobNextRun, cronLoadOrEmpty, cronStorePath, readCronRunLogMergedFromStore}
import metis.gateway.config.{buildGatewayConfigFromUserSettings, listGatewayChannelCatalogEntries}
import metis.gateway.core.GatewaySessionStore
import metis.gateway.core.{GATEWAY_CONTROL_UI_CLIENT_NAME, GatewaySessionCatalogRow, GatewaySessionCatalogView, GatewaySessionConversationView, gatewayBuildChatEventPayload, gatewayBuildSessionCatalogOrigin, gatewayFindSessionConversationViewForUser, gatewayListSessionConversationViewsForUser, gatewaySessionStoreForSessionKey, gatewaySessionStoreForUserWithAgentId}
import metis.gateway.model.GatewayConfig
import metis.gateway.session.{GatewayIngressSource, gatewayBuildChatHistoryRpcParams, gatewayBuildChatSendRpcParams, gatewayBuildSessionsDeleteRpcParams}
import metis.gateway.protocol.{GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED, GATEWAY_ERROR_INVALID_CONNECT, GATEWAY_ERROR_NOT_CONNECTED, GatewayClientInfo, GatewayConnectParams, GatewayProtocolRequest, GatewayProtocolResponse, validateGatewayConnectParams}
import magic.log.LogUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Directory, File, FileInfo, Path, exists}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}
import stdx.net.http.*

private let gatewayControlUiWsClientIdLock = Mutex()
private var gatewayControlUiWsClientIdSeq: Int64 = 0
private let gatewayControlUiWsConnectionRegistryLock = Mutex()
private var gatewayControlUiWsConnectionRegistry = HashMap<String, GatewayControlUiWsConnection>()
private const GATEWAY_CONTROL_UI_AGENT_FILE_INITIAL_LIMIT: Int64 = 32 * 1024
private const GATEWAY_CONTROL_UI_AGENT_FILE_MAX_LIMIT: Int64 = 256 * 1024

private class GatewayControlUiWsSessionState {
    public var connectParams: Option<GatewayConnectParams> = None<GatewayConnectParams>
    public var closed: Bool = false
    public var registryToken: String = ""
    public var connectionId: String = ""
}

private class GatewayControlUiWsConnection {
    public let token: String
    public let websocket: WebSocket
    public let writeLock: Mutex
    public init(token: String, websocket: WebSocket, writeLock: Mutex) {
        this.token = token
        this.websocket = websocket
        this.writeLock = writeLock
    }
}

private func gatewayControlUiWsNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func gatewayControlUiWsNextClientId(): String {
    synchronized(gatewayControlUiWsClientIdLock) {
        gatewayControlUiWsClientIdSeq += 1
        "control-ui-browser-${gatewayControlUiWsNowMs()}-${gatewayControlUiWsClientIdSeq}"
    }
}

private func gatewayControlUiWsNextConnectionId(clientId: String): String {
    synchronized(gatewayControlUiWsClientIdLock) {
        gatewayControlUiWsClientIdSeq += 1
        let normalized = clientId.trimAscii()
        let prefix = if (normalized.isEmpty()) { "control-ui-browser" } else { normalized }
        "${prefix}-conn-${gatewayControlUiWsNowMs()}-${gatewayControlUiWsClientIdSeq}"
    }
}

private func gatewayControlUiWsString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayControlUiWsObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayControlUiWsBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) {
                let raw = try { v.asString().getValue().trimAscii().toAsciiLower() } catch (_inner: Exception) { "" }
                raw == "true" || raw == "1" || raw == "yes" || raw == "on"
            }
        case None => false
    }
}

private func gatewayControlUiWsInt(obj: JsonObject, key: String, defaultValue: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.toJsonString().trimAscii().replace("\"", ""))
            } catch (_e: Exception) {
                let raw = try { v.asString().getValue().trimAscii() } catch (_inner: Exception) { "" }
                if (raw.isEmpty()) {
                    defaultValue
                } else {
                    try { Int64.parse(raw) } catch (_inner: Exception) { defaultValue }
                }
            }
        case None => defaultValue
    }
}

private func gatewayControlUiWsStringArray(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii()
                        if (!text.isEmpty() && !out.contains(text)) {
                            out.add(text)
                        }
                    } catch (_inner: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_e: Exception) {
                let raw = try { v.asString().getValue() } catch (_inner: Exception) { "" }
                let out = ArrayList<String>()
                for (part in raw.split(",")) {
                    let text = part.trimAscii()
                    if (!text.isEmpty() && !out.contains(text)) {
                        out.add(text)
                    }
                }
                out.toArray()
            }
        case None => []
    }
}

private func gatewayControlUiWsNormalizeChannelError(raw: String): String {
    let normalized = raw.trimAscii()
    if (normalized.isEmpty()) {
        return ""
    }
    let lower = normalized.toAsciiLower()
    if (lower == "manual-stop") {
        return ""
    }
    normalized
}

private func gatewayControlUiWsCompatCapabilities(obj: JsonObject): Array<String> {
    let direct = gatewayControlUiWsStringArray(obj, "capabilities")
    if (!direct.isEmpty()) {
        return direct
    }
    []
}

private func gatewayControlUiWsCompatOperatorScopes(scopes: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (raw in scopes) {
        let normalized = raw.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            continue
        }
        let mapped = if (normalized.startsWith("operator.")) {
            normalized[9..]
        } else {
            normalized
        }
        if (mapped.isEmpty()) {
            continue
        }
        if (!out.contains(mapped)) {
            out.add(mapped)
        }
    }
    out.toArray()
}

private func gatewayControlUiWsResponseFrame(response: GatewayProtocolResponse, frameId: String): JsonObject {
    let out = JsonObject()
    out.put("type", JsonString("res"))
    out.put("id", JsonString(frameId))
    out.put("ok", response.ok.toJsonValue())
    out.put("method", JsonString(response.method))
    if (response.ok) {
        out.put("payload", response.result)
    } else {
        let error = JsonObject()
        error.put("code", JsonString(response.errorCode))
        error.put("message", JsonString(response.error))
        error.put("details", response.details)
        out.put("error", error)
    }
    out
}

private func gatewayControlUiWsEventFrame(event: JsonObject): JsonObject {
    let out = JsonObject()
    out.put("type", JsonString("event"))
    out.put("event", JsonString(gatewayControlUiWsString(event, "kind")))
    let payload = match (event.get("payload")) {
        case Some(v) => v
        case None => event
    }
    out.put("payload", payload)
    out.put("seq", gatewayControlUiWsEventSeqFromId(gatewayControlUiWsString(event, "id")).toJsonValue())
    out
}

private func gatewayControlUiWsEventSeqFromId(eventId: String): Int64 {
    let normalized = eventId.trimAscii()
    if (!normalized.startsWith("evt-")) {
        return 0
    }
    try {
        Int64.parse(normalized[4..])
    } catch (_e: Exception) {
        0
    }
}

private func gatewayControlUiWsWriteJson(websocket: WebSocket, writeLock: Mutex, frame: JsonObject): Unit {
    let payload = frame.toJsonString()
    synchronized(writeLock) {
        websocket.write(TextWebFrame, payload.toArray())
    }
}

private func gatewayControlUiWsRegisterConnection(clientId: String, token: String, websocket: WebSocket, writeLock: Mutex): Unit {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    synchronized(gatewayControlUiWsConnectionRegistryLock) {
        gatewayControlUiWsConnectionRegistry[normalized] = GatewayControlUiWsConnection(token, websocket, writeLock)
    }
}

private func gatewayControlUiWsUnregisterConnection(clientId: String, token: String): Unit {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    synchronized(gatewayControlUiWsConnectionRegistryLock) {
        match (gatewayControlUiWsConnectionRegistry.get(normalized)) {
            case Some(conn) =>
                if (conn.token == token) {
                    gatewayControlUiWsConnectionRegistry.remove(normalized)
                }
            case None => ()
        }
    }
}

private func gatewayControlUiWsDefaultSessionEventKinds(): Array<String> {
    ["session.updated", "session.lifecycle", "session.transcript.updated", "sessions.changed"]
}

private func gatewayControlUiWsEventKindsJson(kinds: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (kind in kinds) {
        let normalized = kind.trimAscii()
        if (!normalized.isEmpty()) {
            arr.add(JsonString(normalized))
        }
    }
    arr
}

public func gatewayControlUiWsWriteGatewayEventToClient(clientId: String, event: JsonObject): Bool {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return false
    }
    let target = synchronized(gatewayControlUiWsConnectionRegistryLock) {
        gatewayControlUiWsConnectionRegistry.get(normalized)
    }
    match (target) {
        case Some(conn) =>
            try {
                gatewayControlUiWsWriteJson(conn.websocket, conn.writeLock, gatewayControlUiWsEventFrame(event))
                true
            } catch (_: Exception) {
                false
            }
        case None => false
    }
}

public func gatewayControlUiWsHasBoundConnection(clientId: String): Bool {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return false
    }
    synchronized(gatewayControlUiWsConnectionRegistryLock) {
        gatewayControlUiWsConnectionRegistry.contains(normalized)
    }
}

private func gatewayControlUiWsWriteJsonToClient(clientId: String, frame: JsonObject): Bool {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return false
    }
    let target = synchronized(gatewayControlUiWsConnectionRegistryLock) {
        gatewayControlUiWsConnectionRegistry.get(normalized)
    }
    match (target) {
        case Some(conn) =>
            try {
                gatewayControlUiWsWriteJson(conn.websocket, conn.writeLock, frame)
                true
            } catch (_e: Exception) {
                false
            }
        case None => false
    }
}

private func gatewayControlUiWsWriteConnectChallenge(websocket: WebSocket, writeLock: Mutex): String {
    let nonce = "gw-${gatewayControlUiWsNowMs()}"
    let payload = JsonObject()
    payload.put("nonce", JsonString(nonce))
    let frame = JsonObject()
    frame.put("type", JsonString("event"))
    frame.put("event", JsonString("connect.challenge"))
    frame.put("payload", payload)
    frame.put("seq", 0.toJsonValue())
    gatewayControlUiWsWriteJson(websocket, writeLock, frame)
    nonce
}

private func gatewayControlUiWsWriteInvalidConnect(websocket: WebSocket, writeLock: Mutex, frameId: String): Unit {
    let response = GatewayProtocolResponse(false, "connect", requestId: frameId, error: "Invalid gateway connect params.", errorCode: GATEWAY_ERROR_INVALID_CONNECT)
    gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
}

private func gatewayControlUiWsMaybeAutoAckChallenge(connect: GatewayConnectParams, response: GatewayProtocolResponse): GatewayProtocolResponse {
    if (!response.ok) {
        return response
    }
    let root = try {
        response.result.asObject()
    } catch (_e: Exception) {
        return response
    }
    let required = match (root.get("connectChallengeRequired")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    if (!required) {
        return response
    }
    let challenge = gatewayControlUiWsObject(root, "challenge")
    let token = gatewayControlUiWsString(challenge, "challengeToken").trimAscii()
    if (token.isEmpty()) {
        return GatewayProtocolResponse(
            false,
            response.method,
            requestId: response.requestId,
            error: "Gateway connect challenge token missing.",
            errorCode: GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED,
            details: root
        )
    }
    let ack = gatewayControlUiWsGatewayAckRequest(connect, token)
    if (!ack.ok) {
        LogUtils.error("Gateway.control-ui.ws: challenge auto-ack failed clientId=${connect.client.id} error=${ack.error}")
        return GatewayProtocolResponse(
            false,
            response.method,
            requestId: response.requestId,
            error: ack.error,
            errorCode: ack.errorCode,
            details: ack.details
        )
    }
    root.put("connectChallengeRequired", false.toJsonValue())
    root.put("challenge", ack.result)
    GatewayProtocolResponse(true, response.method, requestId: response.requestId, result: root)
}

private func gatewayControlUiWsBuildConnectParams(
    cfg: GatewayConfig,
    payload: JsonObject,
    defaultConnectionId: String
): GatewayConnectParams {
    let binding = GatewayControlUiRuntime.controlUiBinding(cfg)
    let client = gatewayControlUiWsObject(payload, "client")
    let auth = gatewayControlUiWsObject(payload, "auth")
    let device = gatewayControlUiWsObject(payload, "device")
    let clientIdFromClient = gatewayControlUiWsString(client, "id").trimAscii()
    let clientIdTopLevel = gatewayControlUiWsString(payload, "clientId").trimAscii()
    let clientId = if (!clientIdFromClient.isEmpty()) {
        clientIdFromClient
    } else if (!clientIdTopLevel.isEmpty()) {
        clientIdTopLevel
    } else {
        gatewayControlUiWsNextClientId()
    }
    let clientNameFromClient = gatewayControlUiWsString(client, "name").trimAscii()
    let clientNameTopLevel = gatewayControlUiWsString(payload, "clientName").trimAscii()
    let clientName = if (!clientNameFromClient.isEmpty()) {
        clientNameFromClient
    } else if (!clientNameTopLevel.isEmpty()) {
        clientNameTopLevel
    } else {
        GATEWAY_CONTROL_UI_CLIENT_NAME
    }
    let clientModeFromClient = gatewayControlUiWsString(client, "mode").trimAscii()
    let clientModeTopLevel = gatewayControlUiWsString(payload, "clientMode").trimAscii()
    let clientMode = if (!clientModeFromClient.isEmpty()) {
        clientModeFromClient
    } else if (!clientModeTopLevel.isEmpty()) {
        clientModeTopLevel
    } else {
        "webchat"
    }
    let clientVersionFromClient = gatewayControlUiWsString(client, "version").trimAscii()
    let clientVersionTopLevel = gatewayControlUiWsString(payload, "clientVersion").trimAscii()
    let clientVersion = if (!clientVersionFromClient.isEmpty()) {
        clientVersionFromClient
    } else if (!clientVersionTopLevel.isEmpty()) {
        clientVersionTopLevel
    } else {
        CliConfig.version
    }
    let sessionKeyRaw = gatewayControlUiWsString(payload, "sessionKey").trimAscii()
    let sessionKeyAlt = gatewayControlUiWsString(payload, "session").trimAscii()
    let sessionKey = if (!sessionKeyRaw.isEmpty()) { sessionKeyRaw } else { sessionKeyAlt }
    let sessionHintRaw = gatewayControlUiWsString(payload, "sessionHint").trimAscii()
    let sessionHintAlt = gatewayControlUiWsString(payload, "conversation").trimAscii()
    let sessionHint = if (!sessionHintRaw.isEmpty()) { sessionHintRaw } else { sessionHintAlt }
    let connectionIdFromClient = gatewayControlUiWsString(client, "instanceId").trimAscii()
    let connectionIdTopLevel = gatewayControlUiWsString(payload, "connectionId").trimAscii()
    let connectionId = if (!connectionIdFromClient.isEmpty()) {
        connectionIdFromClient
    } else if (!connectionIdTopLevel.isEmpty()) {
        connectionIdTopLevel
    } else if (!defaultConnectionId.trimAscii().isEmpty()) {
        defaultConnectionId.trimAscii()
    } else {
        gatewayControlUiWsNextConnectionId(clientId)
    }
    let authTokenNested = gatewayControlUiWsString(auth, "token").trimAscii()
    let authTokenTopLevel = gatewayControlUiWsString(payload, "authToken").trimAscii()
    let authToken = if (!authTokenNested.isEmpty()) { authTokenNested } else { authTokenTopLevel }
    let authPasswordNested = gatewayControlUiWsString(auth, "password").trimAscii()
    let authPasswordTopLevel = gatewayControlUiWsString(payload, "authPassword").trimAscii()
    let authPassword = if (!authPasswordNested.isEmpty()) { authPasswordNested } else { authPasswordTopLevel }
    let deviceIdNested = gatewayControlUiWsString(device, "deviceId").trimAscii()
    let deviceIdTopLevel = gatewayControlUiWsString(payload, "deviceId").trimAscii()
    let deviceId = if (!deviceIdNested.isEmpty()) { deviceIdNested } else { deviceIdTopLevel }
    let deviceTokenPrimary = gatewayControlUiWsString(device, "token").trimAscii()
    let deviceTokenNested = gatewayControlUiWsString(device, "deviceToken").trimAscii()
    let deviceTokenTopLevel = gatewayControlUiWsString(payload, "deviceToken").trimAscii()
    let deviceToken = if (!deviceTokenPrimary.isEmpty()) {
        deviceTokenPrimary
    } else if (!deviceTokenNested.isEmpty()) {
        deviceTokenNested
    } else {
        deviceTokenTopLevel
    }
    let requestedScopes = gatewayControlUiWsStringArray(payload, "scopes")
    let operatorScopes = if (!requestedScopes.isEmpty()) {
        gatewayControlUiWsCompatOperatorScopes(requestedScopes)
    } else {
        gatewayControlUiWsCompatOperatorScopes(gatewayControlUiWsStringArray(payload, "operatorScopes"))
    }
    GatewayConnectParams(
        GatewayClientInfo(clientId, name: clientName, mode: clientMode, version: clientVersion),
        transport: "remote",
        transportKind: "websocket",
        gatewayUrl: binding.wsUrl,
        timeoutMs: 3000,
        requestedAtMs: gatewayControlUiWsNowMs(),
        sessionKey: sessionKey,
        sessionHint: sessionHint,
        connectionId: connectionId,
        capabilities: gatewayControlUiWsCompatCapabilities(payload),
        operatorScopes: operatorScopes,
        authToken: authToken,
        authPassword: authPassword,
        deviceId: deviceId,
        deviceToken: deviceToken,
        declaredUser: gatewayControlUiWsString(payload, "declaredUser").trimAscii()
    )
}

public func gatewayControlUiWsMethodAlias(method: String): String {
    let shared = gatewayDashboardMethodAlias(method)
    if (!shared.isEmpty()) {
        return shared
    }
    let normalized = method.trimAscii().toAsciiLower()
    if (normalized == "skills.status") {
        return "skills.status"
    }
    if (normalized == "skills.compatibilitymatrix") {
        return "skills.compatibilityMatrix"
    }
    if (normalized == "skills.update") {
        return "skills.update"
    }
    if (normalized == "config.schema") {
        return "config.schema"
    }
    normalized
}

public func gatewayControlUiWsRequestParams(method: String, params: JsonObject): JsonObject {
    gatewayDashboardRequestParams(method, params, source: GatewayIngressSource.ControlUi)
}

private func gatewayControlUiWsGatewayRequest(
    connect: GatewayConnectParams,
    frameId: String,
    method: String,
    params!: JsonObject = JsonObject()
): GatewayProtocolResponse {
    let normalizedMethod = gatewayControlUiWsMethodAlias(method)
    let effectiveParams = gatewayControlUiWsRequestParams(normalizedMethod, params)
    GatewayServer.defaultServer().request(
        GatewayProtocolRequest(normalizedMethod, connect, params: effectiveParams, requestId: frameId)
    )
}

private func gatewayControlUiWsSessionSubscribeRequest(
    connect: GatewayConnectParams,
    frameId: String
): GatewayProtocolResponse {
    let eventKinds = gatewayServerSubscribeSessionEvents(connect.client.id, eventKinds: gatewayControlUiWsDefaultSessionEventKinds())
    let result = JsonObject()
    result.put("subscribed", true.toJsonValue())
    result.put("mode", JsonString("direct-websocket"))
    result.put("kinds", gatewayControlUiWsEventKindsJson(eventKinds))
    result.put("cursorMode", JsonString("direct-push"))
    result.put("resumeMethod", JsonString(""))
    result.put("unsubscribeMethod", JsonString("sessions.unsubscribe"))
    GatewayProtocolResponse(true, "sessions.subscribe", requestId: frameId, result: result)
}

private func gatewayControlUiWsSessionUnsubscribeRequest(
    connect: GatewayConnectParams,
    frameId: String
): GatewayProtocolResponse {
    gatewayServerUnsubscribeSessionEvents(connect.client.id)
    let result = JsonObject()
    result.put("subscribed", false.toJsonValue())
    result.put("mode", JsonString("direct-websocket"))
    result.put("kinds", JsonArray([]))
    GatewayProtocolResponse(true, "sessions.unsubscribe", requestId: frameId, result: result)
}

private func gatewayControlUiWsGatewayConnectRequest(
    connect: GatewayConnectParams,
    frameId: String
): GatewayProtocolResponse {
    GatewayServer.defaultServer().request(GatewayProtocolRequest("connect", connect, requestId: frameId))
}

private func gatewayControlUiWsGatewayAckRequest(
    connect: GatewayConnectParams,
    challengeToken: String
): GatewayProtocolResponse {
    let params = JsonObject()
    params.put("challengeToken", JsonString(challengeToken.trimAscii()))
    GatewayServer.defaultServer().request(
        GatewayProtocolRequest("connect.ack", connect, params: params, requestId: "ack-${connect.client.id}")
    )
}

private func gatewayControlUiWsGatewayDisconnectRequest(
    connect: GatewayConnectParams,
    frameId: String
): GatewayProtocolResponse {
    GatewayServer.defaultServer().request(GatewayProtocolRequest("disconnect", connect, requestId: frameId))
}

private func gatewayControlUiWsCurrentGatewayConfig(): GatewayConfig {
    buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
}

private func gatewayControlUiWsCompatHash(raw: String): String {
    "${gatewayControlUiWsNowMs()}-${raw.size}"
}

private func gatewayControlUiWsConfigGetResult(): JsonValue {
    MetisConfigManager.initializeIfMissing()
    let value = match (MetisConfigManager.rawConfig()) {
        case Some(root) => root.toJsonValue()
        case None => JsonObject().toJsonValue()
    }
    let raw = value.toJsonString()
    let result = JsonObject()
    result.put("path", JsonString("gateway"))
    result.put("exists", true.toJsonValue())
    result.put("raw", JsonString(raw))
    result.put("hash", JsonString(gatewayControlUiWsCompatHash(raw)))
    result.put("parsed", value)
    result.put("valid", true.toJsonValue())
    result.put("config", value)
    result.put("issues", JsonArray([]))
    result
}

private func gatewayControlUiWsConfigRoot(): JsonObject {
    MetisConfigManager.initializeIfMissing()
    match (MetisConfigManager.rawConfig()) {
        case Some(root) => root
        case None => JsonObject()
    }
}

private func gatewayControlUiWsAgentConfigEntry(agentId: String): JsonObject {
    let root = gatewayControlUiWsConfigRoot()
    let agentsRoot = gatewayControlUiWsObject(root, "agents")
    let items = try {
        (agentsRoot.get("list") ?? JsonArray([])).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
    let normalized = agentId.trimAscii()
    for (item in items.getItems()) {
        let row = try { item.asObject() } catch (_inner: Exception) { JsonObject() }
        if (gatewayControlUiWsString(row, "id").trimAscii() == normalized) {
            return row
        }
    }
    JsonObject()
}

private func gatewayControlUiWsSchemaNode(kind: String): JsonObject {
    let node = JsonObject()
    node.put("type", JsonString(kind))
    node
}

private func gatewayControlUiWsImageUnderstandingSchema(): JsonObject {
    let props = JsonObject()
    props.put("enabled", gatewayControlUiWsSchemaNode("boolean"))
    props.put("prompt", gatewayControlUiWsSchemaNode("string"))
    props.put("maxBytes", gatewayControlUiWsSchemaNode("integer"))
    props.put("maxChars", gatewayControlUiWsSchemaNode("integer"))
    props.put("timeoutSeconds", gatewayControlUiWsSchemaNode("integer"))
    let modelItemProps = JsonObject()
    modelItemProps.put("provider", gatewayControlUiWsSchemaNode("string"))
    modelItemProps.put("model", gatewayControlUiWsSchemaNode("string"))
    modelItemProps.put("modelRef", gatewayControlUiWsSchemaNode("string"))
    let capabilities = gatewayControlUiWsSchemaNode("array")
    capabilities.put("items", gatewayControlUiWsSchemaNode("string"))
    modelItemProps.put("capabilities", capabilities)
    let modelItem = gatewayControlUiWsSchemaNode("object")
    modelItem.put("additionalProperties", true.toJsonValue())
    modelItem.put("properties", modelItemProps)
    let models = gatewayControlUiWsSchemaNode("array")
    models.put("items", modelItem)
    props.put("models", models)
    let providers = gatewayControlUiWsSchemaNode("object")
    providers.put("additionalProperties", true.toJsonValue())
    props.put("providers", providers)
    props.put("provider", gatewayControlUiWsSchemaNode("string"))
    let schema = gatewayControlUiWsSchemaNode("object")
    schema.put("additionalProperties", true.toJsonValue())
    schema.put("properties", props)
    schema
}

private func gatewayControlUiWsChannelSchemaRoot(): JsonObject {
    let imageSchema = gatewayControlUiWsImageUnderstandingSchema()
    let channelProperties = JsonObject()
    for (channelId in ["whatsapp", "telegram", "discord", "googlechat", "slack", "signal", "imessage", "nostr", "feishu", "qq"]) {
        let channelSchema = JsonObject()
        channelSchema.put("type", JsonString("object"))
        channelSchema.put("additionalProperties", true.toJsonValue())
        channelSchema.put("properties", JsonObject())
        channelProperties.put(channelId, channelSchema)
    }
    for (channelId in ["telegram", "feishu", "qq"]) {
        let channelSchema = channelProperties.get(channelId).getOrThrow().asObject()
        let props = channelSchema.get("properties").getOrThrow().asObject()
        props.put("image", imageSchema)
    }
    let channelsNode = JsonObject()
    channelsNode.put("type", JsonString("object"))
    channelsNode.put("additionalProperties", true.toJsonValue())
    channelsNode.put("properties", channelProperties)
    let imageModelProps = JsonObject()
    imageModelProps.put("primary", gatewayControlUiWsSchemaNode("string"))
    let imageFallbacks = gatewayControlUiWsSchemaNode("array")
    imageFallbacks.put("items", gatewayControlUiWsSchemaNode("string"))
    imageModelProps.put("fallbacks", imageFallbacks)
    let imageModelSchema = gatewayControlUiWsSchemaNode("object")
    imageModelSchema.put("additionalProperties", true.toJsonValue())
    imageModelSchema.put("properties", imageModelProps)
    let defaultsProps = JsonObject()
    defaultsProps.put("imageModel", imageModelSchema)
    let defaultsSchema = gatewayControlUiWsSchemaNode("object")
    defaultsSchema.put("additionalProperties", true.toJsonValue())
    defaultsSchema.put("properties", defaultsProps)
    let agentsProps = JsonObject()
    agentsProps.put("defaults", defaultsSchema)
    let agentsSchema = gatewayControlUiWsSchemaNode("object")
    agentsSchema.put("additionalProperties", true.toJsonValue())
    agentsSchema.put("properties", agentsProps)
    let mediaProps = JsonObject()
    mediaProps.put("image", imageSchema)
    let mediaSchema = gatewayControlUiWsSchemaNode("object")
    mediaSchema.put("additionalProperties", true.toJsonValue())
    mediaSchema.put("properties", mediaProps)
    let gatewayProps = JsonObject()
    gatewayProps.put("media", mediaSchema)
    gatewayProps.put("telegram", channelProperties.get("telegram").getOrThrow())
    gatewayProps.put("feishu", channelProperties.get("feishu").getOrThrow())
    gatewayProps.put("qq", channelProperties.get("qq").getOrThrow())
    let gatewaySchema = gatewayControlUiWsSchemaNode("object")
    gatewaySchema.put("additionalProperties", true.toJsonValue())
    gatewaySchema.put("properties", gatewayProps)
    let rootProps = JsonObject()
    rootProps.put("agents", agentsSchema)
    rootProps.put("gateway", gatewaySchema)
    rootProps.put("channels", channelsNode)
    let schema = JsonObject()
    schema.put("type", JsonString("object"))
    schema.put("properties", rootProps)
    schema.put("additionalProperties", true.toJsonValue())
    schema
}

private func gatewayControlUiWsSystemPresenceResult(cfg: GatewayConfig): JsonValue {
    let platform = gatewayPlatformSnapshot(cfg)
    let nodesRoot = try {
        (platform.get("nodes") ?? JsonObject()).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let items = try {
        (nodesRoot.get("items") ?? JsonArray([])).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
    let result = JsonArray([])
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let entry = JsonObject()
        let nodeId = gatewayControlUiWsString(row, "nodeId").trimAscii()
        entry.put("instanceId", JsonString(if (nodeId.isEmpty()) { "local-gateway" } else { nodeId }))
        entry.put("host", JsonString(gatewayControlUiWsString(row, "host")))
        entry.put("ip", JsonString(gatewayControlUiWsString(row, "ip")))
        entry.put("version", JsonString(gatewayControlUiWsString(row, "version")))
        entry.put("platform", JsonString(gatewayControlUiWsString(row, "platform")))
        entry.put("deviceFamily", JsonString(gatewayControlUiWsString(row, "deviceFamily")))
        entry.put("modelIdentifier", JsonString(gatewayControlUiWsString(row, "modelIdentifier")))
        let roles = JsonArray([])
        roles.add(JsonString("operator"))
        entry.put("roles", roles)
        let scopes = JsonArray([])
        scopes.add(JsonString("operator.admin"))
        scopes.add(JsonString("operator.read"))
        scopes.add(JsonString("operator.write"))
        entry.put("scopes", scopes)
        entry.put("mode", JsonString(gatewayControlUiWsString(row, "mode")))
        entry.put("reason", JsonString(gatewayControlUiWsString(row, "status")))
        entry.put("text", JsonString(gatewayControlUiWsString(row, "detail")))
        entry.put("ts", (row.get("lastHeartbeatAtMs") ?? gatewayControlUiWsNowMs().toJsonValue()))
        result.add(entry)
    }
    result
}

private func gatewayControlUiWsLastHeartbeatResult(cfg: GatewayConfig): JsonValue {
    let runtime = gatewayRuntimeSnapshot()
    let platform = gatewayPlatformSnapshot(cfg)
    let nodesRoot = try {
        (platform.get("nodes") ?? JsonObject()).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let items = try {
        (nodesRoot.get("items") ?? JsonArray([])).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
    var lastHeartbeatAtMs: Int64 = gatewayControlUiWsInt(runtime, "updatedAtMs", 0)
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let seen = gatewayControlUiWsInt(row, "lastHeartbeatAtMs", 0)
        if (seen > lastHeartbeatAtMs) {
            lastHeartbeatAtMs = seen
        }
    }
    let result = JsonObject()
    result.put("ts", lastHeartbeatAtMs.toJsonValue())
    result.put("status", JsonString(gatewayControlUiWsString(runtime, "status")))
    result.put("running", runtime.get("running") ?? false.toJsonValue())
    result.put("reason", JsonString(gatewayControlUiWsString(runtime, "reason")))
    result
}

private func gatewayControlUiWsConfigSchemaResult(params: JsonObject): JsonValue {
    let path = gatewayControlUiWsString(params, "path").trimAscii()
    let result = JsonObject()
    let schema = gatewayControlUiWsChannelSchemaRoot()
    schema.put("title", JsonString(if (path.isEmpty()) { "gateway" } else { path }))
    result.put("schema", schema)
    result.put("uiHints", JsonObject())
    result.put("version", JsonString(CliConfig.version))
    result.put("generatedAt", JsonString(DateTime.now().toString()))
    result
}

private func gatewayControlUiWsSkillsStatusResult(): JsonValue {
    match (handleGatewaySkillsFamily("skills.status")) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            result.put("workspaceDir", JsonString(CliConfig.cwd.join("skills").toString()))
            result.put("managedSkillsDir", JsonString(CliConfig.dotDir.join("skills").toString()))
            result.put("skills", JsonArray([]))
            result
    }
}

private func gatewayControlUiWsSkillsBinsResult(): JsonValue {
    match (handleGatewaySkillsFamily("skills.bins")) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            result.put("bins", JsonArray([]))
            result
    }
}

private func gatewayControlUiWsSkillsDetailResult(params: JsonObject): JsonValue {
    let request = GatewayRpcRequest("skills.detail", params: params)
    match (handleGatewaySkillsFamily("skills.detail", request: Some(request))) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            result.put("skill", JsonObject())
            result
    }
}

private func gatewayControlUiWsSkillsCompatibilityResult(params: JsonObject): JsonValue {
    let request = GatewayRpcRequest("skills.compatibilityMatrix", params: params)
    match (handleGatewaySkillsFamily("skills.compatibilityMatrix", request: Some(request))) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            result.put("kind", JsonString("skills-compatibility-matrix"))
            result.put("summary", JsonObject())
            result.put("rows", JsonArray([]))
            result
    }
}

private func gatewayControlUiWsAgentsRuntimeResult(params: JsonObject): JsonValue {
    let request = GatewayRpcRequest("agents.runtime.profile", params: params)
    match (handleGatewayAgentsFamily("agents.runtime.profile", request: Some(request))) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            let runtime = JsonObject()
            runtime.put("kind", JsonString("gateway-main-runtime-profile"))
            runtime.put("requiredCoreTools", JsonArray([]))
            runtime.put("currentTools", JsonArray([]))
            runtime.put("missingCoreTools", JsonArray([]))
            runtime.put("coversUnifiedCoreBaseline", false.toJsonValue())
            result.put("runtime", runtime)
            result
    }
}

private func gatewayControlUiWsAgentsRuntimeAuditResult(params: JsonObject): JsonValue {
    let request = GatewayRpcRequest("agents.runtime.audit", params: params)
    match (handleGatewayAgentsFamily("agents.runtime.audit", request: Some(request))) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            let audit = JsonObject()
            let summary = JsonObject()
            summary.put("kind", JsonString("gateway-main-runtime-audit"))
            summary.put("phase", JsonString("G8"))
            audit.put("kind", JsonString("gateway-main-runtime-audit"))
            audit.put("summary", summary)
            audit.put("runtime", JsonObject())
            result.put("audit", audit)
            result
    }
}

private func gatewayControlUiWsAgentsFamilyCompatResponse(method: String, params: JsonObject): GatewayProtocolResponse {
    let request = GatewayRpcRequest(method, params: params)
    match (handleGatewayAgentsFamily(method, request: Some(request))) {
        case Some(response) => GatewayProtocolResponse(response.ok, method, result: response.result, error: response.error)
        case None => GatewayProtocolResponse(false, method, error: "Unsupported agents method.", errorCode: "UNSUPPORTED")
    }
}

private func gatewayControlUiWsSkillSourceLabel(location: String): String {
    skillsSourceTagForLocation(location)
}

private func gatewayControlUiWsReadTextFile(path: String): String {
    let p = Path(path)
    if (!exists(p)) {
        return ""
    }
    try {
        String.fromUtf8(File.readFrom(p))
    } catch (_e: Exception) {
        ""
    }
}

private func gatewayControlUiWsExtractSkillField(raw: String, key: String): String {
    let normalizedKey = key.trimAscii().toAsciiLower()
    if (normalizedKey.isEmpty() || raw.trimAscii().isEmpty()) {
        return ""
    }
    for (line0 in raw.split("\n")) {
        let line = line0.trimAscii()
        if (line.isEmpty()) {
            continue
        }
        let lower = line.toAsciiLower()
        let prefix = "${normalizedKey}:"
        if (!lower.startsWith(prefix)) {
            continue
        }
        let value = line[prefix.size..].trimAscii().replace("\"", "").replace("'", "")
        if (!value.isEmpty()) {
            return value
        }
    }
    ""
}

private func gatewayControlUiWsNodeListResult(cfg: GatewayConfig): JsonValue {
    let platform = gatewayPlatformSnapshot(cfg)
    let nodesRoot = try {
        (platform.get("nodes") ?? JsonObject()).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let items = try {
        (nodesRoot.get("items") ?? JsonArray([])).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
    let summarized = JsonArray([])
    var historyTotal: Int64 = 0
    for (i in 0..items.size()) {
        let node = try {
            items[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let history = match (node.get("lifecycleHistory")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        historyTotal += Int64(history.size())
        let row = JsonObject()
        let nodeId = gatewayControlUiWsString(node, "id").trimAscii()
        row.put("id", JsonString(nodeId))
        row.put("nodeId", JsonString(nodeId))
        row.put("kind", JsonString(gatewayControlUiWsString(node, "kind")))
        row.put("running", node.get("running") ?? false.toJsonValue())
        row.put("status", JsonString(gatewayControlUiWsString(node, "status")))
        row.put("lifecycleState", JsonString(gatewayControlUiWsString(node, "lifecycleState")))
        row.put("phase", JsonString(gatewayControlUiWsString(node, "phase")))
        row.put("browserMode", JsonString(gatewayControlUiWsString(node, "browserMode")))
        row.put("browserNode", JsonString(gatewayControlUiWsString(node, "browserNode")))
        row.put("registeredAtMs", node.get("registeredAtMs") ?? 0.toJsonValue())
        row.put("lastHeartbeatAtMs", node.get("lastHeartbeatAtMs") ?? 0.toJsonValue())
        row.put("lastStartedAtMs", node.get("lastStartedAtMs") ?? 0.toJsonValue())
        row.put("lastStoppedAtMs", node.get("lastStoppedAtMs") ?? 0.toJsonValue())
        row.put("transitionCount", node.get("transitionCount") ?? 0.toJsonValue())
        row.put("restartCount", node.get("restartCount") ?? 0.toJsonValue())
        row.put("heartbeatCount", node.get("heartbeatCount") ?? 0.toJsonValue())
        row.put("lifecycleHistoryCount", Int64(history.size()).toJsonValue())
        if (history.size() > 0) {
            row.put("lastLifecycle", history[history.size() - 1])
        }
        summarized.add(row)
    }
    LogUtils.info(
        "Gateway.control-ui.ws: node.list snapshot nodes=${items.size()} lifecycleHistoryTotal=${historyTotal}"
    )
    let result = JsonObject()
    result.put("ts", gatewayControlUiWsNowMs().toJsonValue())
    result.put("nodes", summarized)
    result
}

private func gatewayControlUiWsDevicePairListResult(cfg: GatewayConfig): JsonValue {
    let platform = gatewayPlatformSnapshot(cfg)
    let devicesRoot = try {
        (platform.get("devices") ?? JsonObject()).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let items = try {
        (devicesRoot.get("items") ?? JsonArray([])).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
    let summarized = JsonArray([])
    for (i in 0..items.size()) {
        let device = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let history = match (device.get("authHistory")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let row = JsonObject()
        row.put("id", JsonString(gatewayControlUiWsString(device, "id")))
        row.put("kind", JsonString(gatewayControlUiWsString(device, "kind")))
        row.put("authMode", JsonString(gatewayControlUiWsString(device, "authMode")))
        row.put("status", JsonString(gatewayControlUiWsString(device, "status")))
        row.put("lifecycleState", JsonString(gatewayControlUiWsString(device, "lifecycleState")))
        row.put("authState", JsonString(gatewayControlUiWsString(device, "authState")))
        row.put("approvalState", JsonString(gatewayControlUiWsString(device, "approvalState")))
        row.put("phase", JsonString(gatewayControlUiWsString(device, "phase")))
        row.put("registeredAtMs", device.get("registeredAtMs") ?? 0.toJsonValue())
        row.put("lastSeenAtMs", device.get("lastSeenAtMs") ?? 0.toJsonValue())
        row.put("approvedAtMs", device.get("approvedAtMs") ?? 0.toJsonValue())
        row.put("deniedAtMs", device.get("deniedAtMs") ?? 0.toJsonValue())
        row.put("unregisteredAtMs", device.get("unregisteredAtMs") ?? 0.toJsonValue())
        row.put("authTransitionCount", device.get("authTransitionCount") ?? 0.toJsonValue())
        row.put("authHistoryCount", Int64(history.size()).toJsonValue())
        if (history.size() > 0) {
            row.put("lastAuth", history[history.size() - 1])
        }
        match (device.get("controlUiEnabled")) {
            case Some(v) => row.put("controlUiEnabled", v)
            case None => ()
        }
        summarized.add(row)
    }
    let result = JsonObject()
    result.put("pending", JsonArray([]))
    result.put("paired", summarized)
    result
}

private func gatewayControlUiWsUsageTotalsJson(
    input: Int64,
    output: Int64,
    cacheRead: Int64,
    cacheWrite: Int64,
    totalCost: Float64
): JsonObject {
    let totals = JsonObject()
    let totalTokens = input + output + cacheRead + cacheWrite
    totals.put("input", input.toJsonValue())
    totals.put("output", output.toJsonValue())
    totals.put("cacheRead", cacheRead.toJsonValue())
    totals.put("cacheWrite", cacheWrite.toJsonValue())
    totals.put("totalTokens", totalTokens.toJsonValue())
    totals.put("totalCost", totalCost.toJsonValue())
    totals.put("inputCost", 0.0.toJsonValue())
    totals.put("outputCost", 0.0.toJsonValue())
    totals.put("cacheReadCost", 0.0.toJsonValue())
    totals.put("cacheWriteCost", 0.0.toJsonValue())
    totals.put("missingCostEntries", 0.toJsonValue())
    totals
}

private func gatewayControlUiWsUsageTotalsJson(input: Int64, output: Int64): JsonObject {
    gatewayControlUiWsUsageTotalsJson(input, output, 0, 0, 0.0)
}

private func gatewayControlUiWsUsageEmptyMessageCounts(): JsonObject {
    let messages = JsonObject()
    messages.put("total", 0.toJsonValue())
    messages.put("user", 0.toJsonValue())
    messages.put("assistant", 0.toJsonValue())
    messages.put("toolCalls", 0.toJsonValue())
    messages.put("toolResults", 0.toJsonValue())
    messages.put("errors", 0.toJsonValue())
    messages
}

private func gatewayControlUiWsParseTranscriptObjects(raw: String): ArrayList<JsonObject> {
    let out = ArrayList<JsonObject>()
    let lines = raw.split("\n")
    var buffer = ""
    for (line in lines) {
        if (buffer.isEmpty() && line.trimAscii().isEmpty()) {
            continue
        }
        buffer = if (buffer.isEmpty()) { line } else { buffer + "\n" + line }
        let cand = buffer.trimAscii()
        try {
            out.add(JsonValue.fromStr(cand).asObject())
            buffer = ""
        } catch (_e: Exception) {
            ()
        }
    }
    out
}

private func gatewayControlUiWsParseMs(raw: String): Int64 {
    let normalized = raw.trimAscii()
    if (normalized.isEmpty()) {
        return 0
    }
    try {
        Int64.parse(normalized)
    } catch (_e: Exception) {
        0
    }
}

private func gatewayControlUiWsApproxTokens(text: String): Int64 {
    let trimmed = text.trimAscii()
    if (trimmed.isEmpty()) {
        return 0
    }
    max(1, trimmed.size / 4)
}

private func gatewayControlUiWsSessionDateFloorMs(raw: String): Int64 {
    let normalized = raw.trimAscii()
    if (normalized.isEmpty()) {
        return 0
    }
    try {
        DateTime.parse(normalized, "yyyy-MM-dd").toUnixTimeStamp().toMilliseconds()
    } catch (_e: Exception) {
        0
    }
}

private func gatewayControlUiWsSessionDateCeilMs(raw: String): Int64 {
    let normalized = raw.trimAscii()
    if (normalized.isEmpty()) {
        return 0
    }
    try {
        DateTime.parse("${normalized} 23:59:59", "yyyy-MM-dd HH:mm:ss").toUnixTimeStamp().toMilliseconds()
    } catch (_e: Exception) {
        0
    }
}

public func gatewayControlUiWsResolveSessionAgentId(sessionKey: String, agentIdHint: String): String {
    let hinted = agentIdHint.trimAscii()
    if (!hinted.isEmpty()) {
        return hinted
    }
    let normalized = sessionKey.trimAscii()
    match (parseAgentSessionKey(Some(normalized))) {
        case Some(parsed) => return parsed.agentId
        case None => ()
    }
    if (normalized.startsWith("cli:")) {
        return "main"
    }
    if (normalized.startsWith("qq:")) {
        return "main"
    }
    if (normalized.startsWith("feishu:")) {
        return "main"
    }
    "main"
}

public func gatewayControlUiWsResolveSessionChannel(sessionKey: String): String {
    let normalized = sessionKey.trimAscii()
    if (normalized.startsWith("qq:")) {
        return "qq"
    }
    if (normalized.startsWith("feishu:")) {
        return "feishu"
    }
    if (normalized.startsWith("cli:")) {
        return "cli"
    }
    ""
}

public func gatewayControlUiWsResolveSessionChatType(sessionKey: String): String {
    let normalized = sessionKey.trimAscii()
    if (normalized.contains(":group:")) {
        return "group"
    }
    if (normalized.contains(":direct:") || normalized.startsWith("cli:")) {
        return "direct"
    }
    ""
}

private func gatewayControlUiWsResolveSessionPeer(sessionKey: String): String {
    let normalized = sessionKey.trimAscii()
    let groupMarker = ":group:"
    let directMarker = ":direct:"
    match (normalized.indexOf(groupMarker)) {
        case Some(groupIdx) => return normalized[(groupIdx + groupMarker.size)..normalized.size]
        case None => ()
    }
    match (normalized.indexOf(directMarker)) {
        case Some(directIdx) => return normalized[(directIdx + directMarker.size)..normalized.size]
        case None => ()
    }
    if (normalized.startsWith("cli:")) {
        return "main"
    }
    ""
}

func gatewayControlUiWsBuildSessionOrigin(sessionKey: String, channel: String, chatType: String): JsonObject {
    gatewayBuildSessionCatalogOrigin(
        GatewaySessionCatalogView(
            GatewaySessionCatalogRow("", sessionKey, Path(""), "", "", 0),
            channel,
            chatType,
            gatewayControlUiWsResolveSessionPeer(sessionKey),
            sessionKey
        )
    )
}

private func gatewayControlUiWsSessionUsageSnapshot(
    store: GatewaySessionStore,
    view: GatewaySessionConversationView
): JsonObject {
    let out = JsonObject()
    let sessionKey = view.key
    let updatedAt = view.updatedAt
    let channel = view.channel
    let chatType = view.chatType
    let agentId = gatewayControlUiWsResolveSessionAgentId(sessionKey, view.agentId)
    let model = CliConfig.modelOrEmpty()
    var firstActivity: Int64 = 0
    var lastActivity: Int64 = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var userMessages: Int64 = 0
    var assistantMessages: Int64 = 0
    var lastLabel = ""
    match (store.readTranscriptRaw(sessionKey)) {
        case Some(raw) =>
            let objs = gatewayControlUiWsParseTranscriptObjects(raw)
            for (obj in objs) {
                let kind = gatewayControlUiWsString(obj, "kind")
                if (kind == "meta") {
                    continue
                }
                let role = gatewayControlUiWsString(obj, "role").trimAscii()
                let text = gatewayControlUiWsString(obj, "text")
                let ts = gatewayControlUiWsParseMs(gatewayControlUiWsString(obj, "ts"))
                if (ts > 0 && (firstActivity == 0 || ts < firstActivity)) {
                    firstActivity = ts
                }
                if (ts > lastActivity) {
                    lastActivity = ts
                }
                if (!text.trimAscii().isEmpty()) {
                    lastLabel = text.trimAscii()
                }
                if (role == "user") {
                    userMessages += 1
                    inputTokens += gatewayControlUiWsApproxTokens(text)
                } else if (role == "assistant") {
                    assistantMessages += 1
                    outputTokens += gatewayControlUiWsApproxTokens(text)
                }
            }
        case None => ()
    }
    if (lastActivity == 0) {
        lastActivity = updatedAt
    }
    if (firstActivity == 0) {
        firstActivity = lastActivity
    }
    let usage = gatewayControlUiWsUsageTotalsJson(inputTokens, outputTokens)
    usage.put("sessionId", JsonString(view.sessionId))
    usage.put("sessionFile", JsonString(view.sessionFile))
    usage.put("root", JsonString(view.root.toString()))
    usage.put("delivery", view.delivery)
    usage.put("binding", view.binding)
    usage.put("firstActivity", firstActivity.toJsonValue())
    usage.put("lastActivity", lastActivity.toJsonValue())
    usage.put("durationMs", max(0, lastActivity - firstActivity).toJsonValue())
    usage.put("activityDates", JsonArray([]))
    usage.put("dailyBreakdown", JsonArray([]))
    usage.put("dailyMessageCounts", JsonArray([]))
    usage.put("dailyLatency", JsonArray([]))
    usage.put("dailyModelUsage", JsonArray([]))
    let messageCounts = gatewayControlUiWsUsageEmptyMessageCounts()
    messageCounts.put("total", (userMessages + assistantMessages).toJsonValue())
    messageCounts.put("user", userMessages.toJsonValue())
    messageCounts.put("assistant", assistantMessages.toJsonValue())
    usage.put("messageCounts", messageCounts)
    let toolUsage = JsonObject()
    toolUsage.put("totalCalls", 0.toJsonValue())
    toolUsage.put("uniqueTools", 0.toJsonValue())
    toolUsage.put("tools", JsonArray([]))
    usage.put("toolUsage", toolUsage)
    let modelUsage = JsonArray([])
    let modelRow = JsonObject()
    modelRow.put("provider", JsonString(""))
    modelRow.put("model", JsonString(model))
    modelRow.put("count", (userMessages + assistantMessages).toJsonValue())
    modelRow.put("totals", gatewayControlUiWsUsageTotalsJson(inputTokens, outputTokens))
    modelUsage.add(modelRow)
    usage.put("modelUsage", modelUsage)
    out.put("key", JsonString(sessionKey))
    out.put("label", JsonString(if (lastLabel.isEmpty()) { view.displayName } else { lastLabel }))
    out.put("displayName", JsonString(view.displayName))
    out.put("sessionId", JsonString(view.sessionId))
    out.put("sessionFile", JsonString(view.sessionFile))
    out.put("root", JsonString(view.root.toString()))
    out.put("updatedAt", updatedAt.toJsonValue())
    out.put("agentId", JsonString(agentId))
    out.put("channel", JsonString(channel))
    out.put("chatType", JsonString(chatType))
    out.put("origin", view.origin)
    out.put("delivery", view.delivery)
    out.put("binding", view.binding)
    out.put("modelProvider", JsonString(""))
    out.put("model", JsonString(model))
    out.put("usage", usage)
    out
}

private func gatewayControlUiWsUsageCostResult(params: JsonObject): JsonValue {
    let usage = gatewayControlUiWsSessionsUsageResult(params).asObject()
    let result = JsonObject()
    result.put("updatedAt", usage.get("updatedAt") ?? gatewayControlUiWsNowMs().toJsonValue())
    result.put("days", 0.toJsonValue())
    result.put("daily", JsonArray([]))
    result.put("totals", usage.get("totals") ?? gatewayControlUiWsUsageTotalsJson(0, 0))
    result
}

private func gatewayControlUiWsChannelAccountsSnapshot(): (JsonObject, JsonObject) {
    let grouped = JsonObject()
    let defaults = JsonObject()
    let path = CliConfig.dotDir.join("gateway-channel-runtime-state.json")
    if (!exists(path)) {
        return (grouped, defaults)
    }
    let root = try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_e: Exception) {
        return (grouped, defaults)
    }
    let accounts = try {
        (root.get("accounts") ?? JsonArray([])).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
    for (item in accounts.getItems()) {
        let runtime = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let channelId = gatewayControlUiWsString(runtime, "channelId").trimAscii().toAsciiLower()
        if (channelId.isEmpty()) {
            continue
        }
        let accountId = gatewayControlUiWsString(runtime, "accountId").trimAscii()
        let row = JsonObject()
        row.put("accountId", JsonString(if (accountId.isEmpty()) { "${channelId}:default" } else { accountId }))
        row.put("configured", gatewayControlUiWsBool(runtime, "configured").toJsonValue())
        row.put("running", gatewayControlUiWsBool(runtime, "running").toJsonValue())
        row.put("connected", gatewayControlUiWsBool(runtime, "running").toJsonValue())
        row.put("lastInboundAt", gatewayControlUiWsInt(runtime, "lastEventAtMs", 0).toJsonValue())
        row.put("lastError", JsonString(gatewayControlUiWsNormalizeChannelError(
            gatewayControlUiWsString(runtime, "lastError")
        )))
        let arr = try {
            (grouped.get(channelId) ?? JsonArray([])).asArray()
        } catch (_inner: Exception) {
            JsonArray([])
        }
        if (arr.size() == 0) {
            defaults.put(channelId, JsonString(if (accountId.isEmpty()) { "${channelId}:default" } else { accountId }))
        }
        arr.add(row)
        grouped.put(channelId, arr)
    }
    (grouped, defaults)
}

private func gatewayControlUiWsChannelStatusObject(channelId: String, accounts: JsonArray): JsonObject {
    let user = CliSettingManager.readGatewaySettings()
    let out = JsonObject()
    var configured = false
    var running = false
    var connected = false
    var lastInboundAt: Int64 = 0
    var lastError = ""
    for (item in accounts.getItems()) {
        let row = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        if (gatewayControlUiWsBool(row, "configured")) {
            configured = true
        }
        if (gatewayControlUiWsBool(row, "running")) {
            running = true
        }
        if (gatewayControlUiWsBool(row, "connected")) {
            connected = true
        }
        let inbound = gatewayControlUiWsInt(row, "lastInboundAt", 0)
        if (inbound > lastInboundAt) {
            lastInboundAt = inbound
        }
        let err = gatewayControlUiWsNormalizeChannelError(gatewayControlUiWsString(row, "lastError"))
        if (lastError.isEmpty() && !err.isEmpty()) {
            lastError = err
        }
    }
    out.put("configured", configured.toJsonValue())
    out.put("running", running.toJsonValue())
    out.put("connected", connected.toJsonValue())
    out.put("lastError", JsonString(lastError))
    if (lastInboundAt > 0) {
        out.put("lastInboundAt", lastInboundAt.toJsonValue())
    }
    if (channelId == "feishu") {
        out.put("mode", JsonString(user.feishu.receiveMode))
    } else if (channelId == "qq") {
        out.put("mode", JsonString(user.qq.mode))
    } else {
        out.put("mode", JsonString(""))
    }
    let probe = JsonObject()
    probe.put("ok", (configured && lastError.isEmpty()).toJsonValue())
    probe.put("status", JsonString(
        if (!configured) {
            "pending-config"
        } else if (connected || running) {
            "ready"
        } else {
            "configured"
        }
    ))
    if (!lastError.isEmpty()) {
        probe.put("error", JsonString(lastError))
    }
    out.put("probe", probe)
    out
}

private func gatewayControlUiWsLiveChannelSnapshot(): JsonObject {
    match (gatewayActiveService()) {
        case Some(service) => service.liveChannelSnapshot()
        case None =>
            let empty = JsonObject()
            empty.put("channelAccounts", JsonObject())
            empty.put("channelDefaultAccountId", JsonObject())
            empty.put("channels", JsonObject())
            empty
    }
}

private func gatewayControlUiWsChannelsStatusMinimalResult(): JsonValue {
    let channelOrder = JsonArray([])
    let channelMeta = JsonArray([])
    let channelLabels = JsonObject()
    let channelDetailLabels = JsonObject()
    let channelSystemImages = JsonObject()
    let channelAccounts = JsonObject()
    let channelDefaultAccountId = JsonObject()
    let channels = JsonObject()
    let liveSnapshot = gatewayControlUiWsLiveChannelSnapshot()
    let groupedAccounts = gatewayControlUiWsObject(liveSnapshot, "channelAccounts")
    let defaultAccounts = gatewayControlUiWsObject(liveSnapshot, "channelDefaultAccountId")
    let liveChannels = gatewayControlUiWsObject(liveSnapshot, "channels")
    for (entry in listGatewayChannelCatalogEntries()) {
        let id = entry.id
        channelOrder.add(JsonString(id))
        channelLabels.put(id, JsonString(entry.label))
        channelDetailLabels.put(id, JsonString(entry.detailLabel))
        channelSystemImages.put(id, JsonString(entry.systemImage))
        let accounts = try {
            (groupedAccounts.get(id) ?? JsonArray([])).asArray()
        } catch (_e: Exception) {
            JsonArray([])
        }
        channelAccounts.put(id, accounts)
        channelDefaultAccountId.put(id, defaultAccounts.get(id) ?? JsonString("${id}:default"))
        let liveStatus = match (liveChannels.get(id)) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { gatewayControlUiWsChannelStatusObject(id, accounts) }
            case None => gatewayControlUiWsChannelStatusObject(id, accounts)
        }
        match (liveStatus.get("mode")) {
            case Some(_) => ()
            case None =>
            if (id == "feishu") {
                liveStatus.put("mode", JsonString(CliSettingManager.readGatewaySettings().feishu.receiveMode))
            } else if (id == "qq") {
                liveStatus.put("mode", JsonString(CliSettingManager.readGatewaySettings().qq.mode))
            } else {
                liveStatus.put("mode", JsonString(""))
            }
        }
        match (liveStatus.get("probe")) {
            case Some(_) => ()
            case None =>
            let probe = JsonObject()
            let configured = gatewayControlUiWsBool(liveStatus, "configured")
            let running = gatewayControlUiWsBool(liveStatus, "running")
            let connected = gatewayControlUiWsBool(liveStatus, "connected")
            let lastError = gatewayControlUiWsNormalizeChannelError(gatewayControlUiWsString(liveStatus, "lastError"))
            probe.put("ok", (configured && lastError.isEmpty()).toJsonValue())
            probe.put("status", JsonString(
                if (!configured) {
                    "pending-config"
                } else if (connected || running) {
                    "ready"
                } else {
                    "configured"
                }
            ))
            if (!lastError.isEmpty()) {
                probe.put("error", JsonString(lastError))
            }
            liveStatus.put("probe", probe)
        }
        channels.put(id, liveStatus)
        let meta = JsonObject()
        meta.put("id", JsonString(id))
        meta.put("label", JsonString(entry.label))
        meta.put("detailLabel", JsonString(entry.detailLabel))
        if (!entry.systemImage.isEmpty()) {
            meta.put("systemImage", JsonString(entry.systemImage))
        }
        channelMeta.add(meta)
    }
    let result = JsonObject()
    result.put("ts", gatewayControlUiWsNowMs().toJsonValue())
    result.put("channelOrder", channelOrder)
    result.put("channelLabels", channelLabels)
    result.put("channelDetailLabels", channelDetailLabels)
    result.put("channelSystemImages", channelSystemImages)
    result.put("channelMeta", channelMeta)
    result.put("channels", channels)
    result.put("channelAccounts", channelAccounts)
    result.put("channelDefaultAccountId", channelDefaultAccountId)
    result
}

func gatewayControlUiWsStoreForSessionKey(key: String): GatewaySessionStore {
    gatewaySessionStoreForSessionKey(CliSettingManager.readGatewaySettings(), key)
}

private func gatewayControlUiWsSessionsUsageResult(params: JsonObject): JsonValue {
    let user = CliSettingManager.readGatewaySettings()
    let views = gatewayListSessionConversationViewsForUser(user)
    let startDate = gatewayControlUiWsString(params, "startDate").trimAscii()
    let endDate = gatewayControlUiWsString(params, "endDate").trimAscii()
    let startMs = gatewayControlUiWsSessionDateFloorMs(startDate)
    let endMs = gatewayControlUiWsSessionDateCeilMs(endDate)
    let sessions = JsonArray([])
    var totalInput: Int64 = 0
    var totalOutput: Int64 = 0
    var msgTotal: Int64 = 0
    var msgUser: Int64 = 0
    var msgAssistant: Int64 = 0
    let byAgent = HashMap<String, JsonObject>()
    let byChannel = HashMap<String, JsonObject>()
    let byModel = HashMap<String, JsonObject>()
    let result = JsonObject()
    for (entry in views) {
        let store = gatewaySessionStoreForUserWithAgentId(user, entry.agentId)
        let session = gatewayControlUiWsSessionUsageSnapshot(store, entry)
        let updatedAt = gatewayControlUiWsInt(session, "updatedAt", 0)
        if (startMs > 0 && updatedAt > 0 && updatedAt < startMs) {
            continue
        }
        if (endMs > 0 && updatedAt > 0 && updatedAt > endMs) {
            continue
        }
        sessions.add(session)
        let usage = gatewayControlUiWsObject(session, "usage")
        let input = gatewayControlUiWsInt(usage, "input", 0)
        let output = gatewayControlUiWsInt(usage, "output", 0)
        totalInput += input
        totalOutput += output
        let counts = gatewayControlUiWsObject(usage, "messageCounts")
        msgTotal += gatewayControlUiWsInt(counts, "total", 0)
        msgUser += gatewayControlUiWsInt(counts, "user", 0)
        msgAssistant += gatewayControlUiWsInt(counts, "assistant", 0)
        let agentId = gatewayControlUiWsString(session, "agentId").trimAscii()
        if (!agentId.isEmpty()) {
            let row = match (byAgent.get(agentId)) {
                case Some(existing) => existing
                case None => JsonObject()
            }
            row.put("agentId", JsonString(agentId))
            let prev = gatewayControlUiWsInt(gatewayControlUiWsObject(row, "totals"), "totalTokens", 0)
            row.put("totals", gatewayControlUiWsUsageTotalsJson(0, prev + input + output))
            byAgent[agentId] = row
        }
        let channel = gatewayControlUiWsString(session, "channel").trimAscii()
        if (!channel.isEmpty()) {
            let row = match (byChannel.get(channel)) {
                case Some(existing) => existing
                case None => JsonObject()
            }
            row.put("channel", JsonString(channel))
            let prev = gatewayControlUiWsInt(gatewayControlUiWsObject(row, "totals"), "totalTokens", 0)
            row.put("totals", gatewayControlUiWsUsageTotalsJson(0, prev + input + output))
            byChannel[channel] = row
        }
        let model = gatewayControlUiWsString(session, "model").trimAscii()
        let modelKey = if (model.isEmpty()) { "__default__" } else { model }
        let modelRow = match (byModel.get(modelKey)) {
            case Some(existing) => existing
            case None => JsonObject()
        }
        modelRow.put("provider", JsonString(""))
        modelRow.put("model", JsonString(model))
        modelRow.put("count", (gatewayControlUiWsInt(modelRow, "count", 0) + 1).toJsonValue())
        let prevModelTokens = gatewayControlUiWsInt(gatewayControlUiWsObject(modelRow, "totals"), "totalTokens", 0)
        modelRow.put("totals", gatewayControlUiWsUsageTotalsJson(0, prevModelTokens + input + output))
        byModel[modelKey] = modelRow
    }
    result.put("totals", gatewayControlUiWsUsageTotalsJson(totalInput, totalOutput))
    result.put("updatedAt", gatewayControlUiWsNowMs().toJsonValue())
    result.put("startDate", JsonString(startDate))
    result.put("endDate", JsonString(endDate))
    result.put("sessions", sessions)
    let aggregates = JsonObject()
    let messages = gatewayControlUiWsUsageEmptyMessageCounts()
    messages.put("total", msgTotal.toJsonValue())
    messages.put("user", msgUser.toJsonValue())
    messages.put("assistant", msgAssistant.toJsonValue())
    aggregates.put("messages", messages)
    let tools = JsonObject()
    tools.put("totalCalls", 0.toJsonValue())
    tools.put("uniqueTools", 0.toJsonValue())
    tools.put("tools", JsonArray([]))
    aggregates.put("tools", tools)
    aggregates.put("byProvider", JsonArray([]))
    let byModelArr = JsonArray([])
    for ((_, row) in byModel) {
        byModelArr.add(row)
    }
    aggregates.put("byModel", byModelArr)
    let byAgentArr = JsonArray([])
    for ((_, row) in byAgent) {
        byAgentArr.add(row)
    }
    aggregates.put("byAgent", byAgentArr)
    let byChannelArr = JsonArray([])
    for ((_, row) in byChannel) {
        byChannelArr.add(row)
    }
    aggregates.put("byChannel", byChannelArr)
    aggregates.put("daily", JsonArray([]))
    result.put("aggregates", aggregates)
    result
}

func gatewayControlUiWsSessionsUsageTimeSeriesResult(params: JsonObject): JsonValue {
    let result = JsonObject()
    let key = gatewayControlUiWsString(params, "key").trimAscii()
    let points = JsonArray([])
    let user = CliSettingManager.readGatewaySettings()
    let view = if (!key.isEmpty()) { gatewayFindSessionConversationViewForUser(user, key) } else { None<GatewaySessionConversationView> }
    let resolvedKey = match (view) {
        case Some(v) => v.key
        case None => key
    }
    if (!key.isEmpty()) {
        let store = match (view) {
            case Some(v) => gatewaySessionStoreForUserWithAgentId(user, v.agentId)
            case None => gatewayControlUiWsStoreForSessionKey(key)
        }
        match (store.readTranscriptRaw(resolvedKey)) {
            case Some(raw) =>
                let objs = gatewayControlUiWsParseTranscriptObjects(raw)
                var cumulativeTokens: Int64 = 0
                for (obj in objs) {
                    let kind = gatewayControlUiWsString(obj, "kind")
                    if (kind == "meta") {
                        continue
                    }
                    let role = gatewayControlUiWsString(obj, "role").trimAscii()
                    let text = gatewayControlUiWsString(obj, "text")
                    let tokens = gatewayControlUiWsApproxTokens(text)
                    var input: Int64 = 0
                    var output: Int64 = 0
                    if (role == "user") {
                        input = tokens
                    } else if (role == "assistant") {
                        output = tokens
                    }
                    cumulativeTokens += input + output
                    let row = JsonObject()
                    row.put("timestamp", gatewayControlUiWsParseMs(gatewayControlUiWsString(obj, "ts")).toJsonValue())
                    row.put("input", input.toJsonValue())
                    row.put("output", output.toJsonValue())
                    row.put("cacheRead", 0.toJsonValue())
                    row.put("cacheWrite", 0.toJsonValue())
                    row.put("totalTokens", (input + output).toJsonValue())
                    row.put("cost", 0.0.toJsonValue())
                    row.put("cumulativeTokens", cumulativeTokens.toJsonValue())
                    row.put("cumulativeCost", 0.0.toJsonValue())
                    points.add(row)
                }
            case None => ()
        }
    }
    result.put("sessionId", JsonString(match (view) {
        case Some(v) => if (!v.sessionId.isEmpty()) { v.sessionId } else { resolvedKey }
        case None => key
    }))
    result.put("points", points)
    result
}

func gatewayControlUiWsSessionsUsageLogsResult(params: JsonObject): JsonValue {
    let result = JsonObject()
    let key = gatewayControlUiWsString(params, "key").trimAscii()
    let limit = gatewayControlUiWsInt(params, "limit", 1000)
    let logs = JsonArray([])
    let user = CliSettingManager.readGatewaySettings()
    let view = if (!key.isEmpty()) { gatewayFindSessionConversationViewForUser(user, key) } else { None<GatewaySessionConversationView> }
    let resolvedKey = match (view) {
        case Some(v) => v.key
        case None => key
    }
    if (!key.isEmpty()) {
        let store = match (view) {
            case Some(v) => gatewaySessionStoreForUserWithAgentId(user, v.agentId)
            case None => gatewayControlUiWsStoreForSessionKey(key)
        }
        match (store.readTranscriptRaw(resolvedKey)) {
            case Some(raw) =>
                let objs = gatewayControlUiWsParseTranscriptObjects(raw)
                let start = if (limit > 0 && objs.size > limit) { objs.size - limit } else { 0 }
                for (i in start..objs.size) {
                    let obj = objs[i]
                    let kind = gatewayControlUiWsString(obj, "kind")
                    if (kind == "meta") {
                        continue
                    }
                    let role = gatewayControlUiWsString(obj, "role").trimAscii()
                    let text = gatewayControlUiWsString(obj, "text")
                    if (role.isEmpty() && text.trimAscii().isEmpty()) {
                        continue
                    }
                    let row = JsonObject()
                    row.put("timestamp", gatewayControlUiWsParseMs(gatewayControlUiWsString(obj, "ts")).toJsonValue())
                    row.put("role", JsonString(if (role == "assistant") { "assistant" } else { "user" }))
                    row.put("content", JsonString(text))
                    row.put("tokens", gatewayControlUiWsApproxTokens(text).toJsonValue())
                    row.put("cost", 0.0.toJsonValue())
                    logs.add(row)
                }
            case None => ()
        }
    }
    result.put("logs", logs)
    result
}

func gatewayControlUiWsSessionsListResult(): JsonValue {
    match (handleGatewaySessionsFamily("sessions.list")) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            result.put("count", 0.toJsonValue())
            result.put("sessions", JsonArray([]))
            let defaults = JsonObject()
            defaults.put("modelProvider", JsonString(""))
            defaults.put("model", JsonString(CliConfig.modelOrEmpty()))
            defaults.put("contextTokens", 0.toJsonValue())
            result.put("defaults", defaults)
            result
    }
}

private func gatewayControlUiWsExecApprovalsGetResult(): JsonValue {
    let file = JsonObject()
    file.put("version", 1.toJsonValue())
    file.put("defaults", JsonObject())
    file.put("agents", JsonObject())
    let raw = file.toJsonString()
    let result = JsonObject()
    result.put("path", JsonString(CliConfig.dotDir.join("exec-approvals.json").toString()))
    result.put("exists", false.toJsonValue())
    result.put("hash", JsonString(gatewayControlUiWsCompatHash(raw)))
    result.put("file", file)
    result
}

private func gatewayControlUiWsAgentDisplayName(agentId: String): String {
    let raw = agentId.trimAscii()
    if (raw.isEmpty()) {
        return "Agent"
    }
    let parts = ArrayList<String>()
    for (piece in raw.replace("-", "_").split("_")) {
        let trimmed = piece.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        let lower = trimmed.toAsciiLower()
        let first = lower[0].toString().toAsciiUpper()
        let rest = if (lower.size > 1) { lower[1..] } else { "" }
        parts.add("${first}${rest}")
    }
    if (parts.isEmpty()) {
        raw
    } else {
        String.join(parts.toArray(), delimiter: " ")
    }
}

private func gatewayControlUiWsAgentIdentityName(agentId: String, configuredName: String): String {
    let explicitName = configuredName.trimAscii()
    if (!explicitName.isEmpty()) {
        return explicitName
    }
    if (agentId.trimAscii().toAsciiLower() == "main") {
        return "Metis"
    }
    gatewayControlUiWsAgentDisplayName(agentId)
}

private func gatewayControlUiWsBuiltinAgentCapabilities(agentId: String): JsonArray {
    let out = JsonArray([])
    match (agentId.trimAscii().toAsciiLower()) {
        case "general" =>
            out.add(JsonString("chat"))
            out.add(JsonString("tools"))
        case "cangjie" =>
            out.add(JsonString("chat"))
            out.add(JsonString("cangjie"))
            out.add(JsonString("tools"))
        case "explorer" =>
            out.add(JsonString("search"))
            out.add(JsonString("read-only"))
        case "editor" =>
            out.add(JsonString("edit"))
        case "reviewer" =>
            out.add(JsonString("review"))
        case "test_generator" =>
            out.add(JsonString("tests"))
        case "refactoring" =>
            out.add(JsonString("refactor"))
        case "planner" =>
            out.add(JsonString("plan"))
        case _ => ()
    }
    out
}

private func gatewayControlUiWsChannelsRuntimeResult(params: JsonObject): JsonValue {
    let user = CliSettingManager.readGatewaySettings()
    let request = GatewayRpcRequest("channels.runtime", params: gatewayDashboardRequestParams("channels.runtime", params))
    match (handleGatewayChannelsFamily("channels.runtime", user, request: Some(request))) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            result.put("summary", JsonObject())
            result
    }
}

private func gatewayControlUiWsFeishuAuthStartResult(params: JsonObject): JsonValue {
    let user = CliSettingManager.readGatewaySettings()
    let request = GatewayRpcRequest("channels.feishu.auth.start", params: gatewayDashboardRequestParams("channels.feishu.auth.start", params))
    match (handleGatewayChannelsFamily("channels.feishu.auth.start", user, request: Some(request))) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            result.put("status", JsonString("unavailable"))
            result.put("redacted", JsonBool(true))
            result
    }
}

private func gatewayControlUiWsChannelsHealthResult(): JsonValue {
    let user = CliSettingManager.readGatewaySettings()
    match (handleGatewayChannelsFamily("channels.health", user)) {
        case Some(response) =>
            let result = response.result.asObject()
            result.get("channels") ?? result
        case None =>
            let result = JsonObject()
            result
    }
}

private func gatewayControlUiWsChannelsAuditResult(params: JsonObject): JsonValue {
    let user = CliSettingManager.readGatewaySettings()
    let request = GatewayRpcRequest("channels.audit", params: gatewayDashboardRequestParams("channels.audit", params))
    match (handleGatewayChannelsFamily("channels.audit", user, request: Some(request))) {
        case Some(response) => response.result
        case None =>
            let result = JsonObject()
            let audit = JsonObject()
            let summary = JsonObject()
            summary.put("kind", JsonString("gateway-channels-audit"))
            summary.put("phase", JsonString("T12"))
            audit.put("kind", JsonString("gateway-channels-audit"))
            audit.put("summary", summary)
            audit.put("runtime", JsonObject())
            result.put("audit", audit)
            result
    }
}

private func gatewayControlUiWsCoreToolEntry(
    id: String,
    label: String,
    description: String,
    defaultProfiles: Array<String>,
    optional!: Bool = false
): JsonObject {
    let row = JsonObject()
    row.put("id", JsonString(id))
    row.put("label", JsonString(label))
    row.put("description", JsonString(description))
    row.put("source", JsonString("core"))
    row.put("optional", optional.toJsonValue())
    let profiles = JsonArray([])
    for (item in defaultProfiles) {
        profiles.add(JsonString(item))
    }
    row.put("defaultProfiles", profiles)
    row
}

private func gatewayControlUiWsEffectiveToolEntry(
    id: String,
    label: String,
    description: String
): JsonObject {
    let row = JsonObject()
    row.put("id", JsonString(id))
    row.put("label", JsonString(label))
    row.put("description", JsonString(description))
    row.put("rawDescription", JsonString(description))
    row.put("source", JsonString("core"))
    row
}

private func gatewayControlUiWsToolCatalogSection(
    id: String,
    label: String,
    tools: Array<JsonObject>
): JsonObject {
    let row = JsonObject()
    row.put("id", JsonString(id))
    row.put("label", JsonString(label))
    row.put("source", JsonString("core"))
    let items = JsonArray([])
    for (tool in tools) {
        items.add(tool)
    }
    row.put("tools", items)
    row
}

private func gatewayControlUiWsToolCatalogSections(): Array<JsonObject> {
    [
        gatewayControlUiWsToolCatalogSection("fs", "Files", [
            gatewayControlUiWsCoreToolEntry("read", "read", "Read file contents", ["minimal", "coding", "messaging", "full"]),
            gatewayControlUiWsCoreToolEntry("write", "write", "Create or overwrite files", ["coding", "full"]),
            gatewayControlUiWsCoreToolEntry("edit", "edit", "Make precise edits", ["coding", "full"]),
            gatewayControlUiWsCoreToolEntry("apply_patch", "apply_patch", "Patch files (OpenAI)", ["coding", "full"], optional: true)
        ]),
        gatewayControlUiWsToolCatalogSection("runtime", "Runtime", [
            gatewayControlUiWsCoreToolEntry("exec", "exec", "Run shell commands", ["coding", "full"]),
            gatewayControlUiWsCoreToolEntry("process", "process", "Manage background processes", ["coding", "full"], optional: true)
        ]),
        gatewayControlUiWsToolCatalogSection("web", "Web", [
            gatewayControlUiWsCoreToolEntry("web_search", "web_search", "Search the web", ["minimal", "messaging", "full"]),
            gatewayControlUiWsCoreToolEntry("web_fetch", "web_fetch", "Fetch web content", ["minimal", "messaging", "full"])
        ]),
        gatewayControlUiWsToolCatalogSection("memory", "Memory", [
            gatewayControlUiWsCoreToolEntry("memory_search", "memory_search", "Semantic search", ["minimal", "coding", "full"]),
            gatewayControlUiWsCoreToolEntry("memory_get", "memory_get", "Read memory files", ["minimal", "coding", "full"])
        ]),
        gatewayControlUiWsToolCatalogSection("sessions", "Sessions", [
            gatewayControlUiWsCoreToolEntry("sessions_list", "sessions_list", "List sessions", ["minimal", "coding", "messaging", "full"]),
            gatewayControlUiWsCoreToolEntry("sessions_history", "sessions_history", "Session history", ["minimal", "coding", "messaging", "full"]),
            gatewayControlUiWsCoreToolEntry("sessions_send", "sessions_send", "Send to session", ["messaging", "full"]),
            gatewayControlUiWsCoreToolEntry("sessions_spawn", "sessions_spawn", "Spawn sub-agent", ["coding", "full"]),
            gatewayControlUiWsCoreToolEntry("session_status", "session_status", "Session status", ["minimal", "coding", "messaging", "full"])
        ]),
        gatewayControlUiWsToolCatalogSection("ui", "UI", [
            gatewayControlUiWsCoreToolEntry("browser", "browser", "Control web browser", ["full"], optional: true),
            gatewayControlUiWsCoreToolEntry("canvas", "canvas", "Control canvases", ["full"], optional: true)
        ]),
        gatewayControlUiWsToolCatalogSection("messaging", "Messaging", [
            gatewayControlUiWsCoreToolEntry("message", "message", "Send messages", ["messaging", "full"])
        ]),
        gatewayControlUiWsToolCatalogSection("automation", "Automation", [
            gatewayControlUiWsCoreToolEntry("cron", "cron", "Schedule tasks", ["full"], optional: true),
            gatewayControlUiWsCoreToolEntry("gateway", "gateway", "Gateway control", ["full"], optional: true)
        ]),
        gatewayControlUiWsToolCatalogSection("nodes", "Nodes", [
            gatewayControlUiWsCoreToolEntry("nodes", "nodes", "Nodes + devices", ["full"], optional: true)
        ]),
        gatewayControlUiWsToolCatalogSection("agents", "Agents", [
            gatewayControlUiWsCoreToolEntry("agents_list", "agents_list", "List agents", ["coding", "full"])
        ]),
        gatewayControlUiWsToolCatalogSection("media", "Media", [
            gatewayControlUiWsCoreToolEntry("image", "image", "Image understanding", ["full"], optional: true)
        ])
    ]
}

private func gatewayControlUiWsToolAllowedForProfile(profile: String, defaultProfiles: JsonArray): Bool {
    if (profile.trimAscii().isEmpty()) {
        return true
    }
    for (item in defaultProfiles.getItems()) {
        let value = try { item.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        if (value == profile) {
            return true
        }
    }
    false
}

private func gatewayControlUiWsToolsCatalogResult(params: JsonObject): JsonValue {
    let agentId = gatewayControlUiWsString(params, "agentId").trimAscii()
    let resolvedAgentId = if (agentId.isEmpty()) { "general" } else { agentId }
    let profiles = JsonArray([])
    for ((id, label) in [
        ("minimal", "Minimal"),
        ("coding", "Coding"),
        ("messaging", "Messaging"),
        ("full", "Full")
    ]) {
        let row = JsonObject()
        row.put("id", JsonString(id))
        row.put("label", JsonString(label))
        profiles.add(row)
    }
    let groups = JsonArray([])
    for (group in gatewayControlUiWsToolCatalogSections()) {
        groups.add(group)
    }
    let result = JsonObject()
    result.put("agentId", JsonString(resolvedAgentId))
    result.put("profiles", profiles)
    result.put("groups", groups)
    result
}

private func gatewayControlUiWsToolsEffectiveResult(params: JsonObject): JsonValue {
    let agentId = gatewayControlUiWsString(params, "agentId").trimAscii()
    let resolvedAgentId = if (agentId.isEmpty()) { "general" } else { agentId }
    let profile = if (resolvedAgentId == "explorer") {
        "minimal"
    } else if (resolvedAgentId == "cangjie" || resolvedAgentId == "editor" || resolvedAgentId == "reviewer" ||
        resolvedAgentId == "test_generator" || resolvedAgentId == "refactoring") {
        "coding"
    } else if (resolvedAgentId == "planner") {
        "minimal"
    } else {
        "full"
    }
    let groups = JsonArray([])
    for (group in gatewayControlUiWsToolCatalogSections()) {
        let sourceTools = try { (group.get("tools") ?? JsonArray([])).asArray() } catch (_e: Exception) { JsonArray([]) }
        let enabledTools = JsonArray([])
        for (item in sourceTools.getItems()) {
            let tool = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            let defaultProfiles = try { (tool.get("defaultProfiles") ?? JsonArray([])).asArray() } catch (_e: Exception) { JsonArray([]) }
            if (!gatewayControlUiWsToolAllowedForProfile(profile, defaultProfiles)) {
                continue
            }
            enabledTools.add(gatewayControlUiWsEffectiveToolEntry(
                gatewayControlUiWsString(tool, "id"),
                gatewayControlUiWsString(tool, "label"),
                gatewayControlUiWsString(tool, "description")
            ))
        }
        if (enabledTools.size() == 0) {
            continue
        }
        let enabledGroup = JsonObject()
        enabledGroup.put("id", group.get("id") ?? JsonString(""))
        enabledGroup.put("label", group.get("label") ?? JsonString(""))
        enabledGroup.put("source", JsonString("core"))
        enabledGroup.put("tools", enabledTools)
        groups.add(enabledGroup)
    }
    let result = JsonObject()
    result.put("agentId", JsonString(resolvedAgentId))
    result.put("profile", JsonString(profile))
    result.put("groups", groups)
    result
}

private func gatewayControlUiWsAgentRow(
    agentId: String,
    kind: String,
    workspace!: String = "default",
    capabilities!: JsonArray = JsonArray([]),
    model!: String = ""
): JsonObject {
    let cfgEntry = gatewayControlUiWsAgentConfigEntry(agentId)
    let configuredName = gatewayControlUiWsString(cfgEntry, "name").trimAscii()
    let configuredWorkspace = gatewayControlUiWsString(cfgEntry, "workspace").trimAscii()
    let configuredModel = gatewayControlUiWsString(gatewayControlUiWsObject(cfgEntry, "model"), "primary").trimAscii()
    let name = gatewayControlUiWsAgentIdentityName(agentId, configuredName)
    let identity = JsonObject()
    identity.put("name", JsonString(name))
    identity.put("avatar", JsonString(""))
    identity.put("emoji", JsonString(gatewayControlUiWsAgentEmoji(agentId)))
    let row = JsonObject()
    row.put("id", JsonString(agentId))
    row.put("name", JsonString(name))
    row.put("kind", JsonString(kind))
    row.put("available", true.toJsonValue())
    row.put("configured", true.toJsonValue())
    row.put("health", JsonString("ok"))
    row.put("workspace", JsonString(
        if (!configuredWorkspace.isEmpty()) {
            configuredWorkspace
        } else {
            workspace
        }
    ))
    row.put("model", JsonString(
        if (!configuredModel.isEmpty()) {
            configuredModel
        } else if (model.trimAscii().isEmpty()) {
            CliConfig.modelOrEmpty()
        } else {
            model.trimAscii()
        }
    ))
    row.put("identity", identity)
    row.put("capabilities", capabilities)
    let normalizedAgentId = agentId.trimAscii()
    let memory = JsonObject()
    memory.put(
        "resolvedBackendConfig",
        MemoryRuntimeRegistry.resolveBackendConfig(
            agentId: normalizedAgentId,
            purpose: "control-ui-agents"
        ).toJsonObject()
    )
    memory.put(
        "backendSelection",
        MemoryRuntimeRegistry.backendSelectionSummary(
            agentId: normalizedAgentId,
            purpose: "control-ui-agents"
        )
    )
    memory.put(
        "agentScopedResolve",
        MemoryRuntimeRegistry.agentScopedResolveSummary(
            agentId: normalizedAgentId,
            purpose: "control-ui-agents"
        )
    )
    memory.put(
        "activeMemoryPlugin",
        MemoryRuntimeRegistry.activeMemoryPluginSummary(
            agentId: normalizedAgentId,
            purpose: "control-ui-agents"
        )
    )
    memory.put(
        "activeSearchBackend",
        MemoryRuntimeRegistry.activeSearchBackendSummary(
            agentId: normalizedAgentId,
            purpose: "control-ui-agents"
        )
    )
    memory.put(
        "activeOrchestrationBackend",
        MemoryRuntimeRegistry.activeOrchestrationBackendSummary(
            agentId: normalizedAgentId,
            purpose: "control-ui-agents"
        )
    )
    row.put("memory", memory)
    row
}

public func gatewayControlUiWsAgentsListResult(): JsonValue {
    let root = gatewayControlUiWsConfigRoot()
    let agentsRoot = gatewayControlUiWsObject(root, "agents")
    let defaults = gatewayControlUiWsObject(agentsRoot, "defaults")
    let defaultsModel = gatewayControlUiWsString(gatewayControlUiWsObject(defaults, "model"), "primary").trimAscii()
    let defaultsWorkspace = gatewayControlUiWsString(defaults, "workspace").trimAscii()
    let agents = JsonArray([])
    for (agentId in [
        "general",
        "cangjie",
        "explorer",
        "editor",
        "reviewer",
        "test_generator",
        "refactoring",
        "planner"
    ]) {
        agents.add(
            gatewayControlUiWsAgentRow(
                agentId,
                "builtin",
                workspace: if (defaultsWorkspace.isEmpty()) { CliConfig.cwd.toString() } else { defaultsWorkspace },
                model: defaultsModel,
                capabilities: gatewayControlUiWsBuiltinAgentCapabilities(agentId)
            )
        )
    }
    for (agentDir in CliConfig.subagentDirs) {
        if (!exists(agentDir)) {
            continue
        }
        for (entry in Directory.readFrom(agentDir)) {
            if (!entry.isDirectory()) {
                continue
            }
            let manifest = agentDir.join(entry.name).join("AGENT.md")
            if (!exists(manifest)) {
                continue
            }
            agents.add(
                gatewayControlUiWsAgentRow(
                    entry.name,
                    "custom",
                    workspace: agentDir.join(entry.name).toString(),
                    model: defaultsModel
                )
            )
        }
    }
    let result = JsonObject()
    result.put("defaultId", JsonString("general"))
    result.put("mainKey", JsonString("main"))
    result.put("scope", JsonString("global"))
    result.put("agents", agents)
    result
}

private func gatewayControlUiWsAgentIdentityResult(params: JsonObject): JsonValue {
    let sessionKey = gatewayControlUiWsString(params, "sessionKey").trimAscii()
    var agentId = gatewayControlUiWsResolveSessionAgentId(sessionKey, gatewayControlUiWsString(params, "agentId"))
    if (agentId.isEmpty()) {
        agentId = "general"
    }
    let cfgEntry = gatewayControlUiWsAgentConfigEntry(agentId)
    let configuredName = gatewayControlUiWsString(cfgEntry, "name").trimAscii()
    let result = JsonObject()
    result.put("agentId", JsonString(agentId))
    result.put("name", JsonString(gatewayControlUiWsAgentIdentityName(agentId, configuredName)))
    result.put("avatar", JsonString(""))
    result.put("emoji", JsonString(gatewayControlUiWsAgentEmoji(agentId)))
    result
}

private func gatewayControlUiWsAgentEmoji(agentId: String): String {
    match (agentId.trimAscii().toAsciiLower()) {
        case "general" => ""
        case "cangjie" => ""
        case "explorer" => ""
        case "editor" => ""
        case "reviewer" => ""
        case "test_generator" => ""
        case "refactoring" => ""
        case "planner" => ""
        case _ => ""
    }
}

private func gatewayControlUiWsResolveAgentWorkspace(agentId: String): String {
    let normalized = agentId.trimAscii()
    if (normalized.isEmpty()) {
        return CliConfig.cwd.toString()
    }
    let cfgEntry = gatewayControlUiWsAgentConfigEntry(normalized)
    let configuredWorkspace = gatewayControlUiWsString(cfgEntry, "workspace").trimAscii()
    if (!configuredWorkspace.isEmpty()) {
        return configuredWorkspace
    }
    match (normalized.toAsciiLower()) {
        case "general" | "cangjie" | "explorer" | "editor" | "reviewer" | "test_generator" | "refactoring" | "planner" =>
            return CliConfig.cwd.toString()
        case _ => ()
    }
    for (agentDir in CliConfig.subagentDirs) {
        let path = agentDir.join(normalized)
        if (exists(path) && exists(path.join("AGENT.md"))) {
            return path.toString()
        }
    }
    CliConfig.cwd.toString()
}

private func gatewayControlUiWsAgentFilesListResult(params: JsonObject): JsonValue {
    let agentId = gatewayControlUiWsString(params, "agentId").trimAscii()
    let workspace = gatewayControlUiWsResolveAgentWorkspace(agentId)
    let files = JsonArray([])
    if (!workspace.isEmpty()) {
        let root = Path(workspace)
        let seen = ArrayList<String>()
        for (fileName in ["AGENTS.md", "SOUL.md", "TOOLS.md", "IDENTITY.md", "USER.md", "HEARTBEAT.md", "BOOTSTRAP.md", "MEMORY.md"]) {
            seen.add(fileName)
            let path = root.join(fileName)
            let row = JsonObject()
            row.put("name", JsonString(fileName))
            row.put("path", JsonString(path.toString()))
            let present = exists(path)
            row.put("missing", (!present).toJsonValue())
            if (present) {
                let info = try { FileInfo(path) } catch (_e: Exception) { FileInfo(root) }
                row.put("size", info.size.toJsonValue())
                row.put("updatedAtMs", try { info.lastModificationTime.toUnixTimeStamp().toMilliseconds().toJsonValue() } catch (_e: Exception) { 0.toJsonValue() })
            } else {
                row.put("size", 0.toJsonValue())
                row.put("updatedAtMs", 0.toJsonValue())
            }
            files.add(row)
        }
        if (exists(root)) {
            for (entry in Directory.readFrom(root)) {
                if (entry.isDirectory()) {
                    continue
                }
                let fileName = entry.name.trimAscii()
                if (fileName.isEmpty() || seen.contains(fileName)) {
                    continue
                }
                let lower = fileName.toAsciiLower()
                if (!(lower.endsWith(".md") || lower.endsWith(".txt") || lower.endsWith(".json"))) {
                    continue
                }
                let path = root.join(fileName)
                let row = JsonObject()
                row.put("name", JsonString(fileName))
                row.put("path", JsonString(path.toString()))
                let info = try { FileInfo(path) } catch (_e: Exception) { FileInfo(root) }
                row.put("missing", false.toJsonValue())
                row.put("size", info.size.toJsonValue())
                row.put("updatedAtMs", try { info.lastModificationTime.toUnixTimeStamp().toMilliseconds().toJsonValue() } catch (_e: Exception) { 0.toJsonValue() })
                files.add(row)
            }
        }
    }
    let result = JsonObject()
    result.put("agentId", JsonString(if (agentId.isEmpty()) { "general" } else { agentId }))
    result.put("workspace", JsonString(if (workspace.isEmpty()) { "default" } else { workspace }))
    result.put("files", files)
    result
}

private func gatewayControlUiWsAgentFilesGetResult(params: JsonObject): JsonValue {
    let listed = try {
        gatewayControlUiWsAgentFilesListResult(params).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let name = gatewayControlUiWsString(params, "name").trimAscii()
    let offsetRaw = gatewayControlUiWsInt(params, "offset", 0)
    let limitRaw = gatewayControlUiWsInt(params, "limit", GATEWAY_CONTROL_UI_AGENT_FILE_INITIAL_LIMIT)
    let offset = if (offsetRaw < 0) { 0 } else { offsetRaw }
    let limit = if (limitRaw <= 0) {
        GATEWAY_CONTROL_UI_AGENT_FILE_INITIAL_LIMIT
    } else if (limitRaw > GATEWAY_CONTROL_UI_AGENT_FILE_MAX_LIMIT) {
        GATEWAY_CONTROL_UI_AGENT_FILE_MAX_LIMIT
    } else {
        limitRaw
    }
    let workspace = gatewayControlUiWsString(listed, "workspace").trimAscii()
    let file = JsonObject()
    file.put("name", JsonString(name))
    if (!workspace.isEmpty() && workspace != "default" && !name.isEmpty()) {
        let path = Path(workspace).join(name)
        file.put("path", JsonString(path.toString()))
        if (exists(path)) {
            file.put("missing", false.toJsonValue())
            file.put("updatedAtMs", try { FileInfo(path).lastModificationTime.toUnixTimeStamp().toMilliseconds().toJsonValue() } catch (_e: Exception) { 0.toJsonValue() })
            file.put("size", try { FileInfo(path).size.toJsonValue() } catch (_e: Exception) { 0.toJsonValue() })
            let content = try { String.fromUtf8(File.readFrom(path)) } catch (_e: Exception) { "" }
            let totalSize = content.size
            let off = min(offset, totalSize)
            let end = min(off + limit, totalSize)
            let chunk = if (off >= totalSize) {
                ""
            } else {
                content[off..end]
            }
            let truncated = end < totalSize
            file.put("content", JsonString(chunk))
            file.put("offset", off.toJsonValue())
            file.put("limit", limit.toJsonValue())
            if (truncated) {
                file.put("nextOffset", end.toJsonValue())
            }
            file.put("truncated", truncated.toJsonValue())
            file.put("totalSize", totalSize.toJsonValue())
        } else {
            file.put("missing", true.toJsonValue())
            file.put("content", JsonString(""))
            file.put("offset", 0.toJsonValue())
            file.put("limit", limit.toJsonValue())
            file.put("truncated", false.toJsonValue())
            file.put("totalSize", 0.toJsonValue())
        }
    } else {
        file.put("path", JsonString(name))
        file.put("missing", true.toJsonValue())
        file.put("content", JsonString(""))
        file.put("offset", 0.toJsonValue())
        file.put("limit", limit.toJsonValue())
        file.put("truncated", false.toJsonValue())
        file.put("totalSize", 0.toJsonValue())
    }
    let result = JsonObject()
    result.put("agentId", listed.get("agentId") ?? JsonString("general"))
    result.put("workspace", JsonString(if (workspace.isEmpty()) { "default" } else { workspace }))
    result.put("file", file)
    result
}

private func gatewayControlUiWsAgentFilesSetResult(params: JsonObject): GatewayProtocolResponse {
    let listed = try {
        gatewayControlUiWsAgentFilesListResult(params).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let workspace = gatewayControlUiWsString(listed, "workspace").trimAscii()
    let name = gatewayControlUiWsString(params, "name").trimAscii()
    let content = gatewayControlUiWsString(params, "content")
    if (workspace.isEmpty() || workspace == "default" || name.isEmpty()) {
        return GatewayProtocolResponse(false, "agents.files.set", error: "Agent file is not writable.", errorCode: "UNSUPPORTED")
    }
    let path = Path(workspace).join(name)
    try {
        File.writeTo(path, content.toArray())
    } catch (e: Exception) {
        return GatewayProtocolResponse(false, "agents.files.set", error: e.message, errorCode: "WRITE_FAILED")
    }
    let getParams = JsonObject()
    getParams.put("agentId", listed.get("agentId") ?? JsonString("general"))
    getParams.put("name", JsonString(name))
    let result = JsonObject()
    result.put("ok", true.toJsonValue())
    result.put("agentId", listed.get("agentId") ?? JsonString("general"))
    result.put("workspace", JsonString(workspace))
    result.put("file", try { gatewayControlUiWsAgentFilesGetResult(getParams).asObject().get("file") ?? JsonObject() } catch (_e: Exception) { JsonObject() })
    GatewayProtocolResponse(true, "agents.files.set", result: result)
}

private func gatewayControlUiWsCronJobPayload(job: CronJob): JsonObject {
    let payload = JsonObject()
    if (job.payloadKind.trimAscii().toAsciiLower() == "systemevent") {
        payload.put("kind", JsonString("systemEvent"))
        payload.put("text", JsonString(if (!job.systemEvent.trimAscii().isEmpty()) { job.systemEvent } else { job.prompt }))
    } else {
        payload.put("kind", JsonString("agentTurn"))
        payload.put("message", JsonString(job.prompt))
        if (!job.modelOverride.trimAscii().isEmpty()) {
            payload.put("model", JsonString(job.modelOverride))
        }
        if (!job.thinkingLevel.trimAscii().isEmpty()) {
            payload.put("thinking", JsonString(job.thinkingLevel))
        }
        payload.put("lightContext", job.lightContext.toJsonValue())
        payload.put("deliver", (!job.deliveryChannel.trimAscii().isEmpty() || !job.deliveryTo.trimAscii().isEmpty() || job.deliveryAnnounce).toJsonValue())
        if (!job.deliveryChannel.trimAscii().isEmpty()) {
            payload.put("channel", JsonString(job.deliveryChannel))
        }
        if (!job.deliveryTo.trimAscii().isEmpty()) {
            payload.put("to", JsonString(job.deliveryTo))
        }
        payload.put("bestEffortDeliver", job.bestEffortDeliver.toJsonValue())
    }
    payload
}

private func gatewayControlUiWsCronJobDelivery(job: CronJob): JsonObject {
    let delivery = JsonObject()
    let mode = if (!job.deliveryMode.trimAscii().isEmpty()) {
        job.deliveryMode.trimAscii()
    } else if (!job.deliveryChannel.trimAscii().isEmpty() || !job.deliveryTo.trimAscii().isEmpty() || job.deliveryAnnounce) {
        "announce"
    } else {
        "none"
    }
    delivery.put("mode", JsonString(mode))
    if (!job.deliveryChannel.trimAscii().isEmpty()) {
        delivery.put("channel", JsonString(job.deliveryChannel))
    }
    if (!job.deliveryTo.trimAscii().isEmpty()) {
        delivery.put("to", JsonString(job.deliveryTo))
    }
    if (!job.deliveryAccountId.trimAscii().isEmpty()) {
        delivery.put("accountId", JsonString(job.deliveryAccountId))
    }
    delivery.put("bestEffort", job.bestEffortDeliver.toJsonValue())
    if (!job.failureChannel.trimAscii().isEmpty() || !job.failureTo.trimAscii().isEmpty() || !job.failureDestMode.trimAscii().isEmpty() || !job.failureAccountId.trimAscii().isEmpty()) {
        let failure = JsonObject()
        if (!job.failureChannel.trimAscii().isEmpty()) {
            failure.put("channel", JsonString(job.failureChannel))
        }
        if (!job.failureTo.trimAscii().isEmpty()) {
            failure.put("to", JsonString(job.failureTo))
        }
        let failureMode = if (!job.failureDestMode.trimAscii().isEmpty()) {
            job.failureDestMode.trimAscii()
        } else if (job.failureAnnounce) {
            "announce"
        } else {
            ""
        }
        if (!failureMode.isEmpty()) {
            failure.put("mode", JsonString(failureMode))
        }
        if (!job.failureAccountId.trimAscii().isEmpty()) {
            failure.put("accountId", JsonString(job.failureAccountId))
        }
        delivery.put("failureDestination", failure)
    }
    delivery
}

private func gatewayControlUiWsCronJobState(job: CronJob): JsonObject {
    let state = JsonObject()
    let nowMs = gatewayControlUiWsNowMs()
    let nextRun = match (computeJobNextRun(job, nowMs)) {
        case Some(v) => v
        case None => if (job.state.nextRunAtMs > 0) { job.state.nextRunAtMs } else { 0 }
    }
    if (nextRun > 0) {
        state.put("nextRunAtMs", nextRun.toJsonValue())
    }
    if (job.state.runningAtMs > 0) {
        state.put("runningAtMs", job.state.runningAtMs.toJsonValue())
    }
    if (job.state.lastRunAtMs > 0) {
        state.put("lastRunAtMs", job.state.lastRunAtMs.toJsonValue())
    }
    let lastStatus = job.state.lastStatus.trimAscii()
    if (!lastStatus.isEmpty()) {
        state.put("lastStatus", JsonString(lastStatus))
        state.put("lastRunStatus", JsonString(lastStatus))
    }
    if (!job.state.lastError.trimAscii().isEmpty()) {
        state.put("lastError", JsonString(job.state.lastError))
        state.put("lastErrorReason", JsonString(job.state.lastError))
    }
    if (job.state.consecutiveErrors > 0) {
        state.put("consecutiveErrors", job.state.consecutiveErrors.toJsonValue())
    }
    if (job.state.lastFailureAlertAtMs > 0) {
        state.put("lastFailureAlertAtMs", job.state.lastFailureAlertAtMs.toJsonValue())
    }
    state
}

private func gatewayControlUiWsCronJobResult(job: CronJob): JsonObject {
    let schedule = JsonObject()
    let kind = job.schedule.kind.trimAscii().toAsciiLower()
    schedule.put("kind", JsonString(if (kind.isEmpty()) { "every" } else { kind }))
    if (kind == "every") {
        schedule.put("everyMs", job.schedule.everyMs.toJsonValue())
        if (job.schedule.anchorMs > 0) {
            schedule.put("anchorMs", job.schedule.anchorMs.toJsonValue())
        }
    } else if (kind == "at") {
        schedule.put("at", JsonString("${job.schedule.atMs}"))
    } else {
        schedule.put("expr", JsonString(job.schedule.cronExpr))
        if (!job.schedule.timeZone.trimAscii().isEmpty()) {
            schedule.put("tz", JsonString(job.schedule.timeZone))
        }
        if (job.schedule.staggerMs > 0) {
            schedule.put("staggerMs", job.schedule.staggerMs.toJsonValue())
        }
    }
    let jobObj = JsonObject()
    jobObj.put("id", JsonString(job.id))
    jobObj.put("name", JsonString(if (!job.description.trimAscii().isEmpty()) { job.description } else { job.id }))
    jobObj.put("description", JsonString(job.description))
    jobObj.put("enabled", job.enabled.toJsonValue())
    jobObj.put("schedule", schedule)
    jobObj.put("sessionTarget", JsonString(job.sessionTarget))
    if (!job.agentId.trimAscii().isEmpty()) {
        jobObj.put("agentId", JsonString(job.agentId))
    }
    jobObj.put("payload", gatewayControlUiWsCronJobPayload(job))
    jobObj.put("delivery", gatewayControlUiWsCronJobDelivery(job))
    if (job.failureAlertAfter > 0 || job.failureAlertCooldownMs > 0) {
        let failureAlert = JsonObject()
        if (job.failureAlertAfter > 0) {
            failureAlert.put("after", job.failureAlertAfter.toJsonValue())
        }
        if (job.failureAlertCooldownMs > 0) {
            failureAlert.put("cooldownMs", job.failureAlertCooldownMs.toJsonValue())
        }
        if (!job.failureChannel.trimAscii().isEmpty()) {
            failureAlert.put("channel", JsonString(job.failureChannel))
        }
        if (!job.failureTo.trimAscii().isEmpty()) {
            failureAlert.put("to", JsonString(job.failureTo))
        }
        let failureMode = if (!job.failureDestMode.trimAscii().isEmpty()) {
            job.failureDestMode.trimAscii()
        } else if (job.failureAnnounce) {
            "announce"
        } else {
            ""
        }
        if (!failureMode.isEmpty()) {
            failureAlert.put("mode", JsonString(failureMode))
        }
        if (!job.failureAccountId.trimAscii().isEmpty()) {
            failureAlert.put("accountId", JsonString(job.failureAccountId))
        }
        jobObj.put("failureAlert", failureAlert)
    }
    jobObj.put("wakeMode", JsonString(if (job.wakeMode.trimAscii().isEmpty()) { "next-heartbeat" } else { job.wakeMode }))
    jobObj.put("state", gatewayControlUiWsCronJobState(job))
    if (job.createdAtMs > 0) {
        jobObj.put("createdAtMs", job.createdAtMs.toJsonValue())
    }
    if (job.updatedAtMs > 0) {
        jobObj.put("updatedAtMs", job.updatedAtMs.toJsonValue())
    }
    jobObj
}

private func gatewayControlUiWsCronJobsListResult(params: JsonObject): JsonValue {
    let jobs = cronLoadOrEmpty(cronStorePath(CliConfig.dotDir))
    let rows = JsonArray([])
    for (job in jobs) {
        rows.add(gatewayControlUiWsCronJobResult(job))
    }
    let total = jobs.size
    let limitRaw = gatewayControlUiWsInt(params, "limit", Int64(total))
    let offsetRaw = gatewayControlUiWsInt(params, "offset", 0)
    let limit = if (limitRaw <= 0) { Int64(max(total, 1)) } else { limitRaw }
    let offset = if (offsetRaw < 0) { 0 } else { offsetRaw }
    let sliced = JsonArray([])
    var index: Int64 = offset
    var count: Int64 = 0
    while (index < rows.size() && count < limit) {
        sliced.add(rows[index])
        index += 1
        count += 1
    }
    let hasMore = index < rows.size()
    let result = JsonObject()
    result.put("jobs", sliced)
    result.put("total", Int64(total).toJsonValue())
    result.put("limit", limit.toJsonValue())
    result.put("offset", offset.toJsonValue())
    result.put("nextOffset", if (hasMore) { index.toJsonValue() } else { JsonValue.fromStr("null") })
    result.put("hasMore", hasMore.toJsonValue())
    result
}

private func gatewayControlUiWsCronStatusResult(): JsonValue {
    let jobs = cronLoadOrEmpty(cronStorePath(CliConfig.dotDir))
    var nextWakeAtMs: Int64 = 0
    let nowMs = gatewayControlUiWsNowMs()
    for (job in jobs) {
        if (!job.enabled) {
            continue
        }
        match (computeJobNextRun(job, nowMs)) {
            case Some(ts) =>
                if (nextWakeAtMs <= 0 || ts < nextWakeAtMs) {
                    nextWakeAtMs = ts
                }
            case None => ()
        }
    }
    let result = JsonObject()
    result.put("enabled", true.toJsonValue())
    result.put("jobs", Int64(jobs.size).toJsonValue())
    if (nextWakeAtMs > 0) {
        result.put("nextWakeAtMs", nextWakeAtMs.toJsonValue())
    } else {
        result.put("nextWakeAtMs", JsonValue.fromStr("null"))
    }
    result
}

private func gatewayControlUiWsCronRunsResult(params: JsonObject): JsonValue {
    let jobs = cronLoadOrEmpty(cronStorePath(CliConfig.dotDir))
    let selectedJobId = gatewayControlUiWsString(params, "jobId").trimAscii()
    let jobIds = ArrayList<String>()
    if (!selectedJobId.isEmpty()) {
        jobIds.add(selectedJobId)
    } else {
        for (job in jobs) {
            jobIds.add(job.id)
        }
    }
    let merged = readCronRunLogMergedFromStore(cronStorePath(CliConfig.dotDir), jobIds.toArray(), resultLimit: 800)
    let entries = try {
        gatewayControlUiWsObject(merged, "entries").asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
    let total = gatewayControlUiWsInt(merged, "total", entries.size())
    let limitRaw = gatewayControlUiWsInt(params, "limit", entries.size())
    let offsetRaw = gatewayControlUiWsInt(params, "offset", 0)
    let limit = if (limitRaw <= 0) { Int64(max(entries.size(), 1)) } else { limitRaw }
    let offset = if (offsetRaw < 0) { 0 } else { offsetRaw }
    let page = JsonArray([])
    var index: Int64 = offset
    var count: Int64 = 0
    while (index < entries.size() && count < limit) {
        page.add(entries[index])
        index += 1
        count += 1
    }
    let hasMore = index < entries.size()
    let result = JsonObject()
    result.put("entries", page)
    result.put("total", total.toJsonValue())
    result.put("limit", limit.toJsonValue())
    result.put("offset", offset.toJsonValue())
    result.put("nextOffset", if (hasMore) { index.toJsonValue() } else { JsonValue.fromStr("null") })
    result.put("hasMore", hasMore.toJsonValue())
    result
}

public func gatewayControlUiWsCompatResponse(method: String, params: JsonObject, cfg: GatewayConfig): Option<GatewayProtocolResponse> {
    let normalized = method.trimAscii().toAsciiLower()
    if (normalized == "sessions.subscribe") {
        let result = JsonObject()
        result.put("subscribed", true.toJsonValue())
        result.put("mode", JsonString("direct-websocket"))
        result.put("kinds", gatewayControlUiWsEventKindsJson(gatewayControlUiWsDefaultSessionEventKinds()))
        result.put("cursorMode", JsonString("direct-push"))
        result.put("resumeMethod", JsonString(""))
        result.put("unsubscribeMethod", JsonString("sessions.unsubscribe"))
        return Some(GatewayProtocolResponse(true, method, result: result))
    }
    if (normalized == "sessions.unsubscribe") {
        let result = JsonObject()
        result.put("subscribed", false.toJsonValue())
        result.put("mode", JsonString("direct-websocket"))
        result.put("kinds", JsonArray([]))
        return Some(GatewayProtocolResponse(true, method, result: result))
    }
    if (normalized == "config.get") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsConfigGetResult()))
    }
    if (normalized == "system-presence") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSystemPresenceResult(cfg)))
    }
    if (normalized == "last-heartbeat") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsLastHeartbeatResult(cfg)))
    }
    if (normalized == "config.schema") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsConfigSchemaResult(params)))
    }
    if (normalized == "skills.status") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSkillsStatusResult()))
    }
    if (normalized == "skills.bins") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSkillsBinsResult()))
    }
    if (normalized == "skills.detail") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSkillsDetailResult(params)))
    }
    if (normalized == "skills.compatibilitymatrix") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSkillsCompatibilityResult(params)))
    }
    if (normalized == "channels.status") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsChannelsStatusMinimalResult()))
    }
    if (normalized == "channels.feishu.auth.start") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsFeishuAuthStartResult(params)))
    }
    if (normalized == "channels.runtime") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsChannelsRuntimeResult(params)))
    }
    if (normalized == "channels.health") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsChannelsHealthResult()))
    }
    if (normalized == "channels.audit") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsChannelsAuditResult(params)))
    }
    if (normalized == "node.list") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsNodeListResult(cfg)))
    }
    if (normalized == "exec.approvals.get") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsExecApprovalsGetResult()))
    }
    if (normalized == "device.pair.list") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsDevicePairListResult(cfg)))
    }
    if (normalized == "sessions.list") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSessionsListResult()))
    }
    if (normalized == "agents.list") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsAgentsListResult()))
    }
    if (normalized == "agents.runtime" || normalized == "agents.runtime.profile") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsAgentsRuntimeResult(params)))
    }
    if (normalized == "agents.runtime.audit") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsAgentsRuntimeAuditResult(params)))
    }
    if (
        normalized == "agents.models.status" ||
        normalized == "agents.models.get" ||
        normalized == "agents.models.set" ||
        normalized == "agents.teams.list" ||
        normalized == "agents.teams.get" ||
        normalized == "agents.teams.create" ||
        normalized == "agents.teams.update" ||
        normalized == "agents.teams.delete"
    ) {
        return Some(gatewayControlUiWsAgentsFamilyCompatResponse(normalized, params))
    }
    if (normalized == "agent.identity.get") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsAgentIdentityResult(params)))
    }
    if (normalized == "agents.files.list") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsAgentFilesListResult(params)))
    }
    if (normalized == "agents.files.get") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsAgentFilesGetResult(params)))
    }
    if (normalized == "agents.files.set") {
        return Some(gatewayControlUiWsAgentFilesSetResult(params))
    }
    if (normalized == "tools.catalog") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsToolsCatalogResult(params)))
    }
    if (normalized == "tools.effective") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsToolsEffectiveResult(params)))
    }
    if (normalized == "cron.status") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsCronStatusResult()))
    }
    if (normalized == "cron.list") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsCronJobsListResult(params)))
    }
    if (normalized == "cron.runs") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsCronRunsResult(params)))
    }
    if (normalized == "usage.cost") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsUsageCostResult(params)))
    }
    if (normalized == "sessions.usage") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSessionsUsageResult(params)))
    }
    if (normalized == "sessions.usage.timeseries") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSessionsUsageTimeSeriesResult(params)))
    }
    if (normalized == "sessions.usage.logs") {
        return Some(GatewayProtocolResponse(true, method, result: gatewayControlUiWsSessionsUsageLogsResult(params)))
    }
    None
}

private func gatewayControlUiWsChatMessage(role: String, text: String, tsMs: Int64): JsonObject {
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

func gatewayControlUiWsChatEventPayload(
    sessionKey: String,
    runId: String,
    state: String,
    message: JsonObject,
    conversation!: Option<GatewaySessionConversationView> = None<GatewaySessionConversationView>,
    delivery!: Option<JsonObject> = None<JsonObject>,
    binding!: Option<JsonObject> = None<JsonObject>,
    errorMessage!: String = ""
): JsonObject {
    let payload = gatewayBuildChatEventPayload(
        sessionKey,
        runId,
        state,
        message,
        conversation: conversation,
        errorMessage: errorMessage
    )
    match (delivery) {
        case Some(value) => payload.put("delivery", value)
        case None => ()
    }
    match (binding) {
        case Some(value) => payload.put("binding", value)
        case None => ()
    }
    payload
}

private func gatewayControlUiWsResolveBindingPayload(
    params: JsonObject,
    responseResult!: Option<JsonObject> = None<JsonObject>,
    conversation!: Option<GatewaySessionConversationView> = None<GatewaySessionConversationView>
): Option<JsonObject> {
    match (responseResult) {
        case Some(result) =>
            match (result.get("binding")) {
                case Some(value) =>
                    try { return Some(value.asObject()) } catch (_: Exception) { () }
                case None => ()
            }
        case None => ()
    }
    let requestConversationId = gatewayControlUiWsString(params, "conversationId").trimAscii()
    let requestThreadId = gatewayControlUiWsString(params, "threadId").trimAscii()
    let requestSourceMessageId = gatewayControlUiWsString(params, "sourceMessageId").trimAscii()
    let requestReplyToMessageId = gatewayControlUiWsString(params, "replyToMessageId").trimAscii()
    let requestReplyInThread = gatewayControlUiWsString(params, "replyInThread").trimAscii().toAsciiLower()
    if (!requestConversationId.isEmpty() ||
        !requestThreadId.isEmpty() ||
        !requestSourceMessageId.isEmpty() ||
        !requestReplyToMessageId.isEmpty() ||
        requestReplyInThread == "true") {
        let binding = JsonObject()
        let requestDelivery = gatewayControlUiWsResolveDeliveryPayload(params, conversation: conversation)
        binding.put("channel", JsonString(match (requestDelivery) {
            case Some(delivery) => gatewayControlUiWsString(delivery, "channel").trimAscii()
            case None => match (conversation) {
                case Some(view) => view.channel
                case None => ""
            }
        }))
        binding.put("peer", JsonString(match (requestDelivery) {
            case Some(delivery) => gatewayControlUiWsString(delivery, "peer").trimAscii()
            case None => match (conversation) {
                case Some(view) => view.peer
                case None => ""
            }
        }))
        binding.put("accountId", JsonString(match (requestDelivery) {
            case Some(delivery) => gatewayControlUiWsString(delivery, "accountId").trimAscii()
            case None => ""
        }))
        binding.put("conversationId", JsonString(requestConversationId))
        binding.put("threadId", JsonString(requestThreadId))
        binding.put("sourceMessageId", JsonString(requestSourceMessageId))
        binding.put("replyTargetMessageId", JsonString(requestReplyToMessageId))
        binding.put("replyInThread", (requestReplyInThread == "true").toJsonValue())
        binding.put("mode", JsonString("request-derived"))
        return Some(binding)
    }
    match (conversation) {
        case Some(view) => Some(view.binding)
        case None => None<JsonObject>
    }
}

private func gatewayControlUiWsResolveDeliveryPayload(
    params: JsonObject,
    responseResult!: Option<JsonObject> = None<JsonObject>,
    conversation!: Option<GatewaySessionConversationView> = None<GatewaySessionConversationView>
): Option<JsonObject> {
    match (responseResult) {
        case Some(result) =>
            match (result.get("delivery")) {
                case Some(value) =>
                    try { return Some(value.asObject()) } catch (_: Exception) { () }
                case None => ()
            }
        case None => ()
    }
    let requestReplyChannel = gatewayControlUiWsString(params, "replyChannel").trimAscii()
    let requestReplyTo = gatewayControlUiWsString(params, "replyTo").trimAscii()
    let requestReplyToMessageId = gatewayControlUiWsString(params, "replyToMessageId").trimAscii()
    let requestReplyInThread = gatewayControlUiWsString(params, "replyInThread").trimAscii().toAsciiLower()
    let requestReplyAccountId = gatewayControlUiWsString(params, "replyAccountId").trimAscii()
    if (!requestReplyChannel.isEmpty() ||
        !requestReplyTo.isEmpty() ||
        !requestReplyToMessageId.isEmpty() ||
        requestReplyInThread == "true" ||
        !requestReplyAccountId.isEmpty()) {
        let delivery = JsonObject()
        delivery.put("channel", JsonString(requestReplyChannel))
        delivery.put("peer", JsonString(requestReplyTo))
        delivery.put("replyChannel", JsonString(requestReplyChannel))
        delivery.put("replyTo", JsonString(requestReplyTo))
        delivery.put("replyToMessageId", JsonString(requestReplyToMessageId))
        delivery.put("replyInThread", (requestReplyInThread == "true").toJsonValue())
        delivery.put("accountId", JsonString(requestReplyAccountId))
        delivery.put("deliverable", (!requestReplyChannel.isEmpty()).toJsonValue())
        delivery.put("mode", JsonString(if (requestReplyTo.isEmpty()) { "session-default" } else { "peer-target" }))
        return Some(delivery)
    }
    match (conversation) {
        case Some(view) => Some(view.delivery)
        case None => None<JsonObject>
    }
}

private func gatewayControlUiWsWriteChatEvent(
    clientId: String,
    sessionKey: String,
    runId: String,
    state: String,
    message: JsonObject,
    params!: JsonObject = JsonObject(),
    responseResult!: Option<JsonObject> = None<JsonObject>,
    errorMessage!: String = ""
): Unit {
    let user = CliSettingManager.readGatewaySettings()
    let conversation = gatewayFindSessionConversationViewForUser(user, sessionKey)
    let payload = gatewayControlUiWsChatEventPayload(
        sessionKey,
        runId,
        state,
        message,
        conversation: conversation,
        delivery: gatewayControlUiWsResolveDeliveryPayload(params, responseResult: responseResult, conversation: conversation),
        binding: gatewayControlUiWsResolveBindingPayload(params, responseResult: responseResult, conversation: conversation),
        errorMessage: errorMessage
    )
    let frame = gatewayControlUiWsChatEventFrame(clientId, state, payload)
    let _ = gatewayControlUiWsWriteJsonToClient(clientId, frame)
}

func gatewayControlUiWsResolveEventSessionKey(requestedSession: String, effectiveSession: String): String {
    let effective = effectiveSession.trimAscii()
    if (!effective.isEmpty()) {
        return effective
    }
    requestedSession.trimAscii()
}

func gatewayControlUiWsChatEventFrame(
    clientId: String,
    state: String,
    payload: JsonObject
): JsonObject {
    // Control UI chat relies on immediate websocket delivery; queue-only publication
    // can leave the page waiting until the next full history refresh.
    let event = JsonObject()
    event.put("id", JsonString("evt-control-ui-chat-${gatewayControlUiWsNowMs()}"))
    event.put("kind", JsonString("chat"))
    event.put("detail", JsonString(state))
    event.put("clientId", JsonString(clientId.trimAscii()))
    event.put("ts", gatewayControlUiWsNowMs().toJsonValue())
    event.put("payload", payload)
    gatewayControlUiWsEventFrame(event)
}

private func gatewayControlUiWsMaybeEmitChatEvents(
    clientId: String,
    normalizedMethod: String,
    originalParams: JsonObject,
    response: GatewayProtocolResponse
): Unit {
    if (normalizedMethod.trimAscii().toAsciiLower() != "dashboard.chat.send") {
        return
    }
    let sessionKey = gatewayControlUiWsString(originalParams, "sessionKey").trimAscii()
    let requestedSession = if (!sessionKey.isEmpty()) { sessionKey } else { gatewayControlUiWsString(originalParams, "session").trimAscii() }
    let messageRaw = gatewayControlUiWsString(originalParams, "message")
    let message = if (!messageRaw.trimAscii().isEmpty()) { messageRaw } else { gatewayControlUiWsString(originalParams, "text") }
    let runIdRaw = gatewayControlUiWsString(originalParams, "idempotencyKey").trimAscii()
    let runId = if (!runIdRaw.isEmpty()) { runIdRaw } else { "run-${gatewayControlUiWsNowMs()}" }
    if (!response.ok) {
        if (!requestedSession.isEmpty()) {
            gatewayControlUiWsWriteChatEvent(
                clientId,
                requestedSession,
                runId,
                "error",
                gatewayControlUiWsChatMessage("assistant", "", gatewayControlUiWsNowMs()),
                params: originalParams,
                errorMessage: response.error
            )
        }
        return
    }
    let root = try {
        response.result.asObject()
    } catch (_e: Exception) {
        return
    }
    let effectiveSession = gatewayControlUiWsString(root, "session").trimAscii()
    let effectiveAnswer = gatewayControlUiWsString(root, "answer")
    let eventSession = gatewayControlUiWsResolveEventSessionKey(requestedSession, effectiveSession)
    if (eventSession.isEmpty()) {
        return
    }
    LogUtils.info(
        "Gateway.control-ui.chat: requestedSession=${requestedSession}, effectiveSession=${effectiveSession}, eventSession=${eventSession}, ok=${response.ok}"
    )
    if (!message.trimAscii().isEmpty()) {
        gatewayControlUiWsWriteChatEvent(
            clientId,
            eventSession,
            runId,
            "delta",
            gatewayControlUiWsChatMessage("assistant", "", gatewayControlUiWsNowMs()),
            params: originalParams,
            responseResult: Some(root)
        )
    }
    gatewayControlUiWsWriteChatEvent(
        clientId,
        eventSession,
        runId,
        "final",
        gatewayControlUiWsChatMessage("assistant", effectiveAnswer, gatewayControlUiWsNowMs()),
        params: originalParams,
        responseResult: Some(root)
    )
}

private func gatewayControlUiWsChatAcceptedPayload(params: JsonObject): JsonObject {
    let payload = JsonObject()
    let user = CliSettingManager.readGatewaySettings()
    let sessionKey = gatewayControlUiWsString(params, "sessionKey").trimAscii()
    let requestedSession = if (!sessionKey.isEmpty()) { sessionKey } else { gatewayControlUiWsString(params, "session").trimAscii() }
    var conversation = None<GatewaySessionConversationView>
    if (!requestedSession.isEmpty()) {
        payload.put("sessionKey", JsonString(requestedSession))
        match (gatewayFindSessionConversationViewForUser(user, requestedSession)) {
            case Some(view) =>
                conversation = Some(view)
                payload.put("agentId", JsonString(view.agentId))
                payload.put("displayName", JsonString(view.displayName))
                payload.put("channel", JsonString(view.channel))
                payload.put("chatType", JsonString(view.chatType))
                payload.put("peer", JsonString(view.peer))
                payload.put("sessionId", JsonString(view.sessionId))
                payload.put("origin", view.origin)
                payload.put("binding", match (gatewayControlUiWsResolveBindingPayload(params, conversation: Some(view))) {
                    case Some(binding) => binding
                    case None => view.binding
                })
            case None => ()
        }
    }
    match (gatewayControlUiWsResolveDeliveryPayload(params, conversation: conversation)) {
        case Some(delivery) => payload.put("delivery", delivery)
        case None => ()
    }
    let runIdRaw = gatewayControlUiWsString(params, "idempotencyKey").trimAscii()
    let runId = if (!runIdRaw.isEmpty()) { runIdRaw } else { "run-${gatewayControlUiWsNowMs()}" }
    payload.put("runId", JsonString(runId))
    payload.put("accepted", true.toJsonValue())
    payload
}

private func gatewayControlUiWsHandleChatSendAsync(
    websocket: WebSocket,
    writeLock: Mutex,
    bound: GatewayConnectParams,
    frameId: String,
    params: JsonObject
): Unit {
    let accepted = GatewayProtocolResponse(
        true,
        "chat.send",
        requestId: frameId,
        result: gatewayControlUiWsChatAcceptedPayload(params)
    )
    gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(accepted, frameId))
    spawn {
        try {
            let response = gatewayControlUiWsGatewayRequest(bound, frameId, "dashboard.chat.send", params: params)
            gatewayControlUiWsMaybeEmitChatEvents(bound.client.id, "dashboard.chat.send", params, response)
            if (response.ok) {
                gatewayControlUiWsPublishInvalidate(bound, "dashboard.chat.send", params: params, response: Some(response))
            }
        } catch (e: Exception) {
            let sessionKey = gatewayControlUiWsString(params, "sessionKey").trimAscii()
            if (!sessionKey.isEmpty()) {
                let runIdRaw = gatewayControlUiWsString(params, "idempotencyKey").trimAscii()
                let runId = if (!runIdRaw.isEmpty()) { runIdRaw } else { "run-${gatewayControlUiWsNowMs()}" }
                gatewayControlUiWsWriteChatEvent(
                    bound.client.id,
                    sessionKey,
                    runId,
                    "error",
                    gatewayControlUiWsChatMessage("assistant", "", gatewayControlUiWsNowMs()),
                    params: params,
                    errorMessage: e.message
                )
            }
        }
    }
}

private func gatewayControlUiWsInvalidateSections(method: String): Array<String> {
    let normalized = method.trimAscii().toAsciiLower()
    if (normalized == "dashboard.chat.send") {
        return ["status", "history", "doctor"]
    }
    if (normalized == "dashboard.model.switch") {
        return ["status", "models", "doctor"]
    }
    if (normalized == "dashboard.skills.set" || normalized == "skills.update") {
        return ["status", "skills", "doctor"]
    }
    if (normalized == "dashboard.sessions.delete") {
        return ["status", "history", "sessions", "doctor"]
    }
    if (normalized == "dashboard.cron") {
        return ["status", "cron", "doctor"]
    }
    if (normalized == "config.patch" || normalized == "config.apply") {
        return ["status", "assets", "config", "doctor"]
    }
    []
}

func gatewayControlUiWsInvalidatePayload(
    method: String,
    params: JsonObject,
    response!: Option<GatewayProtocolResponse> = None<GatewayProtocolResponse>
): JsonObject {
    let sections = gatewayControlUiWsInvalidateSections(method)
    let payload = JsonObject()
    payload.put("reason", JsonString(method))
    payload.put("sections", sections.toJsonValue())
    let user = CliSettingManager.readGatewaySettings()
    let sessionKeyRaw = gatewayControlUiWsString(params, "sessionKey").trimAscii()
    let requestedSession = if (!sessionKeyRaw.isEmpty()) { sessionKeyRaw } else { gatewayControlUiWsString(params, "session").trimAscii() }
    let effectiveSession = match (response) {
        case Some(res) =>
            if (!res.ok) {
                ""
            } else {
                try {
                    gatewayControlUiWsString(res.result.asObject(), "session").trimAscii()
                } catch (_: Exception) {
                    ""
                }
            }
        case None => ""
    }
    let sessionKey = gatewayControlUiWsResolveEventSessionKey(requestedSession, effectiveSession)
    if (!sessionKey.isEmpty()) {
        payload.put("sessionKey", JsonString(sessionKey))
        match (gatewayFindSessionConversationViewForUser(user, sessionKey)) {
            case Some(view) =>
                payload.put("agentId", JsonString(view.agentId))
                payload.put("displayName", JsonString(view.displayName))
                payload.put("channel", JsonString(view.channel))
                payload.put("chatType", JsonString(view.chatType))
                payload.put("peer", JsonString(view.peer))
                payload.put("sessionId", JsonString(view.sessionId))
                payload.put("origin", view.origin)
                payload.put("binding", match (gatewayControlUiWsResolveBindingPayload(params, responseResult: match (response) {
                    case Some(res) =>
                        if (!res.ok) {
                            None<JsonObject>
                        } else {
                            try { Some(res.result.asObject()) } catch (_: Exception) { None<JsonObject> }
                        }
                    case None => None<JsonObject>
                }, conversation: Some(view))) {
                    case Some(binding) => binding
                    case None => view.binding
                })
                payload.put("delivery", match (gatewayControlUiWsResolveDeliveryPayload(params, responseResult: match (response) {
                    case Some(res) =>
                        if (!res.ok) {
                            None<JsonObject>
                        } else {
                            try { Some(res.result.asObject()) } catch (_: Exception) { None<JsonObject> }
                        }
                    case None => None<JsonObject>
                }, conversation: Some(view))) {
                    case Some(delivery) => delivery
                    case None => view.delivery
                })
            case None => ()
        }
    }
    payload
}

private func gatewayControlUiWsPublishInvalidate(
    connect: GatewayConnectParams,
    method: String,
    params!: JsonObject = JsonObject(),
    response!: Option<GatewayProtocolResponse> = None<GatewayProtocolResponse>
): Unit {
    let sections = gatewayControlUiWsInvalidateSections(method)
    if (sections.isEmpty()) {
        return
    }
    let payload = gatewayControlUiWsInvalidatePayload(method, params, response: response)
    gatewayServerPublishClientEvent(connect.client.id, "control-ui.invalidate", detail: method, payload: payload)
}

private func gatewayControlUiWsPushStreamEvents(
    websocket: WebSocket,
    writeLock: Mutex,
    result: JsonValue
): Unit {
    try {
        let root = result.asObject()
        let pull = gatewayControlUiWsObject(root, "pull")
        let events = match (pull.get("events")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        var i: Int64 = 0
        while (i < Int64(events.size())) {
            try {
                gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsEventFrame(events[i].asObject()))
            } catch (_inner: Exception) {
                ()
            }
            i += 1
        }
    } catch (_e: Exception) {
        ()
    }
}

private func gatewayControlUiWsHandleConnect(
    websocket: WebSocket,
    cfg: GatewayConfig,
    writeLock: Mutex,
    stateLock: Mutex,
    state: GatewayControlUiWsSessionState,
    frameId: String,
    payload: JsonObject
): Unit {
    let defaultConnectionId = synchronized(stateLock) {
        if (state.connectionId.trimAscii().isEmpty()) {
            let hintedClientId = gatewayControlUiWsString(gatewayControlUiWsObject(payload, "client"), "id").trimAscii()
            let fallbackClientId = if (!hintedClientId.isEmpty()) {
                hintedClientId
            } else {
                gatewayControlUiWsString(payload, "clientId").trimAscii()
            }
            state.connectionId = gatewayControlUiWsNextConnectionId(fallbackClientId)
        }
        state.connectionId
    }
    let connect = gatewayControlUiWsBuildConnectParams(cfg, payload, defaultConnectionId)
    if (!validateGatewayConnectParams(connect)) {
        LogUtils.error("Gateway.control-ui.ws: connect rejected, invalid params clientId=${connect.client.id}")
        gatewayControlUiWsWriteInvalidConnect(websocket, writeLock, frameId)
        return
    }
    let response = gatewayControlUiWsGatewayConnectRequest(connect, frameId)
    if (response.ok) {
        let effectiveResponse = gatewayControlUiWsMaybeAutoAckChallenge(connect, response)
        if (!effectiveResponse.ok) {
            LogUtils.error("Gateway.control-ui.ws: connect failed clientId=${connect.client.id} error=${effectiveResponse.error}")
            gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(effectiveResponse, frameId))
            return
        }
        synchronized(stateLock) {
            state.connectParams = Some(connect)
            if (state.registryToken.isEmpty()) {
                state.registryToken = "conn-${gatewayControlUiWsNowMs()}"
            }
        }
        gatewayControlUiWsRegisterConnection(connect.client.id, synchronized(stateLock) { state.registryToken }, websocket, writeLock)
        LogUtils.info("Gateway.control-ui.ws: connect ok clientId=${connect.client.id}")
        gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(effectiveResponse, frameId))
        return
    }
    LogUtils.error("Gateway.control-ui.ws: connect failed clientId=${connect.client.id} error=${response.error}")
    gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
}

private func gatewayControlUiWsHandleRequest(
    websocket: WebSocket,
    cfg: GatewayConfig,
    writeLock: Mutex,
    stateLock: Mutex,
    state: GatewayControlUiWsSessionState,
    frameId: String,
    method: String,
    params: JsonObject
): Unit {
    let connect = synchronized(stateLock) {
        state.connectParams
    }
    match (connect) {
        case Some(bound) =>
            if (method.trimAscii().toAsciiLower() == "sessions.subscribe") {
                let response = gatewayControlUiWsSessionSubscribeRequest(bound, frameId)
                gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
                return
            }
            if (method.trimAscii().toAsciiLower() == "sessions.unsubscribe") {
                let response = gatewayControlUiWsSessionUnsubscribeRequest(bound, frameId)
                gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
                return
            }
            match (gatewayControlUiWsCompatResponse(method, params, cfg)) {
                case Some(compatResponse) =>
                    gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(compatResponse, frameId))
                    return
                case None => ()
            }
            let normalizedMethod = gatewayControlUiWsMethodAlias(method)
            if (normalizedMethod.trimAscii().toAsciiLower() == "dashboard.chat.send") {
                gatewayControlUiWsHandleChatSendAsync(websocket, writeLock, bound, frameId, params)
                return
            }
            let response = gatewayControlUiWsGatewayRequest(bound, frameId, normalizedMethod, params: params)
            if (response.ok && normalizedMethod.trimAscii().toAsciiLower() == "events.stream") {
                gatewayControlUiWsPushStreamEvents(websocket, writeLock, response.result)
            }
            gatewayControlUiWsMaybeEmitChatEvents(bound.client.id, normalizedMethod, params, response)
            if (response.ok) {
                gatewayControlUiWsPublishInvalidate(bound, normalizedMethod, params: params, response: Some(response))
            }
            gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
        case None =>
            let response = GatewayProtocolResponse(false, method, requestId: frameId, error: "Gateway websocket client is not connected.", errorCode: GATEWAY_ERROR_NOT_CONNECTED)
            gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
    }
}

private func gatewayControlUiWsHandleDisconnect(
    websocket: WebSocket,
    writeLock: Mutex,
    stateLock: Mutex,
    state: GatewayControlUiWsSessionState,
    frameId: String
): Unit {
    let connect = synchronized(stateLock) {
        let current = state.connectParams
        state.connectParams = None<GatewayConnectParams>
        current
    }
    match (connect) {
        case Some(bound) =>
            let response = gatewayControlUiWsGatewayDisconnectRequest(bound, frameId)
            gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
            try {
                websocket.closeConn()
            } catch (_e: Exception) {
                ()
            }
        case None =>
            let response = GatewayProtocolResponse(true, "disconnect", requestId: frameId, result: JsonObject())
            gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
    }
}

private func gatewayControlUiWsHandleFrame(
    websocket: WebSocket,
    cfg: GatewayConfig,
    writeLock: Mutex,
    stateLock: Mutex,
    state: GatewayControlUiWsSessionState,
    raw: String
): Unit {
    let root = try {
        JsonValue.fromStr(raw).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let frameType = gatewayControlUiWsString(root, "type").trimAscii().toAsciiLower()
    let frameIdRaw = gatewayControlUiWsString(root, "id").trimAscii()
    let requestIdRaw = gatewayControlUiWsString(root, "requestId").trimAscii()
    let frameId = if (!frameIdRaw.isEmpty()) {
        frameIdRaw
    } else if (!requestIdRaw.isEmpty()) {
        requestIdRaw
    } else {
        "gw-ws-${gatewayControlUiWsNowMs()}"
    }
    let method = gatewayControlUiWsString(root, "method").trimAscii()
    let payloadObj = gatewayControlUiWsObject(root, "payload")
    let paramsObj = gatewayControlUiWsObject(root, "params")
    let payload = if (payloadObj.size() > 0) { payloadObj } else { paramsObj }
    LogUtils.info("Gateway.control-ui.ws: frame received type=${if (frameType.isEmpty()) { "<empty>" } else { frameType }} method=${if (method.isEmpty()) { "<empty>" } else { method }}")
    if (frameType.isEmpty() && !method.isEmpty()) {
        if (method.trimAscii().toAsciiLower() == "connect") {
            gatewayControlUiWsHandleConnect(websocket, cfg, writeLock, stateLock, state, frameId, payload)
            return
        }
        if (method.trimAscii().toAsciiLower() == "disconnect") {
            gatewayControlUiWsHandleDisconnect(websocket, writeLock, stateLock, state, frameId)
            return
        }
        gatewayControlUiWsHandleRequest(websocket, cfg, writeLock, stateLock, state, frameId, method, payload)
        return
    }
    if (frameType == "ping") {
        let pong = JsonObject()
        pong.put("type", JsonString("pong"))
        pong.put("id", JsonString(frameId))
        pong.put("ts", gatewayControlUiWsNowMs().toJsonValue())
        gatewayControlUiWsWriteJson(websocket, writeLock, pong)
        return
    }
    if (frameType == "disconnect") {
        gatewayControlUiWsHandleDisconnect(websocket, writeLock, stateLock, state, frameId)
        return
    }
    if (frameType == "connect") {
        gatewayControlUiWsHandleConnect(websocket, cfg, writeLock, stateLock, state, frameId, payload)
        return
    }
    if (frameType == "req") {
        let normalizedMethod = method.trimAscii().toAsciiLower()
        if (normalizedMethod == "connect") {
            gatewayControlUiWsHandleConnect(websocket, cfg, writeLock, stateLock, state, frameId, payload)
            return
        }
        if (normalizedMethod == "disconnect") {
            gatewayControlUiWsHandleDisconnect(websocket, writeLock, stateLock, state, frameId)
            return
        }
        gatewayControlUiWsHandleRequest(websocket, cfg, writeLock, stateLock, state, frameId, method, payload)
        return
    }
    let response = GatewayProtocolResponse(false, "unknown", requestId: frameId, error: "Unsupported gateway websocket frame.", errorCode: "UNSUPPORTED_FRAME")
    LogUtils.error("Gateway.control-ui.ws: unsupported frame type=${frameType} method=${method}")
    gatewayControlUiWsWriteJson(websocket, writeLock, gatewayControlUiWsResponseFrame(response, frameId))
}

public func gatewayHandleControlUiWebSocket(ctx: HttpContext, cfg: GatewayConfig): Unit {
    let contract = GatewayControlUiRuntime.controlUiContract(cfg)
    LogUtils.info("Gateway.control-ui.ws: upgrade request")
    let websocket = if (contract.allowedOrigins.isEmpty()) {
        WebSocket.upgradeFromServer(ctx)
    } else {
        let origins = ArrayList<String>()
        for (origin in contract.allowedOrigins) {
            origins.add(origin)
        }
        WebSocket.upgradeFromServer(ctx, origins: origins)
    }
    let writeLock = Mutex()
    let stateLock = Mutex()
    let state = GatewayControlUiWsSessionState()
    try {
        LogUtils.info("Gateway.control-ui.ws: upgrade ok")
        let nonce = gatewayControlUiWsWriteConnectChallenge(websocket, writeLock)
        LogUtils.info("Gateway.control-ui.ws: challenge sent nonce=${nonce}")
        while (true) {
            let frame = websocket.read()
            if (frame.frameType == CloseWebFrame) {
                LogUtils.info("Gateway.control-ui.ws: received close frame")
                break
            }
            if (frame.frameType != TextWebFrame) {
                continue
            }
            let raw = try {
                String.fromUtf8(frame.payload)
            } catch (_e: Exception) {
                ""
            }
            if (raw.trimAscii().isEmpty()) {
                continue
            }
            try {
                gatewayControlUiWsHandleFrame(websocket, cfg, writeLock, stateLock, state, raw)
            } catch (e: Exception) {
                LogUtils.error("Gateway.control-ui.ws: frame handling failed: ${e.message}")
            }
        }
    } finally {
        let closing = synchronized(stateLock) {
            state.closed = true
            (state.connectParams, state.registryToken)
        }
        match (closing[0]) {
            case Some(bound) => gatewayControlUiWsCloseBoundClient(bound, closing[1])
            case None => ()
        }
        try {
            websocket.closeConn()
        } catch (_e: Exception) {
            ()
        }
    }
}

private func gatewayControlUiWsCloseBoundClient(bound: GatewayConnectParams, token: String): Unit {
    gatewayControlUiWsUnregisterConnection(bound.client.id, token)
    let stopped = GatewayServer.defaultServer().stopAndWait(
        clientId: bound.client.id,
        timeoutMs: 250,
        connectionId: bound.connectionId
    )
    if (stopped) {
        LogUtils.info("Gateway.control-ui.ws: closing clientId=${bound.client.id}")
    } else {
        LogUtils.info("Gateway.control-ui.ws: skip stale close clientId=${bound.client.id} connectionId=${bound.connectionId}")
    }
}
