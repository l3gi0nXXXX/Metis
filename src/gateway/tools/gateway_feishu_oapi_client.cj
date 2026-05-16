package metis.gateway.tools

import metis.core.config.MetisPaths

import std.collection.{ArrayList, HashMap, HashSet}
import std.convert.Parsable
import std.env.getVariable
import std.fs.{Directory, File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}
import stdx.encoding.url.URL
import stdx.net.http.*
import stdx.net.tls.*

private func feishuOapiRedactSensitiveText(raw: String): String {
    let text = raw.trimAscii()
    if (text.isEmpty()) {
        return ""
    }
    let lower = text.toAsciiLower()
    if (
        lower.contains("authorization:") ||
        lower.contains("bearer ") ||
        lower.contains("access_token") ||
        lower.contains("refresh_token") ||
        lower.contains("client_secret") ||
        lower.contains("appsecret") ||
        lower.contains("app_secret") ||
        lower.contains("secret") ||
        lower.contains("token=") ||
        lower.contains("password")
    ) {
        return "[redacted]"
    }
    text
}

public class FeishuOapiRequest {
    public let toolName: String
    public let actionKey: String
    public let category: String
    public let domain: String
    public let action: String
    public let accountId: String
    public let path: String
    public let method: String
    public let tokenMode: String
    public let params: JsonObject
    public let requiredScopes: Array<String>
    public let supported: Bool
    public let supportedActions: Array<String>

    public init(
        toolName: String,
        category: String,
        domain: String,
        action: String,
        accountId: String,
        path: String,
        method: String,
        tokenMode: String,
        params: JsonObject,
        requiredScopes: Array<String>
    ) {
        this.toolName = toolName.trimAscii()
        this.actionKey = feishuOapiActionKeyForToolAction(this.toolName, action)
        this.category = category.trimAscii()
        this.domain = domain.trimAscii()
        this.action = action.trimAscii()
        this.accountId = accountId.trimAscii()
        this.path = path.trimAscii()
        this.method = method.trimAscii()
        this.tokenMode = tokenMode.trimAscii()
        this.params = params
        this.requiredScopes = requiredScopes
        this.supported = feishuOapiIsSupportedActionKey(this.actionKey)
        this.supportedActions = feishuOapiSupportedActionsForTool(this.toolName)
    }

    public func toJson(): JsonObject {
        let out = JsonObject()
        out.put("tool", JsonString(this.toolName))
        out.put("action_key", JsonString(this.actionKey))
        out.put("category", JsonString(this.category))
        out.put("domain", JsonString(this.domain))
        out.put("action", JsonString(this.action))
        out.put("account_id", JsonString(this.accountId))
        out.put("path", JsonString(this.path))
        out.put("method", JsonString(this.method))
        out.put("token_mode", JsonString(this.tokenMode))
        out.put("required_scopes", feishuOapiJsonStringArray(this.requiredScopes))
        out.put("supported", JsonBool(this.supported))
        out.put("supported_actions", feishuOapiJsonStringArray(this.supportedActions))
        out.put("params", this.params)
        out
    }
}

public class FeishuOapiResult {
    private let request: FeishuOapiRequest
    private let ok: Bool
    private let status: String
    private let data: Option<JsonValue>
    private let error: String
    private let missingScopes: Array<String>
    private let authState: String
    private let scopeDiagnostic: Option<JsonObject>

    public init(
        request: FeishuOapiRequest,
        ok: Bool,
        status: String,
        data!: Option<JsonValue> = None<JsonValue>,
        error!: String = "",
        missingScopes!: Array<String> = [],
        authState!: String = "",
        scopeDiagnostic!: Option<JsonObject> = None<JsonObject>
    ) {
        this.request = request
        this.ok = ok
        this.status = status.trimAscii()
        this.data = data
        this.error = feishuOapiRedactSensitiveText(error)
        this.missingScopes = missingScopes
        this.authState = authState.trimAscii()
        this.scopeDiagnostic = scopeDiagnostic
    }

    public static func success(request: FeishuOapiRequest, data: JsonValue, scopeDiagnostic!: Option<JsonObject> = None<JsonObject>): FeishuOapiResult {
        FeishuOapiResult(request, true, "success", data: Some(data), scopeDiagnostic: scopeDiagnostic)
    }

    public static func authRequired(
        request: FeishuOapiRequest,
        authState!: String = "absent",
        error!: String = "",
        scopeDiagnostic!: Option<JsonObject> = None<JsonObject>
    ): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "auth_required",
            error: if (error.trimAscii().isEmpty()) {
                "Feishu OAPI user authorization is not configured in this runtime. Configure account auth before calling this tool against Feishu."
            } else {
                error.trimAscii()
            },
            authState: if (authState.trimAscii().isEmpty()) { "absent" } else { authState.trimAscii() },
            scopeDiagnostic: scopeDiagnostic
        )
    }

    public static func scopeMissing(
        request: FeishuOapiRequest,
        missingScopes: Array<String>,
        error!: String = "",
        scopeDiagnostic!: Option<JsonObject> = None<JsonObject>
    ): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "scope_missing",
            error: if (error.trimAscii().isEmpty()) { "Feishu OAPI required scope is missing." } else { error.trimAscii() },
            missingScopes: missingScopes,
            scopeDiagnostic: scopeDiagnostic
        )
    }

    public static func appScopeMissing(
        request: FeishuOapiRequest,
        missingScopes: Array<String>,
        error!: String = "",
        scopeDiagnostic!: Option<JsonObject> = None<JsonObject>
    ): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "app_scope_missing",
            error: if (error.trimAscii().isEmpty()) { "Feishu app is missing required OAPI scope(s)." } else { error.trimAscii() },
            missingScopes: missingScopes,
            scopeDiagnostic: scopeDiagnostic
        )
    }

    public static func unsupportedAction(request: FeishuOapiRequest): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "unsupported_action",
            error: "Unsupported Feishu OAPI action: ${request.actionKey}."
        )
    }

    public static func apiError(
        request: FeishuOapiRequest,
        error: String,
        data!: Option<JsonValue> = None<JsonValue>,
        scopeDiagnostic!: Option<JsonObject> = None<JsonObject>
    ): FeishuOapiResult {
        FeishuOapiResult(request, false, "api_error", data: data, error: error, scopeDiagnostic: scopeDiagnostic)
    }

    public static func invalidRequest(request: FeishuOapiRequest, error: String): FeishuOapiResult {
        FeishuOapiResult(request, false, "invalid_request", error: error)
    }

    public static func tokenModeUnsupported(
        request: FeishuOapiRequest,
        error!: String = "",
        scopeDiagnostic!: Option<JsonObject> = None<JsonObject>
    ): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "token_mode_unsupported",
            error: if (error.trimAscii().isEmpty()) { "Unsupported Feishu OAPI token mode: ${request.tokenMode}." } else { error.trimAscii() },
            scopeDiagnostic: scopeDiagnostic
        )
    }

    public static func missingCredential(
        request: FeishuOapiRequest,
        error!: String = "",
        scopeDiagnostic!: Option<JsonObject> = None<JsonObject>
    ): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "missing_credential",
            error: if (error.trimAscii().isEmpty()) {
                "Feishu appId/appSecret is required before issuing ${request.tokenMode}."
            } else {
                error.trimAscii()
            },
            scopeDiagnostic: scopeDiagnostic
        )
    }

    public func toJson(): JsonObject {
        let out = this.request.toJson()
        out.put("ok", JsonBool(this.ok))
        out.put("status", JsonString(this.status))
        out.put("client", JsonString("metis_feishu_oapi_client"))
        if (!this.error.isEmpty()) {
            out.put("error", JsonString(this.error))
            if (this.status == "invalid_request") {
                out.put("reason", JsonString(this.error))
            }
        }
        if (this.missingScopes.size > 0) {
            out.put("missing_scopes", feishuOapiJsonStringArray(this.missingScopes))
        }
        match (this.scopeDiagnostic) {
            case Some(v) => out.put("scope_diagnostic", v)
            case None => ()
        }
        match (this.data) {
            case Some(v) => out.put("data", v)
            case None => ()
        }
        if (this.status == "auth_required") {
            let auth = JsonObject()
            auth.put("required", JsonBool(true))
            auth.put("state", JsonString(if (this.authState.isEmpty()) { "absent" } else { this.authState }))
            auth.put("mode", JsonString(this.request.tokenMode))
            out.put("auth", auth)
        }
        if (this.status == "missing_credential") {
            let credential = JsonObject()
            credential.put("required", JsonBool(true))
            credential.put("mode", JsonString(this.request.tokenMode))
            credential.put("missing_fields", feishuOapiJsonStringArray(["app_id", "appSecret"]))
            credential.put("redacted", JsonBool(true))
            out.put("credential", credential)
        }
        out
    }
}

public class FeishuOapiTokenLookup {
    public let status: String
    public let accessToken: String
    public let missingScopes: Array<String>
    public let error: String
    public let grantedScopes: Array<String>
    public let hasOfflineAccess: Bool
    public let offlineAccessKnown: Bool

    public init(
        status: String,
        accessToken!: String = "",
        missingScopes!: Array<String> = [],
        error!: String = "",
        grantedScopes!: Array<String> = [],
        hasOfflineAccess!: Bool = false,
        offlineAccessKnown!: Bool = false
    ) {
        this.status = status.trimAscii()
        this.accessToken = accessToken.trimAscii()
        this.missingScopes = missingScopes
        this.error = error.trimAscii()
        this.grantedScopes = grantedScopes
        this.hasOfflineAccess = hasOfflineAccess || feishuOapiHasScope(grantedScopes, "offline_access")
        this.offlineAccessKnown = offlineAccessKnown || grantedScopes.size > 0 || this.status == "authorized" || this.status == "scope_missing"
    }
}

public class FeishuOapiAppScopeCheck {
    public let status: String
    public let grantedScopes: Array<String>
    public let missingScopes: Array<String>
    public let error: String

    public init(status: String, grantedScopes!: Array<String> = [], missingScopes!: Array<String> = [], error!: String = "") {
        let normalized = status.trimAscii()
        this.status = if (normalized.isEmpty()) { "ok" } else { normalized }
        this.grantedScopes = grantedScopes
        this.missingScopes = missingScopes
        this.error = error.trimAscii()
    }
}

public class FeishuOapiRefreshResult {
    public let status: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresInSeconds: Int64
    public let scopes: Array<String>
    public let error: String

    public init(
        status: String,
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
}

public class FeishuOapiAppCredentials {
    public let appId: String
    public let appSecret: String
    public let domain: String

    public init(appId: String, appSecret: String, domain!: String = "https://open.feishu.cn") {
        this.appId = appId.trimAscii()
        this.appSecret = appSecret.trimAscii()
        this.domain = feishuOapiNormalizeDomain(domain)
    }
}

public class FeishuOapiAppTokenResult {
    public let status: String
    public let accessToken: String
    public let expiresInSeconds: Int64
    public let error: String

    public init(status: String, accessToken!: String = "", expiresInSeconds!: Int64 = 0, error!: String = "") {
        this.status = if (status.trimAscii().isEmpty()) { "api_error" } else { status.trimAscii() }
        this.accessToken = accessToken.trimAscii()
        this.expiresInSeconds = expiresInSeconds
        this.error = error.trimAscii()
    }
}

public class FeishuOapiAuthRequestMerger {
    private let entries = HashMap<String, FeishuOapiAuthRequestMergeEntry>()

    public init() {}

    public func merge(turnKey: String, accountId: String, userId: String, scopes: Array<String>, status: String): JsonObject {
        let key = "${turnKey.trimAscii()}\u{0000}${accountId.trimAscii()}\u{0000}${userId.trimAscii()}"
        let entry = match (this.entries.get(key)) {
            case Some(v) => v
            case None =>
                let created = FeishuOapiAuthRequestMergeEntry(turnKey, accountId, userId)
                this.entries[key] = created
                created
        }
        entry.add(scopes, status)
        entry.toJson()
    }
}

private class FeishuOapiAuthRequestMergeEntry {
    private let turnKey: String
    private let accountId: String
    private let userId: String
    private let scopes = ArrayList<String>()
    private var requestCount: Int64 = 0
    private var hasAuthRequired: Bool = false
    private var hasAppScopeMissing: Bool = false

    init(turnKey: String, accountId: String, userId: String) {
        this.turnKey = turnKey.trimAscii()
        this.accountId = feishuOapiNormalizeAccountId(accountId)
        this.userId = userId.trimAscii()
    }

