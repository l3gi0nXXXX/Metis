package metis.gateway.config

import metis.gateway.core.ChannelAdapter

import std.collection.ArrayList
import stdx.encoding.json.JsonObject

public class GatewayPreparedPluginAdapterRegistration {
    public let adapter: ChannelAdapter
    public let profile: GatewayAdapterRegistrationProfile

    public init(adapter: ChannelAdapter, profile: GatewayAdapterRegistrationProfile) {
        this.adapter = adapter
        this.profile = profile
    }
}

public func gatewayPreparedPluginAdapterRegistrations(
    extra: Option<JsonObject>,
    pluginId: String,
    plugin: GatewayChannelPlugin,
    healthMonitorEnabled: Bool
): Array<GatewayPreparedPluginAdapterRegistration> {
    let pid = pluginId.trimAscii()
    let pluginCfg = pluginConfigFromChannelsExtra(extra, pid)
    let pluginConfigured = gatewayPluginConfigPresent(extra, pid)
    let pluginCatalog = getGatewayPluginCatalogEntry(pid)
    let rows = ArrayList<GatewayPreparedPluginAdapterRegistration>()
    for (adapter in plugin.createAdapters(pluginCfg)) {
        let channelCatalog = getGatewayChannelCatalogEntry(adapter.name)
        let profile = GatewayAdapterRegistrationProfile(
            adapter.name,
            "${adapter.name}:default",
            pid,
            match (pluginCatalog) { case Some(v) => v.origin case None => "registered" },
            match (pluginCatalog) { case Some(v) => v.runtimeKind case None => "plugin-adapter" },
            match (pluginCatalog) { case Some(v) => v.compatibilityMode case None => "native-cangjie" },
            match (channelCatalog) {
                case Some(v) => v.label
                case None => match (pluginCatalog) { case Some(v) => v.label case None => adapter.name }
            },
            match (channelCatalog) {
                case Some(v) => v.detailLabel
                case None => match (pluginCatalog) { case Some(v) => v.detailLabel case None => "Gateway plugin adapter" }
            },
            true,
            pluginConfigured,
            healthMonitorEnabled
        )
        rows.add(GatewayPreparedPluginAdapterRegistration(adapter, profile))
    }
    rows.toArray()
}
