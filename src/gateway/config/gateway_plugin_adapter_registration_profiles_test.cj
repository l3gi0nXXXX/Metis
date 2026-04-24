package metis.gateway.config

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.core.ChannelAdapter
import metis.gateway.model.{InboundMessage, OutboundMessage, SendResult}

import std.collection.HashMap
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonValue}

private class TestGatewayPluginAdapter <: ChannelAdapter {
    private let adapterName: String

    public prop name: String {
        get() {
            this.adapterName
        }
    }

    public init(name: String) {
        this.adapterName = name
    }

    public func start(): Unit {}
    public func stop(): Unit {}
    public func pullInbound(): Array<InboundMessage> { [] }
    public func send(_message: OutboundMessage): SendResult { SendResult.Success }
    public func sendWithMessageId(_message: OutboundMessage): String { "" }
}

private class TestGatewayChannelPlugin <: GatewayChannelPlugin {
    public func pluginId(): String { "phase-gateway-plugin" }
    public func declaredChannelIds(): Array<String> { ["phase-gateway-plugin"] }
    public func createAdapters(_config: JsonObject): Array<ChannelAdapter> {
        [TestGatewayPluginAdapter("phase-gateway-plugin")]
    }
}

@Test
public class GatewayPluginAdapterRegistrationProfilesTest {
    @TestCase
    public func preparedPluginRegistrationsUseSharedMetadataPlan(): Unit {
        var user = GatewayUserSettings()
        let root = JsonObject(HashMap<String, JsonValue>())
        let pluginCfg = JsonObject()
        pluginCfg.put("token", "demo-token".toJsonValue())
        root.put("phase-gateway-plugin", pluginCfg)
        user.channelsExtra = Some(root)

        let rows = gatewayPreparedPluginAdapterRegistrations(
            user.channelsExtra,
            "phase-gateway-plugin",
            TestGatewayChannelPlugin(),
            true
        )
        @Expect(rows.size, 1)
        @Expect(rows[0].profile.pluginId, "phase-gateway-plugin")
        @Expect(rows[0].profile.enabled, true)
        @Expect(rows[0].profile.configured, true)
        @Expect(rows[0].profile.healthMonitorEnabled, true)
    }
}
