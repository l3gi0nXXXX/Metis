package metis.gateway.session

import metis.gateway.model.{ChannelType, ChatType, InboundMessage}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

@Test
public class GatewaySessionCoordinatorTest {
    @TestCase
    public func dashboardRequestUsesAgentScopedSessionKey(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.DashboardRpc,
                sessionHint: "main",
                agentId: "general"
            )
        )
        @Expect(context.channelName, "dashboard")
        @Expect(context.sessionKey, "agent:general:main")
        @Expect(context.agentId, "general")
    }

    @TestCase
    public func cliRequestPreservesCliChannelIdentity(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.Cli,
                channelName: "cli",
                sessionHint: "main",
                agentId: "general"
            )
        )
        @Expect(context.channelName, "cli")
        @Expect(context.sourceLabel, "cli")
        @Expect(context.sessionKey, "agent:general:main")
    }

    @TestCase
    public func inboundDirectMessageBuildsChannelSessionAndDeliveryTarget(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.Channel("feishu"),
                channelName: "feishu",
                accountId: "feishu:default",
                peerId: "ou_123",
                senderId: "ou_123",
                chatType: Some(ChatType.Direct),
                deliver: true
            )
        )
        @Expect(context.channelName, "feishu")
        @Expect(context.sessionKey, "feishu:direct:ou_123")
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "feishu")
                @Expect(target.peerId, "ou_123")
                @Expect(target.accountId, "feishu:default")
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func explicitReplyTargetWinsOverDerivedSessionTarget(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.ControlUi,
                channelName: "dashboard",
                sessionHint: "feishu:direct:ou_123",
                agentId: "general",
                replyChannel: "qq",
                replyTo: "10001",
                replyAccountId: "bot-a",
                replyToMessageId: "msg-1",
                replyInThread: true,
                deliver: true
            )
        )
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "qq")
                @Expect(target.peerId, "10001")
                @Expect(target.accountId, "bot-a")
                @Expect(target.replyToMessageId, "msg-1")
                @Expect(target.replyInThread, true)
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func groupSessionKeyUsesSharedBuilder(): Unit {
        let sessionKey = gatewayBuildChannelSessionKey(
            "qq",
            ChatType.Group,
            "group-1",
            "user-9",
            conversationId: "group-1",
            dmScope: "per-channel-peer"
        )
        @Expect(sessionKey, "qq:group:group-1:u:user-9")
    }

    @TestCase
    public func telegramTopicSessionKeyUsesTopicScopedConversationId(): Unit {
        let sessionKey = gatewayBuildChannelSessionKey(
            "telegram",
            ChatType.Group,
            "group:-1001234567890:topic:42",
            "8734062810",
            conversationId: "group:-1001234567890:topic:42",
            dmScope: "per-chat"
        )
        @Expect(sessionKey, "telegram:group:group:-1001234567890:topic:42")
    }

    @TestCase
    public func rpcParamsBuildUnifiedSessionRequest(): Unit {
        let params = JsonObject()
        params.put("source", JsonString("control-ui"))
        params.put("channel", JsonString("cli"))
        params.put("session", JsonString("main"))
        params.put("agentId", JsonString("general"))
        params.put("text", JsonString("hello"))
        params.put("replyChannel", JsonString("qq"))
        params.put("replyTo", JsonString("10001"))
        params.put("replyAccount", JsonString("bot-a"))
        params.put("replyToMessageId", JsonString("msg-2"))
        params.put("replyInThread", JsonBool(true))
        params.put("deliver", JsonBool(true))
        let request = gatewaySessionRequestFromRpcParams(params)
        let context = gatewayResolveSessionContext(request)
        @Expect(context.sourceLabel, "control-ui")
        @Expect(context.channelName, "cli")
        @Expect(context.sessionKey, "agent:general:main")
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "qq")
                @Expect(target.peerId, "10001")
                @Expect(target.accountId, "bot-a")
                @Expect(target.replyToMessageId, "msg-2")
                @Expect(target.replyInThread, true)
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func rpcParamsCarryDeclaredUserAndOperatorScopes(): Unit {
        let params = JsonObject()
        params.put("source", JsonString("gateway-rpc"))
        params.put("session", JsonString("agent:general:main"))
        params.put("text", JsonString("restart gateway"))
        params.put("declaredUser", JsonString("operator:alice"))
        let scopes = JsonArray([])
        scopes.add(JsonString("operator.admin"))
        scopes.add(JsonString("approvals"))
        params.put("operatorScopes", scopes)
        let request = gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.GatewayRpc)
        @Expect(request.declaredUser, "operator:alice")
        @Expect(request.operatorScopes.contains("operator.admin"), true)
        @Expect(request.operatorScopes.contains("approvals"), true)
    }

    @TestCase
    public func chatSendRpcParamsBuilderNormalizesCommonFields(): Unit {
        let params = gatewayBuildChatSendRpcParams(
            GatewayIngressSource.ControlUi,
            session: " main ",
            text: "hello",
            deliver: true,
            thinking: " high ",
            replyChannel: "qq",
            replyTo: "10001",
            replyAccount: "bot-a",
            idempotencyKey: "run-1"
        )
        let request = gatewaySessionRequestFromRpcParams(params)
        let context = gatewayResolveSessionContext(request)
        @Expect(gatewayIngressSourceLabel(request.source), "control-ui")
        @Expect(request.sessionHint, "main")
        @Expect(request.text, "hello")
        @Expect(request.deliver, true)
        @Expect(context.sessionKey, "agent:main:main")
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "qq")
                @Expect(target.peerId, "10001")
                @Expect(target.accountId, "bot-a")
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func inferredTargetPreservesInboundAccountId(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.Channel("qq"),
                channelName: "qq",
                accountId: "qq:bot-b",
                sessionHint: "qq:direct:user:42",
                deliver: true
            )
        )
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "qq")
                @Expect(target.peerId, "user:42")
                @Expect(target.accountId, "qq:bot-b")
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func telegramTopicSessionHintInfersDeliveryTargetAndThread(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.ControlUi,
                channelName: "control-ui",
                accountId: "telegram:default",
                sessionHint: "telegram:group:group:-1001234567890:topic:42",
                deliver: true
            )
        )
        @Expect(context.sessionKey, "telegram:group:group:-1001234567890:topic:42")
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "telegram")
                @Expect(target.peerId, "group:-1001234567890:topic:42")
                @Expect(target.accountId, "telegram:default")
                @Expect(target.conversationId, "group:-1001234567890:topic:42")
                @Expect(target.threadId, "42")
                @Expect(target.replyInThread, true)
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func telegramDirectSessionHintInfersDeliveryTarget(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.ControlUi,
                accountId: "telegram:default",
                sessionHint: "telegram:direct:user:745123456",
                deliver: true
            )
        )
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "telegram")
                @Expect(target.peerId, "user:745123456")
                @Expect(target.accountId, "telegram:default")
                @Expect(target.replyInThread, false)
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func inboundChannelRequestPrefersRouterApprovedSessionHint(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.Channel("feishu"),
                channelName: "feishu",
                accountId: "feishu:default",
                sessionHint: "gateway:dm:main",
                peerId: "ou_123",
                senderId: "ou_456",
                chatType: Some(ChatType.Direct),
                dmScope: "per-peer",
                deliver: true
            )
        )
        @Expect(context.sessionKey, "gateway:dm:main")
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "feishu")
                @Expect(target.peerId, "ou_123")
                @Expect(target.accountId, "feishu:default")
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func sessionRpcParamsBuilderKeepsUnifiedIngressFields(): Unit {
        let params = gatewayBuildSessionRpcParams(
            GatewayIngressSource.Cli,
            session: "main",
            text: "hello",
            channel: "CLI",
            agentId: "general",
            accountId: "cli:default",
            to: "peer-1",
            lane: "primary",
            deliver: true,
            thinking: "high",
            verbose: "full",
            timeoutSeconds: 12,
            bestEffortDeliver: true,
            replyChannel: "qq",
            replyTo: "10001",
            replyAccount: "qq:bot-a",
            declaredUser: "operator:cli",
            operatorScopes: ["operator.admin"],
            extraSystemPrompt: "stay concise",
            idempotencyKey: "run-1"
        )
        let request = gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.Unknown("fallback"))
        @Expect(gatewayIngressSourceLabel(request.source), "cli")
        @Expect(request.channelName, "cli")
        @Expect(request.agentId, "general")
        @Expect(request.accountId, "cli:default")
        @Expect(request.to, "peer-1")
        @Expect(request.lane, "primary")
        @Expect(request.replyChannel, "qq")
        @Expect(request.replyTo, "10001")
        @Expect(request.replyAccountId, "qq:bot-a")
        @Expect(request.declaredUser, "operator:cli")
        @Expect(request.operatorScopes.contains("operator.admin"), true)
        @Expect(request.replyToMessageId, "")
        @Expect(request.replyInThread, false)
        @Expect(request.deliver, true)
    }

    @TestCase
    public func chatHistoryRpcParamsBuilderNormalizesSessionField(): Unit {
        let params = gatewayBuildChatHistoryRpcParams(session: " main ")
        @Expect(params.get("session").getOrThrow().asString().getValue(), "main")
    }

    @TestCase
    public func sessionsDeleteRpcParamsBuilderNormalizesKeysField(): Unit {
        let params = gatewayBuildSessionsDeleteRpcParams(keys: " main \n other ")
        @Expect(params.get("keys").getOrThrow().asString().getValue(), "main \n other")
    }

    @TestCase
    public func explicitAgentSessionHintDerivesAgentIdentity(): Unit {
        let context = gatewayResolveSessionContext(
            GatewaySessionRequest(
                GatewayIngressSource.GatewayRpc,
                sessionHint: "agent:general:main"
            )
        )
        @Expect(context.agentId, "general")
        @Expect(context.sessionKey, "agent:general:main")
    }

    @TestCase
    public func inboundRequestPreservesReplyMessageMetadata(): Unit {
        let media = JsonObject()
        let records = JsonArray([])
        let record = JsonObject()
        record.put("mediaKind", JsonString("photo"))
        record.put("localPath", JsonString("/tmp/metis-photo.jpg"))
        records.add(record)
        media.put("records", records)
        let request = gatewaySessionRequestFromInbound(
            InboundMessage(
                ChannelType.Feishu,
                "msg-current",
                "ou_123",
                "ou_456",
                ChatType.Direct,
                "hello",
                true,
                DateTime.now(),
                conversationId: Some("chat-ou_123"),
                threadId: Some("thread-1"),
                replyTargetMessageId: Some("msg-root"),
                replyInThread: true,
                accountId: "feishu:bot-a",
                mediaContext: media
            )
        )
        let context = gatewayResolveSessionContext(request)
        @Expect(request.conversationId, "chat-ou_123")
        @Expect(request.threadId, "thread-1")
        @Expect(request.sourceMessageId, "msg-current")
        @Expect(request.replyToMessageId, "msg-root")
        @Expect(request.replyInThread, true)
        @Expect(request.mediaContext.get("records").getOrThrow().asArray().size(), 1)
        match (context.deliveryTarget) {
            case Some(target) =>
                @Expect(target.conversationId, "chat-ou_123")
                @Expect(target.threadId, "thread-1")
                @Expect(target.sourceMessageId, "msg-current")
                @Expect(target.replyToMessageId, "msg-root")
                @Expect(target.replyInThread, true)
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func inboundRequestUsesTelegramRouteAgentFromMediaContext(): Unit {
        let media = JsonObject()
        let context = JsonObject()
        let route = JsonObject()
        route.put("agentId", JsonString("topic-agent"))
        context.put("telegramRoute", route)
        media.put("context", context)
        let request = gatewaySessionRequestFromInbound(
            InboundMessage(
                ChannelType.Telegram,
                "msg-current",
                "group:-1001234567890:topic:42",
                "8734062810",
                ChatType.Group,
                "hello",
                true,
                DateTime.now(),
                conversationId: Some("group:-1001234567890:topic:42"),
                threadId: Some("42"),
                mediaContext: media
            )
        )
        let resolved = gatewayResolveSessionContext(request)
        @Expect(request.agentId, "topic-agent")
        @Expect(resolved.agentId, "topic-agent")
    }

}
