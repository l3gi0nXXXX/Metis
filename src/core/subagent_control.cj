package metis.core

import stdx.encoding.json.JsonObject

public func gatewaySubagentControllerCanAccessRun(record: JsonObject, currentSessionKey: String, privileged: Bool): Bool {
    if (privileged) {
        return true
    }
    let current = currentSessionKey.trimAscii()
    if (current.isEmpty()) {
        return true
    }
    current == gatewaySubagentRunRecordString(record, "requesterSessionKey") ||
        current == gatewaySubagentRunRecordString(record, "parentSessionKey") ||
        current == gatewaySubagentRunRecordString(record, "sessionKey")
}

public func gatewaySubagentRunMatchesControlFilter(
    record: JsonObject,
    filter: String,
    currentSessionKey: String,
    privileged: Bool
): Bool {
    let f = filter.trimAscii()
    if (f.isEmpty() || f == "current") {
        if (currentSessionKey.trimAscii().isEmpty() || privileged) {
            return true
        }
        return gatewaySubagentControllerCanAccessRun(record, currentSessionKey, privileged)
    }
    if (f == "all" || f == "*") {
        return gatewaySubagentControllerCanAccessRun(record, currentSessionKey, privileged)
    }
    let normalized = if (f.startsWith("agent:")) { f["agent:".size..].trimAscii() } else { f }
    if (gatewaySubagentRunRecordString(record, "agentId") != normalized) {
        return false
    }
    gatewaySubagentControllerCanAccessRun(record, currentSessionKey, privileged)
}
