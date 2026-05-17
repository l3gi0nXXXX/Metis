package metis.gateway.config

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonBool, JsonObject, JsonString}

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

private func findProfileAccount(
    profiles: Array<GatewayAdapterRegistrationProfile>,
    channelId: String,
    accountId: String
): GatewayAdapterRegistrationProfile {
    for (profile in profiles) {
        if (profile.channelId == channelId && profile.accountId == accountId) {
            return profile
        }
    }
    throw Exception("expected configured account profile: ${channelId}/${accountId}")
}

@Test
public class GatewayAdapterRegistrationProfilesTest {
    @TestCase
    public func builtinProfilesCaptureBuiltinGatewayAdapterPlan(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.appId = "feishu-app"
        user.feishu.appSecret = "feishu-secret"
        user.qq.enabled = true
        user.qq.appId = "qq-app"
        user.qq.appSecret = "qq-secret"

        let profiles = gatewayBuiltinAdapterRegistrationProfiles(user, true)
        @Expect(profiles.size, 5)

        let feishu = findProfile(profiles, "feishu")
        @Expect(feishu.accountId, "default")
        @Expect(feishu.enabled, true)
        @Expect(feishu.configured, true)
        @Expect(feishu.healthMonitorEnabled, true)

        let qq = findProfile(profiles, "qq")
        @Expect(qq.accountId, "default")
        @Expect(qq.enabled, true)
        @Expect(qq.configured, true)

        let telegram = findProfile(profiles, "telegram")
        @Expect(telegram.accountId, "default")
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

    @TestCase
    public func builtinProfilesEnumerateConfiguredImAccountsWithPureAccountIds(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.appId = "feishu-default-app"
        user.feishu.appSecret = "feishu-default-secret"
        let feishuAccounts = JsonObject()
        let feishuWriter = JsonObject()
        feishuWriter.put("appId", JsonString("feishu-writer-app"))
        feishuWriter.put("appSecret", JsonString("feishu-writer-secret"))
        feishuAccounts.put("feishu:feishu-writer", feishuWriter)
        user.feishu.accounts = Some(feishuAccounts)

        user.telegram.enabled = true
        user.telegram.botToken = "100000:default"
        let telegramAccounts = JsonObject()
        let telegramWriter = JsonObject()
        telegramWriter.put("botToken", JsonString("100001:writer"))
        telegramAccounts.put("telegram:tg-writer", telegramWriter)
        user.telegram.accounts = Some(telegramAccounts)

        user.qq.enabled = true
        user.qq.appId = "qq-default-app"
        user.qq.appSecret = "qq-default-secret"
        let qqAccounts = JsonObject()
        let qqWriter = JsonObject()
        qqWriter.put("appId", JsonString("qq-writer-app"))
        qqWriter.put("appSecret", JsonString("qq-writer-secret"))
        qqAccounts.put("qq:qq-writer", qqWriter)
        user.qq.accounts = Some(qqAccounts)

        let profiles = gatewayBuiltinAdapterRegistrationProfiles(user, false)
        @Expect(findProfileAccount(profiles, "feishu", "default").configured, true)
        @Expect(findProfileAccount(profiles, "feishu", "feishu-writer").configured, true)
        @Expect(findProfileAccount(profiles, "telegram", "default").configured, true)
        @Expect(findProfileAccount(profiles, "telegram", "tg-writer").configured, true)
        @Expect(findProfileAccount(profiles, "qq", "default").configured, true)
        @Expect(findProfileAccount(profiles, "qq", "qq-writer").configured, true)
    }

    @TestCase
    public func accountOverrideCanDisableProfileWithoutDroppingStatusRow(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        let accounts = JsonObject()
        let disabled = JsonObject()
        disabled.put("enabled", JsonBool(false))
        disabled.put("botToken", JsonString("100002:disabled"))
        accounts.put("tg-disabled", disabled)
        user.telegram.accounts = Some(accounts)

        let profile = findProfileAccount(gatewayBuiltinAdapterRegistrationProfiles(user, true), "telegram", "tg-disabled")
        @Expect(profile.accountId, "tg-disabled")
        @Expect(profile.enabled, false)
        @Expect(profile.configured, true)
    }
}
