package metis.gateway.runtime

import magic.prelude.*

import metis.gateway.tools.GatewayManagedSessionsToolset

import std.convert.Parsable

import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func gatewaySubagentsRpcStringParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (request.params.get(key)) {
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
    defaultValue
}

private func gatewaySubagentsRpcIntParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: Int64): Int64 {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    return Int64.parse(v.asString().getValue().trimAscii())
                } catch (_: Exception) {
                    try {
                        return Int64.parse(v.toJsonString())
                    } catch (_inner: Exception) {
                        ()
                    }
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewaySubagentsToolJson(action: String, target: String, message: String, recentMinutes: Int64): JsonObject {
    let toolset = GatewayManagedSessionsToolset()
    let raw = toolset.subagentsForCommand(
        Some<String>(action),
        if (target.trimAscii().isEmpty()) { None<String> } else { Some<String>(target.trimAscii()) },
        if (message.trimAscii().isEmpty()) { None<String> } else { Some<String>(message.trimAscii()) },
        if (recentMinutes > 0) { Some<Int64>(recentMinutes) } else { None<Int64> }
    )
    try {
        JsonValue.fromStr(raw).asObject()
    } catch (_: Exception) {
        let err = JsonObject()
        err.put("ok", false.toJsonValue())
        err.put("status", JsonString("error"))
        err.put("action", JsonString(action))
        err.put("error", JsonString("subagents tool returned invalid json"))
        err
    }
}

public func gatewayDashboardSubagentsJson(): JsonObject {
    gatewaySubagentsToolJson("list", "all", "", 0)
}

public func handleGatewaySubagentsFamily(method: String, request!: Option<GatewayRpcRequest> = None<GatewayRpcRequest>): Option<GatewayRpcResponse> {
    let normalized = method.trimAscii().toAsciiLower()
    if (!normalized.startsWith("subagents.")) {
        return None<GatewayRpcResponse>
    }
    let action = normalized["subagents.".size..].trimAscii()
    match (action) {
        case "list" | "status" | "poll" | "logs" | "kill" | "cleanup" =>
            let req = match (request) {
                case Some(value) => value
                case None => GatewayRpcRequest(method)
            }
            let target = gatewaySubagentsRpcStringParam(req, ["target", "runId", "sessionKey", "filter"], if (action == "list") { "all" } else { "" })
            let message = gatewaySubagentsRpcStringParam(req, ["message"], "")
            let recentMinutes = gatewaySubagentsRpcIntParam(req, ["recentMinutes", "recent"], 0)
            let result = gatewaySubagentsToolJson(action, target, message, recentMinutes)
            return Some(GatewayRpcResponse(true, method, result: result))
        case _ => ()
    }
    None<GatewayRpcResponse>
}
