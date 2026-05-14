package metis.gateway.core

import magic.jsonable.*

import metis.core.config.CliConfig

import std.collection.{ArrayList, HashSet}
import std.convert.Parsable
import std.fs.{File, Path, exists}
import std.time.DateTime

import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

public func gatewayChannelRuntimeStatePath(): String {
    CliConfig.dotDir.join("gateway-channel-runtime-state.json").toString()
}

private func gatewayChannelRuntimeReadState(): JsonObject {
    let path = Path(gatewayChannelRuntimeStatePath())
    if (!exists(path)) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func gatewayChannelRuntimeWriteState(root: JsonObject): Unit {
    let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
    root.put("updatedAtMs", now.toJsonValue())
    File.writeTo(Path(gatewayChannelRuntimeStatePath()), root.toJsonString().toArray())
}

private func gatewayChannelRuntimeReadBootstrap(root: JsonObject): JsonObject {
    match (root.get("bootstrap")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayChannelRuntimeNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func channelRuntimeReadString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func channelRuntimeReadBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func channelRuntimeReadInt(obj: JsonObject, key: String, defaultValue: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func channelRuntimeRedactSecretText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lower = text.toAsciiLower()
    if (
        lower.contains("authorization") ||
        lower.contains("bearer ") ||
        lower.contains("secret") ||
        lower.contains("token") ||
        lower.contains("password")
    ) {
        return "[redacted]"
    }
    text
}

private func channelRuntimeReadAccounts(root: JsonObject): JsonArray {
    let raw = match (root.get("accounts")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    if (raw.size() == 0) {
        return raw
    }
    let seen = HashSet<String>()
    let compactReverse = ArrayList<JsonObject>()
    for (idx in raw.size() - 1..=0:-1) {
        let row = try { raw[idx].asObject() } catch (_e: Exception) { JsonObject() }
        let compact = channelRuntimeCompactAccountRow(row)
        let channelId = channelRuntimeReadString(compact, "channelId", "").trimAscii().toAsciiLower()
        let accountId = channelRuntimeReadString(compact, "accountId", "").trimAscii()
        if (channelId.isEmpty() || accountId.isEmpty()) {
            continue
        }
        let key = "${channelId}:${accountId}"
        if (seen.contains(key)) {
            continue
        }
        seen.add(key)
        compactReverse.add(compact)
    }
    let out = JsonArray([])
    for (idx in compactReverse.size - 1..=0:-1) {
        out.add(compactReverse[idx])
    }
    root.put("accounts", out)
    out
}

private func channelRuntimeTrimHistory(history: JsonArray, maxEntries!: Int64 = 64): JsonArray {
    if (history.size() <= maxEntries) {
        return history
    }
    let out = JsonArray([])
    let start = history.size() - maxEntries
    for (idx in start..history.size()) {
        out.add(history[idx])
    }
    out
}

private func channelRuntimeCompactAccountRow(row: JsonObject): JsonObject {
    let out = channelRuntimeCloneRow(row)
    let history = match (out.get("history")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    out.put("history", channelRuntimeTrimHistory(history))
    out
}

private func channelRuntimeAppendHistory(history: JsonArray, state: String, detail: String): JsonArray {
    let out = JsonArray([])
    for (i in 0..history.size()) {
        out.add(history[i])
    }
    let row = JsonObject()
    row.put("state", JsonString(state))
    row.put("detail", JsonString(channelRuntimeRedactSecretText(detail)))
    row.put("ts", gatewayChannelRuntimeNowMs().toJsonValue())
    out.add(row)
    out
}

private func channelRuntimePhase(lifecycleState: String, running: Bool): String {
    if (lifecycleState == "starting") {
        return "starting"
    }
    if (lifecycleState == "backoff") {
        return "backoff"
    }
    if (lifecycleState == "failed") {
        return "failed"
    }
    if (running) {
        return "active"
    }
    if (lifecycleState == "stopped") {
        return "idle"
    }
    return "registered"
}

private func channelRuntimeCloneRow(row: JsonObject): JsonObject {
    let out = JsonObject()
    out.put("channelId", JsonString(channelRuntimeReadString(row, "channelId", "")))
    out.put("accountId", JsonString(channelRuntimeReadString(row, "accountId", "")))
    out.put("pluginId", JsonString(channelRuntimeReadString(row, "pluginId", "")))
    out.put("label", JsonString(channelRuntimeReadString(row, "label", "")))
    out.put("detailLabel", JsonString(channelRuntimeReadString(row, "detailLabel", "")))
    out.put("origin", JsonString(channelRuntimeReadString(row, "origin", "builtin")))
    out.put("runtimeKind", JsonString(channelRuntimeReadString(row, "runtimeKind", "adapter")))
    out.put("compatibilityMode", JsonString(channelRuntimeReadString(row, "compatibilityMode", "native-cangjie")))
    out.put("enabled", channelRuntimeReadBool(row, "enabled", true).toJsonValue())
    out.put("configured", channelRuntimeReadBool(row, "configured", true).toJsonValue())
    out.put("healthMonitorEnabled", channelRuntimeReadBool(row, "healthMonitorEnabled", true).toJsonValue())
    out.put("running", channelRuntimeReadBool(row, "running", false).toJsonValue())
    out.put("lifecycleState", JsonString(channelRuntimeReadString(row, "lifecycleState", "registered")))
    out.put("phase", JsonString(channelRuntimeReadString(row, "phase", "registered")))
    out.put("manualStop", channelRuntimeReadBool(row, "manualStop", false).toJsonValue())
    out.put("startCount", channelRuntimeReadInt(row, "startCount", 0).toJsonValue())
    out.put("stopCount", channelRuntimeReadInt(row, "stopCount", 0).toJsonValue())
    out.put("restartCount", channelRuntimeReadInt(row, "restartCount", 0).toJsonValue())
    out.put("failureCount", channelRuntimeReadInt(row, "failureCount", 0).toJsonValue())
    out.put("pullCount", channelRuntimeReadInt(row, "pullCount", 0).toJsonValue())
    out.put("inboundCount", channelRuntimeReadInt(row, "inboundCount", 0).toJsonValue())
    out.put("sendSuccessCount", channelRuntimeReadInt(row, "sendSuccessCount", 0).toJsonValue())
    out.put("sendFailureCount", channelRuntimeReadInt(row, "sendFailureCount", 0).toJsonValue())
    out.put("registeredAtMs", channelRuntimeReadInt(row, "registeredAtMs", 0).toJsonValue())
    out.put("lastStartAtMs", channelRuntimeReadInt(row, "lastStartAtMs", 0).toJsonValue())
    out.put("lastStopAtMs", channelRuntimeReadInt(row, "lastStopAtMs", 0).toJsonValue())
    out.put("lastPullAtMs", channelRuntimeReadInt(row, "lastPullAtMs", 0).toJsonValue())
    out.put("lastEventAtMs", channelRuntimeReadInt(row, "lastEventAtMs", 0).toJsonValue())
    out.put("lastSendAtMs", channelRuntimeReadInt(row, "lastSendAtMs", 0).toJsonValue())
    out.put("lastError", JsonString(channelRuntimeRedactSecretText(channelRuntimeReadString(row, "lastError", ""))))
    out.put("backoffMs", channelRuntimeReadInt(row, "backoffMs", 0).toJsonValue())
    out.put("nextRestartAtMs", channelRuntimeReadInt(row, "nextRestartAtMs", 0).toJsonValue())
    out.put("configuredBinding", channelRuntimeReadBool(row, "configuredBinding", false).toJsonValue())
    out.put("primed", channelRuntimeReadBool(row, "primed", false).toJsonValue())
    out.put("autoEnabled", channelRuntimeReadBool(row, "autoEnabled", false).toJsonValue())
    out.put("bindingState", JsonString(channelRuntimeReadString(row, "bindingState", "unprimed")))
    out.put("primedAtMs", channelRuntimeReadInt(row, "primedAtMs", 0).toJsonValue())
    out.put("taskState", JsonString(channelRuntimeReadString(row, "taskState", "idle")))
    out.put("taskGeneration", channelRuntimeReadInt(row, "taskGeneration", 0).toJsonValue())
    out.put("abortState", JsonString(channelRuntimeReadString(row, "abortState", "clear")))
    out.put("monitorState", JsonString(channelRuntimeReadString(row, "monitorState", "disabled")))
    out.put("monitorEnabledAtMs", channelRuntimeReadInt(row, "monitorEnabledAtMs", 0).toJsonValue())
    out.put("lastMonitorAtMs", channelRuntimeReadInt(row, "lastMonitorAtMs", 0).toJsonValue())
    out.put("restartBudget", channelRuntimeReadInt(row, "restartBudget", 0).toJsonValue())
    out.put("restartBudgetState", JsonString(channelRuntimeReadString(row, "restartBudgetState", "steady")))
    out.put(
        "history",
        match (row.get("history")) {
            case Some(v) => v
            case None => JsonArray([])
        }
    )
    out
}

private func channelRuntimeUpsertAccount(
    channelId: String,
    accountId: String,
    updater: (JsonObject) -> JsonObject
): JsonObject {
    let root = gatewayChannelRuntimeReadState()
    let existing = channelRuntimeReadAccounts(root)
    let next = JsonArray([])
    let normalizedChannel = channelId.trimAscii().toAsciiLower()
    let normalizedAccount = accountId.trimAscii()
    var found = false
    var updated = JsonObject()
    for (i in 0..existing.size()) {
        let row = try { existing[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (channelRuntimeReadString(row, "channelId", "") == normalizedChannel &&
            channelRuntimeReadString(row, "accountId", "") == normalizedAccount) {
            found = true
            updated = updater(row)
            next.add(updated)
        } else {
            next.add(row)
        }
    }
    if (!found) {
        updated = updater(JsonObject())
        next.add(updated)
    }
    root.put("accounts", next)
    gatewayChannelRuntimeWriteState(root)
    updated
}

public func gatewayChannelRuntimeRegisterAccount(
    channelId: String,
    accountId!: String = "default",
    pluginId!: String = "",
    label!: String = "",
    detailLabel!: String = "",
    origin!: String = "builtin",
    runtimeKind!: String = "adapter",
    compatibilityMode!: String = "native-cangjie",
    enabled!: Bool = true,
    configured!: Bool = true,
    healthMonitorEnabled!: Bool = true
): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = JsonObject()
        let now = gatewayChannelRuntimeNowMs()
        let history = match (row.get("history")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        out.put("channelId", JsonString(channelId.trimAscii().toAsciiLower()))
        out.put("accountId", JsonString(accountId.trimAscii()))
        out.put("pluginId", JsonString(pluginId.trimAscii().toAsciiLower()))
        out.put("label", JsonString(label.trimAscii()))
        out.put("detailLabel", JsonString(detailLabel.trimAscii()))
        out.put("origin", JsonString(origin.trimAscii()))
        out.put("runtimeKind", JsonString(runtimeKind.trimAscii()))
        out.put("compatibilityMode", JsonString(compatibilityMode.trimAscii()))
        out.put("enabled", enabled.toJsonValue())
        out.put("configured", configured.toJsonValue())
        out.put("healthMonitorEnabled", healthMonitorEnabled.toJsonValue())
        out.put("running", row.get("running") ?? false.toJsonValue())
        out.put("lifecycleState", row.get("lifecycleState") ?? JsonString("registered"))
        out.put("phase", row.get("phase") ?? JsonString("registered"))
        out.put("manualStop", row.get("manualStop") ?? false.toJsonValue())
        out.put("startCount", row.get("startCount") ?? 0.toJsonValue())
        out.put("stopCount", row.get("stopCount") ?? 0.toJsonValue())
        out.put("restartCount", row.get("restartCount") ?? 0.toJsonValue())
        out.put("failureCount", row.get("failureCount") ?? 0.toJsonValue())
        out.put("pullCount", row.get("pullCount") ?? 0.toJsonValue())
        out.put("inboundCount", row.get("inboundCount") ?? 0.toJsonValue())
        out.put("sendSuccessCount", row.get("sendSuccessCount") ?? 0.toJsonValue())
        out.put("sendFailureCount", row.get("sendFailureCount") ?? 0.toJsonValue())
        out.put("registeredAtMs", row.get("registeredAtMs") ?? now.toJsonValue())
        out.put("lastStartAtMs", row.get("lastStartAtMs") ?? 0.toJsonValue())
        out.put("lastStopAtMs", row.get("lastStopAtMs") ?? 0.toJsonValue())
        out.put("lastPullAtMs", row.get("lastPullAtMs") ?? 0.toJsonValue())
        out.put("lastEventAtMs", row.get("lastEventAtMs") ?? 0.toJsonValue())
        out.put("lastSendAtMs", row.get("lastSendAtMs") ?? 0.toJsonValue())
        out.put("lastError", row.get("lastError") ?? JsonString(""))
        out.put("backoffMs", row.get("backoffMs") ?? 0.toJsonValue())
        out.put("nextRestartAtMs", row.get("nextRestartAtMs") ?? 0.toJsonValue())
        out.put("configuredBinding", row.get("configuredBinding") ?? false.toJsonValue())
        out.put("primed", row.get("primed") ?? false.toJsonValue())
        out.put("autoEnabled", row.get("autoEnabled") ?? false.toJsonValue())
        out.put("bindingState", row.get("bindingState") ?? JsonString("unprimed"))
        out.put("primedAtMs", row.get("primedAtMs") ?? 0.toJsonValue())
        out.put("taskState", row.get("taskState") ?? JsonString("idle"))
        out.put("taskGeneration", row.get("taskGeneration") ?? 0.toJsonValue())
        out.put("abortState", row.get("abortState") ?? JsonString("clear"))
        out.put("monitorState", row.get("monitorState") ?? JsonString("disabled"))
        out.put("monitorEnabledAtMs", row.get("monitorEnabledAtMs") ?? 0.toJsonValue())
        out.put("lastMonitorAtMs", row.get("lastMonitorAtMs") ?? 0.toJsonValue())
        out.put("restartBudget", row.get("restartBudget") ?? 0.toJsonValue())
        out.put("restartBudgetState", row.get("restartBudgetState") ?? JsonString("steady"))
        out.put("history", if (history.size() == 0) { channelRuntimeAppendHistory(history, "registered", "account-registered") } else { history })
        out
    })
}

public func gatewayChannelRuntimePrimeAccount(
    channelId: String,
    accountId!: String = "default",
    configuredBinding!: Bool = true,
    autoEnabled!: Bool = false,
    detail!: String = "configured-binding-primed"
): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let history = match (row.get("history")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        let now = gatewayChannelRuntimeNowMs()
        let bindingState = if (configuredBinding) { "primed" } else { "registered" }
        out.put("configuredBinding", configuredBinding.toJsonValue())
        out.put("primed", true.toJsonValue())
        out.put("autoEnabled", autoEnabled.toJsonValue())
        out.put("bindingState", JsonString(bindingState))
        out.put("primedAtMs", now.toJsonValue())
        if (autoEnabled && channelRuntimeReadBool(row, "manualStop", false)) {
            out.put("manualStop", false.toJsonValue())
            out.put("abortState", JsonString("clear"))
            if (channelRuntimeReadString(row, "lastError", "") == "manual-stop") {
                out.put("lastError", JsonString(""))
            }
        }
        out.put("history", channelRuntimeAppendHistory(history, "primed", detail.trimAscii()))
        out
    })
}

private func gatewayChannelRuntimePrimeAccountFromRow(
    row: JsonObject,
    configuredBinding: Bool,
    autoEnabled: Bool,
    detail: String
): JsonObject {
    let out = channelRuntimeCloneRow(row)
    let history = match (row.get("history")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
    let now = gatewayChannelRuntimeNowMs()
    let bindingState = if (configuredBinding) { "primed" } else { "registered" }
    out.put("configuredBinding", configuredBinding.toJsonValue())
    out.put("primed", true.toJsonValue())
    out.put("autoEnabled", autoEnabled.toJsonValue())
    out.put("bindingState", JsonString(bindingState))
    out.put("primedAtMs", now.toJsonValue())
    if (autoEnabled && channelRuntimeReadBool(row, "manualStop", false)) {
        out.put("manualStop", false.toJsonValue())
        out.put("abortState", JsonString("clear"))
        if (channelRuntimeReadString(row, "lastError", "") == "manual-stop") {
            out.put("lastError", JsonString(""))
        }
    }
    out.put("history", channelRuntimeAppendHistory(history, "primed", detail.trimAscii()))
    out
}

private func gatewayChannelRuntimeNewBaseAccountRow(
    channelId: String,
    accountId: String
): JsonObject {
    let now = gatewayChannelRuntimeNowMs()
    let base = JsonObject()
    base.put("channelId", JsonString(channelId.trimAscii().toAsciiLower()))
    base.put("accountId", JsonString(accountId.trimAscii()))
    base.put("pluginId", JsonString(""))
    base.put("label", JsonString(""))
    base.put("detailLabel", JsonString(""))
    base.put("origin", JsonString("builtin"))
    base.put("runtimeKind", JsonString("adapter"))
    base.put("compatibilityMode", JsonString("native-cangjie"))
    base.put("enabled", true.toJsonValue())
    base.put("configured", true.toJsonValue())
    base.put("healthMonitorEnabled", true.toJsonValue())
    base.put("running", false.toJsonValue())
    base.put("lifecycleState", JsonString("registered"))
    base.put("phase", JsonString("registered"))
    base.put("manualStop", false.toJsonValue())
    base.put("startCount", 0.toJsonValue())
    base.put("stopCount", 0.toJsonValue())
    base.put("restartCount", 0.toJsonValue())
    base.put("failureCount", 0.toJsonValue())
    base.put("pullCount", 0.toJsonValue())
    base.put("inboundCount", 0.toJsonValue())
    base.put("sendSuccessCount", 0.toJsonValue())
    base.put("sendFailureCount", 0.toJsonValue())
    base.put("registeredAtMs", now.toJsonValue())
    base.put("lastStartAtMs", 0.toJsonValue())
    base.put("lastStopAtMs", 0.toJsonValue())
    base.put("lastPullAtMs", 0.toJsonValue())
    base.put("lastEventAtMs", 0.toJsonValue())
    base.put("lastSendAtMs", 0.toJsonValue())
    base.put("lastError", JsonString(""))
    base.put("backoffMs", 0.toJsonValue())
    base.put("nextRestartAtMs", 0.toJsonValue())
    base.put("configuredBinding", false.toJsonValue())
    base.put("primed", false.toJsonValue())
    base.put("autoEnabled", false.toJsonValue())
    base.put("bindingState", JsonString("unprimed"))
    base.put("primedAtMs", 0.toJsonValue())
    base.put("taskState", JsonString("idle"))
    base.put("taskGeneration", 0.toJsonValue())
    base.put("abortState", JsonString("clear"))
    base.put("monitorState", JsonString("disabled"))
    base.put("monitorEnabledAtMs", 0.toJsonValue())
    base.put("lastMonitorAtMs", 0.toJsonValue())
    base.put("restartBudget", 0.toJsonValue())
    base.put("restartBudgetState", JsonString("steady"))
    base.put("history", JsonArray([]))
    base
}

public func gatewayChannelRuntimePrimeAccounts(entries: JsonArray): Int64 {
    if (entries.size() == 0) {
        return 0
    }
    let root = gatewayChannelRuntimeReadState()
    let next = JsonArray([])
    let seen = HashSet<String>()
    var primedCount: Int64 = 0
    for (j in 0..entries.size()) {
        let spec = try { entries[j].asObject() } catch (_e: Exception) { JsonObject() }
        let channelId = channelRuntimeReadString(spec, "channelId", "").trimAscii().toAsciiLower()
        let accountId = channelRuntimeReadString(spec, "accountId", "default").trimAscii()
        if (channelId.isEmpty() || accountId.isEmpty()) {
            continue
        }
        let key = "${channelId}:${accountId}"
        if (seen.contains(key)) {
            continue
        }
        seen.add(key)
        let base = gatewayChannelRuntimeNewBaseAccountRow(channelId, accountId)
        next.add(gatewayChannelRuntimePrimeAccountFromRow(
            base,
            channelRuntimeReadBool(spec, "configuredBinding", true),
            channelRuntimeReadBool(spec, "autoEnabled", false),
            channelRuntimeReadString(spec, "detail", "configured-binding-primed")
        ))
        primedCount += 1
    }
    root.put("accounts", next)
    gatewayChannelRuntimeWriteState(root)
    primedCount
}

public func gatewayChannelRuntimeMarkBootstrap(
    channelIds: Array<String>,
    pluginIds: Array<String>,
    configuredBindings!: JsonArray = JsonArray([]),
    primedBindings!: JsonArray = JsonArray([]),
    configuredBindingCount!: Int64 = 0,
    primedBindingCount!: Int64 = 0
): JsonObject {
    let root = gatewayChannelRuntimeReadState()
    let bootstrap = JsonObject()
    let now = gatewayChannelRuntimeNowMs()
    bootstrap.put("bootstrapped", true.toJsonValue())
    bootstrap.put("bootstrappedAtMs", now.toJsonValue())
    bootstrap.put("channelIds", channelIds.toJsonValue())
    bootstrap.put("pluginIds", pluginIds.toJsonValue())
    bootstrap.put("configuredBindings", configuredBindings)
    bootstrap.put("primedBindings", primedBindings)
    bootstrap.put("configuredBindingCount", configuredBindingCount.toJsonValue())
    bootstrap.put("primedBindingCount", primedBindingCount.toJsonValue())
    root.put("bootstrap", bootstrap)
    gatewayChannelRuntimeWriteState(root)
    bootstrap
}

public func gatewayChannelRuntimeBootstrapSummary(): JsonObject {
    gatewayChannelRuntimeReadBootstrap(gatewayChannelRuntimeReadState())
}

public func gatewayChannelRuntimeMarkStarting(channelId: String, accountId!: String = "default"): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let startCount = channelRuntimeReadInt(row, "startCount", 0) + 1
        let history = match (row.get("history")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        let now = gatewayChannelRuntimeNowMs()
        out.put("running", false.toJsonValue())
        out.put("lifecycleState", JsonString("starting"))
        out.put("phase", JsonString("starting"))
        out.put("manualStop", false.toJsonValue())
        out.put("startCount", startCount.toJsonValue())
        out.put("lastStartAtMs", now.toJsonValue())
        out.put("taskState", JsonString("starting"))
        out.put("taskGeneration", (channelRuntimeReadInt(row, "taskGeneration", 0) + 1).toJsonValue())
        out.put("abortState", JsonString("clear"))
        out.put("history", channelRuntimeAppendHistory(history, "starting", "adapter-start"))
        out
    })
}

public func gatewayChannelRuntimeMarkRunning(channelId: String, accountId!: String = "default"): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let history = match (row.get("history")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        out.put("running", true.toJsonValue())
        out.put("lifecycleState", JsonString("running"))
        out.put("phase", JsonString("active"))
        out.put("manualStop", false.toJsonValue())
        out.put("backoffMs", 0.toJsonValue())
        out.put("nextRestartAtMs", 0.toJsonValue())
        out.put("taskState", JsonString("running"))
        out.put("abortState", JsonString("clear"))
        out.put("history", channelRuntimeAppendHistory(history, "running", "adapter-running"))
        out
    })
}