    func add(newScopes: Array<String>, status: String): Unit {
        this.requestCount++
        let cleanStatus = status.trimAscii()
        if (cleanStatus == "auth_required") {
            this.hasAuthRequired = true
        }
        if (cleanStatus == "app_scope_missing") {
            this.hasAppScopeMissing = true
        }
        for (scope in newScopes) {
            let clean = scope.trimAscii()
            if (!clean.isEmpty() && !this.scopes.contains(clean)) {
                this.scopes.add(clean)
            }
        }
    }

    func toJson(): JsonObject {
        let out = JsonObject()
        out.put("status", JsonString(if (this.hasAppScopeMissing) {
            "app_scope_missing"
        } else if (this.hasAuthRequired) {
            "auth_required"
        } else {
            "scope_missing"
        }))
        out.put("turn_key", JsonString(this.turnKey))
        out.put("account_id", JsonString(this.accountId))
        out.put("user_id", JsonString(this.userId))
        out.put("request_count", JsonInt(this.requestCount))
        out.put("merged", JsonBool(this.requestCount > 1))
        out.put("merged_scopes", feishuOapiJsonStringArray(this.scopes.toArray()))
        out.put("redacted", JsonBool(true))
        out
    }
}

public class FeishuOapiHttpResponse {
    public let ok: Bool
    public let statusCode: Int64
    public let body: JsonValue
    public let error: String

    public init(ok: Bool, statusCode!: Int64 = 0, body!: JsonValue = JsonObject(), error!: String = "") {
        this.ok = ok
        this.statusCode = statusCode
        this.body = body
        this.error = error.trimAscii()
    }
}

public class FeishuOapiResourceResult {
    public let ok: Bool
    public let status: String
    public let bytes: Array<Byte>
    public let contentType: String
    public let fileName: String
    public let error: String

