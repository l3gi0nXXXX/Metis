package metis.gateway.openclaw_runtime

import metis.core.config.GatewayUserSettings
import magic.jsonable.*
import std.collection.ArrayList
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private class FakeOpenClawCompatHostTransport <: OpenClawCompatHostTransport {
    public let frames = ArrayList<JsonObject>()
    public let timeouts = ArrayList<Int64>()
    public var alive: Bool = true
    public var closed: Bool = false
    private let responses = ArrayList<OpenClawCompatHostTransportResult>()

    public func enqueue(response: JsonObject): Unit {
        this.responses.add(OpenClawCompatHostTransportResult.Response(response))
    }

    public func enqueueTimeout(): Unit {
        this.responses.add(OpenClawCompatHostTransportResult.Timeout)
    }

    public func send(frame: JsonObject, timeoutMs!: Int64): OpenClawCompatHostTransportResult {
        this.frames.add(frame)
        this.timeouts.add(timeoutMs)
        if (this.responses.size == 0) {
            return OpenClawCompatHostTransportResult.Failure("missing fake response")
        }
        let response = this.responses[0]
        this.responses.remove(at: 0)
        response
    }

    public func close(): Unit {
        this.closed = true
        this.alive = false
    }

    public func isAlive(): Bool {
        this.alive
    }
}

private class FakeOpenClawCompatHostProcessRunner <: OpenClawCompatHostProcessRunner {
    public let starts = ArrayList<OpenClawCompatHostLaunchSpec>()
    public let transport = FakeOpenClawCompatHostTransport()
    public var failStartReason: String = ""

    public func start(spec: OpenClawCompatHostLaunchSpec): OpenClawCompatHostStartResult {
        this.starts.add(spec)
        if (!this.failStartReason.isEmpty()) {
            return OpenClawCompatHostStartResult.Failed(this.failStartReason)
        }
        return OpenClawCompatHostStartResult.Started(this.transport)
    }
}

private func jsonRpcResponse(id: Int64, result: JsonObject): JsonObject {
    let out = JsonObject()
    out.put("jsonrpc", JsonString("2.0"))
    out.put("id", id.toJsonValue())
    out.put("result", result)
    out
}

private func okResult(status: String): JsonObject {
    let out = JsonObject()
    out.put("ok", true.toJsonValue())
    out.put("status", JsonString(status))
    out
}

private func jstr(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func jint(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { v.asInt().getValue() } catch (_: Exception) { 0 }
        case None => 0
    }
}

