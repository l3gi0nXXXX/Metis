package metis.gateway.core

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func routeTestAgent(id: String, isDefault!: Bool = false): JsonObject {
    let row = JsonObject()
    row.put("id", JsonString(id))
    if (isDefault) {
        row.put("default", JsonBool(true))
    }
    row
}

private func routeTestConfig(): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let list = JsonArray([])
    list.add(routeTestAgent("main", isDefault: true))
    list.add(routeTestAgent("ops"))
    list.add(routeTestAgent("reviewer"))
    list.add(routeTestAgent("assistant-a"))
    list.add(routeTestAgent("assistant-b"))
    list.add(routeTestAgent("pm"))
    list.add(routeTestAgent("writer"))
    list.add(routeTestAgent("roles-agent"))
    list.add(routeTestAgent("guild-agent"))
    list.add(routeTestAgent("team-agent"))
    agents.put("list", list)
    root.put("agents", agents)

    let channels = JsonObject()
    channels.put("telegram", routeTestChannel("bot-a", ["bot-a", "bot-b"]))
    channels.put("feishu", routeTestChannel("tenant-a", ["tenant-a", "tenant-b"]))
    root.put("channels", channels)
    root.put("session", JsonObject())
    root
}

private func routeTestChannel(defaultAccountId: String, accounts: Array<String>): JsonObject {
    let channel = JsonObject()
    channel.put("defaultAccountId", JsonString(defaultAccountId))
    let arr = JsonArray([])
    for (account in accounts) {
        arr.add(JsonString(account))
    }
    channel.put("accountIds", arr)
    channel
}

private func routeBinding(agentId: String, channel: String, accountId!: String = "", typeName!: String = "route"): JsonObject {
    let binding = JsonObject()
    if (!typeName.isEmpty()) {
        binding.put("type", JsonString(typeName))
    }
    binding.put("agentId", JsonString(agentId))
    let matchObj = JsonObject()
    matchObj.put("channel", JsonString(channel))
    if (!accountId.isEmpty()) {
        matchObj.put("accountId", JsonString(accountId))
    }
    binding.put("match", matchObj)
    binding
}

private func peerBinding(
    agentId: String,
    channel: String,
    peerKind: String,
    peerId: String,
    accountId!: String = "",
    typeName!: String = "route"
): JsonObject {
    let binding = routeBinding(agentId, channel, accountId: accountId, typeName: typeName)
    let matchObj = binding.get("match").getOrThrow().asObject()
    let peer = JsonObject()
    peer.put("kind", JsonString(peerKind))
    peer.put("id", JsonString(peerId))
    matchObj.put("peer", peer)
    binding
}

private func roleBinding(agentId: String, channel: String, guildId: String, roles: Array<String>): JsonObject {
    let binding = routeBinding(agentId, channel, accountId: "*")
    let matchObj = binding.get("match").getOrThrow().asObject()
    matchObj.put("guildId", JsonString(guildId))
    let arr = JsonArray([])
    for (role in roles) {
        arr.add(JsonString(role))
    }
    matchObj.put("roles", arr)
    binding
}

private func guildBinding(agentId: String, channel: String, guildId: String): JsonObject {
    let binding = routeBinding(agentId, channel, accountId: "*")
    binding.get("match").getOrThrow().asObject().put("guildId", JsonString(guildId))
    binding
}

private func teamBinding(agentId: String, channel: String, teamId: String): JsonObject {
    let binding = routeBinding(agentId, channel, accountId: "*")
    binding.get("match").getOrThrow().asObject().put("teamId", JsonString(teamId))
    binding
}

private func putBindings(root: JsonObject, bindings: Array<JsonObject>): Unit {
    let arr = JsonArray([])
    for (binding in bindings) {
        arr.add(binding)
    }
    root.put("bindings", arr)
}

private func applyBindings(root: JsonObject, bindings: Array<JsonObject>): GatewayAgentBindingApplyResult {
    let arr = JsonArray([])
    for (binding in bindings) {
        arr.add(binding)
    }
    gatewayApplyAgentRouteBindings(root, arr)
}

@Test
public class GatewayAgentRouteResolverTest {
    @TestCase
    public func defaultTypeMatchesRouteAndAcpDoesNot(): Unit {
        let root = routeTestConfig()
        putBindings(
            root,
            [
                peerBinding("ops", "telegram", "group", "-100_a", typeName: ""),
                peerBinding("reviewer", "telegram", "group", "-100_b", typeName: "acp")
            ]
        )

        let route = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_a"))
        @Expect(route.agentId, "ops")
        @Expect(route.matchedBy, "binding.peer.exact")

        let acpOnly = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_b"))
        @Expect(acpOnly.agentId, "main")
        @Expect(acpOnly.matchedBy, "default")
    }

