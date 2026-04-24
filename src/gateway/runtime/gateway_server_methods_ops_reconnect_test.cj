package metis.gateway.runtime

import metis.core.config.GatewayUserSettings

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject}

private func opsReconnectTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayServerMethodsOpsReconnectTest {
    @TestCase
    public func transportReconnectStateCarriesSharedRemoteAndReconnectSummaries(): Unit {
        let response = handleGatewayOpsFamily("transport.reconnect.state", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(result.get("remote").isSome(), true)
        @Expect(result.get("reconnect").isSome(), true)
        let remote = result.get("remote").getOrThrow().asObject()
        let reconnect = result.get("reconnect").getOrThrow().asObject()
        @Expect(opsReconnectTestString(remote, "phase"), "idle")
        @Expect(opsReconnectTestString(reconnect, "reconnectState"), "idle")
    }

    @TestCase
    public func transportReconnectPlanCarriesSharedRemoteAndReconnectSummaries(): Unit {
        let response = handleGatewayOpsFamily("transport.reconnect.plan", GatewayUserSettings())
        @Expect(response.isSome(), true)
        let result = response.getOrThrow().result.asObject()
        @Expect(result.get("remote").isSome(), true)
        @Expect(result.get("reconnect").isSome(), true)
        @Expect(result.get("plan").isSome(), true)
    }
}
