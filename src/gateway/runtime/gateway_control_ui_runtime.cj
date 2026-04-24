package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.CliConfig
import metis.gateway.model.GatewayConfig

import std.fs.{File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}
import stdx.net.http.{HttpContext, Server}

public struct GatewayControlUiSnapshot {
    public let enabled: Bool
    public let started: Bool
    public let httpUrl: String
    public let basePath: String
    public let root: String

    public init(
        enabled!: Bool,
        started!: Bool,
        httpUrl!: String,
        basePath!: String,
        root!: String
    ) {
        this.enabled = enabled
        this.started = started
        this.httpUrl = httpUrl
        this.basePath = basePath
        this.root = root
    }
}

public struct GatewayWebchatSnapshot {
    public let enabled: Bool
    public let started: Bool
    public let httpUrl: String
    public let chatHistoryMaxChars: Int64

    public init(
        enabled!: Bool,
        started!: Bool,
        httpUrl!: String,
        chatHistoryMaxChars!: Int64
    ) {
        this.enabled = enabled
        this.started = started
        this.httpUrl = httpUrl
        this.chatHistoryMaxChars = chatHistoryMaxChars
    }
}

public class GatewayControlUiRuntime {
    public static func startIfEnabled(cfg: GatewayConfig): Bool {
        if (!cfg.controlUi.enabled) {
            persistControlUiRuntimeState(cfg, false)
            return false
        }
        GatewayHttpSurface.startIfNeeded(cfg)
        let started = GatewayHttpSurface.isRunning()
        persistControlUiRuntimeState(cfg, started)
        started
    }

    public static func startWebchatIfEnabled(cfg: GatewayConfig): Bool {
        if (!cfg.controlUi.enabled) {
            persistControlUiRuntimeState(cfg, false)
            return false
        }
        GatewayHttpSurface.startIfNeeded(cfg)
        let started = GatewayHttpSurface.isRunning()
        persistControlUiRuntimeState(cfg, started)
        started
    }

    public static func stopIfRunning(cfg: GatewayConfig): Bool {
        // Control UI is embedded in the shared gateway HTTP surface.
        // It cannot be stopped independently without also affecting RPC/HTTP endpoints.
        persistControlUiRuntimeState(cfg, GatewayHttpSurface.isRunning() && cfg.controlUi.enabled)
        false
    }

    public static func reloadIfEnabled(cfg: GatewayConfig): Bool {
        if (!cfg.controlUi.enabled) {
            persistControlUiRuntimeState(cfg, false)
            return false
        }
        let started = GatewayHttpSurface.isRunning()
        persistControlUiRuntimeState(cfg, started)
        started
    }

    public static func controlUiSnapshot(cfg: GatewayConfig): GatewayControlUiSnapshot {
        let contract = controlUiContract(cfg)
        let binding = controlUiBinding(cfg)
        GatewayControlUiSnapshot(
            enabled: cfg.controlUi.enabled,
            started: GatewayHttpSurface.isRunning() && cfg.controlUi.enabled,
            httpUrl: binding.httpUrl,
            basePath: contract.basePath,
            root: cfg.controlUi.root
        )
    }

    public static func webchatSnapshot(cfg: GatewayConfig): GatewayWebchatSnapshot {
        let binding = controlUiBinding(cfg)
        GatewayWebchatSnapshot(
            enabled: cfg.controlUi.enabled,
            started: GatewayHttpSurface.isRunning() && cfg.controlUi.enabled,
            httpUrl: binding.httpUrl,
            chatHistoryMaxChars: cfg.webchat.chatHistoryMaxChars
        )
    }

