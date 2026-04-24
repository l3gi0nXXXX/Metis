package metis.gateway

import magic.jsonable.*

import metis.core.config.CliSettingManager

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public let GATEWAY_MCP_PATH = "/mcp"
public let GATEWAY_MCP_PROTOCOL_VERSION = "2025-03-26"
public let GATEWAY_MCP_SERVER_NAME = "metis-gateway"
public let GATEWAY_MCP_DEFAULT_RESPONSE_ID = "mcp-local"

private func gatewayMcpAppendTool(tools: JsonArray, name: String, description: String): Unit {
    let row = JsonObject()
    row.put("name", JsonString(name))
    row.put("description", JsonString(description))
    tools.add(row)
}

public func gatewayMcpConfigured(): Bool {
    match (CliSettingManager.setting.mcpServers) {
        case Some(obj) => obj.toJsonString().trimAscii() != "{}"
        case None => false
    }
}

public func gatewayMcpInitializeResultJson(serverVersion: String): JsonObject {
    let result = JsonObject()
    result.put("protocolVersion", JsonString(GATEWAY_MCP_PROTOCOL_VERSION))
    let serverInfo = JsonObject()
    serverInfo.put("name", JsonString(GATEWAY_MCP_SERVER_NAME))
    serverInfo.put("version", JsonString(serverVersion))
    result.put("serverInfo", serverInfo)
    let caps = JsonObject()
    let tools = JsonObject()
    tools.put("listChanged", false.toJsonValue())
    caps.put("tools", tools)
    result.put("capabilities", caps)
    result
}

public func gatewayMcpPingResultJson(serverTime: Int64): JsonObject {
    let result = JsonObject()
    result.put("ok", true.toJsonValue())
    result.put("serverTime", serverTime.toJsonValue())
    result
}

