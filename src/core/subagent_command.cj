package metis.core

import std.collection.ArrayList

public class GatewaySubagentCommandRequest {
    public let recognized: Bool
    public let ok: Bool
    public let action: String
    public let agentId: String
    public let target: String
    public let message: String
    public let error: String

    public init(
        recognized!: Bool = false,
        ok!: Bool = false,
        action!: String = "",
        agentId!: String = "",
        target!: String = "",
        message!: String = "",
        error!: String = ""
    ) {
        this.recognized = recognized
        this.ok = ok
        this.action = action.trimAscii().toAsciiLower()
        this.agentId = agentId.trimAscii()
        this.target = target.trimAscii()
        this.message = message.trimAscii()
        this.error = error.trimAscii()
    }
}

public func gatewaySubagentCommandUsage(): String {
    "Usage: /subagents spawn <agentId> \"<task>\" | list [current|all|agent:<id>] | status <runId> | logs <runId> | poll <runId> | kill <runId> | steer <runId> \"<message>\" | send <runId> \"<message>\""
}

public func gatewaySubagentCommandExamples(): Array<String> {
    [
        "/subagents",
        "/subagents list all",
        "/subagents spawn explorer \"inspect the current implementation\"",
        "/subagents status <runId>",
        "/subagents logs <runId>",
        "/subagents kill <runId>",
        "/subagents send <runId> \"continue with tests\""
    ]
}

private func subagentCommandJoin(parts: Array<String>, start: Int64): String {
    if (start >= parts.size) {
        return ""
    }
    var s = parts[start]
    var i = start + 1
    while (i < parts.size) {
        s += " " + parts[i]
        i += 1
    }
    s.trimAscii()
}

public func gatewaySubagentCommandTokenize(line: String): Array<String> {
    let tokens = ArrayList<String>()
    var current = StringBuilder()
    var activeQuote: Rune = r'\0'
    var escaping = false
    for (ch in line.trimAscii().toRuneArray()) {
        if (escaping) {
            current.append(ch)
            escaping = false
            continue
        }
        if (ch == r'\\') {
            escaping = true
            continue
        }
        if (activeQuote != r'\0') {
            if (ch == activeQuote) {
                activeQuote = r'\0'
            } else {
                current.append(ch)
            }
            continue
        }
        if (ch == r'"' || ch == r'\'') {
            activeQuote = ch
            continue
        }
        if (ch == r' ' || ch == r'\t') {
            let t = current.toString().trimAscii()
            if (!t.isEmpty()) {
                tokens.add(t)
            }
            current = StringBuilder()
            continue
        }
        current.append(ch)
    }
    if (escaping) {
        current.append(r'\\')
    }
    let tail = current.toString().trimAscii()
    if (!tail.isEmpty()) {
        tokens.add(tail)
    }
    tokens.toArray()
}

public func parseGatewaySubagentCommandLine(raw: String): GatewaySubagentCommandRequest {
    let tokens = gatewaySubagentCommandTokenize(raw)
    if (tokens.size == 0) {
        return GatewaySubagentCommandRequest()
    }
    let head = tokens[0].trimAscii().toAsciiLower()
    if (head != "/subagents" && head != "subagents") {
        return GatewaySubagentCommandRequest()
    }
    if (tokens.size == 1) {
        return GatewaySubagentCommandRequest(recognized: true, ok: true, action: "list", target: "current")
    }
    let action = tokens[1].trimAscii().toAsciiLower()
    if (action == "help" || action == "-h" || action == "--help") {
        return GatewaySubagentCommandRequest(recognized: true, ok: true, action: "help")
    }
    if (action == "spawn") {
        if (tokens.size < 4) {
            return GatewaySubagentCommandRequest(recognized: true, action: action, error: "spawn requires <agentId> and <task>")
        }
        let task = subagentCommandJoin(tokens, 3)
        if (task.isEmpty()) {
            return GatewaySubagentCommandRequest(recognized: true, action: action, agentId: tokens[2], error: "spawn task must be non-empty")
        }
        return GatewaySubagentCommandRequest(recognized: true, ok: true, action: action, agentId: tokens[2], message: task)
    }
    if (action == "list") {
        return GatewaySubagentCommandRequest(
            recognized: true,
            ok: true,
            action: action,
            target: if (tokens.size >= 3) { tokens[2] } else { "current" }
        )
    }
    if (action == "status" || action == "logs" || action == "poll" || action == "kill") {
        if (tokens.size < 3) {
            return GatewaySubagentCommandRequest(recognized: true, action: action, error: "${action} requires <runId>")
        }
        return GatewaySubagentCommandRequest(recognized: true, ok: true, action: action, target: tokens[2])
    }
    if (action == "steer" || action == "send") {
        if (tokens.size < 4) {
            return GatewaySubagentCommandRequest(recognized: true, action: action, error: "${action} requires <runId> and <message>")
        }
        let msg = subagentCommandJoin(tokens, 3)
        if (msg.isEmpty()) {
            return GatewaySubagentCommandRequest(recognized: true, action: action, target: tokens[2], error: "${action} message must be non-empty")
        }
        return GatewaySubagentCommandRequest(recognized: true, ok: true, action: action, target: tokens[2], message: msg)
    }
    GatewaySubagentCommandRequest(recognized: true, action: action, error: "unknown subagents action: ${action}")
}
