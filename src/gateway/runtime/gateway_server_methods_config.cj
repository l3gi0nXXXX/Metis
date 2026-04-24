package metis.gateway.runtime

import metis.core.config.{CliSettingManager, GatewayUserSettings}

import stdx.encoding.json.{JsonObject, JsonString}

public func handleGatewayConfigFamily(method: String, request: GatewayRpcRequest, user: GatewayUserSettings): Option<GatewayRpcResponse> {
    if (method == "config.get") {
        let rawPath = match (request.params.get("path")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_e: Exception) { "gateway" }
            case None => "gateway"
        }
        match (gatewayRpcConfigValueAtPath(user, rawPath)) {
            case Some(value) =>
                let result = JsonObject()
                result.put("path", JsonString(rawPath))
                result.put("value", value)
                return Some(GatewayRpcResponse(true, method, result: result))
            case None =>
                return Some(GatewayRpcResponse(false, method, error: "Unknown gateway config path."))
        }
    }
    if (method == "config.schema.lookup") {
        let rawPath = match (request.params.get("path")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_e: Exception) { "gateway" }
            case None => "gateway"
        }
        let result = JsonObject()
        result.put("path", JsonString(rawPath))
        result.put("schema", JsonString(gatewayRpcSchemaLookup(rawPath)))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "config.patch" || method == "config.apply") {
        let rawPath = match (request.params.get("path")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_e: Exception) { "" }
            case None => ""
        }
        let rawValue = match (request.params.get("raw")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_e: Exception) { "" }
            case None => ""
        }
        let patchResult = applyGatewayConfigPatch(rawPath, rawValue)
        let result = JsonObject()
        result.put("path", JsonString(rawPath))
        if (patchResult[0]) {
            result.put("status", JsonString("ok"))
            result.put("message", JsonString(patchResult[1]))
            match (gatewayRpcConfigValueAtPath(CliSettingManager.readGatewaySettings(), rawPath)) {
                case Some(v) => result.put("value", v)
                case None => result.put("value", JsonObject())
            }
            return Some(GatewayRpcResponse(true, method, result: result))
        }
        result.put("status", JsonString("error"))
        return Some(GatewayRpcResponse(false, method, result: result, error: patchResult[1]))
    }
    None
}
