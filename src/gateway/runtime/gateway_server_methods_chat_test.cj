package metis.gateway.runtime

import metis.core.config.CliConfig
import metis.core.config.GatewayUserSettings
import metis.gateway.core.gatewaySessionStoreForUserWithAgentId

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private func chatTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayServerMethodsChatTest {
    @TestCase
    public func chatStatusAliasesDashboardStatusFamily(): Unit {
        CliConfig.model = "test:model"
        let response = handleGatewayChatFamily("chat.status", GatewayRpcRequest("chat.status")).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        @Expect(result.get("chat").isSome(), true)
    }

    @TestCase
    public func chatHistoryAliasesDashboardHistoryFamily(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let sessionKey = "agent:general:main"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "hello")

        let params = JsonObject()
        params.put("session", JsonString("main"))
        params.put("agentId", JsonString("general"))
        let response = handleGatewayChatFamily("chat.history", GatewayRpcRequest("chat.history", params: params)).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        @Expect(chatTestString(result, "session"), sessionKey)

        store.deleteSession(sessionKey)
    }

    @TestCase
    public func chatSessionsListAliasesDashboardStatusFamily(): Unit {
        CliConfig.model = "test:model"
        let response = handleGatewayChatFamily("chat.sessions.list", GatewayRpcRequest("chat.sessions.list")).getOrThrow()
        @Expect(response.ok, true)
        let result = response.result.asObject()
        @Expect(result.get("sessions").isSome(), true)
    }

    @TestCase
    public func chatSessionsDeleteWrapsDashboardDeleteResult(): Unit {
        let store = gatewaySessionStoreForUserWithAgentId(GatewayUserSettings(), "general")
        let sessionKey = "agent:general:main"
        store.deleteSession(sessionKey)
        store.appendUser(sessionKey, "cleanup")

        let params = JsonObject()
        params.put("keys", JsonString("main"))
        params.put("agentId", JsonString("general"))
        let response = handleGatewayChatFamily("chat.sessions.delete", GatewayRpcRequest("chat.sessions.delete", params: params)).getOrThrow()
        @Expect(response.ok, true)
        let sessions = response.result.asObject().get("sessions").getOrThrow().asObject()
        let deleted = sessions.get("deleted").getOrThrow().asArray()
        @Expect(deleted.size(), 1)
        @Expect(deleted[0].asString().getValue(), sessionKey)
    }
}
