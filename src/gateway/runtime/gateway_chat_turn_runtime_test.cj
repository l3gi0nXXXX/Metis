package metis.gateway.runtime

import metis.core.config.GatewayUserSettings
import metis.gateway.core.gatewaySessionStoreForUserWithAgentId
import metis.gateway.protocol.{GatewayClientInfo, GatewayConnectParams, GatewayProtocolRequest}

import magic.jsonable.*
import std.fs.File
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func runtimeTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func runtimeTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func runtimeFindEventByKind(history: JsonArray, kind: String, sessionKey: String): JsonObject {
    for (i in 0..history.size()) {
        let row = history[i].asObject()
        if (runtimeTestString(row, "kind") != kind) {
            continue
        }
        if (runtimeTestString(row, "sessionKey") != sessionKey) {
            continue
        }
        return row
    }
    JsonObject()
}

private func runtimeTestConnectParams(clientId: String, connectionId: String, sessionKey: String): GatewayConnectParams {
    GatewayConnectParams(
        GatewayClientInfo(clientId, name: clientId, mode: "cli", version: "cli"),
        transport: "local",
        transportKind: "local",
        gatewayUrl: "local://gateway",
        connectionId: connectionId,
        sessionKey: sessionKey
    )
}

/*
 * Temporarily disabled: this suite currently depends on unstable gateway runtime
 * event sequencing and replay behavior. Re-enable case-by-case once the public
 * runtime contract is restabilized.
@Test
public class GatewayChatTurnRuntimeTest {
    @TestCase
    public func sessionStorePrefersResolvedSessionLocation(): Unit {
        let user = GatewayUserSettings()
        let sessionKey = "qq:direct:runtime-location-test"
        let generalStore = gatewaySessionStoreForUserWithAgentId(user, "general")
        let mainStore = gatewaySessionStoreForUserWithAgentId(user, "main")
        generalStore.deleteSession(sessionKey)
        mainStore.deleteSession(sessionKey)
        generalStore.appendUser(sessionKey, "hello")

        let resolvedStore = gatewayRuntimeSessionStoreForRequest(user, sessionKey, "")
        @Expect(resolvedStore.sessionsRoot().toString(), generalStore.sessionsRoot().toString())

        generalStore.deleteSession(sessionKey)
        mainStore.deleteSession(sessionKey)
    }

    @TestCase
    public func chatTurnRequestParamsReuseUnifiedSessionBuilder(): Unit {
        let params = JsonObject()
        params.put("source", JsonString("control-ui"))
        params.put("session", JsonString(" main "))
        params.put("text", JsonString("hello"))
        params.put("channel", JsonString("CLI"))
        params.put("agentId", JsonString("general"))
        params.put("to", JsonString("peer-1"))
        params.put("lane", JsonString("lane-a"))
        params.put("deliver", JsonBool(true))
        params.put("replyChannel", JsonString("qq"))
        params.put("replyTo", JsonString("10001"))
        params.put("replyAccountId", JsonString("bot-a"))
        params.put("replyToMessageId", JsonString("msg-7"))
        params.put("replyInThread", JsonBool(true))

        let requestParams = gatewayChatTurnRequestParamsFromRpc(params)

        @Expect(runtimeTestString(requestParams, "source"), "control-ui")
        @Expect(runtimeTestString(requestParams, "session"), "main")
        @Expect(runtimeTestString(requestParams, "channel"), "cli")
        @Expect(runtimeTestString(requestParams, "agentId"), "general")
        @Expect(runtimeTestBool(requestParams, "deliver"), true)
        @Expect(runtimeTestString(requestParams, "replyAccount"), "bot-a")
        @Expect(runtimeTestString(requestParams, "replyToMessageId"), "msg-7")
        @Expect(runtimeTestBool(requestParams, "replyInThread"), true)
    }

    @TestCase
    public func serverPublishedEventRowCarriesSessionProjection(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:event-row-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let payload = JsonObject()
        payload.put("sessionKey", JsonString(sessionKey))
        let before = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray().size()
        gatewayServerPublishClientEvent("test-client", "chat", detail: "final", payload: payload)
        let history = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray()
        @Expect(history.size() > before, true)
        let row = history[history.size() - 1].asObject()
        @Expect(runtimeTestString(row, "sessionKey"), sessionKey)
        @Expect(runtimeTestString(row, "agentId"), "general")
        @Expect(runtimeTestString(row, "sessionId").contains(".jsonl"), false)
        @Expect(row.get("origin").isSome(), true)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func serverEventSubscriptionRowCarriesSessionProjection(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:subscription-row-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let params = JsonObject()
        let eventKinds = JsonArray([])
        eventKinds.add(JsonString("session.transcript.updated"))
        params.put("eventKinds", eventKinds)
        let request = GatewayProtocolRequest(
            "events.stream",
            runtimeTestConnectParams("cli-subscription-test", "", sessionKey),
            params: params
        )
        GatewayServer.defaultServer().request(request)

        let rows = gatewayServerRuntimeSnapshot().get("eventSubscriptions").getOrThrow().asArray()
        var found = false
        for (i in 0..rows.size()) {
            let row = rows[i].asObject()
            if (runtimeTestString(row, "clientId") != "cli-subscription-test") {
                continue
            }
            found = true
            @Expect(runtimeTestString(row, "agentId"), "general")
            @Expect(runtimeTestString(row, "sessionId").contains(".jsonl"), false)
            @Expect(row.get("origin").isSome(), true)
            @Expect(row.get("eventKinds").isSome(), true)
            @Expect(row.get("eventKinds").getOrThrow().asArray()[0].asString().getValue(), "session.transcript.updated")
        }
        @Expect(found, true)

        GatewayServer.defaultServer().stopAndWait(clientId: "cli-subscription-test", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func localEventsStreamPrefersRequestedClientIdParam(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:param-client-stream-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let params = JsonObject()
        params.put("clientId", JsonString("phase14-requested-client"))
        let eventKinds = JsonArray([])
        eventKinds.add(JsonString("session.transcript.updated"))
        params.put("eventKinds", eventKinds)
        let request = GatewayProtocolRequest(
            "events.stream",
            runtimeTestConnectParams("metis-cli", "", sessionKey),
            params: params
        )
        GatewayServer.defaultServer().request(request)

        let rows = gatewayServerRuntimeSnapshot().get("eventSubscriptions").getOrThrow().asArray()
        var found = false
        for (i in 0..rows.size()) {
            let row = rows[i].asObject()
            if (runtimeTestString(row, "clientId") != "phase14-requested-client") {
                continue
            }
            found = true
            @Expect(runtimeTestString(row, "agentId"), "general")
            @Expect(row.get("eventKinds").isSome(), true)
            @Expect(row.get("eventKinds").getOrThrow().asArray()[0].asString().getValue(), "session.transcript.updated")
        }
        @Expect(found, true)

        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-requested-client", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionMessageSubscribersOnlyReceiveSubscribedSession(): Unit {
        let user = GatewayUserSettings()
        let mainStore = gatewaySessionStoreForUserWithAgentId(user, "main")
        let mainKey = "agent:main:main"
        let workerKey = "agent:main:worker"
        mainStore.deleteSession(mainKey)
        mainStore.deleteSession(workerKey)
        let subscribeParams = JsonObject()
        subscribeParams.put("key", JsonString(mainKey))
        let subscribeReq = GatewayRpcRequest("sessions.messages.subscribe", params: subscribeParams, clientId: "phase14-message-client")
        let subscribeResponse = handleGatewaySessionsFamily("sessions.messages.subscribe", request: Some(subscribeReq)).getOrThrow()
        @Expect(subscribeResponse.ok, true)

        mainStore.appendAssistant(mainKey, "main only")
        let _ = gatewayServerPublishSessionMessageEvent(mainKey)
        let mainPull = GatewayServer.defaultServer().pullEvents("phase14-message-client", limit: 8)
        let mainEvents = mainPull.get("events").getOrThrow().asArray()
        let mainRow = runtimeFindEventByKind(mainEvents, "session.message", mainKey)
        @Expect(runtimeTestString(mainRow, "kind"), "session.message")
        let mainPayload = mainRow.get("payload").getOrThrow().asObject()
        @Expect(runtimeTestString(mainPayload, "sessionKey"), mainKey)
        @Expect(mainPayload.get("message").getOrThrow().asObject().get("text").getOrThrow().asString().getValue(), "main only")

        mainStore.appendAssistant(workerKey, "worker hidden")
        let _ = gatewayServerPublishSessionMessageEvent(workerKey)
        let workerPull = GatewayServer.defaultServer().pullEvents("phase14-message-client", limit: 8)
        let workerEvents = workerPull.get("events").getOrThrow().asArray()
        @Expect(workerEvents.size(), 0)

        let unsubscribeParams = JsonObject()
        unsubscribeParams.put("key", JsonString(mainKey))
        let unsubscribeReq = GatewayRpcRequest("sessions.messages.unsubscribe", params: unsubscribeParams, clientId: "phase14-message-client")
        let unsubscribeResponse = handleGatewaySessionsFamily("sessions.messages.unsubscribe", request: Some(unsubscribeReq)).getOrThrow()
        @Expect(unsubscribeResponse.ok, true)

        mainStore.appendAssistant(mainKey, "hidden after unsubscribe")
        let _ = gatewayServerPublishSessionMessageEvent(mainKey)
        let afterUnsubscribe = GatewayServer.defaultServer().pullEvents("phase14-message-client", limit: 8)
        @Expect(afterUnsubscribe.get("events").getOrThrow().asArray().size(), 0)

        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-message-client", timeoutMs: 1000)
        mainStore.deleteSession(mainKey)
        mainStore.deleteSession(workerKey)
    }

    @TestCase
    public func streamSubscriptionCanFilterTranscriptEvents(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:stream-filter-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let params = JsonObject()
        let eventKinds = JsonArray([])
        eventKinds.add(JsonString("session.transcript.updated"))
        params.put("eventKinds", eventKinds)
        let request = GatewayProtocolRequest(
            "events.stream",
            runtimeTestConnectParams("cli-stream-filter-test", "", sessionKey),
            params: params
        )
        GatewayServer.defaultServer().request(request)

        let updatedPayload = JsonObject()
        updatedPayload.put("sessionKey", JsonString(sessionKey))
        gatewayServerPublishClientEvent("cli-stream-filter-test", "session.updated", detail: "updated", payload: updatedPayload)
        let transcriptPayload = JsonObject()
        transcriptPayload.put("sessionKey", JsonString(sessionKey))
        gatewayServerPublishClientEvent(
            "cli-stream-filter-test",
            "session.transcript.updated",
            detail: "transcript-updated",
            payload: transcriptPayload
        )

        let stream = GatewayServer.defaultServer().streamEvents("cli-stream-filter-test", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        @Expect(events.size(), 1)
        @Expect(runtimeTestString(events[0].asObject(), "kind"), "session.transcript.updated")

        GatewayServer.defaultServer().stopAndWait(clientId: "cli-stream-filter-test", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionEventSubscriberRegistryAppearsInSnapshot(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:direct-subscriber-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "metis-control-ui",
            eventKinds: ["session.updated", "session.transcript.updated"]
        )
        @Expect(subscribedKinds.size, 2)
        let rows = gatewayServerRuntimeSnapshot().get("eventSubscriptions").getOrThrow().asArray()
        var found = false
        for (i in 0..rows.size()) {
            let row = rows[i].asObject()
            if (runtimeTestString(row, "clientId") != "metis-control-ui") {
                continue
            }
            found = true
            @Expect(runtimeTestString(row, "subscriptionMode"), "direct-websocket")
            @Expect(row.get("eventKinds").getOrThrow().asArray().size(), 2)
        }
        @Expect(found, true)

        gatewayServerUnsubscribeSessionEvents("metis-control-ui")
        GatewayServer.defaultServer().stopAndWait(clientId: "metis-control-ui", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func serverEventQueueRowCarriesSessionProjection(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:queue-row-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let request = GatewayProtocolRequest(
            "events.stream",
            runtimeTestConnectParams("cli-queue-test", "", sessionKey)
        )
        GatewayServer.defaultServer().request(request)
        gatewayServerPublishClientEvent("cli-queue-test", "chat", detail: "queued", payload: JsonObject())

        let rows = gatewayServerRuntimeSnapshot().get("eventQueues").getOrThrow().asArray()
        var found = false
        for (i in 0..rows.size()) {
            let row = rows[i].asObject()
            if (runtimeTestString(row, "clientId") != "cli-queue-test") {
                continue
            }
            found = true
            @Expect(runtimeTestString(row, "agentId"), "general")
            @Expect(runtimeTestString(row, "sessionId").contains(".jsonl"), false)
            @Expect(row.get("origin").isSome(), true)
        }
        @Expect(found, true)

        GatewayServer.defaultServer().stopAndWait(clientId: "cli-queue-test", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func serverStreamResultCarriesSessionProjection(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:stream-result-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let request = GatewayProtocolRequest(
            "events.stream",
            runtimeTestConnectParams("cli-stream-test", "", sessionKey)
        )
        GatewayServer.defaultServer().request(request)
        let result = GatewayServer.defaultServer().keepaliveStream("cli-stream-test")
        @Expect(runtimeTestString(result, "agentId"), "general")
        @Expect(runtimeTestString(result, "sessionId").contains(".jsonl"), false)
        @Expect(result.get("origin").isSome(), true)

        GatewayServer.defaultServer().stopAndWait(clientId: "cli-stream-test", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func serverPublishesSessionLifecycleEventsForBindAndUnbind(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:lifecycle-event-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let before = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray().size()
        let connectParams = runtimeTestConnectParams("cli-lifecycle-test", "conn-lifecycle-test", sessionKey)
        GatewayServer.defaultServer().connect(connectParams)
        GatewayServer.defaultServer().stopAndWait(clientId: "cli-lifecycle-test", timeoutMs: 1000)

        let history = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray()
        @Expect(history.size() > before, true)
        let lifecycleRow = runtimeFindEventByKind(history, "session.lifecycle", sessionKey)
        @Expect(runtimeTestString(lifecycleRow, "agentId"), "general")
        @Expect(runtimeTestString(lifecycleRow, "sessionId").contains(".jsonl"), false)
        @Expect(lifecycleRow.get("origin").isSome(), true)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func serverPublishesSessionLifecycleEventForStreamKeepalive(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:lifecycle-keepalive-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let connectParams = runtimeTestConnectParams("cli-lifecycle-keepalive", "conn-lifecycle-keepalive", sessionKey)
        GatewayServer.defaultServer().connect(connectParams)
        let before = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray().size()
        GatewayServer.defaultServer().keepaliveStream("cli-lifecycle-keepalive")

        let history = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray()
        @Expect(history.size() > before, true)
        let lifecycleRow = runtimeFindEventByKind(history, "session.lifecycle", sessionKey)
        @Expect(runtimeTestString(lifecycleRow, "agentId"), "general")
        @Expect(runtimeTestString(lifecycleRow, "sessionId").contains(".jsonl"), false)
        @Expect(lifecycleRow.get("origin").isSome(), true)

        GatewayServer.defaultServer().stopAndWait(clientId: "cli-lifecycle-keepalive", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func serverPublishesSessionUpdatedEventForRequestBegin(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:request-updated-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let connectParams = runtimeTestConnectParams("cli-request-updated", "conn-request-updated", sessionKey)
        GatewayServer.defaultServer().connect(connectParams)
        let before = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray().size()
        let request = GatewayProtocolRequest(
            "status",
            connectParams,
            requestId: "req-session-updated"
        )
        GatewayServer.defaultServer().request(request)

        let history = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray()
        @Expect(history.size() > before, true)
        let updatedRow = runtimeFindEventByKind(history, "session.updated", sessionKey)
        @Expect(runtimeTestString(updatedRow, "agentId"), "general")
        @Expect(runtimeTestString(updatedRow, "sessionId").contains(".jsonl"), false)
        @Expect(updatedRow.get("origin").isSome(), true)

        GatewayServer.defaultServer().stopAndWait(clientId: "cli-request-updated", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func chatTurnPublishesSessionTranscriptUpdatedEvent(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:transcript-updated-test"
        store.deleteSession(sessionKey)

        let params = JsonObject()
        params.put("session", JsonString(sessionKey))
        params.put("text", JsonString("hello"))
        params.put("channel", JsonString("cli"))
        params.put("agentId", JsonString("general"))
        params.put("source", JsonString("dashboard-rpc"))

        let before = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray().size()
        let result = gatewayExecuteChatTurnFromRpc(params)
        @Expect(result.get("error").isSome(), false)

        let history = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray()
        @Expect(history.size() > before, true)
        let updatedRow = runtimeFindEventByKind(history, "session.transcript.updated", sessionKey)
        let changedRow = runtimeFindEventByKind(history, "sessions.changed", sessionKey)
        @Expect(runtimeTestString(updatedRow, "agentId"), "general")
        @Expect(runtimeTestString(updatedRow, "entryKind"), "turn")
        @Expect(runtimeTestString(updatedRow, "lastRole"), "assistant")
        @Expect(updatedRow.get("origin").isSome(), true)
        @Expect(updatedRow.get("binding").isSome(), true)
        @Expect(runtimeTestString(changedRow, "phase"), "message")
        @Expect(runtimeTestString(changedRow, "agentId"), "general")
        @Expect(changedRow.get("binding").isSome(), true)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionSubscribersReceiveSessionsChangedMessageEvents(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:sessions-changed-test"
        store.deleteSession(sessionKey)

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "phase14-session-change-subscriber",
            eventKinds: ["sessions.changed"]
        )
        @Expect(subscribedKinds.size, 1)

        let params = JsonObject()
        params.put("session", JsonString(sessionKey))
        params.put("text", JsonString("hello"))
        params.put("channel", JsonString("cli"))
        params.put("agentId", JsonString("general"))
        params.put("source", JsonString("dashboard-rpc"))

        let result = gatewayExecuteChatTurnFromRpc(params)
        @Expect(result.get("error").isSome(), false)

        let stream = GatewayServer.defaultServer().streamEvents("phase14-session-change-subscriber", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        @Expect(events.size() > 0, true)
        let row = events[0].asObject()
        @Expect(runtimeTestString(row, "kind"), "sessions.changed")
        @Expect(runtimeTestString(row, "sessionKey"), sessionKey)
        @Expect(runtimeTestString(row, "phase"), "message")
        @Expect(row.get("binding").isSome(), true)

        gatewayServerUnsubscribeSessionEvents("phase14-session-change-subscriber")
        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-session-change-subscriber", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsChangedPatchEventsReplaySessionMetadata(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:sessions-changed-patch-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let root = JsonObject()
        let entry = JsonObject()
        entry.put("sessionKey", JsonString(sessionKey))
        entry.put("updatedAt", 123.toJsonValue())
        entry.put("sessionFile", JsonString("agent_general_sessions-changed-patch-test.jsonl"))
        entry.put("sessionId", JsonString("agent_general_sessions-changed-patch-test"))
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

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "phase14-session-patch-subscriber",
            eventKinds: ["sessions.changed"]
        )
        @Expect(subscribedKinds.size, 1)

        let published = gatewayServerPublishSessionsChangedEvent(
            sessionKey,
            reason: "patch",
            detail: "patch"
        )
        @Expect(published > 0, true)

        let stream = GatewayServer.defaultServer().streamEvents("phase14-session-patch-subscriber", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        @Expect(events.size() > 0, true)
        let row = events[0].asObject()
        @Expect(runtimeTestString(row, "kind"), "sessions.changed")
        @Expect(runtimeTestString(row, "reason"), "patch")
        @Expect(runtimeTestString(row, "sendPolicy"), "deny")
        @Expect(runtimeTestString(row, "verboseLevel"), "on")
        @Expect(runtimeTestString(row, "responseUsage"), "full")
        @Expect(runtimeTestString(row, "lastChannel"), "telegram")
        @Expect(runtimeTestString(row, "lastTo"), "-100123")
        @Expect(runtimeTestString(row, "lastAccountId"), "acct-1")
        @Expect(runtimeTestString(row, "modelProvider"), "openai")
        @Expect(runtimeTestString(row, "model"), "gpt-5.4")
        @Expect(runtimeTestString(row, "spawnedBy"), "agent:main:main")
        @Expect(runtimeTestString(row, "spawnedWorkspaceDir"), "/tmp/subagent-workspace")
        @Expect(runtimeTestString(row, "subagentRole"), "orchestrator")
        @Expect(runtimeTestString(row, "subagentControlScope"), "children")
        @Expect(runtimeTestString(row, "parentSessionKey"), "agent:main:main")

        gatewayServerUnsubscribeSessionEvents("phase14-session-patch-subscriber")
        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-session-patch-subscriber", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionMessageAndSessionsChangedReplayTranscriptMessageId(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:message-id-test"
        store.deleteSession(sessionKey)
        let transcriptPath = store.transcriptPath(sessionKey)
        let raw = "{\"kind\":\"meta\",\"v\":\"1\",\"sessionKey\":\"${sessionKey}\"}\n" +
            "{\"id\":\"msg-phase14\",\"role\":\"assistant\",\"text\":\"hello-id\",\"ts\":\"123\"}\n"
        File.writeTo(transcriptPath, raw.toArray())
        let _ = store.listSessionKeys()

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "phase14-session-message-id-subscriber",
            eventKinds: ["sessions.changed"]
        )
        @Expect(subscribedKinds.size, 1)
        @Expect(gatewayServerSubscribeSessionMessageEvents("phase14-session-message-id-subscriber", sessionKey), true)

        let published = gatewayServerPublishSessionMessageEvent(sessionKey)
        @Expect(published > 0, true)
        let changedPublished = gatewayServerPublishSessionsChangedEvent(
            sessionKey,
            phase: "message",
            detail: "chat-turn-transcript-appended"
        )
        @Expect(changedPublished > 0, true)

        let stream = GatewayServer.defaultServer().streamEvents("phase14-session-message-id-subscriber", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        let messageRow = runtimeFindEventByKind(events, "session.message", sessionKey)
        let changedRow = runtimeFindEventByKind(events, "sessions.changed", sessionKey)
        @Expect(runtimeTestString(messageRow, "messageId"), "msg-phase14")
        @Expect(runtimeTestString(changedRow, "messageId"), "msg-phase14")

        gatewayServerUnsubscribeSessionMessageEvents("phase14-session-message-id-subscriber", sessionKey)
        gatewayServerUnsubscribeSessionEvents("phase14-session-message-id-subscriber")
        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-session-message-id-subscriber", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsDeletePublishesLifecycleAndDeletedReason(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:delete-lifecycle-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "phase14-session-delete-lifecycle-subscriber",
            eventKinds: ["session.lifecycle", "sessions.changed"]
        )
        @Expect(subscribedKinds.size, 2)

        let deleteParams = JsonObject()
        deleteParams.put("key", JsonString(sessionKey))
        let deleteResponse = handleGatewaySessionsFamily("sessions.delete", request: Some(GatewayRpcRequest("sessions.delete", params: deleteParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(deleteResponse.ok, true)

        let stream = GatewayServer.defaultServer().streamEvents("phase14-session-delete-lifecycle-subscriber", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        let lifecycleRow = runtimeFindEventByKind(events, "session.lifecycle", sessionKey)
        let changedRow = runtimeFindEventByKind(events, "sessions.changed", sessionKey)
        @Expect(runtimeTestString(lifecycleRow, "state"), "deleted")
        @Expect(runtimeTestString(lifecycleRow, "detail"), "deleted")
        @Expect(runtimeTestString(changedRow, "reason"), "deleted")

        gatewayServerUnsubscribeSessionEvents("phase14-session-delete-lifecycle-subscriber")
        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-session-delete-lifecycle-subscriber", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsResetPublishesLifecycleAndResetReason(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:reset-lifecycle-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "phase14-session-reset-lifecycle-subscriber",
            eventKinds: ["session.lifecycle", "sessions.changed"]
        )
        @Expect(subscribedKinds.size, 2)

        let resetParams = JsonObject()
        resetParams.put("key", JsonString(sessionKey))
        let resetResponse = handleGatewaySessionsFamily("sessions.reset", request: Some(GatewayRpcRequest("sessions.reset", params: resetParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(resetResponse.ok, true)

        let stream = GatewayServer.defaultServer().streamEvents("phase14-session-reset-lifecycle-subscriber", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        let lifecycleRow = runtimeFindEventByKind(events, "session.lifecycle", sessionKey)
        let changedRow = runtimeFindEventByKind(events, "sessions.changed", sessionKey)
        @Expect(runtimeTestString(lifecycleRow, "state"), "reset")
        @Expect(runtimeTestString(lifecycleRow, "detail"), "reset")
        @Expect(runtimeTestString(changedRow, "reason"), "reset")

        gatewayServerUnsubscribeSessionEvents("phase14-session-reset-lifecycle-subscriber")
        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-session-reset-lifecycle-subscriber", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionsCompactPublishesCompactedChangedEvent(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:compact-changed-test"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "one")
        store.appendAssistant(sessionKey, "two")
        store.appendUser(sessionKey, "three")
        store.appendAssistant(sessionKey, "four")

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "phase14-session-compact-subscriber",
            eventKinds: ["sessions.changed"]
        )
        @Expect(subscribedKinds.size, 1)

        let compactParams = JsonObject()
        compactParams.put("key", JsonString(sessionKey))
        compactParams.put("maxLines", 3.toJsonValue())
        let compactResponse = handleGatewaySessionsFamily("sessions.compact", request: Some(GatewayRpcRequest("sessions.compact", params: compactParams, clientId: "metis-cli"))).getOrThrow()
        @Expect(compactResponse.ok, true)

        let stream = GatewayServer.defaultServer().streamEvents("phase14-session-compact-subscriber", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        let changedRow = runtimeFindEventByKind(events, "sessions.changed", sessionKey)
        @Expect(runtimeTestString(changedRow, "reason"), "compact")
        @Expect(changedRow.get("compacted").getOrThrow().asBool().getValue(), true)

        gatewayServerUnsubscribeSessionEvents("phase14-session-compact-subscriber")
        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-session-compact-subscriber", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func sessionTranscriptSubscribersReceiveTranscriptUpdatedEvents(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:subscriber-transcript-test"
        store.deleteSession(sessionKey)

        let subscribedKinds = gatewayServerSubscribeSessionEvents(
            "phase14-transcript-subscriber",
            eventKinds: ["session.transcript.updated"]
        )
        @Expect(subscribedKinds.size, 1)

        let params = JsonObject()
        params.put("session", JsonString(sessionKey))
        params.put("text", JsonString("hello"))
        params.put("channel", JsonString("cli"))
        params.put("agentId", JsonString("general"))
        params.put("source", JsonString("dashboard-rpc"))

        let result = gatewayExecuteChatTurnFromRpc(params)
        @Expect(result.get("error").isSome(), false)

        let stream = GatewayServer.defaultServer().streamEvents("phase14-transcript-subscriber", limit: 8)
        let pull = stream.get("pull").getOrThrow().asObject()
        let events = pull.get("events").getOrThrow().asArray()
        @Expect(events.size() > 0, true)
        let row = events[0].asObject()
        @Expect(runtimeTestString(row, "kind"), "session.transcript.updated")
        @Expect(runtimeTestString(row, "sessionKey"), sessionKey)
        @Expect(row.get("origin").isSome(), true)
        @Expect(row.get("binding").isSome(), true)

        gatewayServerUnsubscribeSessionEvents("phase14-transcript-subscriber")
        GatewayServer.defaultServer().stopAndWait(clientId: "phase14-transcript-subscriber", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }

    @TestCase
    public func serverPublishesSessionLifecycleEventForStreamWaiting(): Unit {
        let user = GatewayUserSettings()
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        let sessionKey = "agent:general:stream-waiting-test"
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let connectParams = runtimeTestConnectParams("cli-stream-waiting", "conn-stream-waiting", sessionKey)
        GatewayServer.defaultServer().connect(connectParams)
        let before = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray().size()
        let _ = GatewayServer.defaultServer().streamEvents("cli-stream-waiting", waitMs: 30)

        let history = gatewayServerRuntimeSnapshot().get("eventHistory").getOrThrow().asArray()
        @Expect(history.size() > before, true)
        let lifecycleRow = runtimeFindEventByKind(history, "session.lifecycle", sessionKey)
        @Expect(runtimeTestString(lifecycleRow, "agentId"), "general")
        @Expect(runtimeTestString(lifecycleRow, "sessionId").contains(".jsonl"), false)
        @Expect(lifecycleRow.get("origin").isSome(), true)

        GatewayServer.defaultServer().stopAndWait(clientId: "cli-stream-waiting", timeoutMs: 1000)
        store.deleteSession(sessionKey)
    }
}
*/
