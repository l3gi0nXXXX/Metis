package metis.gateway.channels.feishu

import metis.core.config.{GatewayUserSettings, MetisPaths}
import metis.gateway.core.{
    setGatewayFeishuNativeAuthCompleteRunner,
    setGatewayFeishuNativeAuthPollRunner,
    setGatewayFeishuNativeAuthRevokeRunner,
    setGatewayFeishuNativeAuthRunner,
    setGatewayFeishuNativeAuthStatusRunner
}

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}
import stdx.encoding.url.URL
import stdx.net.http.*
import stdx.net.tls.*

public class FeishuAuthHttpResponse {
    public let statusCode: Int64
    public let body: String
    public let error: String

    public init(statusCode: Int64, body: String, error!: String = "") {
        this.statusCode = statusCode
        this.body = body
        this.error = error.trimAscii()
    }
}

public interface FeishuAuthHttpClient {
    func postForm(url: String, fields: HashMap<String, String>, headers: HashMap<String, String>): FeishuAuthHttpResponse
}

public class FeishuNativeAuthHttpClient <: FeishuAuthHttpClient {
    private let timeoutSeconds: Int64

    public init(timeoutSeconds!: Int64 = 30) {
        this.timeoutSeconds = if (timeoutSeconds <= 0) { 30 } else { timeoutSeconds }
    }

    public func postForm(url: String, fields: HashMap<String, String>, headers: HashMap<String, String>): FeishuAuthHttpResponse {
        try {
            let builder = ClientBuilder()
            builder.readTimeout(Duration.second * this.timeoutSeconds)
            if (url.startsWith("https")) {
                var tlsConfig = TlsClientConfig()
                tlsConfig.domain = URL.parse(url).hostName
                tlsConfig.alpnProtocolsList = ["http/1.1"]
                builder.tlsConfig(tlsConfig)
            }
            let client = builder.build()
            try {
                let reqBuilder = HttpRequestBuilder().url(url).post().body(feishuAuthFormBody(fields))
                for ((key, value) in headers) {
                    reqBuilder.header(key, value)
                }
                let response = client.send(reqBuilder.build())
                let bytes = feishuAuthReadAllBytes(response)
                let body = try { String.fromUtf8(bytes) } catch (_e: Exception) { "" }
                return FeishuAuthHttpResponse(Int64(response.status), body)
            } finally {
                client.close()
            }
        } catch (e: Exception) {
            FeishuAuthHttpResponse(0, "", error: e.message)
        }
    }
}

public class FeishuDeviceAuthorizationResult {
    public let status: String
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresInSeconds: Int64
    public let intervalSeconds: Int64
    public let error: String

    public init(
        status!: String = "error",
        deviceCode!: String = "",
        userCode!: String = "",
        verificationUri!: String = "",
        expiresInSeconds!: Int64 = 0,
        intervalSeconds!: Int64 = 5,
        error!: String = ""
    ) {
        this.status = status.trimAscii()
        this.deviceCode = deviceCode.trimAscii()
        this.userCode = userCode.trimAscii()
        this.verificationUri = verificationUri.trimAscii()
        this.expiresInSeconds = expiresInSeconds
        this.intervalSeconds = intervalSeconds
        this.error = error.trimAscii()
    }

    public func toRedactedJson(): JsonObject {
        let out = JsonObject()
        out.put("status", JsonString(this.status))
        out.put("userCode", JsonString(this.userCode))
        out.put("verificationUri", JsonString(this.verificationUri))
        out.put("expiresInSeconds", JsonInt(this.expiresInSeconds))
        out.put("intervalSeconds", JsonInt(this.intervalSeconds))
        out.put("hasDeviceCode", JsonBool(!this.deviceCode.isEmpty()))
        out.put("redacted", JsonBool(true))
        if (!this.error.isEmpty()) {
            out.put("error", JsonString(feishuAuthRedactSensitiveText(this.error)))
        }
        out
    }
}

public class FeishuDeviceTokenResult {
    public let status: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresInSeconds: Int64
    public let scopes: Array<String>
    public let error: String

    public init(
        status!: String = "error",
        accessToken!: String = "",
        refreshToken!: String = "",
        expiresInSeconds!: Int64 = 0,
        scopes!: Array<String> = [],
        error!: String = ""
    ) {
        this.status = status.trimAscii()
        this.accessToken = accessToken.trimAscii()
        this.refreshToken = refreshToken.trimAscii()
        this.expiresInSeconds = expiresInSeconds
        this.scopes = scopes
        this.error = error.trimAscii()
    }