public func gatewayChannelRuntimeMarkStopped(channelId: String, accountId!: String = "default", reason!: String = "", manualStop!: Bool = false): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let stopCount = channelRuntimeReadInt(row, "stopCount", 0) + 1
        let history = match (row.get("history")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        let now = gatewayChannelRuntimeNowMs()
        out.put("running", false.toJsonValue())
        out.put("lifecycleState", JsonString("stopped"))
        out.put("phase", JsonString("idle"))
        out.put("manualStop", manualStop.toJsonValue())
        out.put("stopCount", stopCount.toJsonValue())
        out.put("lastStopAtMs", now.toJsonValue())
        out.put("taskState", JsonString("stopped"))
        out.put("abortState", JsonString(if (manualStop) { "manual-stop" } else { "clear" }))
        if (!reason.trimAscii().isEmpty()) {
            out.put("lastError", JsonString(reason.trimAscii()))
        }
        out.put("history", channelRuntimeAppendHistory(history, "stopped", if (reason.trimAscii().isEmpty()) { "adapter-stopped" } else { reason.trimAscii() }))
        out
    })
}

public func gatewayChannelRuntimeMarkFailure(
    channelId: String,
    accountId!: String = "default",
    lifecycleState!: String = "failed",
    error!: String = "",
    backoffMs!: Int64 = 0
): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let failureCount = channelRuntimeReadInt(row, "failureCount", 0) + 1
        let restartCount = channelRuntimeReadInt(row, "restartCount", 0) + if (backoffMs > 0) { 1 } else { 0 }
        let history = match (row.get("history")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        let now = gatewayChannelRuntimeNowMs()
        let state = lifecycleState.trimAscii()
        out.put("running", false.toJsonValue())
        out.put("lifecycleState", JsonString(state))
        out.put("phase", JsonString(channelRuntimePhase(state, false)))
        out.put("failureCount", failureCount.toJsonValue())
        out.put("restartCount", restartCount.toJsonValue())
        out.put("lastStopAtMs", now.toJsonValue())
        out.put("lastError", JsonString(error.trimAscii()))
        out.put("backoffMs", backoffMs.toJsonValue())
        out.put("nextRestartAtMs", if (backoffMs > 0) { (now + backoffMs).toJsonValue() } else { 0.toJsonValue() })
        out.put("taskState", JsonString(if (state == "backoff") { "recovering" } else { "failed" }))
        out.put("abortState", JsonString(if (channelRuntimeReadBool(row, "manualStop", false)) { "manual-stop" } else { "clear" }))
        let budget = channelRuntimeReadInt(row, "restartBudget", 0) + if (backoffMs > 0) { 1 } else { 0 }
        out.put("restartBudget", budget.toJsonValue())
        out.put(
            "restartBudgetState",
            JsonString(
                if (channelRuntimeReadBool(row, "manualStop", false)) {
                    "suppressed"
                } else if (budget > 3) {
                    "exhausted"
                } else if (backoffMs > 0) {
                    "budgeting"
                } else {
                    "steady"
                }
            )
        )
        out.put("history", channelRuntimeAppendHistory(history, state, if (error.trimAscii().isEmpty()) { "runtime-failure" } else { error.trimAscii() }))
        out
    })
}

