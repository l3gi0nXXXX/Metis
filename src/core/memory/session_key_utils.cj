package metis.core.memory

import std.collection.ArrayList

public class ParsedAgentSessionKey {
    public let agentId: String
    public let rest: String

    public init(agentId: String, rest: String) {
        this.agentId = agentId
        this.rest = rest
    }
}

public func parseAgentSessionKey(sessionKey: Option<String>): Option<ParsedAgentSessionKey> {
    let raw = match (sessionKey) {
        case Some(value) => value.trimAscii().toAsciiLower()
        case None => ""
    }
    if (raw.isEmpty()) {
        return None
    }
    let parts = raw.split(":")
    let filtered = ArrayList<String>()
    for (part in parts) {
        let trimmed = part.trimAscii()
        if (!trimmed.isEmpty()) {
            filtered.add(trimmed)
        }
    }
    let normalized = filtered.toArray()
    if (normalized.size < 3) {
        return None
    }
    if (normalized[0] != "agent") {
        return None
    }
    let agentId = normalized[1].trimAscii()
    if (agentId.isEmpty()) {
        return None
    }
    let restParts = ArrayList<String>()
    for (i in 2..normalized.size) {
        restParts.add(normalized[i])
    }
    let rest = String.join(restParts.toArray(), delimiter: ":").trimAscii()
    if (rest.isEmpty()) {
        return None
    }
    Some(ParsedAgentSessionKey(agentId, rest))
}

public func isSubagentSessionKey(sessionKey: Option<String>): Bool {
    let raw = match (sessionKey) {
        case Some(value) => value.trimAscii().toAsciiLower()
        case None => ""
    }
    if (raw.isEmpty()) {
        return false
    }
    if (raw.startsWith("subagent:")) {
        return true
    }
    match (parseAgentSessionKey(sessionKey)) {
        case Some(parsed) => parsed.rest.trimAscii().toAsciiLower().startsWith("subagent:")
        case None => false
    }
}
