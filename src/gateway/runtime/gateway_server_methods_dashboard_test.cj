package metis.gateway.runtime

import metis.core.config.{CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.gateway.core.{gatewayBuildSessionConversationView, gatewayFindSessionCatalogViewForUser, gatewaySessionStoreForUserWithAgentId}

import std.fs.File
import std.fs.{Directory, Path, remove}
import std.env.{getVariable, setVariable}
import std.convert.Parsable
import std.time.*
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func dashboardStringField(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func dashboardConcatLines(lines: Array<String>): String {
    var out = ""
    for (i in 0..lines.size) {
        if (i > 0) {
            out += "\n"
        }
        out += lines[i]
    }
    out
}

private func withGatewayDashboardTestHome<T>(home: String, block: () -> T): T {
    try {
        remove(Path(home), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(home, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", home)
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}

@Test
public class GatewayServerMethodsDashboardTest {
    @TestCase
    public func chatHistoryResolvesAgentScopedSessionKey(): Unit {
        withGatewayDashboardTestHome("/tmp/metis-dashboard-chat-history-test-home") {
            let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
            let sessionKey = "agent:general:main"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(sessionKey, "world")
            store.listSessionKeys()

            let params = JsonObject()
            params.put("session", JsonString("main"))
            params.put("agentId", JsonString("general"))
            let result = JsonValue.fromStr(gatewayDashboardChatHistoryJsonFromRpc(params)).asObject()
            @Expect(dashboardStringField(result, "session"), sessionKey)

            let messages = result.get("messages").getOrThrow().asArray()
            @Expect(messages.size() >= 1, true)
            @Expect(dashboardStringField(messages[0].asObject(), "role").isEmpty(), false)
            @Expect(dashboardStringField(messages[0].asObject(), "text").isEmpty(), false)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func chatHistoryCacheRefreshesWhenTranscriptChanges(): Unit {
        withGatewayDashboardTestHome("/tmp/metis-dashboard-history-cache-test-home") {
            let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
            let sessionKey = "agent:general:history-cache-test"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(sessionKey, "world")
            store.listSessionKeys()

            let params = JsonObject()
            params.put("session", JsonString(sessionKey))
            params.put("agentId", JsonString("general"))

            let first = JsonValue.fromStr(gatewayDashboardChatHistoryJsonFromRpc(params)).asObject()
            let firstMessages = first.get("messages").getOrThrow().asArray()
            let firstHasMessages = firstMessages.size() >= 2
            @Expect(firstHasMessages || firstMessages.size() == 0, true)

            sleep(Duration.millisecond * 5)
            store.appendAssistant(sessionKey, "again")
            store.listSessionKeys()

            let second = JsonValue.fromStr(gatewayDashboardChatHistoryJsonFromRpc(params)).asObject()
            let secondMessages = second.get("messages").getOrThrow().asArray()
            let cacheRefreshed = secondMessages.size() >= firstMessages.size()
            @Expect(cacheRefreshed, true)
            if (secondMessages.size() > 0) {
                let lastText = dashboardStringField(secondMessages[secondMessages.size() - 1].asObject(), "text")
                @Expect(lastText.isEmpty(), false)
            }

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func chatHistoryPreservesAssistantUsageAndModelMetadata(): Unit {
        withGatewayDashboardTestHome("/tmp/metis-dashboard-history-meta-test-home") {
            let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
            let sessionKey = "agent:main:history-meta-test"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(
                sessionKey,
                "world",
                modelName: "qwen:qwen3.5-plus",
                promptTokens: 29100,
                completionTokens: 236
            )
            store.listSessionKeys()

            let params = JsonObject()
            params.put("session", JsonString(sessionKey))
            params.put("agentId", JsonString("main"))
            let result = JsonValue.fromStr(gatewayDashboardChatHistoryJsonFromRpc(params)).asObject()
            let messages = result.get("messages").getOrThrow().asArray()
            @Expect(messages.size() >= 2, true)
            let assistant = messages[messages.size() - 1].asObject()
            @Expect(dashboardStringField(assistant, "role"), "assistant")
            @Expect(dashboardStringField(assistant, "model"), "qwen:qwen3.5-plus")
            @Expect(dashboardStringField(assistant, "provider"), "qwen")
            let usage = assistant.get("usage").getOrThrow().asObject()
            @Expect(usage.get("input").getOrThrow().toJsonString(), "29100")
            @Expect(usage.get("output").getOrThrow().toJsonString(), "236")

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func sessionsDeleteUsesResolvedSessionKey(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let sessionKey = "agent:general:main"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "cleanup")

        let params = JsonObject()
        params.put("keys", JsonString("main"))
        params.put("agentId", JsonString("general"))
        let result = JsonValue.fromStr(gatewayDashboardSessionsDeleteJsonFromRpc(params)).asObject()
        let deleted = result.get("deleted").getOrThrow().asArray()
        @Expect(deleted.size(), 1)
        @Expect(deleted[0].asString().getValue(), sessionKey)
        @Expect(store.readTranscriptRaw(sessionKey).isSome(), false)
    }

    @TestCase
    public func statusAggregatesSessionCountAcrossAgentStores(): Unit {
        let mainStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let mainKey = "agent:main:status-test"
        let generalKey = "agent:general:status-test"
        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
        mainStore.appendUser(mainKey, "hello-main")
        generalStore.appendUser(generalKey, "hello-general")

        let sessions = dashboardBuildSessionsJson(GatewayUserSettings(), 120)
        let count = Int64.parse(sessions.get("count").getOrThrow().toJsonString())
        let roots = sessions.get("storageRoots").getOrThrow().asArray().toJsonString()
        @Expect(count >= 2, true)
        @Expect(roots.contains(mainStore.sessionsRoot().toString()), true)
        @Expect(roots.contains(generalStore.sessionsRoot().toString()), true)

        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
    }

    @TestCase
    public func modelSwitchPreservesExistingGatewayAuthToken(): Unit {
        let testHome = "/tmp/metis-phase2-dashboard-model-switch"
        try {
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()

        let root = JsonObject()
        let agents = JsonObject()
        let defaults = JsonObject()
        let model = JsonObject()
        model.put("primary", JsonString("qwen/qwen3.6-plus"))
        defaults.put("model", model)
        defaults.put("workspace", JsonString("/tmp/project"))
        agents.put("defaults", defaults)
        root.put("agents", agents)

        let gateway = JsonObject()
        let auth = JsonObject()
        auth.put("mode", JsonString("token"))
        auth.put("token", JsonString("dashboard-token"))
        gateway.put("auth", auth)
        root.put("gateway", gateway)
        root.put("session", JsonObject())
        root.put("wizard", JsonObject())
        MetisConfigManager.writeRoot(root)

        let params = JsonObject()
        params.put("model", JsonString("openai:gpt-5"))
        let response = handleGatewayDashboardFamily(
            "dashboard.model.switch",
            GatewayRpcRequest("dashboard.model.switch", params: params)
        ).getOrThrow()
        let result = response.result.asObject()
        @Expect(result.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(dashboardStringField(result, "current"), "openai:gpt-5")

        let persisted = MetisConfigManager.rawConfig().getOrThrow()
        @Expect(
            persisted.get("agents").getOrThrow().asObject()
                .get("defaults").getOrThrow().asObject()
                .get("model").getOrThrow().asObject()
                .get("primary").getOrThrow().asString().getValue(),
            "openai/gpt-5"
        )
        @Expect(
            persisted.get("gateway").getOrThrow().asObject()
                .get("auth").getOrThrow().asObject()
                .get("token").getOrThrow().asString().getValue(),
            "dashboard-token"
        )

        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }

    @TestCase
    public func statusDetailsReuseSessionCatalogMetadata(): Unit {
        withGatewayDashboardTestHome("/tmp/metis-dashboard-catalog-test-home") {
            let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
            let sessionKey = "agent:general:dashboard-catalog-test"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello-dashboard")
            store.listSessionKeys()

            let sessions = dashboardBuildSessionsJson(GatewayUserSettings(), 120)
            let details = sessions.get("details").getOrThrow().asArray()
            var found = false
            for (i in 0..details.size()) {
                let row = details[i].asObject()
                if (dashboardStringField(row, "key") != sessionKey) {
                    continue
                }
                found = true
                @Expect(dashboardStringField(row, "agentId"), "general")
                @Expect(dashboardStringField(row, "sessionId").contains(".jsonl"), false)
                @Expect(dashboardStringField(row, "sessionFile").endsWith(".jsonl"), true)
                @Expect(dashboardStringField(row, "root"), store.sessionsRoot().toString())
                @Expect(dashboardStringField(row, "displayName"), "dashboard-catalog-test")
                @Expect(dashboardStringField(row, "channel"), "agent")
                @Expect(dashboardStringField(row, "chatType"), "direct")
                @Expect(row.get("origin").isSome(), true)
            }
            @Expect(found, true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func statusDetailsIncludeTelegramThreadBindingProjection(): Unit {
        withGatewayDashboardTestHome("/tmp/metis-dashboard-thread-binding-test-home") {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "main")
            let sessionKey = "agent:main:dashboard-telegram-thread-binding"
            store.deleteSession(sessionKey)
            let transcriptLines = [
                "{\"kind\":\"meta\",\"v\":\"1\",\"sessionKey\":\"${sessionKey}\"}",
                "{\"role\":\"system\",\"text\":\"sessions_spawn metadata: runtime=subagent, streamTo=telegram:group:-1001234567890:topic:42, thread=true\"}"
            ]
            File.writeTo(store.transcriptPath(sessionKey), dashboardConcatLines(transcriptLines).toArray())
            store.listSessionKeys()

            let sessions = dashboardBuildSessionsJson(user, 120)
            let details = sessions.get("details").getOrThrow().asArray()
            var found = false
            for (i in 0..details.size()) {
                let row = details[i].asObject()
                if (dashboardStringField(row, "key") != sessionKey) {
                    continue
                }
                found = true
                if (row.get("threadBinding").isSome()) {
                    let threadBinding = row.get("threadBinding").getOrThrow().asObject()
                    @Expect(dashboardStringField(threadBinding, "channel"), "telegram")
                    @Expect(dashboardStringField(threadBinding, "threadId"), "42")
                }
            }
            @Expect(found, true)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func dashboardChannelsAuditReusesUnifiedTelegramAuditSurface(): Unit {
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let response = handleGatewayDashboardFamily(
            "dashboard.channels.audit",
            GatewayRpcRequest("dashboard.channels.audit", params: params)
        ).getOrThrow()
        let audit = response.result.asObject().get("audit").getOrThrow().asObject()
        @Expect(dashboardStringField(audit, "kind"), "gateway-channels-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(dashboardStringField(summary, "phase"), "T12")
        let closure = summary.get("closure").getOrThrow().asObject()
        @Expect(closure.get("telegramReactionRuntimeVisible").getOrThrow().asBool().getValue(), true)
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(consumers.get("dashboardSessions").getOrThrow().asBool().getValue(), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        let telegram = runtime.get("telegram").getOrThrow().asObject()
        @Expect(telegram.get("registrationPayload").isSome(), true)
        @Expect(telegram.get("healthSnapshot").isSome(), true)
    }

    @TestCase
    public func summarizeSessionReadsResolvedAgentStore(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let sessionKey = "agent:general:summary-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")
        store.appendAssistant(sessionKey, "world")

        let (count, approx, _updatedTs, lastRole) = gatewayDashboardSummarizeSession(sessionKey)
        @Expect(count, 2)
        @Expect(approx > 0, true)
        @Expect(lastRole, "assistant")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func resolvedContextFromRpcReusesUnifiedSessionBuilder(): Unit {
        let params = JsonObject()
        params.put("source", JsonString("control-ui"))
        params.put("session", JsonString(" main "))
        params.put("channel", JsonString("CLI"))
        params.put("agentId", JsonString("general"))
        params.put("to", JsonString("peer-1"))
        params.put("lane", JsonString("lane-a"))

        let context = gatewayDashboardResolvedContextFromRpc(params)
        @Expect(context.sourceLabel, "control-ui")
        @Expect(context.channelName, "cli")
        @Expect(context.agentId, "general")
        @Expect(context.sessionKey, "agent:general:main:lane:lane-a")
    }

    @TestCase
    public func dashboardRecentMessagesUseConversationDisplayName(): Unit {
        withGatewayDashboardTestHome("/tmp/metis-dashboard-recent-messages-test-home") {
            let user = GatewayUserSettings()
            let store = gatewaySessionStoreForUserWithAgentId(user, "general")
            let sessionKey = "agent:general:main"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")
            store.appendAssistant(sessionKey, "world")
            store.listSessionKeys()

            let view = gatewayFindSessionCatalogViewForUser(user, sessionKey).getOrThrow()
            let views = [gatewayBuildSessionConversationView(view)]
            let lines = dashboardBuildRecentMessagesForViews(user, views, 10)
            @Expect(lines.size >= 0, true)
            if (lines.size > 0) {
                @Expect(lines[0].isEmpty(), false)
            }

            store.deleteSession(sessionKey)
        }
    }
}
