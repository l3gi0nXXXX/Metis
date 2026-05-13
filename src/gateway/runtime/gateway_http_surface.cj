package metis.gateway.runtime

import magic.jsonable.*

import metis.core.runtimeToolInvocationAllowedFromRoot
import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.core.model.CliModelManager
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.model.GatewayConfig
import metis.gateway.openclaw_http.gatewayRegisterOpenClawHttpRoutes
import metis.gateway.protocol.{GATEWAY_ERROR_AUTH_FAILED, GATEWAY_ERROR_INVALID_CONNECT, GatewayClientInfo, GatewayConnectParams, GatewayProtocolRequest, GatewayProtocolResponse, validateGatewayConnectParams}
import metis.gateway.security.gatewayAuthorizeHttpRequestForConfig
import metis.gateway.session.{GatewayIngressSource, gatewayBuildChatSendRpcParams}

import std.collection.ArrayList
import std.convert.Parsable
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.base64.toBase64String
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}
import stdx.net.http.*

public class GatewayHttpSurface {
    private static let lock = Mutex()
    private static var started: Bool = false
    private static var server: Option<Server> = None
    private static var bindAddr: String = "127.0.0.1"
    private static var listenPort: UInt16 = 8080u16

    public static func baseUrl(cfg: GatewayConfig): String {
        let host = gatewayHttpListenHost(cfg)
        "http://${host}:${cfg.port}"
    }

    public static func snapshot(cfg: GatewayConfig): JsonObject {
        let obj = JsonObject()
        let probePaths = JsonArray([])
        probePaths.add(JsonString("/health"))
        probePaths.add(JsonString("/healthz"))
        probePaths.add(JsonString("/ready"))
        probePaths.add(JsonString("/readyz"))
        obj.put("enabled", gatewayHttpAnyEndpointEnabled(cfg).toJsonValue())
        obj.put("started", started.toJsonValue())
        obj.put("host", JsonString(gatewayHttpListenHost(cfg)))
        obj.put("bindAddr", JsonString(httpBindAddr(cfg)))
        obj.put("port", cfg.port.toJsonValue())
        obj.put("baseUrl", JsonString(baseUrl(cfg)))
        obj.put("health", JsonString("${baseUrl(cfg)}/health"))
        obj.put("healthz", JsonString("${baseUrl(cfg)}/healthz"))
        obj.put("ready", JsonString("${baseUrl(cfg)}/ready"))
        obj.put("readyz", JsonString("${baseUrl(cfg)}/readyz"))
        obj.put("probePaths", probePaths)
        obj.put("chatCompletionsEnabled", cfg.http.endpoints.chatCompletions.enabled.toJsonValue())
        obj.put("responsesEnabled", cfg.http.endpoints.responses.enabled.toJsonValue())
        obj.put("chatCompletionsPath", JsonString("/v1/chat/completions"))
        obj.put("responsesPath", JsonString("/v1/responses"))
        obj.put("modelsPath", JsonString("/v1/models"))
        obj.put("embeddingsPath", JsonString("/v1/embeddings"))
        obj.put("mcpPath", JsonString("/mcp"))
        obj.put("rpcPath", JsonString("/rpc"))
        obj
    }

    public static func isRunning(): Bool {
        synchronized(lock) {
            started
        }
    }

    public static func startIfNeeded(cfg: GatewayConfig): Unit {
        synchronized(lock) {
            if (started || !gatewayHttpAnyEndpointEnabled(cfg)) {
                return
            }
            bindAddr = httpBindAddr(cfg)
            listenPort = gatewayHttpPortToUInt16(cfg.port, 8080u16)
            let s = ServerBuilder().addr(bindAddr).port(listenPort).build()
            s.distributor.register("/healthz", { ctx =>
                gatewayHttpReplyProbe(ctx, gatewayHttpHealthProbeJson(cfg))
            })
            s.distributor.register("/health", { ctx =>
                gatewayHttpReplyProbe(ctx, gatewayHttpHealthProbeJson(cfg))
            })
            s.distributor.register("/readyz", { ctx =>
                gatewayHttpReplyProbe(ctx, gatewayHttpReadyProbeJson(cfg))
            })
            s.distributor.register("/ready", { ctx =>
                gatewayHttpReplyProbe(ctx, gatewayHttpReadyProbeJson(cfg))
            })
            s.distributor.register("/v1/models", { ctx =>
                let rb = ctx.responseBuilder
                rb.header("content-type", "application/json; charset=utf-8")
                rb.body(handleModels(ctx, cfg))
            })
            s.distributor.register("/v1/embeddings", { ctx =>
                let rb = ctx.responseBuilder
                rb.header("content-type", "application/json; charset=utf-8")
                rb.body(handleEmbeddings(ctx, cfg))
            })
            s.distributor.register("/mcp", { ctx =>
                let rb = ctx.responseBuilder
                rb.header("content-type", "application/json; charset=utf-8")
                rb.body(handleMcpHttp(ctx, cfg))
            })
            s.distributor.register("/rpc", { ctx =>
                let rb = ctx.responseBuilder
                rb.header("content-type", "application/json; charset=utf-8")
                rb.body(handleRpcHttp(ctx, cfg))
            })
            let _ = gatewayRegisterOpenClawHttpRoutes(s)
            if (cfg.controlUi.enabled) {
                gatewayRegisterControlUiRoutes(s, cfg)
            }
            if (cfg.http.endpoints.chatCompletions.enabled) {
                s.distributor.register("/v1/chat/completions", { ctx =>
                    let rb = ctx.responseBuilder
                    rb.header("content-type", "application/json; charset=utf-8")
                    rb.body(handleChatCompletions(ctx, cfg))
                })
            }
            if (cfg.http.endpoints.responses.enabled) {
                s.distributor.register("/v1/responses", { ctx =>
                    let rb = ctx.responseBuilder
                    rb.header("content-type", "application/json; charset=utf-8")
                    rb.body(handleResponses(ctx, cfg))
                })
            }
            server = Some(s)
            started = true
            spawn {
                try {
                    s.serve()
                } catch (_e: Exception) {
                    ()
                } finally {
                    synchronized(lock) {
                        started = false
                        server = None
                    }
                }
            }
        }
    }

    public static func stopIfRunning(): Unit {
        synchronized(lock) {
            if (let Some(s) <- server) {
                try {
                    s.close()
                } catch (_e: Exception) {
                    ()
                }
            }
            started = false
            server = None
        }
    }
}

public func gatewayHttpAnyEndpointEnabled(cfg: GatewayConfig): Bool {
    cfg.http.endpoints.chatCompletions.enabled || cfg.http.endpoints.responses.enabled || gatewayHttpRpcEnabled(cfg)
}

public func gatewayHttpRpcEnabled(cfg: GatewayConfig): Bool {
    cfg.remote.enabled || cfg.controlUi.enabled
}

public func gatewayHttpListenHost(cfg: GatewayConfig): String {
    if (!cfg.customBindHost.trimAscii().isEmpty()) {
        return cfg.customBindHost.trimAscii()
    }
    if (cfg.bind.trimAscii().toAsciiLower() == "lan") {
        return "127.0.0.1"
    }
    "127.0.0.1"
}

private func httpBindAddr(cfg: GatewayConfig): String {
    if (!cfg.customBindHost.trimAscii().isEmpty()) {
        return cfg.customBindHost.trimAscii()
    }
    if (cfg.bind.trimAscii().toAsciiLower() == "lan") {
        return "0.0.0.0"
    }
    "127.0.0.1"
}

public func gatewayHttpPortToUInt16(v: Int64, fallback: UInt16): UInt16 {
    if (v <= 0 || v > 65535) {
        return fallback
    }
    UInt16(v)
}

public func gatewayHttpHealthProbeJson(cfg: GatewayConfig): String {
    let root = JsonObject()
    root.put("ok", true.toJsonValue())
    root.put("status", JsonString("live"))
    root.put("gateway", GatewayHttpSurface.snapshot(cfg))
    root.toJsonString()
}

