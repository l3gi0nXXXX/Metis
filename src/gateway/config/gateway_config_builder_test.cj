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
    public func telegramTypedOpenClawParityConfigMapsIntoRuntimeConfig(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.defaultAccount = "work"
        user.telegram.inlineButtons.scope = "group"
        user.telegram.inlineButtons.allowlist = ["tg:group:-1001"]
        user.telegram.execApprovals.enabled = "true"
        user.telegram.execApprovals.approvers = ["8734062810"]
        user.telegram.execApprovals.agentFilter = ["reviewer"]
        user.telegram.execApprovals.sessionFilter = ["telegram:group"]
        user.telegram.execApprovals.target = "both"
        user.telegram.errorPolicy.policy = "once"
        user.telegram.errorPolicy.cooldownMs = 12345
        user.telegram.errorPolicy.silentErrorReplies = true
        user.telegram.autoTopicLabel.enabled = true
        user.telegram.autoTopicLabel.strategy = "model"
        user.telegram.autoTopicLabel.prompt = "short label"

        let (_, _, telegram) = mergeGatewayUserSettings(user)
        @Expect(telegram.accountId, "work")
        @Expect(telegram.defaultAccount, "work")
        @Expect(telegram.inlineButtons.scope, "group")
        @Expect(telegram.inlineButtons.allowlist[0], "tg:group:-1001")
        @Expect(telegram.execApprovals.enabled, "true")
        @Expect(telegram.execApprovals.approvers[0], "8734062810")
        @Expect(telegram.execApprovals.agentFilter[0], "reviewer")
        @Expect(telegram.execApprovals.sessionFilter[0], "telegram:group")
        @Expect(telegram.execApprovals.target, "both")
        @Expect(telegram.errorPolicy.policy, "once")
        @Expect(telegram.errorPolicy.cooldownMs, 12345)
        @Expect(telegram.errorPolicy.silentErrorReplies, true)
        @Expect(telegram.autoTopicLabel.enabled, true)
        @Expect(telegram.autoTopicLabel.strategy, "model")
        @Expect(telegram.autoTopicLabel.prompt, "short label")
    }

    @TestCase
    public func feishuTypedOpenClawParityConfigMapsIntoRuntimeConfig(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.defaultAccount = "tenant-a"
        user.feishu.appId = "legacy-app"
        user.feishu.appSecret = "legacy-secret"
        user.feishu.threadSession = true
        user.feishu.groupPolicy = "allowlist"
        user.feishu.groupAllowFrom = ["oc_team"]
        user.feishu.requireMention = true
        user.feishu.allowBots = false
        user.feishu.media.downloadEnabled = true
        user.feishu.media.mediaMaxBytes = 1024
        user.feishu.media.downloadRoot = "/tmp/metis-feishu-test-media"
        let groups = JsonObject()
        let groupRule = JsonObject()
        groupRule.put("requireMention", true.toJsonValue())
        groups.put("oc_team", groupRule)
        user.feishu.groups = Some(groups)
        let accounts = JsonObject()
        let tenantAccount = JsonObject()
        tenantAccount.put("appId", JsonString("tenant-app"))
        tenantAccount.put("appSecret", JsonString("tenant-secret"))
        tenantAccount.put("enabled", true.toJsonValue())
        accounts.put("tenant-a", tenantAccount)
        user.feishu.accounts = Some(accounts)

        let (feishu, _, _) = mergeGatewayUserSettings(user)
        @Expect(feishu.accountId, "tenant-a")
        @Expect(feishu.defaultAccount, "tenant-a")
        @Expect(feishu.appId, "legacy-app")
        @Expect(feishu.appSecret, "legacy-secret")
        @Expect(feishu.threadSession, true)
        @Expect(feishu.groupPolicy, "allowlist")
        @Expect(feishu.groupAllowFrom[0], "oc_team")
        @Expect(feishu.requireMention, true)
        @Expect(feishu.allowBots, false)
        @Expect(feishu.groups.isSome(), true)
        @Expect(feishu.accounts.isSome(), true)
        @Expect(feishu.media.downloadEnabled, true)
        @Expect(feishu.media.mediaMaxBytes, 1024)
        @Expect(feishu.media.downloadRoot, "/tmp/metis-feishu-test-media")
    }

    @TestCase
    public func qqPerAccountConfigMapsIntoRuntimeConfigWithoutDroppingTopLevelCompatibility(): Unit {
        var user = GatewayUserSettings()
        user.qq.enabled = true
        user.qq.defaultAccount = "work"
        user.qq.appId = "legacy-qq-app"
        user.qq.appSecret = "legacy-qq-secret"
        let accounts = JsonObject()
        let work = JsonObject()
        work.put("appId", JsonString("work-qq-app"))
        work.put("appSecret", JsonString("work-qq-secret"))
        accounts.put("work", work)
        user.qq.accounts = Some(accounts)

        let (_, qq, _) = mergeGatewayUserSettings(user)

        @Expect(qq.accountId, "work")
        @Expect(qq.defaultAccount, "work")
        @Expect(qq.appId, "legacy-qq-app")
        @Expect(qq.appSecret, "legacy-qq-secret")
        @Expect(qq.accounts.isSome(), true)
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
