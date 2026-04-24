package metis.gateway.config

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*

private func findProfile(
    profiles: Array<GatewayAdapterRegistrationProfile>,
    channelId: String
): GatewayAdapterRegistrationProfile {
    for (profile in profiles) {
        if (profile.channelId == channelId) {
            return profile
        }
    }
    throw Exception("missing profile: ${channelId}")
}

@Test
public class GatewayAdapterRegistrationProfilesTest {
    @TestCase
    public func builtinProfilesCaptureBuiltinGatewayAdapterPlan(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.appId = "feishu-app"
        user.qq.enabled = true
        user.qq.appId = "qq-app"
        user.qq.appSecret = "qq-secret"

        let profiles = gatewayBuiltinAdapterRegistrationProfiles(user, true)
        @Expect(profiles.size, 5)

        let feishu = findProfile(profiles, "feishu")
        @Expect(feishu.enabled, true)
        @Expect(feishu.configured, true)
        @Expect(feishu.healthMonitorEnabled, true)

        let qq = findProfile(profiles, "qq")
        @Expect(qq.enabled, true)
        @Expect(qq.configured, true)

        let telegram = findProfile(profiles, "telegram")
        @Expect(telegram.pluginId, "telegram")
        @Expect(telegram.runtimeKind, "builtin-adapter")
        @Expect(telegram.enabled, false)

        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        let updated = gatewayBuiltinAdapterRegistrationProfiles(user, true)
        let configuredTelegram = findProfile(updated, "telegram")
        @Expect(configuredTelegram.enabled, true)
        @Expect(configuredTelegram.configured, true)
    }
}
