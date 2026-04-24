package metis.gateway.runtime

import stdx.encoding.json.JsonObject

public func callGatewayLocal(
    method: String,
    params!: JsonObject = JsonObject(),
    clientName!: String = "cli",
    mode!: String = "local-cli"
): GatewayRpcResponse {
    let client = GatewayClient(clientName: clientName, mode: mode, transport: "local", gatewayUrl: "local://gateway")
    client.request(method, params: params)
}
