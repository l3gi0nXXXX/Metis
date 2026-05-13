package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.config.buildGatewayConfigFromUserSettings

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.unittest.testmacro.*
import stdx.encoding.json.JsonValue

private func gatewayHttpSurfaceTestUser(): GatewayUserSettings {
    var user = GatewayUserSettings()
    user.auth.mode = "none"
    user
}

private func gatewayHttpSurfaceTestResult(raw: String): JsonValue {
    JsonValue.fromStr(raw).asObject().get("result").getOrThrow()
}

private func withGatewayHttpSurfaceTestSettings<T>(block: () -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let testHome = "/tmp/metis-gateway-http-surface-test-home"
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
        let _ = MetisConfigManager.setGatewaySettings(gatewayHttpSurfaceTestUser())
        CliSettingManager.invalidate()
        try {
            block()
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
}

@Test
public class GatewayHttpSurfaceTest {
    @TestCase
    public func buildChatTurnParamsPreservesUnifiedGatewayHttpIngress(): Unit {
        let params = gatewayHttpBuildChatTurnParams("agent:main:main", "ping")
        @Expect(params.get("session").getOrThrow().asString().getValue(), "agent:main:main")
        @Expect(params.get("text").getOrThrow().asString().getValue(), "ping")
        @Expect(params.get("source").getOrThrow().asString().getValue(), "gateway-http")
        @Expect(params.get("channel").getOrThrow().asString().getValue(), "gateway-http")
        @Expect(params.get("deliver").getOrThrow().asBool().getValue(), false)
    }

    @TestCase
    public func probeBodiesExposeGatewayStatusFields(): Unit {
        let cfg = buildGatewayConfigFromUserSettings(GatewayUserSettings())
        let snapshot = GatewayHttpSurface.snapshot(cfg)
        @Expect(snapshot.get("health").isSome(), true)
        @Expect(snapshot.get("healthz").isSome(), true)
        @Expect(snapshot.get("ready").isSome(), true)
        @Expect(snapshot.get("readyz").isSome(), true)
        @Expect(snapshot.get("probePaths").isSome(), true)

        let healthz = JsonValue.fromStr(gatewayHttpHealthProbeJson(cfg)).asObject()
        @Expect(healthz.get("ok").getOrThrow().asBool().getValue(), true)
        @Expect(healthz.get("status").getOrThrow().asString().getValue(), "live")
        @Expect(healthz.get("gateway").isSome(), true)

        let readyz = JsonValue.fromStr(gatewayHttpReadyProbeJson(cfg)).asObject()
        @Expect(readyz.get("ready").isSome(), true)
        @Expect(readyz.get("ok").isSome(), true)
        @Expect(readyz.get("status").getOrThrow().asString().getValue(), "ready")
        @Expect(readyz.get("gateway").isSome(), true)
    }

    @TestCase
    public func probeHelpersPreserveGatewayMethodSemantics(): Unit {
        @Expect(gatewayHttpProbeMethodAllowed("GET"), true)
        @Expect(gatewayHttpProbeMethodAllowed("HEAD"), true)
        @Expect(gatewayHttpProbeMethodAllowed("POST"), false)
        @Expect(gatewayHttpProbeResponseBody("HEAD", "{\"ok\":true}"), "")
        @Expect(gatewayHttpProbeResponseBody("GET", "{\"ok\":true}"), "{\"ok\":true}")
    }

    @TestCase
    public func mcpToolCatalogCarriesHttpSurfaceTools(): Unit {
        withGatewayHttpSurfaceTestSettings<Unit>({ =>
            let response = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}"
            )
            @Expect(response.contains("gateway.readiness"), true)
            @Expect(response.contains("gateway.config.get"), true)
            @Expect(response.contains("gateway.config.schema.lookup"), true)
            @Expect(response.contains("gateway.http.status"), true)
            @Expect(response.contains("gateway.http.start"), true)
            @Expect(response.contains("gateway.webchat.status"), true)
            @Expect(response.contains("gateway.webchat.start"), true)
            @Expect(response.contains("gateway.channels.audit"), true)
        })
    }

    @TestCase
    public func mcpToolsCallRejectsDeniedGatewayToolBeforeDispatch(): Unit {
        withGatewayHttpSurfaceTestSettings<Unit>({ =>
            var user = gatewayHttpSurfaceTestUser()
            user.tools.deny = ["gateway.http.start"]

            let response = gatewayHandleMcpRequest(
                user,
                "{\"jsonrpc\":\"2.0\",\"id\":17,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.http.start\",\"arguments\":{}}}"
            )

            @Expect(response.contains("\"error\""), true)
            @Expect(response.contains("tool denied by policy"), true)
            @Expect(response.contains("gateway.http.start"), true)
            @Expect(response.contains("\"started\""), false)
        })
    }

    @TestCase
    public func mcpHttpStartAndStatusForwardExistingPlatformMethods(): Unit {
        withGatewayHttpSurfaceTestSettings<Unit>({ =>
            let readinessResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.readiness\",\"arguments\":{}}}"
            )
            @Expect(readinessResponse.contains("\"readiness\""), true)
            @Expect(readinessResponse.contains("\"surfaces\""), true)

            let configGetResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.config.get\",\"arguments\":{\"path\":\"gateway.enabled\"}}}"
            )
            let configGet = gatewayHttpSurfaceTestResult(configGetResponse).asObject()
            @Expect(configGet.get("path").getOrThrow().asString().getValue(), "gateway.enabled")
            @Expect(configGet.get("value").isSome(), true)

            let schemaLookupResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.config.schema.lookup\",\"arguments\":{\"path\":\"gateway\"}}}"
            )
            @Expect(schemaLookupResponse.contains("\"schema\""), true)

            let webchatStatusResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.webchat.status\",\"arguments\":{}}}"
            )
            @Expect(webchatStatusResponse.contains("\"webchat\""), true)

            let webchatStartResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.webchat.start\",\"arguments\":{}}}"
            )
            let webchatStart = gatewayHttpSurfaceTestResult(webchatStartResponse).asObject()
            @Expect(webchatStart.get("started").getOrThrow().asBool().getValue(), true)
            @Expect(webchatStart.get("webchat").isSome(), true)

            let startResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.http.start\",\"arguments\":{}}}"
            )
            let start = gatewayHttpSurfaceTestResult(startResponse).asObject()
            @Expect(start.get("started").getOrThrow().asBool().getValue(), true)
            @Expect(start.get("http").isSome(), true)

            let statusResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.http.status\",\"arguments\":{}}}"
            )
            @Expect(statusResponse.contains("\"http\""), true)
            @Expect(statusResponse.contains("\"probePaths\""), true)

            let channelsAuditResponse = gatewayHandleMcpRequest(
                gatewayHttpSurfaceTestUser(),
                "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"tools/call\",\"params\":{\"name\":\"gateway.channels.audit\",\"arguments\":{\"channelId\":\"telegram\"}}}"
            )
            @Expect(channelsAuditResponse.contains("\"gateway-channels-audit\""), true)
            @Expect(channelsAuditResponse.contains("\"T12\""), true)
            let channelsAudit = gatewayHttpSurfaceTestResult(channelsAuditResponse).asObject()
            let summary = channelsAudit.get("summary").getOrThrow().asObject()
            let consumers = summary.get("consumers").getOrThrow().asObject()
            @Expect(consumers.get("mcpOverHttp").getOrThrow().asBool().getValue(), true)
            @Expect(channelsAuditResponse.contains("\"telegramThreadBindingVisibleInControlUiWsSessions\""), true)
        })
    }
}