public func gatewayChannelRuntimeMarkInboundFailure(
    channelId: String,
    accountId!: String = "default",
    error!: String = ""
): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let failureCount = channelRuntimeReadInt(row, "failureCount", 0) + 1
        let history = match (row.get("history")) { case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) } case None => JsonArray([]) }
        let now = gatewayChannelRuntimeNowMs()
        out.put("running", true.toJsonValue())
        out.put("lifecycleState", JsonString("running"))
        out.put("phase", JsonString("active"))
        out.put("failureCount", failureCount.toJsonValue())
        out.put("lastEventAtMs", now.toJsonValue())
        out.put("lastError", JsonString(error.trimAscii()))
        out.put("backoffMs", 0.toJsonValue())
        out.put("nextRestartAtMs", 0.toJsonValue())
        out.put("taskState", JsonString("running"))
        out.put("abortState", JsonString("clear"))
        out.put("history", channelRuntimeAppendHistory(history, "turn-failed", if (error.trimAscii().isEmpty()) { "inbound-turn-failed" } else { error.trimAscii() }))
        out
    })
}

public func gatewayChannelRuntimeMarkPull(channelId: String, accountId!: String = "default", inboundCount!: Int64 = 0): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let pulls = channelRuntimeReadInt(row, "pullCount", 0) + 1
        let events = channelRuntimeReadInt(row, "inboundCount", 0) + if (inboundCount > 0) { inboundCount } else { 0 }
        let now = gatewayChannelRuntimeNowMs()
        out.put("pullCount", pulls.toJsonValue())
        out.put("lastPullAtMs", now.toJsonValue())
        out.put("inboundCount", events.toJsonValue())
        if (inboundCount > 0) {
            out.put("lastEventAtMs", now.toJsonValue())
        }
        out
    })
}