    public func toRedactedJson(): JsonObject {
        let out = JsonObject()
        out.put("status", JsonString(this.status))
        out.put("authorized", JsonBool(this.status == "authorized"))
        out.put("hasAccessToken", JsonBool(!this.accessToken.isEmpty()))
        out.put("hasRefreshToken", JsonBool(!this.refreshToken.isEmpty()))
        out.put("expiresInSeconds", JsonInt(this.expiresInSeconds))
        out.put("scopes", feishuAuthJsonStringArray(this.scopes))
        out.put("redacted", JsonBool(true))
        if (!this.error.isEmpty()) {
            out.put("error", JsonString(feishuAuthRedactSensitiveText(this.error)))
        }
        out
    }
}

public class FeishuDeviceFlowClient {
    private let http: FeishuAuthHttpClient
    private let domain: String
    private let appId: String
    private let appSecret: String

    public init(http: FeishuAuthHttpClient, domain!: String = "https://open.feishu.cn", appId!: String = "", appSecret!: String = "") {
        this.http = http
        this.domain = feishuAuthNormalizeDomain(domain)
        this.appId = appId.trimAscii()
        this.appSecret = appSecret.trimAscii()
    }

    public func start(scopes!: Array<String> = []): FeishuDeviceAuthorizationResult {
        let fields = HashMap<String, String>()
        fields["client_id"] = this.appId
        fields["client_secret"] = this.appSecret
        fields["scope"] = feishuAuthScopeString(scopes)
        let response = this.http.postForm(
            "${this.domain}/open-apis/authen/v1/oidc/device_authorize",
            fields,
            HashMap<String, String>([("Content-Type", "application/x-www-form-urlencoded")])
        )
        if (response.statusCode < 200 || response.statusCode >= 300) {
            return FeishuDeviceAuthorizationResult(status: "network_error", error: response.error)
        }
        return try {
            let root = JsonValue.fromStr(response.body).asObject()
            let deviceCode = feishuAuthString(root, "device_code")
            if (deviceCode.isEmpty()) {
                FeishuDeviceAuthorizationResult(status: "error", error: feishuAuthString(root, "error"))
            } else {
                FeishuDeviceAuthorizationResult(
                    status: "pending",
                    deviceCode: deviceCode,
                    userCode: feishuAuthString(root, "user_code"),
                    verificationUri: feishuAuthString(root, "verification_uri"),
                    expiresInSeconds: feishuAuthInt(root, "expires_in", 0),
                    intervalSeconds: feishuAuthInt(root, "interval", 5)
                )
            }
        } catch (e: Exception) {
            FeishuDeviceAuthorizationResult(status: "parse_error", error: e.message)
        }
    }

    public func poll(deviceCode: String): FeishuDeviceTokenResult {
        let fields = HashMap<String, String>()
        fields["client_id"] = this.appId
        fields["client_secret"] = this.appSecret
        fields["device_code"] = deviceCode.trimAscii()
        fields["grant_type"] = "urn:ietf:params:oauth:grant-type:device_code"
        let response = this.http.postForm(
            "${this.domain}/open-apis/authen/v1/oidc/token",
            fields,
            HashMap<String, String>([("Content-Type", "application/x-www-form-urlencoded")])
        )
        if (response.statusCode < 200 || response.statusCode >= 300) {
            return FeishuDeviceTokenResult(status: "network_error", error: response.error)
        }
        return try {
            let root = JsonValue.fromStr(response.body).asObject()
            let accessToken = feishuAuthString(root, "access_token")
            if (!accessToken.isEmpty()) {
                FeishuDeviceTokenResult(
                    status: "authorized",
                    accessToken: accessToken,
                    refreshToken: feishuAuthString(root, "refresh_token"),
                    expiresInSeconds: feishuAuthInt(root, "expires_in", 0),
                    scopes: feishuAuthScopes(feishuAuthString(root, "scope"))
                )
            } else {
                let err = feishuAuthString(root, "error")
                FeishuDeviceTokenResult(status: feishuAuthTokenErrorStatus(err), error: err)
            }
        } catch (e: Exception) {
            FeishuDeviceTokenResult(status: "parse_error", error: e.message)
        }
    }
}

public class FeishuUserToken {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAtMs: Int64
    public let scopes: Array<String>

