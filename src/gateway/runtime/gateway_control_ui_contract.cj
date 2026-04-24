package metis.gateway.runtime

import magic.jsonable.*

import metis.gateway.{gatewayRuntimeEffectiveAuthPasswordString, gatewayRuntimeEffectiveAuthTokenString}
import metis.gateway.model.GatewayConfig
import metis.gateway.security.{gatewayDefaultControlUiDeviceId, gatewayDefaultControlUiDeviceToken}

import std.collection.ArrayList
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

public const CONTROL_UI_BOOTSTRAP_CONFIG_PATH: String = "/__metis/control-ui-config.json"
public const CONTROL_UI_AUTH_CONFIG_PATH: String = "/__metis/control-ui-auth.json"

private func gatewayControlUiOptionString(value: Option<JsonValue>): String {
    match (value) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

public struct GatewayControlUiContract {
    public let basePath: String
    public let rootPath: String
    public let chatPath: String
    public let apiPrefix: String
    public let assetsPath: String
    public let routes: Array<String>
    public let allowedOrigins: Array<String>
    public let allowHostHeaderOriginFallback: Bool
    public let allowInsecureAuth: Bool
    public let deviceAuthMode: String
    public let authMode: String
    public let csp: String

    public init(
        basePath!: String,
        rootPath!: String,
        chatPath!: String,
        apiPrefix!: String,
        assetsPath!: String,
        routes!: Array<String>,
        allowedOrigins!: Array<String>,
        allowHostHeaderOriginFallback!: Bool,
        allowInsecureAuth!: Bool,
        deviceAuthMode!: String,
        authMode!: String,
        csp!: String
    ) {
        this.basePath = basePath
        this.rootPath = rootPath
        this.chatPath = chatPath
        this.apiPrefix = apiPrefix
        this.assetsPath = assetsPath
        this.routes = routes
        this.allowedOrigins = allowedOrigins
        this.allowHostHeaderOriginFallback = allowHostHeaderOriginFallback
        this.allowInsecureAuth = allowInsecureAuth
        this.deviceAuthMode = deviceAuthMode
        this.authMode = authMode
        this.csp = csp
    }
}

public struct GatewayControlUiBinding {
    public let host: String
    public let port: UInt16
    public let httpUrl: String
    public let wsUrl: String
    public let basePath: String
    public let apiPrefix: String
    public let assetsPath: String

    public init(
        host!: String,
        port!: UInt16,
        httpUrl!: String,
        wsUrl!: String,
        basePath!: String,
        apiPrefix!: String,
        assetsPath!: String
    ) {
        this.host = host
        this.port = port
        this.httpUrl = httpUrl
        this.wsUrl = wsUrl
        this.basePath = basePath
        this.apiPrefix = apiPrefix
        this.assetsPath = assetsPath
    }
}

public func gatewayControlUiNormalizeBasePath(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty() || trimmed == "/") {
        return ""
    }
    let prefixed = if (trimmed.startsWith("/")) { trimmed } else { "/" + trimmed }
    if (prefixed.endsWith("/")) {
        prefixed[0..prefixed.size - 1]
    } else {
        prefixed
    }
}

private func gatewayControlUiJoinStrings(values: Array<String>, sep: String): String {
    let sb = StringBuilder()
    var first = true
    for (value in values) {
        if (!first) {
            sb.append(sep)
        }
        first = false
        sb.append(value)
    }
    sb.toString()
}

private func gatewayControlUiUniquePush(out: ArrayList<String>, value: String): Unit {
    let text = value.trimAscii()
    if (text.isEmpty() || out.contains(text)) {
        return
    }
    out.add(text)
}

public func gatewayControlUiCsp(cfg: GatewayConfig): String {
    let selfToken = "'self'"
    let host = gatewayHttpListenHost(cfg)
    let httpOrigin = "http://${host}:${cfg.port}"
    let httpsOrigin = "https://${host}:${cfg.port}"
    let wsOrigin = "ws://${host}:${cfg.port}"
    let wssOrigin = "wss://${host}:${cfg.port}"
    let connectOrigins = ArrayList<String>()
    gatewayControlUiUniquePush(connectOrigins, selfToken)
    gatewayControlUiUniquePush(connectOrigins, httpOrigin)
    gatewayControlUiUniquePush(connectOrigins, httpsOrigin)
    gatewayControlUiUniquePush(connectOrigins, wsOrigin)
    gatewayControlUiUniquePush(connectOrigins, wssOrigin)
    for (origin in cfg.controlUi.allowedOrigins) {
        gatewayControlUiUniquePush(connectOrigins, origin)
    }
    let connectSrc = gatewayControlUiJoinStrings(connectOrigins.toArray(), " ")
    "default-src ${selfToken}; connect-src ${connectSrc}; img-src ${selfToken} data: blob:; style-src ${selfToken} 'unsafe-inline'; script-src ${selfToken} 'unsafe-inline';"
}

