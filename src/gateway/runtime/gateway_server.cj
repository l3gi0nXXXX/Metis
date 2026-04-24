package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.CliConfig
import metis.core.config.CliSettingManager
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.model.GatewayConfig
import metis.gateway.core.{gatewayBuildSessionEventPayload, gatewayChatEventShouldPublishToClient, gatewayFindSessionCatalogRowForUser, gatewayFindSessionConversationViewForUser, gatewaySessionStoreForSessionKey}
import metis.gateway.protocol.{GATEWAY_ERROR_AUTH_FAILED, GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED, GATEWAY_ERROR_CONNECT_FAILED, GATEWAY_ERROR_INVALID_CONNECT, GATEWAY_ERROR_NOT_CONNECTED, GATEWAY_ERROR_REQUEST_CANCELLED, GATEWAY_ERROR_REQUEST_TIMEOUT, GATEWAY_ERROR_TRANSPORT_DISABLED, GATEWAY_ERROR_UNSUPPORTED_METHOD, GATEWAY_ERROR_UNSUPPORTED_PROTOCOL, GATEWAY_PROTOCOL_VERSION, GatewayClientInfo, GatewayConnectParams, GatewayProtocolRequest, GatewayProtocolResponse, validateGatewayConnectParams, validateGatewayProtocolVersion}
import metis.gateway.security.gatewayAuthorizeProtocolRequest

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{File, exists}
import std.sync.Mutex
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let gatewayServerLock = Mutex()
private var gatewayServerStarted: Bool = false
private var gatewayServerStartedAtMs: Int64 = 0
private var gatewayServerRequestCount: Int64 = 0
private var gatewayServerActiveRequests: Int64 = 0
private var gatewayServerLastRequestAtMs: Int64 = 0
private var gatewayServerLastRequestMethod: String = ""
private var gatewayServerLastError: String = ""
private var gatewayServerLastConnectAtMs: Int64 = 0
private var gatewayServerLastDisconnectAtMs: Int64 = 0
private var gatewayActiveRequestMethodById = HashMap<String, String>()
private var gatewayActiveRequestClientById = HashMap<String, String>()
private var gatewayActiveRequestSessionById = HashMap<String, String>()
private var gatewayActiveRequestStartedAtById = HashMap<String, Int64>()
private var gatewayConnectedAtByClient = HashMap<String, Int64>()
private var gatewayLastSeenAtByClient = HashMap<String, Int64>()
private var gatewayClientNameById = HashMap<String, String>()
private var gatewayClientModeById = HashMap<String, String>()
private var gatewayTransportById = HashMap<String, String>()
private var gatewayTransportKindById = HashMap<String, String>()
private var gatewayUrlById = HashMap<String, String>()
private var gatewaySessionKeyByClient = HashMap<String, String>()
private var gatewaySessionHintByClient = HashMap<String, String>()
private var gatewayConnectionIdByClient = HashMap<String, String>()
private var gatewayCapabilitiesByClient = HashMap<String, Array<String>>()
private var gatewayChallengeTokenByConnection = HashMap<String, String>()
private var gatewayChallengeExpiresAtByConnection = HashMap<String, Int64>()
private var gatewayChallengeAckedByConnection = HashMap<String, Bool>()
private var gatewayChallengeClientIdByConnection = HashMap<String, String>()
private var gatewayEventQueueByClient = HashMap<String, ArrayList<JsonObject>>()
private var gatewaySessionEventSubscriberKindsByClient = HashMap<String, Array<String>>()
private var gatewaySessionMessageSubscriberKeysByClient = HashMap<String, Array<String>>()
private var gatewaySessionMessageSubscribersBySessionKey = HashMap<String, Array<String>>()
private var gatewayRecentEvents = ArrayList<JsonObject>()
private var gatewayEventSequence: Int64 = 0
private var gatewayLastDeliveredEventSeqByClient = HashMap<String, Int64>()
private var gatewayLastPullAtByClient = HashMap<String, Int64>()
private var gatewayDeliveredEventCountByClient = HashMap<String, Int64>()
private var gatewayPeekPullCountByClient = HashMap<String, Int64>()
private var gatewayLastCursorByClient = HashMap<String, String>()
private var gatewayEventKindsByClient = HashMap<String, Array<String>>()
private var gatewayStreamOpenCountByClient = HashMap<String, Int64>()
private var gatewayStreamLastOpenAtByClient = HashMap<String, Int64>()
private var gatewayStreamLastCloseAtByClient = HashMap<String, Int64>()
private var gatewayStreamLastWaitMsByClient = HashMap<String, Int64>()
private var gatewayStreamActiveByClient = HashMap<String, Bool>()
private var gatewayStreamLeaseExpiresAtByClient = HashMap<String, Int64>()
private var gatewayStreamKeepaliveCountByClient = HashMap<String, Int64>()
private var gatewayStreamIdByClient = HashMap<String, String>()
private var gatewayStreamPendingPushCountByClient = HashMap<String, Int64>()
private var gatewayStreamWaiterCountByClient = HashMap<String, Int64>()
private var gatewayStreamWakeCountByClient = HashMap<String, Int64>()
private var gatewayStreamLastServerPushAtByClient = HashMap<String, Int64>()
private var gatewayStreamStateByClient = HashMap<String, String>()
private var gatewayStreamSessionGenerationByClient = HashMap<String, Int64>()
private var gatewayStreamLastModeByClient = HashMap<String, String>()
private var gatewayStreamPhaseByClient = HashMap<String, String>()
private var gatewayStreamAttachCountByClient = HashMap<String, Int64>()
private var gatewayStreamDetachCountByClient = HashMap<String, Int64>()
private var gatewayStreamLastAttachAtByClient = HashMap<String, Int64>()
private var gatewayStreamLastDetachAtByClient = HashMap<String, Int64>()
private var gatewayStreamLastWakeReasonByClient = HashMap<String, String>()
private const GATEWAY_EVENT_QUEUE_MAX_PER_CLIENT: Int64 = 128
private const GATEWAY_SERVER_SNAPSHOT_WRITE_INTERVAL_MS: Int64 = 1000
private var gatewayServerTimeoutCount: Int64 = 0
private var gatewayServerCancelCount: Int64 = 0
private var gatewayServerChallengeIssuedCount: Int64 = 0
private var gatewayServerChallengeAckCount: Int64 = 0
private var gatewayServerLastPersistAtMs: Int64 = 0
private var gatewayServerSnapshotDirty: Bool = false
private var gatewayServerCurrentOptions = GatewayServerOptions()

private func gatewayServerChallengeKey(connectionId: String, clientId: String): String {
    let normalizedConnectionId = connectionId.trimAscii()
    if (!normalizedConnectionId.isEmpty()) {
        return normalizedConnectionId
    }
    clientId.trimAscii()
}

private func gatewayServerChallengeKeyForConnect(connect: GatewayConnectParams): String {
    gatewayServerChallengeKey(connect.connectionId, connect.client.id)
}

private func gatewayServerClearChallengeLocked(connectionId: String, clientId!: String = ""): Unit {
    let key = gatewayServerChallengeKey(connectionId, clientId)
    if (key.isEmpty()) {
        return
    }
    gatewayChallengeTokenByConnection.remove(key)
    gatewayChallengeExpiresAtByConnection.remove(key)
    gatewayChallengeAckedByConnection.remove(key)
    gatewayChallengeClientIdByConnection.remove(key)
}

public class GatewayServerOptions {
    public let serverName: String
    public let bindMode: String
    public let bindAddress: String
    public let localTransportEnabled: Bool
    public let remoteTransportEnabled: Bool
    public let requestTimeoutMs: Int64
    public let defaultGatewayUrl: String
    public let enableHandshake: Bool

    public init(
        serverName!: String = "metis-gateway",
        bindMode!: String = "local",
        bindAddress!: String = "local://gateway",
        localTransportEnabled!: Bool = true,
        remoteTransportEnabled!: Bool = false,
        requestTimeoutMs!: Int64 = 3000,
        defaultGatewayUrl!: String = "local://gateway",
        enableHandshake!: Bool = true
    ) {
        this.serverName = serverName
        this.bindMode = bindMode
        this.bindAddress = bindAddress
        this.localTransportEnabled = localTransportEnabled
        this.remoteTransportEnabled = remoteTransportEnabled
        this.requestTimeoutMs = requestTimeoutMs
        this.defaultGatewayUrl = defaultGatewayUrl
        this.enableHandshake = enableHandshake
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("serverName", JsonString(this.serverName))
        obj.put("bindMode", JsonString(this.bindMode))
        obj.put("bindAddress", JsonString(this.bindAddress))
        obj.put("localTransportEnabled", this.localTransportEnabled.toJsonValue())
        obj.put("remoteTransportEnabled", this.remoteTransportEnabled.toJsonValue())
        obj.put("requestTimeoutMs", this.requestTimeoutMs.toJsonValue())
        obj.put("defaultGatewayUrl", JsonString(this.defaultGatewayUrl))
        obj.put("enableHandshake", this.enableHandshake.toJsonValue())
        obj
    }
}

public class GatewayServer {
    private static let shared = GatewayServer()
    private var options: GatewayServerOptions

    public init(options!: GatewayServerOptions = GatewayServerOptions()) {
        this.options = options
    }

    public static func defaultServer(): GatewayServer {
        shared.ensureStarted()
        shared
    }

    public static func startGatewayServer(options!: GatewayServerOptions = GatewayServerOptions()): GatewayServer {
        let server = defaultServer()
        synchronized(gatewayServerLock) {
            gatewayServerCurrentOptions = options
            server.options = options
        }
        server.ensureStarted()
        server
    }

    public static func statePath(): String {
        CliConfig.dotDir.join("gateway-rpc-state.json").toString()
    }

    public static func snapshot(): JsonObject {
        synchronized(gatewayServerLock) {
            gatewayServerExpireStreamLeasesLocked()
            persistSnapshotLocked(force: true)
            buildSnapshotLocked()
        }
    }

    public func ensureStarted(): Unit {
        synchronized(gatewayServerLock) {
            if (!gatewayServerStarted) {
                gatewayServerStarted = true
                gatewayServerStartedAtMs = gatewayServerNowMs()
                gatewayServerLastError = ""
            }
            gatewayServerCurrentOptions = this.options
            persistSnapshotLocked(force: true)
        }
    }

    public func stopServer(reason!: String = "shutdown"): Unit {
        synchronized(gatewayServerLock) {
            gatewayServerStarted = false
            gatewayServerActiveRequests = 0
            gatewayServerLastError = reason
            persistSnapshotLockedWithOptions(this.options, force: true)
        }
    }

    public func connect(params: GatewayConnectParams): Bool {
        this.ensureStarted()
        if (!validateGatewayConnectParams(params)) {
            synchronized(gatewayServerLock) {
                gatewayServerLastError = "invalid-connect-params"
                persistSnapshotLockedWithOptions(this.options)
            }
            return false
        }
        synchronized(gatewayServerLock) {
            gatewayServerCleanupExpiredRequestsLocked(this.options)
            gatewayServerExpireStreamLeasesLocked()
            if (!gatewayServerTransportAllowedLocked(params, this.options)) {
                gatewayServerLastError = "transport-not-enabled"
                persistSnapshotLockedWithOptions(this.options)
                return false
            }
            let clientId = params.client.id.trimAscii()
            let ts = gatewayServerNowMs()
            gatewayConnectedAtByClient[clientId] = existingIntOr(clientId, gatewayConnectedAtByClient, ts)
            gatewayLastSeenAtByClient[clientId] = ts
            gatewayClientNameById[clientId] = params.client.name
            gatewayClientModeById[clientId] = params.client.mode
            gatewayTransportById[clientId] = params.transport
            gatewayTransportKindById[clientId] = params.transportKind
            gatewayUrlById[clientId] = params.gatewayUrl
            gatewaySessionKeyByClient[clientId] = params.sessionKey
            gatewaySessionHintByClient[clientId] = params.sessionHint
            let previousConnectionId = existingStringOr(clientId, gatewayConnectionIdByClient, "")
            gatewayConnectionIdByClient[clientId] = params.connectionId
            gatewayCapabilitiesByClient[clientId] = params.capabilities
            if (!previousConnectionId.isEmpty() && previousConnectionId != params.connectionId) {
                gatewayServerClearChallengeLocked(previousConnectionId, clientId: clientId)
            }
            let challenge = gatewayServerIssueChallengeLocked(params, this.options)
            let challengeKey = gatewayServerChallengeKeyForConnect(params)
            gatewayChallengeTokenByConnection[challengeKey] = challenge[0]
            gatewayChallengeExpiresAtByConnection[challengeKey] = challenge[1]
            gatewayChallengeAckedByConnection[challengeKey] = challenge[0].isEmpty()
            gatewayChallengeClientIdByConnection[challengeKey] = clientId
            if (!challenge[0].isEmpty()) {
                gatewayServerChallengeIssuedCount += 1
                let _ = gatewayServerPublishSessionUpdateForClient(
                    clientId,
                    "challenge-issued",
                    detail: "connect-challenge-issued",
                    runId: params.connectionId
                )
            }
            gatewayServerLastConnectAtMs = ts
            gatewayServerLastRequestAtMs = ts
            gatewayServerLastRequestMethod = "connect"
            gatewayServerLastError = ""
            gatewayServerPublishEventLocked(clientId, "connect", detail: "client-connected")
            let _ = gatewayServerPublishSessionLifecycleForClient(clientId, "bound", detail: "client-connected", runId: params.connectionId)
            persistSnapshotLockedWithOptions(this.options)
            true
        }
    }

