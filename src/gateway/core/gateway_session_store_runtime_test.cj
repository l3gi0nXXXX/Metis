package metis.gateway.core

import metis.core.config.GatewayUserSettings
import metis.gateway.session.{GatewayDeliveryTarget, GatewayIngressSource, gatewaySessionRequestFromRpcParams}

import magic.jsonable.*
import std.fs.File
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

@Test
public class GatewaySessionStoreRuntimeTest {
    @TestCase
    public func listSessionLocationsAggregatesAcrossAgentRoots(): Unit {
        let user = GatewayUserSettings()
        let mainStore = gatewaySessionStoreForUserWithAgentId(user, "main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(user, "general")
        let mainKey = "agent:main:runtime-test"
        let generalKey = "agent:general:runtime-test"
        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
        mainStore.appendUser(mainKey, "main")
        generalStore.appendUser(generalKey, "general")

        let locations = gatewayListSessionLocationsForUser(user)
        var sawMain = false
        var sawGeneral = false
        for (entry in locations) {
            if (entry.sessionKey == mainKey && entry.agentId == "main") {
                sawMain = true
            }
            if (entry.sessionKey == generalKey && entry.agentId == "general") {
                sawGeneral = true
            }
        }
        @Expect(sawMain, true)
        @Expect(sawGeneral, true)

        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
    }

    @TestCase
    public func findSessionLocationReturnsOwningAgentRoot(): Unit {
        let user = GatewayUserSettings()
        let generalStore = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:location-test"
        generalStore.deleteSession(sessionKey)
        generalStore.appendUser(sessionKey, "hello")

        let location = gatewayFindSessionLocationForUser(user, sessionKey).getOrThrow()
        @Expect(location.agentId, "general")
        @Expect(location.sessionKey, sessionKey)
        @Expect(location.root.toString(), generalStore.sessionsRoot().toString())

        generalStore.deleteSession(sessionKey)
    }

    @TestCase
    public func resolvedRequestStoreUsesResolvedAgentContext(): Unit {
        let user = GatewayUserSettings()
        let params = JsonObject()
        params.put("session", JsonString("agent:general:main"))
        let request = gatewaySessionRequestFromRpcParams(params, fallbackSource: GatewayIngressSource.Cli)
        let store = gatewaySessionStoreForResolvedRequest(user, request)
        let generalStore = gatewaySessionStoreForUserWithAgentId(user, "general")
        @Expect(store.sessionsRoot().toString(), generalStore.sessionsRoot().toString())
    }

    @TestCase
    public func sessionKeyStoreHelperUsesResolvedAgentContext(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForSessionKey(user, "agent:general:main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(user, "general")
        @Expect(store.sessionsRoot().toString(), generalStore.sessionsRoot().toString())
    }

    @TestCase
    public func sessionCatalogRowsExposeTranscriptMetadata(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:catalog-row-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let rows = gatewayListSessionCatalogRowsForUser(user)
        var found = false
        for (row in rows) {
            if (row.sessionKey != sessionKey) {
                continue
            }
            found = true
            @Expect(row.agentId, "general")
            @Expect(row.sessionId.contains(".jsonl"), false)
            @Expect(row.sessionFile.endsWith(".jsonl"), true)
            @Expect(row.root.toString(), store.sessionsRoot().toString())
            @Expect(row.updatedAt > 0, true)
        }
        @Expect(found, true)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func findSessionCatalogRowReturnsOwningMetadata(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:catalog-find-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let row = gatewayFindSessionCatalogRowForUser(user, sessionKey).getOrThrow()
        @Expect(row.agentId, "general")
        @Expect(row.sessionKey, sessionKey)
        @Expect(row.root.toString(), store.sessionsRoot().toString())

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func projectSessionCatalogRowDerivesChannelAndDisplayName(): Unit {
        let qqRow = GatewaySessionCatalogRow(
            "main",
            "qq:group:chat-42",
            gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main").sessionsRoot(),
            "qq_group_chat_42",
            "qq_group_chat_42.jsonl",
            1
        )
        let qqView = gatewayProjectSessionCatalogRow(qqRow)
        @Expect(qqView.channel, "qq")
        @Expect(qqView.chatType, "group")
        @Expect(qqView.peer, "chat-42")
        @Expect(qqView.displayName, "chat-42")

        let cliRow = GatewaySessionCatalogRow(
            "main",
            "cli:main",
            gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main").sessionsRoot(),
            "cli_main",
            "cli_main.jsonl",
            1
        )
        let cliView = gatewayProjectSessionCatalogRow(cliRow)
        @Expect(cliView.channel, "cli")
        @Expect(cliView.chatType, "direct")
        @Expect(cliView.displayName, "CLI")

        let qqOrigin = gatewayBuildSessionCatalogOrigin(qqView)
        @Expect(qqOrigin.get("provider").getOrThrow().asString().getValue(), "qq")
        @Expect(qqOrigin.get("to").getOrThrow().asString().getValue(), "chat-42")

        let cliOrigin = gatewayBuildSessionCatalogOrigin(cliView)
        @Expect(cliOrigin.get("surface").getOrThrow().asString().getValue(), "cli")
        @Expect(cliOrigin.get("from").getOrThrow().asString().getValue(), "local-user")

        let qqConversation = gatewayBuildSessionConversationView(qqView)
        @Expect(qqConversation.displayName, "chat-42")
        @Expect(qqConversation.origin.get("to").getOrThrow().asString().getValue(), "chat-42")
        @Expect(qqConversation.delivery.get("channel").getOrThrow().asString().getValue(), "qq")
        @Expect(qqConversation.delivery.get("replyTo").getOrThrow().asString().getValue(), "chat-42")
        @Expect(qqConversation.delivery.get("conversationId").getOrThrow().asString().getValue(), "chat-42")
        @Expect(qqConversation.delivery.get("replyToMessageId").getOrThrow().asString().getValue(), "")
        @Expect(qqConversation.delivery.get("replyInThread").getOrThrow().asBool().getValue(), false)
        @Expect(qqConversation.binding.get("conversationId").getOrThrow().asString().getValue(), "chat-42")
        @Expect(qqConversation.binding.get("replyTargetMessageId").getOrThrow().asString().getValue(), "")
    }

    @TestCase
    public func catalogRowReplaysLatestBindingSnapshotFromTranscript(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "main")
        let sessionKey = "feishu:group:chat-ou_phase10"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")
        store.appendBindingSnapshot(
            sessionKey,
            GatewayDeliveryTarget(
                "feishu",
                "chat-ou_phase10",
                accountId: "feishu:bot-default",
                conversationId: "chat-ou_phase10",
                threadId: "thread-42",
                sourceMessageId: "msg-source-42",
                replyToMessageId: "msg-root-42",
                replyInThread: true
            )
        )

        let row = gatewayFindSessionCatalogRowForUser(user, sessionKey).getOrThrow()
        @Expect(row.deliverySnapshot.get("threadId").getOrThrow().asString().getValue(), "thread-42")
        @Expect(row.bindingSnapshot.get("replyTargetMessageId").getOrThrow().asString().getValue(), "msg-root-42")

        let conversation = gatewayFindSessionConversationViewForUser(user, sessionKey).getOrThrow()
        @Expect(conversation.delivery.get("threadId").getOrThrow().asString().getValue(), "thread-42")
        @Expect(conversation.delivery.get("sourceMessageId").getOrThrow().asString().getValue(), "msg-source-42")
        @Expect(conversation.delivery.get("replyToMessageId").getOrThrow().asString().getValue(), "msg-root-42")
        @Expect(conversation.binding.get("replyTargetMessageId").getOrThrow().asString().getValue(), "msg-root-42")
        @Expect(conversation.binding.get("replyInThread").getOrThrow().asBool().getValue(), true)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func projectSessionCatalogRowPrefersBindingSnapshotIdentity(): Unit {
        let binding = JsonObject()
        binding.put("channel", JsonString("plugin-demo"))
        binding.put("peer", JsonString("conversation-99"))
        binding.put("conversationId", JsonString("conversation-99"))
        binding.put("accountId", JsonString("plugin-demo:acct-1"))
        let row = GatewaySessionCatalogRow(
            "main",
            "gateway:peer:user-42",
            gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main").sessionsRoot(),
            "gateway_peer_user_42",
            "gateway_peer_user_42.jsonl",
            1,
            bindingSnapshot: binding
        )
        let view = gatewayProjectSessionCatalogRow(row)
        @Expect(view.channel, "plugin-demo")
        @Expect(view.peer, "conversation-99")
        @Expect(view.displayName, "conversation-99")
        let origin = gatewayBuildSessionCatalogOrigin(view)
        @Expect(origin.get("provider").getOrThrow().asString().getValue(), "plugin-demo")
        @Expect(origin.get("to").getOrThrow().asString().getValue(), "conversation-99")
        @Expect(origin.get("accountId").getOrThrow().asString().getValue(), "plugin-demo:acct-1")
    }

    @TestCase
    public func catalogRowsReplaySessionsJsonMetadata(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:metadata-row-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let root = JsonObject()
        let entry = JsonObject()
        entry.put("sessionKey", JsonString(sessionKey))
        entry.put("updatedAt", 123.toJsonValue())
        entry.put("sessionFile", JsonString("agent_general_metadata-row-test.jsonl"))
        entry.put("sessionId", JsonString("agent_general_metadata-row-test"))
        entry.put("sendPolicy", JsonString("deny"))
        entry.put("verboseLevel", JsonString("on"))
        entry.put("responseUsage", JsonString("full"))
        entry.put("fastMode", true.toJsonValue())
        entry.put("lastChannel", JsonString("telegram"))
        entry.put("lastTo", JsonString("-100123"))
        entry.put("lastAccountId", JsonString("acct-1"))
        entry.put("lastThreadId", 42.toJsonValue())
        entry.put("modelProvider", JsonString("openai"))
        entry.put("model", JsonString("gpt-5.4"))
        entry.put("contextTokens", 123456.toJsonValue())
        entry.put("totalTokens", 2400.toJsonValue())
        entry.put("totalTokensFresh", true.toJsonValue())
        entry.put("estimatedCostUsd", 0.0042.toJsonValue())
        entry.put("spawnedBy", JsonString("agent:main:main"))
        entry.put("spawnedWorkspaceDir", JsonString("/tmp/subagent-workspace"))
        entry.put("forkedFromParent", true.toJsonValue())
        entry.put("spawnDepth", 2.toJsonValue())
        entry.put("subagentRole", JsonString("orchestrator"))
        entry.put("subagentControlScope", JsonString("children"))
        entry.put("parentSessionKey", JsonString("agent:main:main"))
        let children = JsonArray([])
        children.add(JsonString("agent:general:child"))
        entry.put("childSessions", children)
        root.put(sessionKey, entry)
        File.writeTo(store.sessionsRoot().join("sessions.json"), root.toJsonString().toArray())

        let row = gatewayFindSessionCatalogRowForUser(user, sessionKey).getOrThrow()
        @Expect(row.sendPolicy, "deny")
        @Expect(row.verboseLevel, "on")
        @Expect(row.responseUsage, "full")
        @Expect(row.fastMode, true)
        @Expect(row.lastChannel, "telegram")
        @Expect(row.lastTo, "-100123")
        @Expect(row.lastAccountId, "acct-1")
        @Expect(row.lastThreadId, 42)
        @Expect(row.modelProvider, "openai")
        @Expect(row.model, "gpt-5.4")
        @Expect(row.contextTokens, 123456)
        @Expect(row.totalTokens, 2400)
        @Expect(row.totalTokensFresh, true)
        @Expect(row.spawnedBy, "agent:main:main")
        @Expect(row.spawnedWorkspaceDir, "/tmp/subagent-workspace")
        @Expect(row.forkedFromParent, true)
        @Expect(row.spawnDepth, 2)
        @Expect(row.subagentRole, "orchestrator")
        @Expect(row.subagentControlScope, "children")
        @Expect(row.parentSessionKey, "agent:main:main")
        @Expect(row.childSessions.size, 1)
        @Expect(row.childSessions[0], "agent:general:child")

        store.deleteSession(sessionKey)
    }
}
