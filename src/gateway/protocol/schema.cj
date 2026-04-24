package metis.gateway.protocol

import magic.jsonable.*

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

public let GATEWAY_PROTOCOL_VERSION = "2025-03-26"
public let GATEWAY_ERROR_UNSUPPORTED_PROTOCOL = "UNSUPPORTED_PROTOCOL_VERSION"
public let GATEWAY_ERROR_INVALID_CONNECT = "INVALID_CONNECT_PARAMS"
public let GATEWAY_ERROR_TRANSPORT_DISABLED = "TRANSPORT_NOT_ENABLED"
public let GATEWAY_ERROR_CONNECT_FAILED = "CONNECT_FAILED"
public let GATEWAY_ERROR_AUTH_FAILED = "AUTH_FAILED"
public let GATEWAY_ERROR_REMOTE_UNAVAILABLE = "REMOTE_UNAVAILABLE"
public let GATEWAY_ERROR_INVALID_RESPONSE = "INVALID_REMOTE_RESPONSE"
public let GATEWAY_ERROR_UNSUPPORTED_METHOD = "UNSUPPORTED_METHOD"
public let GATEWAY_ERROR_REQUEST_TIMEOUT = "REQUEST_TIMEOUT"
public let GATEWAY_ERROR_REQUEST_CANCELLED = "REQUEST_CANCELLED"
public let GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED = "CONNECT_CHALLENGE_REQUIRED"
public let GATEWAY_ERROR_NOT_CONNECTED = "NOT_CONNECTED"

public class GatewayClientInfo {
    public let id: String
    public let name: String
    public let mode: String
    public let version: String

    public init(
        id: String,
        name!: String = "",
        mode!: String = "",
        version!: String = "dev"
    ) {
        this.id = id
        this.name = name
        this.mode = mode
        this.version = version
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("id", JsonString(this.id))
        obj.put("name", JsonString(this.name))
        obj.put("mode", JsonString(this.mode))
        obj.put("version", JsonString(this.version))
        obj
    }
}

public class GatewayConnectParams {
    public let client: GatewayClientInfo
    public let transport: String
    public let transportKind: String
    public let gatewayUrl: String
    public let timeoutMs: Int64
    public let requestedAtMs: Int64
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

    public init(
        client: GatewayClientInfo,
        transport!: String = "local",
        transportKind!: String = "local",
        gatewayUrl!: String = "local://gateway",
        timeoutMs!: Int64 = 3000,
        requestedAtMs!: Int64 = 0,
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
        this.client = client
        this.transport = transport
        this.transportKind = transportKind
        this.gatewayUrl = gatewayUrl
        this.timeoutMs = timeoutMs
        this.requestedAtMs = requestedAtMs
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
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("client", this.client.toJson())
        obj.put("transport", JsonString(this.transport))
        obj.put("transportKind", JsonString(this.transportKind))
        obj.put("gatewayUrl", JsonString(this.gatewayUrl))
        obj.put("timeoutMs", this.timeoutMs.toJsonValue())
        obj.put("requestedAtMs", this.requestedAtMs.toJsonValue())
        obj.put("sessionKey", JsonString(this.sessionKey))
        obj.put("sessionHint", JsonString(this.sessionHint))
        obj.put("connectionId", JsonString(this.connectionId))
        obj.put("capabilities", this.capabilities.toJsonValue())
        obj.put("operatorScopes", this.operatorScopes.toJsonValue())
        obj.put("authToken", JsonString(this.authToken))
        obj.put("authPassword", JsonString(this.authPassword))
        obj.put("deviceId", JsonString(this.deviceId))
        obj.put("deviceToken", JsonString(this.deviceToken))
        obj.put("declaredUser", JsonString(this.declaredUser))
        obj
    }
}

public class GatewayProtocolRequest {
    public let protocolVersion: String
    public let method: String
    public let params: JsonObject
    public let connect: GatewayConnectParams
    public let requestId: String

    public init(
        method: String,
        connect: GatewayConnectParams,
        protocolVersion!: String = GATEWAY_PROTOCOL_VERSION,
        params!: JsonObject = JsonObject(),
        requestId!: String = ""
    ) {
        this.protocolVersion = protocolVersion
        this.method = method
        this.connect = connect
        this.params = params
        this.requestId = requestId
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("protocolVersion", JsonString(this.protocolVersion))
        obj.put("method", JsonString(this.method))
        obj.put("params", this.params)
        obj.put("connect", this.connect.toJson())
        obj.put("requestId", JsonString(this.requestId))
        obj
    }
}

public class GatewayProtocolResponse {
    public let protocolVersion: String
    public let ok: Bool
    public let method: String
    public let requestId: String
    public let result: JsonValue
    public let error: String
    public let errorCode: String
    public let details: JsonValue

    public init(
        ok: Bool,
        method: String,
        protocolVersion!: String = GATEWAY_PROTOCOL_VERSION,
        requestId!: String = "",
        result!: JsonValue = JsonObject(),
        error!: String = "",
        errorCode!: String = "",
        details!: JsonValue = JsonObject()
    ) {
        this.protocolVersion = protocolVersion
        this.ok = ok
        this.method = method
        this.requestId = requestId
        this.result = result
        this.error = error
        this.errorCode = errorCode
        this.details = details
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
        obj.put("protocolVersion", JsonString(this.protocolVersion))
        obj.put("ok", this.ok.toJsonValue())
        obj.put("method", JsonString(this.method))
        obj.put("requestId", JsonString(this.requestId))
        if (this.ok) {
            obj.put("result", this.result)
        } else {
            obj.put("error", JsonString(this.error))
            obj.put("errorCode", JsonString(this.errorCode))
            obj.put("details", this.details)
        }
        obj
    }
}

public func validateGatewayConnectParams(params: GatewayConnectParams): Bool {
    !params.client.id.trimAscii().isEmpty() &&
        !params.transport.trimAscii().isEmpty() &&
        !params.transportKind.trimAscii().isEmpty() &&
        !params.gatewayUrl.trimAscii().isEmpty()
}

public func validateGatewayProtocolVersion(version: String): Bool {
    version.trimAscii().isEmpty() || version.trimAscii() == GATEWAY_PROTOCOL_VERSION
}
