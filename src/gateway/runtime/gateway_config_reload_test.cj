package metis.gateway.runtime

import metis.core.config.GatewayUserSettings
import metis.gateway.config.GatewayPreparedAdapterRegistration

import std.collection.ArrayList
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private class FakeReloadRuntime <: GatewayReloadChannelRuntime {
    public let channels = ArrayList<String>()
    public let registrationCounts = ArrayList<Int64>()

    public init() {}

    public func reconcileChannel(channelId: String, registrations: Array<GatewayPreparedAdapterRegistration>): Unit {
        this.channels.add(channelId)
        this.registrationCounts.add(registrations.size)
    }
}

@Test
public class GatewayConfigReloadTest {
    @TestCase
    public func diffGatewayConfigPathsReportsNestedChanges(): Unit {
        let prevGateway = JsonObject()
        let prevTelegram = JsonObject()
        prevTelegram.put("botToken", JsonString("old-token"))
        prevGateway.put("telegram", prevTelegram)
        let prev = JsonObject()
        prev.put("gateway", prevGateway)

        let nextGateway = JsonObject()
        let nextTelegram = JsonObject()
        nextTelegram.put("botToken", JsonString("new-token"))
        nextGateway.put("telegram", nextTelegram)
        let next = JsonObject()
        next.put("gateway", nextGateway)

        let paths = diffGatewayConfigPaths(prev, next)
        @Expect(paths.size, 1)
        @Expect(paths[0], "gateway.telegram.botToken")
    }

    @TestCase
    public func reloadPlanMapsBuiltinGatewayChannelPrefixesToRestartChannels(): Unit {
        let plan = buildGatewayReloadPlan([
            "gateway.telegram.accounts.work.botToken",
            "gateway.feishu.appId",
            "gateway.qq.accounts.ops.appSecret"
        ])

        @Expect(plan.restartGateway, false)
        @Expect(plan.restartChannels.size, 3)
        @Expect(plan.restartChannels.contains("telegram"), true)
        @Expect(plan.restartChannels.contains("feishu"), true)
        @Expect(plan.restartChannels.contains("qq"), true)
    }

    @TestCase
    public func reloadPlanDefaultsUnknownPathsToGatewayRestart(): Unit {
        let plan = buildGatewayReloadPlan(["plugins.example.enabled"])

        @Expect(plan.restartGateway, true)
        @Expect(plan.restartReasons.size, 1)
        @Expect(plan.restartReasons[0], "plugins.example.enabled")
    }

    @TestCase
    public func hotReloadHandlerUsesPreparedRegistrationsAndRuntimeReconciler(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "123456:test-token"
        user.feishu.enabled = true
        user.feishu.appId = "feishu-app"
        user.feishu.appSecret = "feishu-secret"
        user.qq.enabled = true
        user.qq.appId = "qq-app"
        user.qq.appSecret = "qq-secret"

        let runtime = FakeReloadRuntime()
        let plan = buildGatewayReloadPlan(["gateway.telegram.botToken", "gateway.feishu.accounts.writer.appId"])
        applyGatewayHotReload(plan, user, runtime)

        @Expect(runtime.channels.size, 2)
        @Expect(runtime.channels.contains("telegram"), true)
        @Expect(runtime.channels.contains("feishu"), true)
        @Expect(runtime.registrationCounts[0] > 0, true)
        @Expect(runtime.registrationCounts[1] > 0, true)
    }
}
