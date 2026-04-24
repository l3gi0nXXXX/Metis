package metis.gateway.config

import metis.core.config.GatewayUserSettings

import magic.jsonable.*
import std.collection.HashMap
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

@Test
public class GatewayConfigBuilderTest {
    @TestCase
    public func mergedGatewayUserSettingsStillMapBuiltinChannelConfigs(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.appId = "cli-feishu-app"
        user.qq.enabled = true
        user.qq.appId = "cli-qq-app"

        let (feishu, qq, telegram) = mergeGatewayUserSettings(user)
        @Expect(feishu.enabled, true)
        @Expect(feishu.appId, "cli-feishu-app")
        @Expect(qq.enabled, true)
        @Expect(qq.appId, "cli-qq-app")
        @Expect(telegram.enabled, false)
    }

    @TestCase
    public func gatewayConfigBuilderStillProducesRuntimeConfigOutsideGatewayRuntimePackage(): Unit {
        var user = GatewayUserSettings()
        user.enabled = true
        user.port = 18080
        user.webchat.chatHistoryMaxChars = 4321
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"

        let cfg = buildGatewayConfigFromUserSettings(user)
        @Expect(cfg.enabled, true)
        @Expect(cfg.port, 18080)
        @Expect(cfg.webchat.chatHistoryMaxChars, 4321)
        @Expect(cfg.policyByChannel.contains("feishu"), true)
        @Expect(cfg.policyByChannel.contains("qq"), true)
        @Expect(cfg.telegram.enabled, true)
        @Expect(cfg.telegram.botToken, "telegram-token")
    }

    @TestCase
    public func pluginConfigPresenceUsesSharedGatewayConfigHelper(): Unit {
        var user = GatewayUserSettings()
        let root = JsonObject(HashMap<String, JsonValue>())
        let pluginCfg = JsonObject()
        pluginCfg.put("token", JsonString("demo-token"))
        root.put("dingtalk", pluginCfg)
        user.channelsExtra = Some(root)

        @Expect(gatewayPluginConfigPresent(user.channelsExtra, "dingtalk"), true)
        @Expect(gatewayPluginConfigPresent(user.channelsExtra, "slack"), false)
    }
}
