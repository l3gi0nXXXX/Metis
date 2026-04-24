package metis.gateway.runtime

import metis.core.config.GatewayUserSettings
import metis.gateway.core.gatewaySessionStoreForUserWithAgentId

import magic.jsonable.*
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func connectTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayServerMethodsConnectTest {
    @TestCase
    public func sessionKeyForClientUsesSessionBindingsSnapshot(): Unit {
        let rpc = JsonObject()
        let bindings = JsonArray([])
        let row = JsonObject()
        row.put("sessionKey", JsonString("agent:general:connect-bindings-test"))
        row.put("clientIds", JsonArray([JsonString("cli-connect-test")]))
        bindings.add(row)
        rpc.put("sessionBindings", bindings)

        @Expect(gatewayConnectSessionKeyForClient(rpc, "cli-connect-test"), "agent:general:connect-bindings-test")
    }

    @TestCase
    public func actionsCarryConversationProjectionForBoundStreamClient(): Unit {
        let user = GatewayUserSettings()
        let sessionKey = "agent:general:connect-actions-test"
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let rpc = JsonObject()

        let clients = JsonArray([])
        let client = JsonObject()
        client.put("clientId", JsonString("cli-connect-test"))
        clients.add(client)
        rpc.put("clients", clients)

        let streams = JsonArray([])
        let stream = JsonObject()
        stream.put("clientId", JsonString("cli-connect-test"))
        stream.put("phase", JsonString("streaming"))
        streams.add(stream)
        rpc.put("eventStreams", streams)

        let bindings = JsonArray([])
        let binding = JsonObject()
        binding.put("sessionKey", JsonString(sessionKey))
        binding.put("clientIds", JsonArray([JsonString("cli-connect-test")]))
        bindings.add(binding)
        rpc.put("sessionBindings", bindings)

        let actions = gatewayConnectActionsJson(rpc, "cli-connect-test", "", "")
        @Expect(actions.size() >= 2, true)

        let first = actions[0].asObject()
        @Expect(connectTestString(first, "agentId"), "general")
        @Expect(connectTestString(first, "sessionId").contains(".jsonl"), false)
        @Expect(first.get("origin").isSome(), true)
        @Expect(first.get("delivery").isSome(), true)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func projectedSessionKeyPrefersRequestedThenStreamRows(): Unit {
        let empty = JsonArray([])
        let streamRows = JsonArray([])
        let stream = JsonObject()
        stream.put("sessionKey", JsonString("agent:general:connect-stream-session"))
        streamRows.add(stream)

        @Expect(
            gatewayConnectProjectedSessionKey("agent:general:requested", streamRows, empty),
            "agent:general:requested"
        )
        @Expect(
            gatewayConnectProjectedSessionKey("", streamRows, empty),
            "agent:general:connect-stream-session"
        )
    }

    @TestCase
    public func appendProjectionForFirstRowUsesFilteredSessionKey(): Unit {
        let user = GatewayUserSettings()
        let sessionKey = "agent:general:connect-first-row-test"
        let store = gatewaySessionStoreForUserWithAgentId(user, "general")
        store.deleteSession(sessionKey)
        store.appendAssistant(sessionKey, "hello")

        let result = JsonObject()
        let rows = JsonArray([])
        let row = JsonObject()
        row.put("sessionKey", JsonString(sessionKey))
        rows.add(row)
        gatewayConnectAppendProjectionForFirstRow(result, rows, "")

        @Expect(connectTestString(result, "agentId"), "general")
        @Expect(connectTestString(result, "sessionId").contains(".jsonl"), false)
        @Expect(result.get("origin").isSome(), true)
        @Expect(result.get("delivery").isSome(), true)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func connectSummaryProjectsRemoteAndReconnectRuntime(): Unit {
        let transport = JsonObject()
        let remote = JsonObject()
        remote.put("connected", true.toJsonValue())
        remote.put("phase", JsonString("stable"))
        remote.put("policyState", JsonString("healthy"))
        remote.put("runtimeModel", JsonString("persistent-session-lease"))
        remote.put("resumable", true.toJsonValue())
        remote.put("attachable", true.toJsonValue())
        remote.put("serverPushCapable", true.toJsonValue())
        remote.put("lastError", JsonString(""))
        remote.put("lastProtocolVersion", JsonString("2026-04-17"))
        remote.put("lifecycle", JsonArray([]))
        remote.put("reconnectState", JsonString("connected"))
        remote.put("nextRetryAtMs", 0.toJsonValue())
        remote.put("cooldownRemainingMs", 0.toJsonValue())
        remote.put("eligibleForReconnect", true.toJsonValue())
        remote.put("transitionCount", 4.toJsonValue())
        remote.put("lastTransitionAtMs", 123.toJsonValue())
        remote.put("consecutiveFailureCount", 0.toJsonValue())
        remote.put("lastFailureAtMs", 0.toJsonValue())
        remote.put("lastSuccessAtMs", 456.toJsonValue())
        remote.put("lastBackoffMs", 0.toJsonValue())
        transport.put("preferred", JsonString("remote"))
        transport.put("remote", remote)
        let remoteSummary = gatewayConnectRemoteSummary(transport)
        let reconnectSummary = gatewayConnectReconnectSummary(transport)
        @Expect(connectTestString(remoteSummary, "phase"), "stable")
        @Expect(connectTestString(remoteSummary, "runtimeModel"), "persistent-session-lease")
        @Expect(connectTestString(reconnectSummary, "reconnectState"), "connected")
        @Expect(connectTestString(reconnectSummary, "policyState"), "healthy")
        @Expect(connectTestString(reconnectSummary, "phase"), "stable")
    }

    @TestCase
    public func streamSummariesProjectSharedLifecycleFields(): Unit {
        let streams = JsonArray([])
        let stream = JsonObject()
        stream.put("active", true.toJsonValue())
        stream.put("state", JsonString("streaming"))
        stream.put("phase", JsonString("queued"))
        stream.put("sessionMode", JsonString("persistent-session"))
        stream.put("runtimeModel", JsonString("persistent-session-lease"))
        stream.put("attachable", true.toJsonValue())
        stream.put("resumable", false.toJsonValue())
        stream.put("serverPushCapable", true.toJsonValue())
        stream.put("leaseState", JsonString("active"))
        stream.put("streamId", JsonString("str-1"))
        stream.put("sessionGeneration", 2.toJsonValue())
        stream.put("attachCount", 3.toJsonValue())
        stream.put("waiterCount", 1.toJsonValue())
        streams.add(stream)

        let subscriptions = JsonArray([])
        let subscription = JsonObject()
        subscription.put("streamState", JsonString("streaming"))
        subscription.put("streamPhase", JsonString("queued"))
        subscription.put("sessionMode", JsonString("persistent-session"))
        subscription.put("runtimeModel", JsonString("persistent-session-lease"))
        subscription.put("attachable", true.toJsonValue())
        subscription.put("resumable", false.toJsonValue())
        subscription.put("leaseState", JsonString("active"))
        subscription.put("streamId", JsonString("str-1"))
        subscription.put("sessionGeneration", 2.toJsonValue())
        subscription.put("attachCount", 3.toJsonValue())
        subscription.put("waiterCount", 1.toJsonValue())
        subscriptions.add(subscription)

        let streamSummary = gatewayConnectStreamSummary(streams)
        let subscriptionSummary = gatewayConnectSubscriptionSummary(subscriptions)
        @Expect(connectTestString(streamSummary, "phase"), "queued")
        @Expect(connectTestString(streamSummary, "streamId"), "str-1")
        @Expect(connectTestString(subscriptionSummary, "streamPhase"), "queued")
        @Expect(connectTestString(subscriptionSummary, "runtimeModel"), "persistent-session-lease")
    }
}