    public init(accessToken!: String = "", refreshToken!: String = "", expiresAtMs!: Int64 = 0, scopes!: Array<String> = []) {
        this.accessToken = accessToken.trimAscii()
        this.refreshToken = refreshToken.trimAscii()
        this.expiresAtMs = expiresAtMs
        this.scopes = scopes
    }

    public func toJson(): JsonObject {
        let out = JsonObject()
        out.put("accessToken", JsonString(this.accessToken))
        out.put("refreshToken", JsonString(this.refreshToken))
        out.put("expiresAtMs", JsonInt(this.expiresAtMs))
        out.put("scopes", feishuAuthJsonStringArray(this.scopes))
        out
    }

    public func redactedStatus(accountId: String): JsonObject {
        let hasAccessToken = !this.accessToken.isEmpty()
        let expired = hasAccessToken && this.expiresAtMs > 0 && this.expiresAtMs <= DateTime.now().toUnixTimeStamp().toMilliseconds()
        let out = JsonObject()
        out.put("accountId", JsonString(gatewayFeishuNormalizeAccountId(accountId)))
        out.put("status", JsonString(if (!hasAccessToken) { "missing" } else if (expired) { "expired" } else { "authorized" }))
        out.put("authorized", JsonBool(hasAccessToken && !expired))
        out.put("hasAccessToken", JsonBool(hasAccessToken))
        out.put("hasRefreshToken", JsonBool(!this.refreshToken.isEmpty()))
        out.put("expiresAtMs", JsonInt(this.expiresAtMs))
        out.put("scopes", feishuAuthJsonStringArray(this.scopes))
        out.put("redacted", JsonBool(true))
        out
    }
}

public interface FeishuTokenStore {
    func save(accountId: String, token: FeishuUserToken): Unit
    func load(accountId: String): Option<FeishuUserToken>
    func status(accountId: String): JsonObject
    func delete(accountId: String): Unit
}

public class FeishuFileTokenStore <: FeishuTokenStore {
    private let root: Path

    public init(root: Path) {
        this.root = root
    }

    public func save(accountId: String, token: FeishuUserToken): Unit {
        if (!exists(this.root)) {
            Directory.create(this.root, recursive: true)
        }
        File.writeTo(this.pathFor(accountId), token.toJson().toJsonString().toArray())
    }

    public func load(accountId: String): Option<FeishuUserToken> {
        let path = this.pathFor(accountId)
        if (!exists(path)) {
            return None<FeishuUserToken>
        }
        return try {
            let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
            Some(FeishuUserToken(
                accessToken: feishuAuthString(root, "accessToken"),
                refreshToken: feishuAuthString(root, "refreshToken"),
                expiresAtMs: feishuAuthInt(root, "expiresAtMs", 0),
                scopes: feishuAuthStringArray(root, "scopes")
            ))
        } catch (_: Exception) {
            None<FeishuUserToken>
        }
    }

    public func status(accountId: String): JsonObject {
        match (this.load(accountId)) {
            case Some(token) => token.redactedStatus(accountId)
            case None =>
                let out = JsonObject()
                out.put("accountId", JsonString(gatewayFeishuNormalizeAccountId(accountId)))
                out.put("status", JsonString("missing"))
                out.put("authorized", JsonBool(false))
                out.put("redacted", JsonBool(true))
                out
        }
    }

    public func delete(accountId: String): Unit {
        try { remove(this.pathFor(accountId)) } catch (_: Exception) { () }
    }

    private func pathFor(accountId: String): Path {
        this.root.join("${feishuAuthSafeSegment(accountId)}.json")
    }
}

public class FeishuPendingUserAuth {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresAtMs: Int64
    public let intervalSeconds: Int64
    public let createdAtMs: Int64

    public init(
        deviceCode!: String = "",
        userCode!: String = "",
        verificationUri!: String = "",
        expiresAtMs!: Int64 = 0,
        intervalSeconds!: Int64 = 5,
        createdAtMs!: Int64 = 0
    ) {
        this.deviceCode = deviceCode.trimAscii()
        this.userCode = userCode.trimAscii()
        this.verificationUri = verificationUri.trimAscii()
        this.expiresAtMs = expiresAtMs
        this.intervalSeconds = if (intervalSeconds <= 0) { 5 } else { intervalSeconds }
        this.createdAtMs = createdAtMs
    }

