package metis.gateway.openclaw_channel

import metis.gateway.config.{GatewayChannelPlugin, GatewayChannelPluginRegistry}
import metis.gateway.core.ChannelAdapter
import metis.gateway.openclaw_channel_http.OpenClawBridgeRunner

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject}

private class OpenClawGatewayChannelPlugin <: GatewayChannelPlugin {
    private let capability: OpenClawChannelCapability

    public init(capability: OpenClawChannelCapability) {
        this.capability = capability
    }

    public func pluginId(): String {
        this.capability.pluginId
    }

    public func declaredChannelIds(): Array<String> {
        [this.capability.channelId]
    }

    public func createAdapters(_config: JsonObject): Array<ChannelAdapter> {
        let out = ArrayList<ChannelAdapter>()
        if (this.capability.accountIds.size == 0) {
            out.add(openClawChannelAdapterForAccount(this.capability, "default"))
        } else {
            for (accountId in this.capability.accountIds) {
                out.add(openClawChannelAdapterForAccount(this.capability, accountId))
            }
        }
        out.toArray()
    }
}

public func registerOpenClawChannelPlugin(capability: OpenClawChannelCapability): Unit {
    GatewayChannelPluginRegistry.register(OpenClawGatewayChannelPlugin(capability))
}

private func openClawCaptureObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func openClawCaptureArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func openClawCaptureString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func openClawCaptureString(obj: JsonObject, keys: Array<String>): String {
    for (key in keys) {
        let value = openClawCaptureString(obj, key)
        if (!value.isEmpty()) {
            return value
        }
    }
    ""
}

private func openClawCapturedCapabilityArray(capture: JsonObject, key: String): JsonArray {
    let direct = openClawCaptureArray(capture, key)
    if (direct.size() > 0) {
        return direct
    }
    let capabilities = openClawCaptureArray(openClawCaptureObject(capture, "capabilities"), key)
    if (capabilities.size() > 0) {
        return capabilities
    }
    let gatewayRegistries = openClawCaptureArray(openClawCaptureObject(capture, "gatewayRegistries"), key)
    if (gatewayRegistries.size() > 0) {
        return gatewayRegistries
    }
    openClawCaptureArray(openClawCaptureObject(capture, "registry"), key)
}

private func openClawCapturedAccounts(record: JsonObject, spec: JsonObject): Array<String> {
    let out = ArrayList<String>()
    let direct = openClawCaptureArray(record, "accountIds")
    let specIds = openClawCaptureArray(spec, "accountIds")
    let accounts = if (direct.size() > 0) { direct } else { specIds }
    for (i in 0..accounts.size()) {
        let accountId = try { accounts[i].asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        if (!accountId.isEmpty()) {
            out.add(accountId)
        }
    }
    out.toArray()
}

public func registerOpenClawCapturedChannelPlugins(capture: JsonObject, runner: OpenClawBridgeRunner): Int64 {
    var count: Int64 = 0
    let channels = openClawCapturedCapabilityArray(capture, "channels")
    for (i in 0..channels.size()) {
        let record = try { channels[i].asObject() } catch (_e: Exception) { JsonObject() }
        let spec = openClawCaptureObject(record, "spec")
        let pluginMeta = openClawCaptureObject(spec, "plugin")
        var channelId = openClawCaptureString(record, ["id", "name", "channelId"])
        if (channelId.isEmpty()) {
            channelId = openClawCaptureString(spec, ["id", "name", "channelId"])
        }
        var pluginId = openClawCaptureString(record, "pluginId")
        if (pluginId.isEmpty()) {
            pluginId = openClawCaptureString(pluginMeta, ["id", "name"])
        }
        if (pluginId.isEmpty()) {
            pluginId = channelId
        }
        if (channelId.isEmpty()) {
            channelId = pluginId
        }
        if (channelId.isEmpty()) {
            continue
        }
        registerOpenClawChannelPlugin(
            OpenClawChannelCapability(
                pluginId,
                channelId,
                openClawCapturedAccounts(record, spec),
                runner,
                meta: spec,
                capabilities: record
            )
        )
        count += 1
    }
    count
}
