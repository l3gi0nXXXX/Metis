package metis.gateway.tools

import metis.core.{GatewaySubagentCommandRequest, gatewaySubagentCommandUsage, parseGatewaySubagentCommandLine}

import stdx.encoding.json.{JsonBool, JsonObject, JsonString}

private func subagentCommandSome(v: String): Option<String> {
    Some<String>(v)
}

private func subagentCommandErrorJson(req: GatewaySubagentCommandRequest): String {
    let out = JsonObject()
    out.put("ok", JsonBool(false))
    out.put("status", JsonString("error"))
    out.put("action", JsonString(req.action))
    out.put("error", JsonString(req.error))
    out.put("usage", JsonString(gatewaySubagentCommandUsage()))
    out.toJsonString()
}

public func gatewayHandleSubagentsCommandLine(raw: String): Option<String> {
    let req = parseGatewaySubagentCommandLine(raw)
    if (!req.recognized) {
        return None<String>
    }
    if (!req.ok) {
        return Some(subagentCommandErrorJson(req))
    }
    let toolset = GatewayManagedSessionsToolset()
    if (req.action == "spawn") {
        return Some(toolset.sessionsSpawnForCommand(
            req.message,
            None<String>,
            subagentCommandSome("subagent"),
            subagentCommandSome(req.agentId),
            None<String>,
            None<String>,
            None<String>,
            None<String>,
            None<Int64>,
            None<Int64>,
            None<Bool>,
            None<String>,
            None<String>,
            None<String>,
            None<String>
        ))
    }
    Some(toolset.subagentsForCommand(
        subagentCommandSome(req.action),
        if (req.target.isEmpty()) { None<String> } else { subagentCommandSome(req.target) },
        if (req.message.isEmpty()) { None<String> } else { subagentCommandSome(req.message) },
        None<Int64>
    ))
}
