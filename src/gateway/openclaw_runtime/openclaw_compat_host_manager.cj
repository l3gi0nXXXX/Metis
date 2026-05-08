package metis.gateway.openclaw_runtime

import metis.core.config.GatewayUserSettings
import magic.jsonable.*
import std.collection.ArrayList
import std.convert.Parsable
import std.core.Duration
import std.io.*
import std.process.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

public class OpenClawCompatHostConfig {
    public var enabled: Bool = false
    public var nodeCommand: String = "node"
    public var hostScript: String = ""
    public var pluginRoots: Array<String> = []
    public var timeoutMs: Int64 = 10000
    public var restartPolicy: String = "on-failure"
    public var backoffMs: Int64 = 1000
    public var runtimeParams: JsonObject = JsonObject()

    public init() {}
}

public class OpenClawCompatHostLaunchSpec {
    public let nodeCommand: String
    public let hostScript: String
    public let pluginRoots: Array<String>
    public let timeoutMs: Int64

    public init(nodeCommand: String, hostScript: String, pluginRoots: Array<String>, timeoutMs: Int64) {
        this.nodeCommand = nodeCommand
        this.hostScript = hostScript
        this.pluginRoots = pluginRoots
        this.timeoutMs = timeoutMs
    }
}

public enum OpenClawCompatHostStartResult {
    | Started(OpenClawCompatHostTransport)
    | Failed(String)
}

public interface OpenClawCompatHostProcessRunner {
    func start(spec: OpenClawCompatHostLaunchSpec): OpenClawCompatHostStartResult
}

private class OpenClawCompatStdioHostTransport <: OpenClawCompatHostTransport {
    private let process: SubProcess
    private let reader: StringReader<InputStream>
    private let writer: StringWriter<OutputStream>
    private var closed: Bool = false

    public init(process: SubProcess) {
        this.process = process
        this.reader = StringReader<InputStream>(process.stdOutPipe)
        this.writer = StringWriter<OutputStream>(process.stdInPipe)
    }

    private func compactJsonLine(raw: String): String {
        let out = StringBuilder()
        var inString = false
        var escaped = false
        for (ch in raw.toRuneArray()) {
            if (escaped) {
                out.append(ch)
                escaped = false
                continue
            }
            if (inString && ch == r'\\') {
                out.append(ch)
                escaped = true
                continue
            }
            if (ch == r'"') {
                out.append(ch)
                inString = !inString
                continue
            }
            if (!inString && (ch == r' ' || ch == r'\n' || ch == r'\r' || ch == r'\t')) {
                continue
            }
            out.append(ch)
        }
        out.toString()
    }

    private func readLine(timeoutMs: Int64): Option<String> {
        let effectiveTimeoutMs = if (timeoutMs > 0) { timeoutMs } else { 10000 }
        let fut = spawn {
            try { this.reader.readln() } catch (_: Exception) { None<String> }
        }
        let watchdog = spawn {
            sleep(Duration.millisecond * effectiveTimeoutMs)
            fut.cancel()
        }
        try {
            let line = fut.get()
            watchdog.cancel()
            return line
        } catch (_: Exception) {
            try { watchdog.cancel() } catch (_e: Exception) { () }
            return None<String>
        }
    }

    public func send(frame: JsonObject, timeoutMs!: Int64): OpenClawCompatHostTransportResult {
        if (this.closed) {
            return OpenClawCompatHostTransportResult.Failure("OpenClaw compatibility host transport is closed")
        }
        try {
            this.writer.writeln(this.compactJsonLine(frame.toJsonString()))
            this.writer.flush()
        } catch (e: Exception) {
            this.closed = true
            return OpenClawCompatHostTransportResult.Failure("OpenClaw compatibility host write failed: ${e.message}")
        }
        match (this.readLine(timeoutMs)) {
            case Some(line) =>
                let trimmed = line.trimAscii()
                if (trimmed.isEmpty()) {
                    return OpenClawCompatHostTransportResult.Failure("OpenClaw compatibility host returned an empty frame")
                }
                try {
                    return OpenClawCompatHostTransportResult.Response(JsonValue.fromStr(trimmed).asObject())
                } catch (e: Exception) {
                    return OpenClawCompatHostTransportResult.Failure("OpenClaw compatibility host returned invalid json: ${e.message}")
                }
            case None =>
                OpenClawCompatHostTransportResult.Timeout
        }
    }

    public func close(): Unit {
        if (this.closed) {
            return
        }
        this.closed = true
        try {
            let _ = this.process.wait(timeout: Some(Duration.millisecond * 250))
        } catch (_: Exception) {
            try { this.process.terminate(force: true) } catch (_e: Exception) { () }
        }
    }

    public func isAlive(): Bool {
        !this.closed && this.process.isAlive()
    }
}

public class OpenClawCompatStdioProcessRunner <: OpenClawCompatHostProcessRunner {
    public init() {}