    public init(
        ok!: Bool = false,
        status!: String = "not_configured",
        bytes!: Array<Byte> = [],
        contentType!: String = "",
        fileName!: String = "",
        error!: String = ""
    ) {
        this.ok = ok
        this.status = if (status.trimAscii().isEmpty()) { if (ok) { "ok" } else { "error" } } else { status.trimAscii() }
        this.bytes = bytes
        this.contentType = contentType.trimAscii()
        this.fileName = fileName.trimAscii()
        this.error = feishuOapiRedactSensitiveText(error)
    }
}

public interface FeishuOapiTokenProvider {
    func userAccessToken(accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup
    func tokenLookup(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup
}

public interface FeishuOapiAppScopeChecker {
    func check(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiAppScopeCheck
}

public interface FeishuOapiRefreshClient {
    func refresh(accountId: String, refreshToken: String): FeishuOapiRefreshResult
}

public interface FeishuOapiAppTokenClient {
    func fetch(accountId: String, tokenMode: String, credentials: FeishuOapiAppCredentials): FeishuOapiAppTokenResult
}

public interface FeishuOapiHttpClient {
    func request(request: FeishuOapiRequest, accessToken: String): FeishuOapiHttpResponse
}

public interface FeishuOapiResourceHttpClient {
    func fetchMessageResource(request: FeishuOapiRequest, accessToken: String): FeishuOapiResourceResult
}

public interface FeishuOapiClient {
    func invoke(request: FeishuOapiRequest): JsonObject
}

public interface FeishuOapiResourceClient {
    func fetchMessageResource(accountId: String, messageId: String, fileKey: String, resourceType: String): FeishuOapiResourceResult
}

public class FeishuOapiRawHttpRequest {
    public let accountId: String
    public let method: String
    public let url: String
    public let headers: HashMap<String, String>
    public let body: String

    public init(accountId: String, method: String, url: String, headers: HashMap<String, String>, body!: String = "") {
        this.accountId = if (accountId.trimAscii().isEmpty()) { "default" } else { accountId.trimAscii() }
        this.method = if (method.trimAscii().isEmpty()) { "GET" } else { method.trimAscii().toAsciiUpper() }
        this.url = url.trimAscii()
        this.headers = headers
        this.body = body
    }

    public func toRedactedJson(): JsonObject {
        let out = JsonObject()
        out.put("accountId", JsonString(this.accountId))
        out.put("method", JsonString(this.method))
        out.put("url", JsonString(this.url))
        out.put("hasBody", JsonBool(!this.body.isEmpty()))
        let headersJson = JsonObject()
        for ((key, value) in this.headers) {
            let normalized = key.trimAscii()
            if (normalized.toAsciiLower() == "authorization") {
                headersJson.put(normalized, JsonString("[redacted]"))
            } else {
                headersJson.put(normalized, JsonString(value.trimAscii()))
            }
        }
        out.put("headers", headersJson)
        out.put("redacted", JsonBool(true))
        out
    }
}

public class FeishuOapiRawHttpResponse {
    public let statusCode: Int64
    public let body: String
    public let error: String

    public init(statusCode: Int64, body!: String = "", error!: String = "") {
        this.statusCode = statusCode
        this.body = body
        this.error = error.trimAscii()
    }
}

public interface FeishuOapiRawHttpTransport {
    func send(request: FeishuOapiRawHttpRequest): FeishuOapiRawHttpResponse
}

private class FeishuOapiCachedAppToken {
    let accessToken: String
    let expiresAtMs: Int64

    init(accessToken: String, expiresAtMs: Int64) {
        this.accessToken = accessToken.trimAscii()
        this.expiresAtMs = expiresAtMs
    }
}

public class MetisFeishuOapiTokenProvider <: FeishuOapiTokenProvider {
    private let root: Path
    private let refreshClient: Option<FeishuOapiRefreshClient>
    private let appId: String
    private let appSecret: String
    private let appDomain: String
    private let appTokenClient: Option<FeishuOapiAppTokenClient>
    private let nowMsValue: Int64
    private let appTokenCache = HashMap<String, FeishuOapiCachedAppToken>()

    public init(
        root!: Path = feishuOapiDefaultTokenStoreRoot(),
        refreshClient!: Option<FeishuOapiRefreshClient> = None<FeishuOapiRefreshClient>,
        appId!: String = feishuOapiEnvValue("METIS_FEISHU_OAPI_APP_ID"),
        appSecret!: String = feishuOapiEnvValue("METIS_FEISHU_OAPI_APP_SECRET"),
        appDomain!: String = feishuOapiEnvValue("METIS_FEISHU_OAPI_DOMAIN"),
        appTokenClient!: Option<FeishuOapiAppTokenClient> = None<FeishuOapiAppTokenClient>,
        nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
    ) {
        this.root = root
        this.refreshClient = refreshClient
        this.appId = appId.trimAscii()
        this.appSecret = appSecret.trimAscii()
        this.appDomain = if (appDomain.trimAscii().isEmpty()) { "https://open.feishu.cn" } else { feishuOapiNormalizeDomain(appDomain) }
        this.appTokenClient = appTokenClient
        this.nowMsValue = nowMs
    }

    public func userAccessToken(accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        let normalized = feishuOapiNormalizeAccountId(accountId)
        let token = match (this.load(normalized)) {
            case Some(v) => v
            case None => return FeishuOapiTokenLookup("auth_required", error: "Feishu user authorization is missing for account ${normalized}.")
        }
        let missing = feishuOapiMissingScopes(token.scopes, requiredScopes)
        if (missing.size > 0) {
            return FeishuOapiTokenLookup(
                "scope_missing",
                missingScopes: missing,
                error: "Feishu user authorization is missing required scope(s).",
                grantedScopes: token.scopes,
                hasOfflineAccess: feishuOapiHasScope(token.scopes, "offline_access")
            )
        }
        if (token.expiresAtMs <= this.nowMsValue) {
            return this.refreshOrExpired(normalized, token, requiredScopes)
        }
        if (token.accessToken.isEmpty()) {
            return FeishuOapiTokenLookup(
                "auth_required",
                error: "Stored Feishu user authorization does not contain an access token.",
                grantedScopes: token.scopes,
                hasOfflineAccess: feishuOapiHasScope(token.scopes, "offline_access")
            )
        }
        FeishuOapiTokenLookup(
            "authorized",
            accessToken: token.accessToken,
            grantedScopes: token.scopes,
            hasOfflineAccess: feishuOapiHasScope(token.scopes, "offline_access")
        )
    }

    public func tokenLookup(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        match (tokenMode.trimAscii()) {
            case "user_access_token" => this.userAccessToken(accountId, requiredScopes)
            case "tenant_access_token" => this.appToken(accountId, "tenant_access_token", requiredScopes)
            case "bot_access_token" => this.appToken(accountId, "bot_access_token", requiredScopes)
            case "app_access_token" => this.appToken(accountId, "app_access_token", requiredScopes)
            case _ =>
                FeishuOapiTokenLookup(
                    "token_mode_unsupported",
                    error: "Unsupported Feishu OAPI token mode: ${tokenMode.trimAscii()}."
                )
        }
    }

    private func appToken(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        let normalized = feishuOapiNormalizeAccountId(accountId)
        let cleanMode = tokenMode.trimAscii()
        if (this.appId.isEmpty() || this.appSecret.isEmpty()) {
            return FeishuOapiTokenLookup(
                "missing_credential",
                error: "Feishu appId/appSecret is required before issuing ${cleanMode}."
            )
        }
        let cacheKey = "${normalized}\u{0000}${cleanMode}"
        match (this.appTokenCache.get(cacheKey)) {
            case Some(cached) =>
                if (!cached.accessToken.isEmpty() && this.nowMsValue < cached.expiresAtMs - 60 * 1000) {
                    return FeishuOapiTokenLookup(
                        "authorized",
                        accessToken: cached.accessToken,
                        grantedScopes: requiredScopes,
                        hasOfflineAccess: false
                    )
                }
            case None => ()
        }
        let credentials = FeishuOapiAppCredentials(this.appId, this.appSecret, domain: this.appDomain)
        let result = match (this.appTokenClient) {
            case Some(client) => client.fetch(normalized, cleanMode, credentials)
            case None => FeishuNativeOapiAppTokenClient(domain: this.appDomain).fetch(normalized, cleanMode, credentials)
        }
        if (result.status != "authorized" || result.accessToken.isEmpty()) {
            return FeishuOapiTokenLookup(
                if (result.status.isEmpty()) { "api_error" } else { result.status },
                error: if (result.error.isEmpty()) { "Feishu OAPI app token request failed." } else { result.error }
            )
        }
        let ttlSeconds = if (result.expiresInSeconds > 0) { result.expiresInSeconds } else { 7200 }
        this.appTokenCache[cacheKey] = FeishuOapiCachedAppToken(
            result.accessToken,
            this.nowMsValue + ttlSeconds * 1000
        )
        FeishuOapiTokenLookup(
            "authorized",
            accessToken: result.accessToken,
            grantedScopes: requiredScopes,
            hasOfflineAccess: false
        )
    }

    private func refreshOrExpired(accountId: String, token: FeishuOapiStoredToken, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        if (token.refreshToken.isEmpty()) {
            return FeishuOapiTokenLookup(
                "expired",
                error: "Stored Feishu user authorization is expired and has no refresh token.",
                grantedScopes: token.scopes,
                hasOfflineAccess: feishuOapiHasScope(token.scopes, "offline_access")
            )
        }
        let refreshed = match (this.refreshClient) {
            case Some(client) => client.refresh(accountId, token.refreshToken)
            case None => return FeishuOapiTokenLookup(
                "expired",
                error: "Stored Feishu user authorization is expired.",
                grantedScopes: token.scopes,
                hasOfflineAccess: feishuOapiHasScope(token.scopes, "offline_access")
            )
        }
        if (refreshed.status != "authorized" || refreshed.accessToken.isEmpty()) {
            return FeishuOapiTokenLookup(
                if (refreshed.status.isEmpty()) { "expired" } else { refreshed.status },
                error: if (refreshed.error.isEmpty()) { "Feishu user authorization refresh did not return an access token." } else { refreshed.error },
                grantedScopes: token.scopes,
                hasOfflineAccess: feishuOapiHasScope(token.scopes, "offline_access")
            )
        }
        let scopes = if (refreshed.scopes.size > 0) { refreshed.scopes } else { token.scopes }
        let missing = feishuOapiMissingScopes(scopes, requiredScopes)
        if (missing.size > 0) {
            return FeishuOapiTokenLookup(
                "scope_missing",
                missingScopes: missing,
                error: "Refreshed Feishu user authorization is missing required scope(s).",
                grantedScopes: scopes,
                hasOfflineAccess: feishuOapiHasScope(scopes, "offline_access")
            )
        }
        this.save(accountId, FeishuOapiStoredToken(
            accessToken: refreshed.accessToken,
            refreshToken: if (refreshed.refreshToken.isEmpty()) { token.refreshToken } else { refreshed.refreshToken },
            expiresAtMs: this.nowMsValue + refreshed.expiresInSeconds * 1000,
            scopes: scopes
        ))
        FeishuOapiTokenLookup(
            "authorized",
            accessToken: refreshed.accessToken,
            grantedScopes: scopes,
            hasOfflineAccess: feishuOapiHasScope(scopes, "offline_access")
        )
    }

    private func load(accountId: String): Option<FeishuOapiStoredToken> {
        let path = this.pathFor(accountId)
        if (!exists(path)) {
            return None<FeishuOapiStoredToken>
        }
        try {
            let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
            return Some(FeishuOapiStoredToken(
                accessToken: feishuOapiJsonString(root, "accessToken"),
                refreshToken: feishuOapiJsonString(root, "refreshToken"),
                expiresAtMs: feishuOapiJsonInt(root, "expiresAtMs", 0),
                scopes: feishuOapiJsonStringArrayField(root, "scopes")
            ))
        } catch (_e: Exception) {
            return None<FeishuOapiStoredToken>
        }
    }

    private func save(accountId: String, token: FeishuOapiStoredToken): Unit {
        if (!exists(this.root)) {
            Directory.create(this.root, recursive: true)
        }
        let obj = JsonObject()
        obj.put("accessToken", JsonString(token.accessToken))
        obj.put("refreshToken", JsonString(token.refreshToken))
        obj.put("expiresAtMs", JsonInt(token.expiresAtMs))
        obj.put("scopes", feishuOapiJsonStringArray(token.scopes))
        File.writeTo(this.pathFor(accountId), obj.toJsonString().toArray())
    }

    private func pathFor(accountId: String): Path {
        this.root.join("${feishuOapiSafeAccountSegment(accountId)}.json")
    }
}

private class FeishuOapiStoredToken {
    let accessToken: String
    let refreshToken: String
    let expiresAtMs: Int64
    let scopes: Array<String>

    init(accessToken!: String = "", refreshToken!: String = "", expiresAtMs!: Int64 = 0, scopes!: Array<String> = []) {
        this.accessToken = accessToken.trimAscii()
        this.refreshToken = refreshToken.trimAscii()
        this.expiresAtMs = expiresAtMs
        this.scopes = scopes
    }
}

public class FeishuNativeOapiAppTokenClient <: FeishuOapiAppTokenClient {
    private let domain: String
    private let transport: Option<FeishuOapiRawHttpTransport>

    public init(
        domain!: String = "https://open.feishu.cn",
        transport!: Option<FeishuOapiRawHttpTransport> = None<FeishuOapiRawHttpTransport>
    ) {
        this.domain = feishuOapiNormalizeDomain(domain)
        this.transport = transport
    }

    public func fetch(accountId: String, tokenMode: String, credentials: FeishuOapiAppCredentials): FeishuOapiAppTokenResult {
        if (credentials.appId.isEmpty() || credentials.appSecret.isEmpty()) {
            return FeishuOapiAppTokenResult(
                "missing_credential",
                error: "Feishu appId/appSecret is required before issuing ${tokenMode.trimAscii()}."
            )
        }
        let cleanMode = tokenMode.trimAscii()
        let path = match (cleanMode) {
            case "tenant_access_token" => "/open-apis/auth/v3/tenant_access_token/internal"
            case "bot_access_token" => "/open-apis/auth/v3/tenant_access_token/internal"
            case "app_access_token" => "/open-apis/auth/v3/app_access_token/internal"
            case _ => return FeishuOapiAppTokenResult(
                "token_mode_unsupported",
                error: "Unsupported Feishu OAPI app token mode: ${cleanMode}."
            )
        }
        let headers = HashMap<String, String>([
            ("Content-Type", "application/json; charset=utf-8"),
            ("Accept", "application/json")
        ])
        let body = JsonObject()
        body.put("app_id", JsonString(credentials.appId))
        body.put("app_secret", JsonString(credentials.appSecret))
        let raw = FeishuOapiRawHttpRequest(
            accountId,
            "POST",
            "${this.domain}${path}",
            headers,
            body: body.toJsonString()
        )
        let response = match (this.transport) {
            case Some(t) => t.send(raw)
            case None => FeishuNativeOapiRawHttpTransport().send(raw)
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            return FeishuOapiAppTokenResult(
                "api_error",
                error: if (response.error.isEmpty()) { "Feishu app token request failed with HTTP ${response.statusCode}." } else { response.error }
            )
        }
        try {
            let parsed = JsonValue.fromStr(response.body).asObject()
            let code = feishuOapiResponseCode(parsed)
            if (!code.isEmpty() && code != "0") {
                return FeishuOapiAppTokenResult("api_error", error: "Feishu app token endpoint returned code ${code}.")
            }
            let field = if (cleanMode == "app_access_token") { "app_access_token" } else { "tenant_access_token" }
            let token = feishuOapiJsonString(parsed, field)
            if (token.isEmpty()) {
                return FeishuOapiAppTokenResult("api_error", error: "Feishu app token endpoint did not return ${field}.")
            }
            let expires = feishuOapiJsonInt(parsed, "expire", 7200)
            return FeishuOapiAppTokenResult("authorized", accessToken: token, expiresInSeconds: expires)
        } catch (e: Exception) {
            return FeishuOapiAppTokenResult("api_error", error: "Feishu app token response is not valid JSON: ${e.message}")
        }
    }
}

public class FeishuNativeOapiHttpClient <: FeishuOapiHttpClient {
    private let domain: String
    private let transport: Option<FeishuOapiRawHttpTransport>
    private let timeoutSeconds: Int64

    public init(
        domain!: String = "https://open.feishu.cn",
        transport!: Option<FeishuOapiRawHttpTransport> = None<FeishuOapiRawHttpTransport>,
        timeoutSeconds!: Int64 = 30
    ) {
        this.domain = feishuOapiNormalizeDomain(domain)
        this.transport = transport
        this.timeoutSeconds = if (timeoutSeconds <= 0) { 30 } else { timeoutSeconds }
    }

    public func request(request: FeishuOapiRequest, accessToken: String): FeishuOapiHttpResponse {
        let raw = feishuOapiBuildRawHttpRequest(this.domain, request, accessToken)
        let response = match (this.transport) {
            case Some(t) => t.send(raw)
            case None => FeishuNativeOapiRawHttpTransport(timeoutSeconds: this.timeoutSeconds).send(raw)
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
            let (parsed, body) = feishuOapiParseBodyWithStatus(response.body)
            return FeishuOapiHttpResponse(
                false,
                statusCode: response.statusCode,
                body: body,
                error: if (!response.error.isEmpty()) { response.error } else if (!parsed) { "Feishu OAPI response body is not valid JSON." } else { "" }
            )
        }
        let (parsed, body) = feishuOapiParseBodyWithStatus(response.body)
        if (!parsed) {
            return FeishuOapiHttpResponse(false, statusCode: response.statusCode, body: body, error: "Feishu OAPI response body is not valid JSON.")
        }
        let apiCode = feishuOapiResponseCode(body)
        if (!apiCode.isEmpty() && apiCode != "0") {
            return FeishuOapiHttpResponse(false, statusCode: response.statusCode, body: body, error: "Feishu OAPI returned code ${apiCode}.")
        }
        FeishuOapiHttpResponse(true, statusCode: response.statusCode, body: body)
    }
}

public class FeishuNativeOapiRawHttpTransport <: FeishuOapiRawHttpTransport {
    private let timeoutSeconds: Int64

    public init(timeoutSeconds!: Int64 = 30) {
        this.timeoutSeconds = if (timeoutSeconds <= 0) { 30 } else { timeoutSeconds }
    }

    public func send(request: FeishuOapiRawHttpRequest): FeishuOapiRawHttpResponse {
        try {
            let builder = ClientBuilder()
            builder.readTimeout(Duration.second * this.timeoutSeconds)
            if (request.url.startsWith("https")) {
                var tlsConfig = TlsClientConfig()
                tlsConfig.domain = URL.parse(request.url).hostName
                tlsConfig.alpnProtocolsList = ["http/1.1"]
                builder.tlsConfig(tlsConfig)
            }
            let client = builder.build()
            try {
                let reqBuilder = HttpRequestBuilder().url(request.url)
                match (request.method) {
                    case "POST" => reqBuilder.post()
                    case "PATCH" => reqBuilder.method("PATCH")
                    case "DELETE" => reqBuilder.method("DELETE")
                    case "PUT" => reqBuilder.method("PUT")
                    case _ => reqBuilder.get()
                }
                if (!request.body.isEmpty()) {
                    reqBuilder.body(request.body)
                }
                for ((key, value) in request.headers) {
                    reqBuilder.header(key, value)
                }
                let response = client.send(reqBuilder.build())
                let bytes = feishuOapiReadAllBytes(response)
                let body = try { String.fromUtf8(bytes) } catch (_e: Exception) { "" }
                return FeishuOapiRawHttpResponse(Int64(response.status), body: body)
            } finally {
                client.close()
            }
        } catch (e: Exception) {
            FeishuOapiRawHttpResponse(0, error: e.message)
        }
    }
}

public class MetisFeishuOapiClient <: FeishuOapiClient {
    private let tokenProvider: Option<FeishuOapiTokenProvider>
    private let httpClient: Option<FeishuOapiHttpClient>
    private let appScopeChecker: Option<FeishuOapiAppScopeChecker>

    public init(
        tokenProvider!: Option<FeishuOapiTokenProvider> = None<FeishuOapiTokenProvider>,
        httpClient!: Option<FeishuOapiHttpClient> = None<FeishuOapiHttpClient>,
        appScopeChecker!: Option<FeishuOapiAppScopeChecker> = None<FeishuOapiAppScopeChecker>
    ) {
        this.tokenProvider = tokenProvider
        this.httpClient = httpClient
        this.appScopeChecker = appScopeChecker
    }

    public func invoke(request: FeishuOapiRequest): JsonObject {
        if (!request.supported) {
            return FeishuOapiResult.unsupportedAction(request).toJson()
        }
        let appScope = match (this.appScopeChecker) {
            case Some(checker) => Some(checker.check(request.accountId, request.tokenMode, request.requiredScopes))
            case None => None<FeishuOapiAppScopeCheck>
        }
        match (appScope) {
            case Some(check) =>
                if (check.status == "app_scope_missing") {
                    return FeishuOapiResult.appScopeMissing(
                        request,
                        check.missingScopes,
                        error: check.error,
                        scopeDiagnostic: Some(feishuOapiScopeDiagnostic(request, appScope, None<FeishuOapiTokenLookup>))
                    ).toJson()
                }
                if (check.status == "token_mode_unsupported") {
                    return FeishuOapiResult.invalidRequest(request, if (check.error.isEmpty()) { "Unsupported Feishu OAPI token mode: ${request.tokenMode}." } else { check.error }).toJson()
                }
            case None => ()
        }
        let token = match (this.tokenProvider) {
            case Some(provider) => provider.tokenLookup(request.accountId, request.tokenMode, request.requiredScopes)
            case None => return FeishuOapiResult.authRequired(
                request,
                scopeDiagnostic: Some(feishuOapiScopeDiagnostic(request, appScope, None<FeishuOapiTokenLookup>))
            ).toJson()
        }
        let scopeDiagnostic = Some(feishuOapiScopeDiagnostic(request, appScope, Some(token)))
        if (token.status == "token_mode_unsupported") {
            return FeishuOapiResult.tokenModeUnsupported(request, error: token.error, scopeDiagnostic: scopeDiagnostic).toJson()
        }
        if (token.status == "missing_credential") {
            return FeishuOapiResult.missingCredential(request, error: token.error, scopeDiagnostic: scopeDiagnostic).toJson()
        }
        if (token.status == "api_error") {
            return FeishuOapiResult.apiError(request, if (token.error.isEmpty()) { "Feishu OAPI token request failed." } else { token.error }, scopeDiagnostic: scopeDiagnostic).toJson()
        }
        if (token.status == "app_scope_missing") {
            return FeishuOapiResult.appScopeMissing(request, token.missingScopes, error: token.error, scopeDiagnostic: scopeDiagnostic).toJson()
        }
        if (token.status == "scope_missing") {
            return FeishuOapiResult.scopeMissing(request, token.missingScopes, error: token.error, scopeDiagnostic: scopeDiagnostic).toJson()
        }
        if (token.status == "expired") {
            return FeishuOapiResult.authRequired(request, authState: "expired", error: token.error, scopeDiagnostic: scopeDiagnostic).toJson()
        }
        if (token.status == "auth_required" || token.accessToken.isEmpty()) {
            return FeishuOapiResult.authRequired(request, authState: token.status, error: token.error, scopeDiagnostic: scopeDiagnostic).toJson()
        }
        match (this.httpClient) {
            case Some(http) =>
                let response = http.request(request, token.accessToken)
                if (response.ok) {
                    return FeishuOapiResult.success(request, response.body, scopeDiagnostic: scopeDiagnostic).toJson()
                }
                let code = feishuOapiResponseCode(response.body)
                if (code == "99991672") {
                    return FeishuOapiResult.appScopeMissing(request, request.requiredScopes, error: response.error, scopeDiagnostic: scopeDiagnostic).toJson()
                }
                if (code == "99991679") {
                    return FeishuOapiResult.scopeMissing(request, request.requiredScopes, error: response.error, scopeDiagnostic: scopeDiagnostic).toJson()
                }
                return FeishuOapiResult.apiError(
                    request,
                    if (response.error.isEmpty()) { "Feishu OAPI request failed with HTTP ${response.statusCode}." } else { response.error },
                    data: Some(response.body),
                    scopeDiagnostic: scopeDiagnostic
                ).toJson()
            case None =>
                FeishuOapiResult.apiError(request, "Feishu OAPI HTTP client is not configured for this runtime.", scopeDiagnostic: scopeDiagnostic).toJson()
        }
    }
}

public class MetisFeishuOapiResourceClient <: FeishuOapiResourceClient {
    private let tokenProvider: Option<FeishuOapiTokenProvider>
    private let httpClient: Option<FeishuOapiResourceHttpClient>

    public init(
        tokenProvider!: Option<FeishuOapiTokenProvider> = None<FeishuOapiTokenProvider>,
        httpClient!: Option<FeishuOapiResourceHttpClient> = None<FeishuOapiResourceHttpClient>
    ) {
        this.tokenProvider = tokenProvider
        this.httpClient = httpClient
    }

    public func fetchMessageResource(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String
    ): FeishuOapiResourceResult {
        let params = JsonObject()
        params.put("message_id", JsonString(messageId.trimAscii()))
        params.put("file_key", JsonString(fileKey.trimAscii()))
        params.put("type", JsonString(resourceType.trimAscii()))
        let request = feishuOapiBuildRequest("feishu_im_user_fetch_resource", "fetch", accountId, params)
        let token = match (this.tokenProvider) {
            case Some(provider) => provider.userAccessToken(request.accountId, request.requiredScopes)
            case None =>
                return FeishuOapiResourceResult(
                    status: "auth_required",
                    error: "Feishu OAPI user authorization is not configured for historical resource fetch."
                )
        }
        if (token.status == "scope_missing") {
            return FeishuOapiResourceResult(
                status: "scope_missing",
                error: if (token.error.isEmpty()) { "Feishu OAPI required resource scope is missing." } else { token.error }
            )
        }
        if (token.status == "auth_required" || token.accessToken.isEmpty()) {
            return FeishuOapiResourceResult(
                status: "auth_required",
                error: if (token.error.isEmpty()) { "Feishu OAPI user authorization is required for historical resource fetch." } else { token.error }
            )
        }
        match (this.httpClient) {
            case Some(http) => http.fetchMessageResource(request, token.accessToken)
            case None =>
                FeishuOapiResourceResult(
                    status: "not_configured",
                    error: "Feishu OAPI resource HTTP client is not configured for this runtime."
                )
        }
    }
}

public func feishuOapiBuildRequest(toolName: String, action: String, accountId: String, params: JsonObject): FeishuOapiRequest {
    let cleanTool = toolName.trimAscii()
    let cleanAction = if (action.trimAscii().isEmpty()) { "default" } else { action.trimAscii() }
    let category = feishuOapiCategoryForTool(cleanTool)
    let actionKey = feishuOapiActionKeyForToolAction(cleanTool, cleanAction)
    FeishuOapiRequest(
        cleanTool,
        category,
        feishuOapiDomainForCategory(category),
        cleanAction,
        if (accountId.trimAscii().isEmpty()) { "default" } else { accountId.trimAscii() },
        feishuOapiPathForActionKey(actionKey),
        feishuOapiMethodForActionKey(actionKey),
        feishuOapiTokenModeForActionKey(actionKey),
        params,
        feishuOapiRequiredScopesForActionKey(actionKey)
    )
}

public func feishuOapiJsonStringArray(values: Array<String>): JsonArray {
    let arr = JsonArray([])
    for (value in values) {
        arr.add(JsonString(value.trimAscii()))
    }
    arr
}

public func feishuOapiCategoryForTool(toolName: String): String {
    let name = toolName.trimAscii()
    if (name == "feishu_oauth" || name == "feishu_oauth_batch_auth") {
        return "oauth"
    }
    if (name == "feishu_ask_user_question") {
        return "interaction"
    }
    if (name == "feishu_fetch_doc" || name == "feishu_create_doc" || name == "feishu_update_doc" || name.startsWith("feishu_doc_")) {
        return "docs"
    }
    if (name.startsWith("feishu_wiki_")) {
        return "wiki"
    }
    if (name.startsWith("feishu_drive_")) {
        return "drive"
    }
    if (name.startsWith("feishu_search_doc")) {
        return "search"
    }
    if (name.startsWith("feishu_bitable_")) {
        return "bitable"
    }
    if (name.startsWith("feishu_calendar_")) {
        return "calendar"
    }
    if (name.startsWith("feishu_task_")) {
        return "task"
    }
    if (name == "feishu_sheet") {
        return "sheets"
    }
    if (name.startsWith("feishu_chat")) {
        return "chat"
    }
    if (name == "feishu_get_user" || name == "feishu_search_user") {
        return "user"
    }
    if (name.startsWith("feishu_im_")) {
        return "im"
    }
    "oapi"
}

public func feishuOapiDomainForCategory(category: String): String {
    match (category.trimAscii()) {
        case "user" => "common"
        case "chat" => "chat"
        case "im" => "im"
        case "docs" => "docs"
        case "wiki" => "wiki"
        case "drive" => "drive"
        case "search" => "search"
        case "calendar" => "calendar"
        case "task" => "task"
        case "sheets" => "sheets"
        case "bitable" => "bitable"
        case "oauth" => "oauth"
        case "interaction" => "interaction"
        case _ => "common"
    }
}

public func feishuOapiRequiredScopesForTool(toolName: String, _category: String, action: String): Array<String> {
    feishuOapiRequiredScopesForActionKey(feishuOapiActionKeyForToolAction(toolName, action))
}

public func feishuOapiActionKeyForToolAction(toolName: String, action: String): String {
    let tool = toolName.trimAscii()
    let rawAction = if (action.trimAscii().isEmpty()) { "default" } else { action.trimAscii().toAsciiLower() }
    let normalizedAction = match (tool) {
        case "feishu_fetch_doc" => "default"
        case "feishu_create_doc" => "default"
        case "feishu_update_doc" => "default"
        case "feishu_get_user" =>
            if (rawAction == "basic_batch") { "basic_batch" } else { "default" }
        case "feishu_search_user" => "default"
        case "feishu_chat_members" => "default"
        case "feishu_im_user_get_messages" => "default"
        case "feishu_im_user_get_thread_messages" => "default"
        case "feishu_im_user_search_messages" => "default"
        case "feishu_im_user_fetch_resource" => "default"
        case "feishu_im_bot_image" => "default"
        case "feishu_oauth" => "default"
        case "feishu_oauth_batch_auth" => "default"
        case "feishu_ask_user_question" => "default"
        case "feishu_im_user_message" =>
            if (rawAction == "create") { "send" } else { rawAction }
        case _ => rawAction
    }
    if (tool == "feishu_im_user_get_thread_messages") {
        return "feishu_im_user_get_messages.default"
    }
    if (tool == "feishu_im_bot_image") {
        return "feishu_im_user_fetch_resource.default"
    }
    "${tool}.${normalizedAction}"
}

public func feishuOapiSupportedActionsForTool(toolName: String): Array<String> {
    match (toolName.trimAscii()) {
        case "feishu_chat" => ["get", "search"]
        case "feishu_im_user_message" => ["send", "reply"]
        case "feishu_sheet" => ["info", "read", "write", "append", "find", "create", "export"]
        case "feishu_drive_file" => ["list", "get_meta", "copy", "move", "delete", "upload", "download"]
        case "feishu_wiki_space" => ["list", "get", "create"]
        case "feishu_wiki_space_node" => ["list", "get", "create", "move", "copy"]
        case "feishu_doc_comments" => ["list", "list_replies", "create", "reply", "patch"]
        case "feishu_doc_media" => ["download", "insert"]
        case "feishu_bitable_app" => ["create", "get", "list", "patch", "copy"]
        case "feishu_bitable_app_table" => ["create", "list", "patch", "batch_create"]
        case "feishu_bitable_app_table_record" => ["create", "update", "delete", "batch_create", "batch_update", "batch_delete", "list"]
        case "feishu_bitable_app_table_field" => ["create", "list", "update", "delete"]
        case "feishu_bitable_app_table_view" => ["create", "get", "list", "patch"]
        case "feishu_calendar_calendar" => ["list", "get", "primary"]
        case "feishu_calendar_event" => ["create", "list", "get", "patch", "delete", "search", "reply", "instances", "instance_view"]
        case "feishu_calendar_event_attendee" => ["create", "list"]
        case "feishu_calendar_freebusy" => ["list"]
        case "feishu_task_task" => ["create", "get", "list", "patch", "add_members", "append_steps"]
        case "feishu_task_tasklist" => ["create", "get", "list", "tasks", "patch", "add_members"]
        case "feishu_task_attachment" => ["upload"]
        case "feishu_task_section" => ["create", "get", "list", "patch", "tasks"]
        case "feishu_task_comment" => ["create", "list", "get"]
        case "feishu_task_subtask" => ["create", "list"]
        case "feishu_task_agent" => ["register", "update_profile"]
        case "feishu_search_doc_wiki" => ["search"]
        case "feishu_fetch_doc" => ["default"]
        case "feishu_create_doc" => ["default"]
        case "feishu_update_doc" => ["default"]
        case "feishu_get_user" => ["default", "basic_batch"]
        case "feishu_search_user" => ["default"]
        case "feishu_chat_members" => ["default"]
        case "feishu_im_user_get_messages" => ["default"]
        case "feishu_im_user_get_thread_messages" => ["default"]
        case "feishu_im_user_search_messages" => ["default"]
        case "feishu_im_user_fetch_resource" => ["default"]
        case "feishu_im_bot_image" => ["default"]
        case "feishu_oauth" => ["default"]
        case "feishu_oauth_batch_auth" => ["default"]
        case "feishu_ask_user_question" => ["default"]
        case _ => []
    }
}

public func feishuOapiIsSupportedActionKey(actionKey: String): Bool {
    feishuOapiPathForActionKey(actionKey) != ""
}

public func feishuOapiOpenClawActionKeys(): Array<String> {
    [
        "feishu_bitable_app.copy", "feishu_bitable_app.create", "feishu_bitable_app.get", "feishu_bitable_app.list",
        "feishu_bitable_app.patch", "feishu_bitable_app_table.batch_create", "feishu_bitable_app_table.create",
        "feishu_bitable_app_table.list", "feishu_bitable_app_table.patch", "feishu_bitable_app_table_field.create",
        "feishu_bitable_app_table_field.delete", "feishu_bitable_app_table_field.list", "feishu_bitable_app_table_field.update",
        "feishu_bitable_app_table_record.batch_create", "feishu_bitable_app_table_record.batch_delete",
        "feishu_bitable_app_table_record.batch_update", "feishu_bitable_app_table_record.create",
        "feishu_bitable_app_table_record.delete", "feishu_bitable_app_table_record.list", "feishu_bitable_app_table_record.update",
        "feishu_bitable_app_table_view.create", "feishu_bitable_app_table_view.get", "feishu_bitable_app_table_view.list",
        "feishu_bitable_app_table_view.patch", "feishu_calendar_calendar.get", "feishu_calendar_calendar.list",
        "feishu_calendar_calendar.primary", "feishu_calendar_event.create", "feishu_calendar_event.delete",
        "feishu_calendar_event.get", "feishu_calendar_event.instance_view", "feishu_calendar_event.instances",
        "feishu_calendar_event.list", "feishu_calendar_event.patch", "feishu_calendar_event.reply",
        "feishu_calendar_event.search", "feishu_calendar_event_attendee.create", "feishu_calendar_event_attendee.list",
        "feishu_calendar_freebusy.list", "feishu_chat.get", "feishu_chat.search", "feishu_chat_members.default",
        "feishu_create_doc.default", "feishu_doc_comments.create", "feishu_doc_comments.list",
        "feishu_doc_comments.list_replies", "feishu_doc_comments.patch", "feishu_doc_comments.reply",
        "feishu_doc_media.download", "feishu_doc_media.insert", "feishu_drive_file.copy", "feishu_drive_file.delete",
        "feishu_drive_file.download", "feishu_drive_file.get_meta", "feishu_drive_file.list", "feishu_drive_file.move",
        "feishu_drive_file.upload", "feishu_fetch_doc.default", "feishu_get_user.basic_batch", "feishu_get_user.default",
        "feishu_im_user_fetch_resource.default", "feishu_im_user_get_messages.default", "feishu_im_user_message.reply",
        "feishu_im_user_message.send", "feishu_im_user_search_messages.default", "feishu_search_doc_wiki.search",
        "feishu_search_user.default", "feishu_task_attachment.upload", "feishu_task_comment.create",
        "feishu_task_comment.get", "feishu_task_comment.list", "feishu_task_section.create", "feishu_task_section.get",
        "feishu_task_section.list", "feishu_task_section.patch", "feishu_task_section.tasks", "feishu_task_subtask.create",
        "feishu_task_subtask.list", "feishu_task_task.create", "feishu_task_task.get", "feishu_task_task.list",
        "feishu_task_task.patch", "feishu_task_task.add_members", "feishu_task_task.append_steps",
        "feishu_task_tasklist.add_members", "feishu_task_tasklist.create", "feishu_task_tasklist.get",
        "feishu_task_tasklist.list", "feishu_task_tasklist.patch", "feishu_task_tasklist.tasks",
        "feishu_task_agent.register", "feishu_task_agent.update_profile", "feishu_update_doc.default",
        "feishu_wiki_space.create", "feishu_wiki_space.get", "feishu_wiki_space.list", "feishu_wiki_space_node.copy",
        "feishu_wiki_space_node.create", "feishu_wiki_space_node.get", "feishu_wiki_space_node.list",
        "feishu_wiki_space_node.move", "feishu_sheet.info", "feishu_sheet.read", "feishu_sheet.write",
        "feishu_sheet.append", "feishu_sheet.find", "feishu_sheet.create", "feishu_sheet.export"
    ]
}

public func feishuOapiPathForActionKeyForTest(actionKey: String): String {
    feishuOapiPathForActionKey(actionKey)
}

public func feishuOapiMethodForActionKeyForTest(actionKey: String): String {
    feishuOapiMethodForActionKey(actionKey)
}

public func feishuOapiRequiredScopesForActionKeyForTest(actionKey: String): Array<String> {
    feishuOapiRequiredScopesForActionKey(actionKey)
}

private func feishuOapiTokenModeForActionKey(actionKey: String): String {
    match (actionKey) {
        case "feishu_doc_comments.list_replies" => "tenant_access_token"
        case "feishu_task_task.append_steps" => "tenant_access_token"
        case "feishu_im_user_fetch_resource.default" => "bot_access_token"
        case "feishu_ask_user_question.default" => "app_access_token"
        case "feishu_oauth.default" => "app_access_token"
        case "feishu_oauth_batch_auth.default" => "app_access_token"
        case _ => "user_access_token"
    }
}

private func feishuOapiMethodForActionKey(actionKey: String): String {
    match (actionKey) {
        case "feishu_oauth.default" => "POST"
        case "feishu_oauth_batch_auth.default" => "POST"
        case "feishu_ask_user_question.default" => "POST"
        case "feishu_create_doc.default" => "POST"
        case "feishu_update_doc.default" => "PATCH"
        case "feishu_chat.search" => "GET"
        case "feishu_search_user.default" => "GET"
        case "feishu_im_user_message.send" => "POST"
        case "feishu_im_user_message.reply" => "POST"
        case "feishu_get_user.basic_batch" => "POST"
        case "feishu_search_doc_wiki.search" => "POST"
        case "feishu_sheet.write" => "PUT"
        case "feishu_sheet.append" => "POST"
        case "feishu_sheet.create" => "POST"
        case "feishu_sheet.export" => "POST"
        case "feishu_drive_file.get_meta" => "POST"
        case "feishu_drive_file.copy" => "POST"
        case "feishu_drive_file.move" => "POST"
        case "feishu_drive_file.delete" => "DELETE"
        case "feishu_drive_file.upload" => "POST"
        case "feishu_doc_comments.create" => "POST"
        case "feishu_doc_comments.reply" => "POST"
        case "feishu_doc_comments.patch" => "PATCH"
        case "feishu_doc_media.insert" => "POST"
        case "feishu_wiki_space.create" => "POST"
        case "feishu_wiki_space_node.create" => "POST"
        case "feishu_wiki_space_node.move" => "POST"
        case "feishu_wiki_space_node.copy" => "POST"
        case "feishu_calendar_event.reply" => "POST"
        case "feishu_calendar_freebusy.list" => "POST"
        case "feishu_task_attachment.upload" => "POST"
        case _ =>
            let action = actionKey.split(".")[1].trimAscii()
            if (action == "create" || action == "batch_create" || action == "register" || action == "add_members" || action == "append_steps" ||
                action == "copy" || action == "reply" || action == "upload" || action == "export") {
                "POST"
            } else if (action == "patch" || action == "update" || action == "update_profile" || action == "batch_update") {
                "PATCH"
            } else if (action == "delete" || action == "batch_delete") {
                "DELETE"
            } else {
                "GET"
            }
    }
}

private func feishuOapiPathForActionKey(actionKey: String): String {
    match (actionKey) {
        case "feishu_oauth.default" => "/open-apis/authen/v1/oidc/device_authorize"
        case "feishu_oauth_batch_auth.default" => "/open-apis/authen/v1/oidc/device_authorize"
        case "feishu_ask_user_question.default" => "/open-apis/cardkit/v1/cards"
        case "feishu_fetch_doc.default" => "/open-apis/docx/v1/documents/:document_id/raw_content"
        case "feishu_create_doc.default" => "/open-apis/docx/v1/documents"
        case "feishu_update_doc.default" => "/open-apis/docx/v1/documents/:document_id"
        case "feishu_doc_comments.list" => "/open-apis/docx/v1/documents/:document_id/comments"
        case "feishu_doc_comments.list_replies" => "/open-apis/docx/v1/documents/:document_id/comments/:comment_id/replies"
        case "feishu_doc_comments.create" => "/open-apis/docx/v1/documents/:document_id/comments"
        case "feishu_doc_comments.reply" => "/open-apis/docx/v1/documents/:document_id/comments/:comment_id/replies"
        case "feishu_doc_comments.patch" => "/open-apis/docx/v1/documents/:document_id/comments/:comment_id"
        case "feishu_doc_media.download" => "/open-apis/docx/v1/documents/:document_id/media/:file_token/download"
        case "feishu_doc_media.insert" => "/open-apis/docx/v1/documents/:document_id/media"
        case "feishu_wiki_space.list" => "/open-apis/wiki/v2/spaces"
        case "feishu_wiki_space.get" => "/open-apis/wiki/v2/spaces/:space_id"
        case "feishu_wiki_space.create" => "/open-apis/wiki/v2/spaces"
        case "feishu_wiki_space_node.list" => "/open-apis/wiki/v2/spaces/:space_id/nodes"
        case "feishu_wiki_space_node.get" => "/open-apis/wiki/v2/spaces/:space_id/nodes/:node_token"
        case "feishu_wiki_space_node.create" => "/open-apis/wiki/v2/spaces/:space_id/nodes"
        case "feishu_wiki_space_node.move" => "/open-apis/wiki/v2/spaces/:space_id/nodes/:node_token/move"
        case "feishu_wiki_space_node.copy" => "/open-apis/wiki/v2/spaces/:space_id/nodes/:node_token/copy"
        case "feishu_drive_file.list" => "/open-apis/drive/v1/files"
        case "feishu_drive_file.get_meta" => "/open-apis/drive/v1/metas/batch_query"
        case "feishu_drive_file.copy" => "/open-apis/drive/v1/files/:file_token/copy"
        case "feishu_drive_file.move" => "/open-apis/drive/v1/files/:file_token/move"
        case "feishu_drive_file.delete" => "/open-apis/drive/v1/files/:file_token"
        case "feishu_drive_file.upload" => "/open-apis/drive/v1/files/upload_all"
        case "feishu_drive_file.download" => "/open-apis/drive/v1/files/:file_token/download"
        case "feishu_search_doc_wiki.search" => "/open-apis/search/v2/data_sources/:data_source_id/search"
        case "feishu_sheet.info" => "/open-apis/sheets/v3/spreadsheets/:spreadsheet_token"
        case "feishu_sheet.read" => "/open-apis/sheets/v2/spreadsheets/:spreadsheet_token/values/:range"
        case "feishu_sheet.write" => "/open-apis/sheets/v2/spreadsheets/:spreadsheet_token/values"
        case "feishu_sheet.append" => "/open-apis/sheets/v2/spreadsheets/:spreadsheet_token/values_append"
        case "feishu_sheet.find" => "/open-apis/sheets/v3/spreadsheets/:spreadsheet_token/sheets/:sheet_id/find"
        case "feishu_sheet.create" => "/open-apis/sheets/v3/spreadsheets"
        case "feishu_sheet.export" => "/open-apis/drive/v1/export_tasks"
        case "feishu_chat.search" => "/open-apis/im/v1/chats/search"
        case "feishu_chat.get" => "/open-apis/im/v1/chats/:chat_id"
        case "feishu_chat_members.default" => "/open-apis/im/v1/chats/:chat_id/members"
        case "feishu_get_user.default" => "/open-apis/contact/v3/users/:user_id"
        case "feishu_get_user.basic_batch" => "/open-apis/contact/v3/users/basic_batch"
        case "feishu_search_user.default" => "/open-apis/search/v1/user"
        case "feishu_im_user_message.send" => "/open-apis/im/v1/messages"
        case "feishu_im_user_message.reply" => "/open-apis/im/v1/messages/:message_id/reply"
        case "feishu_im_user_get_messages.default" => "/open-apis/im/v1/messages"
        case "feishu_im_user_search_messages.default" => "/open-apis/search/v2/data_sources/im_message/search"
        case "feishu_im_user_fetch_resource.default" => "/open-apis/im/v1/messages/:message_id/resources/:file_key"
        case "feishu_bitable_app.create" => "/open-apis/bitable/v1/apps"
        case "feishu_bitable_app.get" => "/open-apis/bitable/v1/apps/:app_token"
        case "feishu_bitable_app.list" => "/open-apis/bitable/v1/apps"
        case "feishu_bitable_app.patch" => "/open-apis/bitable/v1/apps/:app_token"
        case "feishu_bitable_app.copy" => "/open-apis/bitable/v1/apps/:app_token/copy"
        case "feishu_bitable_app_table.create" => "/open-apis/bitable/v1/apps/:app_token/tables"
        case "feishu_bitable_app_table.list" => "/open-apis/bitable/v1/apps/:app_token/tables"
        case "feishu_bitable_app_table.patch" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id"
        case "feishu_bitable_app_table.batch_create" => "/open-apis/bitable/v1/apps/:app_token/tables/batch_create"
        case "feishu_bitable_app_table_record.create" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records"
        case "feishu_bitable_app_table_record.update" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records/:record_id"
        case "feishu_bitable_app_table_record.delete" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records/:record_id"
        case "feishu_bitable_app_table_record.batch_create" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records/batch_create"
        case "feishu_bitable_app_table_record.batch_update" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records/batch_update"
        case "feishu_bitable_app_table_record.batch_delete" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records/batch_delete"
        case "feishu_bitable_app_table_record.list" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records"
        case "feishu_bitable_app_table_field.create" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/fields"
        case "feishu_bitable_app_table_field.list" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/fields"
        case "feishu_bitable_app_table_field.update" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/fields/:field_id"
        case "feishu_bitable_app_table_field.delete" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/fields/:field_id"
        case "feishu_bitable_app_table_view.create" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/views"
        case "feishu_bitable_app_table_view.get" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/views/:view_id"
        case "feishu_bitable_app_table_view.list" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/views"
        case "feishu_bitable_app_table_view.patch" => "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/views/:view_id"
        case "feishu_calendar_calendar.list" => "/open-apis/calendar/v4/calendars"
        case "feishu_calendar_calendar.get" => "/open-apis/calendar/v4/calendars/:calendar_id"
        case "feishu_calendar_calendar.primary" => "/open-apis/calendar/v4/calendars/primary"
        case "feishu_calendar_event.create" => "/open-apis/calendar/v4/calendars/:calendar_id/events"
        case "feishu_calendar_event.list" => "/open-apis/calendar/v4/calendars/:calendar_id/events"
        case "feishu_calendar_event.get" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id"
        case "feishu_calendar_event.patch" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id"
        case "feishu_calendar_event.delete" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id"
        case "feishu_calendar_event.search" => "/open-apis/calendar/v4/calendars/:calendar_id/events/search"
        case "feishu_calendar_event.reply" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/reply"
        case "feishu_calendar_event.instances" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/instances"
        case "feishu_calendar_event.instance_view" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/instance_view"
        case "feishu_calendar_event_attendee.create" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/attendees"
        case "feishu_calendar_event_attendee.list" => "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/attendees"
        case "feishu_calendar_freebusy.list" => "/open-apis/calendar/v4/freebusy/list"
        case "feishu_task_task.create" => "/open-apis/task/v2/tasks"
        case "feishu_task_task.get" => "/open-apis/task/v2/tasks/:task_guid"
        case "feishu_task_task.list" => "/open-apis/task/v2/tasks"
        case "feishu_task_task.patch" => "/open-apis/task/v2/tasks/:task_guid"
        case "feishu_task_task.add_members" => "/open-apis/task/v2/tasks/:task_guid/add_members"
        case "feishu_task_task.append_steps" => "/open-apis/task/v2/tasks/:task_guid/append_steps"
        case "feishu_task_tasklist.create" => "/open-apis/task/v2/tasklists"
        case "feishu_task_tasklist.get" => "/open-apis/task/v2/tasklists/:tasklist_guid"
        case "feishu_task_tasklist.list" => "/open-apis/task/v2/tasklists"
        case "feishu_task_tasklist.tasks" => "/open-apis/task/v2/tasklists/:tasklist_guid/tasks"
        case "feishu_task_tasklist.patch" => "/open-apis/task/v2/tasklists/:tasklist_guid"
        case "feishu_task_tasklist.add_members" => "/open-apis/task/v2/tasklists/:tasklist_guid/add_members"
        case "feishu_task_attachment.upload" => "/open-apis/task/v2/tasks/:task_guid/attachments"
        case "feishu_task_section.create" => "/open-apis/task/v2/tasklists/:tasklist_guid/sections"
        case "feishu_task_section.get" => "/open-apis/task/v2/tasklists/:tasklist_guid/sections/:section_guid"
        case "feishu_task_section.list" => "/open-apis/task/v2/tasklists/:tasklist_guid/sections"
        case "feishu_task_section.patch" => "/open-apis/task/v2/tasklists/:tasklist_guid/sections/:section_guid"
        case "feishu_task_section.tasks" => "/open-apis/task/v2/tasklists/:tasklist_guid/sections/:section_guid/tasks"
        case "feishu_task_comment.create" => "/open-apis/task/v2/tasks/:task_guid/comments"
        case "feishu_task_comment.list" => "/open-apis/task/v2/tasks/:task_guid/comments"
        case "feishu_task_comment.get" => "/open-apis/task/v2/tasks/:task_guid/comments/:comment_id"
        case "feishu_task_subtask.create" => "/open-apis/task/v2/tasks/:task_guid/subtasks"
        case "feishu_task_subtask.list" => "/open-apis/task/v2/tasks/:task_guid/subtasks"
        case "feishu_task_agent.register" => "/open-apis/task/v2/tasks/:task_guid/collaborators"
        case "feishu_task_agent.update_profile" => "/open-apis/task/v2/tasks/:task_guid/collaborators/:user_id"
        case _ => ""
    }
}

private func feishuOapiRequiredScopesForActionKey(actionKey: String): Array<String> {
    match (actionKey) {
        case "feishu_chat.search" => ["im:chat:read"]
        case "feishu_chat.get" => ["im:chat:read"]
        case "feishu_chat_members.default" => ["im:chat.members:read"]
        case "feishu_get_user.default" => ["contact:contact.base:readonly", "contact:user.base:readonly"]
        case "feishu_get_user.basic_batch" => ["contact:user.basic_profile:readonly"]
        case "feishu_search_user.default" => ["contact:user:search"]
        case "feishu_im_user_message.send" => ["im:message", "im:message.send_as_user"]
        case "feishu_im_user_message.reply" => ["im:message", "im:message.send_as_user"]
        case "feishu_im_user_fetch_resource.default" => ["im:message.group_msg:get_as_user", "im:message.p2p_msg:get_as_user", "im:message:readonly"]
        case "feishu_im_user_get_messages.default" => ["im:chat:read", "im:message:readonly", "im:message.group_msg:get_as_user", "im:message.p2p_msg:get_as_user", "contact:contact.base:readonly", "contact:user.base:readonly"]
        case "feishu_im_user_search_messages.default" => ["im:chat:read", "im:message:readonly", "im:message.group_msg:get_as_user", "im:message.p2p_msg:get_as_user", "contact:contact.base:readonly", "contact:user.base:readonly", "search:message"]
        case "feishu_fetch_doc.default" => ["docx:document:readonly", "wiki:node:read"]
        case "feishu_create_doc.default" => ["board:whiteboard:node:create", "docx:document:create", "docx:document:readonly", "docx:document:write_only", "wiki:node:create", "wiki:node:read", "docs:document.media:upload"]
        case "feishu_update_doc.default" => ["board:whiteboard:node:create", "docx:document:create", "docx:document:readonly", "docx:document:write_only"]
        case "feishu_doc_comments.list" => ["wiki:node:read", "docs:document.comment:read"]
        case "feishu_doc_comments.list_replies" => ["wiki:node:read", "docs:document.comment:read"]
        case "feishu_doc_comments.create" => ["wiki:node:read", "docs:document.comment:create"]
        case "feishu_doc_comments.reply" => ["wiki:node:read", "docs:document.comment:create"]
        case "feishu_doc_comments.patch" => ["docs:document.comment:update"]
        case "feishu_doc_media.download" => ["board:whiteboard:node:read", "docs:document.media:download"]
        case "feishu_doc_media.insert" => ["docx:document:write_only", "docs:document.media:upload"]
        case "feishu_wiki_space.list" => ["wiki:space:retrieve"]
        case "feishu_wiki_space.get" => ["wiki:space:read"]
        case "feishu_wiki_space.create" => ["wiki:space:write_only"]
        case "feishu_wiki_space_node.list" => ["wiki:node:retrieve"]
        case "feishu_wiki_space_node.get" => ["wiki:node:read"]
        case "feishu_wiki_space_node.create" => ["wiki:node:create"]
        case "feishu_wiki_space_node.move" => ["wiki:node:move"]
        case "feishu_wiki_space_node.copy" => ["wiki:node:copy"]
        case "feishu_bitable_app.copy" => ["base:app:copy"]
        case "feishu_bitable_app_table.create" => ["base:table:create"]
        case "feishu_bitable_app_table.list" => ["base:table:read"]
        case "feishu_bitable_app_table.patch" => ["base:table:update"]
        case "feishu_bitable_app_table.batch_create" => ["base:table:create"]
        case "feishu_bitable_app_table_record.create" => ["base:record:create"]
        case "feishu_bitable_app_table_record.update" => ["base:record:update"]
        case "feishu_bitable_app_table_record.batch_create" => ["base:record:create"]
        case "feishu_bitable_app_table_record.batch_update" => ["base:record:update"]
        case "feishu_bitable_app_table_record.list" => ["base:record:retrieve"]
        case "feishu_bitable_app_table_view.create" => ["base:view:write_only"]
        case "feishu_bitable_app_table_view.get" => ["base:view:read"]
        case "feishu_bitable_app_table_view.list" => ["base:view:read"]
        case "feishu_bitable_app_table_view.patch" => ["base:view:write_only"]
        case "feishu_drive_file.list" => ["space:document:retrieve"]
        case "feishu_drive_file.get_meta" => ["drive:drive.metadata:readonly"]
        case "feishu_drive_file.copy" => ["docs:document:copy"]
        case "feishu_drive_file.move" => ["space:document:move"]
        case "feishu_drive_file.delete" => ["space:document:delete"]
        case "feishu_drive_file.upload" => ["drive:file:upload"]
        case "feishu_drive_file.download" => ["drive:file:download"]
        case "feishu_search_doc_wiki.search" => ["search:docs:read"]
        case "feishu_sheet.info" => ["sheets:spreadsheet.meta:read", "sheets:spreadsheet:read"]
        case "feishu_sheet.read" => ["sheets:spreadsheet.meta:read", "sheets:spreadsheet:read"]
        case "feishu_sheet.write" => ["sheets:spreadsheet.meta:read", "sheets:spreadsheet:read", "sheets:spreadsheet:create", "sheets:spreadsheet:write_only"]
        case "feishu_sheet.append" => ["sheets:spreadsheet.meta:read", "sheets:spreadsheet:read", "sheets:spreadsheet:create", "sheets:spreadsheet:write_only"]
        case "feishu_sheet.find" => ["sheets:spreadsheet.meta:read", "sheets:spreadsheet:read"]
        case "feishu_sheet.create" => ["sheets:spreadsheet.meta:read", "sheets:spreadsheet:read", "sheets:spreadsheet:create", "sheets:spreadsheet:write_only"]
        case "feishu_sheet.export" => ["docs:document:export"]
        case "feishu_calendar_event_attendee.create" => ["calendar:calendar.event:update"]
        case "feishu_calendar_event_attendee.list" => ["calendar:calendar.event:read"]
        case "feishu_task_attachment.upload" => ["task:attachment:write"]
        case "feishu_task_comment.create" => ["task:comment:write"]
        case "feishu_task_comment.list" => ["task:comment:read", "task:comment:write"]
        case "feishu_task_comment.get" => ["task:comment:read", "task:comment:write"]
        case "feishu_task_section.create" => ["task:task"]
        case "feishu_task_section.get" => ["task:task"]
        case "feishu_task_section.list" => ["task:task"]
        case "feishu_task_section.patch" => ["task:task"]
        case "feishu_task_section.tasks" => ["task:task"]
        case "feishu_task_task.create" => ["task:task:write", "task:task:writeonly"]
        case "feishu_task_task.patch" => ["task:task:write", "task:task:writeonly"]
        case "feishu_task_task.add_members" => ["task:task:write", "task:task:writeonly"]
        case "feishu_task_task.append_steps" => ["task:task:write", "task:task:writeonly"]
        case "feishu_task_tasklist.create" => ["task:tasklist:write"]
        case "feishu_task_tasklist.get" => ["task:tasklist:read", "task:tasklist:write"]
        case "feishu_task_tasklist.list" => ["task:tasklist:read", "task:tasklist:write"]
        case "feishu_task_tasklist.tasks" => ["task:tasklist:read", "task:tasklist:write"]
        case "feishu_task_tasklist.patch" => ["task:tasklist:write"]
        case "feishu_task_tasklist.add_members" => ["task:tasklist:write"]
        case "feishu_task_agent.update_profile" => ["task:task:write", "task:task:writeonly"]
        case "feishu_oauth.default" => ["offline_access"]
        case "feishu_oauth_batch_auth.default" => ["offline_access"]
        case "feishu_ask_user_question.default" => ["cardkit:card"]
        case _ =>
            feishuOapiFallbackScopesForActionKey(actionKey)
    }
}

private func feishuOapiFallbackScopesForActionKey(actionKey: String): Array<String> {
    if (actionKey.startsWith("feishu_bitable_app_table_field.")) {
        match (actionKey) {
            case "feishu_bitable_app_table_field.create" => return ["base:field:create"]
            case "feishu_bitable_app_table_field.list" => return ["base:field:read"]
            case "feishu_bitable_app_table_field.update" => return ["base:field:read", "base:field:update"]
            case "feishu_bitable_app_table_field.delete" => return ["base:field:delete"]
            case _ => return []
        }
    }
    if (actionKey.startsWith("feishu_bitable_")) {
        if (actionKey.contains(".list")) { return ["space:document:retrieve"] }
        if (actionKey.contains(".create") || actionKey.contains(".batch_create")) { return ["base:app:create"] }
        if (actionKey.contains(".patch") || actionKey.contains(".update") || actionKey.contains(".batch_update")) { return ["base:app:update"] }
        if (actionKey.contains(".delete") || actionKey.contains(".batch_delete")) { return ["base:record:delete"] }
        return ["base:app:read"]
    }
    if (actionKey.startsWith("feishu_calendar_event.")) {
        if (actionKey.endsWith(".create")) { return ["calendar:calendar.event:create", "calendar:calendar.event:update"] }
        if (actionKey.endsWith(".patch")) { return ["calendar:calendar.event:update"] }
        if (actionKey.endsWith(".delete")) { return ["calendar:calendar.event:delete"] }
        if (actionKey.endsWith(".reply")) { return ["calendar:calendar.event:reply"] }
        return ["calendar:calendar.event:read"]
    }
    if (actionKey.startsWith("feishu_calendar_")) {
        if (actionKey == "feishu_calendar_freebusy.list") { return ["calendar:calendar.free_busy:read"] }
        return ["calendar:calendar:read"]
    }
    if (actionKey.startsWith("feishu_task_")) {
        if (actionKey.contains(".create") || actionKey.contains(".patch") || actionKey.contains(".add_members") || actionKey.contains(".append_steps") || actionKey.contains(".register") || actionKey.contains(".update_profile")) {
            return ["task:task:write"]
        }
        return ["task:task:read", "task:task:write"]
    }
    []
}

public func feishuOapiDefaultTokenStoreRoot(): Path {
    MetisPaths.homeRoot().join("feishu").join("user-tokens")
}

private class FeishuOapiStaticTokenProvider <: FeishuOapiTokenProvider {
    private let accessToken: String
    private let grantedScopes: Array<String>

    init(accessToken: String, grantedScopes: Array<String>) {
        this.accessToken = accessToken.trimAscii()
        this.grantedScopes = grantedScopes
    }

    public func userAccessToken(_accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        let missing = feishuOapiMissingScopes(this.grantedScopes, requiredScopes)
        if (missing.size > 0) {
            return FeishuOapiTokenLookup(
                "scope_missing",
                missingScopes: missing,
                error: "METIS_FEISHU_OAPI_LIVE_USER_SCOPES is missing required scope(s).",
                grantedScopes: this.grantedScopes,
                hasOfflineAccess: feishuOapiHasScope(this.grantedScopes, "offline_access")
            )
        }
        FeishuOapiTokenLookup(
            "authorized",
            accessToken: this.accessToken,
            grantedScopes: this.grantedScopes,
            hasOfflineAccess: feishuOapiHasScope(this.grantedScopes, "offline_access")
        )
    }

    public func tokenLookup(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        if (tokenMode.trimAscii() == "user_access_token") {
            return this.userAccessToken(accountId, requiredScopes)
        }
        FeishuOapiTokenLookup(
            "token_mode_unsupported",
            error: "Static Feishu OAPI live-smoke token provider only supports user_access_token."
        )
    }
}

private class FeishuOapiStaticAppScopeChecker <: FeishuOapiAppScopeChecker {
    private let grantedScopes: Array<String>

    init(grantedScopes: Array<String>) {
        this.grantedScopes = grantedScopes
    }

    public func check(_accountId: String, _tokenMode: String, requiredScopes: Array<String>): FeishuOapiAppScopeCheck {
        let missing = feishuOapiMissingScopes(this.grantedScopes, requiredScopes)
        if (missing.size > 0) {
            return FeishuOapiAppScopeCheck(
                "app_scope_missing",
                grantedScopes: this.grantedScopes,
                missingScopes: missing,
                error: "METIS_FEISHU_OAPI_LIVE_APP_SCOPES is missing required app scope(s)."
            )
        }
        FeishuOapiAppScopeCheck("ok", grantedScopes: this.grantedScopes)
    }
}

private func feishuOapiWriteLiveSmokeReportIfRequested(out: JsonObject): JsonObject {
    let rawDir = feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_REPORT_DIR").trimAscii()
    if (rawDir.isEmpty()) {
        return out
    }
    try {
        let root = Path(rawDir)
        if (!exists(root)) {
            Directory.create(root, recursive: true)
        }
        let reportPath = root.join("report.json")
        out.put("reportPath", JsonString(reportPath.toString()))
        File.writeTo(reportPath, out.toJsonString().toArray())
    } catch (e: Exception) {
        out.put("reportStatus", JsonString("write_failed"))
        out.put("reportError", JsonString(e.message))
    }
    out
}

public func feishuOapiLiveSmokeHarnessFromEnv(): JsonObject {
    let required = JsonArray([
        JsonString("METIS_FEISHU_OAPI_LIVE_SMOKE"),
        JsonString("METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN"),
        JsonString("METIS_FEISHU_OAPI_LIVE_USER_SCOPES"),
        JsonString("METIS_FEISHU_OAPI_LIVE_APP_SCOPES"),
        JsonString("METIS_FEISHU_OAPI_LIVE_CASES_JSON")
    ])
    if (!feishuOapiEnvEnabled(feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_SMOKE"))) {
        let out = JsonObject()
        out.put("status", JsonString("skipped"))
        out.put("reason", JsonString("env_gate_disabled"))
        out.put("live", JsonBool(false))
        out.put("redacted", JsonBool(true))
        out.put("requiresEnv", required)
        return feishuOapiWriteLiveSmokeReportIfRequested(out)
    }

    let accessToken = feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN")
    let userScopes = feishuOapiSplitScopes(feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_USER_SCOPES"))
    let appScopes = feishuOapiSplitScopes(feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_APP_SCOPES"))
    let casesRaw = feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_CASES_JSON")
    let missingEnv = JsonArray([])
    if (accessToken.isEmpty()) {
        missingEnv.add(JsonString("METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN"))
    }
    if (userScopes.size == 0) {
        missingEnv.add(JsonString("METIS_FEISHU_OAPI_LIVE_USER_SCOPES"))
    }
    if (appScopes.size == 0) {
        missingEnv.add(JsonString("METIS_FEISHU_OAPI_LIVE_APP_SCOPES"))
    }
    if (casesRaw.isEmpty()) {
        missingEnv.add(JsonString("METIS_FEISHU_OAPI_LIVE_CASES_JSON"))
    }
    if (missingEnv.size() > 0) {
        let out = JsonObject()
        out.put("status", JsonString("skipped"))
        out.put("reason", JsonString("external-resource-required"))
        out.put("blocker", JsonString("missing_live_smoke_env"))
        out.put("externalResourceRequired", JsonBool(true))
        out.put("missingEnv", missingEnv)
        out.put("live", JsonBool(false))
        out.put("networkAttempted", JsonBool(false))
        out.put("redacted", JsonBool(true))
        out.put("requiresEnv", required)
        return feishuOapiWriteLiveSmokeReportIfRequested(out)
    }

    let cases = try {
        JsonValue.fromStr(casesRaw).asArray()
    } catch (e: Exception) {
        let out = JsonObject()
        out.put("status", JsonString("invalid_request"))
        out.put("reason", JsonString("METIS_FEISHU_OAPI_LIVE_CASES_JSON must be a JSON array: ${e.message}"))
        out.put("live", JsonBool(false))
        out.put("redacted", JsonBool(true))
        out.put("requiresEnv", required)
        return feishuOapiWriteLiveSmokeReportIfRequested(out)
    }

    let domain = feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_DOMAIN")
    let defaultAccount = feishuOapiEnvValue("METIS_FEISHU_OAPI_LIVE_ACCOUNT_ID")
    let client = MetisFeishuOapiClient(
        tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiStaticTokenProvider(accessToken, userScopes)),
        appScopeChecker: Some<FeishuOapiAppScopeChecker>(FeishuOapiStaticAppScopeChecker(appScopes)),
        httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
            domain: if (domain.isEmpty()) { "https://open.feishu.cn" } else { domain }
        ))
    )
    let results = JsonArray([])
    var failures: Int64 = 0
    for (i in 0..cases.size()) {
        let item = try { cases[i].asObject() } catch (_e: Exception) { JsonObject() }
        let tool = feishuOapiJsonString(item, "tool")
        let action = if (feishuOapiJsonString(item, "action").isEmpty()) { "default" } else { feishuOapiJsonString(item, "action") }
        let accountId = if (feishuOapiJsonString(item, "accountId").isEmpty()) { defaultAccount } else { feishuOapiJsonString(item, "accountId") }
        let params = match (feishuOapiObjectField(item, "params")) {
            case Some(v) => v
            case None => JsonObject()
        }
        let request = feishuOapiBuildRequest(tool, action, if (accountId.isEmpty()) { "default" } else { accountId }, params)
        let invoked = client.invoke(request)
        let ok = try { invoked.get("ok").getOrThrow().asBool().getValue() } catch (_e: Exception) { false }
        if (!ok) {
            failures++
        }
        let row = JsonObject()
        row.put("tool", JsonString(request.toolName))
        row.put("action", JsonString(request.action))
        row.put("accountId", JsonString(request.accountId))
        row.put("path", JsonString(request.path))
        row.put("method", JsonString(request.method))
        row.put("tokenMode", JsonString(request.tokenMode))
        row.put("ok", JsonBool(ok))
        row.put("status", invoked.get("status") ?? JsonString("unknown"))
        row.put("missing_scopes", invoked.get("missing_scopes") ?? JsonArray([]))
        row.put("hasData", JsonBool(invoked.get("data").isSome()))
        row.put("redacted", JsonBool(true))
        results.add(row)
    }
    let out = JsonObject()
    out.put("status", JsonString(if (failures == 0) { "ok" } else { "completed_with_failures" }))
    out.put("live", JsonBool(true))
    out.put("redacted", JsonBool(true))
    out.put("caseCount", JsonInt(cases.size()))
    out.put("failureCount", JsonInt(failures))
    out.put("results", results)
    out.put("requiresEnv", required)
    feishuOapiWriteLiveSmokeReportIfRequested(out)
}

public func feishuOapiSmokeDryRunPlanFromCases(
    casesRaw: String,
    defaultAccountId!: String = "default",
    domain!: String = "https://open.feishu.cn"
): JsonObject {
    let out = JsonObject()
    out.put("status", JsonString("dry_run"))
    out.put("live", JsonBool(false))
    out.put("networkAttempted", JsonBool(false))
    out.put("externalResourceRequired", JsonBool(true))
    out.put("redacted", JsonBool(true))
    out.put("writeRequiresLiveOptIn", JsonBool(true))
    out.put("domain", JsonString(feishuOapiNormalizeDomain(domain)))

    let cases = try {
        JsonValue.fromStr(casesRaw.trimAscii()).asArray()
    } catch (e: Exception) {
        out.put("status", JsonString("invalid_request"))
        out.put("reason", JsonString("cases_json must be a JSON array: ${e.message}"))
        out.put("requests", JsonArray([]))
        out.put("caseCount", JsonInt(0))
        out.put("readCount", JsonInt(0))
        out.put("writeCount", JsonInt(0))
        return out
    }

    let requests = JsonArray([])
    var readCount: Int64 = 0
    var writeCount: Int64 = 0
    for (i in 0..cases.size()) {
        let item = try { cases[i].asObject() } catch (_e: Exception) { JsonObject() }
        let tool = feishuOapiJsonString(item, "tool")
        let action = if (feishuOapiJsonString(item, "action").isEmpty()) { "default" } else { feishuOapiJsonString(item, "action") }
        let accountId = if (feishuOapiJsonString(item, "accountId").isEmpty()) { defaultAccountId } else { feishuOapiJsonString(item, "accountId") }
        let params = match (feishuOapiObjectField(item, "params")) {
            case Some(v) => v
            case None => JsonObject()
        }
        let request = feishuOapiBuildRequest(tool, action, if (accountId.trimAscii().isEmpty()) { "default" } else { accountId }, params)
        let raw = feishuOapiBuildRawHttpRequest(domain, request, "dry-run-redacted-token")
        let row = raw.toRedactedJson()
        let operation = feishuOapiOperationKind(request.method)
        if (operation == "read") {
            readCount++
        } else {
            writeCount++
        }
        row.put("tool", JsonString(request.toolName))
        row.put("action", JsonString(request.action))
        row.put("action_key", JsonString(request.actionKey))
        row.put("account_id", JsonString(request.accountId))
        row.put("path", JsonString(request.path))
        row.put("token_mode", JsonString(request.tokenMode))
        row.put("required_scopes", feishuOapiJsonStringArray(request.requiredScopes))
        row.put("operation", JsonString(operation))
        row.put("supported", JsonBool(request.supported))
        row.put("networkAttempted", JsonBool(false))
        row.put("redacted", JsonBool(true))
        requests.add(row)
    }

    out.put("caseCount", JsonInt(cases.size()))
    out.put("readCount", JsonInt(readCount))
    out.put("writeCount", JsonInt(writeCount))
    out.put("requests", requests)
    out
}

public func feishuOapiBuildRawHttpRequest(domain: String, request: FeishuOapiRequest, accessToken: String): FeishuOapiRawHttpRequest {
    let headers = feishuOapiHeadersFromParams(request.params)
    headers["Authorization"] = "Bearer ${accessToken}"
    headers["Accept"] = "application/json"
    if (!headers.contains("Content-Type")) {
        headers["Content-Type"] = "application/json; charset=utf-8"
    }
    let path = feishuOapiResolvePathParams(request.path, request.params)
    let query = feishuOapiQueryString(request.params)
    let url = "${feishuOapiNormalizeDomain(domain)}${path}${if (query.isEmpty()) { "" } else { "?${query}" }}"
    FeishuOapiRawHttpRequest(request.accountId, request.method, url, headers, body: feishuOapiBodyString(request.params))
}

private func feishuOapiOperationKind(method: String): String {
    if (method.trimAscii().toAsciiUpper() == "GET") { "read" } else { "write" }
}

private func feishuOapiNormalizeDomain(raw: String): String {
    var out = raw.trimAscii()
    if (out.isEmpty()) {
        out = "https://open.feishu.cn"
    }
    while (out.endsWith("/") && out.size > 0) {
        out = out[0..out.size - 1]
    }
    out
}

private func feishuOapiNormalizeAccountId(raw: String): String {
    let out = raw.trimAscii()
    if (out.isEmpty()) { "default" } else { out }
}

private func feishuOapiSafeAccountSegment(raw: String): String {
    let out = StringBuilder()
    for (r in feishuOapiNormalizeAccountId(raw).runes()) {
        if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'-' || r == r'_') {
            out.append(r)
        } else {
            out.append(r'_')
        }
    }
    let value = out.toString().trimAscii()
    if (value.isEmpty()) { "default" } else { value }
}

private func feishuOapiMissingScopes(granted: Array<String>, required: Array<String>): Array<String> {
    let set = HashSet<String>()
    for (scope in granted) {
        let clean = scope.trimAscii()
        if (!clean.isEmpty()) {
            set.add(clean)
        }
    }
    let missing = ArrayList<String>()
    for (scope in required) {
        let clean = scope.trimAscii()
        if (!clean.isEmpty() && !set.contains(clean)) {
            missing.add(clean)
        }
    }
    missing.toArray()
}

private func feishuOapiHasScope(scopes: Array<String>, expected: String): Bool {
    let cleanExpected = expected.trimAscii()
    if (cleanExpected.isEmpty()) {
        return false
    }
    for (scope in scopes) {
        if (scope.trimAscii() == cleanExpected) {
            return true
        }
    }
    false
}

private func feishuOapiScopeDiagnosticStatus(
    status: String,
    grantedScopes: Array<String>,
    missingScopes: Array<String>,
    error: String
): JsonObject {
    let out = JsonObject()
    out.put("status", JsonString(if (status.trimAscii().isEmpty()) { "unknown" } else { status.trimAscii() }))
    out.put("granted_scopes", feishuOapiJsonStringArray(grantedScopes))
    out.put("missing_scopes", feishuOapiJsonStringArray(missingScopes))
    let safeError = feishuOapiRedactSensitiveText(error)
    if (!safeError.isEmpty()) {
        out.put("error", JsonString(safeError))
    }
    return out
}

private func feishuOapiScopeDiagnostic(
    request: FeishuOapiRequest,
    appScope: Option<FeishuOapiAppScopeCheck>,
    userToken: Option<FeishuOapiTokenLookup>
): JsonObject {
    let out = JsonObject()
    out.put("tokenMode", JsonString(request.tokenMode))
    out.put("token_mode", JsonString(request.tokenMode))
    out.put("required_scopes", feishuOapiJsonStringArray(request.requiredScopes))
    match (appScope) {
        case Some(check) =>
            out.put("app", feishuOapiScopeDiagnosticStatus(check.status, check.grantedScopes, check.missingScopes, check.error))
        case None =>
            out.put("app", feishuOapiScopeDiagnosticStatus("not_checked", [], [], ""))
    }
    match (userToken) {
        case Some(token) =>
            out.put("user", feishuOapiScopeDiagnosticStatus(token.status, token.grantedScopes, token.missingScopes, token.error))
            let offline = JsonObject()
            let required = request.tokenMode == "user_access_token"
            offline.put("required", JsonBool(required))
            offline.put("granted", JsonBool(token.hasOfflineAccess))
            offline.put("status", JsonString(if (!required) {
                "not_required"
            } else if (!token.offlineAccessKnown) {
                "unknown"
            } else if (token.hasOfflineAccess) {
                "present"
            } else {
                "missing"
            }))
            out.put("offline_access", offline)
        case None =>
            out.put("user", feishuOapiScopeDiagnosticStatus("not_checked", [], [], ""))
            let offline = JsonObject()
            offline.put("required", JsonBool(request.tokenMode == "user_access_token"))
            offline.put("granted", JsonBool(false))
            offline.put("status", JsonString("not_checked"))
            out.put("offline_access", offline)
    }
    out.put("repair_hints", feishuOapiRepairHints(request))
    out
}

private func feishuOapiRepairHints(request: FeishuOapiRequest): JsonObject {
    let out = JsonObject()
    out.put("token_mode", JsonString(request.tokenMode))
    out.put("required_scopes", feishuOapiJsonStringArray(request.requiredScopes))

    let user = JsonObject()
    user.put("required", JsonBool(request.tokenMode == "user_access_token"))
    user.put("repair_method", JsonString("channels.feishu.auth.start"))
    user.put("network", JsonString("not_started"))
    user.put("can_start", JsonBool(request.tokenMode == "user_access_token"))
    user.put("scopes", feishuOapiJsonStringArray(request.requiredScopes))
    out.put("user_authorization", user)

    let appScope = JsonObject()
    appScope.put("required", JsonBool(true))
    appScope.put("repair_method", JsonString("feishu_developer_console_scope_grant"))
    appScope.put("status", JsonString("operator_required"))
    appScope.put("network", JsonString("not_started"))
    appScope.put("self_manage_scope", JsonString("application:application:self_manage"))
    appScope.put("self_manage_scope_is_app_creation", JsonBool(false))
    appScope.put("scopes", feishuOapiJsonStringArray(request.requiredScopes))
    out.put("app_scope", appScope)

    let credentials = JsonObject()
    credentials.put("required", JsonBool(request.tokenMode != "user_access_token"))
    credentials.put("repair_method", JsonString("configure_feishu_app_credentials"))
    credentials.put("missing_fields", feishuOapiJsonStringArray(["app_id", "appSecret"]))
    credentials.put("network", JsonString("not_started"))
    credentials.put("redacted", JsonBool(true))
    out.put("app_credentials", credentials)

    let platform = JsonObject()
    platform.put("app_bot_autocreate", JsonString("not_supported"))
    platform.put("setup_mode", JsonString("guided_existing_app_bot"))
    platform.put("self_manage_scope_is_app_creation", JsonBool(false))
    platform.put(
        "boundary",
        JsonString("Metis can guide setup and bind an existing Feishu app/bot, but it must not claim OAPI app/bot auto-creation without platform evidence.")
    )
    platform.put("network", JsonString("not_started"))
    out.put("platform", platform)

    out.put("redacted", JsonBool(true))
    out
}

private func feishuOapiJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func feishuOapiJsonInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asInt().getValue() } catch (_e: Exception) {
                try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_inner: Exception) { fallback }
            }
        case None => fallback
    }
}

