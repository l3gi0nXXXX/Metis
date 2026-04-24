package metis.gateway.security

import magic.jsonable.*

import metis.core.config.GatewayUserSettings
import metis.gateway.{gatewayRuntimeEffectiveAuthPassword, gatewayRuntimeEffectiveAuthToken}
import metis.gateway.model.{GatewayAuthConfig, GatewayControlUiConfig, GatewayConfig, GatewayAuthRateLimitConfig, GatewayTrustedProxyConfig}
import metis.gateway.protocol.GatewayProtocolRequest

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}
import stdx.net.http.HttpContext

private let gatewayAuthLock = Mutex()
private var gatewayAuthWindowAttempts = HashMap<String, Int64>()
private var gatewayAuthWindowStartedAt = HashMap<String, Int64>()
private var gatewayAuthLockedUntilAt = HashMap<String, Int64>()

public class GatewayAuthorizationResult {
    public let ok: Bool
    public let authMethod: String
    public let scopes: Array<String>
    public let identity: String
    public let error: String
    public let missingScope: String

    public init(
        ok: Bool,
        authMethod!: String = "",
        scopes!: Array<String> = [],
        identity!: String = "",
        error!: String = "",
        missingScope!: String = ""
    ) {
        this.ok = ok
        this.authMethod = authMethod
        this.scopes = scopes
        this.identity = identity
        this.error = error
        this.missingScope = missingScope
    }

    public func toJson(): JsonObject {
        let out = JsonObject()
        out.put("ok", this.ok.toJsonValue())
        out.put("authMethod", JsonString(this.authMethod))
        out.put("scopes", this.scopes.toJsonValue())
        out.put("identity", JsonString(this.identity))
        out.put("error", JsonString(this.error))
        out.put("missingScope", JsonString(this.missingScope))
        out
    }
}

