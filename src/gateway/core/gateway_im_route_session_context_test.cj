package metis.gateway.core

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.model.{ChannelType, ChatType, InboundMessage}
import metis.gateway.session.gatewaySessionRequestFromInbound
import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
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

private func imRouteSessionBindingForAccount(agentId: String, accountId: String): JsonObject {
    imRouteSessionBinding(agentId, "telegram", "topic", "42", accountId: accountId)
}

private func withImRouteSessionTempHome<T>(label: String, block: (Path) -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = Path("/tmp/metis-im-route-session-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(home, recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", home.toString())
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try {
            return block(home)
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            CliConfig.invalidatePathCache()
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            try { remove(home, recursive: true) } catch (_: Exception) { () }
        }
    }
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

    @TestCase
    public func sameThreadOnDifferentAccountsKeepsDistinctAgentSessionAndScope(): Unit {
        withImRouteSessionTempHome("account-scope", { _home: Path =>
            let root = imRouteSessionRoot([
                imRouteSessionBindingForAccount("reviewer", "bot-a"),
                imRouteSessionBindingForAccount("writer", "bot-b")
            ])
            let channels = JsonObject()
            channels.put("telegram", imRouteSessionChannel("bot-a"))
            let telegram = channels.get("telegram").getOrThrow().asObject()
            telegram.put("accountIds", JsonArray([JsonString("bot-a"), JsonString("bot-b")]))
            root.put("channels", channels)

            let requestA = gatewaySessionRequestFromInbound(
                InboundMessage(
                    ChannelType.Telegram,
                    "msg-a",
                    "group:-1001234567890:topic:42",
                    "8734062810",
                    ChatType.Group,
                    "same input",
                    true,
                    DateTime.now(),
                    conversationId: Some("group:-1001234567890:topic:42"),
                    threadId: Some("42"),
                    accountId: "bot-a",
                    mediaContext: imRouteMediaContext(
                        "bot-a",
                        "bot-a",
                        "topic",
                        "42",
                        parentPeerKind: "group",
                        parentPeerId: "-1001234567890"
                    )
                ),
                routeRoot: root
            )
            let requestB = gatewaySessionRequestFromInbound(
                InboundMessage(
                    ChannelType.Telegram,
                    "msg-b",
                    "group:-1001234567890:topic:42",
                    "8734062810",
                    ChatType.Group,
                    "same input",
                    true,
                    DateTime.now(),
                    conversationId: Some("group:-1001234567890:topic:42"),
                    threadId: Some("42"),
                    accountId: "bot-b",
                    mediaContext: imRouteMediaContext(
                        "bot-b",
                        "bot-a",
                        "topic",
                        "42",
                        parentPeerKind: "group",
                        parentPeerId: "-1001234567890"
                    )
                ),
                routeRoot: root
            )

            let resolvedA = gatewayResolveSessionContextWithAgentRoute(requestA)
            let resolvedB = gatewayResolveSessionContextWithAgentRoute(requestB)

            @Expect(resolvedA.agentId, "reviewer")
            @Expect(resolvedB.agentId, "writer")
            @Expect(resolvedA.sessionKey != resolvedB.sessionKey, true)
            @Expect(resolvedA.turnContext.workspaceDir != resolvedB.turnContext.workspaceDir, true)
            @Expect(resolvedA.turnContext.modelsJsonPath != resolvedB.turnContext.modelsJsonPath, true)
            @Expect(resolvedA.turnContext.authProfilesPath != resolvedB.turnContext.authProfilesPath, true)
            @Expect(resolvedA.turnContext.accountId, "bot-a")
            @Expect(resolvedB.turnContext.accountId, "bot-b")
        })
    }
}