    public func toJson(): JsonObject {
        let out = JsonObject()
        out.put("deviceCode", JsonString(this.deviceCode))
        out.put("userCode", JsonString(this.userCode))
        out.put("verificationUri", JsonString(this.verificationUri))
        out.put("expiresAtMs", JsonInt(this.expiresAtMs))
        out.put("intervalSeconds", JsonInt(this.intervalSeconds))
        out.put("createdAtMs", JsonInt(this.createdAtMs))
        out
    }

    public func redactedStatus(accountId: String, nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()): JsonObject {
        let expired = this.expiresAtMs > 0 && this.expiresAtMs <= nowMs
        let out = JsonObject()
        out.put("accountId", JsonString(gatewayFeishuNormalizeAccountId(accountId)))
        out.put("status", JsonString(if (expired) { "expired" } else { "pending" }))
        out.put("authorized", JsonBool(false))
        out.put("pending", JsonBool(!expired))
        out.put("userCode", JsonString(this.userCode))
        out.put("verificationUri", JsonString(this.verificationUri))
        out.put("expiresAtMs", JsonInt(this.expiresAtMs))
        out.put("expiresInSeconds", JsonInt(if (expired || this.expiresAtMs <= 0) { 0 } else { (this.expiresAtMs - nowMs) / 1000 }))
        out.put("intervalSeconds", JsonInt(this.intervalSeconds))
        out.put("hasDeviceCode", JsonBool(!this.deviceCode.isEmpty()))
        out.put("redacted", JsonBool(true))
        out
    }
}

public interface FeishuAuthSessionStore {
    func save(accountId: String, pending: FeishuPendingUserAuth): Unit
    func load(accountId: String): Option<FeishuPendingUserAuth>
    func delete(accountId: String): Unit
}

public class FeishuFileAuthSessionStore <: FeishuAuthSessionStore {
    private let root: Path

    public init(root: Path) {
        this.root = root
    }

    public func save(accountId: String, pending: FeishuPendingUserAuth): Unit {
        if (!exists(this.root)) {
            Directory.create(this.root, recursive: true)
        }
        File.writeTo(this.pathFor(accountId), pending.toJson().toJsonString().toArray())
    }

    public func load(accountId: String): Option<FeishuPendingUserAuth> {
        let path = this.pathFor(accountId)
        if (!exists(path)) {
            return None<FeishuPendingUserAuth>
        }
        return try {
            let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
            Some(FeishuPendingUserAuth(
                deviceCode: feishuAuthString(root, "deviceCode"),
                userCode: feishuAuthString(root, "userCode"),
                verificationUri: feishuAuthString(root, "verificationUri"),
                expiresAtMs: feishuAuthInt(root, "expiresAtMs", 0),
                intervalSeconds: feishuAuthInt(root, "intervalSeconds", 5),
                createdAtMs: feishuAuthInt(root, "createdAtMs", 0)
            ))
        } catch (_: Exception) {
            None<FeishuPendingUserAuth>
        }
    }

    public func delete(accountId: String): Unit {
        try { remove(this.pathFor(accountId)) } catch (_: Exception) { () }
    }

    private func pathFor(accountId: String): Path {
        this.root.join("${feishuAuthSafeSegment(accountId)}.json")
    }
}

public func feishuGatewayNativeAuthTokenStoreRoot(): Path {
    MetisPaths.homeRoot().join("feishu").join("user-tokens")
}

public func feishuGatewayNativeAuthSessionStoreRoot(): Path {
    MetisPaths.homeRoot().join("feishu").join("auth-sessions")
}

public func feishuInstallGatewayNativeAuthRunner(): Unit {
    setGatewayFeishuNativeAuthRunner(Some({ accountId: String, user: GatewayUserSettings =>
        feishuGatewayNativeAuthStart(accountId, user)
    }))
    setGatewayFeishuNativeAuthStatusRunner(Some({ accountId: String, user: GatewayUserSettings =>
        feishuGatewayNativeAuthStatus(accountId, user)
    }))
    setGatewayFeishuNativeAuthPollRunner(Some({ accountId: String, user: GatewayUserSettings =>
        feishuGatewayNativeAuthPoll(accountId, user)
    }))
    setGatewayFeishuNativeAuthCompleteRunner(Some({ accountId: String, user: GatewayUserSettings =>
        feishuGatewayNativeAuthComplete(accountId, user)
    }))
    setGatewayFeishuNativeAuthRevokeRunner(Some({ accountId: String, user: GatewayUserSettings =>
        feishuGatewayNativeAuthRevoke(accountId, user)
    }))
}

