package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.gateway.core.{gatewaySessionStoreForSessionKey, gatewaySessionStoreForUserWithAgentId}

import magic.jsonable.*
import std.env.{getVariable, setVariable}
import std.collection.*
import std.fs.{Directory, File, Path, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func sessionRowExists(rows: JsonArray, sessionKey: String, agentId: String): Bool {
    for (i in 0..rows.size()) {
        try {
            let obj = rows[i].asObject()
            let key = obj.get("key").getOrThrow().asString().getValue()
            let agent = obj.get("agentId").getOrThrow().asString().getValue()
            if (key == sessionKey && agent == agentId) {
                return true
            }
        } catch (_: Exception) {
            ()
        }
    }
    false
}

private func sessionRowHasProjection(rows: JsonArray, sessionKey: String): Bool {
    for (i in 0..rows.size()) {
        try {
            let obj = rows[i].asObject()
            let key = obj.get("key").getOrThrow().asString().getValue()
            if (key != sessionKey) {
                continue
            }
            let displayName = obj.get("displayName").getOrThrow().asString().getValue()
            let channel = obj.get("channel").getOrThrow().asString().getValue()
            let chatType = obj.get("chatType").getOrThrow().asString().getValue()
            let sessionId = obj.get("sessionId").getOrThrow().asString().getValue()
            let origin = obj.get("origin").getOrThrow().asObject()
            if (!displayName.isEmpty() && !channel.isEmpty() && !chatType.isEmpty() &&
                !sessionId.isEmpty() && origin.get("provider").isSome()) {
                return true
            }
        } catch (_: Exception) {
            ()
        }
    }
    false
}

private func concatLines(lines: Array<String>): String {
    var out = ""
    for (i in 0..lines.size) {
        if (i > 0) {
            out += "\n"
        }
        out += lines[i]
    }
    out
}

private func previewEntryFor(rows: JsonArray, key: String): JsonObject {
    for (i in 0..rows.size()) {
        let row = rows[i].asObject()
        if (row.get("key").getOrThrow().asString().getValue() == key) {
            return row
        }
    }
    JsonObject()
}

private func withGatewaySessionsTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-sessions-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}

@Test
public class GatewayServerMethodsSessionsTest {
    @TestCase
    public func sessionsListAggregatesAcrossAgentStores(): Unit {
        let mainStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let mainKey = "agent:main:main"
        let generalKey = "agent:general:main"
        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
        mainStore.appendUser(mainKey, "hello-main")
        generalStore.appendUser(generalKey, "hello-general")

        let response = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        let result = response.result.asObject()
        let sessions = result.get("sessions").getOrThrow().asArray()
        @Expect(sessionRowExists(sessions, mainKey, "main"), true)
        @Expect(sessionRowExists(sessions, generalKey, "general"), true)
        @Expect(sessionRowHasProjection(sessions, mainKey), true)
        @Expect(sessionRowHasProjection(sessions, generalKey), true)

        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
    }

    @TestCase
    public func sessionsPathReturnsAllKnownRoots(): Unit {
        let mainStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let response = handleGatewaySessionsFamily("sessions.path").getOrThrow()
        let result = response.result.asObject()
        let roots = result.get("roots").getOrThrow().asArray()
        let mainRoot = JsonString(mainStore.sessionsRoot().toString()).toJsonString()
        let generalRoot = JsonString(generalStore.sessionsRoot().toString()).toJsonString()
        @Expect(roots.toJsonString().contains(mainRoot), true)
        @Expect(roots.toJsonString().contains(generalRoot), true)
    }

    @TestCase
    public func sessionsListExposesDefaultModelSummary(): Unit {
        let response = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        @Expect(response.ok, true)
        let defaults = response.result.asObject().get("defaults").getOrThrow().asObject()
        @Expect(defaults.get("model").isSome(), true)
        @Expect(defaults.get("modelProvider").isSome(), true)
        @Expect(defaults.get("contextTokens").isSome(), true)
    }

