package metis.gateway.core

import std.collection.ArrayList

public class GatewayTelegramNativeCommandSpec {
    public let command: String
    public let aliases: Array<String>
    public let description: String
    public let category: String
    public let auth: String
    public let status: String
    public let args: Array<String>
    public let argsMenuChoices: Array<String>
    public let openclawEvidence: String
    public let notApplicableReason: String

    public init(
        command: String,
        description!: String,
        category!: String,
        auth!: String = "authorized",
        status!: String = "implemented",
        aliases!: Array<String> = [],
        args!: Array<String> = [],
        argsMenuChoices!: Array<String> = [],
        openclawEvidence!: String = "openclaw/src/auto-reply/commands-registry.shared.ts:116-830",
        notApplicableReason!: String = ""
    ) {
        this.command = command
        this.aliases = aliases
        this.description = description
        this.category = category
        this.auth = auth
        this.status = status
        this.args = args
        this.argsMenuChoices = argsMenuChoices
        this.openclawEvidence = openclawEvidence
        this.notApplicableReason = notApplicableReason
    }
}

private func spec(
    command: String,
    description: String,
    category: String,
    auth!: String = "authorized",
    status!: String = "implemented",
    aliases!: Array<String> = [],
    args!: Array<String> = [],
    menu!: Array<String> = [],
    evidence!: String = "openclaw/src/auto-reply/commands-registry.shared.ts:116-830",
    reason!: String = ""
): GatewayTelegramNativeCommandSpec {
    GatewayTelegramNativeCommandSpec(
        command,
        description: description,
        category: category,
        auth: auth,
        status: status,
        aliases: aliases,
        args: args,
        argsMenuChoices: menu,
        openclawEvidence: evidence,
        notApplicableReason: reason
    )
}