    public func start(spec: OpenClawCompatHostLaunchSpec): OpenClawCompatHostStartResult {
        let command = spec.nodeCommand.trimAscii()
        let script = spec.hostScript.trimAscii()
        if (command.isEmpty() || script.isEmpty()) {
            return OpenClawCompatHostStartResult.Failed("nodeCommand and hostScript are required")
        }
        try {
            let process = launch(
                command,
                [script],
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe
            )
            OpenClawCompatHostStartResult.Started(OpenClawCompatStdioHostTransport(process))
        } catch (e: Exception) {
            OpenClawCompatHostStartResult.Failed(e.message)
        }
    }
}

public class OpenClawCompatHostManagerStatus {
    public let ok: Bool
    public let state: String
    public let diagnostic: JsonObject
    public let raw: JsonObject

    public init(
        ok: Bool,
        state: String,
        diagnostic!: JsonObject = JsonObject(),
        raw!: JsonObject = JsonObject()
    ) {
        this.ok = ok
        this.state = state
        this.diagnostic = diagnostic
        this.raw = raw
    }
}

private func ocManagerDiagnostic(kind: String, message!: String = ""): JsonObject {
    let out = JsonObject()
    out.put("kind", JsonString(kind))
    if (!message.trimAscii().isEmpty()) {
        out.put("message", JsonString(message.trimAscii()))
    }
    out
}

private func ocManagerString(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let value = v.asString().getValue().trimAscii()
                if (value.isEmpty()) { fallback } else { value }
            } catch (_: Exception) {
                fallback
            }
        case None => fallback
    }
}

private func ocManagerBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func ocManagerInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_: Exception) { fallback }
        case None => fallback
    }
}

private func ocManagerArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func ocManagerObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func ocManagerConfigObject(user: GatewayUserSettings): JsonObject {
    match (user.channelsExtra) {
        case Some(extra) =>
            for (key in ["openclawRuntime", "openclawCompatHost", "openclawCompatibilityHost"]) {
                match (extra.get(key)) {
                    case Some(v) => try { return v.asObject() } catch (_: Exception) { () }
                    case None => ()
                }
            }
        case None => ()
    }
    JsonObject()
}

public func openClawCompatHostConfigFromGatewaySettings(user: GatewayUserSettings): OpenClawCompatHostConfig {
    let raw = ocManagerConfigObject(user)
    let config = OpenClawCompatHostConfig()
    config.runtimeParams = raw
    config.enabled = ocManagerBool(raw, "enabled", false)
    config.nodeCommand = ocManagerString(raw, "nodeCommand", "node")
    config.hostScript = ocManagerString(raw, "hostScript", "")
    let roots = ArrayList<String>()
    let arr = ocManagerArray(raw, "pluginRoots")
    for (i in 0..arr.size()) {
        let root = try { arr[i].asString().getValue().trimAscii() } catch (_: Exception) { "" }
        if (!root.isEmpty()) {
            roots.add(root)
        }
    }
    config.pluginRoots = roots.toArray()
    let timeoutMs = ocManagerInt(raw, "timeoutMs", 10000)
    config.timeoutMs = if (timeoutMs > 0) { timeoutMs } else { 10000 }
    config.restartPolicy = ocManagerString(raw, "restartPolicy", "on-failure")
    let backoffMs = ocManagerInt(raw, "backoffMs", 1000)
    config.backoffMs = if (backoffMs > 0) { backoffMs } else { 1000 }
    config
}

private func ocManagerRegistryArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

public class OpenClawCompatGatewayRegistryBridge {
    public let raw: JsonObject
    public let channels: JsonArray
    public let httpRoutes: JsonArray
    public let tools: JsonArray
    public let providers: JsonArray
    public let hooks: JsonArray

    public init(raw!: JsonObject = JsonObject()) {
        this.raw = raw
        this.channels = ocManagerRegistryArray(raw, "channels")
        this.httpRoutes = ocManagerRegistryArray(raw, "httpRoutes")
        this.tools = ocManagerRegistryArray(raw, "tools")
        this.providers = ocManagerRegistryArray(raw, "providers")
        this.hooks = ocManagerRegistryArray(raw, "hooks")
    }

    public func channelCount(): Int64 { this.channels.size() }
    public func httpRouteCount(): Int64 { this.httpRoutes.size() }
    public func toolCount(): Int64 { this.tools.size() }
    public func providerCount(): Int64 { this.providers.size() }
    public func hookCount(): Int64 { this.hooks.size() }
}

public class OpenClawCompatHostManager {
    private let config: OpenClawCompatHostConfig
    private let runner: OpenClawCompatHostProcessRunner
    private var client: Option<OpenClawCompatHostClient> = None<OpenClawCompatHostClient>
    private var state: String = "stopped"
    private var restartBackoffActive: Bool = false
    private var lastDiagnostic: JsonObject = JsonObject()
    private var registryBridge: OpenClawCompatGatewayRegistryBridge = OpenClawCompatGatewayRegistryBridge()

