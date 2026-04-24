package metis.gateway.runtime


import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.config.{listGatewayPluginCatalogEntries, normalizeGatewayChannelId}
import metis.gateway.core.{
    gatewayChannelRuntimeMarkMonitorEnabled,
    gatewayChannelRuntimePrimeAccount,
    gatewayChannelRuntimeRegisterAccount
}

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewayLegacyPluginConsumerString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let text = v.asString().getValue().trimAscii()
                if (text.isEmpty()) { defaultValue } else { text }
            } catch (_e: Exception) {
                defaultValue
            }
        case None => defaultValue
    }
}

private func gatewayLegacyPluginConsumerBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayLegacyPluginConsumerArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayLegacyPluginConsumerConfig(user: GatewayUserSettings, pluginId: String): JsonValue {
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(pluginId)) {
                case Some(v) => v
                case None => JsonObject()
            }
        case None => JsonObject()
    }
}

private func gatewayLegacyPluginConsumerChannelIds(inspect: JsonObject, bindings: JsonObject, pluginId: String): Array<String> {
    let ids = ArrayList<String>()
    let active = gatewayLegacyPluginConsumerArray(bindings, "activeChannelIds")
    let inspectIds = gatewayLegacyPluginConsumerArray(inspect, "channelIds")
    let source = if (active.size() > 0) { active } else { inspectIds }
    for (i in 0..source.size()) {
        try {
            let value = source[i].asString().getValue().trimAscii()
            if (!value.isEmpty()) {
                ids.add(normalizeGatewayChannelId(value))
            }
        } catch (_e: Exception) {
            ()
        }
    }
    if (ids.isEmpty()) {
        ids.add(normalizeGatewayChannelId(pluginId))
    }
    ids.toArray()
}

private func gatewayLegacyPluginConsumerAccountRows(accounts: JsonObject, bindings: JsonObject, defaultAccountId: String): JsonArray {
    let bindingAccounts = gatewayLegacyPluginConsumerArray(bindings, "accounts")
    if (bindingAccounts.size() > 0) {
        return bindingAccounts
    }
    let accountRows = gatewayLegacyPluginConsumerArray(accounts, "accounts")
    if (accountRows.size() > 0) {
        return accountRows
    }
    let accountIds = gatewayLegacyPluginConsumerArray(bindings, "accountIds")
    let rows = JsonArray([])
    for (i in 0..accountIds.size()) {
        let accountId = try { accountIds[i].asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        if (accountId.isEmpty()) {
            continue
        }
        let row = JsonObject()
        row.put("accountId", JsonString(accountId))
        row.put("configured", true.toJsonValue())
        row.put("defaultAccount", (accountId == defaultAccountId).toJsonValue())
        rows.add(row)
    }
    if (rows.size() == 0 && !defaultAccountId.isEmpty()) {
        let row = JsonObject()
        row.put("accountId", JsonString(defaultAccountId))
        row.put("configured", true.toJsonValue())
        row.put("defaultAccount", true.toJsonValue())
        rows.add(row)
    }
    rows
}

public func gatewayConsumeLegacyPluginRuntime(user: GatewayUserSettings, pluginId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    let result = JsonObject()
    result.put("pluginId", JsonString(normalized))
    if (!gatewayLegacyPluginHostCompatible(normalized)) {
        result.put("consumed", false.toJsonValue())
        result.put("reason", JsonString("not-legacy-compatible"))
        return result
    }
    let config = gatewayLegacyPluginConsumerConfig(user, normalized)
    let inspect = gatewayLegacyPluginHostInspect(normalized, config: config)
    let bindings = gatewayLegacyPluginHostBindings(normalized, config: config)
    let accounts = gatewayLegacyPluginHostAccounts(normalized, config: config)
    let defaultAccountId = gatewayLegacyPluginConsumerString(
        bindings,
        "defaultAccountId",
        gatewayLegacyPluginConsumerString(inspect, "defaultAccountId", "${normalized}:default")
    )
    let configuredBinding = gatewayLegacyPluginConsumerBool(bindings, "configuredBinding", gatewayLegacyPluginConsumerBool(bindings, "configured", false))
    let channelIds = gatewayLegacyPluginConsumerChannelIds(inspect, bindings, normalized)
    let accountRows = gatewayLegacyPluginConsumerAccountRows(accounts, bindings, defaultAccountId)
    var registeredCount: Int64 = 0
    var primedCount: Int64 = 0
    for (i in 0..accountRows.size()) {
        let accountRow = try { accountRows[i].asObject() } catch (_e: Exception) { JsonObject() }
        let accountId = gatewayLegacyPluginConsumerString(accountRow, "accountId", defaultAccountId)
        if (accountId.isEmpty()) {
            continue
        }
        let configured = gatewayLegacyPluginConsumerBool(accountRow, "configured", gatewayLegacyPluginConsumerBool(inspect, "configured", false))
        for (channelId in channelIds) {
            gatewayChannelRuntimeRegisterAccount(
                channelId,
                accountId: accountId,
                pluginId: normalized,
                label: normalized,
                detailLabel: "Legacy compatibility host account",
                origin: "registered",
                runtimeKind: "legacy-node-plugin",
                compatibilityMode: "legacy-plugin-host",
                enabled: true,
                configured: configured,
                healthMonitorEnabled: true
            )
            let _ = gatewayChannelRuntimeMarkMonitorEnabled(channelId, accountId: accountId, enabled: true)
            registeredCount += 1
            if (configured && configuredBinding) {
                let _ = gatewayChannelRuntimePrimeAccount(
                    channelId,
                    accountId: accountId,
                    configuredBinding: true,
                    autoEnabled: true,
                    detail: "legacy-host-binding-consumed"
                )
                primedCount += 1
            }
        }
    }
    result.put("consumed", true.toJsonValue())
    result.put("configuredBinding", configuredBinding.toJsonValue())
    result.put("defaultAccountId", JsonString(defaultAccountId))
    result.put("channelIds", channelIds.toJsonValue())
    result.put("registeredCount", registeredCount.toJsonValue())
    result.put("primedCount", primedCount.toJsonValue())
    result.put("accounts", accountRows)
    result
}

public func gatewayConsumeAllLegacyPluginRuntimes(user: GatewayUserSettings): JsonObject {
    let rows = JsonArray([])
    var consumedCount: Int64 = 0
    for (entry in listGatewayPluginCatalogEntries()) {
        if (entry.builtin || !gatewayLegacyPluginHostCompatible(entry.id)) {
            continue
        }
        let row = gatewayConsumeLegacyPluginRuntime(user, entry.id)
        rows.add(row)
        if (gatewayLegacyPluginConsumerBool(row, "consumed", false)) {
            consumedCount += 1
        }
    }
    let out = JsonObject()
    out.put("items", rows)
    out.put("consumedCount", consumedCount.toJsonValue())
    out
}
