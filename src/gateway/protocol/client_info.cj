package metis.gateway.protocol

public let GATEWAY_CLIENT_ID_CLI = "metis-cli"
public let GATEWAY_CLIENT_ID_TOOL = "metis-agent-tool"
public let GATEWAY_CLIENT_ID_GATEWAY = "metis-gateway-client"

public let GATEWAY_CLIENT_MODE_LOCAL_CLI = "local-cli"
public let GATEWAY_CLIENT_MODE_AGENT_TOOL = "agent-tool"
public let GATEWAY_CLIENT_MODE_LOCAL_RPC = "local-rpc"

public func gatewayClientIdForName(name: String): String {
    let normalized = name.trimAscii().toAsciiLower()
    if (normalized == "tool" || normalized == "agent-tool") {
        return GATEWAY_CLIENT_ID_TOOL
    }
    if (normalized == "gateway" || normalized == "gateway-client") {
        return GATEWAY_CLIENT_ID_GATEWAY
    }
    GATEWAY_CLIENT_ID_CLI
}
