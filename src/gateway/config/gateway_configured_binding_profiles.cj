package metis.gateway.config

import metis.core.config.GatewayUserSettings

import magic.jsonable.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

public func gatewayConfiguredBindingRowJson(
    channelId: String,
    pluginId: String,
    accountId: String,
    enabled: Bool,
    configured: Bool,
    autoEnabled: Bool,
    origin!: String = "builtin"
): JsonObject {
    let row = JsonObject()
    row.put("channelId", JsonString(channelId))
    row.put("pluginId", JsonString(pluginId))
    row.put("accountId", JsonString(accountId))
    row.put("defaultAccountId", JsonString(accountId))
    row.put("enabled", enabled.toJsonValue())
    row.put("configured", configured.toJsonValue())
    row.put("autoEnabled", autoEnabled.toJsonValue())
    row.put("origin", JsonString(origin))
    row.put("bindingKind", JsonString("configured"))
    row
}

public func gatewayConfiguredBuiltinBindingRows(user: GatewayUserSettings): JsonArray {
    let rows = JsonArray([])
    let feishuConfigured = !user.feishu.appId.trimAscii().isEmpty()
    rows.add(gatewayConfiguredBindingRowJson(
        "feishu",
        "feishu",
        "feishu:default",
        user.feishu.enabled,
        feishuConfigured,
        user.feishu.enabled
    ))

    let qqConfigured = !(user.qq.appId.trimAscii().isEmpty() || user.qq.appSecret.trimAscii().isEmpty())
    rows.add(gatewayConfiguredBindingRowJson(
        "qq",
        "qq",
        "qq:default",
        user.qq.enabled,
        qqConfigured,
        user.qq.enabled
    ))

    rows.add(gatewayConfiguredBindingRowJson(
        "telegram",
        "telegram",
        "telegram:default",
        user.telegram.enabled,
        !(user.telegram.botToken.trimAscii().isEmpty() && user.telegram.tokenFile.trimAscii().isEmpty() && user.telegram.webhookUrl.trimAscii().isEmpty()),
        user.telegram.enabled
    ))

    for (channelId in ["slack", "discord"]) {
        let configured = gatewayBuiltinExtraChannelConfigPresent(user, channelId)
        let enabled = gatewayBuiltinExtraChannelEnabled(user, channelId)
        rows.add(gatewayConfiguredBindingRowJson(
            channelId,
            channelId,
            "${channelId}:default",
            enabled,
            configured,
            enabled
        ))
    }
    rows
}

public func gatewayConfiguredBuiltinPrimeEntries(user: GatewayUserSettings): JsonArray {
    let rows = JsonArray([])
    let configuredBindings = gatewayConfiguredBuiltinBindingRows(user)
    for (i in 0..configuredBindings.size()) {
        let row = try { configuredBindings[i].asObject() } catch (_e: Exception) { JsonObject() }
        let configured = match (row.get("configured")) {
            case Some(v) => try { v.asBool().getValue() } catch (_e2: Exception) { false }
            case None => false
        }
        if (!configured) {
            continue
        }
        let primed = JsonObject()
        primed.put("channelId", row.get("channelId") ?? JsonString(""))
        primed.put("accountId", row.get("accountId") ?? JsonString(""))
        primed.put("configuredBinding", true.toJsonValue())
        primed.put("autoEnabled", row.get("autoEnabled") ?? false.toJsonValue())
        primed.put("detail", JsonString("configured-binding-primed"))
        rows.add(primed)
    }
    rows
}

public func gatewayConfiguredPluginDefaultBindingRow(
    pluginId: String,
    enabled: Bool,
    configured: Bool,
    origin!: String = "registered"
): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    gatewayConfiguredBindingRowJson(
        normalized,
        normalized,
        "${normalized}:default",
        enabled,
        configured,
        enabled,
        origin: origin
    )
}

public func gatewayConfiguredPrimeEntryFromBindingRow(row: JsonObject): JsonObject {
    let primed = JsonObject()
    primed.put("channelId", row.get("channelId") ?? JsonString(""))
    primed.put("accountId", row.get("accountId") ?? JsonString(""))
    primed.put("configuredBinding", true.toJsonValue())
    primed.put("autoEnabled", row.get("autoEnabled") ?? false.toJsonValue())
    primed.put("detail", JsonString("configured-binding-primed"))
    primed
}

public func gatewayConfiguredPrimedBindings(rows: JsonArray): JsonArray {
    let primedBindings = JsonArray([])
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        let configured = match (row.get("configured")) {
            case Some(v) => try { v.asBool().getValue() } catch (_e2: Exception) { false }
            case None => false
        }
        if (!configured) {
            continue
        }
        let primed = gatewayConfiguredPrimeEntryFromBindingRow(row)
        primed.put("pluginId", row.get("pluginId") ?? JsonString(""))
        primed.put("defaultAccountId", row.get("defaultAccountId") ?? JsonString(""))
        primed.put("origin", row.get("origin") ?? JsonString("builtin"))
        primed.put("bindingKind", row.get("bindingKind") ?? JsonString("configured"))
        primedBindings.add(primed)
    }
    primedBindings
}

private func gatewayBindingStringField(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii().toAsciiLower() } catch (_e: Exception) { "" }
        case None => ""
    }
}

public func gatewayConfiguredBindingRowByField(rows: JsonArray, key: String, value: String): JsonObject {
    let normalized = value.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) {
        return JsonObject()
    }
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (gatewayBindingStringField(row, key) == normalized) {
            return row
        }
    }
    JsonObject()
}