public func gatewayControlUiContractJson(cfg: GatewayConfig): JsonObject {
    let contract = GatewayControlUiRuntime.controlUiContract(cfg)
    let out = JsonObject()
    out.put("basePath", JsonString(contract.basePath))
    out.put("rootPath", JsonString(contract.rootPath))
    out.put("chatPath", JsonString(contract.chatPath))
    out.put("apiPrefix", JsonString(contract.apiPrefix))
    out.put("assetsPath", JsonString(contract.assetsPath))
    out.put("routes", contract.routes.toJsonValue())
    out.put("allowedOrigins", contract.allowedOrigins.toJsonValue())
    out.put("allowHostHeaderOriginFallback", contract.allowHostHeaderOriginFallback.toJsonValue())
    out.put("allowInsecureAuth", contract.allowInsecureAuth.toJsonValue())
    out.put("deviceAuthMode", JsonString(contract.deviceAuthMode))
    out.put("authMode", JsonString(contract.authMode))
    out.put("csp", JsonString(contract.csp))
    out
}

public func gatewayControlUiOriginPolicyJson(cfg: GatewayConfig): JsonObject {
    let contract = gatewayControlUiContractJson(cfg)
    let out = JsonObject()
    out.put("allowedOrigins", contract.get("allowedOrigins") ?? JsonArray([]))
    out.put("allowHostHeaderOriginFallback", contract.get("allowHostHeaderOriginFallback") ?? false.toJsonValue())
    out.put("allowInsecureAuth", contract.get("allowInsecureAuth") ?? false.toJsonValue())
    out.put("authMode", contract.get("authMode") ?? JsonString("required"))
    out.put("deviceAuthMode", contract.get("deviceAuthMode") ?? JsonString("required"))
    out.put("csp", contract.get("csp") ?? JsonString(""))
    out
}

public func gatewayControlUiBootstrapConfigJson(cfg: GatewayConfig): JsonObject {
    let contract = GatewayControlUiRuntime.controlUiContract(cfg)
    let binding = GatewayControlUiRuntime.controlUiBinding(cfg)
    let out = JsonObject()
    out.put("basePath", JsonString(contract.basePath))
    out.put("wsUrl", JsonString(binding.wsUrl))
    out.put("assistantName", JsonString("Metis"))
    out.put("assistantAvatar", JsonString(""))
    out
}

public func gatewayControlUiBrowserAuthConfigJson(cfg: GatewayConfig): JsonObject {
    let out = JsonObject()
    out.put("deviceId", JsonString(gatewayDefaultControlUiDeviceId()))
    out.put("deviceToken", JsonString(gatewayDefaultControlUiDeviceToken()))
    out.put("authToken", JsonString(gatewayRuntimeEffectiveAuthTokenString(gatewayControlUiOptionString(cfg.auth.token))))
    out.put("authPassword", JsonString(gatewayRuntimeEffectiveAuthPasswordString(gatewayControlUiOptionString(cfg.auth.password))))
    out.put("clientMode", JsonString("control-ui-browser"))
    out.put("operatorScopes", JsonString("admin,read,write,approvals,pairing,talk-secrets"))
    out
}

public func gatewayControlUiBindingJson(cfg: GatewayConfig): JsonObject {
    let binding = GatewayControlUiRuntime.controlUiBinding(cfg)
    let out = JsonObject()
    out.put("host", JsonString(binding.host))
    out.put("port", Int64(binding.port).toJsonValue())
    out.put("httpUrl", JsonString(binding.httpUrl))
    out.put("wsUrl", JsonString(binding.wsUrl))
    out.put("basePath", JsonString(binding.basePath))
    out.put("apiPrefix", JsonString(binding.apiPrefix))
    out.put("assetsPath", JsonString(binding.assetsPath))
    out
}

public func gatewayControlUiDashboardBindingJson(cfg: GatewayConfig): JsonObject {
    let binding = GatewayControlUiRuntime.controlUiBinding(cfg)
    let out = JsonObject()
    out.put("wsUrl", JsonString(binding.wsUrl))
    out.put("httpUrl", JsonString(binding.httpUrl))
    out.put("apiPrefix", JsonString(binding.apiPrefix))
    out.put("assetsPath", JsonString(binding.assetsPath))
    out
}