public func feishuGatewayNativeAuthStart(accountId: String, user: GatewayUserSettings): JsonObject {
    feishuGatewayNativeAuthStartWithClient(
        accountId,
        user,
        FeishuNativeAuthHttpClient(),
        FeishuFileTokenStore(feishuGatewayNativeAuthTokenStoreRoot()),
        sessionStore: FeishuFileAuthSessionStore(feishuGatewayNativeAuthSessionStoreRoot())
    )
}

public func feishuGatewayNativeAuthStartWithClient(
    accountId: String,
    user: GatewayUserSettings,
    http: FeishuAuthHttpClient,
    store: FeishuTokenStore,
    sessionStore!: FeishuAuthSessionStore = FeishuFileAuthSessionStore(feishuGatewayNativeAuthSessionStoreRoot()),
    nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
): JsonObject {
    let normalized = feishuAuthNativeAccountId(accountId, user)
    let stored = store.status(normalized)
    let tokenStatus = feishuAuthString(stored, "status")
    if (tokenStatus == "authorized") {
        let out = JsonObject()
        out.put("status", JsonString("authorized"))
        out.put("accountId", JsonString(normalized))
        out.put("tokenStatus", JsonString("authorized"))
        out.put("scopeSummary", JsonString(feishuAuthScopeSummary(stored)))
        out.put("redacted", JsonBool(true))
        out.put("message", JsonString("Stored Feishu user authorization is available."))
        return out
    }

    let account = feishuAuthNativeAccountConfig(normalized, user)
    let appId = feishuAuthJsonStringFallback(account, ["appId", "app_id"], user.feishu.appId)
    let appSecret = feishuAuthJsonStringFallback(account, ["appSecret", "app_secret"], user.feishu.appSecret)
    if (appId.isEmpty() || appSecret.isEmpty()) {
        let out = JsonObject()
        out.put("status", JsonString("missing_app_credentials"))
        out.put("accountId", JsonString(normalized))
        out.put("tokenStatus", JsonString(tokenStatus))
        out.put("redacted", JsonBool(true))
        out.put("message", JsonString("Feishu appId/appSecret is required before user authorization can start."))
        return out
    }

    let domain = feishuAuthJsonStringFallback(account, ["domain"], user.feishu.domain)
    let client = FeishuDeviceFlowClient(http, domain: domain, appId: appId, appSecret: appSecret)
    let started = client.start()
    let out = started.toRedactedJson()
    out.put("accountId", JsonString(normalized))
    out.put("tokenStatus", JsonString(tokenStatus))
    if (started.status == "pending") {
        sessionStore.save(normalized, FeishuPendingUserAuth(
            deviceCode: started.deviceCode,
            userCode: started.userCode,
            verificationUri: started.verificationUri,
            expiresAtMs: nowMs + started.expiresInSeconds * 1000,
            intervalSeconds: started.intervalSeconds,
            createdAtMs: nowMs
        ))
        out.put("message", JsonString("Open the verification URL and enter the user code to authorize Feishu user access."))
    }
    out.put("expiresInSeconds", JsonString(started.expiresInSeconds.toString()))
    out.put("redacted", JsonBool(true))
    out
}

public func feishuGatewayNativeAuthStatus(accountId: String, user: GatewayUserSettings): JsonObject {
    feishuGatewayNativeAuthStatusWithStores(
        accountId,
        user,
        FeishuFileTokenStore(feishuGatewayNativeAuthTokenStoreRoot()),
        FeishuFileAuthSessionStore(feishuGatewayNativeAuthSessionStoreRoot())
    )
}

public func feishuGatewayNativeAuthStatusWithStores(
    accountId: String,
    user: GatewayUserSettings,
    store: FeishuTokenStore,
    sessionStore: FeishuAuthSessionStore,
    nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
): JsonObject {
    let normalized = feishuAuthNativeAccountId(accountId, user)
    let tokenStatus = store.status(normalized)
    let tokenStatusText = feishuAuthString(tokenStatus, "status")
    if (tokenStatusText == "authorized") {
        return feishuAuthLifecycleTokenStatus(normalized, tokenStatus, "Stored Feishu user authorization is available.")
    }
    match (sessionStore.load(normalized)) {
        case Some(pending) =>
            let out = pending.redactedStatus(normalized, nowMs: nowMs)
            out.put("tokenStatus", JsonString(tokenStatusText))
            if (feishuAuthString(out, "status") == "expired") {
                out.put("message", JsonString("Feishu OAuth device authorization has expired. Start authorization again."))
            } else {
                out.put("message", JsonString("Feishu OAuth device authorization is pending user confirmation."))
            }
            return out
        case None => ()
    }
    feishuAuthLifecycleTokenStatus(normalized, tokenStatus, "Feishu user authorization is not available.")
}

