package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.config.{gatewayConfiguredBindingRowByField, gatewayConfiguredBindingRowJson, gatewayConfiguredBuiltinBindingRows, gatewayConfiguredBuiltinPrimeEntries, gatewayConfiguredPluginDefaultBindingRow, gatewayConfiguredPrimeEntryFromBindingRow, gatewayPluginConfigPresent, normalizeGatewayChannelId}
import metis.gateway.core.{gatewayChannelRuntimePrimeAccounts, gatewayLogEventInfo, gatewayLogMeta, gatewayLogProcessMemory}

import std.convert.Parsable

import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func gatewayConfiguredBindingsPrimeLog(step: String, configuredCount: Int64, queuedCount: Int64): Unit {
    gatewayLogEventInfo(
        "gateway/channel/binding",
        "channel.registered",
        "configured channel bindings primed",
        meta: gatewayLogMeta()
            .string("step", step)
            .int("configuredCount", configuredCount)
            .int("queuedPrimeCount", queuedCount)
            .object()
    )
    gatewayLogProcessMemory(
        "bindings-prime:${step}",
        note: "configuredCount=${configuredCount}, queuedPrimeCount=${queuedCount}"
    )
}

private func gatewayPrimeEntriesCount(entries: JsonArray): Int64 {
    Int64.parse(entries.size().toString())
}

private func gatewayChannelsExtraConfigObject(user: GatewayUserSettings, pluginId: String): JsonObject {
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(pluginId)) {
                case Some(v) =>
                    try { v.asObject() } catch (_e: Exception) { JsonObject() }
                case None => JsonObject()
            }
        case None => JsonObject()
    }
}