public func gatewayChannelRuntimeMarkSend(channelId: String, accountId!: String = "default", success!: Bool = true, detail!: String = ""): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let now = gatewayChannelRuntimeNowMs()
        out.put("lastSendAtMs", now.toJsonValue())
        if (success) {
            out.put("sendSuccessCount", (channelRuntimeReadInt(row, "sendSuccessCount", 0) + 1).toJsonValue())
        } else {
            out.put("sendFailureCount", (channelRuntimeReadInt(row, "sendFailureCount", 0) + 1).toJsonValue())
            out.put("lastError", JsonString(detail.trimAscii()))
        }
        out
    })
}

public func gatewayChannelRuntimeMarkMonitorEnabled(
    channelId: String,
    accountId!: String = "default",
    enabled!: Bool = true
): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        let now = gatewayChannelRuntimeNowMs()
        out.put("monitorState", JsonString(if (enabled) { "enabled" } else { "disabled" }))
        out.put("monitorEnabledAtMs", if (enabled) { now.toJsonValue() } else { 0.toJsonValue() })
        out.put("lastMonitorAtMs", now.toJsonValue())
        out
    })
}

public func gatewayChannelRuntimeMarkMonitorTick(channelId: String, accountId!: String = "default"): JsonObject {
    channelRuntimeUpsertAccount(channelId, accountId, { row =>
        let out = channelRuntimeCloneRow(row)
        out.put("lastMonitorAtMs", gatewayChannelRuntimeNowMs().toJsonValue())
        out
    })
}

