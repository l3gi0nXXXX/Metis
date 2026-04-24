package metis.gateway.runtime

import metis.core.config.GatewayUserSettings
import metis.gateway.config.{
    gatewayApplyChannelDeliveryPolicy as gatewayApplyChannelDeliveryPolicyFromConfig,
    gatewayChannelSupportsJson as gatewayChannelSupportsJsonFromConfig,
    gatewayChannelSupportsMessageReply as gatewayChannelSupportsMessageReplyFromConfig,
    gatewayChannelSupportsReplyInThread as gatewayChannelSupportsReplyInThreadFromConfig,
    gatewayPluginSupportsJson as gatewayPluginSupportsJsonFromConfig
}
import stdx.encoding.json.JsonObject

public func gatewayPluginSupportsJson(user: GatewayUserSettings, pluginId: String): JsonObject {
    gatewayPluginSupportsJsonFromConfig(user, pluginId)
}

public func gatewayChannelSupportsJson(user: GatewayUserSettings, channelId: String): JsonObject {
    gatewayChannelSupportsJsonFromConfig(user, channelId)
}

public func gatewayChannelSupportsReplyInThread(supports: JsonObject): Bool {
    gatewayChannelSupportsReplyInThreadFromConfig(supports)
}

public func gatewayChannelSupportsMessageReply(supports: JsonObject): Bool {
    gatewayChannelSupportsMessageReplyFromConfig(supports)
}

public func gatewayApplyChannelDeliveryPolicy(user: GatewayUserSettings, channelId: String, delivery: JsonObject): JsonObject {
    gatewayApplyChannelDeliveryPolicyFromConfig(user, channelId, delivery)
}