public func feishuGatewayNativeAuthPoll(accountId: String, user: GatewayUserSettings): JsonObject {
    feishuGatewayNativeAuthPollWithClient(
        accountId,
        user,
        FeishuNativeAuthHttpClient(),
        FeishuFileTokenStore(feishuGatewayNativeAuthTokenStoreRoot()),
        FeishuFileAuthSessionStore(feishuGatewayNativeAuthSessionStoreRoot())
    )
}

public func feishuGatewayNativeAuthPollWithClient(
    accountId: String,
    user: GatewayUserSettings,
    http: FeishuAuthHttpClient,
    store: FeishuTokenStore,
    sessionStore: FeishuAuthSessionStore,
    nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
): JsonObject {
    let normalized = feishuAuthNativeAccountId(accountId, user)
    let stored = store.status(normalized)
    let tokenStatus = feishuAuthString(stored, "status")
    if (tokenStatus == "authorized") {
        return feishuAuthLifecycleTokenStatus(normalized, stored, "Stored Feishu user authorization is available.")
    }
    let pending = match (sessionStore.load(normalized)) {
        case Some(v) => v
        case None =>
            let out = feishuAuthLifecycleTokenStatus(normalized, stored, "No pending Feishu OAuth device authorization is available.")
            out.put("status", JsonString("missing_device_flow"))
            out.put("pending", JsonBool(false))
            return out
    }
    if (pending.expiresAtMs > 0 && pending.expiresAtMs <= nowMs) {
        sessionStore.delete(normalized)
        let out = pending.redactedStatus(normalized, nowMs: nowMs)
        out.put("tokenStatus", JsonString(tokenStatus))
        out.put("message", JsonString("Feishu OAuth device authorization has expired. Start authorization again."))
        return out
    }

    let account = feishuAuthNativeAccountConfig(normalized, user)
    let appId = feishuAuthJsonStringFallback(account, ["appId", "app_id"], user.feishu.appId)
    let appSecret = feishuAuthJsonStringFallback(account, ["appSecret", "app_secret"], user.feishu.appSecret)
    if (appId.isEmpty() || appSecret.isEmpty()) {
        let out = feishuAuthLifecycleTokenStatus(normalized, stored, "Feishu appId/appSecret is required before user authorization can be polled.")
        out.put("status", JsonString("missing_app_credentials"))
        return out
    }

    let domain = feishuAuthJsonStringFallback(account, ["domain"], user.feishu.domain)
    let result = FeishuDeviceFlowClient(http, domain: domain, appId: appId, appSecret: appSecret).poll(pending.deviceCode)
    if (result.status == "authorized") {
        let saved = feishuSaveAuthorizedUserToken(store, normalized, result, nowMs: nowMs)
        sessionStore.delete(normalized)
        return feishuAuthLifecycleTokenStatus(normalized, saved, "Feishu user authorization completed.")
    }
    if (result.status == "denied" || result.status == "expired") {
        sessionStore.delete(normalized)
    }
    let out = result.toRedactedJson()
    out.put("accountId", JsonString(normalized))
    out.put("tokenStatus", JsonString(tokenStatus))
    out.put("pending", JsonBool(result.status == "authorization_pending" || result.status == "slow_down"))
    out.put("userCode", JsonString(pending.userCode))
    out.put("verificationUri", JsonString(pending.verificationUri))
    out.put("intervalSeconds", JsonInt(pending.intervalSeconds))
    out.put("redacted", JsonBool(true))
    return out
}

public func feishuGatewayNativeAuthComplete(accountId: String, user: GatewayUserSettings): JsonObject {
    feishuGatewayNativeAuthCompleteWithClient(
        accountId,
        user,
        FeishuNativeAuthHttpClient(),
        FeishuFileTokenStore(feishuGatewayNativeAuthTokenStoreRoot()),
        FeishuFileAuthSessionStore(feishuGatewayNativeAuthSessionStoreRoot())
    )
}

