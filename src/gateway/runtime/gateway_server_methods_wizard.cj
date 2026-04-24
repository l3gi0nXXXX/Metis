package metis.gateway.runtime

import metis.core.config.MetisConfigManager

import stdx.encoding.json.{JsonObject, JsonString}

private func gatewayWizardConfigJson(): JsonObject {
    match (MetisConfigManager.rawConfig()) {
        case Some(root) =>
            match (root.get("wizard")) {
                case Some(value) =>
                    try { value.asObject() } catch (_: Exception) { JsonObject() }
                case None => JsonObject()
            }
        case None => JsonObject()
    }
}

public func handleGatewayWizardFamily(method: String): Option<GatewayRpcResponse> {
    if (method == "wizard.status" || method == "wizard.get") {
        let result = JsonObject()
        result.put("wizard", gatewayWizardConfigJson())
        result.put("configPath", JsonString(MetisConfigManager.configPath().toString()))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    None
}
