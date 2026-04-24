package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings

import std.convert.Parsable
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewayHealthBindingBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayHealthBindingCount(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayHealthBindingString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

public func gatewayChannelHealthPolicy(user: GatewayUserSettings, channelId: String, status: JsonObject): JsonObject {
    let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let staleThresholdMs = user.channelStaleEventThresholdMinutes * 60 * 1000
    let runtime = match (status.get("runtime")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let enabled = gatewayHealthBindingBool(status, "enabled")
    let configured = gatewayHealthBindingBool(status, "configured")
    let running = gatewayHealthBindingCount(runtime, "running") > 0
    let failed = gatewayHealthBindingCount(runtime, "failed") > 0
    let backoff = gatewayHealthBindingCount(runtime, "backoff") > 0
    let restartCount = gatewayHealthBindingCount(runtime, "restartCount")
    let runtimeAccounts = match (runtime.get("accounts")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var stale: Bool = false
    var primed: Bool = false
    for (j in 0..runtimeAccounts.size()) {
        let account = try { runtimeAccounts[j].asObject() } catch (_e: Exception) { JsonObject() }
        let lastEventAtMs = gatewayHealthBindingCount(account, "lastEventAtMs")
        let bindingState = gatewayHealthBindingString(account, "bindingState", "")
        if (bindingState == "primed") {
            primed = true
        }
        if (lastEventAtMs > 0 && staleThresholdMs > 0 && now - lastEventAtMs > staleThresholdMs) {
            stale = true
        }
    }
    let healthState = if (!enabled) {
        "disabled"
    } else if (!configured) {
        "unconfigured"
    } else if (failed) {
        "failed"
    } else if (backoff) {
        "backoff"
    } else if (stale) {
        "stale"
    } else if (running) {
        "healthy"
    } else {
        "idle"
    }
    let constraints = JsonArray([])
    let configuredConstraint = JsonObject()
    configuredConstraint.put("name", JsonString("configured"))
    configuredConstraint.put("ok", configured.toJsonValue())
    configuredConstraint.put("detail", JsonString(if (configured) { "channel configured" } else { "channel configuration missing" }))
    constraints.add(configuredConstraint)
    let primedConstraint = JsonObject()
    primedConstraint.put("name", JsonString("binding-primed"))
    primedConstraint.put("ok", primed.toJsonValue())
    primedConstraint.put("detail", JsonString(if (primed) { "configured binding primed" } else { "no primed binding" }))
    constraints.add(primedConstraint)
    let restartConstraint = JsonObject()
    restartConstraint.put("name", JsonString("restart-budget"))
    restartConstraint.put("ok", (restartCount <= user.channelMaxRestartsPerHour).toJsonValue())
    restartConstraint.put("detail", JsonString("restartCount=${restartCount}, limit=${user.channelMaxRestartsPerHour}"))
    constraints.add(restartConstraint)
    let actions = JsonArray([])
    if (!configured) {
        let action = JsonObject()
        action.put("action", JsonString("configure-channel"))
        action.put("method", JsonString("channels.get"))
        let params = JsonObject()
        params.put("channelId", JsonString(channelId))
        action.put("params", params)
        actions.add(action)
    } else if (failed || backoff) {
        let action = JsonObject()
        action.put("action", JsonString("restart-channel-runtime"))
        action.put("method", JsonString("channels.runtime"))
        let params = JsonObject()
        params.put("channelId", JsonString(channelId))
        action.put("params", params)
        actions.add(action)
    } else if (stale) {
        let action = JsonObject()
        action.put("action", JsonString("probe-channel"))
        action.put("method", JsonString("channels.status"))
        let params = JsonObject()
        params.put("channelId", JsonString(channelId))
        params.put("probe", true.toJsonValue())
        action.put("params", params)
        actions.add(action)
    }
    let result = JsonObject()
    result.put("enabled", enabled.toJsonValue())
    result.put("configured", configured.toJsonValue())
    result.put("healthState", JsonString(healthState))
    result.put("constraints", constraints)
    result.put("actions", actions)
    result.put("actionsNeeded", (actions.size() > 0).toJsonValue())
    result
}

public func gatewayPluginHealthPolicy(user: GatewayUserSettings, pluginId: String, status: JsonObject): JsonObject {
    let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let staleThresholdMs = user.channelStaleEventThresholdMinutes * 60 * 1000
    let runtime = match (status.get("runtime")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let plugin = match (status.get("plugin")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let enabled = gatewayHealthBindingBool(status, "enabled")
    let configured = gatewayHealthBindingBool(status, "configured")
    let running = gatewayHealthBindingCount(runtime, "running") > 0
    let failureCount = gatewayHealthBindingCount(runtime, "failureCount")
    let restartBudget = gatewayHealthBindingCount(runtime, "restartBudget")
    let runtimeAccounts = match (runtime.get("accounts")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var stale: Bool = false
    for (j in 0..runtimeAccounts.size()) {
        let account = try { runtimeAccounts[j].asObject() } catch (_e: Exception) { JsonObject() }
        let lastEventAtMs = gatewayHealthBindingCount(account, "lastEventAtMs")
        if (lastEventAtMs > 0 && staleThresholdMs > 0 && now - lastEventAtMs > staleThresholdMs) {
            stale = true
        }
    }
    let healthState = if (!enabled) {
        "disabled"
    } else if (!configured) {
        "unconfigured"
    } else if (failureCount > 0) {
        "failed"
    } else if (stale) {
        "stale"
    } else if (running) {
        "healthy"
    } else {
        "idle"
    }
    let constraints = JsonArray([])
    let installConstraint = JsonObject()
    installConstraint.put("name", JsonString("plugin-installed"))
    installConstraint.put("ok", gatewayHealthBindingBool(plugin, "installed").toJsonValue())
    installConstraint.put("detail", JsonString("plugin installed/manifest resolved"))
    constraints.add(installConstraint)
    let configuredConstraint = JsonObject()
    configuredConstraint.put("name", JsonString("plugin-configured"))
    configuredConstraint.put("ok", configured.toJsonValue())
    configuredConstraint.put("detail", JsonString(if (configured) { "plugin runtime/config is present" } else { "plugin needs configuration" }))
    constraints.add(configuredConstraint)
    let restartConstraint = JsonObject()
    restartConstraint.put("name", JsonString("restart-budget"))
    restartConstraint.put("ok", (restartBudget <= user.channelMaxRestartsPerHour).toJsonValue())
    restartConstraint.put("detail", JsonString("restartBudget=${restartBudget}, limit=${user.channelMaxRestartsPerHour}"))
    constraints.add(restartConstraint)
    let actions = JsonArray([])
    if (!configured) {
        let action = JsonObject()
        action.put("action", JsonString("configure-plugin"))
        action.put("method", JsonString("plugins.get"))
        let params = JsonObject()
        params.put("pluginId", JsonString(pluginId))
        action.put("params", params)
        actions.add(action)
    } else if (failureCount > 0 || stale) {
        let action = JsonObject()
        action.put("action", JsonString("probe-plugin"))
        action.put("method", JsonString("plugins.status"))
        let params = JsonObject()
        params.put("pluginId", JsonString(pluginId))
        params.put("probe", true.toJsonValue())
        action.put("params", params)
        actions.add(action)
    }
    let result = JsonObject()
    result.put("enabled", enabled.toJsonValue())
    result.put("configured", configured.toJsonValue())
    result.put("healthState", JsonString(healthState))
    result.put("constraints", constraints)
    result.put("actions", actions)
    result.put("actionsNeeded", (actions.size() > 0).toJsonValue())
    result
}