    @TestCase
    public func sessionsSubscribeAndUnsubscribePreferTargetClientIdParam(): Unit {
        let subscribeParams = JsonObject()
        subscribeParams.put("clientId", JsonString("phase14-session-subscriber"))
        let subscribeReq = GatewayRpcRequest("sessions.subscribe", params: subscribeParams, clientId: "metis-cli")
        let subscribeResponse = handleGatewaySessionsFamily("sessions.subscribe", request: Some(subscribeReq)).getOrThrow()
        @Expect(subscribeResponse.ok, true)
        let subscribeResult = subscribeResponse.result.asObject()
        @Expect(subscribeResult.get("subscribed").getOrThrow().asBool().getValue(), true)
        let kinds = subscribeResult.get("kinds").getOrThrow().asArray()
        @Expect(kinds.size() >= 4, true)
        @Expect(kinds.toJsonString().contains("\"sessions.changed\""), true)

        let unsubscribeParams = JsonObject()
        unsubscribeParams.put("clientId", JsonString("phase14-session-subscriber"))
        let unsubscribeReq = GatewayRpcRequest("sessions.unsubscribe", params: unsubscribeParams, clientId: "metis-cli")
        let unsubscribeResponse = handleGatewaySessionsFamily("sessions.unsubscribe", request: Some(unsubscribeReq)).getOrThrow()
        @Expect(unsubscribeResponse.ok, true)
        let unsubscribeResult = unsubscribeResponse.result.asObject()
        @Expect(unsubscribeResult.get("subscribed").getOrThrow().asBool().getValue(), false)
        @Expect(unsubscribeResult.get("kinds").getOrThrow().asArray().size(), 0)
    }

