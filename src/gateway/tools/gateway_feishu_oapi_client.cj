package metis.gateway.tools

import metis.core.config.MetisPaths

import std.collection.{ArrayList, HashMap, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}
import stdx.encoding.url.URL
import stdx.net.http.*
import stdx.net.tls.*

public class FeishuOapiRequest {
    public let toolName: String
    public let category: String
    public let domain: String
    public let action: String
    public let accountId: String
    public let path: String
    public let method: String
    public let tokenMode: String
    public let params: JsonObject
    public let requiredScopes: Array<String>

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
        this.category = category.trimAscii()
        this.domain = domain.trimAscii()
        this.action = action.trimAscii()
        this.accountId = accountId.trimAscii()
        this.path = path.trimAscii()
        this.method = method.trimAscii()
        this.tokenMode = tokenMode.trimAscii()
        this.params = params
        this.requiredScopes = requiredScopes
    }

    public func toJson(): JsonObject {
        let out = JsonObject()
        out.put("tool", JsonString(this.toolName))
        out.put("category", JsonString(this.category))
        out.put("domain", JsonString(this.domain))
        out.put("action", JsonString(this.action))
        out.put("account_id", JsonString(this.accountId))
        out.put("path", JsonString(this.path))
        out.put("method", JsonString(this.method))
        out.put("token_mode", JsonString(this.tokenMode))
        out.put("required_scopes", feishuOapiJsonStringArray(this.requiredScopes))
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

    public init(
        request: FeishuOapiRequest,
        ok: Bool,
        status: String,
        data!: Option<JsonValue> = None<JsonValue>,
        error!: String = "",
        missingScopes!: Array<String> = [],
        authState!: String = ""
    ) {
        this.request = request
        this.ok = ok
        this.status = status.trimAscii()
        this.data = data
        this.error = error.trimAscii()
        this.missingScopes = missingScopes
        this.authState = authState.trimAscii()
    }

    public static func success(request: FeishuOapiRequest, data: JsonValue): FeishuOapiResult {
        FeishuOapiResult(request, true, "success", data: Some(data))
    }

    public static func authRequired(request: FeishuOapiRequest, authState!: String = "absent", error!: String = ""): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "auth_required",
            error: if (error.trimAscii().isEmpty()) {
                "Feishu OAPI user authorization is not configured in this runtime. Configure account auth before calling this tool against Feishu."
            } else {
                error.trimAscii()
            },
            authState: if (authState.trimAscii().isEmpty()) { "absent" } else { authState.trimAscii() }
        )
    }

    public static func scopeMissing(request: FeishuOapiRequest, missingScopes: Array<String>, error!: String = ""): FeishuOapiResult {
        FeishuOapiResult(
            request,
            false,
            "scope_missing",
            error: if (error.trimAscii().isEmpty()) { "Feishu OAPI required scope is missing." } else { error.trimAscii() },
            missingScopes: missingScopes
        )
    }

    public static func apiError(request: FeishuOapiRequest, error: String, data!: Option<JsonValue> = None<JsonValue>): FeishuOapiResult {
        FeishuOapiResult(request, false, "api_error", data: data, error: error)
    }

    public static func invalidRequest(request: FeishuOapiRequest, error: String): FeishuOapiResult {
        FeishuOapiResult(request, false, "invalid_request", error: error)
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
        out
    }
}

public class FeishuOapiTokenLookup {
    public let status: String
    public let accessToken: String
    public let missingScopes: Array<String>
    public let error: String

