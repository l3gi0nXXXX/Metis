package metis.gateway.runtime

import metis.core.config.{CliConfig, GatewayUserSettings}
import metis.gateway.config.GatewayChannelPluginRegistry
import metis.gateway.openclaw_http.OpenClawHttpRouteRegistry
import metis.gateway.openclaw_runtime.{OpenClawCompatHostLaunchSpec, OpenClawCompatHostProcessRunner, OpenClawCompatHostStartResult, OpenClawCompatHostTransport, OpenClawCompatHostTransportResult}

import magic.jsonable.*
import std.collection.ArrayList
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func gatewayOpenClawCompatLifecycleSettings(): GatewayUserSettings {
    var user = GatewayUserSettings()
    let runtime = JsonObject()
    runtime.put("enabled", true.toJsonValue())
    runtime.put("nodeCommand", JsonString("node"))
    runtime.put("hostScript", JsonString(CliConfig.cwd.join("scripts").join("openclaw-compat-host.mjs").toString()))
    let roots = JsonArray([])
    roots.add(JsonString(CliConfig.cwd.join("scripts").join("fixtures").join("openclaw-compat-host").join("raw-register").toString()))
    runtime.put("pluginRoots", roots)
    runtime.put("timeoutMs", 5000.toJsonValue())
    let secrets = JsonObject()
    secrets.put("OPENCLAW_TOKEN", JsonString("super-secret-token"))
    runtime.put("secrets", secrets)
    let permissions = JsonObject()
    permissions.put("media", true.toJsonValue())
    permissions.put("reply", true.toJsonValue())
    permissions.put("conversation", true.toJsonValue())
    permissions.put("thread", true.toJsonValue())
    permissions.put("process", false.toJsonValue())
    runtime.put("permissions", permissions)
    let extra = JsonObject()
    extra.put("openclawRuntime", runtime)
    user.channelsExtra = Some(extra)
    user
}

private class RuntimeLifecycleFakeTransport <: OpenClawCompatHostTransport {
    private let responses = ArrayList<OpenClawCompatHostTransportResult>()
    public var alive: Bool = true

    public func enqueue(response: JsonObject): Unit {
        this.responses.add(OpenClawCompatHostTransportResult.Response(response))
    }

    public func send(_frame: JsonObject, timeoutMs!: Int64): OpenClawCompatHostTransportResult {
        if (this.responses.size == 0) {
            return OpenClawCompatHostTransportResult.Failure("missing fake response")
        }
        let response = this.responses[0]
        this.responses.remove(at: 0)
        response
    }

    public func close(): Unit {
        this.alive = false
    }

    public func isAlive(): Bool {
        this.alive
    }
}

private class RuntimeLifecycleFakeRunner <: OpenClawCompatHostProcessRunner {
    public let transport = RuntimeLifecycleFakeTransport()

    public func start(_spec: OpenClawCompatHostLaunchSpec): OpenClawCompatHostStartResult {
        OpenClawCompatHostStartResult.Started(this.transport)
    }
}

private func runtimeLifecycleRpcResponse(id: Int64, result: JsonObject): JsonObject {
    let out = JsonObject()
    out.put("jsonrpc", JsonString("2.0"))
    out.put("id", id.toJsonValue())
    out.put("result", result)
    out
}

private func runtimeLifecycleOk(status: String): JsonObject {
    let out = JsonObject()
    out.put("ok", true.toJsonValue())
    out.put("status", JsonString(status))
    out
}

private func runtimeLifecycleRegisteredCapabilities(): JsonObject {
    let result = runtimeLifecycleOk("registered")
    let registries = JsonObject()
    let channels = JsonArray([])
    let channel = JsonObject()
    channel.put("pluginId", JsonString("raw-register-openclaw-fixture"))
    channel.put("id", JsonString("raw-register-openclaw-fixture"))
    let channelSpec = JsonObject()
    channelSpec.put("id", JsonString("raw-register-openclaw-fixture"))
    channel.put("spec", channelSpec)
    channels.add(channel)
    registries.put("channels", channels)

    let httpRoutes = JsonArray([])
    let route = JsonObject()
    route.put("pluginId", JsonString("raw-register-openclaw-fixture"))
    route.put("method", JsonString("GET"))
    route.put("path", JsonString("/fixture"))
    let routeSpec = JsonObject()
    routeSpec.put("method", JsonString("GET"))
    routeSpec.put("path", JsonString("/fixture"))
    route.put("spec", routeSpec)
    httpRoutes.add(route)
    registries.put("httpRoutes", httpRoutes)

    registries.put("tools", JsonArray([]))
    registries.put("providers", JsonArray([]))
    registries.put("hooks", JsonArray([]))
    result.put("gatewayRegistries", registries)
    result
}

@Test
public class GatewayOpenClawCompatLifecycleTest {
    @TestCase
    public func lifecycleStartSyncsHostCapabilitiesIntoGatewayRegistries(): Unit {
        OpenClawHttpRouteRegistry.clearForTest()
        GatewayChannelPluginRegistry.removeForTest("raw-register-openclaw-fixture")
        let user = gatewayOpenClawCompatLifecycleSettings()
        let runner = RuntimeLifecycleFakeRunner()
        runner.transport.enqueue(runtimeLifecycleRpcResponse(1, runtimeLifecycleOk("loaded")))
        runner.transport.enqueue(runtimeLifecycleRpcResponse(2, runtimeLifecycleRegisteredCapabilities()))
        runner.transport.enqueue(runtimeLifecycleRpcResponse(3, runtimeLifecycleOk("stopping")))

        let started = gatewayOpenClawCompatHostStartWithRunnerForTest(user, runner)
        let stopped = gatewayOpenClawCompatHostStop(user)
        let channelRegistered = GatewayChannelPluginRegistry.getById("raw-register-openclaw-fixture").isSome()
        let httpRouteRegistered = OpenClawHttpRouteRegistry.find("GET", "/fixture").isSome()
        GatewayChannelPluginRegistry.removeForTest("raw-register-openclaw-fixture")
        OpenClawHttpRouteRegistry.clearForTest()

        @Expect(started.get("state").getOrThrow().asString().getValue(), "running")
        @Expect(started.get("registrySync").getOrThrow().asObject().get("channels").getOrThrow().asInt().getValue(), 1)
        @Expect(started.get("registrySync").getOrThrow().asObject().get("httpRoutes").getOrThrow().asInt().getValue(), 1)
        @Expect(channelRegistered, true)
        @Expect(httpRouteRegistered, true)
        @Expect(stopped.get("state").getOrThrow().asString().getValue(), "stopped")
    }
}
