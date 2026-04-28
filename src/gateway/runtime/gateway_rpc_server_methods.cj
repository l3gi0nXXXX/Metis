package metis.gateway.runtime

import metis.core.config.CliSettingManager
public func gatewayDispatchLocalMethod(request: GatewayRpcRequest): GatewayRpcResponse {
    let requested = request.method.trimAscii()
    let normalized = requested.toAsciiLower()
    let method = match (gatewayDashboardMethodAlias(requested)) {
        case "" =>
            if (normalized == "skills.compatibilitymatrix") {
                "skills.compatibilityMatrix"
            } else {
                normalized
            }
        case alias => alias
    }
    let user = CliSettingManager.readGatewaySettings()

    match (handleGatewayStatusFamily(method, user)) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayPlatformFamily(method, user)) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayCronFamily(method, request)) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewaySessionsFamily(method, request: Some(request))) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewaySubagentsFamily(method, request: Some(request))) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayChannelsFamily(method, user, request: Some(request))) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayAgentsFamily(method, request: Some(request))) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewaySkillsFamily(method, request: Some(request))) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayChatFamily(method, request)) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayWizardFamily(method)) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayDashboardFamily(method, request)) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayOpsFamily(method, user, request: Some(request))) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayConfigFamily(method, request, user)) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayConnectFamily(method, request: Some(request))) {
        case Some(res) => return res
        case None => ()
    }
    match (handleGatewayRuntimeMutationFamily(method, request, user)) {
        case Some(res) => return res
        case None => ()
    }

    GatewayRpcResponse(false, method, error: "Unsupported local gateway RPC method: ${method}")
}
