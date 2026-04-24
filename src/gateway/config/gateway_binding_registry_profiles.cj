package metis.gateway.config

import magic.jsonable.*

import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewayRegistryProfileBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayRegistryProfileInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayRegistryProfileFirstRuntimeAccount(accounts: JsonArray): JsonObject {
    if (accounts.size() == 0) {
        return JsonObject()
    }
    try { accounts[0].asObject() } catch (_e: Exception) { JsonObject() }
}

private func gatewayRegistryProfileConfiguredAccountIds(configured: JsonObject): JsonArray {
    let accountIds = JsonArray([])
    match (configured.get("accountId")) {
        case Some(v) => accountIds.add(v)
        case None => ()
    }
    accountIds
}

private func gatewayRegistryProfileDefaultAccountId(configured: JsonObject, defaultValue: String): JsonValue {
    match (configured.get("defaultAccountId")) {
        case Some(v) => v
        case None =>
            match (configured.get("accountId")) {
                case Some(v) => v
                case None => JsonString(defaultValue)
            }
    }
}

public func gatewayBindingRegistryRowJson(
    idKey: String,
    id: String,
    configured: JsonObject,
    runtimeAccounts: JsonArray
): JsonObject {
    let normalized = id.trimAscii().toAsciiLower()
    let runtime = gatewayRegistryProfileFirstRuntimeAccount(runtimeAccounts)
    let row = JsonObject()
    row.put(idKey, JsonString(normalized))
    row.put("configured", configured)
    row.put("runtime", runtime)
    row.put("runtimeAccounts", runtimeAccounts)
    row.put("configuredBinding", (gatewayRegistryProfileBool(configured, "configured") || gatewayRegistryProfileBool(runtime, "configuredBinding")).toJsonValue())
    row.put("primed", gatewayRegistryProfileBool(runtime, "primed").toJsonValue())
    row.put("autoEnabled", (gatewayRegistryProfileBool(runtime, "autoEnabled") || gatewayRegistryProfileBool(configured, "autoEnabled")).toJsonValue())
    row.put("bindingState", JsonString(
        if (gatewayRegistryProfileBool(runtime, "primed")) {
            "primed"
        } else if (gatewayRegistryProfileBool(configured, "configured")) {
            "configured"
        } else {
            "unprimed"
        }
    ))
    row.put("primedAtMs", gatewayRegistryProfileInt(runtime, "primedAtMs").toJsonValue())
    row.put("accountCount", runtimeAccounts.size().toJsonValue())
    let configuredAccountIds = gatewayRegistryProfileConfiguredAccountIds(configured)
    row.put("configuredAccountIds", configuredAccountIds)
    row.put("configuredAccountCount", configuredAccountIds.size().toJsonValue())
    row.put("defaultAccountId", gatewayRegistryProfileDefaultAccountId(configured, "${normalized}:default"))
    row
}

public func gatewayChannelBindingState(enabled: Bool, configured: Bool, primed: Bool): String {
    if (primed && enabled && configured) {
        return "bound"
    }
    if (enabled && configured) {
        return "configured"
    }
    if (enabled) {
        return "pending-config"
    }
    "disabled"
}

public func gatewayPluginBindingState(installed: Bool, registered: Bool, enabled: Bool, configured: Bool, primed: Bool): String {
    if (installed && registered && enabled && configured && primed) {
        return "bound"
    }
    if (installed && registered && enabled && configured) {
        return "configured"
    }
    if (installed && registered) {
        return "available"
    }
    "missing"
}

public func gatewayBindingActionsNeeded(ready: Bool): Bool {
    !ready
}
