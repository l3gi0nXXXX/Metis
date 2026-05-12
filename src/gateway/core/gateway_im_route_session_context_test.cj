package metis.gateway.core

import metis.gateway.model.{ChannelType, ChatType, InboundMessage}
import metis.gateway.session.gatewaySessionRequestFromInbound
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func imRouteSessionAgent(id: String, isDefault!: Bool = false): JsonObject {
    let row = JsonObject()
    row.put("id", JsonString(id))
    if (isDefault) {
        row.put("default", JsonBool(true))
    }
    row
}

private func imRouteSessionChannel(defaultAccountId: String): JsonObject {
    let channel = JsonObject()
    channel.put("defaultAccountId", JsonString(defaultAccountId))
    let accounts = JsonArray([])
    accounts.add(JsonString(defaultAccountId))
    channel.put("accountIds", accounts)
    channel
}

private func imRouteSessionBinding(
    agentId: String,
    channel: String,
    peerKind: String,
    peerId: String,
    accountId!: String = "*",
    enabled!: Bool = true
): JsonObject {
    let binding = JsonObject()
    binding.put("type", JsonString("route"))
    binding.put("agentId", JsonString(agentId))
    binding.put("enabled", JsonBool(enabled))
    let matchObj = JsonObject()
    matchObj.put("channel", JsonString(channel))
    matchObj.put("accountId", JsonString(accountId))
    let peer = JsonObject()
    peer.put("kind", JsonString(peerKind))
    peer.put("id", JsonString(peerId))
    matchObj.put("peer", peer)
    binding.put("match", matchObj)
    binding
}

private func imRouteSessionRoot(bindings: Array<JsonObject>): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let list = JsonArray([])
    list.add(imRouteSessionAgent("main", isDefault: true))
    list.add(imRouteSessionAgent("reviewer"))
    list.add(imRouteSessionAgent("writer"))
    agents.put("list", list)
    root.put("agents", agents)
    let channels = JsonObject()
    channels.put("telegram", imRouteSessionChannel("default"))
    channels.put("feishu", imRouteSessionChannel("default"))
    root.put("channels", channels)
    let rows = JsonArray([])
    for (binding in bindings) {
        rows.add(binding)
    }
    root.put("bindings", rows)
    root
}

private func imRouteMediaContext(
    accountId: String,
    defaultAccountId: String,
    peerKind: String,
    peerId: String,
    parentPeerKind!: String = "",
    parentPeerId!: String = ""
): JsonObject {
    let media = JsonObject()
    let context = JsonObject()
    let route = JsonObject()
    route.put("accountId", JsonString(accountId))
    route.put("defaultAccountId", JsonString(defaultAccountId))
    route.put("peerKind", JsonString(peerKind))
    route.put("peerId", JsonString(peerId))
    if (!parentPeerKind.isEmpty()) {
        route.put("parentPeerKind", JsonString(parentPeerKind))
    }
    if (!parentPeerId.isEmpty()) {
        route.put("parentPeerId", JsonString(parentPeerId))
    }
    context.put("imRoute", route)
    media.put("context", context)
    media
}

@Test
public class GatewayImRouteSessionContextTest {
    @TestCase
    public func inboundRequestResolvesTelegramTopicRouteContextThroughBindingResolver(): Unit {
        let root = imRouteSessionRoot([
            imRouteSessionBinding("reviewer", "telegram", "topic", "42")
        ])
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
                accountId: "",
                mediaContext: imRouteMediaContext(
                    "default",
                    "default",
                    "topic",
                    "42",
                    parentPeerKind: "group",
                    parentPeerId: "-1001234567890"
                )
            ),
            sessionHint: "telegram:group:group:-1001234567890:topic:42",
            accountId: "telegram:default",
            routeRoot: root
        )
        let resolved = gatewayResolveSessionContextWithAgentRoute(request)
        @Expect(resolved.agentId, "reviewer")
        @Expect(resolved.sessionKey, "agent:reviewer:telegram:topic:42")
        @Expect(resolved.matchedBy, "binding.peer.exact")
        @Expect(resolved.preferredAccountId, "default")
        @Expect(resolved.lastRoutePolicy, "session")
        match (resolved.deliveryTarget) {
            case Some(target) =>
                @Expect(target.peerId, "group:-1001234567890:topic:42")
                @Expect(target.threadId, "42")
                @Expect(target.accountId, "default")
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func inboundRequestResolvesFeishuThreadRouteWithoutLeakingChannelManagerAccountPrefix(): Unit {
        let root = imRouteSessionRoot([
            imRouteSessionBinding("writer", "feishu", "thread", "thread_x")
        ])
        let request = gatewaySessionRequestFromInbound(
            InboundMessage(
                ChannelType.Feishu,
                "msg-current",
                "oc_a",
                "ou_123",
                ChatType.Group,
                "hello",
                true,
                DateTime.now(),
                conversationId: Some("oc_a:topic:thread_x"),
                threadId: Some("thread_x"),
                mediaContext: imRouteMediaContext(
                    "default",
                    "default",
                    "thread",
                    "thread_x",
                    parentPeerKind: "group",
                    parentPeerId: "oc_a"
                )
            ),
            sessionHint: "feishu:group:oc_a:topic:thread_x",
            accountId: "feishu:default",
            routeRoot: root
        )
        let resolved = gatewayResolveSessionContextWithAgentRoute(request)
        @Expect(resolved.agentId, "writer")
        @Expect(resolved.sessionKey, "agent:writer:feishu:thread:thread_x")
        @Expect(resolved.matchedBy, "binding.peer.exact")
        @Expect(resolved.accountId, "default")
        match (resolved.deliveryTarget) {
            case Some(target) =>
                @Expect(target.channelName, "feishu")
                @Expect(target.peerId, "oc_a")
                @Expect(target.accountId, "default")
            case None =>
                @Expect("missing", "delivery-target")
        }
    }

    @TestCase
    public func inboundRequestIgnoresDisabledRouteBindingAndFallsBackToDefaultAgent(): Unit {
        let root = imRouteSessionRoot([
            imRouteSessionBinding("reviewer", "telegram", "group", "-1001234567890", enabled: false)
        ])
        let request = gatewaySessionRequestFromInbound(
            InboundMessage(
                ChannelType.Telegram,
                "msg-current",
                "group:-1001234567890",
                "8734062810",
                ChatType.Group,
                "hello",
                true,
                DateTime.now(),
                conversationId: Some("group:-1001234567890"),
                mediaContext: imRouteMediaContext("default", "default", "group", "-1001234567890")
            ),
            sessionHint: "telegram:group:group:-1001234567890",
            accountId: "telegram:default",
            routeRoot: root
        )
        let resolved = gatewayResolveSessionContextWithAgentRoute(request)
        @Expect(resolved.agentId, "main")
        @Expect(resolved.sessionKey, "agent:main:telegram:group:-1001234567890")
        @Expect(resolved.matchedBy, "default")
    }
}
