package metis.gateway.runtime

import metis.core.config.GatewayUserSettings
import metis.gateway.channels.telegram.TelegramAdapter

import std.unittest.testmacro.*

@Test
public class GatewayConfigFactoryTest {
    @TestCase
    public func buildGatewayServiceRegistersNativeTelegramAdapter(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"

        let (gateway, _feishu) = buildGatewayServiceFromUserSettings(user)
        let adapter = gateway.getAdapter("telegram")
        @Expect(adapter.isSome(), true)
        @Expect(adapter.getOrThrow() is TelegramAdapter, true)
    }
}
