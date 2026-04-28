package metis.gateway.security

public let GATEWAY_SCOPE_READ = "read"
public let GATEWAY_SCOPE_WRITE = "write"
public let GATEWAY_SCOPE_ADMIN = "admin"
public let GATEWAY_SCOPE_APPROVALS = "approvals"
public let GATEWAY_SCOPE_PAIRING = "pairing"
public let GATEWAY_SCOPE_TALK_SECRETS = "talk-secrets"

public func gatewayCliDefaultOperatorScopes(): Array<String> {
    [GATEWAY_SCOPE_ADMIN, GATEWAY_SCOPE_READ, GATEWAY_SCOPE_WRITE, GATEWAY_SCOPE_APPROVALS, GATEWAY_SCOPE_PAIRING, GATEWAY_SCOPE_TALK_SECRETS]
}

public func gatewayDefaultOperatorScopesForClientMode(mode: String): Array<String> {
    let normalized = mode.trimAscii().toAsciiLower()
    if (normalized == "local-cli" || normalized == "agent-tool" || normalized == "local-rpc") {
        return gatewayCliDefaultOperatorScopes()
    }
    [GATEWAY_SCOPE_READ]
}

public func gatewayResolveRequiredOperatorScope(method: String): String {
    let m = method.trimAscii().toAsciiLower()
    if (m == "status" || m == "health" || m == "readiness" || m == "connect.status" ||
        m == "config.get" || m == "config.schema.lookup" ||
        m == "http.status" || m == "control_ui.status" || m == "control-ui.status" || m == "webchat.status" ||
        m == "discover" || m == "sessions.list" || m == "sessions.path" ||
        m == "subagents.list" || m == "subagents.status" || m == "subagents.poll" || m == "subagents.logs" ||
        m == "cron.list" || m == "cron.path" || m == "cron.help" || m == "cron.status" ||
        m == "channels.status" || m == "channels.list" || m == "channels.runtime" || m == "channels.manager" ||
        m == "plugins.status" || m == "plugins.list" || m == "plugins.runtime" || m == "plugins.manager" ||
        m == "plugins.actions" || m == "plugins.approvals" || m == "plugins.package_state" || m == "plugins.setup" ||
        m == "models.status" || m == "models.list" || m == "logs.status" || m == "logs.list" || m == "doctor" ||
        m == "nodes.status" || m == "devices.status" || m == "push.status" ||
        m == "usage-cost" || m == "secrets.status" || m == "canvas.status" || m == "talk.status" ||
        m == "http.models" || m == "http.mcp") {
        return GATEWAY_SCOPE_READ
    }
    if (m == "http.chat.completions" || m == "http.responses" || m == "http.embeddings") {
        return GATEWAY_SCOPE_WRITE
    }
    GATEWAY_SCOPE_ADMIN
}

public func gatewayAuthorizeOperatorScopesForMethod(method: String, scopes: Array<String>): (Bool, String) {
    let required = gatewayResolveRequiredOperatorScope(method)
    if (scopes.contains(GATEWAY_SCOPE_ADMIN)) {
        return (true, "")
    }
    if (required == GATEWAY_SCOPE_READ) {
        if (scopes.contains(GATEWAY_SCOPE_READ) || scopes.contains(GATEWAY_SCOPE_WRITE)) {
            return (true, "")
        }
        return (false, GATEWAY_SCOPE_READ)
    }
    if (scopes.contains(required)) {
        return (true, "")
    }
    (false, required)
}
