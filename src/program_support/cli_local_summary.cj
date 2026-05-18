package metis.program_support

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject, JsonValue}

private func localJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func localJsonArraySummary(value: JsonValue): String {
    let arr = try {
        value.asArray()
    } catch (_e: Exception) {
        return ""
    }
    if (arr.size() == 0) {
        return "(none)"
    }
    let items = ArrayList<String>()
    var allStrings = true
    for (idx in 0..arr.size()) {
        try {
            items.add(arr[idx].asString().getValue())
        } catch (_e: Exception) {
            allStrings = false
        }
    }
    if (allStrings) {
        return String.join(items.toArray(), delimiter: ", ")
    }
    return "${arr.size()} item(s)"
}

private func localJsonScalarSummary(value: JsonValue): String {
    try {
        return value.asString().getValue()
    } catch (_e: Exception) {
        ()
    }
    try {
        return if (value.asBool().getValue()) { "true" } else { "false" }
    } catch (_e: Exception) {
        ()
    }
    try {
        return "${value.asInt().getValue()}"
    } catch (_e: Exception) {
        ()
    }
    let arrayText = localJsonArraySummary(value)
    if (!arrayText.isEmpty()) {
        return arrayText
    }
    return "available with --json"
}

private func localSummaryKnownField(key: String): Bool {
    key == "kind" ||
    key == "command" ||
    key == "subcommand" ||
    key == "status" ||
    key == "nextSteps" ||
    key == "modelConfig" ||
    key == "modelRuntime" ||
    key == "runtimeState" ||
    key == "modelSelection" ||
    key == "authChoices" ||
    key == "authChoiceGroups" ||
    key == "providers" ||
    key == "pending" ||
    key == "approvedSenders" ||
    key == "code"
}

private func localFieldLabel(key: String): String {
    if (key == "configPath") { return "Config path" }
    if (key == "logsDir") { return "Logs dir" }
    if (key == "storeRoot") { return "Store root" }
    if (key == "accountId") { return "Account" }
    if (key == "currentModel") { return "Current model" }
    if (key == "availableProviders") { return "Available providers" }
    if (key == "rootRemoval") { return "Would remove root" }
    if (key == "pendingCount") { return "Pending" }
    if (key == "approvedCount") { return "Approved senders" }
    if (key == "approved") { return "Approved" }
    if (key == "dispatchMode") { return "Dispatch mode" }
    if (key == "primaryPath") { return "Primary path" }
    return key
}

private func localAppendField(lines: ArrayList<String>, obj: JsonObject, key: String): Unit {
    match (obj.get(key)) {
        case Some(value) =>
            let text = localJsonScalarSummary(value)
            if (!text.isEmpty()) {
                lines.add("  ${localFieldLabel(key)}: ${text}")
            }
        case None => ()
    }
}

public func programSupportRenderLocalCommandSummary(obj: JsonObject): String {
    let kind = localJsonString(obj, "kind")
    let command = if (kind.isEmpty()) { localJsonString(obj, "command") } else { kind }
    let sub = localJsonString(obj, "subcommand")
    let mode = localJsonString(obj, "mode")
    let action = localJsonString(obj, "action")
    let detail = if (!sub.isEmpty()) {
        sub
    } else if (!mode.isEmpty()) {
        mode
    } else {
        action
    }
    let title = if (detail.isEmpty()) { "Metis ${command}" } else { "Metis ${command} ${detail}" }
    let lines = ArrayList<String>()
    lines.add(title)

    let orderedFields = [
        "surface", "mode", "action", "field", "key", "value", "provider", "currentModel", "resolved",
        "workspace", "home", "path", "configPath", "logsDir", "storeRoot", "channel", "accountId",
        "exists", "enabled", "entrypoint", "profile", "preview", "url", "primaryPath", "query",
        "target", "source", "dispatchMode", "model", "pendingCount", "approvedCount", "rootRemoval",
        "availableProviders", "recommended"
    ]
    for (key in orderedFields) {
        localAppendField(lines, obj, key)
    }
    for ((key, value) in obj.getFields()) {
        if (localSummaryKnownField(key)) {
            continue
        }
        var alreadyPrinted = false
        for (known in orderedFields) {
            if (known == key) {
                alreadyPrinted = true
            }
        }
        if (!alreadyPrinted) {
            let text = localJsonScalarSummary(value)
            if (!text.isEmpty()) {
                lines.add("  ${localFieldLabel(key)}: ${text}")
            }
        }
    }
    if (obj.get("modelConfig").isSome() || obj.get("modelRuntime").isSome() || obj.get("runtimeState").isSome() || obj.get("modelSelection").isSome()) {
        lines.add("  Model details: available with --json")
    }
    if (obj.get("providers").isSome() || obj.get("authChoices").isSome() || obj.get("authChoiceGroups").isSome()) {
        lines.add("  Catalog details: available with --json")
    }
    if (obj.get("pending").isSome() || obj.get("approvedSenders").isSome()) {
        lines.add("  Pairing details: codes and sender records are hidden by default; use --json for machine output.")
    }
    match (obj.get("nextSteps")) {
        case Some(value) =>
            let arr = try { value.asArray() } catch (_e: Exception) { JsonArray([]) }
            if (arr.size() > 0) {
                lines.add("Next steps:")
                for (idx in 0..arr.size()) {
                    try {
                        lines.add("  - ${arr[idx].asString().getValue()}")
                    } catch (_e: Exception) {
                        ()
                    }
                }
            }
        case None => ()
    }
    lines.add("Machine output: rerun with --json.")
    String.join(lines.toArray(), delimiter: "\n")
}