private func feishuOapiJsonStringArrayField(obj: JsonObject, key: String): Array<String> {
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

private func feishuOapiObjectField(obj: JsonObject, key: String): Option<JsonObject> {
    match (obj.get(key)) {
        case Some(v) => try { Some(v.asObject()) } catch (_e: Exception) { None<JsonObject> }
        case None => None<JsonObject>
    }
}

private func feishuOapiStringValue(value: JsonValue): String {
    try { value.asString().getValue().trimAscii() } catch (_e: Exception) {
        try { value.asInt().getValue().toString() } catch (_inner: Exception) {
            try { if (value.asBool().getValue()) { "true" } else { "false" } } catch (_b: Exception) { value.toJsonString() }
        }
    }
}

private func feishuOapiResolvePathParams(pathTemplate: String, params: JsonObject): String {
    var path = pathTemplate.trimAscii()
    match (feishuOapiObjectField(params, "path")) {
        case Some(pathParams) =>
            for (key in pathParams.getFields().keys()) {
                match (pathParams.get(key)) {
                    case Some(v) => path = path.replace(":${key}", feishuOapiUrlEncode(feishuOapiStringValue(v)))
                    case None => ()
                }
            }
        case None => ()
    }
    for (key in params.getFields().keys()) {
        if (key != "query" && key != "body" && key != "headers" && key != "path") {
            match (params.get(key)) {
                case Some(v) => path = path.replace(":${key}", feishuOapiUrlEncode(feishuOapiStringValue(v)))
                case None => ()
            }
        }
    }
    path
}

private func feishuOapiHeadersFromParams(params: JsonObject): HashMap<String, String> {
    let headers = HashMap<String, String>()
    match (feishuOapiObjectField(params, "headers")) {
        case Some(obj) =>
            for (key in obj.getFields().keys()) {
                if (key.trimAscii().toAsciiLower() != "authorization") {
                    match (obj.get(key)) {
                        case Some(v) => headers[key.trimAscii()] = feishuOapiStringValue(v)
                        case None => ()
                    }
                }
            }
        case None => ()
    }
    headers
}

private func feishuOapiQueryString(params: JsonObject): String {
    let parts = ArrayList<String>()
    match (feishuOapiObjectField(params, "query")) {
        case Some(query) =>
            for (key in query.getFields().keys()) {
                match (query.get(key)) {
                    case Some(v) =>
                        let value = feishuOapiStringValue(v)
                        if (!key.trimAscii().isEmpty()) {
                            parts.add("${feishuOapiUrlEncode(key)}=${feishuOapiUrlEncode(value)}")
                        }
                    case None => ()
                }
            }
        case None => ()
    }
    String.join(parts.toArray(), delimiter: "&")
}

private func feishuOapiBodyString(params: JsonObject): String {
    match (params.get("body")) {
        case Some(v) => v.toJsonString()
        case None => ""
    }
}

private func feishuOapiUrlEncode(raw: String): String {
    let out = StringBuilder()
    let hex = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    for (b in raw.toArray()) {
        let v = Int64(b)
        if ((v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) ||
            v == 45 || v == 46 || v == 95 || v == 126) {
            out.append(String.fromUtf8([b]))
        } else {
            out.append("%")
            out.append(hex[(v >> 4) & 0x0F])
            out.append(hex[v & 0x0F])
        }
    }
    out.toString()
}

private func feishuOapiParseBodyWithStatus(body: String): (Bool, JsonValue) {
    if (body.trimAscii().isEmpty()) {
        return (true, JsonObject())
    }
    try { (true, JsonValue.fromStr(body)) } catch (_e: Exception) {
        let out = JsonObject()
        out.put("raw", JsonString(body))
        (false, out)
    }
}

private func feishuOapiParseBody(body: String): JsonValue {
    let (_, parsed) = feishuOapiParseBodyWithStatus(body)
    parsed
}

private func feishuOapiEnvValue(name: String): String {
    match (getVariable(name)) {
        case Some(v) => v.trimAscii()
        case None => ""
    }
}

private func feishuOapiEnvEnabled(raw: String): Bool {
    let value = raw.trimAscii().toAsciiLower()
    value == "1" || value == "true" || value == "yes" || value == "on"
}

private func feishuOapiSplitScopes(raw: String): Array<String> {
    let normalized = raw.replace(",", " ").replace("\n", " ").replace("\t", " ")
    let out = ArrayList<String>()
    for (part in normalized.split(" ")) {
        let clean = part.trimAscii()
        if (!clean.isEmpty() && !out.contains(clean)) {
            out.add(clean)
        }
    }
    out.toArray()
}

private func feishuOapiResponseCode(body: JsonValue): String {
    let obj = try { body.asObject() } catch (_e: Exception) { return "" }
    match (obj.get("code")) {
        case Some(v) =>
            try { return v.asInt().getValue().toString() } catch (_e: Exception) {
                try { return v.asString().getValue().trimAscii() } catch (_inner: Exception) { return "" }
            }
        case None => ""
    }
}

private func feishuOapiReadAllBytes(response: HttpResponse): Array<Byte> {
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