public func gatewayChannelRuntimeCanStart(channelId: String, accountId!: String = "default"): Bool {
    let accounts = gatewayChannelRuntimeAccountsJson(channelId)
    let normalizedAccount = accountId.trimAscii()
    let now = gatewayChannelRuntimeNowMs()
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (channelRuntimeReadString(row, "accountId", "") != normalizedAccount) {
            continue
        }
        if (channelRuntimeReadBool(row, "manualStop", false)) {
            return false
        }
        let nextRestartAtMs = channelRuntimeReadInt(row, "nextRestartAtMs", 0)
        if (nextRestartAtMs > now) {
            return false
        }
        let budget = channelRuntimeReadInt(row, "restartBudget", 0)
        if (budget > 3) {
            return false
        }
        return true
    }
    true
}

public func gatewayChannelRuntimeSnapshot(): JsonObject {
    gatewayChannelRuntimeReadState()
}

public func gatewayChannelRuntimeAccountsJson(channelId: String): JsonArray {
    let out = JsonArray([])
    let normalized = channelId.trimAscii().toAsciiLower()
    let accounts = channelRuntimeReadAccounts(gatewayChannelRuntimeReadState())
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (channelRuntimeReadString(row, "channelId", "") == normalized) {
            out.add(row)
        }
    }
    out
}