public func feishuGatewayNativeAuthCompleteWithClient(
    accountId: String,
    user: GatewayUserSettings,
    http: FeishuAuthHttpClient,
    store: FeishuTokenStore,
    sessionStore: FeishuAuthSessionStore,
    nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
): JsonObject {
    let normalized = feishuAuthNativeAccountId(accountId, user)
    let stored = store.status(normalized)
    if (feishuAuthString(stored, "status") == "authorized") {
        return feishuAuthLifecycleTokenStatus(normalized, stored, "Stored Feishu user authorization is available.")
    }
    match (sessionStore.load(normalized)) {
        case Some(_) => feishuGatewayNativeAuthPollWithClient(normalized, user, http, store, sessionStore, nowMs: nowMs)
        case None =>
            let out = feishuAuthLifecycleTokenStatus(normalized, stored, "No pending Feishu OAuth device authorization is available.")
            out.put("status", JsonString("missing_device_flow"))
            out.put("pending", JsonBool(false))
            out
    }
}

public func feishuGatewayNativeAuthRevoke(accountId: String, user: GatewayUserSettings): JsonObject {
    feishuGatewayNativeAuthRevokeWithStores(
        accountId,
        user,
        FeishuFileTokenStore(feishuGatewayNativeAuthTokenStoreRoot()),
        FeishuFileAuthSessionStore(feishuGatewayNativeAuthSessionStoreRoot())
    )
}

public func feishuGatewayNativeAuthRevokeWithStores(
    accountId: String,
    user: GatewayUserSettings,
    store: FeishuTokenStore,
    sessionStore: FeishuAuthSessionStore
): JsonObject {
    let normalized = feishuAuthNativeAccountId(accountId, user)
    store.delete(normalized)
    sessionStore.delete(normalized)
    let out = JsonObject()
    out.put("accountId", JsonString(normalized))
    out.put("status", JsonString("revoked"))
    out.put("tokenStatus", JsonString("missing"))
    out.put("authorized", JsonBool(false))
    out.put("pending", JsonBool(false))
    out.put("revoked", JsonBool(true))
    out.put("redacted", JsonBool(true))
    out.put("message", JsonString("Local Feishu user authorization was removed."))
    out
}

public func feishuSaveAuthorizedUserToken(
    store: FeishuTokenStore,
    accountId: String,
    result: FeishuDeviceTokenResult,
    nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
): JsonObject {
    if (result.status == "authorized" && !result.accessToken.isEmpty()) {
        store.save(gatewayFeishuNormalizeAccountId(accountId), FeishuUserToken(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAtMs: nowMs + result.expiresInSeconds * 1000,
            scopes: result.scopes
        ))
        return store.status(accountId)
    }
    result.toRedactedJson()
}

private func feishuAuthLifecycleTokenStatus(accountId: String, tokenStatus: JsonObject, message: String): JsonObject {
    let out = JsonObject()
    out.put("accountId", JsonString(gatewayFeishuNormalizeAccountId(accountId)))
    let status = feishuAuthString(tokenStatus, "status")
    out.put("status", JsonString(status))
    out.put("tokenStatus", JsonString(status))
    out.put("pending", JsonBool(false))
    out.put("redacted", JsonBool(true))
    for (key in ["authorized", "hasAccessToken", "hasRefreshToken", "expiresAtMs", "scopes"]) {
        match (tokenStatus.get(key)) {
            case Some(v) => out.put(key, v)
            case None => ()
        }
    }
    if (!message.isEmpty()) {
        out.put("message", JsonString(message))
    }
    out
}

private func feishuAuthNormalizeDomain(raw: String): String {
    var out = raw.trimAscii()
    if (out.isEmpty()) {
        out = "https://open.feishu.cn"
    }
    while (out.endsWith("/") && out.size > 0) {
        out = out[0..out.size - 1]
    }
    out
}

private func feishuAuthRedactSensitiveText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lower = text.toAsciiLower()
    if (
        lower.contains("authorization") ||
        lower.contains("bearer ") ||
        lower.contains("access_token") ||
        lower.contains("refresh_token") ||
        lower.contains("client_secret") ||
        lower.contains("appsecret") ||
        lower.contains("secret") ||
        lower.contains("token") ||
        lower.contains("password")
    ) {
        return "[redacted]"
    }
    text
}

private func feishuAuthReadAllBytes(response: HttpResponse): Array<Byte> {
    let out = ArrayList<Byte>()
    let buffer = Array<Byte>(8192, repeat: 0)
    while (true) {
        let n = response.body.read(buffer)
        if (n <= 0) {
            break
        }
        out.add(all: buffer[..n])
    }
    out.toArray()
}