    @TestCase
    public func accountDefaultOnlyMatchesDefaultAndStarMatchesAnyAccount(): Unit {
        let root = routeTestConfig()
        putBindings(
            root,
            [
                routeBinding("assistant-a", "telegram"),
                routeBinding("assistant-b", "telegram", accountId: "*")
            ]
        )

        let defaultAccount = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_a"))
        @Expect(defaultAccount.agentId, "assistant-a")
        @Expect(defaultAccount.accountId, "bot-a")
        @Expect(defaultAccount.preferredAccountId, "bot-a")
        @Expect(defaultAccount.matchedBy, "binding.account")

        let nonDefaultAccount = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-b", peerKind: "group", peerId: "-100_a"))
        @Expect(nonDefaultAccount.agentId, "assistant-b")
        @Expect(nonDefaultAccount.accountId, "bot-b")
        @Expect(nonDefaultAccount.preferredAccountId, "bot-a")
        @Expect(nonDefaultAccount.matchedBy, "binding.channel")
    }

    @TestCase
    public func explicitDefaultAccountMatchesResolvedChannelDefault(): Unit {
        let root = routeTestConfig()
        putBindings(
            root,
            [
                routeBinding("assistant-a", "telegram", accountId: "default"),
                routeBinding("assistant-b", "telegram", accountId: "*")
            ]
        )

        let omittedInputAccount = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", peerKind: "group", peerId: "-100_a"))
        @Expect(omittedInputAccount.agentId, "assistant-a")
        @Expect(omittedInputAccount.accountId, "bot-a")
        @Expect(omittedInputAccount.preferredAccountId, "bot-a")
        @Expect(omittedInputAccount.matchedBy, "binding.account")

        let explicitDefaultInputAccount = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "default", peerKind: "group", peerId: "-100_a"))
        @Expect(explicitDefaultInputAccount.agentId, "assistant-a")
        @Expect(explicitDefaultInputAccount.accountId, "bot-a")
        @Expect(explicitDefaultInputAccount.preferredAccountId, "bot-a")
        @Expect(explicitDefaultInputAccount.matchedBy, "binding.account")
    }

    @TestCase
    public func accountIdsAreCanonicalizedAcrossInputBindingAndChannelDefault(): Unit {
        let root = routeTestConfig()
        let channels = root.get("channels").getOrThrow().asObject()
        channels.put("telegram", routeTestChannel("Bot A!!", ["Bot A!!", "Ops/Bot"]))
        putBindings(
            root,
            [
                routeBinding("assistant-a", "telegram", accountId: "BOT A"),
                routeBinding("assistant-b", "telegram", accountId: "ops bot")
            ]
        )

        let defaultAccount = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: " default ", peerKind: "group", peerId: "-100_a"))
        @Expect(defaultAccount.agentId, "assistant-a")
        @Expect(defaultAccount.accountId, "bot-a")
        @Expect(defaultAccount.preferredAccountId, "bot-a")

        let explicitAccount = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "Ops/Bot", peerKind: "group", peerId: "-100_a"))
        @Expect(explicitAccount.agentId, "assistant-b")
        @Expect(explicitAccount.accountId, "ops-bot")
        @Expect(explicitAccount.preferredAccountId, "ops-bot")
    }

    @TestCase
    public func mostSpecificPriorityIsStableAcrossPeerParentWildcardGuildTeamAccountChannel(): Unit {
        let root = routeTestConfig()
        putBindings(
            root,
            [
                routeBinding("assistant-b", "telegram", accountId: "*"),
                routeBinding("assistant-a", "telegram", accountId: "bot-a"),
                teamBinding("team-agent", "telegram", "team-1"),
                guildBinding("guild-agent", "telegram", "guild-1"),
                roleBinding("roles-agent", "telegram", "guild-1", ["mod"]),
                peerBinding("pm", "telegram", "group", "*", accountId: "*"),
                peerBinding("ops", "telegram", "group", "-100_parent", accountId: "*"),
                peerBinding("reviewer", "telegram", "thread", "thread-42", accountId: "*")
            ]
        )

        let exact = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(
                root,
                "telegram",
                accountId: "bot-a",
                peerKind: "thread",
                peerId: "thread-42",
                parentPeerKind: "group",
                parentPeerId: "-100_parent",
                guildId: "guild-1",
                teamId: "team-1",
                roles: ["mod"]
            )
        )
        @Expect(exact.agentId, "reviewer")
        @Expect(exact.matchedBy, "binding.peer.exact")

        let parent = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(
                root,
                "telegram",
                accountId: "bot-a",
                peerKind: "thread",
                peerId: "thread-other",
                parentPeerKind: "group",
                parentPeerId: "-100_parent",
                guildId: "guild-1",
                teamId: "team-1",
                roles: ["mod"]
            )
        )
        @Expect(parent.agentId, "ops")
        @Expect(parent.matchedBy, "binding.peer.parent")

        let wildcard = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(
                root,
                "telegram",
                accountId: "bot-a",
                peerKind: "group",
                peerId: "-100_other",
                guildId: "guild-1",
                teamId: "team-1",
                roles: ["mod"]
            )
        )
        @Expect(wildcard.agentId, "pm")
        @Expect(wildcard.matchedBy, "binding.peer.wildcard")
    }

    @TestCase
    public func guildRolesGuildTeamAccountAndChannelFallbackTiersResolveAfterPeerTiers(): Unit {
        let root = routeTestConfig()
        putBindings(
            root,
            [
                routeBinding("assistant-b", "telegram", accountId: "*"),
                routeBinding("assistant-a", "telegram", accountId: "bot-a"),
                teamBinding("team-agent", "telegram", "team-1"),
                guildBinding("guild-agent", "telegram", "guild-1"),
                roleBinding("roles-agent", "telegram", "guild-1", ["mod"])
            ]
        )

        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "g1", guildId: "guild-1", teamId: "team-1", roles: ["mod"])
        ).matchedBy, "binding.guild+roles")
        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "g1", guildId: "guild-1", teamId: "team-1", roles: ["other"])
        ).matchedBy, "binding.guild")
        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "g1", teamId: "team-1")
        ).matchedBy, "binding.team")
        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "g1")
        ).matchedBy, "binding.account")
        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-b", peerKind: "group", peerId: "g1")
        ).matchedBy, "binding.channel")
    }

    @TestCase
    public func telegramAndFeishuTopicThreadRoutesBuildAgentScopedSessionKeys(): Unit {
        let root = routeTestConfig()
        putBindings(
            root,
            [
                peerBinding("ops", "telegram", "group", "-100_a", accountId: "*"),
                peerBinding("reviewer", "telegram", "topic", "42", accountId: "*"),
                peerBinding("pm", "feishu", "group", "oc_a", accountId: "*"),
                peerBinding("writer", "feishu", "thread", "thread_x", accountId: "*")
            ]
        )

        let telegramGroup = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_a"))
        @Expect(telegramGroup.agentId, "ops")
        @Expect(telegramGroup.sessionKey, "agent:ops:telegram:group:-100_a")
        @Expect(telegramGroup.lastRoutePolicy, "session")

        let telegramTopic = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "topic", peerId: "42",
                parentPeerKind: "group", parentPeerId: "-100_a"))
        @Expect(telegramTopic.agentId, "reviewer")
        @Expect(telegramTopic.sessionKey, "agent:reviewer:telegram:topic:42")

        let feishuGroup = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "feishu", accountId: "tenant-a", peerKind: "group", peerId: "oc_a"))
        @Expect(feishuGroup.agentId, "pm")
        @Expect(feishuGroup.sessionKey, "agent:pm:feishu:group:oc_a")

        let feishuThread = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "feishu", accountId: "tenant-a", peerKind: "thread", peerId: "thread_x",
                parentPeerKind: "group", parentPeerId: "oc_a"))
        @Expect(feishuThread.agentId, "writer")
        @Expect(feishuThread.sessionKey, "agent:writer:feishu:thread:thread_x")
    }

    @TestCase
    public func directDmScopesIncludeMainPeerChannelPeerAndPerAccountKeys(): Unit {
        let root = routeTestConfig()
        putBindings(root, [peerBinding("assistant-a", "telegram", "direct", "u_1", accountId: "*")])

        let mainRoute = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "direct", peerId: "u_1",
                dmScope: "main"))
        @Expect(mainRoute.sessionKey, "agent:assistant-a:main")
        @Expect(mainRoute.mainSessionKey, "agent:assistant-a:main")
        @Expect(mainRoute.lastRoutePolicy, "main")

        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "direct", peerId: "u_1", dmScope: "per-peer")
        ).sessionKey, "agent:assistant-a:direct:u_1")

        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "direct", peerId: "u_1", dmScope: "per-channel-peer")
        ).sessionKey, "agent:assistant-a:telegram:direct:u_1")

        @Expect(gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "direct", peerId: "u_1", dmScope: "per-account-channel-peer")
        ).sessionKey, "agent:assistant-a:telegram:bot-a:direct:u_1")
    }

    @TestCase
    public func mainDmOwnerPinMismatchIsExplicitAndDoesNotAuthorizeMainLastRouteUpdate(): Unit {
        let root = routeTestConfig()
        let route = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(
                root,
                "telegram",
                accountId: "bot-a",
                peerKind: "direct",
                peerId: "intruder",
                senderId: "intruder",
                dmScope: "main",
                mainDmOwnerId: "owner-1"
            )
        )
        @Expect(route.sessionKey, "agent:main:main")
        @Expect(route.lastRoutePolicy, "main")
        @Expect(route.allowMainLastRouteUpdate, false)
        @Expect(route.diagnostics.contains("main-dm-owner-mismatch"), true)
    }

    @TestCase
    public func legacyChannelAccountSpecConvertsToRouteBinding(): Unit {
        let binding = gatewayBuildLegacyAgentRouteBinding("assistant-a", "telegram:bot-a")
        let matchObj = binding.get("match").getOrThrow().asObject()
        @Expect(binding.get("type").getOrThrow().asString().getValue(), "route")
        @Expect(binding.get("agentId").getOrThrow().asString().getValue(), "assistant-a")
        @Expect(matchObj.get("channel").getOrThrow().asString().getValue(), "telegram")
        @Expect(matchObj.get("accountId").getOrThrow().asString().getValue(), "bot-a")
    }

    @TestCase
    public func bindingApplyReportsAddedUpdatedSkippedAndConflicts(): Unit {
        let root = routeTestConfig()
        putBindings(
            root,
            [
                routeBinding("assistant-a", "telegram"),
                routeBinding("ops", "telegram", accountId: "bot-b")
            ]
        )

        let result = applyBindings(
            root,
            [
                routeBinding("assistant-a", "telegram", accountId: "bot-a"),
                routeBinding("ops", "telegram", accountId: "bot-b"),
                routeBinding("reviewer", "telegram", accountId: "bot-b"),
                peerBinding("pm", "feishu", "group", "oc_a", accountId: "*")
            ]
        )

        @Expect(result.updated.size, 1)
        @Expect(result.skipped.size, 1)
        @Expect(result.conflicts.size, 1)
        @Expect(result.added.size, 1)
        @Expect(result.updated[0].get("match").getOrThrow().asObject().get("accountId").getOrThrow().asString().getValue(), "bot-a")
        @Expect(result.conflicts[0].existingAgentId, "ops")
    }

    @TestCase
    public func bindingApplyPreservesCommentAndEnabledMetadata(): Unit {
        let root = routeTestConfig()
        let disabled = routeBinding("assistant-a", "telegram")
        disabled.put("enabled", JsonBool(false))
        disabled.put("comment", JsonString("kept disabled route"))
        putBindings(root, [disabled])

        let incoming = peerBinding("ops", "telegram", "group", "-100_a", accountId: "*")
        incoming.put("enabled", JsonBool(true))
        incoming.put("comment", JsonString("new peer route"))
        let result = applyBindings(root, [incoming])

        @Expect(result.added.size, 1)
        @Expect(result.added[0].get("enabled").getOrThrow().asBool().getValue(), true)
        @Expect(result.added[0].get("comment").getOrThrow().asString().getValue(), "new peer route")

        let rows = result.config.get("bindings").getOrThrow().asArray()
        let kept = rows[0].asObject()
        @Expect(kept.get("enabled").getOrThrow().asBool().getValue(), false)
        @Expect(kept.get("comment").getOrThrow().asString().getValue(), "kept disabled route")
    }

    @TestCase
    public func unknownAgentFallsBackToDefaultWithDiagnostic(): Unit {
        let root = routeTestConfig()
        putBindings(root, [peerBinding("missing-agent", "telegram", "group", "-100_a", accountId: "*")])

        let route = gatewayResolveAgentRoute(
            GatewayAgentRouteInput(root, "telegram", accountId: "bot-a", peerKind: "group", peerId: "-100_a"))
        @Expect(route.agentId, "main")
        @Expect(route.matchedBy, "binding.peer.exact")
        @Expect(route.diagnostics.contains("unknown-agent:missing-agent"), true)
    }
}