public func gatewayHttpReadyProbeJson(cfg: GatewayConfig): String {
    let root = JsonObject()
    let ready = gatewayHttpAnyEndpointEnabled(cfg)
    root.put("ready", ready.toJsonValue())
    root.put("ok", ready.toJsonValue())
    root.put("status", JsonString(if (ready) { "ready" } else { "not-ready" }))
    root.put("gateway", GatewayHttpSurface.snapshot(cfg))
    root.toJsonString()
}

public func gatewayHttpProbeMethodAllowed(method: String): Bool {
    let normalized = method.trimAscii().toAsciiUpper()
    normalized == "GET" || normalized == "HEAD"
}

public func gatewayHttpProbeResponseBody(method: String, body: String): String {
    if (method.trimAscii().toAsciiUpper() == "HEAD") {
        return ""
    }
    body
}

private func gatewayHttpReplyProbe(ctx: HttpContext, body: String): Unit {
    let method = ctx.request.method
    let rb = ctx.responseBuilder
    if (!gatewayHttpProbeMethodAllowed(method)) {
        rb.status(405)
        rb.header("allow", "GET, HEAD")
        rb.header("content-type", "text/plain; charset=utf-8")
        rb.body("Method Not Allowed")
        return
    }
    rb.header("content-type", "application/json; charset=utf-8")
    rb.body(gatewayHttpProbeResponseBody(method, body))
}

private func handleModels(ctx: HttpContext, cfg: GatewayConfig): String {
    let authz = gatewayAuthorizeHttpRequestForConfig(cfg, ctx, "http.models")
    if (!authz.ok) {
        return buildErrorJson(authz.error)
    }
    let data = JsonArray([])
    let seen = ArrayList<String>()
    for (name in collectGatewayHttpModelNames()) {
        if (seen.contains(name)) {
            continue
        }
        seen.add(name)
        let row = JsonObject()
        row.put("id", JsonString(name))
        row.put("object", JsonString("model"))
        row.put("owned_by", JsonString(resolveGatewayHttpModelOwner(name)))
        row.put("context_window", 0.toJsonValue())
        row.put("supports_chat_completions", cfg.http.endpoints.chatCompletions.enabled.toJsonValue())
        row.put("supports_responses", cfg.http.endpoints.responses.enabled.toJsonValue())
        row.put("supports_embeddings", true.toJsonValue())
        data.add(row)
    }
    let root = JsonObject()
    root.put("object", JsonString("list"))
    root.put("data", data)
    root.put("request_context", gatewayHttpRequestContext(ctx, JsonObject(), "models"))
    root.toJsonString()
}

private func handleEmbeddings(ctx: HttpContext, cfg: GatewayConfig): String {
    let authz = gatewayAuthorizeHttpRequestForConfig(cfg, ctx, "http.embeddings")
    if (!authz.ok) {
        return buildErrorJson(authz.error)
    }
    let raw = readHttpRequestBody(ctx)
    let root = parseRequestObject(raw)
    let modelName = requestModelName(ctx, root)
    let encodingFormat = jsonStringAt(root, "encoding_format").trimAscii().toAsciiLower()
    let inputs = requestEmbeddingInputs(root)
    if (inputs.isEmpty()) {
        return buildErrorJson("input must contain a non-empty string or array of strings")
    }
    let data = JsonArray([])
    var index: Int64 = 0
    for (input in inputs) {
        let row = JsonObject()
        row.put("object", JsonString("embedding"))
        row.put("index", index.toJsonValue())
        if (encodingFormat == "base64") {
            row.put("embedding", JsonString(gatewayEmbeddingBase64(input)))
        } else {
            row.put("embedding", gatewayEmbeddingVector(input))
        }
        data.add(row)
        index += 1
    }
    let out = JsonObject()
    out.put("object", JsonString("list"))
    out.put("data", data)
    out.put("model", JsonString(modelName))
    out.put("dimensions", 8.toJsonValue())
    out.put("encoding_format", JsonString(if (encodingFormat == "base64") { "base64" } else { "float" }))
    out.put("request_context", gatewayHttpRequestContext(ctx, root, "embeddings"))
    out.put("usage", gatewayEmbeddingUsage(inputs))
    out.toJsonString()
}

private func handleMcpHttp(ctx: HttpContext, cfg: GatewayConfig): String {
    let authz = gatewayAuthorizeHttpRequestForConfig(cfg, ctx, "http.mcp")
    if (!authz.ok) {
        return buildErrorJson(authz.error)
    }
    let raw = readHttpRequestBody(ctx)
    gatewayHandleMcpRequest(cfg, raw)
}

public func gatewayHandleMcpRequest(user: GatewayUserSettings, raw: String): String {
    gatewayHandleMcpRequestWithPolicy(buildGatewayConfigFromUserSettings(user), raw, user)
}

public func gatewayHandleMcpRequest(cfg: GatewayConfig, raw: String): String {
    gatewayHandleMcpRequestWithPolicy(cfg, raw, CliSettingManager.readGatewaySettings())
}

