package metis.gateway.config

import metis.core.config.GatewayUserSettings
import magic.jsonable.*

import std.collection.HashMap
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

@Test
public class GatewayBuiltinChannelConfigTest {
    @TestCase
    public func builtinExtraConfigHelpersShareConfiguredAndEnabledSemantics(): Unit {
        var user = GatewayUserSettings()
        let slack = JsonObject()
        slack.put("enabled", true.toJsonValue())
        slack.put("webhookUrl", JsonString("https://hooks.slack.test/demo"))
        let root = JsonObject(HashMap<String, JsonValue>())
        root.put("slack", slack)
        user.channelsExtra = Some(root)

        let slackCfg = gatewayBuiltinExtraConfig(user, "slack")
        @Expect(gatewayBuiltinExtraChannelConfigPresent(user, "slack"), true)
        @Expect(gatewayBuiltinExtraChannelEnabled(user, "slack"), true)
        @Expect(gatewayBuiltinExtraConfigured(slackCfg), true)
        @Expect(gatewayBuiltinExtraString(slackCfg, "webhookUrl"), "https://hooks.slack.test/demo")
    }

    @TestCase
    public func telegramBuiltinHelpersUseTypedTelegramSettings(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-bot-token"
        user.telegram.webhookUrl = "https://example.test/telegram-webhook"

        let telegramCfg = gatewayBuiltinExtraConfig(user, "telegram")
        @Expect(gatewayBuiltinExtraChannelConfigPresent(user, "telegram"), true)
        @Expect(gatewayBuiltinExtraChannelEnabled(user, "telegram"), true)
        @Expect(gatewayBuiltinExtraConfigured(telegramCfg), true)
        @Expect(gatewayBuiltinExtraString(telegramCfg, "botToken"), "telegram-bot-token")
    }
}
