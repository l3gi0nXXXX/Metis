package metis.gateway.core

import magic.jsonable.*

import metis.gateway.model.{ChannelType, InboundMessage, OutboundMessage, SendResult}
import metis.gateway.session.{GatewayDeliveryTarget, GatewayIngressSource, GatewaySessionContext}

import std.collection.ArrayList
import std.fs.Path
import std.unittest.testmacro.*
import stdx.encoding.json.JsonObject

private func stringField(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private class GatewayTestChannelAdapter <: ChannelAdapter {
    private let adapterName: String
    private let sent = ArrayList<OutboundMessage>()

    public prop name: String {
        get() { this.adapterName }
    }

    public init(name: String) {
        this.adapterName = name
    }

    public func start(): Unit {}

    public func stop(): Unit {}

    public func pullInbound(): Array<InboundMessage> {
        []
    }

    public func send(message: OutboundMessage): SendResult {
        this.sent.add(message)
        SendResult.Success
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        this.sent.add(message)
        ""
    }

    public func sentCount(): Int64 {
        Int64(this.sent.size)
    }

    public func sentAccountId(index: Int64): String {
        match (this.sent.get(index)) {
            case Some(v) => v.accountId
            case None => ""
        }
    }
}

@Test
public class GatewayChatTurnSharedTest {
    @TestCase
    public func chatEventTargetIncludesControlUiClients(): Unit {
        @Expect(gatewayChatEventShouldPublishToClient("metis-control-ui", "webchat"), true)
        @Expect(gatewayChatEventShouldPublishToClient("metis-control-ui", "webchat"), true)
        @Expect(gatewayChatEventShouldPublishToClient("browser-control-ui", "control-ui-browser"), true)
        @Expect(gatewayChatEventShouldPublishToClient("cli", "local-cli"), false)
    }

    @TestCase
    public func buildChatEventPayloadCarriesFinalAssistantMessage(): Unit {
        let payload = gatewayBuildChatEventPayload(
            "agent:general:main",
            "run-1",
            "final",
            gatewayBuildChatEventMessage("assistant", "hello", 123)
        )
        @Expect(stringField(payload, "sessionKey"), "agent:general:main")
        @Expect(stringField(payload, "runId"), "run-1")
        @Expect(stringField(payload, "state"), "final")
        let message = payload.get("message").getOrThrow().asObject()
        @Expect(stringField(message, "role"), "assistant")
    }

    @TestCase
    public func buildChatEventPayloadIncludesConversationProjectionWhenProvided(): Unit {
        let origin = JsonObject()
        origin.put("provider", "qq".toJsonValue())
        let payload = gatewayBuildChatEventPayload(
            "qq:group:chat-42",
            "run-2",
            "final",
            gatewayBuildChatEventMessage("assistant", "hello", 456),
            conversation: Some(GatewaySessionConversationView(
                "qq:group:chat-42",
                "chat-42",
                "qq",
                "group",
                "chat-42",
                "general",
                "qq_group_chat_42",
                "qq_group_chat_42.jsonl",
                Path("/tmp"),
                0,
                origin
            )),
            deliveryTarget: Some(GatewayDeliveryTarget("qq", "chat-42", accountId: "qq:bot-a", replyToMessageId: "msg-42", replyInThread: true))
        )
        @Expect(stringField(payload, "agentId"), "general")
        @Expect(stringField(payload, "displayName"), "chat-42")
        @Expect(stringField(payload, "channel"), "qq")
        @Expect(stringField(payload, "chatType"), "group")
        @Expect(stringField(payload, "peer"), "chat-42")
        @Expect(stringField(payload, "sessionId"), "qq_group_chat_42")
        @Expect(payload.get("origin").isSome(), true)
        let delivery = payload.get("delivery").getOrThrow().asObject()
        @Expect(stringField(delivery, "accountId"), "qq:bot-a")
        @Expect(stringField(delivery, "replyToMessageId"), "msg-42")
        let binding = payload.get("binding").getOrThrow().asObject()
        @Expect(stringField(binding, "replyTargetMessageId"), "msg-42")
    }

    @TestCase
    public func buildSessionEventPayloadIncludesConversationProjectionWhenProvided(): Unit {
        let origin = JsonObject()
        origin.put("provider", "qq".toJsonValue())
        let payload = gatewayBuildSessionEventPayload(
            "qq:group:chat-42",
            "updated",
            conversation: Some(GatewaySessionConversationView(
                "qq:group:chat-42",
                "chat-42",
                "qq",
                "group",
                "chat-42",
                "general",
                "qq_group_chat_42",
                "qq_group_chat_42.jsonl",
                Path("/tmp"),
                0,
                origin
            )),
            deliveryTarget: Some(GatewayDeliveryTarget("qq", "chat-42", accountId: "qq:bot-a", replyToMessageId: "msg-42", replyInThread: true)),
            runId: "run-2",
            detail: "chat-turn-completed"
        )
        @Expect(stringField(payload, "sessionKey"), "qq:group:chat-42")
        @Expect(stringField(payload, "state"), "updated")
        @Expect(stringField(payload, "runId"), "run-2")
        @Expect(stringField(payload, "detail"), "chat-turn-completed")
        @Expect(stringField(payload, "agentId"), "general")
        @Expect(stringField(payload, "displayName"), "chat-42")
        @Expect(stringField(payload, "channel"), "qq")
        @Expect(stringField(payload, "chatType"), "group")
        @Expect(stringField(payload, "peer"), "chat-42")
        @Expect(stringField(payload, "sessionId"), "qq_group_chat_42")
        @Expect(payload.get("origin").isSome(), true)
        let delivery = payload.get("delivery").getOrThrow().asObject()
        @Expect(stringField(delivery, "replyToMessageId"), "msg-42")
        let binding = payload.get("binding").getOrThrow().asObject()
        @Expect(stringField(binding, "replyTargetMessageId"), "msg-42")
    }

    @TestCase
    public func buildChatTurnResultUsesDeliveryTargetForReplyFields(): Unit {
        let context = GatewaySessionContext(
            GatewayIngressSource.ControlUi,
            "control-ui",
            "cli",
            "agent:general:main",
            "general",
            deliveryTarget: Some(
                GatewayDeliveryTarget(
                    "qq",
                    "10001",
                    accountId: "bot-a",
                    conversationId: "user:10001",
                    threadId: "thread-9",
                    sourceMessageId: "source-9",
                    replyToMessageId: "msg-9",
                    replyInThread: true
                )
            )
        )
        let result = gatewayBuildChatTurnResult(
            context,
            "hello",
            GatewaySessionExecutionResult("world", delivered: true, deliveryStatus: "delivered"),
            "",
            "high",
            "full",
            20,
            "",
            "run-1",
            "",
            true,
            false,
            "dashboard",
            "fallback",
            "",
            "bot-a",
            conversation: Some(GatewaySessionConversationView(
                "agent:general:main",
                "General Main",
                "cli",
                "direct",
                "main",
                "general",
                "general_main",
                "general_main.jsonl",
                Path("/tmp"),
                0,
                JsonObject()
            ))
        )
        @Expect(stringField(result, "replyChannel"), "qq")
        @Expect(stringField(result, "replyTo"), "10001")
        @Expect(stringField(result, "replyToMessageId"), "msg-9")
        @Expect(result.get("replyInThread").getOrThrow().asBool().getValue(), true)
        @Expect(stringField(result, "agentId"), "general")
        @Expect(stringField(result, "channel"), "cli")
        @Expect(stringField(result, "displayName"), "General Main")
        @Expect(stringField(result, "chatType"), "direct")
        @Expect(stringField(result, "peer"), "main")
        @Expect(stringField(result, "sessionId"), "general_main")
        @Expect(result.get("origin").isSome(), true)
        let delivery = result.get("delivery").getOrThrow().asObject()
        @Expect(stringField(delivery, "replyChannel"), "qq")
        @Expect(stringField(delivery, "conversationId"), "user:10001")
        @Expect(stringField(delivery, "threadId"), "thread-9")
        @Expect(stringField(delivery, "replyToMessageId"), "msg-9")
        let binding = result.get("binding").getOrThrow().asObject()
        @Expect(stringField(binding, "conversationId"), "user:10001")
        @Expect(stringField(binding, "sourceMessageId"), "source-9")
    }

    @TestCase
    public func buildChatTurnResultFallsBackToProvidedReplyFields(): Unit {
        let context = GatewaySessionContext(
            GatewayIngressSource.Cli,
            "cli",
            "cli",
            "agent:general:main",
            "general"
        )
        let result = gatewayBuildChatTurnResult(
            context,
            "hello",
            GatewaySessionExecutionResult("world"),
            "",
            "",
            "",
            0,
            "",
            "",
            "",
            false,
            false,
            "cli",
            "main",
            "acc-1",
            ""
        )
        @Expect(stringField(result, "replyChannel"), "cli")
        @Expect(stringField(result, "replyTo"), "main")
        @Expect(stringField(result, "replyAccount"), "acc-1")
        @Expect(stringField(result, "replyAccountId"), "acc-1")
        @Expect(stringField(result, "replyToMessageId"), "")
        @Expect(result.get("replyInThread").getOrThrow().asBool().getValue(), false)
    }

    @TestCase
    public func channelManagerRespectsOutboundAccountId(): Unit {
        let manager = GatewayChannelManager()
        let adapterA = GatewayTestChannelAdapter("qq")
        let adapterB = GatewayTestChannelAdapter("qq")
        manager.registerAdapter(adapterA, channelId: "qq", accountId: "qq:a")
        manager.registerAdapter(adapterB, channelId: "qq", accountId: "qq:b")
        let send = manager.sendToAdapterName(
            "qq",
            OutboundMessage(
                ChannelType.QQ,
                "user:42",
                "hello",
                accountId: "qq:b"
            )
        )
        @Expect(send.delivered, true)
        @Expect(adapterA.sentCount(), 0)
        @Expect(adapterB.sentCount(), 1)
    }

    @TestCase
    public func channelManagerMatchesRegisteredTelegramDefaultAlias(): Unit {
        let manager = GatewayChannelManager()
        let adapter = GatewayTestChannelAdapter("telegram")
        manager.registerAdapter(adapter, channelId: "telegram", accountId: "telegram:default")
        let send = manager.sendToAdapterName(
            "telegram",
            OutboundMessage(ChannelType.Telegram, "8734062810", "hello", accountId: "default")
        )
        @Expect(send.delivered, true)
        @Expect(send.canonicalAccountId, "default")
        @Expect(adapter.sentCount(), 1)
        @Expect(adapter.sentAccountId(0), "default")
    }

    @TestCase
    public func channelManagerMatchesOutboundTelegramDefaultAlias(): Unit {
        let manager = GatewayChannelManager()
        let adapter = GatewayTestChannelAdapter("telegram")
        manager.registerAdapter(adapter, channelId: "telegram", accountId: "default")
        let send = manager.sendToAdapterName(
            "telegram",
            OutboundMessage(ChannelType.Telegram, "8734062810", "hello", accountId: "telegram:default")
        )
        @Expect(send.delivered, true)
        @Expect(send.canonicalAccountId, "default")
        @Expect(adapter.sentCount(), 1)
    }

    @TestCase
    public func channelManagerMatchesNamedLegacyAliasOnlyOnSameChannel(): Unit {
        let manager = GatewayChannelManager()
        let adapter = GatewayTestChannelAdapter("telegram")
        manager.registerAdapter(adapter, channelId: "telegram", accountId: "telegram:work")
        let send = manager.sendToAdapterName(
            "telegram",
            OutboundMessage(ChannelType.Telegram, "8734062810", "hello", accountId: "work")
        )
        @Expect(send.delivered, true)
        @Expect(send.canonicalAccountId, "work")
        @Expect(adapter.sentCount(), 1)
    }

    @TestCase
    public func channelManagerDoesNotCrossMatchOtherChannelDefaultAlias(): Unit {
        let manager = GatewayChannelManager()
        let adapter = GatewayTestChannelAdapter("telegram")
        manager.registerAdapter(adapter, channelId: "telegram", accountId: "default")
        let send = manager.sendToAdapterName(
            "telegram",
            OutboundMessage(ChannelType.Telegram, "8734062810", "hello", accountId: "feishu:default")
        )
        @Expect(send.delivered, false)
        @Expect(send.reasonKind, "account_mismatch")
        @Expect(send.canonicalAccountId, "feishu:default")
        @Expect(adapter.sentCount(), 0)
    }

    @TestCase
    public func channelManagerDoesNotMatchNamedAccountToDefault(): Unit {
        let manager = GatewayChannelManager()
        let adapter = GatewayTestChannelAdapter("telegram")
        manager.registerAdapter(adapter, channelId: "telegram", accountId: "work")
        let send = manager.sendToAdapterName(
            "telegram",
            OutboundMessage(ChannelType.Telegram, "8734062810", "hello", accountId: "default")
        )
        @Expect(send.delivered, false)
        @Expect(send.reasonKind, "account_mismatch")
        @Expect(send.canonicalAccountId, "default")
        @Expect(adapter.sentCount(), 0)
    }
}
