package metis.gateway.protocol

import std.time.DateTime

private func gatewayProtocolNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

public func gatewayProtocolDefaultConnect(
    clientName: String,
    mode!: String = "local-cli",
    transport!: String = "local",
    gatewayUrl!: String = "local://gateway",
    timeoutMs!: Int64 = 3000,
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
): GatewayConnectParams {
    GatewayConnectParams(
        GatewayClientInfo(
            gatewayClientIdForName(clientName),
            name: clientName,
            mode: mode
        ),
        transport: transport,
        transportKind: transport,
        gatewayUrl: gatewayUrl,
        timeoutMs: timeoutMs,
        requestedAtMs: gatewayProtocolNowMs(),
        sessionKey: sessionKey,
        sessionHint: sessionHint,
        connectionId: connectionId,
        capabilities: capabilities,
        operatorScopes: operatorScopes,
        authToken: authToken,
        authPassword: authPassword,
        deviceId: deviceId,
        deviceToken: deviceToken,
        declaredUser: declaredUser
    )
}