private func gatewayHandleMcpRequestWithPolicy(cfg: GatewayConfig, raw: String, user: GatewayUserSettings): String {
    let root = parseRequestObject(raw)
    let method = jsonStringAt(root, "method").trimAscii()
    let idValue = match (root.get("id")) {
        case Some(v) => v
        case None => JsonString("mcp-local")
    }
    let response = JsonObject()
    response.put("jsonrpc", JsonString("2.0"))
    response.put("id", idValue)
    if (method == "initialize") {
        let result = JsonObject()
        result.put("protocolVersion", JsonString("2025-03-26"))
        let serverInfo = JsonObject()
        serverInfo.put("name", JsonString("metis-gateway"))
        serverInfo.put("version", JsonString(CliConfig.version))
        result.put("serverInfo", serverInfo)
        let caps = JsonObject()
        let tools = JsonObject()
        tools.put("listChanged", false.toJsonValue())
        caps.put("tools", tools)
        result.put("capabilities", caps)
        response.put("result", result)
        return response.toJsonString()
    }
    if (method == "ping") {
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("serverTime", nowSeconds().toJsonValue())
        response.put("result", result)
        return response.toJsonString()
    }
    if (method == "tools/list") {
        let result = JsonObject()
        let tools = JsonArray([])
        let rpcTools = [
            ("gateway.status", "Read gateway status."),
            ("gateway.health", "Read gateway health."),
            ("gateway.readiness", "Read gateway readiness summary."),
            ("gateway.config.get", "Read one gateway config path."),
            ("gateway.config.schema.lookup", "Read one gateway config schema description."),
            ("gateway.http.status", "Read gateway HTTP runtime/status summary."),
            ("gateway.http.start", "Start gateway HTTP runtime if needed."),
            ("gateway.connect.status", "Read gateway RPC connection status."),
            ("gateway.connect.summary", "Read gateway RPC runtime summary."),
            ("gateway.connect.lifecycle", "Read gateway RPC lifecycle history."),
            ("gateway.connect.actions", "Read gateway RPC recommended runtime actions."),
            ("gateway.connect.stream.open", "Open one gateway RPC event stream session."),
            ("gateway.connect.stream.attach", "Attach to one existing gateway RPC event stream session."),
            ("gateway.connect.stream.detach", "Detach from one gateway RPC event stream session."),
            ("gateway.connect.stream.status", "Read one gateway RPC event stream status."),
            ("gateway.connect.stream.keepalive", "Refresh one gateway RPC event stream lease."),
            ("gateway.connect.stream.resume", "Resume one gateway RPC event stream from the last cursor."),
            ("gateway.connect.stream.next", "Read the next event chunk from one gateway RPC stream."),
            ("gateway.connect.stream.push", "Publish one server-side event into a gateway RPC stream."),
            ("gateway.connect.ping", "Ping gateway RPC transport/runtime."),
            ("gateway.connect.reconnect", "Recycle one gateway RPC client connection."),
            ("gateway.connect.stream.close", "Close one gateway RPC event stream."),
            ("gateway.transport.runtime", "Read gateway transport runtime summary."),
            ("gateway.transport.remote", "Read gateway remote transport runtime."),
            ("gateway.transport.lifecycle", "Read gateway transport lifecycle history."),
            ("gateway.transport.reconnect.history", "Read gateway transport reconnect history."),
            ("gateway.transport.reconnect.state", "Read gateway transport reconnect state."),
            ("gateway.transport.reconnect.window", "Read gateway transport reconnect stability window."),
            ("gateway.transport.reconnect.plan", "Read gateway transport reconnect plan."),
            ("gateway.transport.reconnect.audit", "Read gateway transport reconnect audit view."),
            ("gateway.transport.reconnect.reset", "Reset gateway transport reconnect state."),
            ("gateway.transport.stream.health", "Read gateway transport stream health."),
            ("gateway.transport.stream.audit", "Read gateway transport stream audit view."),
            ("gateway.transport.reconnect", "Reconnect gateway transport runtime."),
            ("gateway.agents.summary", "Read gateway agent summary."),
            ("gateway.agent.health", "Read one gateway agent health view."),
            ("gateway.agent.actions", "Read one gateway agent remediation/action plan."),
            ("gateway.agent.routing", "Read one gateway agent routing plan."),
            ("gateway.chat.send", "Send a gateway chat message."),
            ("gateway.agent.preview", "Preview a gateway agent invocation."),
            ("gateway.agent.invoke", "Invoke a gateway agent by session and prompt."),
            ("gateway.nodes.list", "List gateway nodes."),
            ("gateway.nodes.health", "Read one gateway node health view."),
            ("gateway.nodes.execute", "Run one step of pending gateway node work."),
            ("gateway.nodes.restart", "Restart one gateway node lifecycle."),
            ("gateway.nodes.policy.audit", "Read gateway node scheduling audit."),
            ("gateway.nodes.policy.reconcile", "Reconcile gateway node scheduling policy."),
            ("gateway.devices.health", "Read one gateway device health view."),
            ("gateway.devices.unregister", "Remove one gateway device from runtime state."),
            ("gateway.devices.policy.audit", "Read gateway device approval audit."),
            ("gateway.devices.approve", "Approve one gateway device."),
            ("gateway.devices.deny", "Deny one gateway device."),
            ("gateway.push.deliveries", "List push deliveries."),
            ("gateway.push.get", "Read one gateway push delivery."),
            ("gateway.push.retry", "Retry one recorded push delivery."),
            ("gateway.push.orchestration.audit", "Read gateway push orchestration audit."),
            ("gateway.push.orchestration.actions", "Read gateway push orchestration remediation actions."),
            ("gateway.push.orchestrate", "Run gateway push orchestration once."),
            ("gateway.canvas.audit", "Read gateway canvas pipeline audit."),
            ("gateway.canvas.actions", "Read gateway canvas remediation actions."),
            ("gateway.talk.audit", "Read gateway talk pipeline audit."),
            ("gateway.talk.actions", "Read gateway talk remediation actions."),
            ("gateway.discover.detail", "Read gateway channel and plugin discovery detail."),
            ("gateway.channels.status", "Read gateway channel status summary."),
            ("gateway.channels.list", "List gateway channels."),
            ("gateway.channels.get", "Read one gateway channel detail."),
            ("gateway.channels.runtime", "Read one gateway channel runtime view."),
            ("gateway.channels.health", "Read gateway channel health summary."),
            ("gateway.channels.audit", "Read gateway channel audit summary."),
            ("gateway.channels.bindings", "Read one gateway channel binding view."),
            ("gateway.channels.policy", "Read gateway channel policy summary."),
            ("gateway.channels.manager", "Read one gateway channel manager runtime view."),
            ("gateway.channels.health.actions", "Read gateway channel health remediation actions."),
            ("gateway.channels.start", "Start one gateway channel via host-backed runtime forwarder."),
            ("gateway.channels.stop", "Stop one gateway channel via host-backed runtime forwarder."),
            ("gateway.channels.send", "Send one test message through a gateway channel host forwarder."),
            ("gateway.channels.logout", "Log out one gateway channel account."),
            ("gateway.plugins.status", "Read gateway plugin status summary."),
            ("gateway.plugins.list", "List gateway plugins."),
            ("gateway.plugins.get", "Read one gateway plugin detail."),
            ("gateway.plugins.runtime", "Read one gateway plugin runtime view."),
            ("gateway.plugins.health", "Read gateway plugin health summary."),
            ("gateway.plugins.bindings", "Read one gateway plugin binding view."),
            ("gateway.plugins.policy", "Read gateway plugin policy summary."),
            ("gateway.plugins.manager", "Read one gateway plugin manager runtime view."),
            ("gateway.plugins.health.actions", "Read gateway plugin health remediation actions."),
            ("gateway.plugins.actions", "Read gateway plugin action discovery from the compatibility host."),
            ("gateway.plugins.approvals", "Read gateway plugin approval review state."),
            ("gateway.plugins.package_state", "Read gateway plugin package probe state."),
            ("gateway.plugins.setup", "Read gateway plugin setup state."),
            ("gateway.plugins.setup.registry", "Read gateway plugin setup registry/validation capability."),
            ("gateway.plugins.setup.apply", "Apply gateway plugin setup/config into persisted bindings."),
            ("gateway.plugins.runtime.forwarders", "Read gateway plugin host runtime forwarders."),
            ("gateway.plugins.resolve_account", "Resolve one gateway plugin account via the compatibility host."),
            ("gateway.plugins.directory", "Read one gateway plugin live directory snapshot."),
            ("gateway.plugins.targets", "Resolve one gateway plugin target against the live directory."),
            ("gateway.plugins.actions.dispatch", "Dispatch one gateway plugin action through the compatibility host."),
            ("gateway.plugins.start", "Start one gateway plugin account through the compatibility host."),
            ("gateway.plugins.stop", "Stop one gateway plugin account through the compatibility host."),
            ("gateway.plugins.send", "Send one test message through the compatibility host."),
            ("gateway.plugins.logout", "Log out one gateway plugin account through the compatibility host."),
            ("gateway.platform.runtime", "Read gateway platform runtime summary."),
            ("gateway.control_ui.summary", "Read gateway control-ui runtime summary."),
            ("gateway.control_ui.status", "Read gateway control-ui status envelope."),
            ("gateway.control_ui.contract", "Read gateway control-ui contract."),
            ("gateway.control_ui.routes", "Read gateway control-ui route contract."),
            ("gateway.control_ui.binding", "Read gateway control-ui server binding."),
            ("gateway.control_ui.runtime", "Read gateway control-ui runtime envelope."),
            ("gateway.control_ui.auth", "Read gateway control-ui auth contract."),
            ("gateway.control_ui.state", "Read gateway control-ui persisted/runtime state."),
            ("gateway.control_ui.origin_policy", "Read gateway control-ui origin policy."),
            ("gateway.control_ui.health", "Read gateway control-ui health envelope."),
            ("gateway.control_ui.assets", "Read gateway control-ui asset/runtime paths."),
            ("gateway.control_ui.start", "Start gateway control-ui runtime."),
            ("gateway.control_ui.stop", "Stop gateway control-ui runtime."),
            ("gateway.control_ui.reload", "Reload gateway control-ui runtime."),
            ("gateway.webchat.status", "Read gateway webchat runtime summary."),
            ("gateway.webchat.start", "Start gateway webchat runtime."),
            ("gateway.webchat.reload", "Reload gateway webchat runtime."),
            ("gateway.probe", "Read gateway probe diagnostics."),
            ("gateway.probe.actions", "Read gateway probe recommended actions."),
            ("gateway.probe.remediation", "Read gateway probe remediation envelope."),
            ("gateway.doctor.actions", "Read gateway doctor recommended actions."),
            ("gateway.doctor.remediation", "Read gateway doctor remediation envelope."),
            ("gateway.doctor", "Read gateway doctor diagnostics.")
        ]
        for ((toolName, description) in rpcTools) {
            let row = JsonObject()
            row.put("name", JsonString(toolName))
            row.put("description", JsonString(description))
            tools.add(row)
        }
        if (mcpConfigured()) {
            let row = JsonObject()
            row.put("name", JsonString("mcp.configured"))
            row.put("description", JsonString("MCP servers are configured in metis.json; use the CLI/runtime to enumerate loaded tools."))
            tools.add(row)
        }
        result.put("tools", tools)
        response.put("result", result)
        return response.toJsonString()
    }
    if (method == "tools/call") {
        let params = match (root.get("params")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let toolName = jsonStringAt(params, "name").trimAscii()
        let args = match (params.get("arguments")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let callResult = gatewayMcpToolCall(user, toolName, args)
        if (callResult.ok) {
            let payload = gatewayMcpNormalizedPayload(callResult.result)
            response.put("result", gatewayMcpCompatEnvelope(payload, callResult.result))
        } else {
            let error = JsonObject()
            error.put("code", (-32602).toJsonValue())
            error.put("message", JsonString(callResult.error))
            response.put("error", error)
        }
        return response.toJsonString()
    }
    let error = JsonObject()
    error.put("code", (-32601).toJsonValue())
    error.put("message", JsonString("Unsupported MCP method"))
    response.put("error", error)
    response.toJsonString()
}

private func gatewayHttpStringArrayJson(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value))
    }
    arr
}

