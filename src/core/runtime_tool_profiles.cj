package metis.core

import std.collection.ArrayList

public func gatewayMainRuntimeRequiredToolNames(): Array<String> {
    [
        "weather",
        "listDirectory",
        "fileRead",
        "memory_search",
        "memory_get",
        "shellExecute",
        "update_plan",
        "sessions_list",
        "sessions_history",
        "sessions_send",
        "session_status"
    ]
}

public func gatewayMainRuntimeExtendedToolNames(): Array<String> {
    [
        "process",
        "gateway",
        "cron",
        "message",
        "sessions_spawn",
        "subagents"
    ]
}

public func runtimeToolNamesContain(toolNames: Array<String>, expected: String): Bool {
    let needle = expected.trimAscii().toAsciiLower()
    for (name in toolNames) {
        if (name.trimAscii().toAsciiLower() == needle) {
            return true
        }
    }
    false
}

public func runtimeToolNamesContainAll(toolNames: Array<String>, expectedNames: Array<String>): Bool {
    for (expected in expectedNames) {
        if (!runtimeToolNamesContain(toolNames, expected)) {
            return false
        }
    }
    true
}

public func missingRuntimeToolNames(toolNames: Array<String>, expectedNames: Array<String>): Array<String> {
    let missing = ArrayList<String>()
    for (expected in expectedNames) {
        if (!runtimeToolNamesContain(toolNames, expected)) {
            missing.add(expected)
        }
    }
    missing.toArray()
}