    @TestCase
    public func sessionsPreviewReturnsTranscriptPreviewForMainAlias(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:main"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "first answer")
        store.appendTranscriptEntry(sessionKey, "tool", "call weather")
        store.appendAssistant(sessionKey, "final answer")

        let params = JsonObject()
        let keys = JsonArray([])
        keys.add(JsonString("main"))
        params.put("keys", keys)
        params.put("limit", 3.toJsonValue())
        params.put("maxChars", 120.toJsonValue())
        let request = GatewayRpcRequest("sessions.preview", params: params, clientId: "metis-cli")
        let response = handleGatewaySessionsFamily("sessions.preview", request: Some(request)).getOrThrow()
        @Expect(response.ok, true)
        let previews = response.result.asObject().get("previews").getOrThrow().asArray()
        let entry = previewEntryFor(previews, "main")
        @Expect(entry.get("status").getOrThrow().asString().getValue(), "ok")
        let items = entry.get("items").getOrThrow().asArray()
        @Expect(items.size(), 3)
        @Expect(items[0].asObject().get("role").getOrThrow().asString().getValue(), "assistant")
        @Expect(items[1].asObject().get("role").getOrThrow().asString().getValue(), "tool")
        @Expect(items[1].asObject().get("text").getOrThrow().asString().getValue().contains("call weather"), true)
        @Expect(items[2].asObject().get("text").getOrThrow().asString().getValue(), "final answer")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsPreviewReturnsMissingForUnknownKey(): Unit {
        let params = JsonObject()
        let keys = JsonArray([])
        keys.add(JsonString("missing-session"))
        params.put("keys", keys)
        let request = GatewayRpcRequest("sessions.preview", params: params, clientId: "metis-cli")
        let response = handleGatewaySessionsFamily("sessions.preview", request: Some(request)).getOrThrow()
        @Expect(response.ok, true)
        let previews = response.result.asObject().get("previews").getOrThrow().asArray()
        let entry = previewEntryFor(previews, "missing-session")
        @Expect(entry.get("status").getOrThrow().asString().getValue(), "missing")
        @Expect(entry.get("items").getOrThrow().asArray().size(), 0)
    }

    @TestCase
    public func sessionsGetReturnsTranscriptMessagesForMainAlias(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:main"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")
        store.appendAssistant(sessionKey, "world")

        let params = JsonObject()
        params.put("key", JsonString("main"))
        params.put("limit", 10.toJsonValue())
        let request = GatewayRpcRequest("sessions.get", params: params, clientId: "metis-cli")
        let response = handleGatewaySessionsFamily("sessions.get", request: Some(request)).getOrThrow()
        @Expect(response.ok, true)
        let messages = response.result.asObject().get("messages").getOrThrow().asArray()
        @Expect(messages.size(), 2)
        @Expect(messages[0].asObject().get("role").getOrThrow().asString().getValue(), "user")
        @Expect(messages[0].asObject().get("content").getOrThrow().asArray()[0].asObject().get("text").getOrThrow().asString().getValue(), "hello")
        @Expect(messages[1].asObject().get("role").getOrThrow().asString().getValue(), "assistant")
        @Expect(messages[1].asObject().get("content").getOrThrow().asArray()[0].asObject().get("text").getOrThrow().asString().getValue(), "world")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsGetReplaysTranscriptMeta(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:get-message-meta-test"
        store.deleteSession(sessionKey)
        let transcriptLines = [
            "{\"kind\":\"meta\",\"v\":\"1\",\"sessionKey\":\"${sessionKey}\"}",
            "{\"id\":\"msg-1\",\"role\":\"user\",\"text\":\"hello\",\"ts\":\"1000\"}",
            "{\"id\":\"msg-2\",\"role\":\"assistant\",\"text\":\"world\",\"ts\":\"1001\"}"
        ]
        File.writeTo(store.transcriptPath(sessionKey), concatLines(transcriptLines).toArray())
        store.listSessionKeys()

        let params = JsonObject()
        params.put("key", JsonString(sessionKey))
        let request = GatewayRpcRequest("sessions.get", params: params, clientId: "metis-cli")
        let response = handleGatewaySessionsFamily("sessions.get", request: Some(request)).getOrThrow()
        @Expect(response.ok, true)
        let messages = response.result.asObject().get("messages").getOrThrow().asArray()
        let firstMeta = messages[0].asObject().get("__metis").getOrThrow().asObject()
        let secondMeta = messages[1].asObject().get("__metis").getOrThrow().asObject()
        @Expect(firstMeta.get("id").getOrThrow().asString().getValue(), "msg-1")
        @Expect(firstMeta.get("seq").getOrThrow().toJsonString(), "1")
        @Expect(secondMeta.get("id").getOrThrow().asString().getValue(), "msg-2")
        @Expect(secondMeta.get("seq").getOrThrow().toJsonString(), "2")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsGetReplaysCompactionAsSyntheticSystemMessage(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:get-compaction-meta-test"
        store.deleteSession(sessionKey)
        let transcriptLines = [
            "{\"kind\":\"meta\",\"v\":\"1\",\"sessionKey\":\"${sessionKey}\"}",
            "{\"id\":\"cmp-1\",\"type\":\"compaction\",\"timestamp\":\"2026-04-17T03:00:00Z\"}"
        ]
        File.writeTo(store.transcriptPath(sessionKey), concatLines(transcriptLines).toArray())
        store.listSessionKeys()

        let params = JsonObject()
        params.put("key", JsonString(sessionKey))
        let request = GatewayRpcRequest("sessions.get", params: params, clientId: "metis-cli")
        let response = handleGatewaySessionsFamily("sessions.get", request: Some(request)).getOrThrow()
        @Expect(response.ok, true)
        let messages = response.result.asObject().get("messages").getOrThrow().asArray()
        @Expect(messages.size(), 1)
        let message = messages[0].asObject()
        @Expect(message.get("role").getOrThrow().asString().getValue(), "system")
        @Expect(message.get("content").getOrThrow().asArray()[0].asObject().get("text").getOrThrow().asString().getValue(), "Compaction")
        let meta = message.get("__metis").getOrThrow().asObject()
        @Expect(meta.get("kind").getOrThrow().asString().getValue(), "compaction")
        @Expect(meta.get("id").getOrThrow().asString().getValue(), "cmp-1")
        @Expect(meta.get("seq").getOrThrow().toJsonString(), "1")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsGetReturnsEmptyMessagesForUnknownKey(): Unit {
        let params = JsonObject()
        params.put("key", JsonString("missing-session"))
        let request = GatewayRpcRequest("sessions.get", params: params, clientId: "metis-cli")
        let response = handleGatewaySessionsFamily("sessions.get", request: Some(request)).getOrThrow()
        @Expect(response.ok, true)
        @Expect(response.result.asObject().get("messages").getOrThrow().asArray().size(), 0)
    }

    @TestCase
    public func sessionsPatchReturnsEntryAndSessionsListReflectsMetadata(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:main"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let patchParams = JsonObject()
        patchParams.put("key", JsonString("main"))
        patchParams.put("verboseLevel", JsonString("on"))
        patchParams.put("responseUsage", JsonString("full"))
        patchParams.put("fastMode", true.toJsonValue())
        patchParams.put("sendPolicy", JsonString("deny"))
        let patchRequest = GatewayRpcRequest("sessions.patch", params: patchParams, clientId: "metis-cli")
        let patchResponse = handleGatewaySessionsFamily("sessions.patch", request: Some(patchRequest)).getOrThrow()
        @Expect(patchResponse.ok, true)
        let patchResult = patchResponse.result.asObject()
        @Expect(patchResult.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(patchResult.get("key").getOrThrow().asString().getValue(), "agent:main:main")
        let entry = patchResult.get("entry").getOrThrow().asObject()
        @Expect(entry.get("verboseLevel").getOrThrow().asString().getValue(), "on")
        @Expect(entry.get("responseUsage").getOrThrow().asString().getValue(), "full")
        @Expect(entry.get("fastMode").getOrThrow().asBool().getValue(), true)
        @Expect(entry.get("sendPolicy").getOrThrow().asString().getValue(), "deny")

        let listResponse = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        let sessions = listResponse.result.asObject().get("sessions").getOrThrow().asArray()
        let row = previewEntryFor(sessions, "agent:main:main")
        @Expect(row.get("verboseLevel").getOrThrow().asString().getValue(), "on")
        @Expect(row.get("responseUsage").getOrThrow().asString().getValue(), "full")
        @Expect(row.get("fastMode").getOrThrow().asBool().getValue(), true)
        @Expect(row.get("sendPolicy").getOrThrow().asString().getValue(), "deny")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsListReplaysUsageRouteAndChildMetadata(): Unit {
        withGatewaySessionsTestHome {
            let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
            let sessionKey = "agent:main:list-metadata-test"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "hello")

            let root = JsonObject()
            let entry = JsonObject()
            entry.put("sessionKey", JsonString(sessionKey))
            entry.put("updatedAt", 123.toJsonValue())
            entry.put("sessionFile", JsonString("agent_main_list-metadata-test.jsonl"))
            entry.put("sessionId", JsonString("agent_main_list-metadata-test"))
            entry.put("lastChannel", JsonString("telegram"))
            entry.put("lastTo", JsonString("-100123"))
            entry.put("lastAccountId", JsonString("acct-1"))
            entry.put("lastThreadId", 42.toJsonValue())
            entry.put("modelProvider", JsonString("anthropic"))
            entry.put("model", JsonString("claude-sonnet-4-6"))
            entry.put("contextTokens", 1048576.toJsonValue())
            entry.put("totalTokens", 3000.toJsonValue())
            entry.put("totalTokensFresh", true.toJsonValue())
            entry.put("estimatedCostUsd", 0.0042.toJsonValue())
            entry.put("parentSessionKey", JsonString("agent:main:main"))
            let children = JsonArray([])
            children.add(JsonString("agent:main:dashboard:child"))
            entry.put("childSessions", children)
            root.put(sessionKey, entry)
            File.writeTo(store.sessionsRoot().join("sessions.json"), root.toJsonString().toArray())

            let listResponse = handleGatewaySessionsFamily("sessions.list").getOrThrow()
            @Expect(listResponse.ok, true)
            let sessions = listResponse.result.asObject().get("sessions").getOrThrow().asArray()
            let row = previewEntryFor(sessions, sessionKey)
            @Expect(row.get("lastChannel").getOrThrow().asString().getValue(), "telegram")
            @Expect(row.get("lastTo").getOrThrow().asString().getValue(), "-100123")
            @Expect(row.get("lastAccountId").getOrThrow().asString().getValue(), "acct-1")
            @Expect(row.get("lastThreadId").getOrThrow().toJsonString(), "42")
            @Expect(row.get("modelProvider").getOrThrow().asString().getValue(), "anthropic")
            @Expect(row.get("model").getOrThrow().asString().getValue(), "claude-sonnet-4-6")
            @Expect(row.get("contextTokens").getOrThrow().toJsonString(), "1048576")
            @Expect(row.get("totalTokens").getOrThrow().toJsonString(), "3000")
            @Expect(row.get("totalTokensFresh").getOrThrow().asBool().getValue(), true)
            @Expect(row.get("estimatedCostUsd").getOrThrow().toJsonString().contains("0.0042"), true)
            @Expect(row.get("parentSessionKey").getOrThrow().asString().getValue(), "agent:main:main")
            @Expect(row.get("childSessions").getOrThrow().asArray().size(), 1)

            store.deleteSession(sessionKey)
        }
    }

    @TestCase
    public func sessionsListFallsBackToTranscriptUsageAndModelMetadata(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:list-fallback-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let root = JsonObject()
        let entry = JsonObject()
        entry.put("sessionKey", JsonString(sessionKey))
        entry.put("updatedAt", 123.toJsonValue())
        entry.put("sessionFile", JsonString("agent_main_list-fallback-test.jsonl"))
        entry.put("sessionId", JsonString("agent_main_list-fallback-test"))
        entry.put("modelProvider", JsonString("anthropic"))
        entry.put("model", JsonString("claude-sonnet-4-6"))
        entry.put("contextTokens", 0.toJsonValue())
        entry.put("totalTokens", 0.toJsonValue())
        entry.put("totalTokensFresh", false.toJsonValue())
        entry.put("estimatedCostUsd", 0.0.toJsonValue())
        root.put(sessionKey, entry)
        File.writeTo(store.sessionsRoot().join("sessions.json"), root.toJsonString().toArray())

        let transcriptLines = [
            "{\"kind\":\"meta\",\"v\":\"1\",\"sessionKey\":\"${sessionKey}\"}",
            "{\"message\":{\"role\":\"assistant\",\"provider\":\"anthropic\",\"model\":\"claude-sonnet-4-6\",\"usage\":{\"input\":2000,\"output\":500,\"cacheRead\":1000,\"cost\":{\"total\":0.0042}}}}",
            "{\"message\":{\"role\":\"assistant\",\"provider\":\"metis\",\"model\":\"delivery-mirror\",\"usage\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}}}"
        ]
        File.writeTo(store.transcriptPath(sessionKey), concatLines(transcriptLines).toArray())

        let listResponse = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        @Expect(listResponse.ok, true)
        let sessions = listResponse.result.asObject().get("sessions").getOrThrow().asArray()
        let row = previewEntryFor(sessions, sessionKey)
        @Expect(row.get("modelProvider").getOrThrow().asString().getValue(), "anthropic")
        @Expect(row.get("model").getOrThrow().asString().getValue(), "claude-sonnet-4-6")
        @Expect(row.get("totalTokens").getOrThrow().toJsonString(), "3500")
        @Expect(row.get("totalTokensFresh").getOrThrow().asBool().getValue(), true)
        @Expect(row.get("estimatedCostUsd").getOrThrow().toJsonString().contains("0.0042"), true)
        @Expect(row.get("contextTokens").getOrThrow().toJsonString(), "131072")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsListProjectsDeliveryContextFromDeliverySnapshot(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:list-delivery-context-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let root = JsonObject()
        let entry = JsonObject()
        entry.put("sessionKey", JsonString(sessionKey))
        entry.put("updatedAt", 123.toJsonValue())
        entry.put("sessionFile", JsonString("agent_main_list-delivery-context-test.jsonl"))
        entry.put("sessionId", JsonString("agent_main_list-delivery-context-test"))
        let delivery = JsonObject()
        delivery.put("channel", JsonString("whatsapp"))
        delivery.put("peer", JsonString("+1555"))
        delivery.put("replyTo", JsonString("+1555"))
        delivery.put("conversationId", JsonString("+1555"))
        delivery.put("threadId", JsonString("1737500000.123456"))
        delivery.put("accountId", JsonString("work"))
        delivery.put("deliverable", true.toJsonValue())
        delivery.put("mode", JsonString("binding-snapshot"))
        entry.put("delivery", delivery)
        root.put(sessionKey, entry)
        File.writeTo(store.sessionsRoot().join("sessions.json"), root.toJsonString().toArray())

        let listResponse = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        @Expect(listResponse.ok, true)
        let sessions = listResponse.result.asObject().get("sessions").getOrThrow().asArray()
        let row = previewEntryFor(sessions, sessionKey)
        let deliveryContext = row.get("deliveryContext").getOrThrow().asObject()
        @Expect(deliveryContext.get("channel").getOrThrow().asString().getValue(), "agent")
        @Expect(deliveryContext.get("to").getOrThrow().asString().getValue(), "list-delivery-context-test")
        @Expect(row.get("lastChannel").getOrThrow().asString().getValue(), "agent")
        @Expect(row.get("lastTo").getOrThrow().asString().getValue(), "list-delivery-context-test")
        @Expect(row.get("kind").getOrThrow().asString().getValue(), "direct")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsListProjectsTelegramThreadBindingFromSpawnMetadataTranscript(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:telegram-thread-bound-test"
        store.deleteSession(sessionKey)
        let transcriptLines = [
            "{\"kind\":\"meta\",\"v\":\"1\",\"sessionKey\":\"${sessionKey}\"}",
            "{\"role\":\"system\",\"text\":\"sessions_spawn metadata: runtime=subagent, streamTo=telegram:group:-1001234567890:topic:42, thread=true\"}"
        ]
        File.writeTo(store.transcriptPath(sessionKey), concatLines(transcriptLines).toArray())

        let listResponse = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        @Expect(listResponse.ok, true)
        let sessions = listResponse.result.asObject().get("sessions").getOrThrow().asArray()
        let row = previewEntryFor(sessions, sessionKey)
        @Expect(row.get("streamTo").getOrThrow().asString().getValue(), "telegram:group:-1001234567890:topic:42")
        @Expect(row.get("thread").getOrThrow().asBool().getValue(), true)
        @Expect(row.get("lastChannel").getOrThrow().asString().getValue(), "agent")
        @Expect(row.get("lastTo").getOrThrow().asString().getValue(), "telegram-thread-bound-test")
        let deliveryContext = row.get("deliveryContext").getOrThrow().asObject()
        @Expect(deliveryContext.get("channel").getOrThrow().asString().getValue(), "agent")
        @Expect(deliveryContext.get("to").getOrThrow().asString().getValue(), "telegram-thread-bound-test")
        if (row.get("threadBinding").isSome()) {
            let threadBinding = row.get("threadBinding").getOrThrow().asObject()
            @Expect(threadBinding.get("enabled").getOrThrow().asBool().getValue(), true)
            @Expect(threadBinding.get("channel").getOrThrow().asString().getValue(), "telegram")
            @Expect(threadBinding.get("threadId").getOrThrow().asString().getValue(), "42")
        }

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsListProjectsDerivedTitleAndLastMessagePreviewFromTranscript(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:list-derived-title-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "please summarize this very important issue")
        store.appendAssistant(sessionKey, "working on it now")

        let listResponse = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        @Expect(listResponse.ok, true)
        let sessions = listResponse.result.asObject().get("sessions").getOrThrow().asArray()
        let row = previewEntryFor(sessions, sessionKey)
        @Expect(row.get("derivedTitle").getOrThrow().asString().getValue(), "list-derived-title-test")
        @Expect(row.get("lastMessagePreview").getOrThrow().asString().getValue(), "working on it now")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsPatchReturnsErrorForUnknownSession(): Unit {
        let patchParams = JsonObject()
        patchParams.put("key", JsonString("missing-session"))
        patchParams.put("verboseLevel", JsonString("on"))
        let patchRequest = GatewayRpcRequest("sessions.patch", params: patchParams, clientId: "metis-cli")
        let patchResponse = handleGatewaySessionsFamily("sessions.patch", request: Some(patchRequest)).getOrThrow()
        @Expect(patchResponse.ok, false)
    }

    @TestCase
    public func sessionsDeleteRejectsMainSession(): Unit {
        let deleteParams = JsonObject()
        deleteParams.put("key", JsonString("main"))
        let deleteResponse = handleGatewaySessionsFamily("sessions.delete", request: Some(GatewayRpcRequest("sessions.delete", params: deleteParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(deleteResponse.ok, false)
    }

    @TestCase
    public func sessionsDeleteArchivesTranscriptAndRemovesSession(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:delete-me"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello delete")

        let deleteParams = JsonObject()
        deleteParams.put("key", JsonString(sessionKey))
        let deleteResponse = handleGatewaySessionsFamily("sessions.delete", request: Some(GatewayRpcRequest("sessions.delete", params: deleteParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(deleteResponse.ok, true)
        let deleteResult = deleteResponse.result.asObject()
        @Expect(deleteResult.get("deleted").getOrThrow().asBool().getValue(), true)
        let archived = deleteResult.get("archived").getOrThrow().asArray()
        @Expect(archived.size(), 1)
        @Expect(archived[0].asString().getValue().contains(".deleted."), true)
        @Expect(store.readTranscriptRaw(sessionKey).isNone(), true)

        let listResponse = handleGatewaySessionsFamily("sessions.list").getOrThrow()
        let sessions = listResponse.result.asObject().get("sessions").getOrThrow().asArray()
        @Expect(sessionRowExists(sessions, sessionKey, "main"), false)
    }

    @TestCase
    public func sessionsDeleteReturnsFalseForUnknownSession(): Unit {
        let sessionKey = "agent:main:missing-delete"
        let deleteParams = JsonObject()
        deleteParams.put("key", JsonString(sessionKey))
        let deleteResponse = handleGatewaySessionsFamily("sessions.delete", request: Some(GatewayRpcRequest("sessions.delete", params: deleteParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(deleteResponse.ok, true)
        @Expect(deleteResponse.result.asObject().get("deleted").getOrThrow().asBool().getValue(), false)
        @Expect(deleteResponse.result.asObject().get("archived").getOrThrow().asArray().size(), 0)
    }

    @TestCase
    public func sessionsResetArchivesTranscriptAndPreservesSessionMetadata(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:main"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let patchParams = JsonObject()
        patchParams.put("key", JsonString("main"))
        patchParams.put("sendPolicy", JsonString("deny"))
        patchParams.put("spawnedBy", JsonString("agent:main:parent"))
        let _ = handleGatewaySessionsFamily("sessions.patch", request: Some(GatewayRpcRequest("sessions.patch", params: patchParams, clientId: "metis-cli"))).getOrThrow()

        let beforeRaw = store.readTranscriptRaw(sessionKey).getOrThrow()
        let beforeLines = gatewayControlUiParseJsonObjectsFromRaw(beforeRaw)
        @Expect(beforeLines.size >= 2, true)

        let resetParams = JsonObject()
        resetParams.put("key", JsonString("main"))
        let resetResponse = handleGatewaySessionsFamily("sessions.reset", request: Some(GatewayRpcRequest("sessions.reset", params: resetParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(resetResponse.ok, true)
        let resetResult = resetResponse.result.asObject()
        @Expect(resetResult.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(resetResult.get("key").getOrThrow().asString().getValue(), "agent:main:main")
        let entry = resetResult.get("entry").getOrThrow().asObject()
        @Expect(entry.get("sendPolicy").getOrThrow().asString().getValue(), "deny")
        @Expect(entry.get("spawnedBy").getOrThrow().asString().getValue(), "agent:main:parent")

        let afterRaw = store.readTranscriptRaw(sessionKey).getOrThrow()
        let afterLines = gatewayControlUiParseJsonObjectsFromRaw(afterRaw)
        @Expect(afterLines.size >= 1, true)
        @Expect(
            afterLines[0].get("kind").getOrThrow().asString().getValue(),
            "meta"
        )
        @Expect(afterRaw.contains("hello"), false)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsResetCreatesEmptyTranscriptForMissingSession(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:missing-reset"
        store.deleteSession(sessionKey)

        let resetParams = JsonObject()
        resetParams.put("key", JsonString(sessionKey))
        let resetResponse = handleGatewaySessionsFamily("sessions.reset", request: Some(GatewayRpcRequest("sessions.reset", params: resetParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(resetResponse.ok, true)
        let raw = store.readTranscriptRaw(sessionKey).getOrThrow()
        let lines = gatewayControlUiParseJsonObjectsFromRaw(raw)
        @Expect(lines.size >= 1, true)
        @Expect(lines[0].get("kind").getOrThrow().asString().getValue(), "meta")

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsCompactArchivesTranscriptAndKeepsTailLines(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let sessionKey = "agent:main:main"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "one")
        store.appendAssistant(sessionKey, "two")
        store.appendUser(sessionKey, "three")
        store.appendAssistant(sessionKey, "four")

        let compactParams = JsonObject()
        compactParams.put("key", JsonString("main"))
        compactParams.put("maxLines", 3.toJsonValue())
        let compactResponse = handleGatewaySessionsFamily("sessions.compact", request: Some(GatewayRpcRequest("sessions.compact", params: compactParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(compactResponse.ok, true)
        let compactResult = compactResponse.result.asObject()
        @Expect(compactResult.get("compacted").getOrThrow().asBool().getValue(), true)
        @Expect(compactResult.get("archived").getOrThrow().asString().getValue().contains(".jsonl.bak."), true)

        let raw = store.readTranscriptRaw(sessionKey).getOrThrow()
        let lines = raw.split("\n")
        let kept = ArrayList<String>()
        for (line in lines) {
            if (!line.trimAscii().isEmpty()) {
                kept.add(line)
            }
        }
        @Expect(kept.size, 3)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsCompactReturnsFalseWhenTranscriptMissing(): Unit {
        let sessionKey = "agent:main:missing-compact"
        let compactParams = JsonObject()
        compactParams.put("key", JsonString(sessionKey))
        let compactResponse = handleGatewaySessionsFamily("sessions.compact", request: Some(GatewayRpcRequest("sessions.compact", params: compactParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(compactResponse.ok, true)
        let compactResult = compactResponse.result.asObject()
        @Expect(compactResult.get("compacted").getOrThrow().asBool().getValue(), false)
    }

    @TestCase
    public func sessionsMessagesSubscribeAndUnsubscribeResolveKey(): Unit {
        let subscribeParams = JsonObject()
        subscribeParams.put("key", JsonString("main"))
        let subscribeReq = GatewayRpcRequest("sessions.messages.subscribe", params: subscribeParams, clientId: "phase14-message-subscriber")
        let subscribeResponse = handleGatewaySessionsFamily("sessions.messages.subscribe", request: Some(subscribeReq)).getOrThrow()
        @Expect(subscribeResponse.ok, true)
        let subscribeResult = subscribeResponse.result.asObject()
        @Expect(subscribeResult.get("subscribed").getOrThrow().asBool().getValue(), true)
        @Expect(subscribeResult.get("key").getOrThrow().asString().getValue(), "agent:main:main")

        let unsubscribeParams = JsonObject()
        unsubscribeParams.put("key", JsonString("main"))
        let unsubscribeReq = GatewayRpcRequest("sessions.messages.unsubscribe", params: unsubscribeParams, clientId: "phase14-message-subscriber")
        let unsubscribeResponse = handleGatewaySessionsFamily("sessions.messages.unsubscribe", request: Some(unsubscribeReq)).getOrThrow()
        @Expect(unsubscribeResponse.ok, true)
        let unsubscribeResult = unsubscribeResponse.result.asObject()
        @Expect(unsubscribeResult.get("subscribed").getOrThrow().asBool().getValue(), false)
        @Expect(unsubscribeResult.get("key").getOrThrow().asString().getValue(), "agent:main:main")
    }

    @TestCase
    public func sessionsCliListLinesShowAgentScopedEntries(): Unit {
        let mainStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let mainKey = "agent:main:cli-list"
        let generalKey = "agent:general:cli-list"
        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
        mainStore.appendUser(mainKey, "hello-main")
        generalStore.appendUser(generalKey, "hello-general")

        let lines = concatLines(gatewaySessionsListLinesForUser(GatewayUserSettings()))
        @Expect(lines.contains("[main] ${mainKey}"), true)
        @Expect(lines.contains("[general] ${generalKey}"), true)
        @Expect(lines.contains("channel=agent"), true)
        @Expect(lines.contains("kind=direct"), true)
        @Expect(lines.contains("sessionId="), true)

        mainStore.deleteSession(mainKey)
        generalStore.deleteSession(generalKey)
    }

    @TestCase
    public func sessionsCliShowDefaultsToBoundedPreview(): Unit {
        withGatewaySessionsTestHome({ =>
            let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "main")
            let sessionKey = "agent:main:cli-show-preview"
            store.deleteSession(sessionKey)
            store.appendUser(sessionKey, "one")
            store.appendUser(sessionKey, "two")

            let lines = concatLines(gatewaySessionsShowLinesForUser(GatewayUserSettings(), sessionKey, 1))
            @Expect(lines.contains("Transcript preview: ${sessionKey}"), true)
            @Expect(lines.contains("Showing 1 of"), true)
            @Expect(lines.contains("truncated"), true)
            @Expect(lines.contains("gateway sessions export ${sessionKey}"), true)

            store.deleteSession(sessionKey)
        })
    }

    @TestCase
    public func sessionsStoreForKeyFallsBackToUnifiedAgentResolution(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForSessionKey(user, "agent:general:main")
        let generalStore = gatewaySessionStoreForUserWithAgentId(user, "general")
        @Expect(store.sessionsRoot().toString(), generalStore.sessionsRoot().toString())
    }
}
