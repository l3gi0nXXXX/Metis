package metis.gateway.core

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.model.ChatType
import metis.gateway.session.{GatewayIngressSource, GatewaySessionRequest}
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func broadcastStringArray(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(JsonString(value))
    }
    out
}

private func broadcastAgentEntry(home: Path, id: String, modelRef: String, toolName: String, isDefault!: Bool = false): JsonObject {
    let entry = JsonObject()
    entry.put("id", JsonString(id))
    if (isDefault) {
        entry.put("default", JsonBool(true))
    }
    entry.put("workspace", JsonString(home.join("workspaces").join(id).toString()))
    entry.put("agentDir", JsonString(home.join("agents").join(id).join("agent").toString()))
    entry.put("sessionsDir", JsonString(home.join("sessions").join(id).toString()))
    let model = JsonObject()
    model.put("primary", JsonString(modelRef))
    entry.put("model", model)
    let tools = JsonObject()
    tools.put("allow", broadcastStringArray([toolName]))
    entry.put("tools", tools)
    return entry
}

private func broadcastBinding(agentId: String, channel: String, peerKind: String, peerId: String): JsonObject {
    let binding = JsonObject()
    binding.put("type", JsonString("route"))
    binding.put("agentId", JsonString(agentId))
    let matchObj = JsonObject()
    matchObj.put("channel", JsonString(channel))
    matchObj.put("accountId", JsonString("*"))
    let peer = JsonObject()
    peer.put("kind", JsonString(peerKind))
    peer.put("id", JsonString(peerId))
    matchObj.put("peer", peer)
    binding.put("match", matchObj)
    return binding
}

private func broadcastMember(agentId: String): JsonObject {
    let member = JsonObject()
    member.put("agentId", JsonString(agentId))
    return member
}

private func broadcastTeam(enabledValue: Option<JsonBool>, selectedMembers!: Array<String> = []): JsonObject {
    let team = JsonObject()
    team.put("id", JsonString("content"))
    team.put("displayName", JsonString("Content Team"))
    team.put("defaultAgentId", JsonString("ops"))
    let members = JsonArray([])
    members.add(broadcastMember("ops"))
    members.add(broadcastMember("writer"))
    members.add(broadcastMember("reviewer"))
    team.put("members", members)
    let bindings = JsonArray([])
    bindings.add(broadcastBinding("ops", "fake", "group", "room-1"))
    team.put("bindings", bindings)
    let broadcast = JsonObject()
    match (enabledValue) {
        case Some(v) => broadcast.put("enabled", v)
        case None => ()
    }
    if (selectedMembers.size > 0) {
        broadcast.put("members", broadcastStringArray(selectedMembers))
    }
    team.put("broadcast", broadcast)
    return team
}

private func broadcastRoot(home: Path, team: JsonObject): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let list = JsonArray([])
    list.add(broadcastAgentEntry(home, "main", "openai:gpt-main", "mainTool", isDefault: true))
    list.add(broadcastAgentEntry(home, "ops", "openai:gpt-ops", "opsTool"))
    list.add(broadcastAgentEntry(home, "writer", "openai:gpt-writer", "writerTool"))
    list.add(broadcastAgentEntry(home, "reviewer", "openai:gpt-reviewer", "reviewerTool"))
    agents.put("list", list)
    root.put("agents", agents)

    let channels = JsonObject()
    let fake = JsonObject()
    fake.put("defaultAccountId", JsonString("bot-a"))
    fake.put("accountIds", broadcastStringArray(["bot-a"]))
    channels.put("fake", fake)
    root.put("channels", channels)

    let bindings = JsonArray([])
    bindings.add(broadcastBinding("ops", "fake", "group", "room-1"))
    root.put("bindings", bindings)

    let agentTeams = JsonObject()
    agentTeams.put("list", JsonArray([team]))
    root.put("agentTeams", agentTeams)
    return root
}

private func broadcastMediaContext(): JsonObject {
    let media = JsonObject()
    let context = JsonObject()
    let route = JsonObject()
    route.put("accountId", JsonString("bot-a"))
    route.put("defaultAccountId", JsonString("bot-a"))
    route.put("peerKind", JsonString("group"))
    route.put("peerId", JsonString("room-1"))
    context.put("imRoute", route)
    media.put("context", context)
    return media
}