private func feishuAuthFormBody(fields: HashMap<String, String>): String {
    let parts = ArrayList<String>()
    for ((key, value) in fields) {
        parts.add("${feishuAuthFormEncode(key)}=${feishuAuthFormEncode(value)}")
    }
    String.join(parts.toArray(), delimiter: "&")
}

private func feishuAuthFormEncode(raw: String): String {
    let out = StringBuilder()
    let hex = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    for (b in raw.toArray()) {
        let v = Int64(b)
        if ((v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) ||
            v == 45 || v == 46 || v == 95 || v == 126) {
            out.append(String.fromUtf8([b]))
        } else if (v == 32) {
            out.append("+")
        } else {
            out.append("%")
            out.append(hex[(v >> 4) & 0x0F])
            out.append(hex[v & 0x0F])
        }
    }
    out.toString()
}

private func feishuAuthNativeAccountId(raw: String, user: GatewayUserSettings): String {
    let trimmed = raw.trimAscii()
    if (!trimmed.isEmpty()) {
        return gatewayFeishuNormalizeAccountId(trimmed)
    }
    gatewayFeishuNormalizeAccountId(user.feishu.defaultAccount)
}

private func feishuAuthNativeAccountConfig(accountId: String, user: GatewayUserSettings): JsonObject {
    match (user.feishu.accounts) {
        case Some(accounts) =>
            match (accounts.get(accountId)) {
                case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
                case None => JsonObject()
            }
        case None => JsonObject()
    }
}

private func feishuAuthJsonStringFallback(obj: JsonObject, keys: Array<String>, fallback: String): String {
    for (key in keys) {
        match (obj.get(key)) {
            case Some(v) => try { return v.asString().getValue().trimAscii() } catch (_e: Exception) { () }
            case None => ()
        }
    }
    fallback.trimAscii()
}

private func feishuAuthScopeSummary(obj: JsonObject): String {
    match (obj.get("scopes")) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (i in 0..arr.size()) {
                    try {
                        let scope = arr[i].asString().getValue().trimAscii()
                        if (!scope.isEmpty()) {
                            out.add(scope)
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
                return String.join(out.toArray(), delimiter: " ")
            } catch (_e: Exception) {
                ""
            }
        case None => ""
    }
}

private func feishuAuthScopeString(scopes: Array<String>): String {
    let out = ArrayList<String>()
    out.add("offline_access")
    for (scope in scopes) {
        let s = scope.trimAscii()
        if (!s.isEmpty() && s != "offline_access") {
            out.add(s)
        }
    }
    String.join(out.toArray(), delimiter: " ")
}

private func feishuAuthScopes(raw: String): Array<String> {
    let out = ArrayList<String>()
    for (piece in raw.trimAscii().split(" ")) {
        let scope = piece.trimAscii()
        if (!scope.isEmpty()) {
            out.add(scope)
        }
    }
    out.toArray()
}

private func feishuAuthJsonStringArray(items: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (item in items) {
        arr.add(JsonString(item.trimAscii()))
    }
    arr
}

private func feishuAuthStringArray(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let arr = v.asArray()
                let out = ArrayList<String>()
                for (i in 0..arr.size()) {
                    try {
                        let s = arr[i].asString().getValue().trimAscii()
                        if (!s.isEmpty()) {
                            out.add(s)
                        }
                    } catch (_: Exception) {
                        ()
                    }
                }
                out.toArray()
            } catch (_: Exception) {
                []
            }
        case None => []
    }
}

private func feishuAuthString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func feishuAuthInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asInt().getValue() } catch (_: Exception) {
                try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { fallback }
            }
        case None => fallback
    }
}

private func feishuAuthTokenErrorStatus(error: String): String {
    match (error.trimAscii().toAsciiLower()) {
        case "authorization_pending" => "authorization_pending"
        case "slow_down" => "slow_down"
        case "expired_token" => "expired"
        case "access_denied" => "denied"
        case _ => "error"
    }
}

private func feishuAuthSafeSegment(raw: String): String {
    let out = StringBuilder()
    for (r in gatewayFeishuNormalizeAccountId(raw).runes()) {
        if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'-' || r == r'_') {
            out.append(r)
        } else {
            out.append(r'_')
        }
    }
    let value = out.toString().trimAscii()
    if (value.isEmpty()) { "default" } else { value }
}