private func gatewayNowMsForAuth(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func normalizeGatewayMode(mode: String): String {
    let normalized = mode.trimAscii().toAsciiLower()
    if (normalized.isEmpty()) {
        return "token"
    }
    normalized
}

private func gatewayJsonString(value: Option<JsonValue>): String {
    match (value) {
        case Some(v) =>
            try {
                v.asString().getValue().trimAscii()
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func gatewayHeader(ctx: HttpContext, name: String): String {
    ctx.request.headers.getFirst(name) ??
        ctx.request.headers.getFirst(name.toAsciiLower()) ??
        ""
}

private func gatewayParseScopesHeader(raw: String): Array<String> {
    let out = ArrayList<String>()
    for (part in raw.split(",")) {
        let normalized = part.trimAscii().toAsciiLower()
        if (!normalized.isEmpty() && !out.contains(normalized)) {
            out.add(normalized)
        }
    }
    out.toArray()
}

private func gatewayTrustedProxyScopesFromRequest(ctx: HttpContext): Array<String> {
    gatewayParseScopesHeader(gatewayHeader(ctx, "X-Metis-Operator-Scopes"))
}

private func gatewayTrustedProxyScopesFromProtocol(req: GatewayProtocolRequest): Array<String> {
    if (!req.connect.operatorScopes.isEmpty()) {
        return req.connect.operatorScopes
    }
    match (req.params.get("operatorScopes")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (item in arr.getItems()) {
                    let text = item.asString().getValue().trimAscii().toAsciiLower()
                    if (!text.isEmpty() && !out.contains(text)) {
                        out.add(text)
                    }
                }
                out.toArray()
            } catch (_e: Exception) {
                []
            }
        case None => []
    }
}

private func gatewayRateLimitIdentityKey(identity: String): String {
    let normalized = identity.trimAscii()
    if (normalized.isEmpty()) {
        return "anonymous"
    }
    normalized
}

private func gatewayCheckRateLimit(auth: GatewayAuthConfig, identity: String, isLoopback: Bool): GatewayAuthorizationResult {
    if (isLoopback && auth.rateLimit.exemptLoopback) {
        return GatewayAuthorizationResult(true)
    }
    let key = gatewayRateLimitIdentityKey(identity)
    let now = gatewayNowMsForAuth()
    synchronized(gatewayAuthLock) {
        let lockedUntil = gatewayAuthLockedUntilAt.get(key) ?? 0
        if (lockedUntil > now) {
            return GatewayAuthorizationResult(false, error: "Gateway auth rate limit active.")
        }
    }
    GatewayAuthorizationResult(true)
}

private func gatewayRecordAuthFailure(auth: GatewayAuthConfig, identity: String, isLoopback: Bool): Unit {
    if (isLoopback && auth.rateLimit.exemptLoopback) {
        return
    }
    let key = gatewayRateLimitIdentityKey(identity)
    let now = gatewayNowMsForAuth()
    synchronized(gatewayAuthLock) {
        let windowStart = gatewayAuthWindowStartedAt.get(key) ?? now
        if (now - windowStart > auth.rateLimit.windowMs) {
            gatewayAuthWindowStartedAt[key] = now
            gatewayAuthWindowAttempts[key] = 1
        } else {
            gatewayAuthWindowAttempts[key] = (gatewayAuthWindowAttempts.get(key) ?? 0) + 1
        }
        if ((gatewayAuthWindowAttempts.get(key) ?? 0) >= auth.rateLimit.maxAttempts) {
            gatewayAuthLockedUntilAt[key] = now + auth.rateLimit.lockoutMs
        }
    }
}

private func gatewayRecordAuthSuccess(identity: String): Unit {
    let key = gatewayRateLimitIdentityKey(identity)
    synchronized(gatewayAuthLock) {
        gatewayAuthWindowAttempts.remove(key)
        gatewayAuthWindowStartedAt.remove(key)
        gatewayAuthLockedUntilAt.remove(key)
    }
}

private func gatewayTrustedProxyAllowed(auth: GatewayAuthConfig, declaredUser: String, headers: JsonObject): Bool {
    if (auth.trustedProxy.userHeader.trimAscii().isEmpty()) {
        return false
    }
    if (declaredUser.trimAscii().isEmpty()) {
        return false
    }
    for (required in auth.trustedProxy.requiredHeaders) {
        let normalized = required.trimAscii()
        if (normalized.isEmpty()) {
            continue
        }
        match (headers.get(normalized)) {
            case Some(_) => ()
            case None =>
                match (headers.get(normalized.toAsciiLower())) {
                    case Some(_) => ()
                    case None => return false
                }
        }
    }
    if (!auth.trustedProxy.allowUsers.isEmpty() && !auth.trustedProxy.allowUsers.contains(declaredUser.trimAscii())) {
        return false
    }
    true
}

private func gatewayAuthTokenFromAuthorization(authorization: String, prefix: String): String {
    if (!authorization.startsWith(prefix)) {
        return ""
    }
    let parts = authorization.split(" ")
    if (parts.size < 2) {
        return ""
    }
    parts[1].trimAscii()
}

private func gatewayProtocolHeaders(req: GatewayProtocolRequest): JsonObject {
    match (req.params.get("trustedHeaders")) {
        case Some(v) =>
            try {
                v.asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
        case None => JsonObject()
    }
}

private func gatewayHeaderObject(ctx: HttpContext): JsonObject {
    let obj = JsonObject()
    for (name in ["authorization", "x-metis-gateway-token", "x-metis-gateway-password", "origin", "x-metis-operator-scopes", "x-metis-device-id", "x-metis-device-token", "x-forwarded-for", "x-real-ip"]) {
        let value = gatewayHeader(ctx, name)
        if (!value.trimAscii().isEmpty()) {
            obj.put(name, JsonString(value.trimAscii()))
        }
    }
    obj
}

private func gatewayAuthBySharedSecret(mode: String, expectedToken: String, expectedPassword: String, suppliedToken: String, suppliedPassword: String): (Bool, String) {
    if (mode == "none") {
        return (true, "none")
    }
    if (mode == "token") {
        return (!expectedToken.isEmpty() && suppliedToken == expectedToken, "token")
    }
    if (mode == "password") {
        return (!expectedPassword.isEmpty() && suppliedPassword == expectedPassword, "password")
    }
    (false, "")
}

private func gatewayAuthorizationIdentityForProtocol(req: GatewayProtocolRequest): String {
    if (!req.connect.declaredUser.trimAscii().isEmpty()) {
        return req.connect.declaredUser.trimAscii()
    }
    req.connect.client.id.trimAscii()
}

private func gatewayAuthorizationIdentityForHttp(ctx: HttpContext, auth: GatewayAuthConfig): String {
    if (auth.mode.trimAscii().toAsciiLower() == "trusted-proxy") {
        let userHeader = auth.trustedProxy.userHeader.trimAscii()
        if (!userHeader.isEmpty()) {
            let value = gatewayHeader(ctx, userHeader)
            if (!value.trimAscii().isEmpty()) {
                return value.trimAscii()
            }
        }
    }
    let forwarded = gatewayHeader(ctx, "X-Forwarded-For")
    if (!forwarded.trimAscii().isEmpty()) {
        return forwarded.trimAscii()
    }
    let realIp = gatewayHeader(ctx, "X-Real-IP")
    if (!realIp.trimAscii().isEmpty()) {
        return realIp.trimAscii()
    }
    "loopback"
}

private func gatewayProtocolNeedsDeviceAuth(controlUi: GatewayControlUiConfig, req: GatewayProtocolRequest): Bool {
    if (controlUi.dangerouslyDisableDeviceAuth) {
        return false
    }
    let mode = req.connect.client.mode.trimAscii().toAsciiLower()
    mode.contains("control-ui") || mode.contains("browser")
}

private func gatewayHttpNeedsDeviceAuth(controlUi: GatewayControlUiConfig, ctx: HttpContext, requiresDeviceAuth: Bool): Bool {
    if (controlUi.dangerouslyDisableDeviceAuth) {
        return false
    }
    if (requiresDeviceAuth) {
        return true
    }
    let mode = gatewayHeader(ctx, "X-Metis-Client-Mode").trimAscii().toAsciiLower()
    mode.contains("control-ui") || mode.contains("browser")
}

public func gatewayAuthorizeProtocolRequest(cfg: GatewayConfig, req: GatewayProtocolRequest): GatewayAuthorizationResult {
    let auth = cfg.auth
    let mode = normalizeGatewayMode(auth.mode)
    let identity = gatewayAuthorizationIdentityForProtocol(req)
    let rate = gatewayCheckRateLimit(auth, identity, req.connect.transport == "local")
    if (!rate.ok) {
        return GatewayAuthorizationResult(false, error: rate.error, identity: identity)
    }

    var scopes = gatewayTrustedProxyScopesFromProtocol(req)
    var authMethod = ""
    let suppliedToken = req.connect.authToken.trimAscii()
    let suppliedPassword = req.connect.authPassword.trimAscii()
    let expectedToken = gatewayJsonString(auth.token)
    let expectedPassword = gatewayJsonString(auth.password)

    if (req.connect.transport == "local" &&
        (req.connect.client.mode == "local-cli" || req.connect.client.mode == "agent-tool" || req.connect.client.mode == "local-rpc")) {
        authMethod = "local"
        if (scopes.isEmpty()) {
            scopes = gatewayDefaultOperatorScopesForClientMode(req.connect.client.mode)
        }
    } else if (mode == "trusted-proxy") {
        let headers = gatewayProtocolHeaders(req)
        if (!gatewayTrustedProxyAllowed(auth, req.connect.declaredUser.trimAscii(), headers)) {
            gatewayRecordAuthFailure(auth, identity, false)
            return GatewayAuthorizationResult(false, error: "Gateway trusted-proxy auth rejected.", identity: identity)
        }
        authMethod = "trusted-proxy"
        if (scopes.isEmpty()) {
            scopes = [GATEWAY_SCOPE_READ]
        }
    } else {
        let shared = gatewayAuthBySharedSecret(mode, expectedToken, expectedPassword, suppliedToken, suppliedPassword)
        if (!shared[0]) {
            gatewayRecordAuthFailure(auth, identity, false)
            return GatewayAuthorizationResult(false, error: "Gateway shared-secret auth rejected.", identity: identity)
        }
        authMethod = shared[1]
        if (scopes.isEmpty()) {
            scopes = gatewayCliDefaultOperatorScopes()
        }
    }

    if (gatewayProtocolNeedsDeviceAuth(cfg.controlUi, req)) {
        if (!gatewayVerifyDeviceToken(req.connect.deviceId, req.connect.deviceToken)) {
            gatewayRecordAuthFailure(auth, identity, false)
            return GatewayAuthorizationResult(false, authMethod: authMethod, identity: identity, scopes: scopes, error: "Gateway device auth rejected.")
        }
    }

    let scopeResult = gatewayAuthorizeOperatorScopesForMethod(req.method, scopes)
    if (!scopeResult[0]) {
        return GatewayAuthorizationResult(false, authMethod: authMethod, identity: identity, scopes: scopes, error: "Gateway operator scopes rejected.", missingScope: scopeResult[1])
    }
    gatewayRecordAuthSuccess(identity)
    GatewayAuthorizationResult(true, authMethod: authMethod, identity: identity, scopes: scopes)
}

public func gatewayAuthorizeHttpRequestForConfig(
    cfg: GatewayConfig,
    ctx: HttpContext,
    requiredMethod: String,
    requiresDeviceAuth!: Bool = false
): GatewayAuthorizationResult {
    let auth = cfg.auth
    let mode = normalizeGatewayMode(auth.mode)
    let identity = gatewayAuthorizationIdentityForHttp(ctx, auth)
    let rate = gatewayCheckRateLimit(auth, identity, true)
    if (!rate.ok) {
        return GatewayAuthorizationResult(false, error: rate.error, identity: identity)
    }

    let authorization = gatewayHeader(ctx, "Authorization").trimAscii()
    let tokenHeader = gatewayHeader(ctx, "X-Metis-Gateway-Token").trimAscii()
    let passwordHeader = gatewayHeader(ctx, "X-Metis-Gateway-Password").trimAscii()
    let bearer = gatewayAuthTokenFromAuthorization(authorization, "Bearer ")
    let basic = gatewayAuthTokenFromAuthorization(authorization, "Basic ")
    let suppliedToken = if (!tokenHeader.isEmpty()) { tokenHeader } else { bearer }
    let suppliedPassword = if (!passwordHeader.isEmpty()) { passwordHeader } else { basic }
    let expectedToken = gatewayJsonString(auth.token)
    let expectedPassword = gatewayJsonString(auth.password)
    let headers = gatewayHeaderObject(ctx)
    var scopes = gatewayTrustedProxyScopesFromRequest(ctx)
    var authMethod = ""

    if (mode == "trusted-proxy") {
        let userHeaderName = auth.trustedProxy.userHeader.trimAscii()
        let declaredUser = if (!userHeaderName.isEmpty()) { gatewayHeader(ctx, userHeaderName).trimAscii() } else { "" }
        if (!gatewayTrustedProxyAllowed(auth, declaredUser, headers)) {
            gatewayRecordAuthFailure(auth, identity, true)
            return GatewayAuthorizationResult(false, error: "Gateway trusted-proxy auth rejected.", identity: identity)
        }
        authMethod = "trusted-proxy"
        if (scopes.isEmpty()) {
            scopes = [GATEWAY_SCOPE_READ]
        }
    } else {
        let shared = gatewayAuthBySharedSecret(mode, expectedToken, expectedPassword, suppliedToken, suppliedPassword)
        if (!shared[0]) {
            gatewayRecordAuthFailure(auth, identity, true)
            return GatewayAuthorizationResult(false, error: "Gateway shared-secret auth rejected.", identity: identity)
        }
        authMethod = shared[1]
        if (scopes.isEmpty()) {
            scopes = gatewayCliDefaultOperatorScopes()
        }
    }

    if (gatewayHttpNeedsDeviceAuth(cfg.controlUi, ctx, requiresDeviceAuth)) {
        let deviceId = gatewayHeader(ctx, "X-Metis-Device-Id").trimAscii()
        let deviceToken = gatewayHeader(ctx, "X-Metis-Device-Token").trimAscii()
        if (!gatewayVerifyDeviceToken(deviceId, deviceToken)) {
            gatewayRecordAuthFailure(auth, identity, true)
            return GatewayAuthorizationResult(false, authMethod: authMethod, identity: identity, scopes: scopes, error: "Gateway device auth rejected.")
        }
    }

    let scopeResult = gatewayAuthorizeOperatorScopesForMethod(requiredMethod, scopes)
    if (!scopeResult[0]) {
        return GatewayAuthorizationResult(false, authMethod: authMethod, identity: identity, scopes: scopes, error: "Gateway operator scopes rejected.", missingScope: scopeResult[1])
    }
    gatewayRecordAuthSuccess(identity)
    GatewayAuthorizationResult(true, authMethod: authMethod, identity: identity, scopes: scopes)
}

public func gatewayAuthorizeDashboardRequest(
    user: GatewayUserSettings,
    ctx: HttpContext,
    requiredMethod: String
): GatewayAuthorizationResult {
    let authMode = normalizeGatewayMode(user.auth.mode)
    let effectiveToken = gatewayRuntimeEffectiveAuthToken(user).trimAscii()
    let effectivePassword = gatewayRuntimeEffectiveAuthPassword(user).trimAscii()
    let authCfg = GatewayAuthConfig(
        mode: user.auth.mode,
        token: if (effectiveToken.isEmpty()) { None } else { Some<JsonValue>(JsonString(effectiveToken)) },
        password: if (effectivePassword.isEmpty()) { None } else { Some<JsonValue>(JsonString(effectivePassword)) },
        allowTailscale: user.auth.allowTailscale,
        rateLimit: GatewayAuthRateLimitConfig(
            maxAttempts: user.auth.rateLimit.maxAttempts,
            windowMs: user.auth.rateLimit.windowMs,
            lockoutMs: user.auth.rateLimit.lockoutMs,
            exemptLoopback: user.auth.rateLimit.exemptLoopback
        ),
        trustedProxy: GatewayTrustedProxyConfig(
            userHeader: user.auth.trustedProxy.userHeader,
            requiredHeaders: user.auth.trustedProxy.requiredHeaders,
            allowUsers: user.auth.trustedProxy.allowUsers
        )
    )
    let identity = gatewayAuthorizationIdentityForHttp(ctx, authCfg)
    var scopes = gatewayTrustedProxyScopesFromRequest(ctx)
    var authMethod = ""
    let authorization = gatewayHeader(ctx, "Authorization").trimAscii()
    let tokenHeader = gatewayHeader(ctx, "X-Metis-Gateway-Token").trimAscii()
    let passwordHeader = gatewayHeader(ctx, "X-Metis-Gateway-Password").trimAscii()
    let bearer = gatewayAuthTokenFromAuthorization(authorization, "Bearer ")
    let basic = gatewayAuthTokenFromAuthorization(authorization, "Basic ")
    let suppliedToken = if (!tokenHeader.isEmpty()) { tokenHeader } else { bearer }
    let suppliedPassword = if (!passwordHeader.isEmpty()) { passwordHeader } else { basic }
    let rate = gatewayCheckRateLimit(authCfg, identity, true)
    if (!rate.ok) {
        return GatewayAuthorizationResult(false, error: rate.error, identity: identity)
    }
    if (authMode == "trusted-proxy") {
        let userHeaderName = user.auth.trustedProxy.userHeader.trimAscii()
        let declaredUser = if (!userHeaderName.isEmpty()) { gatewayHeader(ctx, userHeaderName).trimAscii() } else { "" }
        if (!gatewayTrustedProxyAllowed(authCfg, declaredUser, gatewayHeaderObject(ctx))) {
            gatewayRecordAuthFailure(authCfg, identity, true)
            return GatewayAuthorizationResult(false, error: "Gateway trusted-proxy auth rejected.", identity: identity)
        }
        authMethod = "trusted-proxy"
        if (scopes.isEmpty()) {
            scopes = [GATEWAY_SCOPE_READ]
        }
    } else {
        let shared = gatewayAuthBySharedSecret(authMode, effectiveToken, effectivePassword, suppliedToken, suppliedPassword)
        if (!shared[0]) {
            gatewayRecordAuthFailure(authCfg, identity, true)
            return GatewayAuthorizationResult(false, error: "Gateway shared-secret auth rejected.", identity: identity)
        }
        authMethod = shared[1]
        if (scopes.isEmpty()) {
            scopes = gatewayCliDefaultOperatorScopes()
        }
    }
    if (!user.controlUi.dangerouslyDisableDeviceAuth) {
        let deviceId = gatewayHeader(ctx, "X-Metis-Device-Id").trimAscii()
        let deviceToken = gatewayHeader(ctx, "X-Metis-Device-Token").trimAscii()
        if (!gatewayVerifyDeviceToken(deviceId, deviceToken)) {
            gatewayRecordAuthFailure(authCfg, identity, true)
            return GatewayAuthorizationResult(false, authMethod: authMethod, identity: identity, scopes: scopes, error: "Gateway device auth rejected.")
        }
    }
    let scopeResult = gatewayAuthorizeOperatorScopesForMethod(requiredMethod, scopes)
    if (!scopeResult[0]) {
        return GatewayAuthorizationResult(false, authMethod: authMethod, identity: identity, scopes: scopes, error: "Gateway operator scopes rejected.", missingScope: scopeResult[1])
    }
    gatewayRecordAuthSuccess(identity)
    GatewayAuthorizationResult(true, authMethod: authMethod, identity: identity, scopes: scopes)
}
