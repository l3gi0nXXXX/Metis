package metis.gateway.runtime

import magic.jsonable.*

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

public class GatewayRpcRequest {
    public let method: String
    public let params: JsonObject
    public let clientId: String
    public let clientName: String
    public let mode: String
    public let transport: String
    public let transportKind: String
    public let gatewayUrl: String

    public init(
        method: String,
        params!: JsonObject = JsonObject(),
        clientId!: String = "metis-cli",
        clientName!: String = "cli",
        mode!: String = "local-cli",
        transport!: String = "local",
        transportKind!: String = "local",
        gatewayUrl!: String = "local://gateway"
    ) {
        this.method = method
        this.params = params
        this.clientId = clientId
        this.clientName = clientName
        this.mode = mode
        this.transport = transport
        this.transportKind = transportKind
        this.gatewayUrl = gatewayUrl
    }
}

public class GatewayRpcResponse {
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
        requestId!: String = "",
        result!: JsonValue = JsonObject(),
        error!: String = "",
        errorCode!: String = "",
        details!: JsonValue = JsonObject()
    ) {
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