    public init(status: String, accessToken!: String = "", missingScopes!: Array<String> = [], error!: String = "") {
        this.status = status.trimAscii()
        this.accessToken = accessToken.trimAscii()
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

public interface FeishuOapiTokenProvider {
    func userAccessToken(accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup
}

public interface FeishuOapiRefreshClient {
    func refresh(accountId: String, refreshToken: String): FeishuOapiRefreshResult
}

public interface FeishuOapiHttpClient {
    func request(request: FeishuOapiRequest, accessToken: String): FeishuOapiHttpResponse
}

public interface FeishuOapiClient {
    func invoke(request: FeishuOapiRequest): JsonObject
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

public class MetisFeishuOapiTokenProvider <: FeishuOapiTokenProvider {
    private let root: Path
    private let refreshClient: Option<FeishuOapiRefreshClient>
    private let nowMsValue: Int64

    public init(
        root!: Path = feishuOapiDefaultTokenStoreRoot(),
        refreshClient!: Option<FeishuOapiRefreshClient> = None<FeishuOapiRefreshClient>,
        nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
    ) {
        this.root = root
        this.refreshClient = refreshClient
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
            return FeishuOapiTokenLookup("scope_missing", missingScopes: missing, error: "Feishu user authorization is missing required scope(s).")
        }
        if (token.expiresAtMs <= this.nowMsValue) {
            return this.refreshOrExpired(normalized, token, requiredScopes)
        }
        if (token.accessToken.isEmpty()) {
            return FeishuOapiTokenLookup("auth_required", error: "Stored Feishu user authorization does not contain an access token.")
        }
        FeishuOapiTokenLookup("authorized", accessToken: token.accessToken)
    }

    private func refreshOrExpired(accountId: String, token: FeishuOapiStoredToken, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        if (token.refreshToken.isEmpty()) {
            return FeishuOapiTokenLookup("expired", error: "Stored Feishu user authorization is expired and has no refresh token.")
        }
        let refreshed = match (this.refreshClient) {
            case Some(client) => client.refresh(accountId, token.refreshToken)
            case None => return FeishuOapiTokenLookup("expired", error: "Stored Feishu user authorization is expired.")
        }
        if (refreshed.status != "authorized" || refreshed.accessToken.isEmpty()) {
            return FeishuOapiTokenLookup(
                if (refreshed.status.isEmpty()) { "expired" } else { refreshed.status },
                error: if (refreshed.error.isEmpty()) { "Feishu user authorization refresh did not return an access token." } else { refreshed.error }
            )
        }
        let scopes = if (refreshed.scopes.size > 0) { refreshed.scopes } else { token.scopes }
        let missing = feishuOapiMissingScopes(scopes, requiredScopes)
        if (missing.size > 0) {
            return FeishuOapiTokenLookup("scope_missing", missingScopes: missing, error: "Refreshed Feishu user authorization is missing required scope(s).")
        }
        this.save(accountId, FeishuOapiStoredToken(
            accessToken: refreshed.accessToken,
            refreshToken: if (refreshed.refreshToken.isEmpty()) { token.refreshToken } else { refreshed.refreshToken },
            expiresAtMs: this.nowMsValue + refreshed.expiresInSeconds * 1000,
            scopes: scopes
        ))
        FeishuOapiTokenLookup("authorized", accessToken: refreshed.accessToken)
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
            return FeishuOapiHttpResponse(false, statusCode: response.statusCode, body: feishuOapiParseBody(response.body), error: response.error)
        }
        let body = feishuOapiParseBody(response.body)
        let apiCode = try { body.asObject().get("code").getOrThrow().asInt().getValue() } catch (_e: Exception) { 0 }
        if (apiCode != 0) {
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

    public init(
        tokenProvider!: Option<FeishuOapiTokenProvider> = None<FeishuOapiTokenProvider>,
        httpClient!: Option<FeishuOapiHttpClient> = None<FeishuOapiHttpClient>
    ) {
        this.tokenProvider = tokenProvider
        this.httpClient = httpClient
    }

    public func invoke(request: FeishuOapiRequest): JsonObject {
        let token = match (this.tokenProvider) {
            case Some(provider) => provider.userAccessToken(request.accountId, request.requiredScopes)
            case None => return FeishuOapiResult.authRequired(request).toJson()
        }
        if (token.status == "scope_missing") {
            return FeishuOapiResult.scopeMissing(request, token.missingScopes, error: token.error).toJson()
        }
        if (token.status == "expired") {
            return FeishuOapiResult.authRequired(request, authState: "expired", error: token.error).toJson()
        }
        if (token.status == "auth_required" || token.accessToken.isEmpty()) {
            return FeishuOapiResult.authRequired(request, authState: token.status, error: token.error).toJson()
        }
        match (this.httpClient) {
            case Some(http) =>
                let response = http.request(request, token.accessToken)
                if (response.ok) {
                    return FeishuOapiResult.success(request, response.body).toJson()
                }
                return FeishuOapiResult.apiError(
                    request,
                    if (response.error.isEmpty()) { "Feishu OAPI request failed with HTTP ${response.statusCode}." } else { response.error },
                    data: Some(response.body)
                ).toJson()
            case None =>
                FeishuOapiResult.apiError(request, "Feishu OAPI HTTP client is not configured for this runtime.").toJson()
        }
    }
}

public func feishuOapiBuildRequest(toolName: String, action: String, accountId: String, params: JsonObject): FeishuOapiRequest {
    let cleanTool = toolName.trimAscii()
    let cleanAction = if (action.trimAscii().isEmpty()) { "default" } else { action.trimAscii() }
    let category = feishuOapiCategoryForTool(cleanTool)
    FeishuOapiRequest(
        cleanTool,
        category,
        feishuOapiDomainForCategory(category),
        cleanAction,
        if (accountId.trimAscii().isEmpty()) { "default" } else { accountId.trimAscii() },
        feishuOapiPathForTool(cleanTool, cleanAction),
        feishuOapiMethodForAction(cleanAction),
        "user_access_token",
        params,
        feishuOapiRequiredScopesForTool(cleanTool, category, cleanAction)
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

public func feishuOapiRequiredScopesForTool(toolName: String, category: String, _action: String): Array<String> {
    let name = toolName.trimAscii()
    match (category.trimAscii()) {
        case "docs" =>
            if (name == "feishu_create_doc" || name == "feishu_update_doc") {
                return ["docx:document"]
            }
            ["docx:document:readonly"]
        case "wiki" => ["wiki:wiki:readonly"]
        case "drive" => ["drive:drive:readonly"]
        case "search" => ["docx:document:readonly", "wiki:wiki:readonly"]
        case "bitable" => ["bitable:app:readonly"]
        case "calendar" => ["calendar:calendar:readonly"]
        case "task" => ["task:task:readonly"]
        case "sheets" => ["sheets:spreadsheet:readonly"]
        case "chat" => ["im:chat:readonly"]
        case "user" => ["contact:contact.base:readonly"]
        case "im" =>
            if (name == "feishu_im_bot_image") {
                return ["im:resource"]
            }
            if (name == "feishu_im_user_message") {
                return ["im:message"]
            }
            ["im:message:readonly"]
        case "oauth" => ["offline_access"]
        case "interaction" => ["cardkit:card"]
        case _ => []
    }
}

private func feishuOapiMethodForAction(action: String): String {
    let clean = action.trimAscii().toAsciiLower()
    if (clean == "create" || clean == "send" || clean == "search") {
        return "POST"
    }
    if (clean == "update" || clean == "patch") {
        return "PATCH"
    }
    if (clean == "delete" || clean == "remove") {
        return "DELETE"
    }
    "GET"
}

private func feishuOapiPathForTool(toolName: String, _action: String): String {
    let name = toolName.trimAscii()
    if (name == "feishu_oauth" || name == "feishu_oauth_batch_auth") {
        return "/open-apis/authen/v1/oidc/device_authorize"
    }
    if (name == "feishu_ask_user_question") {
        return "/open-apis/cardkit/v1/cards"
    }
    if (name == "feishu_fetch_doc") {
        return "/open-apis/docx/v1/documents/:document_id/raw_content"
    }
    if (name == "feishu_create_doc" || name == "feishu_update_doc") {
        return "/open-apis/docx/v1/documents"
    }
    if (name == "feishu_doc_comments") {
        return "/open-apis/docx/v1/documents/:document_id/comments"
    }
    if (name == "feishu_doc_media") {
        return "/open-apis/docx/v1/documents/:document_id/media"
    }
    if (name == "feishu_wiki_space_node") {
        return "/open-apis/wiki/v2/spaces/:space_id/nodes"
    }
    if (name == "feishu_wiki_space") {
        return "/open-apis/wiki/v2/spaces"
    }
    if (name == "feishu_drive_file") {
        return "/open-apis/drive/v1/files"
    }
    if (name == "feishu_search_doc_wiki") {
        return "/open-apis/search/v2/data_sources/:data_source_id/search"
    }
    if (name == "feishu_bitable_app_table_record") {
        return "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records"
    }
    if (name == "feishu_bitable_app_table_field") {
        return "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/fields"
    }
    if (name == "feishu_bitable_app_table_view") {
        return "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/views"
    }
    if (name == "feishu_bitable_app_table") {
        return "/open-apis/bitable/v1/apps/:app_token/tables"
    }
    if (name == "feishu_bitable_app") {
        return "/open-apis/bitable/v1/apps"
    }
    if (name == "feishu_calendar_event_attendee") {
        return "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/attendees"
    }
    if (name == "feishu_calendar_event") {
        return "/open-apis/calendar/v4/calendars/:calendar_id/events"
    }
    if (name == "feishu_calendar_freebusy") {
        return "/open-apis/calendar/v4/freebusy/list"
    }
    if (name == "feishu_calendar_calendar") {
        return "/open-apis/calendar/v4/calendars"
    }
    if (name == "feishu_task_tasklist") {
        return "/open-apis/task/v2/tasklists"
    }
    if (name == "feishu_task_attachment") {
        return "/open-apis/task/v2/tasks/:task_guid/attachments"
    }
    if (name == "feishu_task_section") {
        return "/open-apis/task/v2/tasklists/:tasklist_guid/sections"
    }
    if (name == "feishu_task_comment") {
        return "/open-apis/task/v2/tasks/:task_guid/comments"
    }
    if (name == "feishu_task_subtask") {
        return "/open-apis/task/v2/tasks/:task_guid/subtasks"
    }
    if (name == "feishu_task_agent") {
        return "/open-apis/task/v2/tasks/:task_guid/collaborators"
    }
    if (name == "feishu_task_task") {
        return "/open-apis/task/v2/tasks"
    }
    if (name == "feishu_sheet") {
        return "/open-apis/sheets/v3/spreadsheets"
    }
    if (name == "feishu_chat_members") {
        return "/open-apis/im/v1/chats/:chat_id/members"
    }
    if (name == "feishu_chat") {
        return "/open-apis/im/v1/chats"
    }
    if (name == "feishu_get_user") {
        return "/open-apis/contact/v3/users/:user_id"
    }
    if (name == "feishu_search_user") {
        return "/open-apis/contact/v3/users/batch_get_id"
    }
    if (name == "feishu_im_user_get_thread_messages") {
        return "/open-apis/im/v1/messages/:message_id/replies"
    }
    if (name == "feishu_im_user_search_messages") {
        return "/open-apis/search/v2/data_sources/im_message/search"
    }
    if (name == "feishu_im_user_fetch_resource" || name == "feishu_im_bot_image") {
        return "/open-apis/im/v1/messages/:message_id/resources/:file_key"
    }
    if (name == "feishu_im_user_get_messages" || name == "feishu_im_user_message") {
        return "/open-apis/im/v1/messages"
    }
    "/open-apis/${feishuOapiDomainForCategory(feishuOapiCategoryForTool(name))}/generic"
}

public func feishuOapiDefaultTokenStoreRoot(): Path {
    MetisPaths.homeRoot().join("feishu").join("user-tokens")
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

private func feishuOapiParseBody(body: String): JsonValue {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    try { JsonValue.fromStr(body) } catch (_e: Exception) {
        let out = JsonObject()
        out.put("raw", JsonString(body))
        out
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
