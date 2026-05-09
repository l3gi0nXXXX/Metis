package metis.gateway.runtime

import std.collection.ArrayList
import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

import metis.io.PrintUtils

private func cliJsonString(obj: JsonObject, key: String, defaultValue!: String = ""): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func cliJsonBool(obj: JsonObject, key: String, defaultValue!: Bool = false): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func cliJsonInt(obj: JsonObject, key: String, defaultValue!: Int64 = 0): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { return Int64.parse(v.asString().getValue().trimAscii()) } catch (_: Exception) { () }
            try { return Int64.parse(v.toJsonString()) } catch (_: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func cliJsonObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func cliJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func cliJsonNestedObject(root: JsonObject, keys: Array<String>): JsonObject {
    var current = root
    for (key in keys) {
        let next = cliJsonObject(current, key)
        if (next.toJsonString() == "{}") {
            return next
        }
        current = next
    }
    current
}

private func cliOneLine(value: String, maxLen!: Int64 = 140): String {
    let flat = value.replace("\n", " ").replace("\r", " ").trimAscii()
    if (flat.size <= maxLen) {
        return flat
    }
    flat[0..maxLen] + "..."
}

private func cliYesNo(v: Bool): String {
    if (v) { "yes" } else { "no" }
}

private func cliRenderSubagentRow(row: JsonObject): String {
    let runId = cliJsonString(row, "runId")
    let agent = cliJsonString(row, "agentId")
    let status = cliJsonString(row, "effectiveState", defaultValue: cliJsonString(row, "status"))
    let runtime = cliJsonString(row, "runtime")
    let session = cliJsonString(row, "sessionKey")
    let notice = cliJsonString(row, "noticeStatus")
    var line = "  - ${if (runId.isEmpty()) { session } else { runId }}"
    if (!agent.isEmpty()) { line += "  agent=${agent}" }
    if (!status.isEmpty()) { line += "  state=${status}" }
    if (!runtime.isEmpty()) { line += "  runtime=${runtime}" }
    if (!notice.isEmpty()) { line += "  notice=${notice}" }
    if (!session.isEmpty() && session != runId) { line += "  session=${session}" }
    line
}

private func cliRenderSubagents(obj: JsonObject): Option<String> {
    let action = cliJsonString(obj, "action")
    if (action.isEmpty()) {
        return None<String>
    }
    let lines = ArrayList<String>()
    if (!cliJsonBool(obj, "ok", defaultValue: true)) {
        lines.add("Subagents: failed")
        let err = cliJsonString(obj, "error", defaultValue: cliJsonString(obj, "message"))
        if (!err.isEmpty()) { lines.add("Reason: ${err}") }
        let usage = cliJsonString(obj, "usage")
        if (!usage.isEmpty()) {
            lines.add(if (usage.startsWith("Usage:")) { usage } else { "Usage: ${usage}" })
        }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (action == "help") {
        lines.add("Subagents commands")
        let usage = cliJsonString(obj, "usage")
        if (!usage.isEmpty()) {
            lines.add(if (usage.startsWith("Usage:")) { usage } else { "Usage: ${usage}" })
        }
        let examples = cliJsonArray(obj, "examples")
        if (examples.size() > 0) {
            lines.add("Examples:")
            for (i in 0..examples.size()) {
                let text = try { examples[i].asString().getValue() } catch (_: Exception) { "" }
                if (!text.isEmpty()) { lines.add("  - ${text}") }
            }
        }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (action == "list") {
        lines.add("Subagents")
        lines.add(
            "Filter: ${cliJsonString(obj, "filter", defaultValue: "current")}  total=${cliJsonInt(obj, "total")} active=${cliJsonInt(obj, "activeCount")} terminal=${cliJsonInt(obj, "terminalCount")} stale=${cliJsonInt(obj, "staleCount")}"
        )
        let rows = cliJsonArray(obj, "sessions")
        if (rows.size() == 0) {
            lines.add("Runs: none")
        } else {
            lines.add("Runs:")
            let limit = if (rows.size() > 12) { 12 } else { rows.size() }
            for (i in 0..limit) {
                try {
                    lines.add(cliRenderSubagentRow(rows[i].asObject()))
                } catch (_: Exception) {
                    ()
                }
            }
            if (rows.size() > limit) {
                lines.add("  ... ${rows.size() - limit} more. Use logs/status with a runId for details.")
            }
        }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (action == "logs") {
        lines.add("Subagent logs")
        lines.add("Run: ${cliJsonString(obj, "runId")}  state=${cliJsonString(obj, "effectiveState", defaultValue: cliJsonString(obj, "status"))}")
        let transcript = cliJsonString(obj, "transcriptPath")
        if (!transcript.isEmpty()) { lines.add("Transcript: ${transcript}") }
        let logs = cliJsonString(obj, "logs")
        if (!logs.isEmpty()) {
            lines.add("")
            lines.add(cliOneLine(logs, maxLen: 4000))
        }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (action == "status" || action == "poll") {
        lines.add("Subagent ${action}")
        lines.add("Run: ${cliJsonString(obj, "runId")}")
        lines.add("State: ${cliJsonString(obj, "effectiveState", defaultValue: cliJsonString(obj, "status"))}")
        let agent = cliJsonString(obj, "agentId")
        if (!agent.isEmpty()) { lines.add("Agent: ${agent}") }
        let session = cliJsonString(obj, "sessionKey")
        if (!session.isEmpty()) { lines.add("Session: ${session}") }
        let transcript = cliJsonString(obj, "transcriptPath")
        if (!transcript.isEmpty()) { lines.add("Transcript: ${transcript}") }
        lines.add("Live future: ${cliYesNo(cliJsonBool(obj, "hasLiveFuture"))}  live process: ${cliYesNo(cliJsonBool(obj, "hasLiveProcess"))}")
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (action == "spawn") {
        lines.add("Subagent spawn: ${cliJsonString(obj, "status")}")
        lines.add("Run: ${cliJsonString(obj, "runId")}")
        lines.add("Agent: ${cliJsonString(obj, "agentId")}")
        lines.add("Session: ${cliJsonString(obj, "sessionKey")}")
        let text = cliJsonString(obj, "text", defaultValue: cliJsonString(obj, "message"))
        if (!text.isEmpty()) { lines.add("Message: ${text}") }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (action == "kill" || action == "cleanup" || action == "steer" || action == "send") {
        lines.add("Subagent ${action}: ${cliJsonString(obj, "status")}")
        let runId = cliJsonString(obj, "runId")
        if (!runId.isEmpty()) { lines.add("Run: ${runId}") }
        let target = cliJsonString(obj, "target")
        if (!target.isEmpty()) { lines.add("Target: ${target}") }
        let count = cliJsonInt(obj, "count", defaultValue: -1)
        if (count >= 0) { lines.add("Affected: ${count}") }
        let text = cliJsonString(obj, "text", defaultValue: cliJsonString(obj, "message"))
        if (!text.isEmpty()) { lines.add("Message: ${text}") }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    None<String>
}

private func cliRenderDiscoverResult(result: JsonObject): Option<String> {
    let channels = cliJsonArray(result, "channels")
    if (channels.size() == 0) {
        return None<String>
    }
    let lines = ArrayList<String>()
    lines.add("Gateway channels")
    lines.add("Meaning: enabled=config switch, configured=credentials present, mode=transport/runtime mode.")
    for (i in 0..channels.size()) {
        try {
            let ch = channels[i].asObject()
            var id = cliJsonString(ch, "id", defaultValue: cliJsonString(ch, "pluginId"))
            if (id.isEmpty() && cliJsonString(ch, "mode") == "polling") {
                let network = cliJsonObject(ch, "network")
                if (cliJsonString(network, "apiRoot").contains("telegram")) {
                    id = "telegram"
                }
            }
            if (id.isEmpty()) {
                continue
            }
            let mode = cliJsonString(ch, "mode", defaultValue: "-")
            lines.add(
                "  - ${id}: enabled=${cliJsonBool(ch, "enabled")} configured=${cliJsonBool(ch, "configured")} mode=${mode}"
            )
            if (id == "telegram") {
                let media = cliJsonObject(ch, "media")
                let network = cliJsonObject(ch, "network")
                lines.add("    telegram media: download=${cliJsonBool(media, "downloadEnabled")} local-send=${cliJsonBool(media, "outboundAllowLocalPath")} url-send=${cliJsonBool(media, "outboundAllowUrl")}")
                lines.add("    telegram network: apiRoot=${cliJsonString(network, "apiRoot")} proxy=${cliJsonBool(network, "proxyConfigured")}")
            }
        } catch (_: Exception) {
            ()
        }
    }
    let plugins = cliJsonArray(result, "plugins")
    lines.add("External plugins: ${plugins.size()}")
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderChannelsRuntime(result: JsonObject): Option<String> {
    let accounts = cliJsonArray(result, "accounts")
    if (accounts.size() == 0) {
        let runtime = cliJsonObject(result, "runtime")
        let nested = cliJsonArray(runtime, "accounts")
        if (nested.size() == 0) {
            return None<String>
        }
    }
    let rows = if (accounts.size() > 0) { accounts } else { cliJsonArray(cliJsonObject(result, "runtime"), "accounts") }
    let lines = ArrayList<String>()
    let channelId = cliJsonString(result, "channelId", defaultValue: "all")
    lines.add("Channel runtime: ${channelId}")
    lines.add("Meaning: running=live adapter process/task, phase=lifecycle phase, failures=send/poll/start failures.")
    for (i in 0..rows.size()) {
        try {
            let row = rows[i].asObject()
            lines.add(
                "  - ${cliJsonString(row, "channelId")}/${cliJsonString(row, "accountId")}: running=${cliJsonBool(row, "running")} phase=${cliJsonString(row, "phase")} pull=${cliJsonInt(row, "pullCount")} inbound=${cliJsonInt(row, "inboundCount")} sendOk=${cliJsonInt(row, "sendSuccessCount")} sendFail=${cliJsonInt(row, "sendFailureCount")}"
            )
            let err = cliJsonString(row, "lastError")
            if (!err.isEmpty()) { lines.add("    lastError: ${cliOneLine(err)}") }
        } catch (_: Exception) {
            ()
        }
    }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderChannelsHealth(result: JsonObject): Option<String> {
    let channels = cliJsonArray(cliJsonObject(result, "channels"), "items")
    if (channels.size() == 0) {
        return cliRenderChannelsRuntime(result)
    }
    let lines = ArrayList<String>()
    lines.add("Channel health")
    lines.add("Meaning: policy=routing readiness, binding=account binding, probe=health probe status.")
    for (i in 0..channels.size()) {
        try {
            let item = channels[i].asObject()
            let status = cliJsonObject(item, "status")
            let channel = cliJsonObject(status, "channel")
            let probe = cliJsonObject(status, "probe")
            let id = cliJsonString(channel, "id", defaultValue: cliJsonString(item, "id", defaultValue: cliJsonString(status, "channelId")))
            lines.add(
                "  - ${id}: enabled=${cliJsonBool(status, "enabled")} configured=${cliJsonBool(status, "configured")} policy=${cliJsonString(status, "policyState")} binding=${cliJsonString(status, "bindingState")} probe=${cliJsonString(probe, "status")}"
            )
        } catch (_: Exception) {
            ()
        }
    }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderChannelGet(result: JsonObject): Option<String> {
    let channel = cliJsonObject(result, "channel")
    if (channel.toJsonString() == "{}") {
        return None<String>
    }
    var id = cliJsonString(channel, "id", defaultValue: cliJsonString(channel, "pluginId"))
    if (id.isEmpty() && cliJsonString(channel, "mode") == "polling") {
        id = "telegram"
    }
    let lines = ArrayList<String>()
    lines.add("Channel: ${if (id.isEmpty()) { "unknown" } else { id }}")
    lines.add("Enabled: ${cliJsonBool(channel, "enabled")}  configured=${cliJsonBool(channel, "configured")}  mode=${cliJsonString(channel, "mode", defaultValue: "-")}")
    let network = cliJsonObject(channel, "network")
    if (network.toJsonString() != "{}") {
        lines.add("Network: apiRoot=${cliJsonString(network, "apiRoot")} proxy=${cliJsonBool(network, "proxyConfigured")} envProxy=${cliJsonBool(network, "envProxyEnabled")}")
    }
    let media = cliJsonObject(channel, "media")
    if (media.toJsonString() != "{}") {
        lines.add("Media: download=${cliJsonBool(media, "downloadEnabled")} maxBytes=${cliJsonInt(media, "mediaMaxBytes")} localSend=${cliJsonBool(media, "outboundAllowLocalPath")} urlSend=${cliJsonBool(media, "outboundAllowUrl")}")
    }
    let directory = cliJsonObject(channel, "directory")
    if (directory.toJsonString() != "{}") {
        lines.add("Directory targets: ${cliJsonInt(directory, "rowCount")}")
    }
    let actions = cliJsonObject(channel, "actions")
    if (actions.toJsonString() != "{}") {
        let enabled = ArrayList<String>()
        for (name in ["sendMessage", "photo", "document", "audio", "voice", "video", "reactions", "inlineKeyboard", "callbackQuery"]) {
            if (cliJsonBool(actions, name)) {
                enabled.add(name)
            }
        }
        lines.add("Enabled actions: ${if (enabled.size == 0) { "none" } else { String.join(enabled.toArray(), delimiter: ", ") }}")
    }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderChannelsAudit(result: JsonObject): Option<String> {
    let audit = cliJsonObject(result, "audit")
    if (audit.toJsonString() == "{}") {
        return None<String>
    }
    let summary = cliJsonObject(audit, "summary")
    let lines = ArrayList<String>()
    lines.add("Channel audit")
    lines.add("Focus: ${cliJsonString(summary, "focus", defaultValue: "all")}  acceptance=${cliJsonInt(summary, "acceptanceCount")} remaining=${cliJsonInt(summary, "remainingCount")}")
    let diagnostics = cliJsonObject(summary, "telegramDiagnostics")
    if (diagnostics.toJsonString() != "{}") {
        lines.add("Telegram diagnostics: healthy=${cliJsonBool(diagnostics, "healthy")} findings=${cliJsonInt(diagnostics, "findingCount")} warnings=${cliJsonInt(diagnostics, "warningCount")} failed=${cliJsonInt(diagnostics, "failedCount")}")
    }
    let acceptance = cliJsonArray(audit, "acceptance")
    if (acceptance.size() > 0) {
        lines.add("Acceptance:")
        let limit = if (acceptance.size() > 8) { 8 } else { acceptance.size() }
        for (i in 0..limit) {
            let text = try { acceptance[i].asString().getValue() } catch (_: Exception) { "" }
            if (!text.isEmpty()) { lines.add("  - ${text}") }
        }
        if (acceptance.size() > limit) {
            lines.add("  ... ${acceptance.size() - limit} more")
        }
    }
    let remaining = cliJsonArray(audit, "remaining")
    if (remaining.size() > 0) {
        lines.add("Remaining:")
        let limit = if (remaining.size() > 8) { 8 } else { remaining.size() }
        for (i in 0..limit) {
            lines.add("  - ${cliOneLine(remaining[i].toJsonString(), maxLen: 180)}")
        }
    } else {
        lines.add("Remaining: none")
    }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderDashboardStatus(result: JsonObject): Option<String> {
    let gateway = cliJsonObject(result, "gateway")
    if (gateway.toJsonString() == "{}") {
        return None<String>
    }
    let lines = ArrayList<String>()
    lines.add("Gateway status")
    lines.add("Model: ${cliJsonString(result, "model")}")
    lines.add("Gateway: enabled=${cliJsonBool(gateway, "enabled")} running=${cliJsonBool(gateway, "running")}")
    let dashboard = cliJsonObject(result, "dashboard")
    let url = cliJsonString(dashboard, "httpUrl")
    if (!url.isEmpty()) { lines.add("Control UI: ${url}") }
    let sessions = cliJsonObject(result, "sessions")
    lines.add("Sessions: ${cliJsonInt(sessions, "count")}")
    let channels = cliJsonArray(result, "channels")
    if (channels.size() > 0) {
        lines.add("Channels:")
        for (i in 0..channels.size()) {
            try {
                let ch = channels[i].asObject()
                lines.add("  - ${cliJsonString(ch, "id")}: enabled=${cliJsonBool(ch, "enabled")} mode=${cliJsonString(ch, "mode")}")
            } catch (_: Exception) {
                ()
            }
        }
    }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderGenericRpc(obj: JsonObject): Option<String> {
    let method = cliJsonString(obj, "method")
    let result = cliJsonObject(obj, "result")
    if (method == "discover") { return cliRenderDiscoverResult(result) }
    if (method == "channels.runtime") { return cliRenderChannelsRuntime(result) }
    if (method == "channels.health") { return cliRenderChannelsHealth(result) }
    if (method == "channels.get") { return cliRenderChannelGet(result) }
    if (method == "channels.audit") { return cliRenderChannelsAudit(result) }
    if (method == "dashboard.status" || method == "health") { return cliRenderDashboardStatus(result) }
    if (!cliJsonBool(obj, "ok", defaultValue: true)) {
        let lines = ArrayList<String>()
        lines.add("Gateway call failed: ${method}")
        lines.add("Error: ${cliJsonString(obj, "error")}")
        let code = cliJsonString(obj, "errorCode")
        if (!code.isEmpty()) { lines.add("Code: ${code}") }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    None<String>
}

public func gatewayFormatCommandOutput(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    try {
        let obj = JsonValue.fromStr(trimmed).asObject()
        match (cliRenderSubagents(obj)) {
            case Some(v) => return v
            case None => ()
        }
        match (cliRenderGenericRpc(obj)) {
            case Some(v) => return v
            case None => ()
        }
    } catch (_: Exception) {
        return trimmed
    }
    trimmed
}

public func gatewayPrintCommandOutput(raw: String): Unit {
    let text = gatewayFormatCommandOutput(raw)
    if (text.isEmpty()) {
        return
    }
    for (line in text.split("\n")) {
        PrintUtils.printLine(line)
    }
}