private func jobj(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func jarr(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func runtimeSettings(): GatewayUserSettings {
    var user = GatewayUserSettings()
    let runtime = JsonObject()
    runtime.put("enabled", true.toJsonValue())
    runtime.put("nodeCommand", JsonString("/opt/node"))
    runtime.put("hostScript", JsonString("/repo/scripts/openclaw-compat-host.mjs"))
    let roots = JsonArray([])
    roots.add(JsonString("/plugins/a"))
    roots.add(JsonString("/plugins/b"))
    runtime.put("pluginRoots", roots)
    runtime.put("timeoutMs", 2500.toJsonValue())
    runtime.put("restartPolicy", JsonString("on-failure"))
    let extra = JsonObject()
    extra.put("openclawRuntime", runtime)
    user.channelsExtra = Some(extra)
    user
}

@Test
public class OpenClawCompatHostTest {
    @TestCase
    public func clientAssignsRequestIdsAndForwardsTimeoutToTransport(): Unit {
        let transport = FakeOpenClawCompatHostTransport()
        transport.enqueue(jsonRpcResponse(1, okResult("loaded")))
        transport.enqueue(jsonRpcResponse(2, okResult("healthy")))
        let client = OpenClawCompatHostClient(transport, defaultTimeoutMs: 1500)

        let first = client.request("plugin.load")
        let second = client.request("runtime.health", timeoutMs: 75)

        @Expect(first.ok, true)
        @Expect(first.requestId, 1)
        @Expect(second.ok, true)
        @Expect(second.requestId, 2)
        @Expect(jstr(transport.frames[0], "jsonrpc"), "2.0")
        @Expect(jint(transport.frames[0], "id"), 1)
        @Expect(jstr(transport.frames[0], "method"), "plugin.load")
        @Expect(jint(transport.frames[1], "id"), 2)
        @Expect(jstr(transport.frames[1], "method"), "runtime.health")
        @Expect(transport.timeouts[0], 1500)
        @Expect(transport.timeouts[1], 75)
    }

    @TestCase
    public func clientTimeoutBecomesDiagnosticWithoutClosingTransport(): Unit {
        let transport = FakeOpenClawCompatHostTransport()
        transport.enqueueTimeout()
        let client = OpenClawCompatHostClient(transport, defaultTimeoutMs: 90)

        let result = client.request("plugin.load")

        @Expect(result.ok, false)
        @Expect(result.status, "timeout")
        @Expect(result.errorCode, "OPENCLAW_HOST_TIMEOUT")
        @Expect(jstr(result.diagnostic, "kind"), "timeout")
        @Expect(jint(result.diagnostic, "timeoutMs"), 90)
        @Expect(transport.closed, false)
    }

    @TestCase
    public func clientStopSendsRuntimeStopAndClosesTransport(): Unit {
        let transport = FakeOpenClawCompatHostTransport()
        transport.enqueue(jsonRpcResponse(1, okResult("stopping")))
        let client = OpenClawCompatHostClient(transport, defaultTimeoutMs: 500)

        let result = client.stop()

        @Expect(result.ok, true)
        @Expect(jstr(transport.frames[0], "method"), "runtime.stop")
        @Expect(transport.closed, true)
    }

    @TestCase
    public func configReadsOpenClawRuntimeFromGatewayChannelsExtra(): Unit {
        let config = openClawCompatHostConfigFromGatewaySettings(runtimeSettings())

        @Expect(config.enabled, true)
        @Expect(config.nodeCommand, "/opt/node")
        @Expect(config.hostScript, "/repo/scripts/openclaw-compat-host.mjs")
        @Expect(config.pluginRoots.size, 2)
        @Expect(config.pluginRoots[0], "/plugins/a")
        @Expect(config.timeoutMs, 2500)
        @Expect(config.restartPolicy, "on-failure")
    }

    @TestCase
    public func managerStartLaunchesPersistentHostAndLoadsPluginRoots(): Unit {
        let runner = FakeOpenClawCompatHostProcessRunner()
        runner.transport.enqueue(jsonRpcResponse(1, okResult("loaded")))
        let manager = OpenClawCompatHostManager(
            openClawCompatHostConfigFromGatewaySettings(runtimeSettings()),
            runner: runner
        )

        let status = manager.start()

        @Expect(status.ok, true)
        @Expect(status.state, "running")
        @Expect(runner.starts.size, 1)
        @Expect(runner.starts[0].nodeCommand, "/opt/node")
        @Expect(runner.starts[0].hostScript, "/repo/scripts/openclaw-compat-host.mjs")
        @Expect(runner.starts[0].pluginRoots.size, 2)
        @Expect(jstr(runner.transport.frames[0], "method"), "plugin.load")
        @Expect(jarr(jobj(runner.transport.frames[0], "params"), "roots").size(), 2)
    }

    @TestCase
    public func managerStopSendsRuntimeStop(): Unit {
        let runner = FakeOpenClawCompatHostProcessRunner()
        runner.transport.enqueue(jsonRpcResponse(1, okResult("loaded")))
        runner.transport.enqueue(jsonRpcResponse(2, okResult("stopping")))
        let manager = OpenClawCompatHostManager(
            openClawCompatHostConfigFromGatewaySettings(runtimeSettings()),
            runner: runner
        )
        let _ = manager.start()

        let stopped = manager.stop()

        @Expect(stopped.ok, true)
        @Expect(stopped.state, "stopped")
        @Expect(jstr(runner.transport.frames[1], "method"), "runtime.stop")
        @Expect(runner.transport.closed, true)
    }

    @TestCase
    public func managerCrashHealthIsDiagnosticAndBackoffPreventsImmediateRestart(): Unit {
        let runner = FakeOpenClawCompatHostProcessRunner()
        runner.transport.enqueue(jsonRpcResponse(1, okResult("loaded")))
        let manager = OpenClawCompatHostManager(
            openClawCompatHostConfigFromGatewaySettings(runtimeSettings()),
            runner: runner
        )
        let _ = manager.start()
        runner.transport.alive = false

        let health = manager.health()
        let restart = manager.restart()

        @Expect(health.ok, false)
        @Expect(health.state, "crashed")
        @Expect(jstr(health.diagnostic, "kind"), "host_crashed")
        @Expect(restart.ok, false)
        @Expect(restart.state, "backoff")
        @Expect(jstr(restart.diagnostic, "kind"), "restart_backoff")
        @Expect(runner.starts.size, 1)
    }
}