public func gatewayMcpToolListResultJson(includeConfiguredMarker!: Bool = false): JsonObject {
    let result = JsonObject()
    let tools = JsonArray([])
    gatewayMcpAppendTool(tools, "gateway.status", "Read gateway status.")
    gatewayMcpAppendTool(tools, "gateway.health", "Read gateway health.")
    gatewayMcpAppendTool(tools, "gateway.connect.status", "Read gateway RPC connection status.")
    gatewayMcpAppendTool(tools, "gateway.connect.summary", "Read gateway RPC runtime summary.")
    gatewayMcpAppendTool(tools, "gateway.connect.lifecycle", "Read gateway RPC lifecycle history.")
    gatewayMcpAppendTool(tools, "gateway.connect.actions", "Read gateway RPC recommended runtime actions.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.open", "Open one gateway RPC event stream session.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.attach", "Attach to one existing gateway RPC event stream session.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.detach", "Detach from one existing gateway RPC event stream session.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.status", "Read one gateway RPC event stream status.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.keepalive", "Refresh one gateway RPC event stream lease.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.resume", "Resume one gateway RPC event stream from the last cursor.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.next", "Read the next event chunk from one gateway RPC stream.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.push", "Publish one server-side event into a gateway RPC stream.")
    gatewayMcpAppendTool(tools, "gateway.connect.ping", "Ping gateway RPC transport/runtime.")
    gatewayMcpAppendTool(tools, "gateway.connect.reconnect", "Recycle one gateway RPC client connection.")
    gatewayMcpAppendTool(tools, "gateway.connect.stream.close", "Close one gateway RPC event stream.")
    gatewayMcpAppendTool(tools, "gateway.transport.runtime", "Read gateway transport runtime summary.")
    gatewayMcpAppendTool(tools, "gateway.transport.remote", "Read gateway remote transport runtime.")
    gatewayMcpAppendTool(tools, "gateway.transport.lifecycle", "Read gateway transport lifecycle history.")
    gatewayMcpAppendTool(tools, "gateway.transport.reconnect.history", "Read gateway transport reconnect history.")
    gatewayMcpAppendTool(tools, "gateway.transport.reconnect.state", "Read gateway transport reconnect state.")
    gatewayMcpAppendTool(tools, "gateway.transport.reconnect.window", "Read gateway transport reconnect stability window.")
    gatewayMcpAppendTool(tools, "gateway.transport.reconnect.plan", "Read gateway transport reconnect plan.")
    gatewayMcpAppendTool(tools, "gateway.transport.reconnect.audit", "Read gateway transport reconnect audit view.")
    gatewayMcpAppendTool(tools, "gateway.transport.reconnect.reset", "Reset gateway transport reconnect state.")
    gatewayMcpAppendTool(tools, "gateway.transport.stream.health", "Read gateway transport stream health.")
    gatewayMcpAppendTool(tools, "gateway.transport.stream.audit", "Read gateway transport stream audit view.")
    gatewayMcpAppendTool(tools, "gateway.transport.reconnect", "Reconnect gateway transport runtime.")
    gatewayMcpAppendTool(tools, "gateway.agents.summary", "Read gateway agent summary.")
    gatewayMcpAppendTool(tools, "gateway.agent.health", "Read one gateway agent health view.")
    gatewayMcpAppendTool(tools, "gateway.agent.actions", "Read one gateway agent remediation/action plan.")
    gatewayMcpAppendTool(tools, "gateway.agent.routing", "Read one gateway agent routing plan.")
    gatewayMcpAppendTool(tools, "gateway.chat.send", "Send a gateway chat message.")
    gatewayMcpAppendTool(tools, "gateway.agent.preview", "Preview a gateway agent invocation.")
    gatewayMcpAppendTool(tools, "gateway.agent.invoke", "Invoke a gateway agent by session and prompt.")
    gatewayMcpAppendTool(tools, "gateway.nodes.list", "List gateway nodes.")
    gatewayMcpAppendTool(tools, "gateway.nodes.health", "Read one gateway node health view.")
    gatewayMcpAppendTool(tools, "gateway.nodes.execute", "Run one step of pending gateway node work.")
    gatewayMcpAppendTool(tools, "gateway.nodes.restart", "Restart one gateway node lifecycle.")
    gatewayMcpAppendTool(tools, "gateway.nodes.policy.audit", "Read gateway node scheduling audit.")
    gatewayMcpAppendTool(tools, "gateway.nodes.policy.reconcile", "Reconcile gateway node scheduling policy.")
    gatewayMcpAppendTool(tools, "gateway.devices.health", "Read one gateway device health view.")
    gatewayMcpAppendTool(tools, "gateway.devices.unregister", "Remove one gateway device from runtime state.")
    gatewayMcpAppendTool(tools, "gateway.devices.policy.audit", "Read gateway device approval audit.")
    gatewayMcpAppendTool(tools, "gateway.devices.approve", "Approve one gateway device.")
    gatewayMcpAppendTool(tools, "gateway.devices.deny", "Deny one gateway device.")
    gatewayMcpAppendTool(tools, "gateway.push.deliveries", "List push deliveries.")
    gatewayMcpAppendTool(tools, "gateway.push.get", "Read one gateway push delivery.")
    gatewayMcpAppendTool(tools, "gateway.push.retry", "Retry one recorded push delivery.")
    gatewayMcpAppendTool(tools, "gateway.push.orchestration.audit", "Read gateway push orchestration audit.")
    gatewayMcpAppendTool(tools, "gateway.push.orchestration.actions", "Read gateway push orchestration remediation actions.")
    gatewayMcpAppendTool(tools, "gateway.push.orchestrate", "Run gateway push orchestration once.")
    gatewayMcpAppendTool(tools, "gateway.canvas.audit", "Read gateway canvas pipeline audit.")
    gatewayMcpAppendTool(tools, "gateway.canvas.actions", "Read gateway canvas remediation actions.")
    gatewayMcpAppendTool(tools, "gateway.talk.audit", "Read gateway talk pipeline audit.")
    gatewayMcpAppendTool(tools, "gateway.talk.actions", "Read gateway talk remediation actions.")
    gatewayMcpAppendTool(tools, "gateway.discover.detail", "Read gateway channel and plugin discovery detail.")
    gatewayMcpAppendTool(tools, "gateway.channels.status", "Read gateway channel status summary.")
    gatewayMcpAppendTool(tools, "gateway.channels.list", "List gateway channels.")
    gatewayMcpAppendTool(tools, "gateway.channels.get", "Read one gateway channel detail.")
    gatewayMcpAppendTool(tools, "gateway.channels.runtime", "Read one gateway channel runtime view.")
    gatewayMcpAppendTool(tools, "gateway.channels.health", "Read gateway channel health summary.")
    gatewayMcpAppendTool(tools, "gateway.channels.audit", "Read gateway channel audit summary.")
    gatewayMcpAppendTool(tools, "gateway.channels.bindings", "Read one gateway channel binding view.")
    gatewayMcpAppendTool(tools, "gateway.channels.policy", "Read gateway channel policy summary.")
    gatewayMcpAppendTool(tools, "gateway.channels.manager", "Read one gateway channel manager runtime view.")
    gatewayMcpAppendTool(tools, "gateway.channels.health.actions", "Read gateway channel health remediation actions.")
    gatewayMcpAppendTool(tools, "gateway.channels.start", "Start one gateway channel via host-backed runtime forwarder.")
    gatewayMcpAppendTool(tools, "gateway.channels.stop", "Stop one gateway channel via host-backed runtime forwarder.")
    gatewayMcpAppendTool(tools, "gateway.channels.send", "Send one test message through a gateway channel host forwarder.")
    gatewayMcpAppendTool(tools, "gateway.channels.logout", "Log out one gateway channel account.")
    gatewayMcpAppendTool(tools, "gateway.plugins.status", "Read gateway plugin status summary.")
    gatewayMcpAppendTool(tools, "gateway.plugins.list", "List gateway plugins.")
    gatewayMcpAppendTool(tools, "gateway.plugins.get", "Read one gateway plugin detail.")
    gatewayMcpAppendTool(tools, "gateway.plugins.runtime", "Read one gateway plugin runtime view.")
    gatewayMcpAppendTool(tools, "gateway.plugins.health", "Read gateway plugin health summary.")
    gatewayMcpAppendTool(tools, "gateway.plugins.bindings", "Read one gateway plugin binding view.")
    gatewayMcpAppendTool(tools, "gateway.plugins.policy", "Read gateway plugin policy summary.")
    gatewayMcpAppendTool(tools, "gateway.plugins.manager", "Read one gateway plugin manager runtime view.")
    gatewayMcpAppendTool(tools, "gateway.plugins.health.actions", "Read gateway plugin health remediation actions.")
    gatewayMcpAppendTool(tools, "gateway.plugins.actions", "Read gateway plugin action discovery from the compatibility host.")
    gatewayMcpAppendTool(tools, "gateway.plugins.approvals", "Read gateway plugin approval review state.")
    gatewayMcpAppendTool(tools, "gateway.plugins.package_state", "Read gateway plugin package probe state.")
    gatewayMcpAppendTool(tools, "gateway.plugins.setup", "Read gateway plugin setup state.")
    gatewayMcpAppendTool(tools, "gateway.plugins.setup.registry", "Read gateway plugin setup registry/validation capability.")
    gatewayMcpAppendTool(tools, "gateway.plugins.setup.apply", "Apply gateway plugin setup/config into persisted bindings.")
    gatewayMcpAppendTool(tools, "gateway.plugins.runtime.forwarders", "Read gateway plugin host runtime forwarders.")
    gatewayMcpAppendTool(tools, "gateway.plugins.resolve_account", "Resolve one gateway plugin account via the compatibility host.")
    gatewayMcpAppendTool(tools, "gateway.plugins.directory", "Read one gateway plugin live directory snapshot.")
    gatewayMcpAppendTool(tools, "gateway.plugins.targets", "Resolve one gateway plugin target against the live directory.")
    gatewayMcpAppendTool(tools, "gateway.plugins.actions.dispatch", "Dispatch one gateway plugin action through the compatibility host.")
    gatewayMcpAppendTool(tools, "gateway.plugins.start", "Start one gateway plugin account through the compatibility host.")
    gatewayMcpAppendTool(tools, "gateway.plugins.stop", "Stop one gateway plugin account through the compatibility host.")
    gatewayMcpAppendTool(tools, "gateway.plugins.send", "Send one test message through the compatibility host.")
    gatewayMcpAppendTool(tools, "gateway.plugins.logout", "Log out one gateway plugin account through the compatibility host.")
    gatewayMcpAppendTool(tools, "gateway.platform.runtime", "Read gateway platform runtime summary.")
    gatewayMcpAppendTool(tools, "gateway.control_ui.summary", "Read gateway control-ui runtime summary.")
    gatewayMcpAppendTool(tools, "gateway.control_ui.binding", "Read gateway control-ui server binding.")
    gatewayMcpAppendTool(tools, "gateway.control_ui.runtime", "Read gateway control-ui runtime envelope.")
    gatewayMcpAppendTool(tools, "gateway.control_ui.assets", "Read gateway control-ui asset/runtime paths.")
    gatewayMcpAppendTool(tools, "gateway.control_ui.stop", "Stop gateway control-ui runtime.")
    gatewayMcpAppendTool(tools, "gateway.control_ui.reload", "Reload gateway control-ui runtime.")
    gatewayMcpAppendTool(tools, "gateway.webchat.reload", "Reload gateway webchat runtime.")
    gatewayMcpAppendTool(tools, "gateway.probe", "Read gateway probe diagnostics.")
    gatewayMcpAppendTool(tools, "gateway.probe.actions", "Read gateway probe recommended actions.")
    gatewayMcpAppendTool(tools, "gateway.probe.remediation", "Read gateway probe remediation envelope.")
    gatewayMcpAppendTool(tools, "gateway.doctor.actions", "Read gateway doctor recommended actions.")
    gatewayMcpAppendTool(tools, "gateway.doctor.remediation", "Read gateway doctor remediation envelope.")
    gatewayMcpAppendTool(tools, "gateway.doctor", "Read gateway doctor diagnostics.")
    if (includeConfiguredMarker) {
        gatewayMcpAppendTool(tools, "mcp.configured", "MCP servers are configured in metis.json; use the CLI/runtime to enumerate loaded tools.")
    }
    result.put("tools", tools)
    result
}