    public static func controlUiContract(cfg: GatewayConfig): GatewayControlUiContract {
        let basePath = gatewayControlUiNormalizeBasePath(cfg.controlUi.basePath)
        let rootPath = if (basePath.isEmpty()) { "/" } else { basePath }
        let chatPath = if (basePath.isEmpty()) { "/chat" } else { basePath + "/chat" }
        let apiPrefix = if (basePath.isEmpty()) { "/api" } else { basePath + "/api" }
        let assetsPath = if (basePath.isEmpty()) { "/assets" } else { basePath + "/assets" }
        let spaRoutes = gatewayControlUiSpaRoutes(basePath)
        let routes = Array<String>(spaRoutes.size + 9, repeat: "")
        for (i in 0..spaRoutes.size) {
            routes[i] = spaRoutes[i]
        }
        routes[spaRoutes.size] = if (basePath.isEmpty()) { "/ws" } else { basePath + "/ws" }
        routes[spaRoutes.size + 1] = apiPrefix + "/status"
        routes[spaRoutes.size + 2] = apiPrefix + "/chat/history"
        routes[spaRoutes.size + 3] = apiPrefix + "/chat/send"
        routes[spaRoutes.size + 4] = apiPrefix + "/models"
        routes[spaRoutes.size + 5] = apiPrefix + "/model"
        routes[spaRoutes.size + 6] = apiPrefix + "/skills"
        routes[spaRoutes.size + 7] = apiPrefix + "/cron"
        routes[spaRoutes.size + 8] = assetsPath
        GatewayControlUiContract(
            basePath: basePath,
            rootPath: rootPath,
            chatPath: chatPath,
            apiPrefix: apiPrefix,
            assetsPath: assetsPath,
            routes: routes,
            allowedOrigins: cfg.controlUi.allowedOrigins,
            allowHostHeaderOriginFallback: cfg.controlUi.dangerouslyAllowHostHeaderOriginFallback,
            allowInsecureAuth: cfg.controlUi.allowInsecureAuth,
            deviceAuthMode: if (cfg.controlUi.dangerouslyDisableDeviceAuth) { "disabled" } else { "required" },
            authMode: if (cfg.controlUi.allowInsecureAuth) { "optional" } else { "required" },
            csp: gatewayControlUiCsp(cfg)
        )
    }

    public static func controlUiBinding(cfg: GatewayConfig): GatewayControlUiBinding {
        let contract = controlUiContract(cfg)
        let host = gatewayHttpListenHost(cfg)
        let port = gatewayHttpPortToUInt16(cfg.port, 8080u16)
        let httpUrl = "http://${host}:${port}${if (contract.basePath.isEmpty()) { "/" } else { contract.basePath + "/" }}"
        let wsUrl = "ws://${host}:${port}${if (contract.basePath.isEmpty()) { "/ws" } else { contract.basePath + "/ws" }}"
        GatewayControlUiBinding(
            host: host,
            port: port,
            httpUrl: httpUrl,
            wsUrl: wsUrl,
            basePath: contract.basePath,
            apiPrefix: contract.apiPrefix,
            assetsPath: contract.assetsPath
        )
    }

    public static func controlUiRouteBindings(cfg: GatewayConfig): Array<String> {
        let contract = controlUiContract(cfg)
        let routes = Array<String>(contract.routes.size, repeat: "")
        for (i in 0..contract.routes.size) {
            routes[i] = contract.routes[i]
        }
        routes
    }

    public static func registerRoute(server: Server, cfg: GatewayConfig, path: String, handler: (HttpContext) -> Unit): Unit {
        let basePath = controlUiContract(cfg).basePath
        server.distributor.register(path, handler)
        if (!basePath.isEmpty()) {
            let normalized = if (path == "/") { basePath } else { basePath + path }
            server.distributor.register(normalized, handler)
        }
    }
}

public func gatewayControlUiSpaRoutes(basePath: String): Array<String> {
    let tabs = [
        "/",
        "/chat",
        "/overview",
        "/channels",
        "/instances",
        "/sessions",
        "/usage",
        "/cron",
        "/agents",
        "/skills",
        "/nodes",
        "/dreaming",
        "/config",
        "/communications",
        "/appearance",
        "/automation",
        "/infrastructure",
        "/ai-agents",
        "/debug",
        "/logs"
    ]
    let normalizedBase = gatewayControlUiNormalizeBasePath(basePath)
    let routes = Array<String>(tabs.size, repeat: "")
    for (i in 0..tabs.size) {
        let path = tabs[i]
        routes[i] = if (normalizedBase.isEmpty()) {
            path
        } else if (path == "/") {
            normalizedBase
        } else {
            normalizedBase + path
        }
    }
    routes
}

