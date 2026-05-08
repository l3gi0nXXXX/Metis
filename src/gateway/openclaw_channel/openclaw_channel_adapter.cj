package metis.gateway.openclaw_channel

import metis.gateway.openclaw_channel_http.{OpenClawBridgeCallResult, OpenClawBridgeRunner, OpenClawChannelAdapterBridge, openClawChannelLifecyclePayload, openClawParseCallResult, OPENCLAW_CHANNEL_HEALTH_METHOD}

import stdx.encoding.json.JsonObject

public class OpenClawChannelCapability {
    public let pluginId: String
    public let channelId: String
    public let accountIds: Array<String>
    public let runner: OpenClawBridgeRunner
    public let meta: JsonObject
    public let capabilities: JsonObject

    public init(
        pluginId: String,
        channelId: String,
        accountIds: Array<String>,
        runner: OpenClawBridgeRunner,
        meta!: JsonObject = JsonObject(),
        capabilities!: JsonObject = JsonObject()
    ) {
        this.pluginId = pluginId.trimAscii().toAsciiLower()
        this.channelId = channelId.trimAscii().toAsciiLower()
        this.accountIds = accountIds
        this.runner = runner
        this.meta = meta
        this.capabilities = capabilities
    }
}

public func openClawChannelHealth(capability: OpenClawChannelCapability, accountId: String): OpenClawBridgeCallResult {
    openClawParseCallResult(
        capability.runner.invoke(
            OPENCLAW_CHANNEL_HEALTH_METHOD,
            openClawChannelLifecyclePayload(capability.channelId, accountId, "health")
        )
    )
}

public func openClawChannelAdapterForAccount(
    capability: OpenClawChannelCapability,
    accountId: String
): OpenClawChannelAdapterBridge {
    OpenClawChannelAdapterBridge(capability.channelId, accountId, capability.runner)
}