    public init(
        config: OpenClawCompatHostConfig,
        runner!: OpenClawCompatHostProcessRunner = OpenClawCompatStdioProcessRunner()
    ) {
        this.config = config
        this.runner = runner
    }

    private func pluginLoadParams(): JsonObject {
        let params = JsonObject()
        let roots = JsonArray([])
        for (root in this.config.pluginRoots) {
            roots.add(JsonString(root))
        }
        params.put("roots", roots)
        let runtime = JsonObject()
        runtime.put("version", JsonString("metis-openclaw-compat"))
        params.put("runtime", runtime)
        for (key in ["config", "secrets", "permissions", "fetchPolicy"]) {
            match (this.config.runtimeParams.get(key)) {
                case Some(v) => params.put(key, v)
                case None => ()
            }
        }
        params
    }

    private func syncRegisteredCapabilities(client: OpenClawCompatHostClient): OpenClawCompatHostClientResult {
        let registered = client.request("plugin.registeredCapabilities")
        if (registered.ok) {
            this.registryBridge = OpenClawCompatGatewayRegistryBridge(raw: ocManagerObject(registered.result, "gatewayRegistries"))
        }
        registered
    }

    private func status(ok: Bool, state: String, diagnostic!: JsonObject = JsonObject(), raw!: JsonObject = JsonObject()): OpenClawCompatHostManagerStatus {
        this.state = state
        this.lastDiagnostic = diagnostic
        OpenClawCompatHostManagerStatus(ok, state, diagnostic: diagnostic, raw: raw)
    }

    public func start(): OpenClawCompatHostManagerStatus {
        if (!this.config.enabled) {
            return this.status(true, "disabled")
        }
        match (this.client) {
            case Some(existing) =>
                if (existing.isAlive()) {
                    return this.status(true, "running")
                }
            case None => ()
        }
        if (this.restartBackoffActive) {
            return this.status(false, "backoff", diagnostic: ocManagerDiagnostic("restart_backoff"))
        }
        let spec = OpenClawCompatHostLaunchSpec(
            this.config.nodeCommand,
            this.config.hostScript,
            this.config.pluginRoots,
            this.config.timeoutMs
        )
        match (this.runner.start(spec)) {
            case Started(transport) =>
                let client = OpenClawCompatHostClient(transport, defaultTimeoutMs: this.config.timeoutMs)
                this.client = Some(client)
                let loaded = client.request("plugin.load", params: this.pluginLoadParams())
                if (loaded.ok) {
                    let registered = this.syncRegisteredCapabilities(client)
                    if (!registered.ok) {
                        return this.status(false, registered.status, diagnostic: registered.diagnostic, raw: registered.raw)
                    }
                    return this.status(true, "running", raw: loaded.raw)
                }
                return this.status(false, loaded.status, diagnostic: loaded.diagnostic, raw: loaded.raw)
            case Failed(reason) =>
                this.client = None<OpenClawCompatHostClient>
                return this.status(false, "error", diagnostic: ocManagerDiagnostic("launch_failed", message: reason))
        }
    }

    public func stop(): OpenClawCompatHostManagerStatus {
        match (this.client) {
            case Some(existing) =>
                let stopped = existing.stop()
                this.client = None<OpenClawCompatHostClient>
                this.restartBackoffActive = false
                return this.status(stopped.ok, "stopped", diagnostic: stopped.diagnostic, raw: stopped.raw)
            case None =>
                this.restartBackoffActive = false
                return this.status(true, "stopped")
        }
    }

    public func health(): OpenClawCompatHostManagerStatus {
        if (!this.config.enabled) {
            return this.status(true, "disabled")
        }
        match (this.client) {
            case Some(existing) =>
                if (!existing.isAlive()) {
                    this.restartBackoffActive = true
                    return this.status(false, "crashed", diagnostic: ocManagerDiagnostic("host_crashed"))
                }
                let healthy = existing.health()
                if (healthy.ok) {
                    return this.status(true, "running", raw: healthy.raw)
                }
                return this.status(false, healthy.status, diagnostic: healthy.diagnostic, raw: healthy.raw)
            case None =>
                return this.status(false, "stopped", diagnostic: ocManagerDiagnostic("host_not_started"))
        }
    }

    public func restart(): OpenClawCompatHostManagerStatus {
        if (this.config.restartPolicy.trimAscii().toAsciiLower() == "never") {
            return this.status(false, "disabled", diagnostic: ocManagerDiagnostic("restart_disabled"))
        }
        if (this.restartBackoffActive) {
            return this.status(false, "backoff", diagnostic: ocManagerDiagnostic("restart_backoff"))
        }
        let _ = this.stop()
        this.start()
    }

    public func snapshot(): OpenClawCompatHostManagerStatus {
        OpenClawCompatHostManagerStatus(
            this.state == "running" || this.state == "disabled" || this.state == "stopped",
            this.state,
            diagnostic: this.lastDiagnostic
        )
    }

    public func gatewayRegistryBridge(): OpenClawCompatGatewayRegistryBridge {
        this.registryBridge
    }
}
