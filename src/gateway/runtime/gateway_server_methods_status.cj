package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.config.{buildGatewayConfigFromUserSettings, mergeGatewayUserSettings}
import metis.gateway.model.GatewayConfig

import std.collection.HashMap
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewayStatusServerRuntime(): JsonObject {
    gatewayServerRuntimeSnapshot()
}

private func gatewayStatusTransportRuntime(user: GatewayUserSettings): JsonObject {
    gatewayTransportRuntimeSnapshot(user)
}

private func gatewayStatusTransportSnapshot(runtime: JsonObject): JsonObject {
    match (runtime.get("transport")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayStatusJsonObject(value: JsonValue): JsonObject {
    try { value.asObject() } catch (_e: Exception) { JsonObject() }
}

private func gatewayStatusConfig(user: GatewayUserSettings): GatewayConfig {
    buildGatewayConfigFromUserSettings(user)
}

private func gatewayStatusHttp(cfg: GatewayConfig): JsonObject {
    GatewayHttpSurface.snapshot(cfg)
}

private func gatewayStatusPlatform(cfg: GatewayConfig): JsonObject {
    gatewayPlatformSnapshot(cfg)
}

public func buildGatewayExternalSurfaceJson(user: GatewayUserSettings): JsonObject {
    let cfg = gatewayStatusConfig(user)
    let surfaces = JsonObject()

    surfaces.put("controlUi", gatewayControlUiSnapshotJson(cfg))
    surfaces.put("webchat", gatewayWebchatSnapshotJson(cfg))

    let http = JsonObject()
    let runtimeHttp = gatewayStatusHttp(cfg)
    http.put("chatCompletionsEnabled", cfg.http.endpoints.chatCompletions.enabled.toJsonValue())
    http.put("responsesEnabled", cfg.http.endpoints.responses.enabled.toJsonValue())
    http.put("chatCompletionsPath", JsonString("/v1/chat/completions"))
    http.put("responsesPath", JsonString("/v1/responses"))
    http.put("modelsPath", JsonString("/v1/models"))
    http.put("embeddingsPath", JsonString("/v1/embeddings"))
    http.put("mcpPath", JsonString("/mcp"))
    http.put("rpcPath", JsonString("/rpc"))
    http.put("baseUrl", runtimeHttp.get("baseUrl") ?? JsonString(""))
    http.put("health", runtimeHttp.get("health") ?? JsonString(""))
    http.put("healthz", runtimeHttp.get("healthz") ?? JsonString(""))
    http.put("ready", runtimeHttp.get("ready") ?? JsonString(""))
    http.put("readyz", runtimeHttp.get("readyz") ?? JsonString(""))
    http.put("probePaths", runtimeHttp.get("probePaths") ?? JsonArray([]))
    http.put("started", runtimeHttp.get("started") ?? false.toJsonValue())
    surfaces.put("http", http)

    let health = JsonObject()
    health.put("feishuHealthz", JsonString("http://${cfg.feishu.webhookHost}:${cfg.feishu.webhookPort}/healthz"))
    health.put("qqHealthz", JsonString("http://${cfg.qq.webhookHost}:${cfg.qq.webhookPort}/healthz"))
    health.put("runtimeStatePath", JsonString(gatewayRuntimeStatePath().toString()))
    surfaces.put("health", health)
    surfaces
}

private func stringMapToJson(map: HashMap<String, String>): JsonObject {
    let obj = JsonObject()
    for ((k, v) in map) {
        obj.put(k, JsonString(v))
    }
    obj
}

public func buildGatewayRpcStatusJson(user: GatewayUserSettings): JsonObject {
    let cfg = gatewayStatusConfig(user)
    let (fCfg, qCfg, tCfg) = mergeGatewayUserSettings(user)
    let rpc = gatewayStatusServerRuntime()
    let result = JsonObject()
    result.put("enabled", user.enabled.toJsonValue())
    result.put("port", cfg.port.toJsonValue())
    result.put("mode", JsonString(cfg.mode))
    result.put("bind", JsonString(cfg.bind))
    result.put("customBindHost", JsonString(cfg.customBindHost))

    let session = JsonObject()
    session.put("dmScope", JsonString(user.session.dmScope))
    session.put("persistenceEnabled", user.session.persistenceEnabled.toJsonValue())
    result.put("session", session)

    let feishu = JsonObject()
    feishu.put("enabled", user.feishu.enabled.toJsonValue())
    feishu.put("appId", JsonString(user.feishu.appId))
    feishu.put("receiveMode", JsonString(user.feishu.receiveMode))
    feishu.put("groupSessionScope", JsonString(user.feishu.groupSessionScope))
    feishu.put("replyInThread", JsonString(user.feishu.replyInThread))
    feishu.put("effectiveEnabled", fCfg.enabled.toJsonValue())
    result.put("feishu", feishu)

    let qq = JsonObject()
    qq.put("enabled", user.qq.enabled.toJsonValue())
    qq.put("mode", JsonString(user.qq.mode))
    qq.put("appId", JsonString(user.qq.appId))
    qq.put("configured", (!(user.qq.appId.trimAscii().isEmpty() || user.qq.appSecret.trimAscii().isEmpty())).toJsonValue())
    qq.put("transport", JsonString("official_ws"))
    qq.put("supportedInbound", JsonString("c2c_message,group_at_message,group_message_with_mention"))
    qq.put("effectiveEnabled", qCfg.enabled.toJsonValue())
    result.put("qq", qq)

    let discovery = JsonObject()
    discovery.put("wideAreaEnabled", cfg.discovery.wideArea.enabled.toJsonValue())
    discovery.put("wideAreaDomain", JsonString(cfg.discovery.wideArea.domain))
    discovery.put("mdnsMode", JsonString(cfg.discovery.mdns.mode))
    result.put("discovery", discovery)

    let http = JsonObject()
    http.put("chatCompletionsEnabled", cfg.http.endpoints.chatCompletions.enabled.toJsonValue())
    http.put("responsesEnabled", cfg.http.endpoints.responses.enabled.toJsonValue())
    result.put("http", http)

    let controlUi = JsonObject()
    controlUi.put("enabled", cfg.controlUi.enabled.toJsonValue())
    controlUi.put("basePath", JsonString(cfg.controlUi.basePath))
    controlUi.put("root", JsonString(cfg.controlUi.root))
    controlUi.put("assetMode", gatewayControlUiSnapshotJson(cfg).get("assetMode") ?? JsonString("inline-fallback"))
    controlUi.put("rootState", gatewayControlUiRootStateJson(cfg))
    result.put("controlUi", controlUi)

    let transport = JsonObject()
    transport.put("preferred", JsonString(gatewayPreferredTransportFromSettings(user)))
    transport.put("gatewayUrl", JsonString(gatewayPreferredGatewayUrlFromSettings(user)))
    transport.put("hasRemoteConfig", user.remote.enabled.toJsonValue())
    transport.put("remoteMode", JsonString(user.remote.transport))
    transport.put("runtime", gatewayStatusTransportRuntime(user))
    result.put("transportSummary", transport)

    let plugins = JsonArray([])
    for (p in user.gatewayPlugins) {
        let row = JsonObject()
        row.put("id", JsonString(p.id))
        row.put("enabled", p.enabled.toJsonValue())
        plugins.add(row)
    }
    result.put("gatewayPlugins", plugins)
    result.put("hasAnyEnabledChannel", gatewayHasAnyEnabledChannel(user).toJsonValue())
    result.put("runtime", gatewayRuntimeSnapshot())
    result.put("rpc", rpc)
    result.put("serveLockPresent", gatewayAnotherServeInstanceSeemsRunning().toJsonValue())

    let auth = JsonObject()
    auth.put("mode", JsonString(cfg.auth.mode))
    auth.put("allowTailscale", cfg.auth.allowTailscale.toJsonValue())
    auth.put("hasToken", cfg.auth.token.isSome().toJsonValue())
    auth.put("hasPassword", cfg.auth.password.isSome().toJsonValue())
    auth.put("trustedProxyUserHeader", JsonString(cfg.auth.trustedProxy.userHeader))
    result.put("authSummary", auth)

    let readiness = JsonObject()
    let ready = user.enabled && gatewayHasAnyEnabledChannel(user)
    readiness.put("ready", ready.toJsonValue())
    readiness.put("masterEnabled", user.enabled.toJsonValue())
    readiness.put("hasEnabledChannel", gatewayHasAnyEnabledChannel(user).toJsonValue())
    readiness.put("rpcConnected", rpc.get("connected") ?? false.toJsonValue())
    readiness.put("reason", JsonString(if (ready) { "ok" } else if (!user.enabled) { "gateway-disabled" } else { "no-enabled-channel" }))
    result.put("readiness", readiness)

    result.put("surfaces", buildGatewayExternalSurfaceJson(user))
    result.put("platform", gatewayStatusPlatform(cfg))
    result
}

public func handleGatewayStatusFamily(method: String, user: GatewayUserSettings): Option<GatewayRpcResponse> {
    if (method == "status") {
        return Some(GatewayRpcResponse(true, method, result: buildGatewayRpcStatusJson(user)))
    }
    if (method == "health") {
        let full = buildGatewayRpcStatusJson(user)
        let fullRpc = gatewayStatusJsonObject(full.get("rpc") ?? JsonObject())
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("ready", full.get("readiness") ?? JsonObject())
        result.put("runtime", full.get("runtime") ?? JsonObject())
        result.put("rpc", full.get("rpc") ?? JsonObject())
        result.put("transport", gatewayStatusTransportSnapshot(fullRpc))
        result.put("authSummary", full.get("authSummary") ?? JsonObject())
        result.put("hasAnyEnabledChannel", full.get("hasAnyEnabledChannel") ?? false.toJsonValue())
        result.put("surfaces", full.get("surfaces") ?? JsonObject())
        result.put("platform", full.get("platform") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "readiness") {
        let full = buildGatewayRpcStatusJson(user)
        let fullRpc = gatewayStatusJsonObject(full.get("rpc") ?? JsonObject())
        let result = JsonObject()
        result.put("readiness", full.get("readiness") ?? JsonObject())
        result.put("runtime", full.get("runtime") ?? JsonObject())
        result.put("rpc", full.get("rpc") ?? JsonObject())
        result.put("transport", gatewayStatusTransportSnapshot(fullRpc))
        result.put("surfaces", full.get("surfaces") ?? JsonObject())
        result.put("platform", full.get("platform") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    None
}

public func gatewayRpcConfigValueAtPath(user: GatewayUserSettings, path: String): Option<JsonValue> {
    let normalized = path.trimAscii().toAsciiLower()
    if (normalized.isEmpty() || normalized == "gateway") {
        return Some(user.toJsonValue())
    }
    match (normalized) {
        case "enabled" | "gateway.enabled" => Some(user.enabled.toJsonValue())
        case "port" | "gateway.port" => Some(user.port.toJsonValue())
        case "mode" | "gateway.mode" => Some(JsonString(user.mode))
        case "bind" | "gateway.bind" => Some(JsonString(user.bind))
        case "custombindhost" | "gateway.custombindhost" => Some(JsonString(user.customBindHost))
        case "session" | "gateway.session" => Some(user.session.toJsonValue())
        case "session.dmscope" | "gateway.session.dmscope" => Some(JsonString(user.session.dmScope))
        case "session.persistenceenabled" | "gateway.session.persistenceenabled" => Some(user.session.persistenceEnabled.toJsonValue())
        case "feishu" | "gateway.feishu" => Some(user.feishu.toJsonValue())
        case "qq" | "gateway.qq" => Some(user.qq.toJsonValue())
        case "telegram" | "gateway.telegram" => Some(user.telegram.toJsonValue())
        case "tools" | "gateway.tools" => Some(user.tools.toJsonValue())
        case "gatewayplugins" | "gateway.gatewayplugins" => Some(user.gatewayPlugins.toJsonValue())
        case "channelmodels" | "gateway.channelmodels" => Some(stringMapToJson(user.channelModels))
        case "tls" | "gateway.tls" => Some(user.tls.toJsonValue())
        case "discovery" | "gateway.discovery" => Some(user.discovery.toJsonValue())
        case "controlui" | "gateway.controlui" => Some(user.controlUi.toJsonValue())
        case "auth" | "gateway.auth" => Some(user.auth.toJsonValue())
        case "tailscale" | "gateway.tailscale" => Some(user.tailscale.toJsonValue())
        case "remote" | "gateway.remote" => Some(user.remote.toJsonValue())
        case "reload" | "gateway.reload" => Some(user.reload.toJsonValue())
        case "http" | "gateway.http" => Some(user.http.toJsonValue())
        case "push" | "gateway.push" => Some(user.push.toJsonValue())
        case "nodes" | "gateway.nodes" => Some(user.nodes.toJsonValue())
        case "canvas" | "gateway.canvas" => Some(user.canvas.toJsonValue())
        case "talk" | "gateway.talk" => Some(user.talk.toJsonValue())
        case "webchat" | "gateway.webchat" => Some(user.webchat.toJsonValue())
        case "trustedproxies" | "gateway.trustedproxies" => Some(user.trustedProxies.toJsonValue())
        case "allowrealipfallback" | "gateway.allowrealipfallback" => Some(user.allowRealIpFallback.toJsonValue())
        case "channelsextra" | "gateway.channelsextra" =>
            match (user.channelsExtra) {
                case Some(v) => Some(v)
                case None => Some(JsonObject())
            }
        case _ => None
    }
}

public func gatewayRpcSchemaLookup(path: String): String {
    let normalized = path.trimAscii().toAsciiLower()
    match (normalized) {
        case "" | "gateway" =>
            "gateway: root object. Keys include enabled, port, mode, bind, session, feishu, qq, telegram, discovery, tls, controlUi, auth, remote, reload, http, push, nodes, canvas, talk, tools, gatewayPlugins, channelsExtra."
        case "enabled" | "gateway.enabled" =>
            "gateway.enabled: Bool. Master switch for the gateway runtime."
        case "port" | "gateway.port" =>
            "gateway.port: Int64. Primary gateway listen port."
        case "mode" | "gateway.mode" =>
            "gateway.mode: String. Gateway mode hint."
        case "bind" | "gateway.bind" =>
            "gateway.bind: String. Bind policy such as loopback, lan, auto, custom, or tailnet."
        case "session" | "gateway.session" =>
            "gateway.session: object. Keys: dmScope (String), persistenceEnabled (Bool)."
        case "feishu" | "gateway.feishu" =>
            "gateway.feishu: object. Feishu channel configuration."
        case "qq" | "gateway.qq" =>
            "gateway.qq: object. QQ channel configuration."
        case "telegram" | "gateway.telegram" =>
            "gateway.telegram: object. Telegram Bot API channel configuration."
        case "discovery" | "gateway.discovery" =>
            "gateway.discovery: object. Keys: wideArea, mdns."
        case "tls" | "gateway.tls" =>
            "gateway.tls: object. Keys: enabled, autoGenerate, certPath, keyPath, caPath."
        case "controlui" | "gateway.controlui" =>
            "gateway.controlUi: object. Control UI config surface."
        case "auth" | "gateway.auth" =>
            "gateway.auth: object. Keys: mode, token, password, allowTailscale, rateLimit, trustedProxy."
        case "http" | "gateway.http" =>
            "gateway.http: object. HTTP endpoints and security headers."
        case "gatewayplugins" | "gateway.gatewayplugins" =>
            "gateway.gatewayPlugins: array<object>. Each item has id and enabled."
        case _ =>
            "Unknown gateway config path: ${path.trimAscii()}"
    }
}