public func gatewayPluginRuntimeAccountsJson(pluginId: String): JsonArray {
    let out = JsonArray([])
    let normalized = pluginId.trimAscii().toAsciiLower()
    let accounts = channelRuntimeReadAccounts(gatewayChannelRuntimeReadState())
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (channelRuntimeReadString(row, "pluginId", "") == normalized) {
            out.add(row)
        }
    }
    out
}

public func gatewayChannelRuntimeDefaultAccountId(channelId: String): JsonValue {
    let accounts = gatewayChannelRuntimeAccountsJson(channelId)
    if (accounts.size() == 0) {
        return JsonString("")
    }
    try {
        let first = accounts[0].asObject()
        return JsonString(channelRuntimeReadString(first, "accountId", ""))
    } catch (_e: Exception) {
        return JsonString("")
    }
}

public func gatewayChannelRuntimeSummary(channelId: String): JsonObject {
    let out = JsonObject()
    let accounts = gatewayChannelRuntimeAccountsJson(channelId)
    var runningCount: Int64 = 0
    var backoffCount: Int64 = 0
    var failedCount: Int64 = 0
    var totalStarts: Int64 = 0
    var totalStops: Int64 = 0
    var totalRestarts: Int64 = 0
    var monitorEnabled: Int64 = 0
    var manualStopCount: Int64 = 0
    var exhaustedBudgetCount: Int64 = 0
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (channelRuntimeReadBool(row, "running", false)) {
            runningCount += 1
        }
        let lifecycleState = channelRuntimeReadString(row, "lifecycleState", "")
        if (lifecycleState == "backoff") {
            backoffCount += 1
        }
        if (lifecycleState == "failed") {
            failedCount += 1
        }
        totalStarts += channelRuntimeReadInt(row, "startCount", 0)
        totalStops += channelRuntimeReadInt(row, "stopCount", 0)
        totalRestarts += channelRuntimeReadInt(row, "restartCount", 0)
        if (channelRuntimeReadString(row, "monitorState", "disabled") == "enabled") {
            monitorEnabled += 1
        }
        if (channelRuntimeReadBool(row, "manualStop", false)) {
            manualStopCount += 1
        }
        if (channelRuntimeReadString(row, "restartBudgetState", "steady") == "exhausted") {
            exhaustedBudgetCount += 1
        }
    }
    out.put("count", accounts.size().toJsonValue())
    out.put("running", runningCount.toJsonValue())
    out.put("backoff", backoffCount.toJsonValue())
    out.put("failed", failedCount.toJsonValue())
    out.put("startCount", totalStarts.toJsonValue())
    out.put("stopCount", totalStops.toJsonValue())
    out.put("restartCount", totalRestarts.toJsonValue())
    out.put("monitorEnabledCount", monitorEnabled.toJsonValue())
    out.put("manualStopCount", manualStopCount.toJsonValue())
    out.put("exhaustedBudgetCount", exhaustedBudgetCount.toJsonValue())
    out.put("accounts", accounts)
    out.put("defaultAccountId", gatewayChannelRuntimeDefaultAccountId(channelId))
    out.put("bootstrap", gatewayChannelRuntimeBootstrapSummary())
    out
}

