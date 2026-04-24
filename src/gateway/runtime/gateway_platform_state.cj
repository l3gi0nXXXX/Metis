package metis.gateway.runtime

import magic.jsonable.*
import magic.log.LogUtils

import metis.core.config.CliConfig
import metis.core.config.CliSettingManager
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.model.GatewayConfig

import std.convert.Parsable
import std.fs.{File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

public func gatewayPlatformStatePath(): String {
    CliConfig.dotDir.join("gateway-platform-state.json").toString()
}

public func gatewayNodeRegistryPath(): String {
    CliConfig.dotDir.join("gateway-node-registry.json").toString()
}

public func gatewayPendingWorkPath(): String {
    CliConfig.dotDir.join("gateway-pending-work.json").toString()
}

public func gatewayPushDeliveriesPath(): String {
    CliConfig.dotDir.join("gateway-push-deliveries.json").toString()
}

private func readPlatformState(): JsonObject {
    let path = CliConfig.dotDir.join("gateway-platform-state.json")
    if (!exists(path)) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func writePlatformState(root: JsonObject): Unit {
    let path = CliConfig.dotDir.join("gateway-platform-state.json")
    File.writeTo(path, root.toJsonString().toArray())
}

private func readJsonObjectFile(path: String): JsonObject {
    let file = Path(path)
    if (!exists(file)) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(file))).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func writeJsonObjectFile(path: String, root: JsonObject): Unit {
    File.writeTo(Path(path), root.toJsonString().toArray())
}

private func localNodeId(): String {
    "local-gateway"
}

private func readJsonString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func readJsonInt(obj: JsonObject, key: String, defaultValue: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func readJsonBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private const GATEWAY_PLATFORM_HISTORY_LIMIT: Int64 = 64

private func appendLifecycleHistory(history: JsonArray, state: String, status: String, detail!: String = ""): JsonArray {
    let out = JsonArray([])
    let historySize = history.size()
    var start = 0
    if (Int64(historySize) >= GATEWAY_PLATFORM_HISTORY_LIMIT) {
        start = historySize - GATEWAY_PLATFORM_HISTORY_LIMIT + 1
    }
    for (i in start..historySize) {
        out.add(history[i])
    }
    let row = JsonObject()
    row.put("state", JsonString(state))
    row.put("status", JsonString(status))
    row.put("detail", JsonString(detail))
    row.put("ts", nowMs().toJsonValue())
    out.add(row)
    let nextSize = out.size()
    if (nextSize == 1 || nextSize % 100 == 0) {
        LogUtils.info(
            "Gateway.platform: lifecycle history append size=${nextSize} state=${state} status=${status} detail=${detail}"
        )
    }
    out
}

private func gatewayNodePhase(lifecycleState: String, running: Bool, status: String): String {
    if (lifecycleState == "restarting") {
        return "restarting"
    }
    if (running && status == "online") {
        return "active"
    }
    if (!running && status == "offline") {
        return "idle"
    }
    return "transitioning"
}

private func gatewayPendingWorkPhase(lifecycleState: String, status: String): String {
    if (lifecycleState == "retrying") {
        return "backoff"
    }
    if (lifecycleState == "claimed" || status == "claimed") {
        return "executing"
    }
    if (lifecycleState == "failed" || status == "failed") {
        return "failed"
    }
    if (lifecycleState == "completed" || status == "completed") {
        return "done"
    }
    return "dispatch"
}

private func gatewayDevicePhase(authState: String, status: String, lifecycleState: String): String {
    if (authState == "revoked" || lifecycleState == "unregistered") {
        return "revoked"
    }
    if (authState == "revalidating" || lifecycleState == "revalidating") {
        return "revalidating"
    }
    if (lifecycleState == "recovered") {
        return "trusted"
    }
    if (status == "active" && authState == "validated") {
        return "trusted"
    }
    if (status == "active") {
        return "active"
    }
    return "inactive"
}

private func gatewayNodeSchedulingDecision(node: JsonObject): String {
    let running = readJsonBool(node, "running", false)
    let status = readJsonString(node, "status", "")
    let browserMode = readJsonString(node, "browserMode", "auto")
    let allowCount = match (node.get("allowCommands")) {
        case Some(v) =>
            try { Int64(v.asArray().size()) } catch (_e: Exception) { 0 }
        case None => 0
    }
    let denyCount = match (node.get("denyCommands")) {
        case Some(v) =>
            try { Int64(v.asArray().size()) } catch (_e: Exception) { 0 }
        case None => 0
    }
    if (denyCount > 0 && allowCount == 0) {
        return "denied"
    }
    if (browserMode == "disabled") {
        return "browser-disabled"
    }
    if (running && status == "online") {
        return "dispatch"
    }
    if (!running && status == "offline") {
        return "wake"
    }
    return "hold"
}

private func gatewayDeviceApprovalState(row: JsonObject): String {
    let explicit = readJsonString(row, "approvalState", "")
    if (!explicit.isEmpty()) {
        return explicit
    }
    let lifecycleState = readJsonString(row, "lifecycleState", "")
    let authState = readJsonString(row, "authState", "")
    let status = readJsonString(row, "status", "")
    if (authState == "revoked") {
        return "denied"
    }
    if (authState == "revalidating" || lifecycleState == "revalidating") {
        return "pending"
    }
    if (status == "active" && (authState == "validated" || authState == "refreshed")) {
        return "approved"
    }
    if (lifecycleState == "recovered") {
        return "recovered"
    }
    return "inactive"
}

private func gatewayJsonArrayContains(arr: JsonValue, target: String): Bool {
    try {
        let items = arr.asArray()
        for (i in 0..items.size()) {
            let item = try { items[i].asString().getValue() } catch (_e: Exception) { "" }
            if (item == target || item == "*") {
                return true
            }
        }
    } catch (_e: Exception) {
        return false
    }
    false
}

private func gatewayNodeAllowsWork(node: JsonObject, workKind: String): Bool {
    let deny = match (node.get("denyCommands")) {
        case Some(v) => gatewayJsonArrayContains(v, workKind)
        case None => false
    }
    if (deny) {
        return false
    }
    let allow = match (node.get("allowCommands")) {
        case Some(v) =>
            try { v.asArray().size() > 0 } catch (_e: Exception) { false }
        case None => false
    }
    if (!allow) {
        return true
    }
    match (node.get("allowCommands")) {
        case Some(v) => gatewayJsonArrayContains(v, workKind)
        case None => true
    }
}

private func gatewayFindNodeById(cfg: GatewayConfig, nodeId: String): JsonObject {
    let snapshot = gatewayNodeRegistrySnapshot(cfg, false)
    let nodesRoot = match (snapshot.get("nodes")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (nodesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (readJsonString(row, "id", "") == nodeId) {
            return row
        }
    }
    JsonObject()
}

private func gatewayPushPhase(lifecycleState: String, status: String): String {
    if (lifecycleState == "failed" || status == "failed") {
        return "failed"
    }
    if (lifecycleState == "retried" || status == "retried") {
        return "retrying"
    }
    if (lifecycleState == "sent" || status == "sent") {
        return "delivered"
    }
    return "queued"
}

private func makeNodesJson(cfg: GatewayConfig, running: Bool): JsonObject {
    let registry = gatewayNodeRegistrySnapshot(cfg, running)
    match (registry.get("nodes")) {
        case Some(v) =>
            try { return v.asObject() } catch (_e: Exception) { () }
        case None => ()
    }
    let localNode = JsonObject()
    localNode.put("id", JsonString(localNodeId()))
    localNode.put("kind", JsonString("local"))
    localNode.put("running", running.toJsonValue())
    localNode.put("status", JsonString(if (running) { "online" } else { "offline" }))
    localNode.put("lifecycleState", JsonString(if (running) { "running" } else { "stopped" }))
    localNode.put("phase", JsonString(gatewayNodePhase(if (running) { "running" } else { "stopped" }, running, if (running) { "online" } else { "offline" })))
    localNode.put("lastHeartbeatAtMs", nowMs().toJsonValue())
    localNode.put("browserMode", JsonString(cfg.nodes.browser.mode))
    localNode.put("browserNode", JsonString(cfg.nodes.browser.node))
    localNode.put("allowCommands", cfg.nodes.allowCommands.toJsonValue())
    localNode.put("denyCommands", cfg.nodes.denyCommands.toJsonValue())
    let rows = JsonArray([])
    rows.add(localNode)
    let root = JsonObject()
    root.put("count", 1.toJsonValue())
    root.put("items", rows)
    root
}

private func makeDevicesJson(cfg: GatewayConfig): JsonObject {
    let existing = readPlatformState()
    match (existing.get("devices")) {
        case Some(v) =>
            try { return v.asObject() } catch (_e: Exception) { () }
        case None => ()
    }
    let items = JsonArray([])
    var count: Int64 = 0
    if (cfg.controlUi.enabled) {
        let now = nowMs()
        let browser = JsonObject()
        browser.put("id", JsonString("browser-control-ui"))
        browser.put("kind", JsonString("browser"))
        browser.put("authMode", JsonString(if (cfg.controlUi.dangerouslyDisableDeviceAuth) { "disabled" } else { "device-auth" }))
        browser.put("controlUiEnabled", cfg.controlUi.enabled.toJsonValue())
        browser.put("status", JsonString("active"))
        browser.put("lifecycleState", JsonString("registered"))
        browser.put("registeredAtMs", now.toJsonValue())
        browser.put("lastSeenAtMs", now.toJsonValue())
        browser.put("authState", JsonString(if (cfg.controlUi.dangerouslyDisableDeviceAuth) { "disabled" } else { "validated" }))
        browser.put("approvalState", JsonString("approved"))
        browser.put("phase", JsonString(gatewayDevicePhase(if (cfg.controlUi.dangerouslyDisableDeviceAuth) { "disabled" } else { "validated" }, "active", "registered")))
        browser.put("authTransitionCount", 1.toJsonValue())
        let authHistory = JsonArray([])
        let authRow = JsonObject()
        authRow.put("atMs", now.toJsonValue())
        authRow.put("authState", browser.get("authState") ?? JsonString("validated"))
        authRow.put("status", JsonString("active"))
        authHistory.add(authRow)
        browser.put("authHistory", authHistory)
        items.add(browser)
        count += 1
    }
    let root = JsonObject()
    root.put("count", count.toJsonValue())
    root.put("items", items)
    root
}

private func makePushJson(cfg: GatewayConfig): JsonObject {
    let deliveries = gatewayPushDeliverySnapshot()
    let items = match (deliveries.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let root = JsonObject()
    let apns = JsonObject()
    apns.put("relayBaseUrl", JsonString(cfg.push.apns.relay.baseUrl))
    apns.put("relayTimeoutMs", cfg.push.apns.relay.timeoutMs.toJsonValue())
    apns.put("configured", (!cfg.push.apns.relay.baseUrl.trimAscii().isEmpty()).toJsonValue())
    root.put("apns", apns)
    root.put("deliveries", items)
    root.put("deliveryCount", deliveries.get("count") ?? 0.toJsonValue())
    let byStatus = JsonObject()
    let byLifecycleState = JsonObject()
    var retryCount: Int64 = 0
    var failedCount: Int64 = 0
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let status = readJsonString(row, "status", "")
        let lifecycleState = readJsonString(row, "lifecycleState", status)
        let retries = readJsonInt(row, "retryCount", 0)
        if (retries > 0) {
            retryCount += 1
        }
        if (status == "failed" || lifecycleState == "failed") {
            failedCount += 1
        }
        let currentStatus = match (byStatus.get(status)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byStatus.put(status, (currentStatus + 1).toJsonValue())
        let currentLifecycle = match (byLifecycleState.get(lifecycleState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byLifecycleState.put(lifecycleState, (currentLifecycle + 1).toJsonValue())
    }
    let summary = JsonObject()
    summary.put("retryingDeliveries", retryCount.toJsonValue())
    summary.put("failedDeliveries", failedCount.toJsonValue())
    summary.put("byStatus", byStatus)
    summary.put("byLifecycleState", byLifecycleState)
    root.put("summary", summary)
    root
}

private func makeUsageJson(): JsonObject {
    let root = JsonObject()
    root.put("promptTokens", 0.toJsonValue())
    root.put("completionTokens", 0.toJsonValue())
    root.put("totalTokens", 0.toJsonValue())
    root.put("costUsd", JsonString("0"))
    root
}

private func makeSecretsJson(cfg: GatewayConfig): JsonObject {
    let root = JsonObject()
    let auth = JsonObject()
    auth.put("hasGatewayToken", cfg.auth.token.isSome().toJsonValue())
    auth.put("hasGatewayPassword", cfg.auth.password.isSome().toJsonValue())
    auth.put("hasRemoteToken", cfg.remote.token.isSome().toJsonValue())
    auth.put("hasRemotePassword", cfg.remote.password.isSome().toJsonValue())
    root.put("auth", auth)
    root
}

private func makeCanvasJson(cfg: GatewayConfig): JsonObject {
    let root = JsonObject()
    let rootConfigured = !cfg.canvas.root.trimAscii().isEmpty()
    let enabled = cfg.canvas.enabled
    root.put("enabled", cfg.canvas.enabled.toJsonValue())
    root.put("root", JsonString(cfg.canvas.root))
    root.put("port", cfg.canvas.port.toJsonValue())
    root.put("liveReload", cfg.canvas.liveReload.toJsonValue())
    root.put("rootPresent", rootConfigured.toJsonValue())
    root.put("assetState", JsonString(if (!enabled) { "disabled" } else if (rootConfigured) { "mounted" } else { "missing-root" }))
    root.put("watchState", JsonString(if (!enabled) { "disabled" } else if (cfg.canvas.liveReload) { "watching" } else { "static" }))
    root.put("phase", JsonString(if (!enabled) { "disabled" } else if (rootConfigured) { "ready" } else { "misconfigured" }))
    root.put("healthy", (enabled && rootConfigured).toJsonValue())
    root.put("httpUrl", JsonString(if (enabled) { "http://127.0.0.1:${cfg.canvas.port}/" } else { "" }))
    root
}

private func makeTalkJson(cfg: GatewayConfig): JsonObject {
    let root = JsonObject()
    let providerConfigured = !cfg.talk.provider.trimAscii().isEmpty()
    root.put("provider", JsonString(cfg.talk.provider))
    root.put("providerConfigured", providerConfigured.toJsonValue())
    root.put("interruptOnSpeech", cfg.talk.interruptOnSpeech.toJsonValue())
    root.put("silenceTimeoutMs", cfg.talk.silenceTimeoutMs.toJsonValue())
    root.put("inputState", JsonString(if (providerConfigured) { "listening" } else { "disabled" }))
    root.put("outputState", JsonString(if (providerConfigured) { "speaking" } else { "disabled" }))
    root.put("phase", JsonString(if (providerConfigured) { "ready" } else { "disabled" }))
    root.put("healthy", providerConfigured.toJsonValue())
    root
}

private func buildPlatformState(cfg: GatewayConfig, running: Bool): JsonObject {
    let root = JsonObject()
    root.put("running", running.toJsonValue())
    root.put("updatedAtMs", nowMs().toJsonValue())
    root.put("nodes", makeNodesJson(cfg, running))
    root.put("devices", makeDevicesJson(cfg))
    root.put("push", makePushJson(cfg))
    root.put("usage", makeUsageJson())
    root.put("secrets", makeSecretsJson(cfg))
    root.put("canvas", makeCanvasJson(cfg))
    root.put("talk", makeTalkJson(cfg))
    root
}

public func gatewayNodeRegistrySnapshot(cfg: GatewayConfig, running: Bool): JsonObject {
    let root = readJsonObjectFile(gatewayNodeRegistryPath())
    match (root.get("nodes")) {
        case Some(_) => return root
        case None => ()
    }
    let localNode = JsonObject()
    localNode.put("id", JsonString(localNodeId()))
    localNode.put("kind", JsonString("local"))
    localNode.put("running", running.toJsonValue())
    localNode.put("status", JsonString(if (running) { "online" } else { "offline" }))
    localNode.put("lifecycleState", JsonString(if (running) { "running" } else { "stopped" }))
    localNode.put("lastHeartbeatAtMs", nowMs().toJsonValue())
    localNode.put("browserMode", JsonString(cfg.nodes.browser.mode))
    localNode.put("browserNode", JsonString(cfg.nodes.browser.node))
    localNode.put("allowCommands", cfg.nodes.allowCommands.toJsonValue())
    localNode.put("denyCommands", cfg.nodes.denyCommands.toJsonValue())
    let rows = JsonArray([])
    rows.add(localNode)
    let nodes = JsonObject()
    nodes.put("count", 1.toJsonValue())
    nodes.put("items", rows)
    let out = JsonObject()
    out.put("updatedAtMs", nowMs().toJsonValue())
    out.put("nodes", nodes)
    out
}

public func gatewayRegisterOrHeartbeatNode(
    cfg: GatewayConfig,
    nodeId: String,
    running!: Bool = true,
    kind!: String = "local",
    status!: String = "online",
    lifecycleState!: String = "running"
): JsonObject {
    let snapshot = gatewayNodeRegistrySnapshot(cfg, running)
    let nodes = match (snapshot.get("nodes")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (nodes.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let normalizedNodeId = nodeId.trimAscii()
    let updated = JsonArray([])
    var found = false
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let existingId = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (existingId == normalizedNodeId) {
            let previousLifecycleState = readJsonString(obj, "lifecycleState", "")
            let previousRunning = match (obj.get("running")) {
                case Some(v) =>
                    try { v.asBool().getValue() } catch (_e: Exception) { false }
                case None => false
            }
            let history = match (obj.get("lifecycleHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let transitionCountBase = readJsonInt(obj, "transitionCount", 0)
            let restartCountBase = readJsonInt(obj, "restartCount", 0)
            let heartbeatCountBase = readJsonInt(obj, "heartbeatCount", 0)
            let registeredAtMs = readJsonInt(obj, "registeredAtMs", nowMs())
            let lifecycleChanged = previousLifecycleState != lifecycleState
            let runningChanged = previousRunning != running
            let nextTransitionCount = transitionCountBase + if (lifecycleChanged || runningChanged) { 1 } else { 0 }
            let nextRestartCount = restartCountBase + if (lifecycleState == "restarting") { 1 } else { 0 }
            let nextHeartbeatCount = heartbeatCountBase + 1
            let row = JsonObject()
            row.put("id", JsonString(normalizedNodeId))
            row.put("kind", JsonString(kind))
            row.put("running", running.toJsonValue())
            row.put("status", JsonString(status))
            row.put("lifecycleState", JsonString(lifecycleState))
            row.put("phase", JsonString(gatewayNodePhase(lifecycleState, running, status)))
            row.put("browserMode", JsonString(cfg.nodes.browser.mode))
            row.put("browserNode", JsonString(cfg.nodes.browser.node))
            row.put("allowCommands", cfg.nodes.allowCommands.toJsonValue())
            row.put("denyCommands", cfg.nodes.denyCommands.toJsonValue())
            row.put("registeredAtMs", registeredAtMs.toJsonValue())
            row.put("lastHeartbeatAtMs", nowMs().toJsonValue())
            row.put("lastStartedAtMs", if (running) { nowMs().toJsonValue() } else { obj.get("lastStartedAtMs") ?? 0.toJsonValue() })
            row.put("lastStoppedAtMs", if (!running) { nowMs().toJsonValue() } else { obj.get("lastStoppedAtMs") ?? 0.toJsonValue() })
            row.put("transitionCount", nextTransitionCount.toJsonValue())
            row.put("restartCount", nextRestartCount.toJsonValue())
            row.put("heartbeatCount", nextHeartbeatCount.toJsonValue())
            row.put("lifecycleHistory", appendLifecycleHistory(history, lifecycleState, status, detail: if (lifecycleChanged || runningChanged) { "state-change" } else { "heartbeat" }))
            if (nextHeartbeatCount == 1 || nextHeartbeatCount % 100 == 0 || lifecycleChanged || runningChanged) {
                LogUtils.info(
                    "Gateway.platform: node heartbeat node=${normalizedNodeId} count=${nextHeartbeatCount} historySize=${history.size() + 1} lifecycle=${lifecycleState} status=${status} running=${running}"
                )
            }
            updated.add(row)
            found = true
        } else {
            updated.add(obj)
        }
    }
    if (!found) {
        let row = JsonObject()
        row.put("id", JsonString(normalizedNodeId))
        row.put("kind", JsonString(kind))
        row.put("running", running.toJsonValue())
        row.put("status", JsonString(status))
        row.put("lifecycleState", JsonString(lifecycleState))
        row.put("phase", JsonString(gatewayNodePhase(lifecycleState, running, status)))
        row.put("browserMode", JsonString(cfg.nodes.browser.mode))
        row.put("browserNode", JsonString(cfg.nodes.browser.node))
        row.put("allowCommands", cfg.nodes.allowCommands.toJsonValue())
        row.put("denyCommands", cfg.nodes.denyCommands.toJsonValue())
        row.put("registeredAtMs", nowMs().toJsonValue())
        row.put("lastHeartbeatAtMs", nowMs().toJsonValue())
        row.put("lastStartedAtMs", if (running) { nowMs().toJsonValue() } else { 0.toJsonValue() })
        row.put("lastStoppedAtMs", if (!running) { nowMs().toJsonValue() } else { 0.toJsonValue() })
        row.put("transitionCount", 1.toJsonValue())
        row.put("restartCount", if (lifecycleState == "restarting") { 1.toJsonValue() } else { 0.toJsonValue() })
        row.put("heartbeatCount", 1.toJsonValue())
        row.put("lifecycleHistory", appendLifecycleHistory(JsonArray([]), lifecycleState, status, detail: "registered"))
        updated.add(row)
    }
    let nodesOut = JsonObject()
    nodesOut.put("count", Int64(updated.size()).toJsonValue())
    nodesOut.put("items", updated)
    let out = JsonObject()
    out.put("updatedAtMs", nowMs().toJsonValue())
    out.put("nodes", nodesOut)
    writeJsonObjectFile(gatewayNodeRegistryPath(), out)
    out
}

public func gatewayPendingWorkSnapshot(): JsonObject {
    let root = readJsonObjectFile(gatewayPendingWorkPath())
    match (root.get("items")) {
        case Some(_) => root
        case None =>
            let out = JsonObject()
            out.put("count", 0.toJsonValue())
            out.put("items", JsonArray([]))
            out
    }
}

public func gatewayPushDeliverySnapshot(): JsonObject {
    let root = readJsonObjectFile(gatewayPushDeliveriesPath())
    match (root.get("items")) {
        case Some(_) => root
        case None =>
            let out = JsonObject()
            out.put("count", 0.toJsonValue())
            out.put("items", JsonArray([]))
            out
    }
}

public func gatewayQueuePendingWork(kind: String, targetId: String, payload!: JsonObject = JsonObject()): JsonObject {
    let root = gatewayPendingWorkSnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let row = JsonObject()
    row.put("id", JsonString("pw-${nowMs()}"))
    row.put("kind", JsonString(kind))
    row.put("targetId", JsonString(targetId))
    row.put("payload", payload)
    row.put("status", JsonString("queued"))
    row.put("lifecycleState", JsonString("queued"))
    row.put("phase", JsonString(gatewayPendingWorkPhase("queued", "queued")))
    row.put("claimedBy", JsonString(""))
    row.put("attempts", 0.toJsonValue())
    row.put("createdAtMs", nowMs().toJsonValue())
    row.put("nextAttemptAtMs", nowMs().toJsonValue())
    row.put("lastError", JsonString(""))
    row.put("history", appendLifecycleHistory(JsonArray([]), "queued", "queued", detail: kind + ":" + targetId))
    items.add(row)
    let count = match (root.get("count")) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) + 1 } catch (_e: Exception) { 1 }
        case None => 1
    }
    let out = JsonObject()
    out.put("count", count.toJsonValue())
    out.put("items", items)
    writeJsonObjectFile(gatewayPendingWorkPath(), out)
    out
}

public func gatewayClaimPendingWork(nodeId: String): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let node = gatewayFindNodeById(cfg, nodeId.trimAscii())
    let nodeRunning = readJsonBool(node, "running", false)
    let nodeStatus = readJsonString(node, "status", "")
    let root = gatewayPendingWorkSnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let claimed = JsonArray([])
    var claimedOne = false
    let now = nowMs()
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let status = match (obj.get("status")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "queued" }
            case None => "queued"
        }
        let nextAttemptAtMs = readJsonInt(obj, "nextAttemptAtMs", 0)
        let targetId = readJsonString(obj, "targetId", "")
        let kind = readJsonString(obj, "kind", "")
        let targetsNode = targetId == nodeId.trimAscii()
        let nodeReady = nodeRunning && nodeStatus == "online"
        let policyAllows = gatewayNodeAllowsWork(node, kind)
        let claimable = status == "queued" && nextAttemptAtMs <= now && targetsNode && policyAllows && (nodeReady || kind == "wake-node")
        if (!claimedOne && claimable) {
            let attempts = readJsonInt(obj, "attempts", 0) + 1
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", obj.get("id") ?? JsonString(""))
            row.put("kind", obj.get("kind") ?? JsonString(""))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("payload", obj.get("payload") ?? JsonObject())
            row.put("status", JsonString("claimed"))
            row.put("lifecycleState", JsonString("claimed"))
            row.put("phase", JsonString(gatewayPendingWorkPhase("claimed", "claimed")))
            row.put("claimedBy", JsonString(nodeId.trimAscii()))
            row.put("attempts", attempts.toJsonValue())
            row.put("retryWindowCount", obj.get("retryWindowCount") ?? 0.toJsonValue())
            row.put("backoffMs", obj.get("backoffMs") ?? 0.toJsonValue())
            row.put("recoveryState", JsonString("executing"))
            row.put("createdAtMs", obj.get("createdAtMs") ?? 0.toJsonValue())
            row.put("claimedAtMs", nowMs().toJsonValue())
            row.put("nextAttemptAtMs", 0.toJsonValue())
            row.put("lastError", obj.get("lastError") ?? JsonString(""))
            row.put("history", appendLifecycleHistory(history, "claimed", "claimed", detail: nodeId.trimAscii()))
            updated.add(row)
            claimed.add(row)
            claimedOne = true
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPendingWorkPath(), out)
    let result = JsonObject()
    result.put("pendingWork", out)
    result.put("claimed", claimed)
    result
}

public func gatewayPendingWorkBacklogSummary(): JsonObject {
    let snapshot = gatewayPendingWorkSnapshot()
    let items = match (snapshot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let now = nowMs()
    let byKind = JsonObject()
    let byTarget = JsonObject()
    let byRecoveryState = JsonObject()
    var nextReadyAtMs: Int64 = 0
    var ready: Int64 = 0
    var blocked: Int64 = 0
    var retrying: Int64 = 0
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let status = readJsonString(row, "status", "")
        let lifecycleState = readJsonString(row, "lifecycleState", status)
        let nextAttemptAtMs = readJsonInt(row, "nextAttemptAtMs", 0)
        let recoveryState = readJsonString(row, "recoveryState", if (status == "queued" && nextAttemptAtMs <= now) { "ready" } else { "" })
        if (status == "queued" && nextAttemptAtMs <= now) {
            ready += 1
        } else if (status == "queued" && nextAttemptAtMs > now) {
            blocked += 1
            if (nextReadyAtMs == 0 || nextAttemptAtMs < nextReadyAtMs) {
                nextReadyAtMs = nextAttemptAtMs
            }
        }
        if (lifecycleState == "retrying") {
            retrying += 1
        }
        let kind = readJsonString(row, "kind", "")
        let targetId = readJsonString(row, "targetId", "")
        let currentKind = match (byKind.get(kind)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
            case None => 0
        }
        byKind.put(kind, (currentKind + 1).toJsonValue())
        let currentTarget = match (byTarget.get(targetId)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
            case None => 0
        }
        byTarget.put(targetId, (currentTarget + 1).toJsonValue())
        if (!recoveryState.isEmpty()) {
            let currentRecovery = match (byRecoveryState.get(recoveryState)) {
                case Some(v) =>
                    try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
                case None => 0
            }
            byRecoveryState.put(recoveryState, (currentRecovery + 1).toJsonValue())
        }
    }
    let out = JsonObject()
    out.put("ready", ready.toJsonValue())
    out.put("blocked", blocked.toJsonValue())
    out.put("retrying", retrying.toJsonValue())
    out.put("total", items.size().toJsonValue())
    out.put("byKind", byKind)
    out.put("byTarget", byTarget)
    out.put("byRecoveryState", byRecoveryState)
    out.put("nextReadyAtMs", nextReadyAtMs.toJsonValue())
    out
}

public func gatewayDispatchPendingWorkBatch(nodeId!: String = "local-gateway", limit!: Int64 = 4): JsonObject {
    let claimedRows = JsonArray([])
    let completedRows = JsonArray([])
    var executed: Int64 = 0
    while (executed < limit) {
        let claimed = gatewayClaimPendingWork(nodeId)
        let rows = match (claimed.get("claimed")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        if (rows.size() == 0) {
            break
        }
        let first = try { rows[0].asObject() } catch (_e: Exception) { JsonObject() }
        let workId = readJsonString(first, "id", "")
        claimedRows.add(first)
        let completed = gatewayCompletePendingWork(workId, nodeId)
        let completedArr = match (completed.get("completed")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        if (completedArr.size() > 0) {
            completedRows.add(completedArr[0])
        }
        executed += 1
    }
    let out = JsonObject()
    out.put("nodeId", JsonString(nodeId))
    out.put("limit", limit.toJsonValue())
    out.put("executed", executed.toJsonValue())
    out.put("claimed", claimedRows)
    out.put("completed", completedRows)
    out.put("summary", gatewayPendingWorkExecutorSummary())
    out.put("backlog", gatewayPendingWorkBacklogSummary())
    out
}

public func gatewayCompletePendingWork(workId: String, nodeId: String, status!: String = "completed"): JsonObject {
    let root = gatewayPendingWorkSnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let completed = JsonArray([])
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id == workId.trimAscii()) {
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("kind", obj.get("kind") ?? JsonString(""))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("payload", obj.get("payload") ?? JsonObject())
            row.put("status", JsonString(status))
            row.put("lifecycleState", JsonString(status))
            row.put("phase", JsonString(gatewayPendingWorkPhase(status, status)))
            row.put("claimedBy", JsonString(nodeId.trimAscii()))
            row.put("attempts", obj.get("attempts") ?? 1.toJsonValue())
            row.put("retryWindowCount", obj.get("retryWindowCount") ?? 0.toJsonValue())
            row.put("backoffMs", 0.toJsonValue())
            row.put("recoveryState", JsonString("done"))
            row.put("createdAtMs", obj.get("createdAtMs") ?? 0.toJsonValue())
            row.put("completedAtMs", nowMs().toJsonValue())
            row.put("nextAttemptAtMs", 0.toJsonValue())
            row.put("lastError", obj.get("lastError") ?? JsonString(""))
            row.put("history", appendLifecycleHistory(history, status, status, detail: nodeId.trimAscii()))
            updated.add(row)
            completed.add(row)
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPendingWorkPath(), out)
    let result = JsonObject()
    result.put("pendingWork", out)
    result.put("completed", completed)
    result
}

public func gatewayRetryPendingWork(workId: String, backoffMs!: Int64 = 1000, error!: String = ""): JsonObject {
    let root = gatewayPendingWorkSnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let retried = JsonArray([])
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = readJsonString(obj, "id", "")
        if (id == workId.trimAscii()) {
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let attempts = readJsonInt(obj, "attempts", 0)
            let retryWindowCount = readJsonInt(obj, "retryWindowCount", 0) + 1
            let effectiveBackoff = if (backoffMs > 0) { backoffMs * retryWindowCount } else { 1000 * retryWindowCount }
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("kind", obj.get("kind") ?? JsonString(""))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("payload", obj.get("payload") ?? JsonObject())
            row.put("status", JsonString("queued"))
            row.put("lifecycleState", JsonString("retrying"))
            row.put("phase", JsonString(gatewayPendingWorkPhase("retrying", "queued")))
            row.put("claimedBy", obj.get("claimedBy") ?? JsonString(""))
            row.put("attempts", attempts.toJsonValue())
            row.put("retryWindowCount", retryWindowCount.toJsonValue())
            row.put("backoffMs", effectiveBackoff.toJsonValue())
            row.put("recoveryState", JsonString("scheduled"))
            row.put("createdAtMs", obj.get("createdAtMs") ?? 0.toJsonValue())
            row.put("claimedAtMs", obj.get("claimedAtMs") ?? 0.toJsonValue())
            row.put("nextAttemptAtMs", (nowMs() + effectiveBackoff).toJsonValue())
            row.put("lastError", JsonString(error))
            row.put("history", appendLifecycleHistory(history, "retrying", "queued", detail: error))
            updated.add(row)
            retried.add(row)
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPendingWorkPath(), out)
    let result = JsonObject()
    result.put("pendingWork", out)
    result.put("retried", retried)
    result
}

public func gatewayRecoverPendingWork(workId: String): JsonObject {
    let root = gatewayPendingWorkSnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let recovered = JsonArray([])
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let id = readJsonString(obj, "id", "")
        if (id == workId.trimAscii()) {
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("kind", obj.get("kind") ?? JsonString(""))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("payload", obj.get("payload") ?? JsonObject())
            row.put("status", JsonString("queued"))
            row.put("lifecycleState", JsonString("recovered"))
            row.put("phase", JsonString(gatewayPendingWorkPhase("queued", "queued")))
            row.put("claimedBy", JsonString(""))
            row.put("attempts", obj.get("attempts") ?? 0.toJsonValue())
            row.put("retryWindowCount", obj.get("retryWindowCount") ?? 0.toJsonValue())
            row.put("backoffMs", 0.toJsonValue())
            row.put("recoveryState", JsonString("ready"))
            row.put("createdAtMs", obj.get("createdAtMs") ?? 0.toJsonValue())
            row.put("nextAttemptAtMs", nowMs().toJsonValue())
            row.put("lastError", JsonString(""))
            row.put("history", appendLifecycleHistory(history, "recovered", "queued", detail: "manual-recover"))
            updated.add(row)
            recovered.add(row)
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPendingWorkPath(), out)
    let result = JsonObject()
    result.put("pendingWork", out)
    result.put("recovered", recovered)
    result
}

public func gatewayFailPendingWork(workId: String, nodeId: String, error!: String = "failed"): JsonObject {
    let root = gatewayPendingWorkSnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let failed = JsonArray([])
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = readJsonString(obj, "id", "")
        if (id == workId.trimAscii()) {
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("kind", obj.get("kind") ?? JsonString(""))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("payload", obj.get("payload") ?? JsonObject())
            row.put("status", JsonString("failed"))
            row.put("lifecycleState", JsonString("failed"))
            row.put("phase", JsonString(gatewayPendingWorkPhase("failed", "failed")))
            row.put("claimedBy", JsonString(nodeId.trimAscii()))
            row.put("attempts", obj.get("attempts") ?? 1.toJsonValue())
            row.put("retryWindowCount", obj.get("retryWindowCount") ?? 0.toJsonValue())
            row.put("backoffMs", obj.get("backoffMs") ?? 0.toJsonValue())
            row.put("recoveryState", JsonString("failed"))
            row.put("createdAtMs", obj.get("createdAtMs") ?? 0.toJsonValue())
            row.put("claimedAtMs", obj.get("claimedAtMs") ?? 0.toJsonValue())
            row.put("completedAtMs", nowMs().toJsonValue())
            row.put("nextAttemptAtMs", 0.toJsonValue())
            row.put("lastError", JsonString(error))
            row.put("history", appendLifecycleHistory(history, "failed", "failed", detail: error))
            updated.add(row)
            failed.add(row)
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPendingWorkPath(), out)
    let result = JsonObject()
    result.put("pendingWork", out)
    result.put("failed", failed)
    result
}

public func gatewayRegisterDevice(deviceId: String, kind!: String = "browser", authMode!: String = "device-auth"): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let platform = gatewayPlatformSnapshot(cfg)
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    var found = false
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id == deviceId.trimAscii()) {
            found = true
            let history = match (obj.get("authHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(deviceId.trimAscii()))
            row.put("kind", JsonString(kind))
            row.put("authMode", JsonString(authMode))
            row.put("status", JsonString("active"))
            row.put("lifecycleState", JsonString("registered"))
            row.put("registeredAtMs", obj.get("registeredAtMs") ?? nowMs().toJsonValue())
            row.put("lastSeenAtMs", nowMs().toJsonValue())
            row.put("authState", JsonString("validated"))
            row.put("approvalState", JsonString("approved"))
            row.put("phase", JsonString(gatewayDevicePhase("validated", "active", "registered")))
            row.put("authTransitionCount", (readJsonInt(obj, "authTransitionCount", 0) + 1).toJsonValue())
            row.put("authHistory", appendLifecycleHistory(history, "validated", "active", detail: authMode))
            updated.add(row)
        } else {
            updated.add(obj)
        }
    }
    if (!found) {
        let row = JsonObject()
        row.put("id", JsonString(deviceId.trimAscii()))
        row.put("kind", JsonString(kind))
        row.put("authMode", JsonString(authMode))
        row.put("status", JsonString("active"))
        row.put("lifecycleState", JsonString("registered"))
        row.put("registeredAtMs", nowMs().toJsonValue())
        row.put("lastSeenAtMs", nowMs().toJsonValue())
        row.put("authState", JsonString("validated"))
        row.put("approvalState", JsonString("approved"))
        row.put("phase", JsonString(gatewayDevicePhase("validated", "active", "registered")))
        row.put("authTransitionCount", 1.toJsonValue())
        row.put("authHistory", appendLifecycleHistory(JsonArray([]), "validated", "active", detail: authMode))
        updated.add(row)
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    let persisted = platform
    persisted.put("devices", out)
    persisted.put("updatedAtMs", nowMs().toJsonValue())
    writePlatformState(persisted)
    out
}

public func gatewayTouchDevice(deviceId: String, authState!: String = "validated", status!: String = "active"): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let platform = gatewayPlatformSnapshot(cfg)
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let targetId = deviceId.trimAscii()
    var found = false
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = readJsonString(obj, "id", "")
        if (id == targetId) {
            found = true
            let history = match (obj.get("authHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(targetId))
            row.put("kind", obj.get("kind") ?? JsonString("browser"))
            row.put("authMode", obj.get("authMode") ?? JsonString("device-auth"))
            row.put("status", JsonString(status))
            row.put("lifecycleState", JsonString("touched"))
            row.put("registeredAtMs", obj.get("registeredAtMs") ?? nowMs().toJsonValue())
            row.put("lastSeenAtMs", nowMs().toJsonValue())
            row.put("authState", JsonString(authState))
            row.put("approvalState", JsonString(if (authState == "validated" || authState == "refreshed") { "approved" } else { gatewayDeviceApprovalState(obj) }))
            row.put("phase", JsonString(gatewayDevicePhase(authState, status, "touched")))
            row.put("authTransitionCount", (readJsonInt(obj, "authTransitionCount", 0) + 1).toJsonValue())
            row.put("authHistory", appendLifecycleHistory(history, authState, status, detail: "touch"))
            updated.add(row)
        } else {
            updated.add(obj)
        }
    }
    if (!found) {
        return gatewayRegisterDevice(targetId, authMode: authState)
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    let persisted = platform
    persisted.put("devices", out)
    persisted.put("updatedAtMs", nowMs().toJsonValue())
    writePlatformState(persisted)
    out
}

public func gatewayRevalidateDevice(deviceId: String, authState!: String = "validated"): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let platform = gatewayPlatformSnapshot(cfg)
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let targetId = deviceId.trimAscii()
    let targetAuthState = if (authState.trimAscii().isEmpty()) { "validated" } else { authState.trimAscii() }
    var found = false
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let id = readJsonString(obj, "id", "")
        if (id == targetId) {
            found = true
            let history = match (obj.get("authHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(targetId))
            row.put("kind", obj.get("kind") ?? JsonString("browser"))
            row.put("authMode", obj.get("authMode") ?? JsonString("device-auth"))
            row.put("status", JsonString("inactive"))
            row.put("lifecycleState", JsonString("revalidating"))
            row.put("registeredAtMs", obj.get("registeredAtMs") ?? nowMs().toJsonValue())
            row.put("lastSeenAtMs", nowMs().toJsonValue())
            row.put("authState", JsonString(if (targetAuthState == "validated") { "revalidating" } else { targetAuthState }))
            row.put("approvalState", JsonString("pending"))
            row.put("phase", JsonString(gatewayDevicePhase(if (targetAuthState == "validated") { "revalidating" } else { targetAuthState }, "inactive", "revalidating")))
            row.put("authTransitionCount", (readJsonInt(obj, "authTransitionCount", 0) + 1).toJsonValue())
            row.put("authHistory", appendLifecycleHistory(history, if (targetAuthState == "validated") { "revalidating" } else { targetAuthState }, "inactive", detail: "revalidate"))
            match (obj.get("controlUiEnabled")) {
                case Some(v) => row.put("controlUiEnabled", v)
                case None => ()
            }
            updated.add(row)
        } else {
            updated.add(obj)
        }
    }
    if (!found) {
        return gatewayRegisterDevice(targetId)
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    let persisted = platform
    persisted.put("devices", out)
    persisted.put("updatedAtMs", nowMs().toJsonValue())
    writePlatformState(persisted)
    out
}

public func gatewayApproveDevice(deviceId: String, authState!: String = "validated"): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let platform = gatewayPlatformSnapshot(cfg)
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let targetId = deviceId.trimAscii()
    let nextAuthState = if (authState.trimAscii().isEmpty()) { "validated" } else { authState.trimAscii() }
    var found = false
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let id = readJsonString(obj, "id", "")
        if (id == targetId) {
            found = true
            let history = match (obj.get("authHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(targetId))
            row.put("kind", obj.get("kind") ?? JsonString("browser"))
            row.put("authMode", obj.get("authMode") ?? JsonString("device-auth"))
            row.put("status", JsonString("active"))
            row.put("lifecycleState", JsonString("approved"))
            row.put("registeredAtMs", obj.get("registeredAtMs") ?? nowMs().toJsonValue())
            row.put("lastSeenAtMs", nowMs().toJsonValue())
            row.put("approvedAtMs", nowMs().toJsonValue())
            row.put("authState", JsonString(nextAuthState))
            row.put("approvalState", JsonString("approved"))
            row.put("phase", JsonString(gatewayDevicePhase(nextAuthState, "active", "approved")))
            row.put("authTransitionCount", (readJsonInt(obj, "authTransitionCount", 0) + 1).toJsonValue())
            row.put("authHistory", appendLifecycleHistory(history, nextAuthState, "active", detail: "approve"))
            match (obj.get("controlUiEnabled")) {
                case Some(v) => row.put("controlUiEnabled", v)
                case None => ()
            }
            updated.add(row)
        } else {
            updated.add(obj)
        }
    }
    if (!found) {
        return gatewayRegisterDevice(targetId)
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    let persisted = platform
    persisted.put("devices", out)
    persisted.put("updatedAtMs", nowMs().toJsonValue())
    writePlatformState(persisted)
    out
}

public func gatewayRecoverDevice(deviceId: String): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let platform = gatewayPlatformSnapshot(cfg)
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let targetId = deviceId.trimAscii()
    var found = false
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let id = readJsonString(obj, "id", "")
        if (id == targetId) {
            found = true
            let history = match (obj.get("authHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(targetId))
            row.put("kind", obj.get("kind") ?? JsonString("browser"))
            row.put("authMode", obj.get("authMode") ?? JsonString("device-auth"))
            row.put("status", JsonString("active"))
            row.put("lifecycleState", JsonString("recovered"))
            row.put("registeredAtMs", obj.get("registeredAtMs") ?? nowMs().toJsonValue())
            row.put("lastSeenAtMs", nowMs().toJsonValue())
            row.put("authState", JsonString("validated"))
            row.put("approvalState", JsonString("approved"))
            row.put("phase", JsonString(gatewayDevicePhase("validated", "active", "recovered")))
            row.put("authTransitionCount", (readJsonInt(obj, "authTransitionCount", 0) + 1).toJsonValue())
            row.put("authHistory", appendLifecycleHistory(history, "validated", "active", detail: "recover"))
            match (obj.get("controlUiEnabled")) {
                case Some(v) => row.put("controlUiEnabled", v)
                case None => ()
            }
            updated.add(row)
        } else {
            updated.add(obj)
        }
    }
    if (!found) {
        return gatewayRegisterDevice(targetId)
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    let persisted = platform
    persisted.put("devices", out)
    persisted.put("updatedAtMs", nowMs().toJsonValue())
    writePlatformState(persisted)
    out
}

public func gatewayDenyDevice(deviceId: String, reason!: String = "denied"): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let platform = gatewayPlatformSnapshot(cfg)
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let targetId = deviceId.trimAscii()
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let id = readJsonString(obj, "id", "")
        if (id != targetId) {
            updated.add(obj)
        } else {
            let history = match (obj.get("authHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(targetId))
            row.put("kind", obj.get("kind") ?? JsonString("browser"))
            row.put("authMode", obj.get("authMode") ?? JsonString("device-auth"))
            row.put("status", JsonString("inactive"))
            row.put("lifecycleState", JsonString("denied"))
            row.put("registeredAtMs", obj.get("registeredAtMs") ?? 0.toJsonValue())
            row.put("lastSeenAtMs", nowMs().toJsonValue())
            row.put("deniedAtMs", nowMs().toJsonValue())
            row.put("authState", JsonString("revoked"))
            row.put("approvalState", JsonString("denied"))
            row.put("phase", JsonString(gatewayDevicePhase("revoked", "inactive", "denied")))
            row.put("authTransitionCount", (readJsonInt(obj, "authTransitionCount", 0) + 1).toJsonValue())
            row.put("authHistory", appendLifecycleHistory(history, "revoked", "inactive", detail: reason))
            match (obj.get("controlUiEnabled")) {
                case Some(v) => row.put("controlUiEnabled", v)
                case None => ()
            }
            updated.add(row)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    let persisted = platform
    persisted.put("devices", out)
    persisted.put("updatedAtMs", nowMs().toJsonValue())
    writePlatformState(persisted)
    out
}

public func gatewayUnregisterDevice(deviceId: String): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let platform = gatewayPlatformSnapshot(cfg)
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let targetId = deviceId.trimAscii()
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id != targetId) {
            updated.add(obj)
        } else {
            let history = match (obj.get("authHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(targetId))
            row.put("kind", obj.get("kind") ?? JsonString("browser"))
            row.put("authMode", obj.get("authMode") ?? JsonString(""))
            row.put("status", JsonString("inactive"))
            row.put("lifecycleState", JsonString("unregistered"))
            row.put("registeredAtMs", obj.get("registeredAtMs") ?? 0.toJsonValue())
            row.put("lastSeenAtMs", nowMs().toJsonValue())
            row.put("unregisteredAtMs", nowMs().toJsonValue())
            row.put("authState", JsonString("revoked"))
            row.put("approvalState", JsonString("denied"))
            row.put("phase", JsonString(gatewayDevicePhase("revoked", "inactive", "unregistered")))
            row.put("authTransitionCount", (readJsonInt(obj, "authTransitionCount", 0) + 1).toJsonValue())
            row.put("authHistory", appendLifecycleHistory(history, "revoked", "inactive", detail: "unregister"))
            updated.add(row)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    let persisted = platform
    persisted.put("devices", out)
    persisted.put("updatedAtMs", nowMs().toJsonValue())
    writePlatformState(persisted)
    out
}

public func gatewayRecordPushDelivery(channel: String, targetId: String, status: String, detail!: String = ""): JsonObject {
    let root = gatewayPushDeliverySnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let row = JsonObject()
    row.put("id", JsonString("pd-${nowMs()}"))
    row.put("channel", JsonString(channel))
    row.put("targetId", JsonString(targetId))
    row.put("status", JsonString(status))
    row.put("lifecycleState", JsonString(status))
    row.put("phase", JsonString(gatewayPushPhase(status, status)))
    row.put("detail", JsonString(detail))
    row.put("attempt", 1.toJsonValue())
    row.put("retryCount", 0.toJsonValue())
    row.put("createdAtMs", nowMs().toJsonValue())
    row.put("lastAttemptAtMs", nowMs().toJsonValue())
    row.put("deliveredAtMs", nowMs().toJsonValue())
    row.put("history", appendLifecycleHistory(JsonArray([]), status, status, detail: detail))
    items.add(row)
    let count = match (root.get("count")) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) + 1 } catch (_e: Exception) { 1 }
        case None => 1
    }
    let out = JsonObject()
    out.put("count", count.toJsonValue())
    out.put("items", items)
    writeJsonObjectFile(gatewayPushDeliveriesPath(), out)
    out
}

public func gatewaySendPush(channel: String, targetId: String, body: String): JsonObject {
    let detail = if (body.trimAscii().isEmpty()) { "empty-body" } else { body.trimAscii() }
    gatewayRecordPushDelivery(channel, targetId, "sent", detail: detail)
}

public func gatewayRetryPushDelivery(deliveryId: String): JsonObject {
    let root = gatewayPushDeliverySnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let retried = JsonArray([])
    let targetId = deliveryId.trimAscii()
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (id == targetId) {
            let attempt = match (obj.get("attempt")) {
                case Some(v) =>
                    try { Int64.parse(v.toJsonString()) + 1 } catch (_inner: Exception) { 2 }
                case None => 2
            }
            let retryCount = readJsonInt(obj, "retryCount", 0) + 1
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("channel", obj.get("channel") ?? JsonString(""))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("status", JsonString("retried"))
            row.put("lifecycleState", JsonString("retried"))
            row.put("phase", JsonString(gatewayPushPhase("retried", "retried")))
            row.put("detail", obj.get("detail") ?? JsonString(""))
            row.put("attempt", attempt.toJsonValue())
            row.put("retryCount", retryCount.toJsonValue())
            row.put("createdAtMs", obj.get("createdAtMs") ?? nowMs().toJsonValue())
            row.put("lastAttemptAtMs", nowMs().toJsonValue())
            row.put("deliveredAtMs", nowMs().toJsonValue())
            row.put("retriedAtMs", nowMs().toJsonValue())
            row.put("history", appendLifecycleHistory(history, "retried", "retried", detail: readJsonString(obj, "detail", "")))
            updated.add(row)
            retried.add(row)
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPushDeliveriesPath(), out)
    let result = JsonObject()
    result.put("push", out)
    result.put("retried", retried)
    result
}

public func gatewayFailPushDelivery(deliveryId: String, reason!: String = "failed"): JsonObject {
    let root = gatewayPushDeliverySnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let failed = JsonArray([])
    let targetId = deliveryId.trimAscii()
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let id = readJsonString(obj, "id", "")
        if (id == targetId) {
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("channel", obj.get("channel") ?? JsonString(""))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("status", JsonString("failed"))
            row.put("lifecycleState", JsonString("failed"))
            row.put("phase", JsonString(gatewayPushPhase("failed", "failed")))
            row.put("detail", JsonString(reason))
            row.put("attempt", obj.get("attempt") ?? 1.toJsonValue())
            row.put("retryCount", obj.get("retryCount") ?? 0.toJsonValue())
            row.put("createdAtMs", obj.get("createdAtMs") ?? nowMs().toJsonValue())
            row.put("lastAttemptAtMs", nowMs().toJsonValue())
            row.put("deliveredAtMs", obj.get("deliveredAtMs") ?? 0.toJsonValue())
            row.put("failedAtMs", nowMs().toJsonValue())
            row.put("history", appendLifecycleHistory(history, "failed", "failed", detail: reason))
            updated.add(row)
            failed.add(row)
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPushDeliveriesPath(), out)
    let result = JsonObject()
    result.put("push", out)
    result.put("failed", failed)
    result
}

public func gatewayRecoverPushDelivery(deliveryId: String, detail!: String = "recovered"): JsonObject {
    let root = gatewayPushDeliverySnapshot()
    let items = match (root.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let updated = JsonArray([])
    let recovered = JsonArray([])
    let targetId = deliveryId.trimAscii()
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try { item.asObject() } catch (_e: Exception) { JsonObject() }
        let id = readJsonString(obj, "id", "")
        if (id == targetId) {
            let attempt = readJsonInt(obj, "attempt", 1) + 1
            let retryCount = readJsonInt(obj, "retryCount", 0)
            let history = match (obj.get("history")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            let row = JsonObject()
            row.put("id", JsonString(id))
            row.put("channel", obj.get("channel") ?? JsonString("local"))
            row.put("targetId", obj.get("targetId") ?? JsonString(""))
            row.put("status", JsonString("sent"))
            row.put("lifecycleState", JsonString("recovered"))
            row.put("phase", JsonString(gatewayPushPhase("sent", "sent")))
            row.put("detail", JsonString(detail))
            row.put("attempt", attempt.toJsonValue())
            row.put("retryCount", retryCount.toJsonValue())
            row.put("createdAtMs", obj.get("createdAtMs") ?? nowMs().toJsonValue())
            row.put("lastAttemptAtMs", nowMs().toJsonValue())
            row.put("deliveredAtMs", nowMs().toJsonValue())
            row.put("orchestrationAction", JsonString("recover"))
            row.put("history", appendLifecycleHistory(history, "recovered", "sent", detail: detail))
            updated.add(row)
            recovered.add(row)
        } else {
            updated.add(obj)
        }
    }
    let out = JsonObject()
    out.put("count", Int64(updated.size()).toJsonValue())
    out.put("items", updated)
    writeJsonObjectFile(gatewayPushDeliveriesPath(), out)
    let result = JsonObject()
    result.put("push", out)
    result.put("recovered", recovered)
    result
}

public func gatewayWakePushTarget(channel: String, targetId: String, body!: String = "wake"): JsonObject {
    let cfg = buildGatewayConfigFromUserSettings(CliSettingManager.readGatewaySettings())
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let target = targetId.trimAscii()
    var targetStateBefore = "unknown"
    var approvalStateBefore = "unknown"
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (readJsonString(row, "id", "") == target) {
            targetStateBefore = if (readJsonString(row, "status", "") == "active") { "reachable" } else { "inactive" }
            approvalStateBefore = gatewayDeviceApprovalState(row)
            break
        }
    }
    let touched = if (approvalStateBefore == "denied") {
        JsonObject()
    } else if (targetStateBefore == "inactive" && approvalStateBefore == "approved") {
        gatewayRecoverDevice(target)
    } else if (targetStateBefore == "reachable" && approvalStateBefore == "approved") {
        gatewayTouchDevice(target, authState: "refreshed", status: "active")
    } else if (approvalStateBefore == "pending") {
        gatewayRevalidateDevice(target)
    } else {
        JsonObject()
    }
    let push = if (targetStateBefore == "unknown") {
        gatewayRecordPushDelivery(channel, target, "failed", detail: "missing-target")
    } else if (approvalStateBefore == "denied") {
        gatewayRecordPushDelivery(channel, target, "failed", detail: "approval-denied")
    } else if (approvalStateBefore == "pending") {
        gatewayRecordPushDelivery(channel, target, "failed", detail: "approval-pending")
    } else {
        gatewaySendPush(channel, target, body)
    }
    let result = JsonObject()
    result.put("devices", touched)
    result.put("push", push)
    result.put("targetId", JsonString(target))
    result.put("targetStateBefore", JsonString(targetStateBefore))
    result.put("approvalStateBefore", JsonString(approvalStateBefore))
    result.put("wokeTarget", (targetStateBefore != "unknown").toJsonValue())
    result
}

private func gatewayDevicePresenceStateForTarget(cfg: GatewayConfig, targetId: String): String {
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let now = nowMs()
    let staleThreshold: Int64 = 5 * 60 * 1000
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (readJsonString(row, "id", "") != targetId) {
            continue
        }
        let status = readJsonString(row, "status", "")
        let seenAt = readJsonInt(row, "lastSeenAtMs", 0)
        if (status != "active") {
            return "inactive"
        }
        if (seenAt > 0 && now - seenAt > staleThreshold) {
            return "stale"
        }
        return "reachable"
    }
    return "unknown"
}

private func gatewayDeviceApprovalStateForTarget(cfg: GatewayConfig, targetId: String): String {
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (readJsonString(row, "id", "") == targetId) {
            return gatewayDeviceApprovalState(row)
        }
    }
    return "unknown"
}

public func gatewayRunPushOrchestration(cfg: GatewayConfig, channel!: String = "local", limit!: Int64 = 4): JsonObject {
    let snapshot = gatewayPushDeliverySnapshot()
    let items = match (snapshot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let actions = JsonArray([])
    var processed: Int64 = 0
    for (i in 0..items.size()) {
        if (processed >= limit) {
            break
        }
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let deliveryId = readJsonString(row, "id", "")
        let targetId = readJsonString(row, "targetId", "")
        let status = readJsonString(row, "status", "")
        if (status != "failed" && status != "retried") {
            continue
        }
        let targetState = gatewayDevicePresenceStateForTarget(cfg, targetId)
        let approvalState = gatewayDeviceApprovalStateForTarget(cfg, targetId)
        let action = JsonObject()
        action.put("deliveryId", JsonString(deliveryId))
        action.put("targetId", JsonString(targetId))
        action.put("targetState", JsonString(targetState))
        action.put("approvalState", JsonString(approvalState))
        if (approvalState == "denied") {
            action.put("action", JsonString("fail"))
            action.put("result", gatewayFailPushDelivery(deliveryId, reason: "orchestrator-approval-denied"))
        } else if (approvalState == "pending") {
            action.put("action", JsonString("revalidate"))
            action.put("result", gatewayRevalidateDevice(targetId))
        } else if (targetState == "reachable" || targetState == "stale") {
            action.put("action", JsonString("recover"))
            action.put("result", gatewayRecoverPushDelivery(deliveryId, detail: "orchestrator-recover"))
        } else if (targetState == "inactive") {
            action.put("action", JsonString("wake"))
            action.put("result", gatewayWakePushTarget(channel, targetId, body: "orchestrator-wake"))
        } else {
            action.put("action", JsonString("fail"))
            action.put("result", gatewayFailPushDelivery(deliveryId, reason: "orchestrator-missing-target"))
        }
        actions.add(action)
        processed += 1
    }
    let out = JsonObject()
    out.put("processed", processed.toJsonValue())
    out.put("actions", actions)
    out.put("dispatcher", gatewayPushDispatcherSummary(cfg))
    out.put("orchestration", gatewayPushOrchestrationSummary(cfg))
    out
}

public func gatewayReconcileNodeScheduling(cfg: GatewayConfig, nodeId!: String = "", limit!: Int64 = 4): JsonObject {
    let snapshot = gatewayNodeRegistrySnapshot(cfg, false)
    let nodesRoot = match (snapshot.get("nodes")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (nodesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let actions = JsonArray([])
    var processed: Int64 = 0
    for (i in 0..items.size()) {
        if (processed >= limit) {
            break
        }
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let id = readJsonString(row, "id", "")
        if (!nodeId.trimAscii().isEmpty() && id != nodeId.trimAscii()) {
            continue
        }
        let decision = gatewayNodeSchedulingDecision(row)
        let action = JsonObject()
        action.put("nodeId", JsonString(id))
        action.put("decision", JsonString(decision))
        if (decision == "wake") {
            let payload = JsonObject()
            payload.put("requestedBy", JsonString("node-policy"))
            payload.put("message", JsonString("scheduler-wake"))
            action.put("result", gatewayQueuePendingWork("wake-node", id, payload: payload))
            processed += 1
        } else {
            action.put("result", row)
        }
        actions.add(action)
    }
    let out = JsonObject()
    out.put("processed", processed.toJsonValue())
    out.put("actions", actions)
    out.put("policy", gatewayNodeSchedulerPolicySummary(cfg))
    out.put("backlog", gatewayPendingWorkBacklogSummary())
    out
}

public func gatewayPendingWorkExecutorSummary(): JsonObject {
    let snapshot = gatewayPendingWorkSnapshot()
    let items = match (snapshot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var queued: Int64 = 0
    var claimed: Int64 = 0
    var completed: Int64 = 0
    var retrying: Int64 = 0
    var failed: Int64 = 0
    let byPhase = JsonObject()
    let byRecoveryState = JsonObject()
    for (i in 0..items.size()) {
        let item = items[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let status = match (obj.get("status")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (status == "queued") {
            queued += 1
        } else if (status == "claimed") {
            claimed += 1
        } else if (status == "completed") {
            completed += 1
        } else if (status == "failed") {
            failed += 1
        } else if (status == "retrying") {
            retrying += 1
        }
        let phase = readJsonString(obj, "phase", gatewayPendingWorkPhase(readJsonString(obj, "lifecycleState", status), status))
        let currentPhase = match (byPhase.get(phase)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byPhase.put(phase, (currentPhase + 1).toJsonValue())
        let recoveryState = readJsonString(obj, "recoveryState", "")
        if (!recoveryState.isEmpty()) {
            let currentRecovery = match (byRecoveryState.get(recoveryState)) {
                case Some(v) =>
                    try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
                case None => 0
            }
            byRecoveryState.put(recoveryState, (currentRecovery + 1).toJsonValue())
        }
    }
    let result = JsonObject()
    result.put("queued", queued.toJsonValue())
    result.put("claimed", claimed.toJsonValue())
    result.put("completed", completed.toJsonValue())
    result.put("retrying", retrying.toJsonValue())
    result.put("failed", failed.toJsonValue())
    result.put("total", items.size().toJsonValue())
    result.put("byPhase", byPhase)
    result.put("byRecoveryState", byRecoveryState)
    result.put("executorState", JsonString(if (claimed > 0) { "busy" } else if (queued > 0 || retrying > 0) { "pending" } else if (failed > 0) { "degraded" } else { "idle" }))
    result
}

public func gatewayNodeLifecycleSummary(cfg: GatewayConfig): JsonObject {
    let nodes = gatewayNodeRegistrySnapshot(cfg, false)
    let nodesRoot = match (nodes.get("nodes")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (nodesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var runningCount: Int64 = 0
    var stoppedCount: Int64 = 0
    var onlineCount: Int64 = 0
    var offlineCount: Int64 = 0
    let lifecycleCounts = JsonObject()
    let phaseCounts = JsonObject()
    for (i in 0..items.size()) {
        let row = try {
            items[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let status = match (row.get("status")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        let lifecycleState = match (row.get("lifecycleState")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (status == "online") {
            onlineCount += 1
        } else {
            offlineCount += 1
        }
        if (lifecycleState == "running") {
            runningCount += 1
        } else {
            stoppedCount += 1
        }
        let current = match (lifecycleCounts.get(lifecycleState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        lifecycleCounts.put(lifecycleState, (current + 1).toJsonValue())
        let phase = readJsonString(row, "phase", gatewayNodePhase(lifecycleState, status == "online", status))
        let currentPhase = match (phaseCounts.get(phase)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        phaseCounts.put(phase, (currentPhase + 1).toJsonValue())
    }
    let out = JsonObject()
    out.put("running", runningCount.toJsonValue())
    out.put("stopped", stoppedCount.toJsonValue())
    out.put("online", onlineCount.toJsonValue())
    out.put("offline", offlineCount.toJsonValue())
    out.put("byLifecycleState", lifecycleCounts)
    out.put("byPhase", phaseCounts)
    out.put("count", items.size().toJsonValue())
    var restartCount: Int64 = 0
    var transitionCount: Int64 = 0
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        restartCount += readJsonInt(row, "restartCount", 0)
        transitionCount += readJsonInt(row, "transitionCount", 0)
    }
    out.put("restartCount", restartCount.toJsonValue())
    out.put("transitionCount", transitionCount.toJsonValue())
    out
}

public func gatewayNodeSchedulerPolicySummary(cfg: GatewayConfig): JsonObject {
    let nodes = gatewayNodeRegistrySnapshot(cfg, false)
    let nodesRoot = match (nodes.get("nodes")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (nodesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let byBrowserMode = JsonObject()
    let byPhase = JsonObject()
    var dispatchable: Int64 = 0
    var blocked: Int64 = 0
    var browserManaged: Int64 = 0
    var allowRules: Int64 = 0
    var denyRules: Int64 = 0
    let byDecision = JsonObject()
    let byBlockedReason = JsonObject()
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let browserMode = readJsonString(row, "browserMode", "auto")
        let browserModeCount = match (byBrowserMode.get(browserMode)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byBrowserMode.put(browserMode, (browserModeCount + 1).toJsonValue())
        let phase = readJsonString(row, "phase", gatewayNodePhase(readJsonString(row, "lifecycleState", ""), readJsonBool(row, "running", false), readJsonString(row, "status", "")))
        let phaseCount = match (byPhase.get(phase)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byPhase.put(phase, (phaseCount + 1).toJsonValue())
        let allow = match (row.get("allowCommands")) {
            case Some(v) =>
                try { Int64(v.asArray().size()) } catch (_e: Exception) { 0 }
            case None => 0
        }
        let deny = match (row.get("denyCommands")) {
            case Some(v) =>
                try { Int64(v.asArray().size()) } catch (_e: Exception) { 0 }
            case None => 0
        }
        allowRules += allow
        denyRules += deny
        if (!readJsonString(row, "browserNode", "").isEmpty() || browserMode == "auto") {
            browserManaged += 1
        }
        let decision = gatewayNodeSchedulingDecision(row)
        let decisionCount = match (byDecision.get(decision)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byDecision.put(decision, (decisionCount + 1).toJsonValue())
        let blockedReason = if (decision == "denied") { "policy-deny" } else if (decision == "browser-disabled") { "browser-disabled" } else if (decision == "wake") { "offline" } else if (decision == "hold") { "transitioning" } else { "" }
        if (!blockedReason.isEmpty()) {
            let blockedCount = match (byBlockedReason.get(blockedReason)) {
                case Some(v) =>
                    try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
                case None => 0
            }
            byBlockedReason.put(blockedReason, (blockedCount + 1).toJsonValue())
        }
        if (decision == "dispatch") {
            dispatchable += 1
        } else {
            blocked += 1
        }
    }
    let out = JsonObject()
    out.put("count", items.size().toJsonValue())
    out.put("dispatchable", dispatchable.toJsonValue())
    out.put("blocked", blocked.toJsonValue())
    out.put("browserManaged", browserManaged.toJsonValue())
    out.put("allowRules", allowRules.toJsonValue())
    out.put("denyRules", denyRules.toJsonValue())
    out.put("byBrowserMode", byBrowserMode)
    out.put("byPhase", byPhase)
    out.put("byDecision", byDecision)
    out.put("byBlockedReason", byBlockedReason)
    out.put("policyState", JsonString(if (dispatchable > 0) { "dispatchable" } else if (items.size() > 0) { "blocked" } else { "empty" }))
    out
}

public func gatewayNodeSchedulingAuditSummary(cfg: GatewayConfig): JsonObject {
    let policy = gatewayNodeSchedulerPolicySummary(cfg)
    let out = JsonObject()
    let byDecision = match (policy.get("byDecision")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let wake = readJsonInt(byDecision, "wake", 0)
    let dispatch = readJsonInt(byDecision, "dispatch", 0)
    let hold = readJsonInt(byDecision, "hold", 0)
    let denied = readJsonInt(byDecision, "denied", 0)
    let browserDisabled = readJsonInt(byDecision, "browser-disabled", 0)
    out.put("count", policy.get("count") ?? 0.toJsonValue())
    out.put("wakeCandidates", wake.toJsonValue())
    out.put("dispatchCandidates", dispatch.toJsonValue())
    out.put("holdCandidates", hold.toJsonValue())
    out.put("deniedCandidates", denied.toJsonValue())
    out.put("browserDisabledCandidates", browserDisabled.toJsonValue())
    out.put("actionsNeeded", (wake + hold + denied + browserDisabled).toJsonValue())
    out.put("auditState", JsonString(if (wake > 0) { "wake-required" } else if (hold > 0) { "transitioning" } else if (denied > 0 || browserDisabled > 0) { "policy-blocked" } else if (dispatch > 0) { "dispatch-ready" } else { "idle" }))
    out.put("policy", policy)
    out
}

public func gatewayDeviceAuthSummary(cfg: GatewayConfig): JsonObject {
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let authModes = JsonObject()
    let byPhase = JsonObject()
    let policyStates = JsonObject()
    var activeCount: Int64 = 0
    for (i in 0..items.size()) {
        let row = try {
            items[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let authMode = match (row.get("authMode")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        let status = match (row.get("status")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        let authState = readJsonString(row, "authState", "")
        if (status == "active") {
            activeCount += 1
        }
        let current = match (authModes.get(authMode)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        authModes.put(authMode, (current + 1).toJsonValue())
        let phase = readJsonString(row, "phase", gatewayDevicePhase(authState, status, readJsonString(row, "lifecycleState", "")))
        let currentPhase = match (byPhase.get(phase)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byPhase.put(phase, (currentPhase + 1).toJsonValue())
        let policyState =
            if (authState == "revoked") {
                "revoked"
            } else if (authState == "revalidating" || readJsonString(row, "lifecycleState", "") == "revalidating") {
                "revalidation-required"
            } else if (status == "active") {
                "trusted"
            } else {
                "inactive"
            }
        let currentPolicy = match (policyStates.get(policyState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        policyStates.put(policyState, (currentPolicy + 1).toJsonValue())
    }
    let out = JsonObject()
    out.put("count", items.size().toJsonValue())
    out.put("active", activeCount.toJsonValue())
    out.put("authModes", authModes)
    out.put("byPhase", byPhase)
    out.put("policyStates", policyStates)
    let authStates = JsonObject()
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let authState = readJsonString(row, "authState", "")
        let current = match (authStates.get(authState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        authStates.put(authState, (current + 1).toJsonValue())
    }
    out.put("authStates", authStates)
    out
}

public func gatewayDeviceApprovalPolicySummary(cfg: GatewayConfig): JsonObject {
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let byAuthMode = JsonObject()
    let byPolicyState = JsonObject()
    let byApprovalState = JsonObject()
    var approvalRequired: Int64 = 0
    var approved: Int64 = 0
    var revalidating: Int64 = 0
    var revoked: Int64 = 0
    var recoverable: Int64 = 0
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let authMode = readJsonString(row, "authMode", "")
        let authModeCount = match (byAuthMode.get(authMode)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byAuthMode.put(authMode, (authModeCount + 1).toJsonValue())
        let lifecycleState = readJsonString(row, "lifecycleState", "")
        let authState = readJsonString(row, "authState", "")
        let status = readJsonString(row, "status", "")
        let policyState =
            if (authState == "revoked") {
                "revoked"
            } else if (authState == "revalidating" || lifecycleState == "revalidating") {
                "revalidation-required"
            } else if (status == "active" && authState == "validated") {
                "trusted"
            } else {
                "inactive"
            }
        let policyCount = match (byPolicyState.get(policyState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byPolicyState.put(policyState, (policyCount + 1).toJsonValue())
        let approvalState = gatewayDeviceApprovalState(row)
        let approvalCount = match (byApprovalState.get(approvalState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byApprovalState.put(approvalState, (approvalCount + 1).toJsonValue())
        if (approvalState == "pending") {
            approvalRequired += 1
            revalidating += 1
        }
        if (approvalState == "approved") {
            approved += 1
        }
        if (approvalState == "revoked") {
            revoked += 1
        }
        if (lifecycleState == "recovered" || authState == "revalidating" || authState == "revoked") {
            recoverable += 1
        }
    }
    let out = JsonObject()
    out.put("count", items.size().toJsonValue())
    out.put("approvalRequired", approvalRequired.toJsonValue())
    out.put("approved", approved.toJsonValue())
    out.put("revalidating", revalidating.toJsonValue())
    out.put("revoked", revoked.toJsonValue())
    out.put("recoverable", recoverable.toJsonValue())
    out.put("byAuthMode", byAuthMode)
    out.put("byPolicyState", byPolicyState)
    out.put("byApprovalState", byApprovalState)
    out.put("policyState", JsonString(if (approvalRequired > 0) { "approval-required" } else if (approved > 0) { "approved" } else if (items.size() > 0) { "inactive" } else { "empty" }))
    out
}

public func gatewayDeviceApprovalAuditSummary(cfg: GatewayConfig): JsonObject {
    let policy = gatewayDeviceApprovalPolicySummary(cfg)
    let out = JsonObject()
    let byApprovalState = match (policy.get("byApprovalState")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let pending = readJsonInt(byApprovalState, "pending", 0)
    let approved = readJsonInt(byApprovalState, "approved", 0)
    let denied = readJsonInt(byApprovalState, "denied", 0)
    let recovered = readJsonInt(byApprovalState, "recovered", 0)
    let inactive = readJsonInt(byApprovalState, "inactive", 0)
    out.put("count", policy.get("count") ?? 0.toJsonValue())
    out.put("pending", pending.toJsonValue())
    out.put("approved", approved.toJsonValue())
    out.put("denied", denied.toJsonValue())
    out.put("recovered", recovered.toJsonValue())
    out.put("inactive", inactive.toJsonValue())
    out.put("actionsNeeded", (pending + denied).toJsonValue())
    out.put("auditState", JsonString(if (pending > 0) { "approval-required" } else if (denied > 0) { "denied" } else if (approved > 0) { "approved" } else { "idle" }))
    out.put("policy", policy)
    out
}

public func gatewayDeviceRuntimeSummary(cfg: GatewayConfig): JsonObject {
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let byKind = JsonObject()
    let byLifecycleState = JsonObject()
    let byStatus = JsonObject()
    let byAuthState = JsonObject()
    var activeCount: Int64 = 0
    var inactiveCount: Int64 = 0
    var trustedCount: Int64 = 0
    var revokedCount: Int64 = 0
    var transitionCount: Int64 = 0
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let kind = readJsonString(row, "kind", "unknown")
        let lifecycleState = readJsonString(row, "lifecycleState", "")
        let status = readJsonString(row, "status", "")
        let authState = readJsonString(row, "authState", "")
        let kindCount = match (byKind.get(kind)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byKind.put(kind, (kindCount + 1).toJsonValue())
        let lifecycleCount = match (byLifecycleState.get(lifecycleState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byLifecycleState.put(lifecycleState, (lifecycleCount + 1).toJsonValue())
        let statusCount = match (byStatus.get(status)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byStatus.put(status, (statusCount + 1).toJsonValue())
        let authCount = match (byAuthState.get(authState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byAuthState.put(authState, (authCount + 1).toJsonValue())
        if (status == "active") {
            activeCount += 1
        } else {
            inactiveCount += 1
        }
        if (authState == "validated" || authState == "refreshed") {
            trustedCount += 1
        }
        if (authState == "revoked") {
            revokedCount += 1
        }
        transitionCount += readJsonInt(row, "authTransitionCount", 0)
    }
    let out = JsonObject()
    out.put("count", items.size().toJsonValue())
    out.put("active", activeCount.toJsonValue())
    out.put("inactive", inactiveCount.toJsonValue())
    out.put("trusted", trustedCount.toJsonValue())
    out.put("revoked", revokedCount.toJsonValue())
    out.put("transitionCount", transitionCount.toJsonValue())
    out.put("byKind", byKind)
    out.put("byLifecycleState", byLifecycleState)
    out.put("byStatus", byStatus)
    out.put("byAuthState", byAuthState)
    out
}

public func gatewayDevicePresenceSummary(cfg: GatewayConfig): JsonObject {
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let items = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let now = nowMs()
    let staleThreshold: Int64 = 5 * 60 * 1000
    let byPresence = JsonObject()
    var reachable: Int64 = 0
    var stale: Int64 = 0
    var inactive: Int64 = 0
    var controlUiDevices: Int64 = 0
    var lastSeenAtMs: Int64 = 0
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let status = readJsonString(row, "status", "")
        let seenAt = readJsonInt(row, "lastSeenAtMs", 0)
        if (seenAt > lastSeenAtMs) {
            lastSeenAtMs = seenAt
        }
        let presence = if (status != "active") {
            inactive += 1
            "inactive"
        } else if (seenAt > 0 && now - seenAt > staleThreshold) {
            stale += 1
            "stale"
        } else {
            reachable += 1
            "reachable"
        }
        let current = match (byPresence.get(presence)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byPresence.put(presence, (current + 1).toJsonValue())
        let controlUiEnabled = match (row.get("controlUiEnabled")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_inner: Exception) { false }
            case None => false
        }
        if (controlUiEnabled) {
            controlUiDevices += 1
        }
    }
    let out = JsonObject()
    out.put("count", items.size().toJsonValue())
    out.put("reachable", reachable.toJsonValue())
    out.put("stale", stale.toJsonValue())
    out.put("inactive", inactive.toJsonValue())
    out.put("controlUiDevices", controlUiDevices.toJsonValue())
    out.put("lastSeenAtMs", lastSeenAtMs.toJsonValue())
    out.put("byPresence", byPresence)
    out.put("presenceState", JsonString(if (reachable > 0) { "reachable" } else if (stale > 0) { "stale" } else { "inactive" }))
    out
}

public func gatewayPushLifecycleSummary(cfg: GatewayConfig): JsonObject {
    let push = makePushJson(cfg)
    let summary = match (push.get("summary")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let out = JsonObject()
    out.put("deliveryCount", push.get("deliveryCount") ?? 0.toJsonValue())
    out.put("retryingDeliveries", summary.get("retryingDeliveries") ?? 0.toJsonValue())
    out.put("failedDeliveries", summary.get("failedDeliveries") ?? 0.toJsonValue())
    out.put("byStatus", summary.get("byStatus") ?? JsonObject())
    out.put("byLifecycleState", summary.get("byLifecycleState") ?? JsonObject())
    out
}

public func gatewayPushDispatcherSummary(cfg: GatewayConfig): JsonObject {
    let push = makePushJson(cfg)
    let items = match (push.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let byChannel = JsonObject()
    let byTarget = JsonObject()
    let byPhase = JsonObject()
    let byTargetState = JsonObject()
    let devicesRoot = match (gatewayPlatformSnapshot(cfg).get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let deviceItems = match (devicesRoot.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var inFlight: Int64 = 0
    var retrying: Int64 = 0
    var terminal: Int64 = 0
    var attemptCount: Int64 = 0
    var wakeTargets: Int64 = 0
    var inactiveTargets: Int64 = 0
    var unknownTargets: Int64 = 0
    var recoverableDeliveries: Int64 = 0
    var lastAttemptAtMs: Int64 = 0
    for (i in 0..items.size()) {
        let row = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
        let channel = readJsonString(row, "channel", "local")
        let target = readJsonString(row, "targetId", "unknown")
        let phase = readJsonString(row, "phase", gatewayPushPhase(readJsonString(row, "lifecycleState", ""), readJsonString(row, "status", "")))
        let status = readJsonString(row, "status", "")
        let attemptAt = readJsonInt(row, "lastAttemptAtMs", 0)
        if (attemptAt > lastAttemptAtMs) {
            lastAttemptAtMs = attemptAt
        }
        let channelCount = match (byChannel.get(channel)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byChannel.put(channel, (channelCount + 1).toJsonValue())
        let targetCount = match (byTarget.get(target)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byTarget.put(target, (targetCount + 1).toJsonValue())
        let phaseCount = match (byPhase.get(phase)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byPhase.put(phase, (phaseCount + 1).toJsonValue())
        attemptCount += readJsonInt(row, "attempt", 1)
        var targetState = "unknown"
        for (j in 0..deviceItems.size()) {
            let device = try { deviceItems[j].asObject() } catch (_e: Exception) { JsonObject() }
            if (readJsonString(device, "id", "") == target) {
                targetState = if (readJsonString(device, "status", "") == "active") { "reachable" } else { "inactive" }
                break
            }
        }
        let stateCount = match (byTargetState.get(targetState)) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_inner: Exception) { 0 }
            case None => 0
        }
        byTargetState.put(targetState, (stateCount + 1).toJsonValue())
        if (targetState == "reachable" || targetState == "stale") {
            wakeTargets += 1
        } else if (targetState == "inactive") {
            inactiveTargets += 1
        } else {
            unknownTargets += 1
        }
        if (status == "failed" || status == "retried") {
            recoverableDeliveries += 1
        }
        if (status == "sent" || status == "retrying" || status == "recorded") {
            inFlight += 1
        }
        if (status == "retrying") {
            retrying += 1
        }
        if (status == "failed" || status == "delivered") {
            terminal += 1
        }
    }
    let out = JsonObject()
    out.put("deliveryCount", items.size().toJsonValue())
    out.put("attemptCount", attemptCount.toJsonValue())
    out.put("inFlight", inFlight.toJsonValue())
    out.put("retrying", retrying.toJsonValue())
    out.put("terminal", terminal.toJsonValue())
    out.put("dispatcherState", JsonString(if (retrying > 0 || inFlight > 0) { "active" } else if (items.size() > 0) { "idle" } else { "empty" }))
    out.put("wakeTargets", wakeTargets.toJsonValue())
    out.put("inactiveTargets", inactiveTargets.toJsonValue())
    out.put("unknownTargets", unknownTargets.toJsonValue())
    out.put("recoverableDeliveries", recoverableDeliveries.toJsonValue())
    out.put("lastAttemptAtMs", lastAttemptAtMs.toJsonValue())
    out.put("byChannel", byChannel)
    out.put("byTarget", byTarget)
    out.put("byPhase", byPhase)
    out.put("byTargetState", byTargetState)
    out
}

public func gatewayPushOrchestrationSummary(cfg: GatewayConfig): JsonObject {
    let dispatcher = gatewayPushDispatcherSummary(cfg)
    let presence = gatewayDevicePresenceSummary(cfg)
    let lifecycle = gatewayPushLifecycleSummary(cfg)
    let devicePolicy = gatewayDeviceApprovalPolicySummary(cfg)
    let out = JsonObject()
    let wakeTargets = readJsonInt(dispatcher, "wakeTargets", 0)
    let inactiveTargets = readJsonInt(dispatcher, "inactiveTargets", 0)
    let unknownTargets = readJsonInt(dispatcher, "unknownTargets", 0)
    let retrying = readJsonInt(dispatcher, "retrying", 0)
    let terminal = readJsonInt(dispatcher, "terminal", 0)
    let pendingApprovals = match (devicePolicy.get("approvalRequired")) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
    let reachableDevices = readJsonInt(presence, "reachable", 0)
    let staleDevices = readJsonInt(presence, "stale", 0)
    let inactiveDevices = readJsonInt(presence, "inactive", 0)
    let dispatcherState = readJsonString(dispatcher, "dispatcherState", "empty")
    let presenceState = readJsonString(presence, "presenceState", "inactive")
    let approvalPolicyState = readJsonString(devicePolicy, "policyState", "empty")
    out.put("wakeTargets", wakeTargets.toJsonValue())
    out.put("inactiveTargets", inactiveTargets.toJsonValue())
    out.put("unknownTargets", unknownTargets.toJsonValue())
    out.put("recoverableTargets", (inactiveTargets + unknownTargets).toJsonValue())
    out.put("retryingDeliveries", lifecycle.get("retryingDeliveries") ?? 0.toJsonValue())
    out.put("failedDeliveries", lifecycle.get("failedDeliveries") ?? 0.toJsonValue())
    out.put("reachableDevices", reachableDevices.toJsonValue())
    out.put("staleDevices", staleDevices.toJsonValue())
    out.put("inactiveDevices", inactiveDevices.toJsonValue())
    out.put("dispatcherState", JsonString(dispatcherState))
    out.put("presenceState", JsonString(presenceState))
    out.put("approvalPolicyState", JsonString(approvalPolicyState))
    let byAction = JsonObject()
    byAction.put("wake", wakeTargets.toJsonValue())
    byAction.put("recover", inactiveTargets.toJsonValue())
    byAction.put("fail", unknownTargets.toJsonValue())
    byAction.put("revalidate", pendingApprovals.toJsonValue())
    byAction.put("retry", retrying.toJsonValue())
    byAction.put("complete", terminal.toJsonValue())
    out.put("byAction", byAction)
    let deliveryPolicyState = if (pendingApprovals > 0) {
        "approval-blocked"
    } else if (unknownTargets > 0 && reachableDevices + staleDevices == 0) {
        "unreachable"
    } else if (retrying > 0 || inactiveTargets > 0) {
        "recovery-required"
    } else if (wakeTargets > 0) {
        "wake-required"
    } else if (terminal > 0) {
        "steady"
    } else {
        "idle"
    }
    let orchestratorState = if (pendingApprovals > 0) { "awaiting-approval" } else if (retrying > 0 || inactiveTargets > 0) { "recovering" } else if (wakeTargets > 0) { "waking" } else if (terminal > 0) { "steady" } else { "idle" }
    out.put("orchestratorState", JsonString(orchestratorState))
    out.put("policyState", JsonString(deliveryPolicyState))
    out.put("actionsNeeded", (inactiveTargets + unknownTargets + pendingApprovals + retrying).toJsonValue())
    let constraints = JsonArray([])
    let approvalConstraint = JsonObject()
    approvalConstraint.put("name", JsonString("approval-ready"))
    approvalConstraint.put("ok", (pendingApprovals == 0).toJsonValue())
    approvalConstraint.put("detail", JsonString("pending=${pendingApprovals}"))
    constraints.add(approvalConstraint)
    let recoverableConstraint = JsonObject()
    recoverableConstraint.put("name", JsonString("recoverable-targets"))
    recoverableConstraint.put("ok", (inactiveTargets + unknownTargets == 0).toJsonValue())
    recoverableConstraint.put("detail", JsonString("recoverable=${inactiveTargets + unknownTargets}"))
    constraints.add(recoverableConstraint)
    let retryConstraint = JsonObject()
    retryConstraint.put("name", JsonString("retry-window"))
    retryConstraint.put("ok", (retrying == 0).toJsonValue())
    retryConstraint.put("detail", JsonString("retrying=${retrying}"))
    constraints.add(retryConstraint)
    let reachableConstraint = JsonObject()
    reachableConstraint.put("name", JsonString("reachable-capacity"))
    reachableConstraint.put("ok", (reachableDevices + staleDevices > 0 || inactiveTargets + unknownTargets == 0).toJsonValue())
    reachableConstraint.put("detail", JsonString("reachable=${reachableDevices}, stale=${staleDevices}"))
    constraints.add(reachableConstraint)
    let dispatcherConstraint = JsonObject()
    dispatcherConstraint.put("name", JsonString("dispatcher-steady"))
    dispatcherConstraint.put("ok", (dispatcherState == "idle" || dispatcherState == "empty").toJsonValue())
    dispatcherConstraint.put("detail", JsonString(dispatcherState))
    constraints.add(dispatcherConstraint)
    out.put("constraints", constraints)
    let actions = JsonArray([])
    if (pendingApprovals > 0) {
        let action = JsonObject()
        action.put("method", JsonString("devices.revalidate"))
        action.put("policyState", JsonString("awaiting-approval"))
        action.put("detail", JsonString("Devices require revalidation before delivery can continue."))
        let params = JsonObject()
        params.put("target", JsonString("pending-approvals"))
        action.put("params", params)
        actions.add(action)
    }
    if (inactiveTargets > 0) {
        let action = JsonObject()
        action.put("method", JsonString("push.wake"))
        action.put("policyState", JsonString("recovering"))
        action.put("detail", JsonString("Inactive targets need wake or recovery before dispatch."))
        let params = JsonObject()
        params.put("targetState", JsonString("inactive"))
        action.put("params", params)
        actions.add(action)
    }
    if (unknownTargets > 0) {
        let action = JsonObject()
        action.put("method", JsonString("push.recover"))
        action.put("policyState", JsonString("unreachable"))
        action.put("detail", JsonString("Unknown targets need recovery or terminal failure handling."))
        let params = JsonObject()
        params.put("targetState", JsonString("unknown"))
        action.put("params", params)
        actions.add(action)
    }
    if (retrying > 0 || unknownTargets > 0) {
        let action = JsonObject()
        action.put("method", JsonString("push.orchestrate"))
        action.put("policyState", JsonString("recovering"))
        action.put("detail", JsonString("Run orchestration to retry or fail unresolved deliveries."))
        let params = JsonObject()
        params.put("channel", JsonString("local"))
        action.put("params", params)
        actions.add(action)
    }
    out.put("actions", actions)
    out
}

public func gatewayPushOrchestrationAuditSummary(cfg: GatewayConfig): JsonObject {
    let summary = gatewayPushOrchestrationSummary(cfg)
    let byAction = match (summary.get("byAction")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let wake = readJsonInt(byAction, "wake", 0)
    let recover = readJsonInt(byAction, "recover", 0)
    let fail = readJsonInt(byAction, "fail", 0)
    let revalidate = readJsonInt(byAction, "revalidate", 0)
    let retry = readJsonInt(byAction, "retry", 0)
    let out = JsonObject()
    out.put("wakeActions", wake.toJsonValue())
    out.put("recoverActions", recover.toJsonValue())
    out.put("failActions", fail.toJsonValue())
    out.put("revalidateActions", revalidate.toJsonValue())
    out.put("retryActions", retry.toJsonValue())
    out.put("actionsNeeded", (wake + recover + fail + revalidate + retry).toJsonValue())
    out.put("auditState", summary.get("orchestratorState") ?? JsonString("idle"))
    out.put("constraints", summary.get("constraints") ?? JsonArray([]))
    out.put("actions", summary.get("actions") ?? JsonArray([]))
    out.put("orchestration", summary)
    out
}

public func gatewayCanvasRuntimeSummary(cfg: GatewayConfig): JsonObject {
    let canvas = makeCanvasJson(cfg)
    let out = JsonObject()
    out.put("enabled", canvas.get("enabled") ?? false.toJsonValue())
    out.put("phase", canvas.get("phase") ?? JsonString("disabled"))
    out.put("healthy", canvas.get("healthy") ?? false.toJsonValue())
    out.put("httpUrl", canvas.get("httpUrl") ?? JsonString(""))
    out.put("root", canvas.get("root") ?? JsonString(""))
    out.put("rootPresent", canvas.get("rootPresent") ?? false.toJsonValue())
    out.put("liveReload", canvas.get("liveReload") ?? false.toJsonValue())
    out.put("assetState", canvas.get("assetState") ?? JsonString("disabled"))
    out.put("watchState", canvas.get("watchState") ?? JsonString("disabled"))
    out.put("policyState", JsonString(if (readJsonBool(canvas, "enabled", false) && readJsonBool(canvas, "rootPresent", false)) { "ready" } else if (readJsonBool(canvas, "enabled", false)) { "misconfigured" } else { "disabled" }))
    out
}

public func gatewayCanvasPipelineSummary(cfg: GatewayConfig): JsonObject {
    let runtime = gatewayCanvasRuntimeSummary(cfg)
    let out = JsonObject()
    let enabled = match (runtime.get("enabled")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let healthy = match (runtime.get("healthy")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let liveReload = match (runtime.get("liveReload")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    out.put("enabled", enabled.toJsonValue())
    out.put("healthy", healthy.toJsonValue())
    out.put("liveReload", liveReload.toJsonValue())
    out.put("pipelineState", JsonString(if (!enabled) { "disabled" } else if (healthy && liveReload) { "ready" } else if (healthy) { "serving" } else { "degraded" }))
    out.put("httpUrl", runtime.get("httpUrl") ?? JsonString(""))
    out.put("root", runtime.get("root") ?? JsonString(""))
    out.put("policyState", runtime.get("policyState") ?? JsonString("disabled"))
    out.put("remediationState", JsonString(if (!enabled) { "disabled" } else if (!healthy) { "repair-required" } else if (!liveReload) { "tunable" } else { "healthy" }))
    let constraints = JsonArray([])
    let rootPresent = JsonObject()
    rootPresent.put("name", JsonString("root-present"))
    rootPresent.put("ok", (runtime.get("rootPresent") ?? false.toJsonValue()))
    rootPresent.put("detail", runtime.get("root") ?? JsonString(""))
    constraints.add(rootPresent)
    let healthyConstraint = JsonObject()
    healthyConstraint.put("name", JsonString("runtime-healthy"))
    healthyConstraint.put("ok", healthy.toJsonValue())
    healthyConstraint.put("detail", runtime.get("assetState") ?? JsonString(""))
    constraints.add(healthyConstraint)
    let liveReloadConstraint = JsonObject()
    liveReloadConstraint.put("name", JsonString("live-reload"))
    liveReloadConstraint.put("ok", liveReload.toJsonValue())
    liveReloadConstraint.put("detail", JsonString(if (liveReload) { "watching" } else { "static" }))
    constraints.add(liveReloadConstraint)
    out.put("constraints", constraints)
    let actions = JsonArray([])
    if (enabled && !healthy) {
        let action = JsonObject()
        action.put("method", JsonString("canvas.runtime"))
        action.put("policyState", JsonString("misconfigured"))
        action.put("detail", JsonString("Canvas is enabled but root is missing or unhealthy."))
        let params = JsonObject()
        params.put("target", JsonString("canvas-root"))
        action.put("params", params)
        actions.add(action)
    }
    if (enabled && !liveReload) {
        let action = JsonObject()
        action.put("method", JsonString("canvas.pipeline"))
        action.put("policyState", JsonString("static"))
        action.put("detail", JsonString("Canvas is serving without live reload."))
        let params = JsonObject()
        params.put("target", JsonString("live-reload"))
        action.put("params", params)
        actions.add(action)
    }
    out.put("actionsNeeded", Int64(actions.size()).toJsonValue())
    out.put("actions", actions)
    out
}

public func gatewayCanvasAuditSummary(cfg: GatewayConfig): JsonObject {
    let pipeline = gatewayCanvasPipelineSummary(cfg)
    let constraints = match (pipeline.get("constraints")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let actions = match (pipeline.get("actions")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let out = JsonObject()
    out.put("auditState", pipeline.get("remediationState") ?? JsonString("healthy"))
    out.put("actionsNeeded", pipeline.get("actionsNeeded") ?? 0.toJsonValue())
    out.put("constraints", constraints)
    out.put("actions", actions)
    out.put("pipeline", pipeline)
    out
}

public func gatewayTalkRuntimeSummary(cfg: GatewayConfig): JsonObject {
    let talk = makeTalkJson(cfg)
    let out = JsonObject()
    out.put("provider", talk.get("provider") ?? JsonString(""))
    out.put("phase", talk.get("phase") ?? JsonString("disabled"))
    out.put("healthy", talk.get("healthy") ?? false.toJsonValue())
    out.put("interruptOnSpeech", talk.get("interruptOnSpeech") ?? false.toJsonValue())
    out.put("silenceTimeoutMs", talk.get("silenceTimeoutMs") ?? 0.toJsonValue())
    out.put("providerConfigured", talk.get("providerConfigured") ?? false.toJsonValue())
    out.put("inputState", talk.get("inputState") ?? JsonString("disabled"))
    out.put("outputState", talk.get("outputState") ?? JsonString("disabled"))
    out.put("policyState", JsonString(if (readJsonBool(talk, "providerConfigured", false)) { "ready" } else { "disabled" }))
    out
}

public func gatewayTalkPipelineSummary(cfg: GatewayConfig): JsonObject {
    let runtime = gatewayTalkRuntimeSummary(cfg)
    let out = JsonObject()
    let provider = readJsonString(runtime, "provider", "")
    let healthy = match (runtime.get("healthy")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let interruptOnSpeech = match (runtime.get("interruptOnSpeech")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    out.put("provider", JsonString(provider))
    out.put("healthy", healthy.toJsonValue())
    out.put("interruptOnSpeech", interruptOnSpeech.toJsonValue())
    out.put("silenceTimeoutMs", runtime.get("silenceTimeoutMs") ?? 0.toJsonValue())
    out.put("pipelineState", JsonString(if (provider.isEmpty()) { "disabled" } else if (healthy) { "ready" } else { "degraded" }))
    out.put("policyState", runtime.get("policyState") ?? JsonString("disabled"))
    out.put("inputState", runtime.get("inputState") ?? JsonString("disabled"))
    out.put("outputState", runtime.get("outputState") ?? JsonString("disabled"))
    out.put("remediationState", JsonString(if (provider.isEmpty()) { "configure-provider" } else if (!healthy) { "validate-provider" } else { "healthy" }))
    let constraints = JsonArray([])
    let providerConstraint = JsonObject()
    providerConstraint.put("name", JsonString("provider-configured"))
    providerConstraint.put("ok", (!provider.isEmpty()).toJsonValue())
    providerConstraint.put("detail", JsonString(provider))
    constraints.add(providerConstraint)
    let healthyConstraint = JsonObject()
    healthyConstraint.put("name", JsonString("provider-healthy"))
    healthyConstraint.put("ok", healthy.toJsonValue())
    healthyConstraint.put("detail", JsonString(if (healthy) { "ready" } else { "degraded" }))
    constraints.add(healthyConstraint)
    let timeoutConstraint = JsonObject()
    let silenceTimeoutMs = readJsonInt(runtime, "silenceTimeoutMs", 0)
    timeoutConstraint.put("name", JsonString("silence-timeout"))
    timeoutConstraint.put("ok", (silenceTimeoutMs >= 500).toJsonValue())
    timeoutConstraint.put("detail", JsonString("silenceTimeoutMs=${silenceTimeoutMs}"))
    constraints.add(timeoutConstraint)
    out.put("constraints", constraints)
    let actions = JsonArray([])
    if (provider.isEmpty()) {
        let action = JsonObject()
        action.put("method", JsonString("talk.runtime"))
        action.put("policyState", JsonString("disabled"))
        action.put("detail", JsonString("Talk runtime needs a provider before the pipeline can run."))
        let params = JsonObject()
        params.put("target", JsonString("provider"))
        action.put("params", params)
        actions.add(action)
    } else if (!healthy) {
        let action = JsonObject()
        action.put("method", JsonString("talk.pipeline"))
        action.put("policyState", JsonString("degraded"))
        action.put("detail", JsonString("Talk provider is configured but the pipeline is not healthy."))
        let params = JsonObject()
        params.put("target", JsonString(provider))
        action.put("params", params)
        actions.add(action)
    }
    if (silenceTimeoutMs < 500) {
        let action = JsonObject()
        action.put("method", JsonString("talk.pipeline"))
        action.put("policyState", JsonString("tuning-required"))
        action.put("detail", JsonString("Talk pipeline silence timeout is too low for stable interaction."))
        let params = JsonObject()
        params.put("silenceTimeoutMs", 500.toJsonValue())
        action.put("params", params)
        actions.add(action)
    }
    out.put("actionsNeeded", Int64(actions.size()).toJsonValue())
    out.put("actions", actions)
    out
}

public func gatewayTalkAuditSummary(cfg: GatewayConfig): JsonObject {
    let pipeline = gatewayTalkPipelineSummary(cfg)
    let constraints = match (pipeline.get("constraints")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let actions = match (pipeline.get("actions")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let out = JsonObject()
    out.put("auditState", pipeline.get("remediationState") ?? JsonString("healthy"))
    out.put("actionsNeeded", pipeline.get("actionsNeeded") ?? 0.toJsonValue())
    out.put("constraints", constraints)
    out.put("actions", actions)
    out.put("pipeline", pipeline)
    out
}

public func gatewayRunPendingWorkExecutor(nodeId!: String = "local-gateway"): JsonObject {
    let startedAtMs = nowMs()
    let claimed = gatewayClaimPendingWork(nodeId)
    let rows = match (claimed.get("claimed")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    if (rows.size() == 0) {
        let result = JsonObject()
        result.put("claimed", rows)
        result.put("completed", JsonArray([]))
        result.put("summary", gatewayPendingWorkExecutorSummary())
        result.put("startedAtMs", startedAtMs.toJsonValue())
        result.put("finishedAtMs", nowMs().toJsonValue())
        return result
    }
    let first = try {
        rows[0].asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
    let workId = match (first.get("id")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_inner: Exception) { "" }
        case None => ""
    }
    let completed = gatewayCompletePendingWork(workId, nodeId)
    let result = JsonObject()
    result.put("claimed", rows)
    result.put("completed", completed.get("completed") ?? JsonArray([]))
    result.put("nodeId", JsonString(nodeId))
    result.put("summary", gatewayPendingWorkExecutorSummary())
    result.put("startedAtMs", startedAtMs.toJsonValue())
    result.put("finishedAtMs", nowMs().toJsonValue())
    result
}

public func gatewayPlatformRuntimeSummary(cfg: GatewayConfig): JsonObject {
    let platform = gatewayPlatformSnapshot(cfg)
    let summary = JsonObject()
    summary.put("nodes", platform.get("nodes") ?? JsonObject())
    summary.put("devices", platform.get("devices") ?? JsonObject())
    summary.put("push", makePushJson(cfg))
    summary.put("executor", gatewayPendingWorkExecutorSummary())
    summary.put("pendingWork", gatewayPendingWorkSnapshot())
    summary.put("backlog", gatewayPendingWorkBacklogSummary())
    summary.put("nodePolicy", gatewayNodeSchedulerPolicySummary(cfg))
    summary.put("nodePolicyAudit", gatewayNodeSchedulingAuditSummary(cfg))
    summary.put("canvasRuntime", gatewayCanvasRuntimeSummary(cfg))
    summary.put("canvasPipeline", gatewayCanvasPipelineSummary(cfg))
    summary.put("canvasAudit", gatewayCanvasAuditSummary(cfg))
    summary.put("talkRuntime", gatewayTalkRuntimeSummary(cfg))
    summary.put("talkPipeline", gatewayTalkPipelineSummary(cfg))
    summary.put("talkAudit", gatewayTalkAuditSummary(cfg))
    summary.put("deviceRuntime", gatewayDeviceRuntimeSummary(cfg))
    summary.put("devicePresence", gatewayDevicePresenceSummary(cfg))
    summary.put("devicePolicy", gatewayDeviceApprovalPolicySummary(cfg))
    summary.put("devicePolicyAudit", gatewayDeviceApprovalAuditSummary(cfg))
    summary.put("pushDispatcher", gatewayPushDispatcherSummary(cfg))
    summary.put("pushOrchestration", gatewayPushOrchestrationSummary(cfg))
    summary.put("pushOrchestrationAudit", gatewayPushOrchestrationAuditSummary(cfg))
    let paths = JsonObject()
    paths.put("platformState", JsonString(gatewayPlatformStatePath()))
    paths.put("nodeRegistry", JsonString(gatewayNodeRegistryPath()))
    paths.put("pendingWork", JsonString(gatewayPendingWorkPath()))
    paths.put("pushDeliveries", JsonString(gatewayPushDeliveriesPath()))
    summary.put("paths", paths)
    let counts = JsonObject()
    let nodes = match (platform.get("nodes")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let devices = match (platform.get("devices")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let push = makePushJson(cfg)
    counts.put("nodes", nodes.get("count") ?? 0.toJsonValue())
    counts.put("devices", devices.get("count") ?? 0.toJsonValue())
    counts.put("pushDeliveries", push.get("deliveryCount") ?? 0.toJsonValue())
    summary.put("counts", counts)
    let nodeHealth = JsonObject()
    let nodeItems = match (nodes.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var onlineNodes: Int64 = 0
    var offlineNodes: Int64 = 0
    for (i in 0..nodeItems.size()) {
        let row = try {
            nodeItems[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let status = match (row.get("status")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (status == "online") {
            onlineNodes += 1
        } else {
            offlineNodes += 1
        }
    }
    nodeHealth.put("online", onlineNodes.toJsonValue())
    nodeHealth.put("offline", offlineNodes.toJsonValue())
    summary.put("nodeHealth", nodeHealth)
    summary.put("nodeLifecycle", gatewayNodeLifecycleSummary(cfg))
    summary.put("nodeScheduler", gatewayPendingWorkExecutorSummary())
    let deviceHealth = JsonObject()
    let deviceItems = match (devices.get("items")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var activeDevices: Int64 = 0
    var inactiveDevices: Int64 = 0
    for (i in 0..deviceItems.size()) {
        let row = try {
            deviceItems[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let status = match (row.get("status")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (status == "active") {
            activeDevices += 1
        } else {
            inactiveDevices += 1
        }
    }
    deviceHealth.put("active", activeDevices.toJsonValue())
    deviceHealth.put("inactive", inactiveDevices.toJsonValue())
    summary.put("deviceHealth", deviceHealth)
    summary.put("deviceAuth", gatewayDeviceAuthSummary(cfg))
    summary.put("pushLifecycle", gatewayPushLifecycleSummary(cfg))
    let health = JsonObject()
    health.put("healthy", true.toJsonValue())
    health.put("executorState", gatewayPendingWorkExecutorSummary().get("executorState") ?? JsonString("idle"))
    health.put("running", platform.get("running") ?? false.toJsonValue())
    summary.put("health", health)
    summary.put("updatedAtMs", platform.get("updatedAtMs") ?? 0.toJsonValue())
    summary
}

public func gatewayPlatformMarkRunning(cfg: GatewayConfig): Unit {
    writeJsonObjectFile(gatewayNodeRegistryPath(), gatewayRegisterOrHeartbeatNode(cfg, localNodeId(), running: true, status: "online", lifecycleState: "running"))
    writePlatformState(buildPlatformState(cfg, true))
}

public func gatewayPlatformHeartbeat(cfg: GatewayConfig): Unit {
    let nodeState = gatewayRegisterOrHeartbeatNode(cfg, localNodeId(), running: true, status: "online", lifecycleState: "running")
    writeJsonObjectFile(gatewayNodeRegistryPath(), nodeState)
    let platform = buildPlatformState(cfg, true)
    writePlatformState(platform)
    try {
        let nodeBytes = File.readFrom(Path(gatewayNodeRegistryPath())).size
        let platformBytes = File.readFrom(Path(gatewayPlatformStatePath())).size
        let nodesRoot = try {
            (nodeState.get("nodes") ?? JsonObject()).asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let items = try {
            (nodesRoot.get("items") ?? JsonArray([])).asArray()
        } catch (_e: Exception) {
            JsonArray([])
        }
        if (items.size() > 0) {
            let node = try {
                items[0].asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
            let heartbeatCount = readJsonInt(node, "heartbeatCount", 0)
            let lifecycleHistory = match (node.get("lifecycleHistory")) {
                case Some(v) =>
                    try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
                case None => JsonArray([])
            }
            if (heartbeatCount == 1 || heartbeatCount % 100 == 0) {
                LogUtils.info(
                    "Gateway.platform: heartbeat persisted nodeBytes=${nodeBytes} platformBytes=${platformBytes} heartbeatCount=${heartbeatCount} lifecycleHistorySize=${lifecycleHistory.size()}"
                )
            }
        }
    } catch (_e: Exception) {
        ()
    }
}

public func gatewayPlatformMarkStopped(cfg: GatewayConfig): Unit {
    writeJsonObjectFile(gatewayNodeRegistryPath(), gatewayRegisterOrHeartbeatNode(cfg, localNodeId(), running: false, status: "offline", lifecycleState: "stopped"))
    writePlatformState(buildPlatformState(cfg, false))
}

public func gatewayPlatformSnapshot(cfg: GatewayConfig): JsonObject {
    let state = readPlatformState()
    match (state.get("running")) {
        case Some(_) => return state
        case None => ()
    }
    buildPlatformState(cfg, false)
}

private func nowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}