private func broadcastRequest(root: JsonObject): GatewaySessionRequest {
    GatewaySessionRequest(
        GatewayIngressSource.Channel("fake"),
        channelName: "fake",
        sessionHint: "fake:group:room-1",
        text: "hello team",
        accountId: "bot-a",
        peerId: "room-1",
        senderId: "user-1",
        conversationId: "room-1",
        sourceMessageId: "msg-1",
        chatType: Some(ChatType.Group),
        dmScope: "per-chat",
        replyToMessageId: "msg-1",
        deliver: true,
        mediaContext: broadcastMediaContext(),
        routeRoot: root,
        routeAccountId: "bot-a",
        routeDefaultAccountId: "bot-a",
        routePeerKind: "group",
        routePeerId: "room-1"
    )
}

private func withBroadcastTempHome<T>(label: String, block: (Path) -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = Path("/tmp/metis-agent-team-broadcast-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
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

private func writeBroadcastRoot(root: JsonObject): Unit {
    File.writeTo(MetisConfigManager.configPath(), root.toJsonString().toArray())
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
}

private func broadcastRouteString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayAgentTeamBroadcastTest {
    @TestCase
    public func disabledBroadcastFallsBackToCurrentSingleAgentRouting(): Unit {
        withBroadcastTempHome("disabled", { home: Path =>
            let root = broadcastRoot(home, broadcastTeam(Some(JsonBool(false)), selectedMembers: ["writer", "reviewer"]))
            writeBroadcastRoot(root)
            let request = broadcastRequest(root)

            let direct = gatewayResolveSessionContextWithAgentRoute(request)
            let plan = gatewayResolveAgentTeamBroadcastPlan(request)

            @Expect(plan.enabled, false)
            @Expect(plan.turns.size, 1)
            @Expect(plan.turns[0].context.agentId, direct.agentId)
            @Expect(plan.turns[0].context.sessionKey, direct.sessionKey)
            @Expect(plan.turns[0].context.matchedBy, "binding.peer.exact")
        })
    }

    @TestCase
    public func enabledBroadcastFansOutOnlySelectedMembersWithIsolatedRuntimeScope(): Unit {
        withBroadcastTempHome("enabled", { home: Path =>
            let root = broadcastRoot(home, broadcastTeam(Some(JsonBool(true)), selectedMembers: ["writer", "reviewer"]))
            writeBroadcastRoot(root)
            let plan = gatewayResolveAgentTeamBroadcastPlan(broadcastRequest(root))

            @Expect(plan.enabled, true)
            @Expect(plan.teamId, "content")
            @Expect(plan.selectedAgentIds.size, 2)
            @Expect(plan.selectedAgentIds.contains("writer"), true)
            @Expect(plan.selectedAgentIds.contains("reviewer"), true)
            @Expect(plan.turns.size, 2)
            @Expect(plan.turns[0].context.agentId, "writer")
            @Expect(plan.turns[1].context.agentId, "reviewer")
            @Expect(plan.turns[0].context.sessionKey, "agent:writer:fake:group:room-1")
            @Expect(plan.turns[1].context.sessionKey, "agent:reviewer:fake:group:room-1")
            @Expect(plan.turns[0].context.sessionKey == plan.turns[1].context.sessionKey, false)
            @Expect(plan.turns[0].request.sessionHint == plan.turns[1].request.sessionHint, false)
            @Expect(plan.turns[0].context.turnContext.workspaceDir, home.join("workspaces").join("writer").toString())
            @Expect(plan.turns[1].context.turnContext.workspaceDir, home.join("workspaces").join("reviewer").toString())
            @Expect(plan.turns[0].context.turnContext.modelRef, "openai:gpt-writer")
            @Expect(plan.turns[1].context.turnContext.modelRef, "openai:gpt-reviewer")
            @Expect(plan.turns[0].context.turnContext.agentScope.toJsonString().contains("writerTool"), true)
            @Expect(plan.turns[1].context.turnContext.agentScope.toJsonString().contains("reviewerTool"), true)

            let executableWriterContext = gatewayResolveSessionContextWithAgentRoute(plan.turns[0].request)
            @Expect(executableWriterContext.agentId, "writer")
            @Expect(executableWriterContext.sessionKey, "agent:writer:fake:group:room-1")
            @Expect(broadcastRouteString(executableWriterContext.turnContext.route, "matchedBy"), "broadcast.team")
            @Expect(broadcastRouteString(executableWriterContext.turnContext.route, "broadcastTeamId"), "content")
        })
    }

    @TestCase
    public func broadcastRequiresBooleanEnabledTrueAndASelectedMemberList(): Unit {
        withBroadcastTempHome("explicit-enabled", { home: Path =>
            let stringEnabledTeam = broadcastTeam(None, selectedMembers: ["writer", "reviewer"])
            stringEnabledTeam.get("broadcast").getOrThrow().asObject().put("enabled", JsonString("true"))
            let stringEnabledRoot = broadcastRoot(home, stringEnabledTeam)
            writeBroadcastRoot(stringEnabledRoot)
            let stringPlan = gatewayResolveAgentTeamBroadcastPlan(broadcastRequest(stringEnabledRoot))
            @Expect(stringPlan.enabled, false)
            @Expect(stringPlan.turns.size, 1)
            @Expect(stringPlan.turns[0].context.agentId, "ops")

            let noMembersRoot = broadcastRoot(home, broadcastTeam(Some(JsonBool(true))))
            writeBroadcastRoot(noMembersRoot)
            let noMembersPlan = gatewayResolveAgentTeamBroadcastPlan(broadcastRequest(noMembersRoot))
            @Expect(noMembersPlan.enabled, false)
            @Expect(noMembersPlan.turns.size, 1)
            @Expect(noMembersPlan.diagnostics.contains("broadcast-members-empty:content"), true)
        })
    }

    @TestCase
    public func broadcastAggregateIsDeterministicAndCarriesPerAgentStatus(): Unit {
        withBroadcastTempHome("aggregate", { home: Path =>
            let root = broadcastRoot(home, broadcastTeam(Some(JsonBool(true)), selectedMembers: ["writer", "reviewer"]))
            writeBroadcastRoot(root)
            let plan = gatewayResolveAgentTeamBroadcastPlan(broadcastRequest(root))
            let writer = GatewayResolvedSessionTurnResult(
                plan.turns[0].context,
                GatewaySessionExecutionResult("writer answer", delivered: true, deliveryStatus: "delivered", deliveryMessageId: "m-writer")
            )
            let reviewer = GatewayResolvedSessionTurnResult(
                plan.turns[1].context,
                GatewaySessionExecutionResult("reviewer answer", delivered: false, deliveryStatus: "not-requested")
            )

            let aggregate = gatewayAgentTeamBroadcastAggregateJson(plan, [reviewer, writer])
            @Expect(aggregate.get("kind").getOrThrow().asString().getValue(), "agent-team-broadcast-aggregate")
            @Expect(aggregate.get("teamId").getOrThrow().asString().getValue(), "content")
            @Expect(aggregate.get("status").getOrThrow().asString().getValue(), "partial")
            @Expect(aggregate.get("delivered").getOrThrow().asBool().getValue(), true)
            let agents = aggregate.get("agents").getOrThrow().asArray()
            @Expect(agents.size(), 2)
            @Expect(agents[0].asObject().get("agentId").getOrThrow().asString().getValue(), "writer")
            @Expect(agents[0].asObject().get("deliveryStatus").getOrThrow().asString().getValue(), "delivered")
            @Expect(agents[0].asObject().get("detail").getOrThrow().asString().getValue(), "delivered")
            @Expect(agents[1].asObject().get("agentId").getOrThrow().asString().getValue(), "reviewer")
            @Expect(agents[1].asObject().get("status").getOrThrow().asString().getValue(), "not-delivered")
            @Expect(agents[1].asObject().get("detail").getOrThrow().asString().getValue(), "not-requested")
            @Expect(aggregate.get("answer").getOrThrow().asString().getValue(), "[writer] writer answer\n[reviewer] reviewer answer")
        })
    }
}
