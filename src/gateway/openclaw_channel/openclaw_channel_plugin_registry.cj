package metis.gateway.openclaw_channel

import metis.gateway.config.{GatewayChannelPlugin, GatewayChannelPluginRegistry}
import metis.gateway.core.ChannelAdapter

import std.collection.ArrayList
import stdx.encoding.json.JsonObject

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
