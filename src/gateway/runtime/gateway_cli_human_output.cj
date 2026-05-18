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

private func cliJsonValueText(obj: JsonObject, key: String, defaultValue!: String = ""): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { return v.asString().getValue().trimAscii() } catch (_: Exception) { () }
            try { return if (v.asBool().getValue()) { "true" } else { "false" } } catch (_: Exception) { () }
            try { return "${v.asInt().getValue()}" } catch (_: Exception) { () }
            defaultValue
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

private func cliJsonHasField(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(_) => true
        case None => false
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

private func cliSafeRedactedValue(value: String): String {
    let trimmed = value.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    let low = trimmed.toAsciiLower()
    if (trimmed.contains("*") || low.contains("redacted")) {
        return trimmed
    }
    "[redacted]"
}

private func cliSafeDiagnosticText(value: String): String {
    let trimmed = value.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    let lower = trimmed.toAsciiLower()
    if (
        lower.contains("authorization") ||
        lower.contains("bearer ") ||
        lower.contains("appsecret") ||
        lower.contains("app_secret") ||
        lower.contains("secret") ||
        lower.contains("token") ||
        lower.contains("verificationtoken") ||
        lower.contains("verification_token") ||
        lower.contains("encryptkey") ||
        lower.contains("encrypt_key") ||
        lower.contains("password")
    ) {
        return "[redacted]"
    }
    trimmed
}

private func cliAddAccountSourceBit(bits: ArrayList<String>, label: String, row: JsonObject, key: String): Unit {
    let source = cliJsonString(row, key)
    if (!source.isEmpty() && source != "none") {
        bits.add("${label}=${source}")
    }
}

private func cliStringListContains(values: ArrayList<String>, target: String): Bool {
    for (value in values) {
        if (value == target) {
            return true
        }
    }
    false
}

private func cliAddOverrideName(overrides: ArrayList<String>, name: String): Unit {
    let normalized = name.trimAscii().toAsciiLower()
    if (!normalized.isEmpty() && !cliStringListContains(overrides, normalized)) {
        overrides.add(normalized)
    }
}

private func cliAccountOverrideSummary(row: JsonObject): String {
    let overrides = ArrayList<String>()
    if (cliJsonBool(row, "hasGroupsOverride")) { cliAddOverrideName(overrides, "groups") }
    if (cliJsonBool(row, "hasDirectOverride")) { cliAddOverrideName(overrides, "direct") }
    if (cliJsonBool(row, "hasDmsOverride")) { cliAddOverrideName(overrides, "dms") }
    if (cliJsonBool(row, "hasMediaOverride")) { cliAddOverrideName(overrides, "media") }
    if (cliJsonBool(row, "hasNetworkOverride")) { cliAddOverrideName(overrides, "network") }
    for ((key, _) in row.getFields()) {
        if (key.startsWith("has") && key.endsWith("Override") && cliJsonBool(row, key)) {
            cliAddOverrideName(overrides, key.replace("has", "").replace("Override", ""))
        }
    }
    if (overrides.size == 0) {
        "none"
    } else {
        String.join(overrides.toArray(), delimiter: ",")
    }
}

private func cliRenderChannelAccountRow(channelId: String, row: JsonObject, defaultAccountId!: String = ""): String {
    let accountId = cliJsonString(row, "accountId", defaultValue: "default")
    var line = "  - ${channelId}/${accountId}"
    if (cliJsonBool(row, "defaultAccount") || (!defaultAccountId.isEmpty() && accountId == defaultAccountId)) {
        line += " [default]"
    }
    let bits = ArrayList<String>()
    bits.add("configured=${cliJsonBool(row, "configured")}")
    bits.add("enabled=${cliJsonBool(row, "enabled", defaultValue: true)}")
    cliAddAccountSourceBit(bits, "credential", row, "credentialSource")
    cliAddAccountSourceBit(bits, "token", row, "tokenSource")
    cliAddAccountSourceBit(bits, "bot", row, "botTokenSource")
    cliAddAccountSourceBit(bits, "appToken", row, "appTokenSource")
    cliAddAccountSourceBit(bits, "app", row, "appSource")
    cliAddAccountSourceBit(bits, "bot", row, "botSource")
    cliAddAccountSourceBit(bits, "signing", row, "signingSecretSource")
    let credentialSources = cliJsonObject(row, "credentialSources")
    if (!cliJsonHasField(row, "credentialSource")) {
        cliAddAccountSourceBit(bits, "credential", credentialSources, "summary")
    }
    cliAddAccountSourceBit(bits, "appIdSource", credentialSources, "appId")
    cliAddAccountSourceBit(bits, "secretSource", credentialSources, "appSecret")
    let appId = cliSafeRedactedValue(cliJsonString(row, "appId"))
    if (!appId.isEmpty()) {
        bits.add("appId=${appId}")
    }
    if (cliJsonHasField(row, "allowFromCount")) {
        bits.add("allow=${cliJsonInt(row, "allowFromCount")}")
    }
    if (cliJsonHasField(row, "allowFromEffectiveCount")) {
        bits.add("allowEffective=${cliJsonInt(row, "allowFromEffectiveCount")}")
    }
    if (cliJsonHasField(row, "groupAllowFromCount")) {
        bits.add("groupAllow=${cliJsonInt(row, "groupAllowFromCount")}")
    }
    if (cliJsonHasField(row, "groupAllowFromEffectiveCount")) {
        bits.add("groupAllowEffective=${cliJsonInt(row, "groupAllowFromEffectiveCount")}")
    }
    let securitySources = cliJsonObject(row, "securitySources")
    cliAddAccountSourceBit(bits, "allowSource", securitySources, "allowFrom")
    cliAddAccountSourceBit(bits, "groupAllowSource", securitySources, "groupAllowFrom")
    cliAddAccountSourceBit(bits, "dmPolicySource", securitySources, "dmPolicy")
    cliAddAccountSourceBit(bits, "groupPolicySource", securitySources, "groupPolicy")
    if (cliJsonHasField(row, "approvedSenderCount")) {
        bits.add("approvedSenders=${cliJsonInt(row, "approvedSenderCount")}")
    }
    bits.add("overrides=${cliAccountOverrideSummary(row)}")
    bits.add("binding=${channelId}:${accountId}")
    if (bits.size > 0) {
        line += ": ${String.join(bits.toArray(), delimiter: " ")}"
    }
    line
}

private func cliRenderChannelAccountInspectLines(channelId: String, inspect: JsonObject, heading!: String = "Accounts"): ArrayList<String> {
    let lines = ArrayList<String>()
    let accounts = cliJsonArray(inspect, "accounts")
    if (accounts.size() == 0) {
        return lines
    }
    let defaultAccountId = cliJsonString(inspect, "defaultAccountId", defaultValue: "default")
    let redacted = cliJsonBool(inspect, "tokenRedacted") || cliJsonBool(inspect, "redacted")
    let count = cliJsonInt(inspect, "count", defaultValue: accounts.size())
    var header = "${heading}: ${count} default=${defaultAccountId}"
    if (redacted) {
        header += " credentials=redacted"
    }
    lines.add(header)
    for (i in 0..accounts.size()) {
        try {
            lines.add(cliRenderChannelAccountRow(channelId, accounts[i].asObject(), defaultAccountId: defaultAccountId))
        } catch (_: Exception) {
            ()
        }
    }
    lines
}

private func cliRuntimeConfiguredAccountInspect(result: JsonObject, channelId: String): JsonObject {
    if (!channelId.isEmpty() && channelId != "all") {
        let nested = cliJsonObject(cliJsonObject(result, channelId), "accountInspect")
        if (nested.toJsonString() != "{}") {
            return nested
        }
    }
    cliJsonObject(result, "accountInspect")
}

private func cliRenderChannelsRuntime(result: JsonObject): Option<String> {
    let accounts = cliJsonArray(result, "accounts")
    let channelId = cliJsonString(result, "channelId", defaultValue: "all")
    let configuredInspect = cliRuntimeConfiguredAccountInspect(result, channelId)
    let configuredAccounts = cliJsonArray(configuredInspect, "accounts")
    if (accounts.size() == 0) {
        let runtime = cliJsonObject(result, "runtime")
        let nested = cliJsonArray(runtime, "accounts")
        if (nested.size() == 0 && configuredAccounts.size() == 0) {
            return None<String>
        }
    }
    let rows = if (accounts.size() > 0) { accounts } else { cliJsonArray(cliJsonObject(result, "runtime"), "accounts") }
    let lines = ArrayList<String>()
    lines.add("Channel runtime: ${channelId}")
    lines.add("Meaning: runtime rows are live adapter state; configured accounts are listed separately when available.")
    lines.add("Metrics: running=live adapter process/task, phase=lifecycle phase, failures=send/poll/start failures.")
    let configuredDefaultAccountId = cliJsonString(configuredInspect, "defaultAccountId")
    let runtimeDefaultAccountId = cliJsonString(result, "defaultAccountId")
    if (!configuredDefaultAccountId.isEmpty()) {
        lines.add("Configured default account: ${configuredDefaultAccountId}")
    }
    if (!runtimeDefaultAccountId.isEmpty() && runtimeDefaultAccountId != configuredDefaultAccountId) {
        lines.add("Runtime default alias: ${runtimeDefaultAccountId}")
    } else if (configuredDefaultAccountId.isEmpty() && !runtimeDefaultAccountId.isEmpty()) {
        lines.add("Runtime default account: ${runtimeDefaultAccountId}")
    }
    lines.add("Runtime accounts:")
    if (rows.size() == 0) {
        lines.add("  - none registered")
    } else {
        for (i in 0..rows.size()) {
            try {
                let row = rows[i].asObject()
                lines.add(
                    "  - ${cliJsonString(row, "channelId")}/${cliJsonString(row, "accountId")}: running=${cliJsonBool(row, "running")} phase=${cliJsonString(row, "phase")} pull=${cliJsonInt(row, "pullCount")} inbound=${cliJsonInt(row, "inboundCount")} sendOk=${cliJsonInt(row, "sendSuccessCount")} sendFail=${cliJsonInt(row, "sendFailureCount")}"
                )
                let err = cliJsonString(row, "lastError")
                if (!err.isEmpty()) { lines.add("    lastError: ${cliOneLine(cliSafeDiagnosticText(err))}") }
            } catch (_: Exception) {
                ()
            }
        }
    }
    for (line in cliRenderChannelAccountInspectLines(channelId, configuredInspect, heading: "Configured accounts")) {
        lines.add(line)
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
    let displayId = if (id.isEmpty()) { "unknown" } else { id }
    let lines = ArrayList<String>()
    lines.add("Channel: ${displayId}")
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
    let accountLines = cliRenderChannelAccountInspectLines(displayId, cliJsonObject(channel, "accountInspect"))
    for (line in accountLines) {
        lines.add(line)
    }
    if (accountLines.size > 0) {
        lines.add("Meaning: this command shows configured channel accounts; use `metis gateway channel runtime ${displayId}` for live adapter state.")
    }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderFeishuAuditDiagnostics(lines: ArrayList<String>, audit: JsonObject, summary: JsonObject): Unit {
    let summaryDiag = cliJsonObject(summary, "feishuDiagnostics")
    let diagnostics = cliJsonObject(audit, "feishuDiagnostics")
    let ownership = cliJsonObject(diagnostics, "eventOwnership")
    if (summaryDiag.toJsonString() == "{}" && ownership.toJsonString() == "{}") {
        return
    }
    let byStatus = cliJsonObject(summaryDiag, "byStatus")
    lines.add(
        "Feishu diagnostics: status=${cliJsonString(summaryDiag, "status", defaultValue: cliJsonString(ownership, "status", defaultValue: "unknown"))} accounts=${cliJsonInt(summaryDiag, "accountCount", defaultValue: cliJsonInt(ownership, "accountCount"))} wrongApp=${cliJsonInt(byStatus, "wrong_app")} noEvent=${cliJsonInt(byStatus, "no_event")} ambiguousAppId=${cliJsonInt(byStatus, "ambiguous_app_id")} missingAppId=${cliJsonInt(byStatus, "missing_app_id")}"
    )
    let accounts = cliJsonArray(ownership, "accounts")
    if (accounts.size() > 0) {
        lines.add("Feishu account diagnostics:")
        let limit = if (accounts.size() > 8) { 8 } else { accounts.size() }
        for (i in 0..limit) {
            try {
                let row = accounts[i].asObject()
                let accountId = cliJsonString(row, "accountId", defaultValue: "default")
                let status = cliJsonString(row, "status", defaultValue: "unknown")
                let reason = cliJsonString(row, "reason")
                var text = "  - feishu/${accountId}: ${status}"
                if (!reason.isEmpty()) {
                    text += " (${reason})"
                }
                let lastError = cliSafeDiagnosticText(cliJsonString(row, "lastError"))
                if (!lastError.isEmpty()) {
                    text += " lastError=${cliOneLine(lastError, maxLen: 80)}"
                }
                lines.add(text)
                let advice = cliJsonArray(row, "advice")
                if (advice.size() > 0) {
                    let first = try { advice[0].asString().getValue().trimAscii() } catch (_: Exception) { "" }
                    if (!first.isEmpty()) {
                        lines.add("    next: ${cliOneLine(cliSafeDiagnosticText(first), maxLen: 160)}")
                    }
                }
            } catch (_: Exception) {
                ()
            }
        }
    }
    let actions = cliJsonArray(ownership, "actions")
    if (actions.size() > 0) {
        lines.add("Feishu actions:")
        let limit = if (actions.size() > 6) { 6 } else { actions.size() }
        for (i in 0..limit) {
            let text = try { actions[i].asString().getValue().trimAscii() } catch (_: Exception) { "" }
            if (!text.isEmpty()) {
                lines.add("  - ${cliOneLine(cliSafeDiagnosticText(text), maxLen: 180)}")
            }
        }
    }
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
    cliRenderFeishuAuditDiagnostics(lines, audit, summary)
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
            try {
                let row = remaining[i].asObject()
                let code = cliJsonString(row, "code", defaultValue: cliJsonString(row, "id", defaultValue: cliJsonString(row, "capability")))
                let status = cliJsonString(row, "status", defaultValue: cliJsonString(row, "severity"))
                let message = cliJsonString(row, "message", defaultValue: cliJsonString(row, "reason"))
                var text = if (code.isEmpty()) { "remaining item" } else { code }
                if (!status.isEmpty()) { text += " [${status}]" }
                if (!message.isEmpty()) { text += ": ${cliOneLine(message, maxLen: 140)}" }
                lines.add("  - ${text}")
            } catch (_: Exception) {
                lines.add("  - remaining item")
            }
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

private func cliJsonStringArrayText(arr: JsonArray): String {
    if (arr.size() == 0) {
        return "none"
    }
    let values = ArrayList<String>()
    for (i in 0..arr.size()) {
        try {
            let text = arr[i].asString().getValue().trimAscii()
            if (!text.isEmpty()) {
                values.add(text)
            }
        } catch (_: Exception) {
            ()
        }
    }
    if (values.size == 0) {
        return "none"
    }
    String.join(values.toArray(), delimiter: ", ")
}

private func cliImageCandidateModel(row: JsonObject): String {
    let modelRef = cliJsonString(row, "modelRef", defaultValue: cliJsonString(row, "model"))
    if (!modelRef.isEmpty()) {
        return modelRef
    }
    let capability = cliJsonObject(row, "capability")
    cliJsonString(capability, "modelRef", defaultValue: cliJsonString(capability, "canonicalRef"))
}

private func cliImageCandidateStatus(row: JsonObject): String {
    let direct = cliJsonString(row, "status")
    if (!direct.isEmpty()) {
        return direct
    }
    let capability = cliJsonObject(row, "capability")
    cliJsonString(capability, "status")
}

private func cliRenderImageCandidate(row: JsonObject): String {
    let model = cliImageCandidateModel(row)
    let source = cliJsonString(row, "source")
    let status = cliImageCandidateStatus(row)
    let capability = cliJsonObject(row, "capability")
    let reason = cliJsonString(capability, "reason", defaultValue: cliJsonString(row, "reason"))
    var line = "  - ${if (model.isEmpty()) { "unknown" } else { model }}"
    if (!source.isEmpty()) { line += "  source=${source}" }
    if (!status.isEmpty()) { line += "  status=${status}" }
    if (!reason.isEmpty()) { line += "  reason=${cliOneLine(reason, maxLen: 120)}" }
    line
}

private func cliRenderImageUnderstandingStatus(result: JsonObject): Option<String> {
    let candidates = cliJsonArray(result, "candidates")
    let rejected = cliJsonArray(result, "rejected")
    let hasImageFields = result.get("imageModel").isSome() ||
        result.get("imageFallbackModels").isSome() ||
        result.get("candidateCount").isSome() ||
        result.get("configChannel").isSome()
    if (!hasImageFields || (result.get("configured").isNone() && candidates.size() == 0 && rejected.size() == 0)) {
        return None<String>
    }

    let lines = ArrayList<String>()
    let configChannel = cliJsonString(result, "configChannel")
    let runtimeChannel = cliJsonString(result, "channel")
    let channel = if (!configChannel.isEmpty()) {
        configChannel
    } else if (!runtimeChannel.isEmpty()) {
        runtimeChannel
    } else {
        "shared"
    }
    lines.add("Image understanding")
    lines.add("Channel: ${channel}  enabled=${cliJsonBool(result, "enabled", defaultValue: true)}  configured=${cliJsonBool(result, "configured")}")
    let imageModel = cliJsonString(result, "imageModel")
    lines.add("Image primary: ${if (imageModel.isEmpty()) { "not set" } else { imageModel }}")
    lines.add("Image fallbacks: ${cliJsonStringArrayText(cliJsonArray(result, "imageFallbackModels"))}")

    if (candidates.size() == 0) {
        lines.add("Candidates: none")
        lines.add("Next: configure agents.defaults.imageModel.primary or gateway.media.image.models with a vision-capable model.")
    } else {
        lines.add("Candidates:")
        let limit = if (candidates.size() > 8) { 8 } else { candidates.size() }
        for (i in 0..limit) {
            try {
                lines.add(cliRenderImageCandidate(candidates[i].asObject()))
            } catch (_: Exception) {
                ()
            }
        }
        if (candidates.size() > limit) {
            lines.add("  ... ${candidates.size() - limit} more")
        }
    }

    if (rejected.size() > 0) {
        lines.add("Skipped:")
        let limit = if (rejected.size() > 8) { 8 } else { rejected.size() }
        for (i in 0..limit) {
            try {
                lines.add(cliRenderImageCandidate(rejected[i].asObject()))
            } catch (_: Exception) {
                ()
            }
        }
        if (rejected.size() > limit) {
            lines.add("  ... ${rejected.size() - limit} more")
        }
    }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderImageConfigMutation(result: JsonObject): Option<String> {
    let action = cliJsonString(result, "action")
    if (action != "set" && action != "add-model" && action != "remove-model") {
        return None<String>
    }
    let image = cliJsonObject(result, "image")
    if (image.toJsonString() == "{}") {
        return None<String>
    }
    let lines = ArrayList<String>()
    lines.add("Image understanding configuration updated")
    lines.add("Channel: ${cliJsonString(result, "channel", defaultValue: "shared")}")
    lines.add("Action: ${action}")
    lines.add("Enabled: ${cliJsonBool(image, "enabled", defaultValue: true)}")
    let provider = cliJsonString(image, "provider")
    if (!provider.isEmpty()) {
        lines.add("Active provider: ${provider}")
    }
    let models = cliJsonArray(image, "models")
    if (models.size() == 0) {
        lines.add("Models: none")
    } else {
        lines.add("Models:")
        let limit = if (models.size() > 8) { 8 } else { models.size() }
        for (idx in 0..limit) {
            try {
                let row = models[idx].asObject()
                let p = cliJsonString(row, "provider")
                let m = cliJsonString(row, "model")
                if (!p.isEmpty() || !m.isEmpty()) {
                    lines.add("  - ${if (p.isEmpty()) { "unknown" } else { p }}:${if (m.isEmpty()) { "unknown" } else { m }}")
                }
            } catch (_: Exception) {
                ()
            }
        }
        if (models.size() > limit) {
            lines.add("  ... ${models.size() - limit} more")
        }
    }
    lines.add("Next: metis gateway media image status --channel ${cliJsonString(result, "channel", defaultValue: "shared")}")
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderCronJobObject(obj: JsonObject): Option<String> {
    let id = cliJsonString(obj, "id", defaultValue: cliJsonString(obj, "name"))
    let schedule = cliJsonObject(obj, "schedule")
    if (id.isEmpty() || schedule.toJsonString() == "{}") {
        return None<String>
    }
    let kind = cliJsonString(schedule, "kind")
    var scheduleText = kind
    if (kind == "every") {
        scheduleText = "every ${cliJsonValueText(schedule, "everyMs", defaultValue: "0")}ms"
    } else if (kind == "at") {
        scheduleText = "at ${cliJsonValueText(schedule, "atMs", defaultValue: "0")}"
    } else if (kind == "cron") {
        let tz = cliJsonString(schedule, "timeZone", defaultValue: "UTC")
        scheduleText = "cron ${cliJsonString(schedule, "cronExpr")} (${tz})"
    }
    let state = cliJsonObject(obj, "state")
    let lines = ArrayList<String>()
    lines.add("Cron job")
    lines.add("ID: ${id}")
    lines.add("Enabled: ${cliJsonBool(obj, "enabled", defaultValue: true)}")
    lines.add("Schedule: ${scheduleText}")
    lines.add("Session: ${cliJsonString(obj, "sessionTarget", defaultValue: "main")}")
    let agent = cliJsonString(obj, "agentId")
    if (!agent.isEmpty()) { lines.add("Agent: ${agent}") }
    let model = cliJsonString(obj, "modelOverride")
    if (!model.isEmpty()) { lines.add("Model: ${model}") }
    let nextRun = cliJsonValueText(state, "nextRunAtMs")
    if (!nextRun.isEmpty() && nextRun != "0") { lines.add("Next run: ${nextRun}") }
    let deliveryChannel = cliJsonString(obj, "deliveryChannel")
    let deliveryTo = cliJsonString(obj, "deliveryTo")
    if (!deliveryChannel.isEmpty() || !deliveryTo.isEmpty()) {
        lines.add("Delivery: ${if (deliveryChannel.isEmpty()) { "default" } else { deliveryChannel }} -> ${if (deliveryTo.isEmpty()) { "(not set)" } else { deliveryTo }}")
    }
    let prompt = cliJsonString(obj, "prompt")
    if (!prompt.isEmpty()) { lines.add("Prompt: ${cliOneLine(prompt, maxLen: 180)}") }
    Some<String>(String.join(lines.toArray(), delimiter: "\n"))
}

private func cliRenderGenericOkErrorObject(obj: JsonObject): Option<String> {
    if (obj.get("ok").isNone()) {
        return None<String>
    }
    let ok = cliJsonBool(obj, "ok", defaultValue: false)
    if (!ok) {
        let lines = ArrayList<String>()
        lines.add("Command failed")
        let err = cliJsonString(obj, "error", defaultValue: cliJsonString(obj, "message"))
        if (!err.isEmpty()) {
            lines.add("Error: ${cliOneLine(err, maxLen: 220)}")
        }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (obj.get("ran").isSome() || obj.get("jobId").isSome() || obj.get("reason").isSome()) {
        let lines = ArrayList<String>()
        lines.add("Cron run")
        let jobId = cliJsonString(obj, "jobId")
        if (!jobId.isEmpty()) { lines.add("Job: ${jobId}") }
        lines.add("Ran: ${cliJsonBool(obj, "ran", defaultValue: false)}")
        let reason = cliJsonString(obj, "reason")
        if (!reason.isEmpty()) { lines.add("Reason: ${reason}") }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    if (obj.getFields().size <= 3) {
        let lines = ArrayList<String>()
        lines.add("Command succeeded")
        let status = cliJsonString(obj, "status")
        if (!status.isEmpty()) { lines.add("Status: ${status}") }
        let message = cliJsonString(obj, "message")
        if (!message.isEmpty()) { lines.add("Message: ${cliOneLine(message, maxLen: 220)}") }
        return Some<String>(String.join(lines.toArray(), delimiter: "\n"))
    }
    None<String>
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
    if (!method.isEmpty()) {
        let lines = ArrayList<String>()
        lines.add("Gateway call: ${method}")
        lines.add("Status: ok")
        if (result.getFields().size > 0) {
            let fields = ArrayList<String>()
            for ((key, _) in result.getFields()) {
                fields.add(key)
            }
            lines.add("Result fields: ${String.join(fields.toArray(), delimiter: ", ")}")
            lines.add("Details: use the dedicated command for this method, or `gateway call --json ${method}` for machine output.")
        }
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
        match (cliRenderImageUnderstandingStatus(obj)) {
            case Some(v) => return v
            case None => ()
        }
        match (cliRenderImageConfigMutation(obj)) {
            case Some(v) => return v
            case None => ()
        }
        match (cliRenderCronJobObject(obj)) {
            case Some(v) => return v
            case None => ()
        }
        match (cliRenderGenericRpc(obj)) {
            case Some(v) => return v
            case None => ()
        }
        match (cliRenderGenericOkErrorObject(obj)) {
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