public func gatewayControlUiSnapshotJson(cfg: GatewayConfig): JsonObject {
    let snapshot = GatewayControlUiRuntime.controlUiSnapshot(cfg)
    let out = JsonObject()
    out.put("enabled", snapshot.enabled.toJsonValue())
    out.put("started", snapshot.started.toJsonValue())
    out.put("httpUrl", JsonString(snapshot.httpUrl))
    out.put("basePath", JsonString(snapshot.basePath))
    out.put("root", JsonString(snapshot.root))
    let contract = GatewayControlUiRuntime.controlUiContract(cfg)
    out.put("allowedOrigins", contract.allowedOrigins.toJsonValue())
    out.put("allowHostHeaderOriginFallback", contract.allowHostHeaderOriginFallback.toJsonValue())
    out.put("allowInsecureAuth", contract.allowInsecureAuth.toJsonValue())
    out.put("deviceAuthMode", JsonString(contract.deviceAuthMode))
    out.put("authMode", JsonString(contract.authMode))
    out.put("contract", gatewayControlUiContractJson(cfg))
    out.put("rootState", gatewayControlUiRootStateJson(cfg))
    out.put("assetMode", JsonString(gatewayControlUiAssetMode(cfg)))
    out.put("statePath", JsonString(gatewayControlUiRuntimeStatePath().toString()))
    out
}

public func gatewayWebchatSnapshotJson(cfg: GatewayConfig): JsonObject {
    let snapshot = GatewayControlUiRuntime.webchatSnapshot(cfg)
    let out = JsonObject()
    out.put("enabled", snapshot.enabled.toJsonValue())
    out.put("started", snapshot.started.toJsonValue())
    out.put("httpUrl", JsonString(snapshot.httpUrl))
    out.put("chatHistoryMaxChars", snapshot.chatHistoryMaxChars.toJsonValue())
    out.put("basePath", JsonString(cfg.controlUi.basePath))
    out
}

public func gatewayControlUiRuntimeStatusJson(cfg: GatewayConfig): JsonObject {
    let snapshot = gatewayControlUiSnapshotJson(cfg)
    let contract = gatewayControlUiContractJson(cfg)
    let binding = gatewayControlUiBindingJson(cfg)
    let state = gatewayControlUiRuntimeStateJson()
    let result = JsonObject()
    result.put("controlUi", snapshot)
    result.put("contract", contract)
    result.put("binding", binding)
    result.put("state", state)
    let auth = gatewayControlUiOriginPolicyJson(cfg)
    result.put("auth", auth)
    let summary = JsonObject()
    summary.put("healthy", gatewayControlUiRuntimeHealthy(cfg).toJsonValue())
    summary.put("started", snapshot.get("started") ?? false.toJsonValue())
    summary.put("enabled", snapshot.get("enabled") ?? false.toJsonValue())
    summary.put("httpUrl", binding.get("httpUrl") ?? JsonString(""))
    summary.put("assetsPath", binding.get("assetsPath") ?? JsonString(""))
    summary.put("assetMode", snapshot.get("assetMode") ?? JsonString("inline-fallback"))
    summary.put("rootState", snapshot.get("rootState") ?? JsonObject())
    result.put("summary", summary)
    result
}

public func gatewayControlUiRuntimeJson(cfg: GatewayConfig): JsonObject {
    let out = JsonObject()
    out.put("binding", gatewayControlUiBindingJson(cfg))
    out.put("contract", gatewayControlUiContractJson(cfg))
    out.put("originPolicy", gatewayControlUiOriginPolicyJson(cfg))
    out.put("state", gatewayControlUiRuntimeStateJson())
    out.put("healthy", gatewayControlUiRuntimeHealthy(cfg).toJsonValue())
    out.put("statePath", JsonString(gatewayControlUiRuntimeStatePath().toString()))
    out
}

public func gatewayControlUiRuntimeStatePath(): Path {
    CliConfig.dotDir.join("gateway-control-ui-state.json")
}

private func persistControlUiRuntimeState(cfg: GatewayConfig, started: Bool): Unit {
    let root = JsonObject()
    root.put("started", started.toJsonValue())
    root.put("updatedAtMs", (DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000).toJsonValue())
    root.put("controlUi", gatewayControlUiSnapshotJson(cfg))
    root.put("webchat", gatewayWebchatSnapshotJson(cfg))
    File.writeTo(gatewayControlUiRuntimeStatePath(), root.toJsonString().toArray())
}

public func gatewayControlUiRuntimeStateJson(): JsonObject {
    let path = gatewayControlUiRuntimeStatePath()
    if (!exists(path)) {
        return JsonObject()
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
    } catch (_e: Exception) {
        JsonObject()
    }
}

public func gatewayControlUiRuntimeHealthy(cfg: GatewayConfig): Bool {
    let snapshot = gatewayControlUiSnapshotJson(cfg)
    let enabled = match (snapshot.get("enabled")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_inner: Exception) { false }
        case None => false
    }
    let started = match (snapshot.get("started")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_inner: Exception) { false }
        case None => false
    }
    !enabled || started
}
