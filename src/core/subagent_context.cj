package metis.core

import std.collection.ArrayList

public func gatewaySubagentNormalizeContextMode(contextMode: String): String {
    match (contextMode.trimAscii().toAsciiLower().replace("-", "_")) {
        case "with_context" | "context" | "recent" => "with_context"
        case "fork" | "full" | "full_context" => "fork"
        case "thread" | "same_thread" => "thread"
        case _ => "fresh"
    }
}

private func gatewaySubagentTrimContextHistory(parentHistory: String): String {
    let trimmed = parentHistory.trimAscii()
    if (trimmed.size > 16000) {
        trimmed[0..16000] + "\n[context truncated]"
    } else {
        trimmed
    }
}

public func gatewaySubagentBuildContextPrompt(
    basePrompt: String,
    contextMode: String,
    parentSessionKey: String,
    childSessionKey: String,
    parentHistory: String
): String {
    let mode = gatewaySubagentNormalizeContextMode(contextMode)
    let base = basePrompt.trimAscii()
    if (mode == "fresh") {
        return base
    }

    let history = gatewaySubagentTrimContextHistory(parentHistory)
    let lines = ArrayList<String>()
    lines.add(base)
    lines.add("")
    lines.add("## Parent Session Context")
    lines.add("Context mode: ${mode}")
    if (!parentSessionKey.trimAscii().isEmpty()) {
        lines.add("Parent session key: ${parentSessionKey.trimAscii()}")
    }
    if (!childSessionKey.trimAscii().isEmpty()) {
        lines.add("Child session key: ${childSessionKey.trimAscii()}")
    }
    if (mode == "with_context") {
        lines.add("Use this recent parent conversation only when it helps complete the task.")
    } else if (mode == "fork") {
        lines.add("Treat this as a fork of the available parent conversation. Preserve the parent context while completing only the assigned task.")
    } else {
        lines.add("This background run belongs to the same requester thread/session. Keep the parent/thread relationship in mind when summarizing results.")
    }
    lines.add("")
    lines.add("Parent conversation:")
    if (history.isEmpty()) {
        lines.add("(no parent conversation history available)")
    } else {
        lines.add(history)
    }
    String.join(lines.toArray(), delimiter: "\n")
}