    public func request(req: GatewayProtocolRequest): GatewayProtocolResponse {
        this.ensureStarted()
        if (!validateGatewayProtocolVersion(req.protocolVersion)) {
            synchronized(gatewayServerLock) {
                gatewayServerLastError = "unsupported-protocol-version"
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(
                false,
                req.method,
                requestId: req.requestId,
                error: "Unsupported gateway protocol version: ${req.protocolVersion}",
                errorCode: GATEWAY_ERROR_UNSUPPORTED_PROTOCOL
            )
        }
        if (!validateGatewayConnectParams(req.connect)) {
            synchronized(gatewayServerLock) {
                gatewayServerLastError = "invalid-connect-params"
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Invalid gateway connect params.", errorCode: GATEWAY_ERROR_INVALID_CONNECT)
        }
        synchronized(gatewayServerLock) {
            gatewayServerCleanupExpiredRequestsLocked(this.options)
            gatewayServerExpireStreamLeasesLocked()
            if (!gatewayServerTransportAllowedLocked(req.connect, this.options)) {
                gatewayServerLastError = "transport-not-enabled"
                persistSnapshotLockedWithOptions(this.options)
                return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Gateway transport is not enabled.", errorCode: GATEWAY_ERROR_TRANSPORT_DISABLED)
            }
            let clientId = req.connect.client.id.trimAscii()
            if (req.method == "connect") {
                let ok = this.connect(req.connect)
                if (!ok) {
                    return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Gateway connect failed.", errorCode: GATEWAY_ERROR_CONNECT_FAILED)
                }
            } else if (!gatewayConnectedAtByClient.contains(clientId)) {
                let ok = this.connect(req.connect)
                if (!ok) {
                    return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Gateway connect failed.", errorCode: GATEWAY_ERROR_CONNECT_FAILED)
                }
            } else {
                gatewayLastSeenAtByClient[clientId] = gatewayServerNowMs()
                persistSnapshotLockedWithOptions(this.options)
            }
            gatewayServerRequestCount += 1
            gatewayServerActiveRequests += 1
            gatewayServerLastRequestAtMs = gatewayServerNowMs()
            gatewayServerLastRequestMethod = req.method
            gatewayServerLastError = ""
            gatewayServerBeginRequestLocked(req)
            persistSnapshotLockedWithOptions(this.options)
        }
        let user = CliSettingManager.readGatewaySettings()
        let cfg = buildGatewayConfigFromUserSettings(user)
        let authz = gatewayAuthorizeProtocolRequest(cfg, req)
        if (!authz.ok) {
            synchronized(gatewayServerLock) {
                gatewayServerLastError = authz.error
                gatewayServerFinishRequestLocked(req, ok: false, error: authz.error)
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: authz.error, errorCode: GATEWAY_ERROR_AUTH_FAILED)
        }
        if (req.method == "connect") {
            synchronized(gatewayServerLock) {
                gatewayServerFinishRequestLocked(req, ok: true)
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(
                true,
                req.method,
                requestId: req.requestId,
                result: gatewayServerHandshakeJson(this.options, req.connect)
            )
        }
        if (req.method == "connect.ack") {
            let ack = synchronized(gatewayServerLock) {
                gatewayServerAcknowledgeChallengeLocked(req)
            }
            synchronized(gatewayServerLock) {
                gatewayServerFinishRequestLocked(req, ok: ack.ok, error: ack.error)
                persistSnapshotLockedWithOptions(this.options)
            }
            return ack
        }
        if (req.method == "disconnect") {
            let _ = this.stopAndWait(clientId: req.connect.client.id, timeoutMs: req.connect.timeoutMs)
            let result = JsonObject()
            result.put("disconnected", true.toJsonValue())
            result.put("clientId", JsonString(req.connect.client.id))
            synchronized(gatewayServerLock) {
                gatewayServerFinishRequestLocked(req, ok: true)
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(true, req.method, requestId: req.requestId, result: result)
        }
        if (req.method == "request.cancel") {
            let cancelled = synchronized(gatewayServerLock) {
                gatewayServerCancelRequestLocked(req)
            }
            synchronized(gatewayServerLock) {
                gatewayServerFinishRequestLocked(req, ok: cancelled.ok, error: cancelled.error)
                persistSnapshotLockedWithOptions(this.options)
            }
            return cancelled
        }
        if (req.method == "events.pull") {
            let events = synchronized(gatewayServerLock) {
                gatewayServerPullEventsLocked(req)
            }
            synchronized(gatewayServerLock) {
                gatewayServerFinishRequestLocked(req, ok: true)
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(true, req.method, requestId: req.requestId, result: events)
        }
        if (req.method == "events.stream") {
            let events = gatewayServerStreamEvents(req)
            synchronized(gatewayServerLock) {
                gatewayServerFinishRequestLocked(req, ok: true)
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(true, req.method, requestId: req.requestId, result: events)
        }
        if (req.method == "stream.close") {
            let result = synchronized(gatewayServerLock) {
                gatewayServerCloseStreamLocked(gatewayServerTargetClientId(req))
            }
            synchronized(gatewayServerLock) {
                gatewayServerFinishRequestLocked(req, ok: true)
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(true, req.method, requestId: req.requestId, result: result)
        }
        let challengePending = synchronized(gatewayServerLock) {
            gatewayServerChallengePendingLocked(req.connect)
        }
        if (challengePending) {
            synchronized(gatewayServerLock) {
                let _ = gatewayServerPublishSessionUpdateForClient(
                    req.connect.client.id.trimAscii(),
                    "challenge-required",
                    detail: "connect-challenge-required",
                    runId: req.requestId,
                    errorMessage: "connect-challenge-required"
                )
                gatewayServerFinishRequestLocked(req, ok: false, error: "connect-challenge-required")
                persistSnapshotLockedWithOptions(this.options)
            }
            return GatewayProtocolResponse(
                false,
                req.method,
                requestId: req.requestId,
                error: "Gateway connect challenge acknowledgement required.",
                errorCode: GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED,
                details: gatewayServerChallengeDetails(req.connect)
            )
        }
        let localReq = GatewayRpcRequest(
            req.method,
            params: req.params,
            clientId: req.connect.client.id,
            clientName: req.connect.client.name,
            mode: req.connect.client.mode,
            transport: req.connect.transport,
            transportKind: req.connect.transportKind,
            gatewayUrl: req.connect.gatewayUrl
        )
        let localRes = gatewayDispatchLocalMethod(localReq)
        let response = GatewayProtocolResponse(
            localRes.ok,
            localRes.method,
            requestId: req.requestId,
            result: localRes.result,
            error: localRes.error,
            errorCode: if (localRes.ok) { "" } else { GATEWAY_ERROR_UNSUPPORTED_METHOD }
        )
        synchronized(gatewayServerLock) {
            gatewayServerFinishRequestLocked(req, ok: response.ok, error: response.error)
            persistSnapshotLockedWithOptions(this.options)
        }
        response
    }

    public func stopAndWait(clientId!: String = "", timeoutMs!: Int64 = 1000): Bool {
        synchronized(gatewayServerLock) {
            let normalized = clientId.trimAscii()
            if (normalized.isEmpty()) {
                gatewayConnectedAtByClient.clear()
                gatewayLastSeenAtByClient.clear()
                gatewayClientNameById.clear()
                gatewayClientModeById.clear()
                gatewayTransportById.clear()
                gatewayTransportKindById.clear()
                gatewayUrlById.clear()
                gatewaySessionKeyByClient.clear()
                gatewaySessionHintByClient.clear()
                gatewayConnectionIdByClient.clear()
                gatewayCapabilitiesByClient.clear()
                gatewayChallengeTokenByConnection.clear()
                gatewayChallengeExpiresAtByConnection.clear()
                gatewayChallengeAckedByConnection.clear()
                gatewayChallengeClientIdByConnection.clear()
                gatewayEventQueueByClient.clear()
                gatewaySessionEventSubscriberKindsByClient.clear()
                gatewaySessionMessageSubscriberKeysByClient.clear()
                gatewaySessionMessageSubscribersBySessionKey.clear()
                gatewayRecentEvents.clear()
                gatewayLastDeliveredEventSeqByClient.clear()
                gatewayLastPullAtByClient.clear()
                gatewayDeliveredEventCountByClient.clear()
                gatewayPeekPullCountByClient.clear()
                gatewayLastCursorByClient.clear()
                gatewayEventKindsByClient.clear()
                gatewayStreamOpenCountByClient.clear()
                gatewayStreamLastOpenAtByClient.clear()
                gatewayStreamLastCloseAtByClient.clear()
                gatewayStreamLastWaitMsByClient.clear()
                gatewayStreamActiveByClient.clear()
                gatewayStreamLeaseExpiresAtByClient.clear()
                gatewayStreamKeepaliveCountByClient.clear()
                gatewayStreamIdByClient.clear()
                gatewayStreamPendingPushCountByClient.clear()
                gatewayStreamWaiterCountByClient.clear()
                gatewayStreamWakeCountByClient.clear()
                gatewayStreamLastServerPushAtByClient.clear()
                gatewayStreamStateByClient.clear()
                gatewayStreamSessionGenerationByClient.clear()
                gatewayStreamLastModeByClient.clear()
                gatewayStreamPhaseByClient.clear()
                gatewayStreamAttachCountByClient.clear()
                gatewayStreamDetachCountByClient.clear()
                gatewayStreamLastAttachAtByClient.clear()
                gatewayStreamLastDetachAtByClient.clear()
                gatewayStreamLastWakeReasonByClient.clear()
            } else {
                let _ = gatewayServerPublishSessionLifecycleForClient(normalized, "unbound", detail: "client-disconnected")
                let connectionId = existingStringOr(normalized, gatewayConnectionIdByClient, "")
                gatewayConnectedAtByClient.remove(normalized)
                gatewayLastSeenAtByClient.remove(normalized)
                gatewayClientNameById.remove(normalized)
                gatewayClientModeById.remove(normalized)
                gatewayTransportById.remove(normalized)
                gatewayTransportKindById.remove(normalized)
                gatewayUrlById.remove(normalized)
                gatewaySessionKeyByClient.remove(normalized)
                gatewaySessionHintByClient.remove(normalized)
                gatewayConnectionIdByClient.remove(normalized)
                gatewayCapabilitiesByClient.remove(normalized)
                gatewayServerClearChallengeLocked(connectionId, clientId: normalized)
                gatewayEventQueueByClient.remove(normalized)
                gatewaySessionEventSubscriberKindsByClient.remove(normalized)
                gatewayServerUnsubscribeAllSessionMessageEventsLocked(normalized)
                gatewayLastDeliveredEventSeqByClient.remove(normalized)
                gatewayLastPullAtByClient.remove(normalized)
                gatewayDeliveredEventCountByClient.remove(normalized)
                gatewayPeekPullCountByClient.remove(normalized)
                gatewayLastCursorByClient.remove(normalized)
                gatewayEventKindsByClient.remove(normalized)
                gatewayStreamOpenCountByClient.remove(normalized)
                gatewayStreamLastOpenAtByClient.remove(normalized)
                gatewayStreamLastCloseAtByClient.remove(normalized)
                gatewayStreamLastWaitMsByClient.remove(normalized)
                gatewayStreamActiveByClient.remove(normalized)
                gatewayStreamLeaseExpiresAtByClient.remove(normalized)
                gatewayStreamKeepaliveCountByClient.remove(normalized)
                gatewayStreamIdByClient.remove(normalized)
                gatewayStreamPendingPushCountByClient.remove(normalized)
                gatewayStreamWaiterCountByClient.remove(normalized)
                gatewayStreamWakeCountByClient.remove(normalized)
                gatewayStreamLastServerPushAtByClient.remove(normalized)
                gatewayStreamStateByClient.remove(normalized)
                gatewayStreamSessionGenerationByClient.remove(normalized)
                gatewayStreamLastModeByClient.remove(normalized)
                gatewayStreamPhaseByClient.remove(normalized)
                gatewayStreamAttachCountByClient.remove(normalized)
                gatewayStreamDetachCountByClient.remove(normalized)
                gatewayStreamLastAttachAtByClient.remove(normalized)
                gatewayStreamLastDetachAtByClient.remove(normalized)
                gatewayStreamLastWakeReasonByClient.remove(normalized)
                gatewayServerRecordClientDisconnectHistoryLocked(normalized)
            }
            gatewayServerLastDisconnectAtMs = gatewayServerNowMs()
            gatewayServerLastRequestAtMs = gatewayServerNowMs()
            gatewayServerLastRequestMethod = "disconnect"
            gatewayServerLastError = ""
            persistSnapshotLockedWithOptions(this.options)
            true
        }
    }

    private func gatewayServerRecordClientDisconnectHistoryLocked(clientId: String): Unit {
        let normalized = clientId.trimAscii()
        if (normalized.isEmpty()) {
            return
        }
        gatewayEventSequence += 1
        let event = JsonObject()
        event.put("id", JsonString("evt-${gatewayEventSequence}"))
        event.put("kind", JsonString("disconnect"))
        event.put("detail", JsonString("client-disconnected"))
        event.put("clientId", JsonString(normalized))
        event.put("ts", gatewayServerNowMs().toJsonValue())
        event.put("payload", JsonObject())
        gatewayRecentEvents.add(event)
        if (gatewayRecentEvents.size > 64) {
            let trimmed = ArrayList<JsonObject>()
            for (i in 1..gatewayRecentEvents.size) {
                trimmed.add(gatewayRecentEvents[i])
            }
            gatewayRecentEvents = trimmed
        }
    }

    public func pullEvents(
        clientId: String,
        limit!: Int64 = 32,
        sinceId!: String = "",
        peek!: Bool = false
    ): JsonObject {
        let params = JsonObject()
        params.put("limit", limit.toJsonValue())
        if (!sinceId.trimAscii().isEmpty()) {
            params.put("sinceId", JsonString(sinceId.trimAscii()))
        }
        if (peek) {
            params.put("peek", true.toJsonValue())
        }
        let request = GatewayProtocolRequest(
            "events.pull",
            GatewayConnectParams(
                GatewayClientInfo(clientId.trimAscii(), name: clientId.trimAscii(), mode: "runtime", version: "1.0"),
                sessionKey: existingStringOr(clientId.trimAscii(), gatewaySessionKeyByClient, ""),
                sessionHint: existingStringOr(clientId.trimAscii(), gatewaySessionHintByClient, ""),
                connectionId: existingStringOr(clientId.trimAscii(), gatewayConnectionIdByClient, ""),
                transport: existingStringOr(clientId.trimAscii(), gatewayTransportById, "local"),
                transportKind: existingStringOr(clientId.trimAscii(), gatewayTransportKindById, "local"),
                gatewayUrl: existingStringOr(clientId.trimAscii(), gatewayUrlById, "local://gateway")
            ),
            params: params,
            requestId: "gw-runtime-events-${clientId.trimAscii()}"
        )
        let response = this.request(request)
        try {
            response.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
    }

    public func streamEvents(
        clientId: String,
        limit!: Int64 = 32,
        sinceId!: String = "",
        waitMs!: Int64 = 0,
        close!: Bool = false,
        attach!: Bool = false,
        detach!: Bool = false
    ): JsonObject {
        let params = JsonObject()
        params.put("limit", limit.toJsonValue())
        if (!sinceId.trimAscii().isEmpty()) {
            params.put("sinceId", JsonString(sinceId.trimAscii()))
        }
        if (waitMs > 0) {
            params.put("waitMs", waitMs.toJsonValue())
        }
        if (close) {
            params.put("close", true.toJsonValue())
        }
        if (attach) {
            params.put("attach", true.toJsonValue())
        }
        if (detach) {
            params.put("detach", true.toJsonValue())
        }
        let request = GatewayProtocolRequest(
            "events.stream",
            GatewayConnectParams(
                GatewayClientInfo(clientId.trimAscii(), name: clientId.trimAscii(), mode: "runtime", version: "1.0"),
                sessionKey: existingStringOr(clientId.trimAscii(), gatewaySessionKeyByClient, ""),
                sessionHint: existingStringOr(clientId.trimAscii(), gatewaySessionHintByClient, ""),
                connectionId: existingStringOr(clientId.trimAscii(), gatewayConnectionIdByClient, ""),
                transport: existingStringOr(clientId.trimAscii(), gatewayTransportById, "local"),
                transportKind: existingStringOr(clientId.trimAscii(), gatewayTransportKindById, "local"),
                gatewayUrl: existingStringOr(clientId.trimAscii(), gatewayUrlById, "local://gateway")
            ),
            params: params,
            requestId: "gw-runtime-stream-${clientId.trimAscii()}"
        )
        let response = this.request(request)
        try {
            response.result.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
    }

    public func resumeStream(
        clientId: String,
        limit!: Int64 = 32,
        waitMs!: Int64 = 0
    ): JsonObject {
        let normalized = clientId.trimAscii()
        let cursor = synchronized(gatewayServerLock) {
            existingStringOr(normalized, gatewayLastCursorByClient, "")
        }
        this.streamEvents(normalized, limit: limit, sinceId: cursor, waitMs: waitMs)
    }

    public func nextStream(
        clientId: String,
        waitMs!: Int64 = 0
    ): JsonObject {
        this.resumeStream(clientId.trimAscii(), limit: 1, waitMs: waitMs)
    }

    public func attachStream(
        clientId: String,
        waitMs!: Int64 = 0
    ): JsonObject {
        let normalized = clientId.trimAscii()
        let cursor = synchronized(gatewayServerLock) {
            existingStringOr(normalized, gatewayLastCursorByClient, "")
        }
        this.streamEvents(normalized, limit: 1, sinceId: cursor, waitMs: waitMs, attach: true)
    }

    public func detachStream(clientId: String): JsonObject {
        synchronized(gatewayServerLock) {
            gatewayServerDetachStreamLocked(clientId)
        }
    }

    public func keepaliveStream(clientId: String): JsonObject {
        synchronized(gatewayServerLock) {
            gatewayServerKeepaliveStreamLocked(clientId)
        }
    }

    public func pushStream(clientId: String, kind!: String = "stream.push", detail!: String = "server-stream-push"): JsonObject {
        synchronized(gatewayServerLock) {
            let normalized = clientId.trimAscii()
            gatewayServerEnsureStreamSessionLocked(normalized)
            gatewayServerPublishEventLocked(normalized, kind, detail: detail)
            gatewayStreamPendingPushCountByClient[normalized] =
                existingIntOr(normalized, gatewayStreamPendingPushCountByClient, 0) + 1
            gatewayStreamLastServerPushAtByClient[normalized] = gatewayServerNowMs()
            gatewayStreamStateByClient[normalized] = if (existingBoolOr(normalized, gatewayStreamActiveByClient, false)) { "pushed" } else { "queued" }
            gatewayStreamPhaseByClient[normalized] = if (existingBoolOr(normalized, gatewayStreamActiveByClient, false)) { "pushed" } else { "queued" }
            gatewayStreamLastModeByClient[normalized] = "server-push"
            gatewayStreamLastWakeReasonByClient[normalized] = "server-push"
            let _ = gatewayServerPublishSessionUpdateForClient(
                normalized,
                "stream-push",
                detail: detail
            )
            let result = JsonObject()
            result.put("clientId", JsonString(normalized))
            result.put("pushed", true.toJsonValue())
            result.put("queueDepth", gatewayServerEventQueueDepthLocked(normalized).toJsonValue())
            result.put("streamId", JsonString(existingStringOr(normalized, gatewayStreamIdByClient, "")))
            result.put("pendingPushCount", existingIntOr(normalized, gatewayStreamPendingPushCountByClient, 0).toJsonValue())
            result.put("lastCursor", JsonString(existingStringOr(normalized, gatewayLastCursorByClient, "")))
            result
        }
    }
}

public func gatewayServerSubscribeSessionEvents(
    clientId: String,
    eventKinds!: Array<String> = ["session.updated", "session.lifecycle", "session.transcript.updated", "sessions.changed"]
): Array<String> {
    synchronized(gatewayServerLock) {
        let normalized = clientId.trimAscii()
        if (normalized.isEmpty()) {
            return gatewayEmptyStringArray()
        }
        let filtered = gatewaySessionEventKindsNormalized(eventKinds)
        gatewaySessionEventSubscriberKindsByClient[normalized] = filtered
        gatewayEventQueueByClient.remove(normalized)
        persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
        filtered
    }
}

public func gatewayServerUnsubscribeSessionEvents(clientId: String): Unit {
    synchronized(gatewayServerLock) {
        let normalized = clientId.trimAscii()
        if (normalized.isEmpty()) {
            return
        }
        gatewaySessionEventSubscriberKindsByClient.remove(normalized)
        persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
    }
}

public func gatewayServerSessionEventKinds(clientId: String): Array<String> {
    synchronized(gatewayServerLock) {
        existingArrayOr(clientId.trimAscii(), gatewaySessionEventSubscriberKindsByClient, gatewayEmptyStringArray())
    }
}

private func gatewayServerNormalizedSessionKey(sessionKey: String): String {
    sessionKey.trimAscii()
}

private func gatewayServerSessionMessageKeysLocked(clientId: String): Array<String> {
    existingArrayOr(clientId.trimAscii(), gatewaySessionMessageSubscriberKeysByClient, gatewayEmptyStringArray())
}

private func gatewayServerSessionMessageSubscribersLocked(sessionKey: String): Array<String> {
    existingArrayOr(gatewayServerNormalizedSessionKey(sessionKey), gatewaySessionMessageSubscribersBySessionKey, gatewayEmptyStringArray())
}

private func gatewayServerRemoveStringFromArray(values: Array<String>, target: String): Array<String> {
    let out = ArrayList<String>()
    let normalizedTarget = target.trimAscii()
    for (value in values) {
        if (value.trimAscii() != normalizedTarget) {
            out.add(value)
        }
    }
    out.toArray()
}

public func gatewayServerSubscribeSessionMessageEvents(clientId: String, sessionKey: String): Bool {
    synchronized(gatewayServerLock) {
        let normalizedClientId = clientId.trimAscii()
        let normalizedSessionKey = gatewayServerNormalizedSessionKey(sessionKey)
        if (normalizedClientId.isEmpty() || normalizedSessionKey.isEmpty()) {
            return false
        }
        let existingKeys = gatewayServerSessionMessageKeysLocked(normalizedClientId)
        if (!existingKeys.contains(normalizedSessionKey)) {
            let nextKeys = ArrayList<String>()
            for (key in existingKeys) {
                nextKeys.add(key)
            }
            nextKeys.add(normalizedSessionKey)
            gatewaySessionMessageSubscriberKeysByClient[normalizedClientId] = nextKeys.toArray()
        }
        let existingClients = gatewayServerSessionMessageSubscribersLocked(normalizedSessionKey)
        if (!existingClients.contains(normalizedClientId)) {
            let nextClients = ArrayList<String>()
            for (existingClientId in existingClients) {
                nextClients.add(existingClientId)
            }
            nextClients.add(normalizedClientId)
            gatewaySessionMessageSubscribersBySessionKey[normalizedSessionKey] = nextClients.toArray()
        }
        persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
        true
    }
}

public func gatewayServerUnsubscribeSessionMessageEvents(clientId: String, sessionKey: String): Bool {
    synchronized(gatewayServerLock) {
        let normalizedClientId = clientId.trimAscii()
        let normalizedSessionKey = gatewayServerNormalizedSessionKey(sessionKey)
        if (normalizedClientId.isEmpty() || normalizedSessionKey.isEmpty()) {
            return false
        }
        let nextKeys = gatewayServerRemoveStringFromArray(gatewayServerSessionMessageKeysLocked(normalizedClientId), normalizedSessionKey)
        if (nextKeys.size == 0) {
            gatewaySessionMessageSubscriberKeysByClient.remove(normalizedClientId)
        } else {
            gatewaySessionMessageSubscriberKeysByClient[normalizedClientId] = nextKeys
        }
        let nextClients = gatewayServerRemoveStringFromArray(gatewayServerSessionMessageSubscribersLocked(normalizedSessionKey), normalizedClientId)
        if (nextClients.size == 0) {
            gatewaySessionMessageSubscribersBySessionKey.remove(normalizedSessionKey)
        } else {
            gatewaySessionMessageSubscribersBySessionKey[normalizedSessionKey] = nextClients
        }
        persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
        true
    }
}

private func gatewayServerUnsubscribeAllSessionMessageEventsLocked(clientId: String): Unit {
    let normalizedClientId = clientId.trimAscii()
    if (normalizedClientId.isEmpty()) {
        return
    }
    let subscribedKeys = gatewayServerSessionMessageKeysLocked(normalizedClientId)
    for (sessionKey in subscribedKeys) {
        let nextClients = gatewayServerRemoveStringFromArray(gatewayServerSessionMessageSubscribersLocked(sessionKey), normalizedClientId)
        if (nextClients.size == 0) {
            gatewaySessionMessageSubscribersBySessionKey.remove(sessionKey)
        } else {
            gatewaySessionMessageSubscribersBySessionKey[sessionKey] = nextClients
        }
    }
    gatewaySessionMessageSubscriberKeysByClient.remove(normalizedClientId)
}

private func gatewayServerEnsureStreamSessionLocked(clientId: String): Unit {
    if (!existingStringOr(clientId, gatewayStreamIdByClient, "").isEmpty() &&
        existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0) > 0) {
        return
    }
    let now = gatewayServerNowMs()
    gatewayStreamSessionGenerationByClient[clientId] = max(1, existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0))
    gatewayStreamIdByClient[clientId] = "str-${clientId}-${now}"
    gatewayStreamLastOpenAtByClient[clientId] = now
    gatewayStreamStateByClient[clientId] = "created"
    gatewayStreamPhaseByClient[clientId] = "created"
    gatewayStreamLastModeByClient[clientId] = "session-create"
}

private func gatewayServerPrepareStreamLocked(req: GatewayProtocolRequest, waitMs: Int64, closeRequested: Bool, attachRequested: Bool, detachRequested: Bool): JsonObject {
    let clientId = gatewayServerTargetClientId(req)
    let openedAt = gatewayServerNowMs()
    let existingStreamId = existingStringOr(clientId, gatewayStreamIdByClient, "")
    let priorState = existingStringOr(clientId, gatewayStreamStateByClient, "idle")
    let hadSession =
        !existingStreamId.isEmpty() &&
        existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0) > 0
    if (!hadSession) {
        gatewayServerEnsureStreamSessionLocked(clientId)
    }
    let sessionReusable =
        hadSession &&
        priorState != "closed"
    let newSession = !closeRequested && !detachRequested && (!sessionReusable)
    if (newSession) {
        gatewayStreamOpenCountByClient[clientId] = existingIntOr(clientId, gatewayStreamOpenCountByClient, 0) + 1
        gatewayStreamSessionGenerationByClient[clientId] = existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0) + 1
        gatewayStreamIdByClient[clientId] = "str-${clientId}-${openedAt}"
        gatewayStreamAttachCountByClient[clientId] = 0
        gatewayStreamDetachCountByClient[clientId] = 0
        gatewayStreamLastWakeReasonByClient[clientId] = ""
    }
    if (detachRequested) {
        return gatewayServerDetachStreamLocked(clientId)
    }
    if (!closeRequested) {
        gatewayStreamLastOpenAtByClient[clientId] = if (newSession) { openedAt } else { existingIntOr(clientId, gatewayStreamLastOpenAtByClient, openedAt) }
        gatewayStreamLastAttachAtByClient[clientId] = openedAt
        gatewayStreamAttachCountByClient[clientId] = existingIntOr(clientId, gatewayStreamAttachCountByClient, 0) + 1
    }
    gatewayStreamLastWaitMsByClient[clientId] = waitMs
    gatewayStreamActiveByClient[clientId] = !closeRequested
    gatewayStreamLeaseExpiresAtByClient[clientId] = openedAt + max(1000, waitMs + 1000)
    gatewayStreamStateByClient[clientId] = if (closeRequested) {
        "closing"
    } else if (attachRequested) {
        "attached"
    } else if (waitMs > 0 && newSession) {
        "opening"
    } else if (waitMs > 0) {
        "attached"
    } else {
        "streaming"
    }
    gatewayStreamPhaseByClient[clientId] = if (closeRequested) {
        "closing"
    } else if (attachRequested) {
        "attached"
    } else if (newSession) {
        "opening"
    } else {
        "attached"
    }
    gatewayStreamLastModeByClient[clientId] = if (attachRequested) {
        "attach"
    } else if (waitMs > 0) {
        "long-poll"
    } else {
        "immediate"
    }
    gatewayServerPublishEventLocked(clientId, if (attachRequested) { "stream.attach" } else { "stream.open" }, detail: req.method)
    let _ = gatewayServerPublishSessionLifecycleForClient(
        clientId,
        if (attachRequested) { "stream-attached" } else { "stream-opened" },
        detail: req.method
    )
    gatewayServerPullEventsLocked(req)
}

private func gatewayServerBuildStreamResultLocked(
    clientId: String,
    waitMs: Int64,
    closeRequested: Bool,
    pull: JsonObject,
    serverPush: Bool
): JsonObject {
    let stream = JsonObject()
    stream.put("clientId", JsonString(clientId))
    stream.put("active", (!closeRequested).toJsonValue())
    let mode = if (serverPush) { "server-push" } else if (waitMs > 0) { "long-poll" } else { "immediate" }
    gatewayStreamLastModeByClient[clientId] = mode
    let delivered = gatewayServerPullDeliveredCount(pull)
    let phase = if (closeRequested) {
        "closing"
    } else if (serverPush) {
        "pushed"
    } else if (delivered > 0) {
        "streaming"
    } else if (waitMs > 0) {
        "waiting"
    } else {
        "attached"
    }
    gatewayStreamStateByClient[clientId] = phase
    gatewayStreamPhaseByClient[clientId] = phase
    gatewayStreamLastWakeReasonByClient[clientId] = if (closeRequested) {
        "close"
    } else if (serverPush) {
        "server-push"
    } else if (delivered > 0) {
        "event-ready"
    } else if (waitMs > 0) {
        "timeout"
    } else {
        "attach"
    }
    stream.put("waitMs", waitMs.toJsonValue())
    stream.put("mode", JsonString(mode))
    stream.put("serverPush", serverPush.toJsonValue())
    stream.put("serverPushCapable", true.toJsonValue())
    stream.put("sessionMode", JsonString("persistent-session"))
    stream.put("attachable", true.toJsonValue())
    stream.put("streamId", JsonString(existingStringOr(clientId, gatewayStreamIdByClient, "")))
    stream.put("state", JsonString(existingStringOr(clientId, gatewayStreamStateByClient, "idle")))
    stream.put("phase", JsonString(existingStringOr(clientId, gatewayStreamPhaseByClient, "idle")))
    stream.put("sessionGeneration", existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0).toJsonValue())
    stream.put("openCount", existingIntOr(clientId, gatewayStreamOpenCountByClient, 0).toJsonValue())
    stream.put("attachCount", existingIntOr(clientId, gatewayStreamAttachCountByClient, 0).toJsonValue())
    stream.put("detachCount", existingIntOr(clientId, gatewayStreamDetachCountByClient, 0).toJsonValue())
    stream.put("lastOpenAtMs", existingIntOr(clientId, gatewayStreamLastOpenAtByClient, 0).toJsonValue())
    stream.put("lastCloseAtMs", existingIntOr(clientId, gatewayStreamLastCloseAtByClient, 0).toJsonValue())
    stream.put("lastAttachAtMs", existingIntOr(clientId, gatewayStreamLastAttachAtByClient, 0).toJsonValue())
    stream.put("lastDetachAtMs", existingIntOr(clientId, gatewayStreamLastDetachAtByClient, 0).toJsonValue())
    stream.put("leaseExpiresAtMs", existingIntOr(clientId, gatewayStreamLeaseExpiresAtByClient, 0).toJsonValue())
    stream.put("keepaliveCount", existingIntOr(clientId, gatewayStreamKeepaliveCountByClient, 0).toJsonValue())
    stream.put("pendingPushCount", existingIntOr(clientId, gatewayStreamPendingPushCountByClient, 0).toJsonValue())
    stream.put("waiterCount", existingIntOr(clientId, gatewayStreamWaiterCountByClient, 0).toJsonValue())
    stream.put("wakeCount", existingIntOr(clientId, gatewayStreamWakeCountByClient, 0).toJsonValue())
    stream.put("lastServerPushAtMs", existingIntOr(clientId, gatewayStreamLastServerPushAtByClient, 0).toJsonValue())
    stream.put("lastWakeReason", JsonString(existingStringOr(clientId, gatewayStreamLastWakeReasonByClient, "")))
    stream.put("lastCursor", JsonString(existingStringOr(clientId, gatewayLastCursorByClient, "")))
    gatewayServerAppendSessionProjection(stream, existingStringOr(clientId, gatewaySessionKeyByClient, ""))
    let result = JsonObject()
    result.put("stream", stream)
    result.put("pull", pull)
    if (closeRequested) {
        result.put("closed", gatewayServerCloseStreamLocked(clientId))
    }
    result
}

public func gatewayServerOptionsFromConfig(cfg: GatewayConfig): GatewayServerOptions {
    GatewayServerOptions(
        bindMode: cfg.bind,
        bindAddress: if (cfg.customBindHost.trimAscii().isEmpty()) { cfg.bind } else { cfg.customBindHost },
        localTransportEnabled: true,
        // HTTP /rpc is a valid remote transport surface even when explicit remote mode is disabled.
        remoteTransportEnabled: cfg.remote.enabled || gatewayHttpAnyEndpointEnabled(cfg),
        requestTimeoutMs: 3000,
        defaultGatewayUrl: if (cfg.remote.enabled && !cfg.remote.url.trimAscii().isEmpty()) { cfg.remote.url } else { "local://gateway" },
        enableHandshake: true
    )
}

private func buildSnapshotLocked(): JsonObject {
    buildSnapshotLockedWithOptions(gatewayServerCurrentOptions)
}

private func gatewayServerAppendSessionProjection(row: JsonObject, sessionKey: String): Unit {
    let normalized = sessionKey.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    let user = CliSettingManager.readGatewaySettings()
    match (gatewayFindSessionConversationViewForUser(user, normalized)) {
        case Some(view) =>
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

private func buildSnapshotLockedWithOptions(options: GatewayServerOptions): JsonObject {
    let clients = JsonArray([])
    for ((clientId, connectedAtMs) in gatewayConnectedAtByClient) {
        let connectionId = existingStringOr(clientId, gatewayConnectionIdByClient, "")
        let row = JsonObject()
        row.put("id", JsonString(clientId))
        row.put("name", JsonString(existingStringOr(clientId, gatewayClientNameById, "")))
        row.put("mode", JsonString(existingStringOr(clientId, gatewayClientModeById, "")))
        row.put("transport", JsonString(existingStringOr(clientId, gatewayTransportById, "")))
        row.put("transportKind", JsonString(existingStringOr(clientId, gatewayTransportKindById, "")))
        row.put("gatewayUrl", JsonString(existingStringOr(clientId, gatewayUrlById, "")))
        row.put("sessionKey", JsonString(existingStringOr(clientId, gatewaySessionKeyByClient, "")))
        row.put("sessionHint", JsonString(existingStringOr(clientId, gatewaySessionHintByClient, "")))
        row.put("connectionId", JsonString(connectionId))
        row.put("capabilities", existingArrayOr(clientId, gatewayCapabilitiesByClient, []).toJsonValue())
        row.put(
            "challengePending",
            gatewayServerChallengePendingLocked(
                GatewayConnectParams(
                    GatewayClientInfo(clientId),
                    connectionId: connectionId
                )
            ).toJsonValue()
        )
        row.put("eventQueueDepth", gatewayServerEventQueueDepthLocked(clientId).toJsonValue())
        row.put("connectedAtMs", connectedAtMs.toJsonValue())
        row.put("lastSeenAtMs", existingIntOr(clientId, gatewayLastSeenAtByClient, connectedAtMs).toJsonValue())
        gatewayServerAppendSessionProjection(row, existingStringOr(clientId, gatewaySessionKeyByClient, ""))
        clients.add(row)
    }
    let activeRequests = JsonArray([])
    for ((requestId, method) in gatewayActiveRequestMethodById) {
        let row = JsonObject()
        row.put("requestId", JsonString(requestId))
        row.put("method", JsonString(method))
        row.put("clientId", JsonString(existingStringOr(requestId, gatewayActiveRequestClientById, "")))
        row.put("sessionKey", JsonString(existingStringOr(requestId, gatewayActiveRequestSessionById, "")))
        row.put("startedAtMs", existingIntOr(requestId, gatewayActiveRequestStartedAtById, 0).toJsonValue())
        gatewayServerAppendSessionProjection(row, existingStringOr(requestId, gatewayActiveRequestSessionById, ""))
        activeRequests.add(row)
    }
    let root = JsonObject()
    root.put("serverStarted", gatewayServerStarted.toJsonValue())
    root.put("startedAtMs", gatewayServerStartedAtMs.toJsonValue())
    root.put("connected", (!gatewayConnectedAtByClient.isEmpty()).toJsonValue())
    root.put("clientCount", gatewayConnectedAtByClient.size.toJsonValue())
    root.put("requestCount", gatewayServerRequestCount.toJsonValue())
    root.put("activeRequests", gatewayServerActiveRequests.toJsonValue())
    root.put("lastRequestAtMs", gatewayServerLastRequestAtMs.toJsonValue())
    root.put("lastRequestMethod", JsonString(gatewayServerLastRequestMethod))
    root.put("lastError", JsonString(gatewayServerLastError))
    root.put("lastConnectAtMs", gatewayServerLastConnectAtMs.toJsonValue())
    root.put("lastDisconnectAtMs", gatewayServerLastDisconnectAtMs.toJsonValue())
    root.put("timeoutCount", gatewayServerTimeoutCount.toJsonValue())
    root.put("cancelCount", gatewayServerCancelCount.toJsonValue())
    root.put("challengeIssuedCount", gatewayServerChallengeIssuedCount.toJsonValue())
    root.put("challengeAckCount", gatewayServerChallengeAckCount.toJsonValue())
    root.put("statePath", JsonString(GatewayServer.statePath()))
    root.put("options", options.toJson())
    root.put("clients", clients)
    root.put("activeRequestRegistry", activeRequests)
    root.put("challengeRegistry", gatewayServerChallengeRegistrySnapshotLocked())
    root.put("eventQueues", gatewayServerEventQueueSnapshotLocked())
    root.put("eventHistory", gatewayServerRecentEventSnapshotLocked())
    root.put("eventSubscriptions", gatewayServerEventSubscriptionSnapshotLocked())
    root.put("eventStreams", gatewayServerStreamSnapshotLocked())
    root.put("updatedAtMs", gatewayServerNowMs().toJsonValue())
    root
}

public func gatewayServerRuntimeSnapshot(): JsonObject {
    let rpc = GatewayServer.snapshot()
    let runtime = JsonObject()
    runtime.put("serverStarted", rpc.get("serverStarted") ?? false.toJsonValue())
    runtime.put("startedAtMs", rpc.get("startedAtMs") ?? 0.toJsonValue())
    runtime.put("clientCount", rpc.get("clientCount") ?? 0.toJsonValue())
    runtime.put("connected", rpc.get("connected") ?? false.toJsonValue())
    runtime.put("requestCount", rpc.get("requestCount") ?? 0.toJsonValue())
    runtime.put("activeRequests", rpc.get("activeRequests") ?? 0.toJsonValue())
    runtime.put("lastRequestAtMs", rpc.get("lastRequestAtMs") ?? 0.toJsonValue())
    runtime.put("lastRequestMethod", rpc.get("lastRequestMethod") ?? JsonString(""))
    runtime.put("lastError", rpc.get("lastError") ?? JsonString(""))
    runtime.put("lastConnectAtMs", rpc.get("lastConnectAtMs") ?? 0.toJsonValue())
    runtime.put("lastDisconnectAtMs", rpc.get("lastDisconnectAtMs") ?? 0.toJsonValue())
    runtime.put("timeoutCount", rpc.get("timeoutCount") ?? 0.toJsonValue())
    runtime.put("cancelCount", rpc.get("cancelCount") ?? 0.toJsonValue())
    runtime.put("challengeIssuedCount", rpc.get("challengeIssuedCount") ?? 0.toJsonValue())
    runtime.put("challengeAckCount", rpc.get("challengeAckCount") ?? 0.toJsonValue())
    runtime.put("statePath", rpc.get("statePath") ?? JsonString(GatewayServer.statePath()))
    runtime.put("options", rpc.get("options") ?? JsonObject())
    runtime.put("clients", rpc.get("clients") ?? JsonArray([]))
    runtime.put("activeRequestRegistry", rpc.get("activeRequestRegistry") ?? JsonArray([]))
    runtime.put("challengeRegistry", rpc.get("challengeRegistry") ?? JsonArray([]))
    runtime.put("eventQueues", rpc.get("eventQueues") ?? JsonArray([]))
    runtime.put("eventHistory", rpc.get("eventHistory") ?? JsonArray([]))
    runtime.put("eventSubscriptions", rpc.get("eventSubscriptions") ?? JsonArray([]))
    runtime.put("eventStreams", rpc.get("eventStreams") ?? JsonArray([]))
    runtime.put("sessionBindings", gatewayServerSessionBindingsSnapshot())
    let transport = JsonObject()
    transport.put("bindMode", gatewayServerRuntimeOptionString(rpc, "bindMode"))
    transport.put("bindAddress", gatewayServerRuntimeOptionString(rpc, "bindAddress"))
    transport.put("defaultGatewayUrl", gatewayServerRuntimeOptionString(rpc, "defaultGatewayUrl"))
    transport.put("localTransportEnabled", gatewayServerRuntimeOptionBool(rpc, "localTransportEnabled"))
    transport.put("remoteTransportEnabled", gatewayServerRuntimeOptionBool(rpc, "remoteTransportEnabled"))
    transport.put("requestTimeoutMs", gatewayServerRuntimeOptionInt(rpc, "requestTimeoutMs"))
    transport.put("enableHandshake", gatewayServerRuntimeOptionBool(rpc, "enableHandshake"))
    runtime.put("transport", transport)
    runtime.put("protocolVersion", JsonString(GATEWAY_PROTOCOL_VERSION))
    runtime
}

private func gatewayServerHandshakeJson(options: GatewayServerOptions, connect: GatewayConnectParams): JsonObject {
    let result = JsonObject()
    result.put("protocolVersion", JsonString(GATEWAY_PROTOCOL_VERSION))
    result.put("connected", true.toJsonValue())
    result.put("server", JsonString(options.serverName))
    result.put("transport", gatewayServerRuntimeSnapshot().get("transport") ?? JsonObject())
    result.put("client", connect.client.toJson())
    result.put("connectionId", JsonString(connect.connectionId))
    result.put("requestTimeoutMs", options.requestTimeoutMs.toJsonValue())
    result.put("serverTimeMs", gatewayServerNowMs().toJsonValue())
    let challengePending = gatewayServerChallengePendingLocked(connect)
    result.put("connectChallengeRequired", challengePending.toJsonValue())
    result.put(
        "connectChallengeTimeoutMs",
        existingIntOr(gatewayServerChallengeKeyForConnect(connect), gatewayChallengeExpiresAtByConnection, 0).toJsonValue()
    )
    result.put("reconnectRecommended", false.toJsonValue())
    result.put("challenge", gatewayServerChallengeDetails(connect))
    let sessionBinding = JsonObject()
    sessionBinding.put("sessionKey", JsonString(connect.sessionKey))
    sessionBinding.put("sessionHint", JsonString(connect.sessionHint))
    sessionBinding.put("connectionId", JsonString(connect.connectionId))
    gatewayServerAppendSessionProjection(sessionBinding, connect.sessionKey)
    result.put("sessionBinding", sessionBinding)
    result.put("rpc", gatewayServerRuntimeSnapshot())
    result
}

private func gatewayServerIssueChallengeLocked(params: GatewayConnectParams, options: GatewayServerOptions): (String, Int64) {
    if (!options.enableHandshake || params.transportKind == "local") {
        return ("", 0)
    }
    let token = "challenge-${params.client.id}-${gatewayServerNowMs()}"
    let expiresAt = gatewayServerNowMs() + 30000
    (token, expiresAt)
}

private func gatewayServerChallengePendingLocked(connect: GatewayConnectParams): Bool {
    let key = gatewayServerChallengeKeyForConnect(connect)
    let token = existingStringOr(key, gatewayChallengeTokenByConnection, "")
    if (token.isEmpty()) {
        return false
    }
    let expiresAt = existingIntOr(key, gatewayChallengeExpiresAtByConnection, 0)
    let acked = existingBoolOr(key, gatewayChallengeAckedByConnection, false)
    !acked && expiresAt > gatewayServerNowMs()
}

private func gatewayServerChallengeDetails(connect: GatewayConnectParams): JsonObject {
    synchronized(gatewayServerLock) {
        let clientId = connect.client.id.trimAscii()
        let key = gatewayServerChallengeKeyForConnect(connect)
        let result = JsonObject()
        result.put("clientId", JsonString(clientId))
        result.put("connectionId", JsonString(key))
        result.put("challengeToken", JsonString(existingStringOr(key, gatewayChallengeTokenByConnection, "")))
        result.put("challengeExpiresAtMs", existingIntOr(key, gatewayChallengeExpiresAtByConnection, 0).toJsonValue())
        result.put("challengePending", gatewayServerChallengePendingLocked(connect).toJsonValue())
        gatewayServerAppendSessionProjection(result, existingStringOr(clientId, gatewaySessionKeyByClient, ""))
        result
    }
}

private func gatewayServerAcknowledgeChallengeLocked(req: GatewayProtocolRequest): GatewayProtocolResponse {
    let clientId = req.connect.client.id.trimAscii()
    let challengeKey = gatewayServerChallengeKeyForConnect(req.connect)
    let expected = existingStringOr(challengeKey, gatewayChallengeTokenByConnection, "")
    let token = match (req.params.get("challengeToken")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    if (expected.isEmpty()) {
        let result = JsonObject()
        result.put("acknowledged", true.toJsonValue())
        result.put("clientId", JsonString(clientId))
        return GatewayProtocolResponse(true, req.method, requestId: req.requestId, result: result)
    }
    if (
        token.trimAscii() != expected ||
        existingIntOr(challengeKey, gatewayChallengeExpiresAtByConnection, 0) <= gatewayServerNowMs()
    ) {
        let _ = gatewayServerPublishSessionUpdateForClient(
            clientId,
            "challenge-ack-failed",
            detail: "invalid-or-expired-challenge-token",
            runId: req.requestId,
            errorMessage: "Invalid or expired connect challenge token."
        )
        return GatewayProtocolResponse(
            false,
            req.method,
            requestId: req.requestId,
            error: "Invalid or expired connect challenge token.",
            errorCode: GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED,
            details: gatewayServerChallengeDetails(req.connect)
        )
    }
    gatewayChallengeAckedByConnection[challengeKey] = true
    gatewayServerChallengeAckCount += 1
    gatewayServerPublishEventLocked(clientId, "connect.ack", detail: "challenge-acknowledged")
    let _ = gatewayServerPublishSessionUpdateForClient(
        clientId,
        "challenge-acknowledged",
        detail: "challenge-acknowledged",
        runId: req.requestId
    )
    let result = JsonObject()
    result.put("acknowledged", true.toJsonValue())
    result.put("clientId", JsonString(clientId))
    result.put("connectionId", JsonString(challengeKey))
    result.put("challenge", gatewayServerChallengeDetails(req.connect))
    GatewayProtocolResponse(true, req.method, requestId: req.requestId, result: result)
}

private func gatewayServerCancelRequestLocked(req: GatewayProtocolRequest): GatewayProtocolResponse {
    let requestId = match (req.params.get("requestId")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    if (requestId.trimAscii().isEmpty() || !gatewayActiveRequestMethodById.contains(requestId.trimAscii())) {
        return GatewayProtocolResponse(
            false,
            req.method,
            requestId: req.requestId,
            error: "Gateway request is not active.",
            errorCode: GATEWAY_ERROR_NOT_CONNECTED
        )
    }
    let normalized = requestId.trimAscii()
    let targetClientId = existingStringOr(normalized, gatewayActiveRequestClientById, "")
    gatewayActiveRequestMethodById.remove(normalized)
    gatewayActiveRequestClientById.remove(normalized)
    gatewayActiveRequestSessionById.remove(normalized)
    gatewayActiveRequestStartedAtById.remove(normalized)
    if (gatewayServerActiveRequests > 0) {
        gatewayServerActiveRequests -= 1
    }
    gatewayServerCancelCount += 1
    gatewayServerPublishEventLocked(targetClientId, "request.cancel", detail: normalized)
    let _ = gatewayServerPublishSessionUpdateForClient(
        targetClientId,
        "request-cancel",
        detail: normalized,
        runId: normalized
    )
    let result = JsonObject()
    result.put("cancelled", true.toJsonValue())
    result.put("requestId", JsonString(normalized))
    GatewayProtocolResponse(true, req.method, requestId: req.requestId, result: result)
}

private func gatewayServerPullEventsLocked(req: GatewayProtocolRequest): JsonObject {
    let clientId = gatewayServerTargetClientId(req)
    let limit = match (req.params.get("limit")) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 32 }
        case None => 32
    }
    let sinceId = match (req.params.get("sinceId")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
    let peek: Bool = match (req.params.get("peek")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let eventKinds = gatewayRequestedEventKindsForClientLocked(clientId, req.params)
    let events = JsonArray([])
    let next = ArrayList<JsonObject>()
    let source = match (gatewayEventQueueByClient.get(clientId)) {
        case Some(v) => v
        case None => ArrayList<JsonObject>()
    }
    let sinceSeq = gatewayEventSequenceFromId(sinceId)
    var taken: Int64 = 0
    var lastEventId = ""
    for (event in source) {
        let eventSeq = gatewayEventSequenceFromObject(event)
        if (eventSeq <= sinceSeq) {
            if (!peek) {
                continue
            }
            next.add(event)
            continue
        }
        if (!gatewayServerEventMatchesKinds(event, eventKinds)) {
            continue
        }
        if (gatewayServerShouldSkipPulledEvent(req, event)) {
            continue
        }
        if (taken < limit) {
            events.add(event)
            taken += 1
            lastEventId = gatewayEventIdFromObject(event)
        } else {
            next.add(event)
        }
    }
    let deliveredPushCount = gatewayServerPullDeliveredPushCount(events)
    if (!peek) {
        gatewayEventQueueByClient[clientId] = next
        if (!lastEventId.isEmpty()) {
            gatewayLastDeliveredEventSeqByClient[clientId] = gatewayEventSequenceFromId(lastEventId)
        }
        let pendingPush = existingIntOr(clientId, gatewayStreamPendingPushCountByClient, 0)
        gatewayStreamPendingPushCountByClient[clientId] = max(0, pendingPush - deliveredPushCount)
    }
    gatewayLastPullAtByClient[clientId] = gatewayServerNowMs()
    gatewayDeliveredEventCountByClient[clientId] = existingIntOr(clientId, gatewayDeliveredEventCountByClient, 0) + taken
    if (peek) {
        gatewayPeekPullCountByClient[clientId] = existingIntOr(clientId, gatewayPeekPullCountByClient, 0) + 1
    }
    gatewayLastCursorByClient[clientId] = if (lastEventId.isEmpty()) {
        existingStringOr(clientId, gatewayLastCursorByClient, sinceId)
    } else {
        lastEventId
    }
    let result = JsonObject()
    result.put("clientId", JsonString(clientId))
    result.put("events", events)
    result.put("remaining", next.size.toJsonValue())
    result.put("peek", peek.toJsonValue())
    result.put("sinceId", JsonString(sinceId))
    result.put("eventKinds", gatewayEventKindsJson(eventKinds))
    result.put("lastEventId", JsonString(lastEventId))
    result.put("nextCursor", JsonString(lastEventId))
    result.put("deliveredCount", taken.toJsonValue())
    result
}

private func gatewayServerStreamEvents(req: GatewayProtocolRequest): JsonObject {
    let clientId = gatewayServerTargetClientId(req)
    let waitMs = match (req.params.get("waitMs")) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
    let closeRequested: Bool = match (req.params.get("close")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let attachRequested: Bool = match (req.params.get("attach")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let detachRequested: Bool = match (req.params.get("detach")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let initialPull = synchronized(gatewayServerLock) {
        gatewayServerPrepareStreamLocked(req, waitMs, closeRequested, attachRequested, detachRequested)
    }
    var pull = initialPull
    var serverPush = false
    if (!closeRequested && waitMs > 0 && gatewayServerPullDeliveredCount(pull) == 0) {
        let startedAt = gatewayServerNowMs()
        synchronized(gatewayServerLock) {
            gatewayStreamWaiterCountByClient[clientId] = existingIntOr(clientId, gatewayStreamWaiterCountByClient, 0) + 1
            let _ = gatewayServerPublishSessionLifecycleForClient(
                clientId,
                "stream-waiting",
                detail: req.method,
                runId: req.requestId
            )
        }
        try {
            var done = false
            while (!done) {
                let elapsed = gatewayServerNowMs() - startedAt
                if (elapsed >= waitMs) {
                    done = true
                } else {
                    let remaining = waitMs - elapsed
                    let slice = if (remaining > 25) { 25 } else { remaining }
                    sleep(Duration.millisecond * slice)
                    pull = synchronized(gatewayServerLock) {
                        gatewayServerPublishEventLocked(clientId, "stream.wait", detail: req.method)
                        gatewayServerPullEventsLocked(req)
                    }
                    let delivered = gatewayServerPullDeliveredCount(pull)
                    if (delivered > 0) {
                        serverPush = gatewayServerPullHasServerPush(pull)
                        if (serverPush) {
                            synchronized(gatewayServerLock) {
                                gatewayStreamWakeCountByClient[clientId] = existingIntOr(clientId, gatewayStreamWakeCountByClient, 0) + 1
                                gatewayStreamLastServerPushAtByClient[clientId] = gatewayServerNowMs()
                            }
                        }
                        done = true
                    }
                }
            }
        } finally {
            synchronized(gatewayServerLock) {
                let waiterCount = existingIntOr(clientId, gatewayStreamWaiterCountByClient, 0)
                gatewayStreamWaiterCountByClient[clientId] = max(0, waiterCount - 1)
            }
        }
    }
    synchronized(gatewayServerLock) {
        gatewayServerBuildStreamResultLocked(clientId, waitMs, closeRequested, pull, serverPush)
    }
}

private func gatewayServerCloseStreamLocked(clientId: String): JsonObject {
    let normalized = clientId.trimAscii()
    gatewayStreamActiveByClient[normalized] = false
    let now = gatewayServerNowMs()
    gatewayStreamLastCloseAtByClient[normalized] = now
    gatewayStreamLastDetachAtByClient[normalized] = now
    gatewayStreamDetachCountByClient[normalized] = existingIntOr(normalized, gatewayStreamDetachCountByClient, 0) + 1
    gatewayStreamLeaseExpiresAtByClient[normalized] = 0
    gatewayStreamPendingPushCountByClient[normalized] = 0
    gatewayStreamWaiterCountByClient[normalized] = 0
    gatewayStreamStateByClient[normalized] = "closed"
    gatewayStreamPhaseByClient[normalized] = "closed"
    gatewayStreamLastModeByClient[normalized] = "closed"
    gatewayStreamLastWakeReasonByClient[normalized] = "close"
    gatewayServerPublishEventLocked(normalized, "stream.close", detail: "client-stream-closed")
    let _ = gatewayServerPublishSessionLifecycleForClient(normalized, "stream-closed", detail: "client-stream-closed")
    let result = JsonObject()
    result.put("clientId", JsonString(normalized))
    result.put("active", false.toJsonValue())
    result.put("streamId", JsonString(existingStringOr(normalized, gatewayStreamIdByClient, "")))
    result.put("lastCloseAtMs", existingIntOr(normalized, gatewayStreamLastCloseAtByClient, 0).toJsonValue())
    result
}

private func gatewayServerDetachStreamLocked(clientId: String): JsonObject {
    let normalized = clientId.trimAscii()
    let now = gatewayServerNowMs()
    gatewayStreamActiveByClient[normalized] = false
    gatewayStreamLastDetachAtByClient[normalized] = now
    gatewayStreamDetachCountByClient[normalized] = existingIntOr(normalized, gatewayStreamDetachCountByClient, 0) + 1
    gatewayStreamLeaseExpiresAtByClient[normalized] = 0
    gatewayStreamWaiterCountByClient[normalized] = 0
    gatewayStreamStateByClient[normalized] = "detached"
    gatewayStreamPhaseByClient[normalized] = "detached"
    gatewayStreamLastModeByClient[normalized] = "detach"
    gatewayStreamLastWakeReasonByClient[normalized] = "detach"
    gatewayServerPublishEventLocked(normalized, "stream.detach", detail: "client-stream-detached")
    let _ = gatewayServerPublishSessionLifecycleForClient(normalized, "stream-detached", detail: "client-stream-detached")
    let result = JsonObject()
    result.put("clientId", JsonString(normalized))
    result.put("active", false.toJsonValue())
    result.put("detached", true.toJsonValue())
    result.put("streamId", JsonString(existingStringOr(normalized, gatewayStreamIdByClient, "")))
    result.put("sessionGeneration", existingIntOr(normalized, gatewayStreamSessionGenerationByClient, 0).toJsonValue())
    result.put("lastDetachAtMs", existingIntOr(normalized, gatewayStreamLastDetachAtByClient, 0).toJsonValue())
    result
}

private func gatewayServerKeepaliveStreamLocked(clientId: String): JsonObject {
    let normalized = clientId.trimAscii()
    let now = gatewayServerNowMs()
    gatewayStreamActiveByClient[normalized] = true
    gatewayStreamLeaseExpiresAtByClient[normalized] = now + max(1000, existingIntOr(normalized, gatewayStreamLastWaitMsByClient, 0) + 1000)
    gatewayStreamKeepaliveCountByClient[normalized] = existingIntOr(normalized, gatewayStreamKeepaliveCountByClient, 0) + 1
    gatewayStreamStateByClient[normalized] = "keepalive"
    gatewayStreamPhaseByClient[normalized] = "keepalive"
    gatewayStreamLastAttachAtByClient[normalized] = now
    gatewayStreamLastWakeReasonByClient[normalized] = "keepalive"
    gatewayServerPublishEventLocked(normalized, "stream.keepalive", detail: "client-stream-keepalive")
    let _ = gatewayServerPublishSessionLifecycleForClient(normalized, "stream-keepalive", detail: "client-stream-keepalive")
    let result = JsonObject()
    result.put("clientId", JsonString(normalized))
    result.put("active", true.toJsonValue())
    result.put("streamId", JsonString(existingStringOr(normalized, gatewayStreamIdByClient, "")))
    result.put("leaseExpiresAtMs", existingIntOr(normalized, gatewayStreamLeaseExpiresAtByClient, 0).toJsonValue())
    result.put("keepaliveCount", existingIntOr(normalized, gatewayStreamKeepaliveCountByClient, 0).toJsonValue())
    result.put("pendingPushCount", existingIntOr(normalized, gatewayStreamPendingPushCountByClient, 0).toJsonValue())
    result.put("lastCursor", JsonString(existingStringOr(normalized, gatewayLastCursorByClient, "")))
    result
}

private func gatewayServerExpireStreamLeasesLocked(): Unit {
    let now = gatewayServerNowMs()
    for ((clientId, leaseExpiresAtMs) in gatewayStreamLeaseExpiresAtByClient) {
        if (existingBoolOr(clientId, gatewayStreamActiveByClient, false) && leaseExpiresAtMs > 0 && leaseExpiresAtMs <= now) {
            gatewayStreamActiveByClient[clientId] = false
            gatewayStreamLastCloseAtByClient[clientId] = now
            gatewayStreamLastDetachAtByClient[clientId] = now
            gatewayStreamDetachCountByClient[clientId] = existingIntOr(clientId, gatewayStreamDetachCountByClient, 0) + 1
            gatewayStreamLeaseExpiresAtByClient[clientId] = 0
            gatewayStreamPendingPushCountByClient[clientId] = 0
            gatewayStreamWaiterCountByClient[clientId] = 0
            gatewayStreamStateByClient[clientId] = "expired"
            gatewayStreamPhaseByClient[clientId] = "expired"
            gatewayStreamLastModeByClient[clientId] = "expired"
            gatewayStreamLastWakeReasonByClient[clientId] = "expired"
            gatewayServerPublishEventLocked(clientId, "stream.expire", detail: "stream-lease-expired")
            let _ = gatewayServerPublishSessionLifecycleForClient(clientId, "stream-expired", detail: "stream-lease-expired")
        }
    }
}

private func gatewayServerTrackedStreamClientsLocked(): ArrayList<String> {
    let seen = HashMap<String, Bool>()
    let clients = ArrayList<String>()
    for ((clientId, _) in gatewayConnectedAtByClient) {
        if (!seen.contains(clientId)) {
            seen[clientId] = true
            clients.add(clientId)
        }
    }
    for ((clientId, _) in gatewayStreamIdByClient) {
        if (!seen.contains(clientId)) {
            seen[clientId] = true
            clients.add(clientId)
        }
    }
    for ((clientId, _) in gatewayStreamSessionGenerationByClient) {
        if (!seen.contains(clientId)) {
            seen[clientId] = true
            clients.add(clientId)
        }
    }
    for ((clientId, _) in gatewayEventQueueByClient) {
        if (!seen.contains(clientId)) {
            seen[clientId] = true
            clients.add(clientId)
        }
    }
    for ((clientId, _) in gatewaySessionEventSubscriberKindsByClient) {
        if (!seen.contains(clientId)) {
            seen[clientId] = true
            clients.add(clientId)
        }
    }
    clients
}

private func gatewaySessionEventKindsNormalized(kinds: Array<String>): Array<String> {
    let out = ArrayList<String>()
    for (raw in kinds) {
        let normalized = raw.trimAscii()
        if (normalized.isEmpty()) {
            continue
        }
        if (!normalized.startsWith("session.") && normalized != "sessions.changed") {
            continue
        }
        if (!out.contains(normalized)) {
            out.add(normalized)
        }
    }
    out.toArray()
}

private func gatewayServerSessionSubscriberKindsLocked(clientId: String): Array<String> {
    existingArrayOr(clientId.trimAscii(), gatewaySessionEventSubscriberKindsByClient, gatewayEmptyStringArray())
}

private func gatewayServerShouldDirectPushSessionEventLocked(clientId: String, kind: String): Bool {
    let normalizedKind = kind.trimAscii()
    if (!normalizedKind.startsWith("session.") && normalizedKind != "sessions.changed") {
        return false
    }
    let subscribedKinds = gatewayServerSessionSubscriberKindsLocked(clientId)
    if (subscribedKinds.size == 0) {
        return false
    }
    for (allowed in subscribedKinds) {
        if (allowed.trimAscii() == normalizedKind) {
            return true
        }
    }
    false
}

private func gatewayServerHasStreamEventSubscriptionLocked(clientId: String, kind: String): Bool {
    let normalizedKind = kind.trimAscii()
    if (!normalizedKind.startsWith("session.") && normalizedKind != "sessions.changed") {
        return false
    }
    let requestedKinds = existingArrayOr(clientId.trimAscii(), gatewayEventKindsByClient, gatewayEmptyStringArray())
    for (allowed in requestedKinds) {
        if (allowed.trimAscii() == normalizedKind) {
            return true
        }
    }
    false
}

private func gatewayServerShouldDirectPushControlUiEventLocked(clientId: String, kind: String): Bool {
    let normalizedKind = kind.trimAscii()
    if (normalizedKind == "chat" || normalizedKind == "control-ui.invalidate") {
        return true
    }
    gatewayServerShouldDirectPushSessionEventLocked(clientId, normalizedKind)
}

private func gatewayServerIsDirectWebsocketSubscriberLocked(clientId: String): Bool {
    gatewayServerSessionSubscriberKindsLocked(clientId).size > 0
}

private func gatewayServerShouldQueueEventLocked(clientId: String, kind: String): Bool {
    if (gatewayServerIsDirectWebsocketSubscriberLocked(clientId) &&
        gatewayControlUiWsHasBoundConnection(clientId)) {
        return false
    }
    true
}

private func gatewayServerTrimEventQueueLocked(queue: ArrayList<JsonObject>): Unit {
    if (Int64(queue.size) <= GATEWAY_EVENT_QUEUE_MAX_PER_CLIENT) {
        return
    }
    let trimmed = ArrayList<JsonObject>()
    let start = Int64(queue.size) - GATEWAY_EVENT_QUEUE_MAX_PER_CLIENT
    var index: Int64 = start
    while (index < Int64(queue.size)) {
        trimmed.add(queue[index])
        index += 1
    }
    queue.clear()
    for (event in trimmed) {
        queue.add(event)
    }
}

private func gatewayRequestedEventKindsLocked(params: JsonObject): Array<String> {
    let out = ArrayList<String>()
    match (params.get("eventKinds")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                for (i in 0..arr.size()) {
                    try {
                        let kind = arr[i].asString().getValue().trimAscii()
                        if (!kind.isEmpty()) {
                            out.add(kind)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
            } catch (_: Exception) {
                try {
                    let raw = v.asString().getValue().trimAscii()
                    if (!raw.isEmpty()) {
                        for (part in raw.split(",")) {
                            let kind = part.trimAscii()
                            if (!kind.isEmpty()) {
                                out.add(kind)
                            }
                        }
                    }
                } catch (_inner: Exception) {
                    ()
                }
            }
        case None => ()
    }
    out.toArray()
}

private func gatewayRequestedEventKindsForClientLocked(clientId: String, params: JsonObject): Array<String> {
    let requested = gatewayRequestedEventKindsLocked(params)
    if (requested.size > 0) {
        gatewayEventKindsByClient[clientId] = requested
        return requested
    }
    existingArrayOr(clientId, gatewayEventKindsByClient, gatewayEmptyStringArray())
}

private func gatewayEmptyStringArray(): Array<String> {
    let out = ArrayList<String>()
    out.toArray()
}

private func gatewayEventKindsJson(kinds: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (kind in kinds) {
        let normalized = kind.trimAscii()
        if (!normalized.isEmpty()) {
            arr.add(JsonString(normalized))
        }
    }
    arr
}

private func gatewayServerEventMatchesKinds(event: JsonObject, kinds: Array<String>): Bool {
    if (kinds.size == 0) {
        return true
    }
    let kind = match (event.get("kind")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
    if (kind.isEmpty()) {
        return false
    }
    for (allowed in kinds) {
        if (allowed.trimAscii() == kind) {
            return true
        }
    }
    false
}

private func gatewayServerEventSubscriptionSnapshotLocked(): JsonArray {
    let rows = JsonArray([])
    for (clientId in gatewayServerTrackedStreamClientsLocked()) {
        let connectedAtMs = existingIntOr(clientId, gatewayConnectedAtByClient, 0)
        let leaseExpiresAtMs = existingIntOr(clientId, gatewayStreamLeaseExpiresAtByClient, 0)
        let row = JsonObject()
        row.put("clientId", JsonString(clientId))
        row.put("connectedAtMs", connectedAtMs.toJsonValue())
        row.put("lastPullAtMs", existingIntOr(clientId, gatewayLastPullAtByClient, 0).toJsonValue())
        row.put("lastDeliveredSeq", existingIntOr(clientId, gatewayLastDeliveredEventSeqByClient, 0).toJsonValue())
        row.put("deliveredEventCount", existingIntOr(clientId, gatewayDeliveredEventCountByClient, 0).toJsonValue())
        row.put("peekPullCount", existingIntOr(clientId, gatewayPeekPullCountByClient, 0).toJsonValue())
        row.put("lastCursor", JsonString(existingStringOr(clientId, gatewayLastCursorByClient, "")))
        let directKinds = gatewayServerSessionSubscriberKindsLocked(clientId)
        let streamKinds = existingArrayOr(clientId, gatewayEventKindsByClient, gatewayEmptyStringArray())
        let effectiveKinds = if (directKinds.size > 0) { directKinds } else { streamKinds }
        row.put("eventKinds", gatewayEventKindsJson(effectiveKinds))
        row.put("queueDepth", gatewayServerEventQueueDepthLocked(clientId).toJsonValue())
        row.put("streamId", JsonString(existingStringOr(clientId, gatewayStreamIdByClient, "")))
        row.put("waiterCount", existingIntOr(clientId, gatewayStreamWaiterCountByClient, 0).toJsonValue())
        row.put("streamState", JsonString(existingStringOr(clientId, gatewayStreamStateByClient, "idle")))
        row.put("streamPhase", JsonString(existingStringOr(clientId, gatewayStreamPhaseByClient, "idle")))
        row.put("sessionMode", JsonString("persistent-session"))
        row.put("runtimeModel", JsonString(if (directKinds.size > 0) { "direct-websocket-subscription" } else { "persistent-session-lease" }))
        row.put("subscriptionMode", JsonString(if (directKinds.size > 0) { "direct-websocket" } else { "event-stream" }))
        row.put("attachable", true.toJsonValue())
        row.put("resumable", (existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0) > 0).toJsonValue())
        row.put("leaseState", JsonString(
            if (leaseExpiresAtMs > gatewayServerNowMs()) {
                "active"
            } else if (leaseExpiresAtMs > 0) {
                "expired"
            } else {
                "idle"
            }
        ))
        row.put("sessionGeneration", existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0).toJsonValue())
        row.put("attachCount", existingIntOr(clientId, gatewayStreamAttachCountByClient, 0).toJsonValue())
        row.put("detachCount", existingIntOr(clientId, gatewayStreamDetachCountByClient, 0).toJsonValue())
        gatewayServerAppendSessionProjection(row, existingStringOr(clientId, gatewaySessionKeyByClient, ""))
        rows.add(row)
    }
    rows
}

private func gatewayServerStreamSnapshotLocked(): JsonArray {
    let rows = JsonArray([])
    for (clientId in gatewayServerTrackedStreamClientsLocked()) {
        let connectedAtMs = existingIntOr(clientId, gatewayConnectedAtByClient, 0)
        let leaseExpiresAtMs = existingIntOr(clientId, gatewayStreamLeaseExpiresAtByClient, 0)
        let row = JsonObject()
        row.put("clientId", JsonString(clientId))
        row.put("connectedAtMs", connectedAtMs.toJsonValue())
        row.put("active", existingBoolOr(clientId, gatewayStreamActiveByClient, false).toJsonValue())
        row.put("streamId", JsonString(existingStringOr(clientId, gatewayStreamIdByClient, "")))
        row.put("openCount", existingIntOr(clientId, gatewayStreamOpenCountByClient, 0).toJsonValue())
        row.put("attachCount", existingIntOr(clientId, gatewayStreamAttachCountByClient, 0).toJsonValue())
        row.put("detachCount", existingIntOr(clientId, gatewayStreamDetachCountByClient, 0).toJsonValue())
        row.put("lastOpenAtMs", existingIntOr(clientId, gatewayStreamLastOpenAtByClient, 0).toJsonValue())
        row.put("lastCloseAtMs", existingIntOr(clientId, gatewayStreamLastCloseAtByClient, 0).toJsonValue())
        row.put("lastAttachAtMs", existingIntOr(clientId, gatewayStreamLastAttachAtByClient, 0).toJsonValue())
        row.put("lastDetachAtMs", existingIntOr(clientId, gatewayStreamLastDetachAtByClient, 0).toJsonValue())
        row.put("lastWaitMs", existingIntOr(clientId, gatewayStreamLastWaitMsByClient, 0).toJsonValue())
        row.put("leaseExpiresAtMs", existingIntOr(clientId, gatewayStreamLeaseExpiresAtByClient, 0).toJsonValue())
        row.put("keepaliveCount", existingIntOr(clientId, gatewayStreamKeepaliveCountByClient, 0).toJsonValue())
        row.put("pendingPushCount", existingIntOr(clientId, gatewayStreamPendingPushCountByClient, 0).toJsonValue())
        row.put("waiterCount", existingIntOr(clientId, gatewayStreamWaiterCountByClient, 0).toJsonValue())
        row.put("wakeCount", existingIntOr(clientId, gatewayStreamWakeCountByClient, 0).toJsonValue())
        row.put("lastServerPushAtMs", existingIntOr(clientId, gatewayStreamLastServerPushAtByClient, 0).toJsonValue())
        row.put("serverPushCapable", true.toJsonValue())
        row.put("sessionMode", JsonString("persistent-session"))
        row.put("runtimeModel", JsonString("persistent-session-lease"))
        row.put("attachable", true.toJsonValue())
        row.put("resumable", (existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0) > 0).toJsonValue())
        row.put("leaseState", JsonString(
            if (leaseExpiresAtMs > gatewayServerNowMs()) {
                "active"
            } else if (leaseExpiresAtMs > 0) {
                "expired"
            } else {
                "idle"
            }
        ))
        row.put("state", JsonString(existingStringOr(clientId, gatewayStreamStateByClient, "idle")))
        row.put("phase", JsonString(existingStringOr(clientId, gatewayStreamPhaseByClient, "idle")))
        row.put("sessionGeneration", existingIntOr(clientId, gatewayStreamSessionGenerationByClient, 0).toJsonValue())
        row.put("lastMode", JsonString(existingStringOr(clientId, gatewayStreamLastModeByClient, "")))
        row.put("lastWakeReason", JsonString(existingStringOr(clientId, gatewayStreamLastWakeReasonByClient, "")))
        row.put("lastCursor", JsonString(existingStringOr(clientId, gatewayLastCursorByClient, "")))
        gatewayServerAppendSessionProjection(row, existingStringOr(clientId, gatewaySessionKeyByClient, ""))
        rows.add(row)
    }
    rows
}

public func gatewayServerPublishClientEvent(
    clientId: String,
    kind: String,
    detail!: String = "",
    payload!: JsonValue = JsonObject()
): Unit {
    synchronized(gatewayServerLock) {
        gatewayServerPublishEventLocked(clientId, kind, detail: detail, payload: payload)
        persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
    }
}

public func gatewayServerPublishEventToMatchingClients(
    kind: String,
    detail!: String = "",
    payload!: JsonValue = JsonObject(),
    predicate!: (String, String, String) -> Bool
): Int64 {
    synchronized(gatewayServerLock) {
        var published: Int64 = 0
        for ((clientId, _) in gatewayConnectedAtByClient) {
            let clientName = existingStringOr(clientId, gatewayClientNameById, "")
            let clientMode = existingStringOr(clientId, gatewayClientModeById, "")
            if (!predicate(clientId, clientName, clientMode)) {
                continue
            }
            gatewayServerPublishEventLocked(clientId, kind, detail: detail, payload: payload)
            published += 1
        }
        if (published > 0) {
            persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
        }
        published
    }
}

public func gatewayServerPublishChatEvent(
    payload: JsonValue,
    detail!: String = "final"
): Int64 {
    gatewayServerPublishEventToMatchingClients(
        "chat",
        detail: detail,
        payload: payload,
        predicate: { _clientId, clientName, clientMode =>
            gatewayChatEventShouldPublishToClient(clientName, clientMode)
        }
    )
}

private func gatewayServerPublishSessionEventToTargets(
    kind: String,
    detail: String,
    payload: JsonValue,
    predicate: (String, String, String) -> Bool
): Int64 {
    synchronized(gatewayServerLock) {
        var published: Int64 = 0
        for (clientId in gatewayServerTrackedStreamClientsLocked()) {
            let clientName = existingStringOr(clientId, gatewayClientNameById, "")
            let clientMode = existingStringOr(clientId, gatewayClientModeById, "")
            if (!predicate(clientId, clientName, clientMode) &&
                !gatewayServerShouldDirectPushSessionEventLocked(clientId, kind) &&
                !gatewayServerHasStreamEventSubscriptionLocked(clientId, kind)) {
                continue
            }
            gatewayServerPublishEventLocked(clientId, kind, detail: detail, payload: payload)
            published += 1
        }
        if (published > 0) {
            persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
        }
        published
    }
}

private func gatewayServerBuildSessionMessageEventPayload(sessionKey: String): JsonObject {
    let payload = JsonObject()
    let normalizedSessionKey = sessionKey.trimAscii()
    payload.put("sessionKey", JsonString(normalizedSessionKey))
    let user = CliSettingManager.readGatewaySettings()
    let conversation = gatewayFindSessionConversationViewForUser(user, normalizedSessionKey)
    match (conversation) {
        case Some(view) =>
            payload.put("agentId", JsonString(view.agentId))
            payload.put("displayName", JsonString(view.displayName))
            payload.put("channel", JsonString(view.channel))
            payload.put("chatType", JsonString(view.chatType))
            payload.put("peer", JsonString(view.peer))
            payload.put("sessionId", JsonString(view.sessionId))
            payload.put("origin", view.origin)
            payload.put("delivery", view.delivery)
            payload.put("binding", view.binding)
        case None => ()
    }
    match (gatewayFindSessionCatalogRowForUser(user, normalizedSessionKey)) {
        case Some(row) =>
            if (!row.verboseLevel.isEmpty()) {
                payload.put("verboseLevel", JsonString(row.verboseLevel))
            }
            if (!row.responseUsage.isEmpty()) {
                payload.put("responseUsage", JsonString(row.responseUsage))
            }
            payload.put("fastMode", row.fastMode.toJsonValue())
            if (!row.sendPolicy.isEmpty()) {
                payload.put("sendPolicy", JsonString(row.sendPolicy))
            }
            if (!row.lastChannel.isEmpty()) {
                payload.put("lastChannel", JsonString(row.lastChannel))
            }
            if (!row.lastTo.isEmpty()) {
                payload.put("lastTo", JsonString(row.lastTo))
            }
            if (!row.lastAccountId.isEmpty()) {
                payload.put("lastAccountId", JsonString(row.lastAccountId))
            }
            if (row.lastThreadId > 0) {
                payload.put("lastThreadId", row.lastThreadId.toJsonValue())
            }
            if (!row.modelProvider.isEmpty()) {
                payload.put("modelProvider", JsonString(row.modelProvider))
            }
            if (!row.model.isEmpty()) {
                payload.put("model", JsonString(row.model))
            }
            if (row.contextTokens > 0) {
                payload.put("contextTokens", row.contextTokens.toJsonValue())
            }
            if (row.totalTokens > 0 || row.totalTokensFresh) {
                payload.put("totalTokens", row.totalTokens.toJsonValue())
                payload.put("totalTokensFresh", row.totalTokensFresh.toJsonValue())
            }
            if (row.estimatedCostUsd > 0.0) {
                payload.put("estimatedCostUsd", row.estimatedCostUsd.toJsonValue())
            }
            if (!row.spawnedBy.isEmpty()) {
                payload.put("spawnedBy", JsonString(row.spawnedBy))
            }
            if (!row.spawnedWorkspaceDir.isEmpty()) {
                payload.put("spawnedWorkspaceDir", JsonString(row.spawnedWorkspaceDir))
            }
            payload.put("forkedFromParent", row.forkedFromParent.toJsonValue())
            if (row.spawnDepth > 0) {
                payload.put("spawnDepth", row.spawnDepth.toJsonValue())
            }
            if (!row.subagentRole.isEmpty()) {
                payload.put("subagentRole", JsonString(row.subagentRole))
            }
            if (!row.subagentControlScope.isEmpty()) {
                payload.put("subagentControlScope", JsonString(row.subagentControlScope))
            }
            if (!row.parentSessionKey.isEmpty()) {
                payload.put("parentSessionKey", JsonString(row.parentSessionKey))
            }
            if (row.childSessions.size > 0) {
                let children = JsonArray([])
                for (child in row.childSessions) {
                    children.add(JsonString(child))
                }
                payload.put("childSessions", children)
            }
        case None => ()
    }
    let store = gatewaySessionStoreForSessionKey(user, normalizedSessionKey)
    if (let Some(raw) <- store.readTranscriptRaw(normalizedSessionKey)) {
        let objs = gatewayControlUiParseJsonObjectsFromRaw(raw)
        var messageSeq: Int64 = 0
        var lastMessage = JsonObject()
        for (obj in objs) {
            let role = match (obj.get("role")) {
                case Some(v) =>
                    try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
                case None => ""
            }
            let text = match (obj.get("text")) {
                case Some(v) =>
                    try { v.asString().getValue() } catch (_: Exception) { "" }
                case None => ""
            }
            if (role.isEmpty() || text.trimAscii().isEmpty()) {
                continue
            }
            messageSeq += 1
            lastMessage = JsonObject()
            lastMessage.put("role", JsonString(role))
            lastMessage.put("text", JsonString(text))
            match (obj.get("id")) {
                case Some(v) =>
                    try {
                        let messageId = v.asString().getValue().trimAscii()
                        if (!messageId.isEmpty()) {
                            lastMessage.put("id", JsonString(messageId))
                            payload.put("messageId", JsonString(messageId))
                        }
                    } catch (_: Exception) {
                        ()
                    }
                case None => ()
            }
            match (obj.get("ts")) {
                case Some(v) => lastMessage.put("ts", v)
                case None => ()
            }
        }
        if (messageSeq > 0) {
            payload.put("message", lastMessage)
            payload.put("messageSeq", messageSeq.toJsonValue())
        }
    }
    payload
}

public func gatewayServerPublishSessionMessageEvent(sessionKey: String, detail!: String = "message"): Int64 {
    synchronized(gatewayServerLock) {
        let normalizedSessionKey = sessionKey.trimAscii()
        if (normalizedSessionKey.isEmpty()) {
            return 0
        }
        let subscribers = gatewayServerSessionMessageSubscribersLocked(normalizedSessionKey)
        if (subscribers.size == 0) {
            return 0
        }
        let payload = gatewayServerBuildSessionMessageEventPayload(normalizedSessionKey)
        var published: Int64 = 0
        for (clientId in subscribers) {
            gatewayServerPublishEventLocked(clientId, "session.message", detail: detail, payload: payload)
            published += 1
        }
        if (published > 0) {
            persistSnapshotLockedWithOptions(gatewayServerCurrentOptions)
        }
        published
    }
}

private func gatewayServerBuildSessionsChangedPayload(
    sessionKey: String,
    phase!: String = "",
    reason!: String = "",
    detail!: String = "",
    messageSeq!: Int64 = 0,
    compacted!: Bool = false
): JsonObject {
    let payload = JsonObject()
    let normalizedSessionKey = sessionKey.trimAscii()
    if (!normalizedSessionKey.isEmpty()) {
        payload.put("sessionKey", JsonString(normalizedSessionKey))
    }
    if (!phase.trimAscii().isEmpty()) {
        payload.put("phase", JsonString(phase.trimAscii()))
    }
    if (!reason.trimAscii().isEmpty()) {
        payload.put("reason", JsonString(reason.trimAscii()))
    }
    if (!detail.trimAscii().isEmpty()) {
        payload.put("detail", JsonString(detail.trimAscii()))
    }
    if (compacted) {
        payload.put("compacted", true.toJsonValue())
    }
    payload.put("ts", gatewayServerNowMs().toJsonValue())

    let base = gatewayServerBuildSessionMessageEventPayload(normalizedSessionKey)
    let passthroughKeys = [
        "agentId",
        "displayName",
        "channel",
        "chatType",
        "peer",
        "sessionId",
        "messageId",
        "origin",
        "delivery",
        "binding"
    ]
    for (key in passthroughKeys) {
        match (base.get(key)) {
            case Some(v) => payload.put(key, v)
            case None => ()
        }
    }
    if (messageSeq > 0) {
        payload.put("messageSeq", messageSeq.toJsonValue())
    } else {
        match (base.get("messageSeq")) {
            case Some(v) => payload.put("messageSeq", v)
            case None => ()
        }
    }
    payload
}

private func gatewayServerPayloadSessionKey(payload: JsonValue): String {
    match (payload) {
        case obj: JsonObject =>
            match (obj.get("sessionKey")) {
                case Some(v) =>
                    try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
                case None => ""
            }
        case _ => ""
    }
}

public func gatewayServerPublishSessionsChangedEvent(
    sessionKey: String,
    phase!: String = "",
    reason!: String = "",
    detail!: String = "changed",
    messageSeq!: Int64 = 0,
    compacted!: Bool = false
): Int64 {
    let payload = gatewayServerBuildSessionsChangedPayload(
        sessionKey,
        phase: phase,
        reason: reason,
        detail: detail,
        messageSeq: messageSeq,
        compacted: compacted
    )
    gatewayServerPublishSessionEventToTargets(
        "sessions.changed",
        detail,
        payload,
        { _clientId, clientName, clientMode =>
            gatewayChatEventShouldPublishToClient(clientName, clientMode)
        }
    )
}

public func gatewayServerPublishSessionEvent(
    payload: JsonValue,
    detail!: String = "updated"
): Int64 {
    gatewayServerPublishSessionEventToTargets(
        "session.updated",
        detail,
        payload,
        { _clientId, clientName, clientMode =>
            gatewayChatEventShouldPublishToClient(clientName, clientMode)
        }
    )
}

public func gatewayServerPublishSessionLifecycleEvent(
    payload: JsonValue,
    detail!: String = "lifecycle"
): Int64 {
    let published = gatewayServerPublishSessionEventToTargets(
        "session.lifecycle",
        detail,
        payload,
        { _clientId, clientName, clientMode =>
            gatewayChatEventShouldPublishToClient(clientName, clientMode)
        }
    )
    let sessionKey = gatewayServerPayloadSessionKey(payload)
    if (!sessionKey.isEmpty()) {
        let _ = gatewayServerPublishSessionsChangedEvent(
            sessionKey,
            reason: detail,
            detail: detail
        )
    }
    published
}

public func gatewayServerPublishSessionTranscriptEvent(
    payload: JsonValue,
    detail!: String = "transcript-updated"
): Int64 {
    let published = gatewayServerPublishSessionEventToTargets(
        "session.transcript.updated",
        detail,
        payload,
        { _clientId, clientName, clientMode =>
            gatewayChatEventShouldPublishToClient(clientName, clientMode)
        }
    )
    let sessionKey = gatewayServerPayloadSessionKey(payload)
    if (!sessionKey.isEmpty()) {
        let _ = gatewayServerPublishSessionsChangedEvent(
            sessionKey,
            phase: "message",
            detail: detail
        )
    }
    published
}

private func gatewayServerPublishSessionLifecycleForClient(
    clientId: String,
    state: String,
    detail!: String = "",
    runId!: String = ""
): Int64 {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return 0
    }
    let sessionKey = existingStringOr(normalized, gatewaySessionKeyByClient, "")
    if (sessionKey.isEmpty()) {
        return 0
    }
    let connectionId = if (runId.trimAscii().isEmpty()) {
        existingStringOr(normalized, gatewayConnectionIdByClient, "")
    } else {
        runId.trimAscii()
    }
    let conversation = gatewayFindSessionConversationViewForUser(CliSettingManager.readGatewaySettings(), sessionKey)
    let payload = gatewayBuildSessionEventPayload(
        sessionKey,
        state,
        conversation: conversation,
        runId: connectionId,
        detail: detail
    )
    gatewayServerPublishSessionLifecycleEvent(payload, detail: detail)
}

private func gatewayServerPublishSessionUpdateForClient(
    clientId: String,
    state: String,
    detail!: String = "",
    runId!: String = "",
    errorMessage!: String = ""
): Int64 {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return 0
    }
    let sessionKey = existingStringOr(normalized, gatewaySessionKeyByClient, "")
    if (sessionKey.isEmpty()) {
        return 0
    }
    let effectiveRunId = if (runId.trimAscii().isEmpty()) {
        existingStringOr(normalized, gatewayConnectionIdByClient, "")
    } else {
        runId.trimAscii()
    }
    let conversation = gatewayFindSessionConversationViewForUser(CliSettingManager.readGatewaySettings(), sessionKey)
    let payload = gatewayBuildSessionEventPayload(
        sessionKey,
        state,
        conversation: conversation,
        runId: effectiveRunId,
        detail: detail,
        errorMessage: errorMessage
    )
    gatewayServerPublishSessionEvent(payload, detail: detail)
}

private func gatewayServerPublishEventLocked(
    clientId: String,
    kind: String,
    detail!: String = "",
    payload!: JsonValue = JsonObject()
): Unit {
    let normalized = clientId.trimAscii()
    if (normalized.isEmpty()) {
        return
    }
    gatewayEventSequence += 1
    let event = JsonObject()
    event.put("id", JsonString("evt-${gatewayEventSequence}"))
    event.put("kind", JsonString(kind))
    event.put("detail", JsonString(detail))
    event.put("clientId", JsonString(normalized))
    event.put("ts", gatewayServerNowMs().toJsonValue())
    event.put("payload", payload)
    try {
        let payloadObj = payload.asObject()
        match (payloadObj.get("sessionKey")) {
            case Some(v) =>
                try {
                    gatewayServerAppendSessionProjection(event, v.asString().getValue())
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
    } catch (_: Exception) {
        ()
    }
    let directPublished =
        gatewayServerShouldDirectPushControlUiEventLocked(normalized, kind) &&
        gatewayControlUiWsWriteGatewayEventToClient(normalized, event)
    if (!directPublished && gatewayServerShouldQueueEventLocked(normalized, kind)) {
        let queue = match (gatewayEventQueueByClient.get(normalized)) {
            case Some(v) => v
            case None =>
                let created = ArrayList<JsonObject>()
                gatewayEventQueueByClient[normalized] = created
                created
        }
        queue.add(event)
        gatewayServerTrimEventQueueLocked(queue)
    }
    gatewayRecentEvents.add(event)
    if (gatewayRecentEvents.size > 64) {
        let trimmed = ArrayList<JsonObject>()
        for (i in 1..gatewayRecentEvents.size) {
            trimmed.add(gatewayRecentEvents[i])
        }
        gatewayRecentEvents = trimmed
    }
}

private func gatewayEventIdFromObject(event: JsonObject): String {
    match (event.get("id")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayEventSequenceFromObject(event: JsonObject): Int64 {
    gatewayEventSequenceFromId(gatewayEventIdFromObject(event))
}

private func gatewayServerShouldSkipPulledEvent(req: GatewayProtocolRequest, event: JsonObject): Bool {
    if (req.method != "events.stream") {
        return false
    }
    let kind = match (event.get("kind")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
    if (kind == "stream.open" || kind == "stream.wait") {
        return true
    }
    kind == "request.begin" || kind == "request.finish" || kind == "request.fail"
}

private func gatewayEventSequenceFromId(eventId: String): Int64 {
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

private func gatewayServerRequestParamString(params: JsonObject, keys: Array<String>): String {
    for (key in keys) {
        match (params.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_: Exception) {
                    ()
                }
            case None => ()
        }
    }
    ""
}

private func gatewayServerTargetClientId(req: GatewayProtocolRequest): String {
    let requested = gatewayServerRequestParamString(req.params, ["clientId", "client", "id"])
    if (!requested.isEmpty()) {
        return requested
    }
    req.connect.client.id.trimAscii()
}

private func gatewayServerPullDeliveredCount(pull: JsonObject): Int64 {
    match (pull.get("deliveredCount")) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayServerPullDeliveredPushCount(events: JsonArray): Int64 {
    var count: Int64 = 0
    var i: Int64 = 0
    while (i < Int64(events.size())) {
        try {
            if (gatewayEventIsServerPush(events[i].asObject())) {
                count += 1
            }
        } catch (_e: Exception) {
        }
        i += 1
    }
    count
}

private func gatewayServerPullHasServerPush(pull: JsonObject): Bool {
    match (pull.get("events")) {
        case Some(v) =>
            try {
                gatewayServerPullDeliveredPushCount(v.asArray()) > 0
            } catch (_e: Exception) {
                false
            }
        case None => false
    }
}

private func gatewayEventIsServerPush(event: JsonObject): Bool {
    match (event.get("kind")) {
        case Some(v) =>
            try {
                v.asString().getValue().startsWith("stream.push")
            } catch (_e: Exception) {
                false
            }
        case None => false
    }
}

private func gatewayServerCleanupExpiredRequestsLocked(options: GatewayServerOptions): Unit {
    if (options.requestTimeoutMs <= 0) {
        return
    }
    let now = gatewayServerNowMs()
    let expired = ArrayList<String>()
    for ((requestId, startedAt) in gatewayActiveRequestStartedAtById) {
        if (now - startedAt > options.requestTimeoutMs) {
            expired.add(requestId)
        }
    }
    for (requestId in expired) {
        let clientId = existingStringOr(requestId, gatewayActiveRequestClientById, "")
        gatewayActiveRequestMethodById.remove(requestId)
        gatewayActiveRequestClientById.remove(requestId)
        gatewayActiveRequestSessionById.remove(requestId)
        gatewayActiveRequestStartedAtById.remove(requestId)
        if (gatewayServerActiveRequests > 0) {
            gatewayServerActiveRequests -= 1
        }
        gatewayServerTimeoutCount += 1
        gatewayServerLastError = GATEWAY_ERROR_REQUEST_TIMEOUT
        gatewayServerPublishEventLocked(clientId, "request.timeout", detail: requestId)
        let _ = gatewayServerPublishSessionUpdateForClient(
            clientId,
            "request-timeout",
            detail: "request-timeout",
            runId: requestId,
            errorMessage: GATEWAY_ERROR_REQUEST_TIMEOUT
        )
    }
}

private func gatewayServerChallengeRegistrySnapshotLocked(): JsonArray {
    let out = JsonArray([])
    for ((connectionId, token) in gatewayChallengeTokenByConnection) {
        let clientId = existingStringOr(connectionId, gatewayChallengeClientIdByConnection, "")
        let pending =
            !existingBoolOr(connectionId, gatewayChallengeAckedByConnection, false) &&
            existingIntOr(connectionId, gatewayChallengeExpiresAtByConnection, 0) > gatewayServerNowMs()
        let row = JsonObject()
        row.put("clientId", JsonString(clientId))
        row.put("connectionId", JsonString(connectionId))
        row.put("token", JsonString(token))
        row.put("expiresAtMs", existingIntOr(connectionId, gatewayChallengeExpiresAtByConnection, 0).toJsonValue())
        row.put("acked", existingBoolOr(connectionId, gatewayChallengeAckedByConnection, false).toJsonValue())
        row.put("pending", pending.toJsonValue())
        gatewayServerAppendSessionProjection(row, existingStringOr(clientId, gatewaySessionKeyByClient, ""))
        out.add(row)
    }
    out
}

private func gatewayServerEventQueueSnapshotLocked(): JsonArray {
    let out = JsonArray([])
    for ((clientId, queue) in gatewayEventQueueByClient) {
        let row = JsonObject()
        row.put("clientId", JsonString(clientId))
        row.put("depth", queue.size.toJsonValue())
        gatewayServerAppendSessionProjection(row, existingStringOr(clientId, gatewaySessionKeyByClient, ""))
        out.add(row)
    }
    out
}

private func gatewayServerRecentEventSnapshotLocked(): JsonArray {
    let out = JsonArray([])
    for (event in gatewayRecentEvents) {
        out.add(event)
    }
    out
}

private func gatewayServerEventQueueDepthLocked(clientId: String): Int64 {
    match (gatewayEventQueueByClient.get(clientId.trimAscii())) {
        case Some(v) => Int64(v.size)
        case None => 0
    }
}

private func gatewayServerBeginRequestLocked(req: GatewayProtocolRequest): Unit {
    gatewayActiveRequestMethodById[req.requestId] = req.method
    gatewayActiveRequestClientById[req.requestId] = req.connect.client.id
    gatewayActiveRequestSessionById[req.requestId] = req.connect.sessionKey
    gatewayActiveRequestStartedAtById[req.requestId] = gatewayServerNowMs()
    gatewayServerPublishEventLocked(req.connect.client.id, "request.begin", detail: req.method)
    let _ = gatewayServerPublishSessionUpdateForClient(
        req.connect.client.id,
        "request-begin",
        detail: req.method,
        runId: req.requestId
    )
}

private func gatewayServerFinishRequestLocked(req: GatewayProtocolRequest, ok!: Bool, error!: String = ""): Unit {
    let clientId = existingStringOr(req.requestId, gatewayActiveRequestClientById, req.connect.client.id)
    gatewayActiveRequestMethodById.remove(req.requestId)
    gatewayActiveRequestClientById.remove(req.requestId)
    gatewayActiveRequestSessionById.remove(req.requestId)
    gatewayActiveRequestStartedAtById.remove(req.requestId)
    if (gatewayServerActiveRequests > 0) {
        gatewayServerActiveRequests -= 1
    } else {
        gatewayServerActiveRequests = 0
    }
    if (!ok && !error.trimAscii().isEmpty()) {
        gatewayServerLastError = error
    }
    gatewayServerPublishEventLocked(
        clientId,
        if (ok) { "request.finish" } else { "request.fail" },
        detail: req.method
    )
    let _ = gatewayServerPublishSessionUpdateForClient(
        clientId,
        if (ok) { "request-finish" } else { "request-fail" },
        detail: req.method,
        runId: req.requestId,
        errorMessage: error
    )
}

private func gatewayServerSessionBindingsSnapshot(): JsonArray {
    let grouped = HashMap<String, ArrayList<String>>()
    for ((clientId, sessionKey) in gatewaySessionKeyByClient) {
        let normalized = sessionKey.trimAscii()
        if (normalized.isEmpty()) {
            continue
        }
        match (grouped.get(normalized)) {
            case Some(existing) => existing.add(clientId)
            case None =>
                let row = ArrayList<String>()
                row.add(clientId)
                grouped[normalized] = row
        }
    }
    let out = JsonArray([])
    for ((sessionKey, clientIds) in grouped) {
        let row = JsonObject()
        row.put("sessionKey", JsonString(sessionKey))
        row.put("clientIds", clientIds.toArray().toJsonValue())
        gatewayServerAppendSessionProjection(row, sessionKey)
        out.add(row)
    }
    out
}

private func gatewayServerRuntimeOptionString(rpc: JsonObject, key: String): JsonValue {
    match (rpc.get("options")) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                obj.get(key) ?? JsonString("")
            } catch (_e: Exception) {
                JsonString("")
            }
        case None => JsonString("")
    }
}

private func gatewayServerRuntimeOptionBool(rpc: JsonObject, key: String): JsonValue {
    match (rpc.get("options")) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                obj.get(key) ?? false.toJsonValue()
            } catch (_e: Exception) {
                false.toJsonValue()
            }
        case None => false.toJsonValue()
    }
}

private func gatewayServerRuntimeOptionInt(rpc: JsonObject, key: String): JsonValue {
    match (rpc.get("options")) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                obj.get(key) ?? 0.toJsonValue()
            } catch (_e: Exception) {
                0.toJsonValue()
            }
        case None => 0.toJsonValue()
    }
}

private func persistSnapshotLocked(force!: Bool = false): Unit {
    persistSnapshotLockedWithOptions(gatewayServerCurrentOptions, force: force)
}

private func persistSnapshotLockedWithOptions(options: GatewayServerOptions, force!: Bool = false): Unit {
    gatewayServerSnapshotDirty = true
    let now = gatewayServerNowMs()
    if (!force && gatewayServerLastPersistAtMs > 0 && (now - gatewayServerLastPersistAtMs) < GATEWAY_SERVER_SNAPSHOT_WRITE_INTERVAL_MS) {
        return
    }
    if (!gatewayServerSnapshotDirty && !force) {
        return
    }
    File.writeTo(CliConfig.dotDir.join("gateway-rpc-state.json"), buildSnapshotLockedWithOptions(options).toJsonString().toArray())
    gatewayServerLastPersistAtMs = now
    gatewayServerSnapshotDirty = false
}

private func gatewayServerNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func existingStringOr(key: String, map: HashMap<String, String>, fallback: String): String {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func existingIntOr(key: String, map: HashMap<String, Int64>, fallback: Int64): Int64 {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func existingBoolOr(key: String, map: HashMap<String, Bool>, fallback: Bool): Bool {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func existingArrayOr(key: String, map: HashMap<String, Array<String>>, fallback: Array<String>): Array<String> {
    match (map.get(key)) {
        case Some(v) => v
        case None => fallback
    }
}

private func gatewayServerTransportAllowedLocked(params: GatewayConnectParams, options: GatewayServerOptions): Bool {
    let normalized = params.transportKind.trimAscii().toAsciiLower()
    if (normalized == "local" || normalized == "local-rpc") {
        return options.localTransportEnabled
    }
    if (normalized == "remote" || normalized == "ws" || normalized == "wss" || normalized == "http" || normalized == "https") {
        return options.remoteTransportEnabled
    }
    options.localTransportEnabled
}