public func gatewayTelegramNativeCommandCatalog(): Array<GatewayTelegramNativeCommandSpec> {
    [
        spec("help", "Show available commands.", "status"),
        spec("commands", "List all slash commands.", "status"),
        spec("tools", "List available runtime tools.", "status", args: ["mode"], menu: ["compact", "verbose"]),
        spec("skill", "Run a Metis skill by name.", "tools", auth: "operator", args: ["name", "input"]),
        spec("status", "Show current status.", "status"),
        spec("tasks", "List background tasks for this session.", "status"),
        spec("allowlist", "OpenClaw text allowlist management is not a Metis Telegram native surface.", "management", status: "stub", reason: "Metis Telegram authorization uses gateway.telegram allowFrom/groupAllowFrom and pairing stores."),
        spec("approve", "Approve or deny exec requests.", "management", auth: "approval", args: ["id", "decision"]),
        spec("context", "Explain how context is built and used.", "status"),
        spec("btw", "Ask a side question without changing future session context.", "tools", auth: "operator", args: ["question"]),
        spec("export-session", "Export current session transcript.", "status", aliases: ["export"], args: ["path"]),
        spec("tts", "Control text-to-speech.", "media", auth: "operator", args: ["action", "value"], menu: ["status", "on", "off", "provider", "limit", "summary", "audio", "help"]),
        spec("whoami", "Show your sender id.", "status", aliases: ["id"]),
        spec("session", "Manage session-level settings.", "session", args: ["action", "value"], menu: ["idle", "max-age"]),
        spec("sessions", "List or inspect persisted Metis Gateway sessions.", "session", args: ["action", "target"], menu: ["list", "path", "preview"], evidence: "Metis Gateway native extension"),
        spec("subagents", "List, kill, log, spawn, or steer subagent runs.", "management", args: ["action", "target", "value"], menu: ["list", "kill", "log", "info", "send", "steer", "spawn"]),
        spec("approvals", "Inspect Metis Gateway approvals.", "management", evidence: "Metis Gateway native extension"),
        spec("acp", "ACP is not a Metis runtime in this Gateway build.", "management", status: "not_applicable", args: ["action", "value"], menu: ["status", "sessions", "doctor", "help"], reason: "Metis uses Gateway sessions and subagents instead of OpenClaw ACP sessions."),
        spec("focus", "Bind this Telegram conversation to a session target.", "management", args: ["target"]),
        spec("unfocus", "Remove this Telegram conversation binding.", "management"),
        spec("agents", "List thread-bound agents for this session.", "management"),
        spec("kill", "Kill a running subagent.", "management", auth: "operator", args: ["target"], menu: ["all"]),
        spec("steer", "Send guidance to a running subagent.", "management", auth: "operator", aliases: ["tell"], args: ["target", "message"]),
        spec("config", "Show or mutate Metis config values.", "management", auth: "operator", args: ["action", "path", "value"], menu: ["show", "get", "set", "unset"]),
        spec("mcp", "Show or mutate MCP server config.", "management", auth: "operator", args: ["action", "path", "value"], menu: ["show", "get", "set", "unset"]),
        spec("plugins", "List, show, enable, or disable plugins.", "management", auth: "operator", aliases: ["plugin"], args: ["action", "path"], menu: ["list", "show", "enable", "disable"]),
        spec("debug", "Show or set runtime debug overrides.", "management", auth: "operator", args: ["action", "path", "value"], menu: ["show", "set", "unset", "reset"]),
        spec("usage", "Usage footer or cost summary.", "options", args: ["mode"], menu: ["off", "tokens", "full", "cost"]),
        spec("stop", "Stop the current run.", "session", auth: "operator"),
        spec("restart", "Restart Gateway runtime.", "tools", auth: "operator"),
        spec("activation", "Set group activation mode.", "management", args: ["mode"], menu: ["mention", "always"]),
        spec("pair", "Inspect Telegram pairing flow.", "management", evidence: "Metis Gateway native extension"),
        spec("send", "Set send policy.", "management", auth: "operator", args: ["mode"], menu: ["on", "off", "inherit"]),
        spec("reset", "Reset the current session.", "session", auth: "operator"),
        spec("new", "Start a new session boundary.", "session", auth: "operator"),
        spec("compact", "Compact the session transcript.", "session", auth: "operator", args: ["instructions"]),
        spec("think", "Set thinking level.", "options", args: ["level"], menu: ["off", "minimal", "low", "medium", "high", "xhigh"], aliases: ["thinking", "t"]),
        spec("verbose", "Toggle verbose mode.", "options", args: ["mode"], menu: ["on", "off"], aliases: ["v"]),
        spec("fast", "Toggle fast mode.", "options", args: ["mode"], menu: ["status", "on", "off"]),
        spec("reasoning", "Toggle reasoning visibility.", "options", args: ["mode"], menu: ["on", "off", "stream"], aliases: ["reason"]),
        spec("elevated", "Toggle elevated mode.", "options", auth: "operator", args: ["mode"], menu: ["on", "off", "ask", "full"], aliases: ["elev"]),
        spec("exec", "Set exec defaults for this session.", "options", auth: "operator", args: ["host", "security", "ask", "node"], menu: ["sandbox", "gateway", "node"]),
        spec("model", "Show or set the model.", "options", args: ["model"]),
        spec("models", "List model providers or provider models.", "options"),
        spec("queue", "Adjust queue settings.", "options", auth: "operator", args: ["mode", "debounce", "cap", "drop"], menu: ["steer", "interrupt", "followup", "collect", "steer-backlog"]),
        spec("bash", "Run host shell commands through approval.", "tools", auth: "approval", args: ["command"])
    ]
}

public func gatewayFindTelegramNativeCommandSpec(raw: String): Option<GatewayTelegramNativeCommandSpec> {
    let trimmed = raw.trimAscii()
    let normalized = if (trimmed.startsWith("/")) { trimmed[1..].toAsciiLower() } else { trimmed.toAsciiLower() }
    if (normalized.isEmpty()) {
        return None
    }
    for (entry in gatewayTelegramNativeCommandCatalog()) {
        if (entry.command == normalized) {
            return Some(entry)
        }
        for (alias in entry.aliases) {
            if (alias.trimAscii().toAsciiLower() == normalized) {
                return Some(entry)
            }
        }
    }
    None
}

public func gatewayTelegramNativeCommandMenuRows(): Array<(String, String)> {
    let rows = ArrayList<(String, String)>()
    for (entry in gatewayTelegramNativeCommandCatalog()) {
        if (entry.status != "not_applicable") {
            rows.add((entry.command, entry.description))
        }
    }
    rows.toArray()
}
