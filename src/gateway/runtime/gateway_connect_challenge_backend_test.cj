package metis.gateway.runtime

import metis.core.config.{CliSettingManager, MetisConfigManager}
import metis.gateway.protocol.{GatewayClientInfo, GatewayConnectParams, GatewayProtocolRequest, GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED}

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private func challengeTestConnect(clientId: String, connectionId: String): GatewayConnectParams {
    GatewayConnectParams(
        GatewayClientInfo(clientId, name: clientId, mode: "control-ui-browser", version: "test"),
        transport: "remote",
        transportKind: "websocket",
        gatewayUrl: "ws://gateway.test",
        connectionId: connectionId,
        authToken: "",
        authPassword: ""
    )
}

private func challengeTestToken(response: JsonObject): String {
    response
        .get("challenge").getOrThrow().asObject()
        .get("challengeToken").getOrThrow().asString().getValue()
}

private func challengeTestConfigRoot(): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let defaults = JsonObject()
    defaults.put("workspace", JsonString(""))
    agents.put("defaults", defaults)
    root.put("agents", agents)
    root.put("gateway", JsonObject())
    root.put("session", JsonObject())
    root.put("skills", JsonObject())
    root.put("tools", JsonObject())
    root.put("models", JsonObject())
    root.put("auth", JsonObject())
    root.put("channels", JsonObject())
    root.put("plugins", JsonObject())
    root.put("wizard", JsonObject())
    root.put("meta", JsonObject())
    root
}

@Test
public class GatewayConnectChallengeBackendTest {
    @TestCase
    public func repeatedClientReconnectDoesNotChallengeGateAcceptedOlderConnection(): Unit {
        let originalRoot = MetisConfigManager.rawConfig() ?? JsonObject()
        MetisConfigManager.writeRoot(challengeTestConfigRoot())
        CliSettingManager.applyPersistedFieldsToCliConfig()
        let original = CliSettingManager.readGatewaySettings()
        var updated = original
        updated.auth.mode = "none"
        updated.controlUi.dangerouslyDisableDeviceAuth = true
        let _ = MetisConfigManager.setGatewaySettings(updated)
        CliSettingManager.invalidate()
        @Expect(CliSettingManager.readGatewaySettings().auth.mode, "none")
        @Expect(CliSettingManager.readGatewaySettings().controlUi.dangerouslyDisableDeviceAuth, true)

        let _ = GatewayServer.startGatewayServer(
            options: GatewayServerOptions(
                remoteTransportEnabled: true,
                enableHandshake: true
            )
        )
        let server = GatewayServer.defaultServer()
        let clientId = "control-ui-reconnect-test"
        try {
            let connectOne = challengeTestConnect(clientId, "conn-one")
            let helloOne = server.request(GatewayProtocolRequest("connect", connectOne))
            @Expect(helloOne.ok, true)
            @Expect(helloOne.result.asObject().get("connectChallengeRequired").getOrThrow().asBool().getValue(), true)

            let ackOneParams = JsonObject()
            ackOneParams.put("challengeToken", JsonString(challengeTestToken(helloOne.result.asObject())))
            let ackOne = server.request(GatewayProtocolRequest("connect.ack", connectOne, params: ackOneParams))
            @Expect(ackOne.ok, true)

            let firstHealth = server.request(GatewayProtocolRequest("health", connectOne))
            @Expect(firstHealth.ok, true)

            let connectTwo = challengeTestConnect(clientId, "conn-two")
            let helloTwo = server.request(GatewayProtocolRequest("connect", connectTwo))
            @Expect(helloTwo.ok, true)
            @Expect(helloTwo.result.asObject().get("connectChallengeRequired").getOrThrow().asBool().getValue(), true)

            let stillHealthy = server.request(GatewayProtocolRequest("health", connectOne))
            @Expect(stillHealthy.ok, true)
            @Expect(stillHealthy.errorCode, "")

            let snapshot = gatewayServerRuntimeSnapshot()
            let registry = snapshot.get("challengeRegistry").getOrThrow().asArray()
            var foundConnectionOne = false
            var foundConnectionTwo = false
            for (i in 0..registry.size()) {
                let row = registry[i].asObject()
                let connectionId = row.get("connectionId").getOrThrow().asString().getValue()
                if (connectionId == "conn-one") {
                    foundConnectionOne = true
                }
                if (connectionId == "conn-two") {
                    foundConnectionTwo = true
                    @Expect(row.get("clientId").getOrThrow().asString().getValue(), clientId)
                    @Expect(row.get("pending").getOrThrow().asBool().getValue(), true)
                }
            }
            @Expect(foundConnectionOne, false)
            @Expect(foundConnectionTwo, true)

            let challengedRequest = server.request(GatewayProtocolRequest("health", connectTwo))
            @Expect(challengedRequest.ok, false)
            @Expect(challengedRequest.errorCode, GATEWAY_ERROR_CONNECT_CHALLENGE_REQUIRED)
        } finally {
            let _ = server.stopAndWait(timeoutMs: 1000)
            MetisConfigManager.writeRoot(originalRoot)
            CliSettingManager.applyPersistedFieldsToCliConfig()
        }
    }
}