private func gatewayHostBindingsArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayHostBindingsString(obj: JsonObject, key: String, defaultValue: String): String {
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

private func gatewayHostBindingsBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayVisitLegacyConfiguredBindingRows(
    user: GatewayUserSettings,
    pluginId: String,
    enabled: Bool,
    configuredDefault: Bool,
    visit: (JsonObject) -> Unit
) {
    let normalized = normalizeGatewayChannelId(pluginId)
    if (!gatewayLegacyPluginHostCompatible(normalized)) {
        visit(gatewayConfiguredPluginDefaultBindingRow(
            normalized,
            enabled,
            configuredDefault,
            origin: "registered"
        ))
        return
    }
    let config = gatewayChannelsExtraConfigObject(user, normalized)
    let hostBindings = gatewayLegacyPluginHostConfiguredBindings(normalized, config: config)
    let hostRows = gatewayHostBindingsArray(hostBindings, "rows")
    let defaultAccountId = gatewayHostBindingsString(hostBindings, "defaultAccountId", "${normalized}:default")
    let configured = gatewayHostBindingsBool(hostBindings, "configured", configuredDefault)
    if (hostRows.size() > 0) {
        for (i in 0..hostRows.size()) {
            let item = try { hostRows[i].asObject() } catch (_e: Exception) { JsonObject() }
            let channelId = gatewayHostBindingsString(item, "channelId", normalized)
            let accountId = gatewayHostBindingsString(item, "accountId", defaultAccountId)
            let row = gatewayConfiguredBindingRowJson(
                channelId,
                normalized,
                accountId,
                enabled,
                gatewayHostBindingsBool(item, "configured", configured),
                gatewayHostBindingsBool(item, "autoEnabled", enabled),
                origin: gatewayHostBindingsString(item, "origin", "registered")
            )
            row.put("defaultAccountId", JsonString(gatewayHostBindingsString(item, "defaultAccountId", defaultAccountId)))
            visit(row)
        }
        return
    }
    let channelIds = gatewayHostBindingsArray(hostBindings, "activeChannelIds")
    let accountIds = gatewayHostBindingsArray(hostBindings, "accountIds")
    if (channelIds.size() == 0) {
        visit(gatewayConfiguredBindingRowJson(
            normalized,
            normalized,
            defaultAccountId,
            enabled,
            configured,
            enabled,
            origin: "registered"
        ))
        return
    }
    let hostAccountIds = if (accountIds.size() == 0) {
        let fallback = JsonArray([])
        fallback.add(JsonString(defaultAccountId))
        fallback
    } else {
        accountIds
    }
    for (i in 0..channelIds.size()) {
        let channelId = try { channelIds[i].asString().getValue().trimAscii() } catch (_e: Exception) { normalized }
        let effectiveChannelId = if (channelId.isEmpty()) { normalized } else { channelId }
        for (j in 0..hostAccountIds.size()) {
            let accountId = try { hostAccountIds[j].asString().getValue().trimAscii() } catch (_e2: Exception) { defaultAccountId }
            let effectiveAccountId = if (accountId.isEmpty()) { defaultAccountId } else { accountId }
            let row = gatewayConfiguredBindingRowJson(
                effectiveChannelId,
                normalized,
                effectiveAccountId,
                enabled,
                configured,
                enabled,
                origin: "registered"
            )
            row.put("defaultAccountId", JsonString(defaultAccountId))
            visit(row)
        }
    }
}

public func gatewayVisitConfiguredChannelBindingRows(user: GatewayUserSettings, visit: (JsonObject) -> Unit): Unit {
    let builtinRows = gatewayConfiguredBuiltinBindingRows(user)
    for (i in 0..builtinRows.size()) {
        let row = try { builtinRows[i].asObject() } catch (_e: Exception) { JsonObject() }
        visit(row)
    }

    for (plugin in user.gatewayPlugins) {
        let pid = plugin.id.trimAscii().toAsciiLower()
        if (pid.isEmpty()) {
            continue
        }
        let pluginConfigured = gatewayPluginConfigPresent(user.channelsExtra, pid)
        gatewayVisitLegacyConfiguredBindingRows(user, pid, plugin.enabled, pluginConfigured, visit)
    }
}

public func gatewayConfiguredChannelBindingsRegistry(user: GatewayUserSettings): JsonArray {
    let rows = JsonArray([])
    gatewayVisitConfiguredChannelBindingRows(user, { row =>
        rows.add(row)
    })
    rows
}

private func gatewayReadBindingCounter(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asInt().getValue() } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayIncrementBindingCounter(obj: JsonObject, key: String): Unit {
    let next = gatewayReadBindingCounter(obj, key) + 1
    obj.put(key, next.toJsonValue())
}

public func gatewayPrimeConfiguredChannelBindingAccounts(user: GatewayUserSettings): (Int64, Int64) {
    var configuredBindingCount: Int64 = 0
    var primedBindingCount: Int64 = 0
    let primeEntries = JsonArray([])
    gatewayConfiguredBindingsPrimeLog("enter", configuredBindingCount, gatewayPrimeEntriesCount(primeEntries))

    let builtinRows = gatewayConfiguredBuiltinBindingRows(user)
    configuredBindingCount += Int64.parse(builtinRows.size().toString())
    let builtinPrimeEntries = gatewayConfiguredBuiltinPrimeEntries(user)
    for (i in 0..builtinPrimeEntries.size()) {
        primeEntries.add(builtinPrimeEntries[i])
    }
    gatewayConfiguredBindingsPrimeLog("builtin-extra", configuredBindingCount, gatewayPrimeEntriesCount(primeEntries))

    for (plugin in user.gatewayPlugins) {
        let pid = plugin.id.trimAscii().toAsciiLower()
        if (pid.isEmpty()) {
            continue
        }
        let pluginConfigured = gatewayPluginConfigPresent(user.channelsExtra, pid)
        let normalized = normalizeGatewayChannelId(pid)
        if (!gatewayLegacyPluginHostCompatible(normalized)) {
            let row = gatewayConfiguredPluginDefaultBindingRow(
                normalized,
                plugin.enabled,
                pluginConfigured,
                origin: "registered"
            )
            configuredBindingCount += 1
            if (pluginConfigured) {
                primeEntries.add(gatewayConfiguredPrimeEntryFromBindingRow(row))
            }
            continue
        }
        let config = gatewayChannelsExtraConfigObject(user, normalized)
        let summary = gatewayLegacyPluginHostConfiguredBindingsSummary(normalized, config: config)
        let defaultAccountId = gatewayHostBindingsString(summary, "defaultAccountId", "${normalized}:default")
        let configured = gatewayHostBindingsBool(summary, "configured", pluginConfigured)
        let channelIds = gatewayHostBindingsArray(summary, "activeChannelIds")
        let accountIds = gatewayHostBindingsArray(summary, "accountIds")
        let effectiveChannelIds = if (channelIds.size() == 0) {
            let fallback = JsonArray([])
            fallback.add(JsonString(normalized))
            fallback
        } else {
            channelIds
        }
        let effectiveAccountIds = if (accountIds.size() == 0) {
            let fallback = JsonArray([])
            fallback.add(JsonString(defaultAccountId))
            fallback
        } else {
            accountIds
        }
        for (i in 0..effectiveChannelIds.size()) {
            let channelId = try { effectiveChannelIds[i].asString().getValue().trimAscii() } catch (_e: Exception) { normalized }
            let effectiveChannelId = if (channelId.isEmpty()) { normalized } else { channelId }
            for (j in 0..effectiveAccountIds.size()) {
                let accountId = try { effectiveAccountIds[j].asString().getValue().trimAscii() } catch (_e2: Exception) { defaultAccountId }
                let effectiveAccountId = if (accountId.isEmpty()) { defaultAccountId } else { accountId }
                configuredBindingCount += 1
                if (configured) {
                    let row = JsonObject()
                    row.put("channelId", JsonString(effectiveChannelId))
                    row.put("accountId", JsonString(effectiveAccountId))
                    row.put("configuredBinding", true.toJsonValue())
                    row.put("autoEnabled", plugin.enabled.toJsonValue())
                    row.put("detail", JsonString("configured-binding-primed"))
                    primeEntries.add(row)
                }
            }
        }
        gatewayConfiguredBindingsPrimeLog("plugin-${normalized}", configuredBindingCount, gatewayPrimeEntriesCount(primeEntries))
    }

    gatewayConfiguredBindingsPrimeLog("before-batch-prime", configuredBindingCount, gatewayPrimeEntriesCount(primeEntries))
    primedBindingCount = gatewayChannelRuntimePrimeAccounts(primeEntries)
    gatewayConfiguredBindingsPrimeLog("after-batch-prime", configuredBindingCount, gatewayPrimeEntriesCount(primeEntries))
    (configuredBindingCount, primedBindingCount)
}

public func gatewayConfiguredChannelBindingRow(user: GatewayUserSettings, channelId: String): JsonObject {
    let rows = gatewayConfiguredChannelBindingsRegistry(user)
    gatewayConfiguredBindingRowByField(rows, "channelId", channelId)
}

public func gatewayConfiguredPluginBindingRow(user: GatewayUserSettings, pluginId: String): JsonObject {
    let rows = gatewayConfiguredChannelBindingsRegistry(user)
    gatewayConfiguredBindingRowByField(rows, "pluginId", pluginId)
}