public func gatewayPluginRuntimeSummary(pluginId: String): JsonObject {
    let out = JsonObject()
    let accounts = gatewayPluginRuntimeAccountsJson(pluginId)
    var runningCount: Int64 = 0
    var failureCount: Int64 = 0
    var monitorEnabled: Int64 = 0
    var manualStopCount: Int64 = 0
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (channelRuntimeReadBool(row, "running", false)) {
            runningCount += 1
        }
        failureCount += channelRuntimeReadInt(row, "failureCount", 0)
        if (channelRuntimeReadString(row, "monitorState", "disabled") == "enabled") {
            monitorEnabled += 1
        }
        if (channelRuntimeReadBool(row, "manualStop", false)) {
            manualStopCount += 1
        }
    }
    out.put("count", accounts.size().toJsonValue())
    out.put("running", runningCount.toJsonValue())
    out.put("failureCount", failureCount.toJsonValue())
    out.put("monitorEnabledCount", monitorEnabled.toJsonValue())
    out.put("manualStopCount", manualStopCount.toJsonValue())
    out.put("accounts", accounts)
    out.put("bootstrap", gatewayChannelRuntimeBootstrapSummary())
    out
}

private func channelRuntimeLatestRow(accounts: JsonArray): JsonObject {
    var latest = JsonObject()
    var latestTs: Int64 = -1
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        let rowTs = max(
            channelRuntimeReadInt(row, "lastEventAtMs", 0),
            max(
                channelRuntimeReadInt(row, "lastMonitorAtMs", 0),
                max(
                    channelRuntimeReadInt(row, "lastStopAtMs", 0),
                    max(
                        channelRuntimeReadInt(row, "lastSendAtMs", 0),
                        channelRuntimeReadInt(row, "lastStartAtMs", 0)
                    )
                )
            )
        )
        if (rowTs >= latestTs) {
            latestTs = rowTs
            latest = row
        }
    }
    latest
}

private func channelRuntimeRepresentativeString(
    accounts: JsonArray,
    key: String,
    priorities: Array<String>,
    defaultValue: String
): String {
    for (priority in priorities) {
        for (i in 0..accounts.size()) {
            let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
            if (channelRuntimeReadString(row, key, "") == priority) {
                return priority
            }
        }
    }
    if (accounts.size() > 0) {
        let latest = channelRuntimeLatestRow(accounts)
        let value = channelRuntimeReadString(latest, key, defaultValue)
        if (!value.isEmpty()) {
            return value
        }
    }
    defaultValue
}

private func channelRuntimeMaxInt(accounts: JsonArray, key: String): Int64 {
    var out: Int64 = 0
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        out = max(out, channelRuntimeReadInt(row, key, 0))
    }
    out
}

private func channelRuntimeMinPositiveInt(accounts: JsonArray, key: String): Int64 {
    var out: Int64 = 0
    for (i in 0..accounts.size()) {
        let row = try { accounts[i].asObject() } catch (_e: Exception) { JsonObject() }
        let value = channelRuntimeReadInt(row, key, 0)
        if (value <= 0) {
            continue
        }
        if (out <= 0 || value < out) {
            out = value
        }
    }
    out
}

private func channelRuntimeLatestError(accounts: JsonArray): String {
    let latest = channelRuntimeLatestRow(accounts)
    let latestError = channelRuntimeReadString(latest, "lastError", "")
    if (!latestError.isEmpty()) {
        return latestError
    }
    for (idx in accounts.size() - 1..=0:-1) {
        let row = try { accounts[idx].asObject() } catch (_e: Exception) { JsonObject() }
        let error = channelRuntimeReadString(row, "lastError", "")
        if (!error.isEmpty()) {
            return error
        }
    }
    ""
}

