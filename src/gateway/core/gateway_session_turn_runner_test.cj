package metis.gateway.core

import metis.core.gatewayCurrentToolRuntimeContext
import metis.core.config.GatewayUserSettings
import metis.gateway.session.{GatewayIngressSource, GatewaySessionRequest}

import std.fs.Path
import std.unittest.testmacro.*

@Test
public class GatewaySessionTurnRunnerTest {
    @TestCase
    public func executeSessionRequestTurnResolvesContextBeforeReply(): Unit {
        let store = GatewaySessionStore(Path("."), enabled: false, agentId: "general")
        let bridge = AgentBridge(sessionStore: store)
        let turn = gatewayExecuteSessionRequestTurn(
            bridge,
            GatewaySessionRequest(
                GatewayIngressSource.Cli,
                channelName: "cli",
                sessionHint: "main",
                agentId: "general"
            ),
            "/unknown"
        )
        @Expect(turn.context.channelName, "cli")
        @Expect(turn.context.sessionKey, "agent:general:main")
        @Expect(turn.context.agentId, "general")
        @Expect(turn.execution.delivered, false)
        @Expect(turn.execution.answer.contains("这不是一个有效的命令"), true)
    }

    @TestCase
    public func executeSessionRequestTurnForUserBuildsBridgeFromResolvedRequest(): Unit {
        let turn = gatewayExecuteSessionRequestTurnForUser(
            GatewayUserSettings(),
            GatewaySessionRequest(
                GatewayIngressSource.Cli,
                channelName: "cli",
                sessionHint: "agent:general:main",
                agentId: ""
            ),
            "/unknown"
        )
        @Expect(turn.context.channelName, "cli")
        @Expect(turn.context.sessionKey, "agent:general:main")
        @Expect(turn.context.agentId, "general")
        @Expect(turn.execution.answer.contains("这不是一个有效的命令"), true)
    }

    @TestCase
    public func executeSessionRequestTurnClearsToolRuntimeContextAfterReply(): Unit {
        let store = GatewaySessionStore(Path("."), enabled: false, agentId: "general")
        let bridge = AgentBridge(sessionStore: store)
        let turn = gatewayExecuteSessionRequestTurn(
            bridge,
            GatewaySessionRequest(
                GatewayIngressSource.ControlUi,
                channelName: "control-ui",
                sessionHint: "main",
                agentId: "general",
                senderId: "operator-1",
                text: "/unknown"
            ),
            "/unknown"
        )
        @Expect(turn.context.channelName, "control-ui")
        @Expect(gatewayCurrentToolRuntimeContext().isNone(), true)
    }

    @TestCase
    public func streamingDefaultsToOnButCanBeDisabledPerImChannel(): Unit {
        var defaults = GatewayUserSettings()
        defaults.telegram.enabled = true
        defaults.feishu.enabled = true
        defaults.qq.enabled = true
        @Expect(gatewayStreamingEnabledForUserChannel(defaults, "telegram"), true)
        @Expect(gatewayStreamingEnabledForUserChannel(defaults, "feishu"), true)
        @Expect(gatewayStreamingEnabledForUserChannel(defaults, "qq"), true)

        var disabled = GatewayUserSettings()
        disabled.telegram.enabled = true
        disabled.telegram.streaming = "off"
        @Expect(gatewayStreamingEnabledForUserChannel(disabled, "telegram"), false)

        var feishuDisabled = GatewayUserSettings()
        feishuDisabled.feishu.enabled = true
        feishuDisabled.feishu.streaming = "off"
        @Expect(gatewayStreamingEnabledForUserChannel(feishuDisabled, "feishu"), false)

        var qqDisabled = GatewayUserSettings()
        qqDisabled.qq.enabled = true
        qqDisabled.qq.streaming = "off"
        @Expect(gatewayStreamingEnabledForUserChannel(qqDisabled, "qq"), false)

        var blocked = GatewayUserSettings()
        blocked.telegram.enabled = true
        blocked.telegram.blockStreaming = true
        @Expect(gatewayStreamingEnabledForUserChannel(blocked, "telegram"), false)

        var feishuBlocked = GatewayUserSettings()
        feishuBlocked.feishu.enabled = true
        feishuBlocked.feishu.blockStreaming = true
        @Expect(gatewayStreamingEnabledForUserChannel(feishuBlocked, "feishu"), false)

        var qqBlocked = GatewayUserSettings()
        qqBlocked.qq.enabled = true
        qqBlocked.qq.blockStreaming = true
        @Expect(gatewayStreamingEnabledForUserChannel(qqBlocked, "qq"), false)
    }
}