private func gatewayHttpRuntimePolicyRoot(user: GatewayUserSettings): JsonObject {
    let root = match (MetisConfigManager.rawConfig()) {
        case Some(raw) =>
            try { JsonValue.fromStr(raw.toJsonString()).asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let gatewayObj = match (root.get("gateway")) {
        case Some(value) =>
            try { value.asObject() } catch (_: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let toolsObj = JsonObject()
    if (user.tools.allow.size > 0) {
        toolsObj.put("allow", gatewayHttpStringArrayJson(user.tools.allow))
    }
    if (user.tools.deny.size > 0) {
        toolsObj.put("deny", gatewayHttpStringArrayJson(user.tools.deny))
    }
    if (toolsObj.size() > 0) {
        gatewayObj.put("tools", toolsObj)
        root.put("gateway", gatewayObj)
    }
    root
}

private func handleRpcHttp(ctx: HttpContext, cfg: GatewayConfig): String {
    let authz = gatewayAuthorizeHttpRequestForConfig(cfg, ctx, "http.mcp")
    if (!authz.ok) {
        return GatewayProtocolResponse(false, "rpc", error: authz.error, errorCode: GATEWAY_ERROR_AUTH_FAILED).toJson().toJsonString()
    }
    let raw = readHttpRequestBody(ctx)
    let root = parseRequestObject(raw)
    let req = parseGatewayProtocolRequest(root)
    if (!validateGatewayConnectParams(req.connect)) {
        return GatewayProtocolResponse(false, req.method, requestId: req.requestId, error: "Invalid gateway connect params.", errorCode: GATEWAY_ERROR_INVALID_CONNECT).toJson().toJsonString()
    }
    gatewayHttpGatewayRequest(root).toJson().toJsonString()
}

private func handleChatCompletions(ctx: HttpContext, cfg: GatewayConfig): String {
    let authz = gatewayAuthorizeHttpRequestForConfig(cfg, ctx, "http.chat.completions")
    if (!authz.ok) {
        return buildErrorJson(authz.error)
    }
    let raw = readHttpRequestBody(ctx)
    let root = parseRequestObject(raw)
    let sessionKey = requestSessionKey(root, "gateway:http:chat-completions")
    let prompt = requestPromptForChatCompletions(root)
    if (prompt.trimAscii().isEmpty()) {
        return buildErrorJson("messages must contain a non-empty user prompt")
    }
    let answer = requestGatewayAnswer(sessionKey, prompt)
    let modelName = requestModelName(ctx, root)
    let choice = JsonObject()
    choice.put("index", 0.toJsonValue())
    let message = JsonObject()
    message.put("role", JsonString("assistant"))
    message.put("content", JsonString(trimToMaxChars(answer, cfg.webchat.chatHistoryMaxChars)))
    choice.put("message", message)
    choice.put("finish_reason", JsonString("stop"))
    let choices = JsonArray([])
    choices.add(choice)
    let usage = zeroUsageJson()
    let out = JsonObject()
    out.put("id", JsonString("chatcmpl-local-${nowSeconds()}"))
    out.put("object", JsonString("chat.completion"))
    out.put("created", nowSeconds().toJsonValue())
    out.put("model", JsonString(modelName))
    out.put("system_fingerprint", JsonString("metis-gateway"))
    out.put("choices", choices)
    out.put("request_context", gatewayHttpRequestContext(ctx, root, "chat.completions"))
    out.put("usage", usage)
    out.toJsonString()
}

private func handleResponses(ctx: HttpContext, cfg: GatewayConfig): String {
    let authz = gatewayAuthorizeHttpRequestForConfig(cfg, ctx, "http.responses")
    if (!authz.ok) {
        return buildErrorJson(authz.error)
    }
    let raw = readHttpRequestBody(ctx)
    let root = parseRequestObject(raw)
    let sessionKey = requestSessionKey(root, "gateway:http:responses")
    let prompt = requestPromptForResponses(root)
    if (prompt.trimAscii().isEmpty()) {
        return buildErrorJson("input must contain a non-empty prompt")
    }
    let answer = requestGatewayAnswer(sessionKey, prompt)
    let modelName = requestModelName(ctx, root)
    let textItem = JsonObject()
    textItem.put("type", JsonString("output_text"))
    textItem.put("text", JsonString(trimToMaxChars(answer, cfg.webchat.chatHistoryMaxChars)))
    let textItems = JsonArray([])
    textItems.add(textItem)
    let message = JsonObject()
    message.put("type", JsonString("message"))
    message.put("role", JsonString("assistant"))
    message.put("content", textItems)
    let output = JsonArray([])
    output.add(message)
    let out = JsonObject()
    out.put("id", JsonString("resp-local-${nowSeconds()}"))
    out.put("object", JsonString("response"))
    out.put("created_at", nowSeconds().toJsonValue())
    out.put("status", JsonString("completed"))
    out.put("model", JsonString(modelName))
    out.put("output", output)
    out.put("output_text", JsonString(trimToMaxChars(answer, cfg.webchat.chatHistoryMaxChars)))
    out.put("request_context", gatewayHttpRequestContext(ctx, root, "responses"))
    out.put("usage", zeroUsageJson())
    out.toJsonString()
}

private func requestGatewayAnswer(sessionKey: String, prompt: String): String {
    let result = gatewayExecuteChatTurnFromRpc(
        gatewayHttpBuildChatTurnParams(sessionKey, prompt),
        fallbackSource: GatewayIngressSource.Unknown("gateway-http")
    )
    match (result.get("answer")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None =>
            match (result.get("error")) {
                case Some(err) =>
                    try { err.asString().getValue() } catch (_: Exception) { "" }
                case None => ""
            }
    }
}

public func gatewayHttpBuildChatTurnParams(sessionKey: String, prompt: String): JsonObject {
    let request = JsonObject()
    request.put("session", JsonString(sessionKey.trimAscii()))
    request.put("text", JsonString(prompt))
    request.put("deliver", false.toJsonValue())
    let params = gatewayDashboardRequestParams(
        "dashboard.chat.send",
        request,
        source: GatewayIngressSource.Unknown("gateway-http")
    )
    params.put("channel", JsonString("gateway-http"))
    params
}

private func readHttpRequestBody(ctx: HttpContext): String {
    let chunks = ArrayList<Byte>()
    let buffer = Array<Byte>(4096, repeat: 0)
    try {
        while (true) {
            let n = ctx.request.body.read(buffer)
            if (n <= 0) {
                break
            }
            for (i in 0..n) {
                chunks.add(buffer[i])
            }
        }
        String.fromUtf8(chunks.toArray())
    } catch (_e: Exception) {
        ""
    }
}

private func parseRequestObject(raw: String): JsonObject {
    if (raw.trimAscii().isEmpty()) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(raw).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

private func parseGatewayProtocolRequest(root: JsonObject): GatewayProtocolRequest {
    let protocolVersion = jsonStringAt(root, "protocolVersion").trimAscii()
    let method = jsonStringAt(root, "method").trimAscii().toAsciiLower()
    let requestId = jsonStringAt(root, "requestId").trimAscii()
    let params = match (root.get("params")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let connect = parseGatewayConnectParams(root)
    GatewayProtocolRequest(method, connect, protocolVersion: protocolVersion, params: params, requestId: requestId)
}

private func gatewayHttpGatewayRequest(root: JsonObject): GatewayProtocolResponse {
    let req = parseGatewayProtocolRequest(root)
    GatewayServer.defaultServer().request(req)
}

private func parseGatewayConnectParams(root: JsonObject): GatewayConnectParams {
    let connectObj = match (root.get("connect")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let clientObj = match (connectObj.get("client")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    GatewayConnectParams(
        GatewayClientInfo(
            jsonStringAt(clientObj, "id").trimAscii(),
            name: jsonStringAt(clientObj, "name").trimAscii(),
            mode: jsonStringAt(clientObj, "mode").trimAscii(),
            version: jsonStringAt(clientObj, "version").trimAscii()
        ),
        transport: jsonStringAt(connectObj, "transport").trimAscii(),
        transportKind: jsonStringAt(connectObj, "transportKind").trimAscii(),
        gatewayUrl: jsonStringAt(connectObj, "gatewayUrl").trimAscii(),
        timeoutMs: jsonIntAt(connectObj, "timeoutMs", 3000),
        requestedAtMs: jsonIntAt(connectObj, "requestedAtMs", 0),
        sessionKey: jsonStringAt(connectObj, "sessionKey").trimAscii(),
        sessionHint: jsonStringAt(connectObj, "sessionHint").trimAscii(),
        connectionId: jsonStringAt(connectObj, "connectionId").trimAscii(),
        capabilities: jsonStringArrayAt(connectObj, "capabilities"),
        operatorScopes: jsonStringArrayAt(connectObj, "operatorScopes"),
        authToken: jsonStringAt(connectObj, "authToken").trimAscii(),
        authPassword: jsonStringAt(connectObj, "authPassword").trimAscii(),
        deviceId: jsonStringAt(connectObj, "deviceId").trimAscii(),
        deviceToken: jsonStringAt(connectObj, "deviceToken").trimAscii(),
        declaredUser: jsonStringAt(connectObj, "declaredUser").trimAscii()
    )
}

private func requestSessionKey(root: JsonObject, fallback: String): String {
    let direct = jsonStringAt(root, "session")
    if (!direct.isEmpty()) {
        return direct
    }
    let conversation = jsonStringAt(root, "conversation")
    if (!conversation.isEmpty()) {
        return conversation
    }
    match (root.get("metadata")) {
        case Some(v) =>
            try {
                let meta = v.asObject()
                let metaSession = jsonStringAt(meta, "session")
                if (!metaSession.isEmpty()) {
                    return metaSession
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    fallback
}

private func requestModelName(ctx: HttpContext, root: JsonObject): String {
    let fromHeader = gatewayHttpModelHeader(ctx)
    if (!fromHeader.isEmpty()) {
        return fromHeader
    }
    let fromReq = jsonStringAt(root, "model")
    if (!fromReq.isEmpty()) {
        return fromReq
    }
    CliConfig.modelOrEmpty()
}

private func gatewayHttpModelHeader(ctx: HttpContext): String {
    for (name in ["X-Metis-Model", "X-Metis-Model", "X-OpenAI-Model"]) {
        let value = ctx.request.headers.getFirst(name) ?? ctx.request.headers.getFirst(name.toAsciiLower()) ?? ""
        if (!value.trimAscii().isEmpty()) {
            return value.trimAscii()
        }
    }
    ""
}

private func requestPromptForChatCompletions(root: JsonObject): String {
    match (root.get("messages")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let parts = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let obj = item.asObject()
                        let role = jsonStringAt(obj, "role").toAsciiLower()
                        let content = chatMessageContentText(obj)
                        if (!content.trimAscii().isEmpty() && (role == "user" || role == "system")) {
                            parts.add(content)
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
                if (!parts.isEmpty()) {
                    return joinStringParts(parts, "\n\n")
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    ""
}

private func requestPromptForResponses(root: JsonObject): String {
    let direct = jsonStringAt(root, "input")
    if (!direct.isEmpty()) {
        return direct
    }
    match (root.get("input")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let parts = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let obj = item.asObject()
                        let role = jsonStringAt(obj, "role").toAsciiLower()
                        let content = responsesInputContentText(obj)
                        if (!content.trimAscii().isEmpty() && (role.isEmpty() || role == "user" || role == "system")) {
                            parts.add(content)
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
                if (!parts.isEmpty()) {
                    return joinStringParts(parts, "\n\n")
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    ""
}

private func chatMessageContentText(obj: JsonObject): String {
    let raw = jsonStringAt(obj, "content")
    if (!raw.isEmpty()) {
        return raw
    }
    match (obj.get("content")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let parts = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let contentObj = item.asObject()
                        let partText = jsonStringAt(contentObj, "text")
                        if (!partText.isEmpty()) {
                            parts.add(partText)
                        }
                        let imageUrl = resolveStructuredUrl(contentObj, "image_url")
                        if (!imageUrl.isEmpty()) {
                            parts.add("[image_url] ${imageUrl}")
                        }
                        let fileUrl = resolveStructuredUrl(contentObj, "file_url")
                        if (!fileUrl.isEmpty()) {
                            parts.add("[file_url] ${fileUrl}")
                        }
                        let fileId = jsonStringAt(contentObj, "file_id")
                        if (!fileId.isEmpty()) {
                            parts.add("[file_id] ${fileId}")
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
                joinStringParts(parts, "\n")
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func responsesInputContentText(obj: JsonObject): String {
    let raw = jsonStringAt(obj, "content")
    if (!raw.isEmpty()) {
        return raw
    }
    match (obj.get("content")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let parts = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let contentObj = item.asObject()
                        let partText = jsonStringAt(contentObj, "text")
                        if (!partText.isEmpty()) {
                            parts.add(partText)
                        }
                        let inputText = jsonStringAt(contentObj, "input_text")
                        if (!inputText.isEmpty()) {
                            parts.add(inputText)
                        }
                        let imageUrl = resolveStructuredUrl(contentObj, "image_url")
                        if (!imageUrl.isEmpty()) {
                            parts.add("[image_url] ${imageUrl}")
                        }
                        let fileUrl = resolveStructuredUrl(contentObj, "file_url")
                        if (!fileUrl.isEmpty()) {
                            parts.add("[file_url] ${fileUrl}")
                        }
                        let fileId = jsonStringAt(contentObj, "file_id")
                        if (!fileId.isEmpty()) {
                            parts.add("[file_id] ${fileId}")
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
                joinStringParts(parts, "\n")
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func jsonStringAt(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayMcpNormalizedPayload(value: JsonValue): JsonValue {
    try {
        let obj = value.asObject()
        match (obj.get("payload")) {
            case Some(v) => return v
            case None => ()
        }
        match (obj.get("result")) {
            case Some(v) => return v
            case None => ()
        }
        value
    } catch (_e: Exception) {
        value
    }
}

private func gatewayMcpCompatEnvelope(payload: JsonValue, raw: JsonValue): JsonObject {
    let result = JsonObject()
    result.put("content", payload)
    result.put("payload", payload)
    result.put("raw", raw)
    try {
        let obj = payload.asObject()
        match (obj.get("path")) {
            case Some(v) => result.put("path", v)
            case None => ()
        }
        match (obj.get("value")) {
            case Some(v) => result.put("value", v)
            case None => ()
        }
        match (obj.get("schema")) {
            case Some(v) => result.put("schema", v)
            case None => ()
        }
        match (obj.get("http")) {
            case Some(v) => result.put("http", v)
            case None => ()
        }
        match (obj.get("webchat")) {
            case Some(v) => result.put("webchat", v)
            case None => ()
        }
        match (obj.get("started")) {
            case Some(v) => result.put("started", v)
            case None => ()
        }
        match (obj.get("audit")) {
            case Some(v) =>
                result.put("audit", v)
                try {
                    let audit = v.asObject()
                    match (audit.get("summary")) {
                        case Some(summary) => result.put("summary", summary)
                        case None => ()
                    }
                } catch (_inner: Exception) {
                    ()
                }
            case None => ()
        }
    } catch (_e: Exception) {
        ()
    }
    result
}

private func jsonIntAt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let raw = v.toJsonString().trimAscii()
                let normalized = if (raw.startsWith("\"") && raw.endsWith("\"") && raw.size >= 2) {
                    raw[1..raw.size - 1]
                } else {
                    raw
                }
                Int64.parse(normalized)
            } catch (_e: Exception) {
                fallback
            }
        case None => fallback
    }
}

private func jsonStringArrayAt(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue().trimAscii()
                        if (!text.isEmpty()) {
                            out.add(text)
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_e: Exception) {
                []
            }
        case None => []
    }
}

private func resolveStructuredUrl(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let nested = v.asObject()
                jsonStringAt(nested, "url")
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func collectGatewayHttpModelNames(): Array<String> {
    let out = ArrayList<String>()
    let configuredModel = CliConfig.modelOrEmpty().trimAscii()
    if (!configuredModel.isEmpty()) {
        out.add(configuredModel)
    }
    match (CliConfig.fastModel) {
        case Some(v) =>
            if (!v.trimAscii().isEmpty()) {
                out.add(v.trimAscii())
            }
        case None => ()
    }
    for (fallback in CliConfig.fallbackModels) {
        if (!fallback.trimAscii().isEmpty() && !out.contains(fallback.trimAscii())) {
            out.add(fallback.trimAscii())
        }
    }
    out.toArray()
}

private func resolveGatewayHttpModelOwner(modelName: String): String {
    let lower = modelName.trimAscii().toAsciiLower()
    if (lower.contains(":")) {
        return lower.split(":")[0]
    }
    "metis"
}

private func requestEmbeddingInputs(root: JsonObject): Array<String> {
    let out = ArrayList<String>()
    let direct = jsonStringAt(root, "input")
    if (!direct.trimAscii().isEmpty()) {
        out.add(direct)
        return out.toArray()
    }
    match (root.get("input")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                for (item in arr.getItems()) {
                    try {
                        let text = item.asString().getValue()
                        if (!text.trimAscii().isEmpty()) {
                            out.add(text)
                        }
                    } catch (_e: Exception) {
                        try {
                            let obj = item.asObject()
                            let text = jsonStringAt(obj, "text")
                            if (!text.trimAscii().isEmpty()) {
                                out.add(text)
                            }
                        } catch (_inner: Exception) {
                            ()
                        }
                    }
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    out.toArray()
}

private func gatewayEmbeddingVector(text: String): JsonArray {
    let bytes = text.toArray()
    let slots = Array<Float64>(8, repeat: 0.0)
    if (bytes.isEmpty()) {
        return JsonArray([0.0.toJsonValue(), 0.0.toJsonValue(), 0.0.toJsonValue(), 0.0.toJsonValue(), 0.0.toJsonValue(), 0.0.toJsonValue(), 0.0.toJsonValue(), 0.0.toJsonValue()])
    }
    for (i in 0..bytes.size) {
        let bucket = i % slots.size
        slots[bucket] = slots[bucket] + Float64(bytes[i]) / 255.0
    }
    let out = JsonArray([])
    for (value in slots) {
        out.add(value.toJsonValue())
    }
    out
}

private func gatewayEmbeddingBase64(text: String): String {
    let parts = ArrayList<String>()
    let slots = Array<Float64>(8, repeat: 0.0)
    let bytes = text.toArray()
    for (i in 0..bytes.size) {
        let bucket = i % slots.size
        slots[bucket] = slots[bucket] + Float64(bytes[i]) / 255.0
    }
    for (value in slots) {
        parts.add(value.toString())
    }
    toBase64String(String.join(parts.toArray(), delimiter: ",").toArray())
}

private func gatewayEmbeddingUsage(inputs: Array<String>): JsonObject {
    var totalChars: Int64 = 0
    for (text in inputs) {
        totalChars += text.size
    }
    let usage = JsonObject()
    usage.put("prompt_tokens", totalChars.toJsonValue())
    usage.put("total_tokens", totalChars.toJsonValue())
    usage
}

private func gatewayHttpRequestContext(ctx: HttpContext, root: JsonObject, surface: String): JsonObject {
    let out = JsonObject()
    let normalizedPath = "/" + surface.replace(".", "/")
    let host = ctx.request.headers.getFirst("host") ?? "127.0.0.1"
    let attachmentRefs = gatewayHttpCollectAttachmentRefs(root)
    let attachmentSummary = gatewayHttpAttachmentSummary(attachmentRefs)
    let bodyBytes = root.toJsonString().toArray().size
    out.put("surface", JsonString(surface))
    out.put("session", JsonString(requestSessionKey(root, "gateway:http:${surface}")))
    out.put("session_source", JsonString(gatewayHttpSessionSource(root)))
    out.put("model", JsonString(requestModelName(ctx, root)))
    out.put("model_source", JsonString(gatewayHttpModelSource(ctx, root)))
    out.put("transport", JsonString("http"))
    out.put("path", JsonString(normalizedPath))
    out.put("method", JsonString(ctx.request.method))
    out.put("gateway_base_url", JsonString("http://${host}"))
    out.put("has_authorization", (!(ctx.request.headers.getFirst("authorization") ?? "").trimAscii().isEmpty()).toJsonValue())
    let attachments = JsonArray([])
    for (item in attachmentRefs) {
        attachments.add(JsonString(item))
    }
    out.put("attachments", attachments)
    out.put("attachment_count", Int64(attachments.size()).toJsonValue())
    out.put("attachment_summary", attachmentSummary)
    out.put("body_bytes", Int64(bodyBytes).toJsonValue())
    out
}

private func gatewayMcpToolCall(user: GatewayUserSettings, name: String, args: JsonObject): GatewayRpcResponse {
    let decision = runtimeToolInvocationAllowedFromRoot(
        gatewayHttpRuntimePolicyRoot(user),
        name,
        [name]
    )
    if (!decision.allowed) {
        return GatewayRpcResponse(false, "tools.call", error: "tool policy rejected `${name.trimAscii()}`: ${decision.reason}; source=${decision.policySource}")
    }
    let normalized = name.trimAscii().toAsciiLower()
    let client = gatewayBuildClient("gateway-http-mcp", "http-mcp")
    if (normalized == "gateway.status") {
        return client.request("status")
    }
    if (normalized == "gateway.health") {
        return client.request("health")
    }
    if (normalized == "gateway.readiness") {
        return client.request("readiness")
    }
    if (normalized == "gateway.config.get") {
        return client.request("config.get", params: args)
    }
    if (normalized == "gateway.config.schema.lookup") {
        return client.request("config.schema.lookup", params: args)
    }
    if (normalized == "gateway.http.status") {
        return client.request("http.status")
    }
    if (normalized == "gateway.http.start") {
        return client.request("http.start", params: args)
    }
    if (normalized == "gateway.connect.status") {
        return client.request("connect.status")
    }
    if (normalized == "gateway.connect.summary") {
        return client.request("connect.summary")
    }
    if (normalized == "gateway.connect.lifecycle") {
        return client.request("connect.lifecycle", params: args)
    }
    if (normalized == "gateway.connect.stream.open") {
        return client.request("connect.stream.open", params: args)
    }
    if (normalized == "gateway.connect.stream.status") {
        return client.request("connect.stream.status", params: args)
    }
    if (normalized == "gateway.connect.stream.keepalive") {
        return client.request("connect.stream.keepalive", params: args)
    }
    if (normalized == "gateway.connect.stream.resume") {
        return client.request("connect.stream.resume", params: args)
    }
    if (normalized == "gateway.connect.stream.next") {
        return client.request("connect.stream.next", params: args)
    }
    if (normalized == "gateway.connect.stream.push") {
        return client.request("connect.stream.push", params: args)
    }
    if (normalized == "gateway.connect.ping") {
        return client.request("connect.ping")
    }
    if (normalized == "gateway.connect.reconnect") {
        return client.request("connect.reconnect", params: args)
    }
    if (normalized == "gateway.connect.actions") {
        return client.request("connect.actions", params: args)
    }
    if (normalized == "gateway.connect.stream.attach") {
        return client.request("connect.stream.attach", params: args)
    }
    if (normalized == "gateway.connect.stream.detach") {
        return client.request("connect.stream.detach", params: args)
    }
    if (normalized == "gateway.connect.stream.close") {
        return client.request("connect.stream.close", params: args)
    }
    if (normalized == "gateway.transport.runtime") {
        return client.request("transport.runtime")
    }
    if (normalized == "gateway.transport.remote") {
        return client.request("transport.remote")
    }
    if (normalized == "gateway.transport.lifecycle") {
        return client.request("transport.lifecycle")
    }
    if (normalized == "gateway.transport.reconnect.history") {
        return client.request("transport.reconnect.history")
    }
    if (normalized == "gateway.transport.reconnect.state") {
        return client.request("transport.reconnect.state")
    }
    if (normalized == "gateway.transport.reconnect.window") {
        return client.request("transport.reconnect.window")
    }
    if (normalized == "gateway.transport.reconnect.plan") {
        return client.request("transport.reconnect.plan")
    }
    if (normalized == "gateway.transport.reconnect.audit") {
        return client.request("transport.reconnect.audit")
    }
    if (normalized == "gateway.transport.reconnect.reset") {
        return client.request("transport.reconnect.reset", params: args)
    }
    if (normalized == "gateway.transport.stream.health") {
        return client.request("transport.stream.health")
    }
    if (normalized == "gateway.transport.stream.audit") {
        return client.request("transport.stream.audit")
    }
    if (normalized == "gateway.transport.reconnect") {
        return client.request("transport.reconnect", params: args)
    }
    if (normalized == "gateway.agents.summary") {
        return client.request("agents.summary")
    }
    if (normalized == "gateway.agent.health") {
        return client.request("agent.health", params: args)
    }
    if (normalized == "gateway.agent.actions") {
        return client.request("agent.actions", params: args)
    }
    if (normalized == "gateway.agent.routing") {
        return client.request("agent.routing", params: args)
    }
    if (normalized == "gateway.chat.send") {
        return client.request("chat.send", params: args)
    }
    if (normalized == "gateway.agent.preview") {
        return client.request("agent.preview", params: args)
    }
    if (normalized == "gateway.agent.invoke") {
        return client.request("agent.invoke", params: args)
    }
    if (normalized == "gateway.nodes.list") {
        return client.request("nodes.list")
    }
    if (normalized == "gateway.nodes.health") {
        return client.request("nodes.health", params: args)
    }
    if (normalized == "gateway.nodes.execute") {
        return client.request("nodes.execute")
    }
    if (normalized == "gateway.nodes.restart") {
        return client.request("nodes.restart", params: args)
    }
    if (normalized == "gateway.nodes.policy.audit") {
        return client.request("nodes.policy.audit", params: args)
    }
    if (normalized == "gateway.nodes.policy.reconcile") {
        return client.request("nodes.policy.reconcile", params: args)
    }
    if (normalized == "gateway.devices.health") {
        return client.request("devices.health", params: args)
    }
    if (normalized == "gateway.devices.unregister") {
        return client.request("devices.unregister", params: args)
    }
    if (normalized == "gateway.devices.policy.audit") {
        return client.request("devices.policy.audit", params: args)
    }
    if (normalized == "gateway.devices.approve") {
        return client.request("devices.approve", params: args)
    }
    if (normalized == "gateway.devices.deny") {
        return client.request("devices.deny", params: args)
    }
    if (normalized == "gateway.push.deliveries") {
        return client.request("push.deliveries")
    }
    if (normalized == "gateway.push.get") {
        return client.request("push.get", params: args)
    }
    if (normalized == "gateway.push.retry") {
        return client.request("push.retry", params: args)
    }
    if (normalized == "gateway.push.orchestration.audit") {
        return client.request("push.orchestration.audit", params: args)
    }
    if (normalized == "gateway.push.orchestration.actions") {
        return client.request("push.orchestration.actions", params: args)
    }
    if (normalized == "gateway.push.orchestrate") {
        return client.request("push.orchestrate", params: args)
    }
    if (normalized == "gateway.canvas.audit") {
        return client.request("canvas.audit", params: args)
    }
    if (normalized == "gateway.canvas.actions") {
        return client.request("canvas.actions", params: args)
    }
    if (normalized == "gateway.talk.audit") {
        return client.request("talk.audit", params: args)
    }
    if (normalized == "gateway.talk.actions") {
        return client.request("talk.actions", params: args)
    }
    if (normalized == "gateway.discover.detail") {
        return client.request("discover.detail", params: args)
    }
    if (normalized == "gateway.channels.status") {
        return client.request("channels.status", params: args)
    }
    if (normalized == "gateway.channels.list") {
        return client.request("channels.list", params: args)
    }
    if (normalized == "gateway.channels.get") {
        return client.request("channels.get", params: args)
    }
    if (normalized == "gateway.channels.runtime") {
        return client.request("channels.runtime", params: args)
    }
    if (normalized == "gateway.channels.health") {
        return client.request("channels.health", params: args)
    }
    if (normalized == "gateway.channels.audit") {
        return client.request("channels.audit", params: args)
    }
    if (normalized == "gateway.channels.bindings") {
        return client.request("channels.bindings", params: args)
    }
    if (normalized == "gateway.channels.policy") {
        return client.request("channels.policy", params: args)
    }
    if (normalized == "gateway.channels.manager") {
        return client.request("channels.manager", params: args)
    }
    if (normalized == "gateway.channels.health.actions") {
        return client.request("channels.health.actions", params: args)
    }
    if (normalized == "gateway.channels.start") {
        return client.request("channels.start", params: args)
    }
    if (normalized == "gateway.channels.stop") {
        return client.request("channels.stop", params: args)
    }
    if (normalized == "gateway.channels.send") {
        return client.request("channels.send", params: args)
    }
    if (normalized == "gateway.channels.logout") {
        return client.request("channels.logout", params: args)
    }
    if (normalized == "gateway.plugins.status") {
        return client.request("plugins.status", params: args)
    }
    if (normalized == "gateway.plugins.list") {
        return client.request("plugins.list", params: args)
    }
    if (normalized == "gateway.plugins.get") {
        return client.request("plugins.get", params: args)
    }
    if (normalized == "gateway.plugins.runtime") {
        return client.request("plugins.runtime", params: args)
    }
    if (normalized == "gateway.plugins.health") {
        return client.request("plugins.health", params: args)
    }
    if (normalized == "gateway.plugins.bindings") {
        return client.request("plugins.bindings", params: args)
    }
    if (normalized == "gateway.plugins.policy") {
        return client.request("plugins.policy", params: args)
    }
    if (normalized == "gateway.plugins.manager") {
        return client.request("plugins.manager", params: args)
    }
    if (normalized == "gateway.plugins.health.actions") {
        return client.request("plugins.health.actions", params: args)
    }
    if (normalized == "gateway.plugins.actions") {
        return client.request("plugins.actions", params: args)
    }
    if (normalized == "gateway.plugins.approvals") {
        return client.request("plugins.approvals", params: args)
    }
    if (normalized == "gateway.plugins.package_state") {
        return client.request("plugins.package_state", params: args)
    }
    if (normalized == "gateway.plugins.setup") {
        return client.request("plugins.setup", params: args)
    }
    if (normalized == "gateway.plugins.setup.registry") {
        return client.request("plugins.setup.registry", params: args)
    }
    if (normalized == "gateway.plugins.setup.apply") {
        return client.request("plugins.setup.apply", params: args)
    }
    if (normalized == "gateway.plugins.runtime.forwarders") {
        return client.request("plugins.runtime.forwarders", params: args)
    }
    if (normalized == "gateway.plugins.resolve_account") {
        return client.request("plugins.resolve_account", params: args)
    }
    if (normalized == "gateway.plugins.directory") {
        return client.request("plugins.directory", params: args)
    }
    if (normalized == "gateway.plugins.targets") {
        return client.request("plugins.targets", params: args)
    }
    if (normalized == "gateway.plugins.actions.dispatch") {
        return client.request("plugins.actions.dispatch", params: args)
    }
    if (normalized == "gateway.plugins.start") {
        return client.request("plugins.start", params: args)
    }
    if (normalized == "gateway.plugins.stop") {
        return client.request("plugins.stop", params: args)
    }
    if (normalized == "gateway.plugins.send") {
        return client.request("plugins.send", params: args)
    }
    if (normalized == "gateway.plugins.logout") {
        return client.request("plugins.logout", params: args)
    }
    if (normalized == "gateway.platform.runtime") {
        return client.request("platform.runtime")
    }
    if (normalized == "gateway.control_ui.summary") {
        return client.request("control_ui.summary")
    }
    if (normalized == "gateway.control_ui.status") {
        return client.request("control_ui.status")
    }
    if (normalized == "gateway.control_ui.contract") {
        return client.request("control_ui.contract")
    }
    if (normalized == "gateway.control_ui.routes") {
        return client.request("control_ui.routes")
    }
    if (normalized == "gateway.control_ui.binding") {
        return client.request("control_ui.binding")
    }
    if (normalized == "gateway.control_ui.runtime") {
        return client.request("control_ui.runtime")
    }
    if (normalized == "gateway.control_ui.auth") {
        return client.request("control_ui.auth")
    }
    if (normalized == "gateway.control_ui.state") {
        return client.request("control_ui.state")
    }
    if (normalized == "gateway.control_ui.origin_policy") {
        return client.request("control_ui.origin_policy")
    }
    if (normalized == "gateway.control_ui.health") {
        return client.request("control_ui.health")
    }
    if (normalized == "gateway.control_ui.assets") {
        return client.request("control_ui.assets")
    }
    if (normalized == "gateway.control_ui.start") {
        return client.request("control_ui.start", params: args)
    }
    if (normalized == "gateway.control_ui.stop") {
        return client.request("control_ui.stop", params: args)
    }
    if (normalized == "gateway.control_ui.reload") {
        return client.request("control_ui.reload", params: args)
    }
    if (normalized == "gateway.webchat.status") {
        return client.request("webchat.status")
    }
    if (normalized == "gateway.webchat.start") {
        return client.request("webchat.start", params: args)
    }
    if (normalized == "gateway.webchat.reload") {
        return client.request("webchat.reload", params: args)
    }
    if (normalized == "gateway.probe") {
        return client.request("probe")
    }
    if (normalized == "gateway.probe.actions") {
        return client.request("probe.actions")
    }
    if (normalized == "gateway.probe.remediation") {
        return client.request("probe.remediation")
    }
    if (normalized == "gateway.doctor.actions") {
        return client.request("doctor.actions")
    }
    if (normalized == "gateway.doctor.remediation") {
        return client.request("doctor.remediation")
    }
    if (normalized == "gateway.doctor") {
        return client.request("doctor")
    }
    GatewayRpcResponse(false, "tools.call", error: "Unsupported MCP-over-HTTP tool: ${name}")
}

private func gatewayHttpAttachmentSummary(items: Array<String>): JsonObject {
    var imageCount: Int64 = 0
    var fileUrlCount: Int64 = 0
    var fileIdCount: Int64 = 0
    for (item in items) {
        let trimmed = item.trimAscii()
        if (trimmed.startsWith("[image_url]")) {
            imageCount += 1
        } else if (trimmed.startsWith("[file_url]")) {
            fileUrlCount += 1
        } else if (trimmed.startsWith("[file_id]")) {
            fileIdCount += 1
        }
    }
    let out = JsonObject()
    out.put("images", imageCount.toJsonValue())
    out.put("file_urls", fileUrlCount.toJsonValue())
    out.put("file_ids", fileIdCount.toJsonValue())
    out.put("total", Int64(items.size).toJsonValue())
    out
}

private func gatewayHttpModelSource(ctx: HttpContext, root: JsonObject): String {
    if (!gatewayHttpModelHeader(ctx).isEmpty()) {
        return "header"
    }
    if (!jsonStringAt(root, "model").isEmpty()) {
        return "body"
    }
    "default"
}

private func gatewayHttpSessionSource(root: JsonObject): String {
    if (!jsonStringAt(root, "session").isEmpty()) {
        return "body.session"
    }
    if (!jsonStringAt(root, "conversation").isEmpty()) {
        return "body.conversation"
    }
    match (root.get("metadata")) {
        case Some(v) =>
            try {
                let meta = v.asObject()
                if (!jsonStringAt(meta, "session").isEmpty()) {
                    return "metadata.session"
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    "fallback"
}


private func gatewayHttpCollectAttachmentRefs(root: JsonObject): Array<String> {
    let out = ArrayList<String>()
    match (root.get("messages")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                for (item in arr.getItems()) {
                    try {
                        let obj = item.asObject()
                        let text = chatMessageContentText(obj).trimAscii()
                        if (!text.isEmpty()) {
                            for (line in text.split("\n")) {
                                let trimmed = line.trimAscii()
                                if (trimmed.startsWith("[image_url]") || trimmed.startsWith("[file_url]") || trimmed.startsWith("[file_id]")) {
                                    out.add(trimmed)
                                }
                            }
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    match (root.get("input")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                for (item in arr.getItems()) {
                    try {
                        let obj = item.asObject()
                        let text = responsesInputContentText(obj).trimAscii()
                        if (!text.isEmpty()) {
                            for (line in text.split("\n")) {
                                let trimmed = line.trimAscii()
                                if (trimmed.startsWith("[image_url]") || trimmed.startsWith("[file_url]") || trimmed.startsWith("[file_id]")) {
                                    out.add(trimmed)
                                }
                            }
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    out.toArray()
}

private func mcpConfigured(): Bool {
    match (CliSettingManager.setting.mcpServers) {
        case Some(obj) => obj.toJsonString().trimAscii() != "{}"
        case None => false
    }
}

private func joinStringParts(parts: ArrayList<String>, separator: String): String {
    let sb = StringBuilder()
    var first = true
    for (part in parts) {
        if (!first) {
            sb.append(separator)
        }
        first = false
        sb.append(part)
    }
    sb.toString()
}

private func zeroUsageJson(): JsonObject {
    let usage = JsonObject()
    usage.put("prompt_tokens", 0.toJsonValue())
    usage.put("completion_tokens", 0.toJsonValue())
    usage.put("total_tokens", 0.toJsonValue())
    usage
}

private func buildErrorJson(message: String): String {
    let err = JsonObject()
    err.put("message", JsonString(message))
    let root = JsonObject()
    root.put("error", err)
    root.toJsonString()
}

private func trimToMaxChars(text: String, maxChars: Int64): String {
    if (maxChars <= 0 || text.size <= maxChars) {
        return text
    }
    text[0..maxChars]
}

private func nowSeconds(): Int64 {
    DateTime.now().toUnixTimeStamp().toSeconds()
}
