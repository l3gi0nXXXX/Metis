package metis.gateway.runtime

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject}

private func opsTransportTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayServerMethodsOpsTransportTest {
    @TestCase
    public func transportLifecycleIncludesRemoteAndReconnectSummaries(): Unit {
        let response = handleGatewayOpsFamily("transport.lifecycle", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(result.get("remote").isSome(), true)
        @Expect(result.get("reconnect").isSome(), true)
        let remote = result.get("remote").getOrThrow().asObject()
        let reconnect = result.get("reconnect").getOrThrow().asObject()
        @Expect(opsTransportTestString(remote, "phase"), "idle")
        @Expect(opsTransportTestString(reconnect, "reconnectState"), "idle")
    }

    @TestCase
    public func transportHealthIncludesReconnectPolicySummary(): Unit {
        let response = handleGatewayOpsFamily("transport.health", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        let health = result.get("health").getOrThrow().asObject()
        @Expect(opsTransportTestString(health, "preferred"), "local")
        @Expect(opsTransportTestString(health, "phase"), "idle")
        @Expect(opsTransportTestString(health, "policyState"), "idle")
        @Expect(result.get("remote").isSome(), true)
        @Expect(result.get("reconnect").isSome(), true)
    }

    @TestCase
    public func transportStreamSessionsExposeSharedStreamSummaries(): Unit {
        let response = handleGatewayOpsFamily("transport.stream.sessions", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(result.get("streamSummary").isSome(), true)
        @Expect(result.get("subscriptionSummary").isSome(), true)
    }
}
