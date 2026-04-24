package metis.gateway.runtime

import magic.jsonable.*

import stdx.encoding.json.{JsonObject, JsonValue}

private func gatewayChatAliasMethod(method: String): String {
    let shared = gatewayDashboardMethodAlias(method)
    if (!shared.isEmpty()) {
        return shared
    }
    match (method.trimAscii().toAsciiLower()) {
        case "chat.status" => "dashboard.status"
        case "chat.sessions.list" => "dashboard.status"
        case "chat.sessions.delete" => "dashboard.sessions.delete"
        case _ => ""
    }
}

private func gatewayChatAliasResponse(method: String, request: GatewayRpcRequest): Option<GatewayRpcResponse> {
    let dashboardMethod = gatewayChatAliasMethod(method)
    if (dashboardMethod.isEmpty()) {
        return None<GatewayRpcResponse>
    }
    handleGatewayDashboardFamily(
        dashboardMethod,
        GatewayRpcRequest(
            dashboardMethod,
            params: request.params,
            clientId: request.clientId,
            clientName: request.clientName,
            mode: request.mode,
            transport: request.transport,
            transportKind: request.transportKind,
            gatewayUrl: request.gatewayUrl
        )
    )
}

private func gatewayChatAliasPassthrough(method: String, request: GatewayRpcRequest): Option<GatewayRpcResponse> {
    match (gatewayChatAliasResponse(method, request)) {
        case Some(response) =>
            Some(
                GatewayRpcResponse(
                    response.ok,
                    method,
                    result: response.result,
                    error: response.error,
                    errorCode: response.errorCode,
                    details: response.details
                )
            )
        case None => None<GatewayRpcResponse>
    }
}

private func gatewayChatAliasWrapped(method: String, request: GatewayRpcRequest, field: String): Option<GatewayRpcResponse> {
    match (gatewayChatAliasResponse(method, request)) {
        case Some(response) =>
            let result = JsonObject()
            if (field == "sessions") {
                result.put("sessions", response.result)
            } else {
                result.put(field, response.result.asObject().get(field) ?? JsonObject())
            }
            Some(
                GatewayRpcResponse(
                    response.ok,
                    method,
                    result: result,
                    error: response.error,
                    errorCode: response.errorCode,
                    details: response.details
                )
            )
        case None => None<GatewayRpcResponse>
    }
}

public func handleGatewayChatFamily(method: String, request: GatewayRpcRequest): Option<GatewayRpcResponse> {
    if (method == "chat.history") {
        return gatewayChatAliasPassthrough(method, request)
    }
    if (method == "chat.send") {
        return gatewayChatAliasPassthrough(method, request)
    }
    if (method == "chat.status") {
        return gatewayChatAliasWrapped(method, request, "chat")
    }
    if (method == "chat.sessions.list") {
        return gatewayChatAliasWrapped(method, request, "sessions")
    }
    if (method == "chat.sessions.delete") {
        return gatewayChatAliasWrapped(method, request, "sessions")
    }
    None
}