public func gatewayChannelManagerSummary(channelId: String): JsonObject {
    let summary = gatewayChannelRuntimeSummary(channelId)
    let out = JsonObject()
    let accounts = match (summary.get("accounts")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let taskState = channelRuntimeRepresentativeString(accounts, "taskState", ["running", "starting", "recovering", "failed", "stopped", "idle"], "idle")
    let lifecycleState = channelRuntimeRepresentativeString(accounts, "lifecycleState", ["running", "starting", "backoff", "failed", "stopped", "registered"], "registered")
    let phase = channelRuntimeRepresentativeString(accounts, "phase", ["active", "starting", "backoff", "failed", "idle", "registered"], "registered")
    let monitorState = channelRuntimeRepresentativeString(accounts, "monitorState", ["enabled", "disabled"], "disabled")
    let abortState = channelRuntimeRepresentativeString(accounts, "abortState", ["manual-stop", "clear"], "clear")
    let restartBudgetState = channelRuntimeRepresentativeString(accounts, "restartBudgetState", ["exhausted", "budgeting", "suppressed", "steady"], "steady")
    out.put("channelId", JsonString(channelId.trimAscii().toAsciiLower()))
    out.put("count", summary.get("count") ?? 0.toJsonValue())
    out.put("running", summary.get("running") ?? 0.toJsonValue())
    out.put("backoff", summary.get("backoff") ?? 0.toJsonValue())
    out.put("failed", summary.get("failed") ?? 0.toJsonValue())
    out.put("startCount", summary.get("startCount") ?? 0.toJsonValue())
    out.put("stopCount", summary.get("stopCount") ?? 0.toJsonValue())
    out.put("restartCount", summary.get("restartCount") ?? 0.toJsonValue())
    out.put("monitorEnabledCount", summary.get("monitorEnabledCount") ?? 0.toJsonValue())
    out.put("manualStopCount", summary.get("manualStopCount") ?? 0.toJsonValue())
    out.put("exhaustedBudgetCount", summary.get("exhaustedBudgetCount") ?? 0.toJsonValue())
    out.put("lifecycleState", JsonString(lifecycleState))
    out.put("phase", JsonString(phase))
    out.put("taskState", JsonString(taskState))
    out.put("taskGeneration", channelRuntimeMaxInt(accounts, "taskGeneration").toJsonValue())
    out.put("monitorState", JsonString(monitorState))
    out.put("monitorEnabledAtMs", channelRuntimeMaxInt(accounts, "monitorEnabledAtMs").toJsonValue())
    out.put("lastMonitorAtMs", channelRuntimeMaxInt(accounts, "lastMonitorAtMs").toJsonValue())
    out.put("abortState", JsonString(abortState))
    out.put("lastEventAtMs", channelRuntimeMaxInt(accounts, "lastEventAtMs").toJsonValue())
    out.put("lastError", JsonString(channelRuntimeLatestError(accounts)))
    out.put("nextRestartAtMs", channelRuntimeMinPositiveInt(accounts, "nextRestartAtMs").toJsonValue())
    out.put("restartBudget", channelRuntimeMaxInt(accounts, "restartBudget").toJsonValue())
    out.put("restartBudgetState", JsonString(restartBudgetState))
    out.put("accounts", summary.get("accounts") ?? JsonArray([]))
    out.put("defaultAccountId", summary.get("defaultAccountId") ?? JsonString(""))
    out.put("bootstrap", summary.get("bootstrap") ?? JsonObject())
    out
}

public func gatewayPluginManagerSummary(pluginId: String): JsonObject {
    let summary = gatewayPluginRuntimeSummary(pluginId)
    let out = JsonObject()
    let accounts = match (summary.get("accounts")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let taskState = channelRuntimeRepresentativeString(accounts, "taskState", ["running", "starting", "recovering", "failed", "stopped", "idle"], "idle")
    let lifecycleState = channelRuntimeRepresentativeString(accounts, "lifecycleState", ["running", "starting", "backoff", "failed", "stopped", "registered"], "registered")
    let phase = channelRuntimeRepresentativeString(accounts, "phase", ["active", "starting", "backoff", "failed", "idle", "registered"], "registered")
    let monitorState = channelRuntimeRepresentativeString(accounts, "monitorState", ["enabled", "disabled"], "disabled")
    let abortState = channelRuntimeRepresentativeString(accounts, "abortState", ["manual-stop", "clear"], "clear")
    let restartBudgetState = channelRuntimeRepresentativeString(accounts, "restartBudgetState", ["exhausted", "budgeting", "suppressed", "steady"], "steady")
    out.put("pluginId", JsonString(pluginId.trimAscii().toAsciiLower()))
    out.put("count", summary.get("count") ?? 0.toJsonValue())
    out.put("running", summary.get("running") ?? 0.toJsonValue())
    out.put("failureCount", summary.get("failureCount") ?? 0.toJsonValue())
    out.put("monitorEnabledCount", summary.get("monitorEnabledCount") ?? 0.toJsonValue())
    out.put("manualStopCount", summary.get("manualStopCount") ?? 0.toJsonValue())
    out.put("lifecycleState", JsonString(lifecycleState))
    out.put("phase", JsonString(phase))
    out.put("taskState", JsonString(taskState))
    out.put("taskGeneration", channelRuntimeMaxInt(accounts, "taskGeneration").toJsonValue())
    out.put("monitorState", JsonString(monitorState))
    out.put("monitorEnabledAtMs", channelRuntimeMaxInt(accounts, "monitorEnabledAtMs").toJsonValue())
    out.put("lastMonitorAtMs", channelRuntimeMaxInt(accounts, "lastMonitorAtMs").toJsonValue())
    out.put("abortState", JsonString(abortState))
    out.put("lastEventAtMs", channelRuntimeMaxInt(accounts, "lastEventAtMs").toJsonValue())
    out.put("lastError", JsonString(channelRuntimeLatestError(accounts)))
    out.put("nextRestartAtMs", channelRuntimeMinPositiveInt(accounts, "nextRestartAtMs").toJsonValue())
    out.put("restartBudget", channelRuntimeMaxInt(accounts, "restartBudget").toJsonValue())
    out.put("restartBudgetState", JsonString(restartBudgetState))
    out.put("accounts", summary.get("accounts") ?? JsonArray([]))
    out.put("bootstrap", summary.get("bootstrap") ?? JsonObject())
    out
}
