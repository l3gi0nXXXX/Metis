package metis.gateway.tools

import metis.core.config.MetisProcessEnvironmentLock

import std.collection.{ArrayList, HashMap}
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private class FeishuOapiToolsetFakeClient <: FeishuOapiClient {
    let captured = ArrayList<String>()

    public init() {}

    public func invoke(request: FeishuOapiRequest): JsonObject {
        this.captured.add(request.toolName)
        this.captured.add(request.category)
        this.captured.add(request.domain)
        this.captured.add(request.action)
        this.captured.add(request.accountId)
        this.captured.add(request.path)
        this.captured.add(request.requiredScopes[0])
        this.captured.add(request.params.get("message").getOrThrow().asString().getValue())

        let data = JsonObject()
        data.put("message_id", JsonString("om_success"))
        return FeishuOapiResult.success(request, data).toJson()
    }
}

private class FeishuOapiToolsetScopeMissingTokenProvider <: FeishuOapiTokenProvider {
    public init() {}

    public func userAccessToken(_accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("scope_missing", missingScopes: requiredScopes, error: "missing test scope")
    }

    public func tokenLookup(_accountId: String, _tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("scope_missing", missingScopes: requiredScopes, error: "missing test scope")
    }
}

private class FeishuOapiToolsetAuthRequiredTokenProvider <: FeishuOapiTokenProvider {
    public init() {}

    public func userAccessToken(_accountId: String, _requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("auth_required", error: "fake user auth missing")
    }

    public func tokenLookup(_accountId: String, _tokenMode: String, _requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("auth_required", error: "fake token missing")
    }
}

private class FeishuOapiToolsetSecretErrorTokenProvider <: FeishuOapiTokenProvider {
    private let statusValue: String

    public init(status: String) {
        this.statusValue = status.trimAscii()
    }

    public func userAccessToken(_accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        this.lookup(requiredScopes)
    }

    public func tokenLookup(_accountId: String, _tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        this.lookup(requiredScopes)
    }

    private func lookup(requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup(
            this.statusValue,
            missingScopes: requiredScopes,
            error: "Authorization: Bearer secret-token-value refresh_token=secret-token-value app_secret=secret-token-value"
        )
    }
}

private class FeishuOapiToolsetAppScopeMissingTokenProvider <: FeishuOapiTokenProvider {
    public init() {}

    public func userAccessToken(_accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("app_scope_missing", missingScopes: requiredScopes, error: "missing app scope")
    }

    public func tokenLookup(_accountId: String, _tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("app_scope_missing", missingScopes: requiredScopes, error: "missing app scope")
    }
}

private class FeishuOapiToolsetReadOkTokenProvider <: FeishuOapiTokenProvider {
    public init() {}

    public func userAccessToken(_accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup(
            "authorized",
            accessToken: "fake-read-user-token",
            grantedScopes: requiredScopes,
            hasOfflineAccess: false
        )
    }

    public func tokenLookup(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        if (tokenMode == "user_access_token") {
            return this.userAccessToken(accountId, requiredScopes)
        }
        FeishuOapiTokenLookup(
            "authorized",
            accessToken: "fake-read-${tokenMode}",
            grantedScopes: requiredScopes,
            hasOfflineAccess: false
        )
    }
}

private class FeishuOapiToolsetReadMissingAppScopeChecker <: FeishuOapiAppScopeChecker {
    public init() {}

    public func check(_accountId: String, _tokenMode: String, requiredScopes: Array<String>): FeishuOapiAppScopeCheck {
        FeishuOapiAppScopeCheck(
            "app_scope_missing",
            grantedScopes: [],
            missingScopes: requiredScopes,
            error: "fake missing app scope"
        )
    }
}

private class FeishuOapiToolsetOkTokenProvider <: FeishuOapiTokenProvider {
    public let modes = ArrayList<String>()

    public init() {}

    public func userAccessToken(_accountId: String, _requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup(
            "authorized",
            accessToken: "fake-access-token",
            grantedScopes: ["im:message", "im:message.send_as_user", "im:chat:read"],
            hasOfflineAccess: false
        )
    }

    public func tokenLookup(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        this.modes.add(tokenMode)
        if (tokenMode == "user_access_token") {
            return this.userAccessToken(accountId, requiredScopes)
        }
        if (tokenMode == "tenant_access_token" || tokenMode == "bot_access_token" || tokenMode == "app_access_token") {
            return FeishuOapiTokenLookup(
                "authorized",
                accessToken: "fake-${tokenMode}",
                grantedScopes: requiredScopes,
                hasOfflineAccess: false
            )
        }
        FeishuOapiTokenLookup("token_mode_unsupported", error: "unsupported token mode ${tokenMode}")
    }
}

private class FeishuOapiToolsetMissingAppScopeChecker <: FeishuOapiAppScopeChecker {
    public init() {}

    public func check(accountId: String, tokenMode: String, requiredScopes: Array<String>): FeishuOapiAppScopeCheck {
        @Expect(accountId, "tenant-a")
        @Expect(tokenMode, "user_access_token")
        @Expect(requiredScopes[0], "im:message")
        FeishuOapiAppScopeCheck(
            "app_scope_missing",
            grantedScopes: ["im:message"],
            missingScopes: ["im:message.send_as_user"],
            error: "missing app grant"
        )
    }
}

private class FeishuOapiToolsetOkAppScopeChecker <: FeishuOapiAppScopeChecker {
    public init() {}

    public func check(_accountId: String, _tokenMode: String, requiredScopes: Array<String>): FeishuOapiAppScopeCheck {
        FeishuOapiAppScopeCheck("ok", grantedScopes: requiredScopes)
    }
}

private class FeishuOapiToolsetErrorHttpClient <: FeishuOapiHttpClient {
    public let captured = ArrayList<String>()

    public init() {}

    public func request(request: FeishuOapiRequest, accessToken: String): FeishuOapiHttpResponse {
        this.captured.add(request.accountId)
        this.captured.add(request.path)
        this.captured.add(accessToken)
        let body = JsonObject()
        body.put("code", JsonString("99991672"))
        FeishuOapiHttpResponse(false, statusCode: 403, body: body, error: "forbidden")
    }
}

private class FeishuOapiToolsetCountingHttpClient <: FeishuOapiHttpClient {
    public let accessTokens = ArrayList<String>()
    public var calls: Int64 = 0

    public init() {}

    public func request(request: FeishuOapiRequest, accessToken: String): FeishuOapiHttpResponse {
        this.calls++
        this.accessTokens.add(accessToken)
        let body = JsonObject()
        body.put("code", JsonString("0"))
        body.put("ok", JsonBool(true))
        FeishuOapiHttpResponse(true, statusCode: 200, body: body)
    }
}

private class FeishuOapiToolsetFakeAppTokenClient <: FeishuOapiAppTokenClient {
    public let accountIds = ArrayList<String>()
    public let modes = ArrayList<String>()
    private let statusValue: String
    private let errorValue: String

    public init(status!: String = "authorized", error!: String = "") {
        this.statusValue = status
        this.errorValue = error
    }

    public func fetch(accountId: String, tokenMode: String, credentials: FeishuOapiAppCredentials): FeishuOapiAppTokenResult {
        this.accountIds.add(accountId)
        this.modes.add(tokenMode)
        if (this.statusValue != "authorized") {
            return FeishuOapiAppTokenResult(this.statusValue, error: this.errorValue)
        }
        FeishuOapiAppTokenResult(
            "authorized",
            accessToken: "issued-${tokenMode}",
            expiresInSeconds: 7200
        )
    }
}

private class FeishuOapiToolsetFakeRefreshClient <: FeishuOapiRefreshClient {
    public let calls = ArrayList<String>()

    public init() {}

    public func refresh(accountId: String, refreshToken: String): FeishuOapiRefreshResult {
        this.calls.add(accountId)
        this.calls.add(refreshToken)
        FeishuOapiRefreshResult(
            "authorized",
            accessToken: "refreshed-access-token",
            refreshToken: "refreshed-refresh-token",
            expiresInSeconds: 3600,
            scopes: ["im:message:readonly", "contact:contact.base:readonly"]
        )
    }
}

private class FeishuOapiToolsetStateRefreshClient <: FeishuOapiRefreshClient {
    private let statusValue: String
    private let accessTokenValue: String
    private let refreshTokenValue: String
    private let errorValue: String

    public init(status: String, accessToken!: String = "", refreshToken!: String = "", error!: String = "") {
        this.statusValue = status
        this.accessTokenValue = accessToken
        this.refreshTokenValue = refreshToken
        this.errorValue = error
    }

    public func refresh(_accountId: String, _refreshToken: String): FeishuOapiRefreshResult {
        FeishuOapiRefreshResult(
            this.statusValue,
            accessToken: this.accessTokenValue,
            refreshToken: this.refreshTokenValue,
            expiresInSeconds: 3600,
            scopes: ["im:message:readonly"],
            error: this.errorValue
        )
    }
}

private class FeishuOapiToolsetFakeRawTransport <: FeishuOapiRawHttpTransport {
    public var last: Option<FeishuOapiRawHttpRequest> = None<FeishuOapiRawHttpRequest>

    public init() {}

    public func send(request: FeishuOapiRawHttpRequest): FeishuOapiRawHttpResponse {
        this.last = Some(request)
        FeishuOapiRawHttpResponse(200, body: "{\"code\":0,\"data\":{\"ok\":true}}")
    }
}

private class FeishuOapiToolsetStaticRawTransport <: FeishuOapiRawHttpTransport {
    public let statusCode: Int64
    public let body: String
    public let error: String
    public var last: Option<FeishuOapiRawHttpRequest> = None<FeishuOapiRawHttpRequest>

    public init(statusCode: Int64, body!: String = "", error!: String = "") {
        this.statusCode = statusCode
        this.body = body
        this.error = error
    }

    public func send(request: FeishuOapiRawHttpRequest): FeishuOapiRawHttpResponse {
        this.last = Some(request)
        FeishuOapiRawHttpResponse(this.statusCode, body: this.body, error: this.error)
    }
}

private class FeishuOapiMatrixCase {
    let tool: String
    let action: String
    let path: String
    let method: String
    let firstScope: String

    init(tool: String, action: String, path: String, method: String, firstScope: String) {
        this.tool = tool
        this.action = action
        this.path = path
        this.method = method
        this.firstScope = firstScope
    }
}

private func feishuOapiToolsetTempRoot(label: String): Path {
    Path("/tmp/metis-feishu-oapi-${label}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
}

private func feishuOapiWriteStoredToken(
    root: Path,
    accountId: String,
    accessToken: String,
    refreshToken: String,
    expiresAtMs: Int64,
    scopes: Array<String>
): Unit {
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    let arr = JsonArray([])
    for (scope in scopes) {
        arr.add(JsonString(scope))
    }
    let token = JsonObject()
    token.put("accessToken", JsonString(accessToken))
    token.put("refreshToken", JsonString(refreshToken))
    token.put("expiresAtMs", JsonString(expiresAtMs.toString()))
    token.put("scopes", arr)
    File.writeTo(root.join("${accountId}.json"), token.toJsonString().toArray())
}

@Test
public class GatewayFeishuOapiToolsetTest {
    @TestCase
    public func defaultClientReturnsStructuredAuthRequiredThroughNativeBoundary(): Unit {
        let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
            "feishu_fetch_doc",
            "fetch",
            Some("default"),
            Some("{\"doc_id\":\"doccn_demo\"}")
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(json.get("tool").getOrThrow().asString().getValue(), "feishu_fetch_doc")
        @Expect(json.get("category").getOrThrow().asString().getValue(), "docs")
        @Expect(json.get("domain").getOrThrow().asString().getValue(), "docs")
        @Expect(json.get("action").getOrThrow().asString().getValue(), "fetch")
        @Expect(json.get("path").getOrThrow().asString().getValue(), "/open-apis/docx/v1/documents/:document_id/raw_content")
        @Expect(json.get("client").getOrThrow().asString().getValue(), "metis_feishu_oapi_client")
        @Expect(json.get("account_id").getOrThrow().asString().getValue(), "default")
        let auth = json.get("auth").getOrThrow().asObject()
        @Expect(auth.get("required").getOrThrow().asBool().getValue(), true)
        @Expect(auth.get("state").getOrThrow().asString().getValue(), "auth_required")
        @Expect(json.get("required_scopes").getOrThrow().asArray()[0].asString().getValue(), "docx:document:readonly")
    }

    @TestCase
    public func typedClientReceivesDomainPathScopesAndCanReturnSuccess(): Unit {
        let fake = FeishuOapiToolsetFakeClient()
        debugSetGatewayFeishuOapiClientForTest(Some<FeishuOapiClient>(fake))
        try {
            let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
                "feishu_im_user_message",
                "create",
                Some("team-a"),
                Some("{\"message\":\"hello\"}")
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(json.get("status").getOrThrow().asString().getValue(), "success")
            @Expect(json.get("tool").getOrThrow().asString().getValue(), "feishu_im_user_message")
            @Expect(json.get("category").getOrThrow().asString().getValue(), "im")
            @Expect(json.get("domain").getOrThrow().asString().getValue(), "im")
            @Expect(json.get("path").getOrThrow().asString().getValue(), "/open-apis/im/v1/messages")
            @Expect(json.get("account_id").getOrThrow().asString().getValue(), "team-a")
            @Expect(json.get("data").getOrThrow().asObject().get("message_id").getOrThrow().asString().getValue(), "om_success")
            @Expect(fake.captured[0], "feishu_im_user_message")
            @Expect(fake.captured[1], "im")
            @Expect(fake.captured[2], "im")
            @Expect(fake.captured[3], "create")
            @Expect(fake.captured[4], "team-a")
            @Expect(fake.captured[5], "/open-apis/im/v1/messages")
            @Expect(fake.captured[6], "im:message")
            @Expect(fake.captured[7], "hello")
        } finally {
            debugSetGatewayFeishuOapiClientForTest(None<FeishuOapiClient>)
        }
    }

    @TestCase
    public func fakeClientReceivesStructuredRequestAndCanReportScopeMissing(): Unit {
        let captured = ArrayList<String>()
        debugSetGatewayFeishuOapiToolCallRunnerForTest(Some({ method: String, payload: JsonObject =>
            captured.add(method)
            captured.add(payload.get("tool").getOrThrow().asString().getValue())
            captured.add(payload.get("category").getOrThrow().asString().getValue())
            captured.add(payload.get("action").getOrThrow().asString().getValue())
            captured.add(payload.get("account_id").getOrThrow().asString().getValue())
            captured.add(payload.get("params").getOrThrow().asObject().get("summary").getOrThrow().asString().getValue())

            let out = JsonObject()
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("scope_missing"))
            out.put("missing_scopes", JsonArray([JsonString("calendar:calendar:readonly")]))
            out
        }))
        try {
            let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
                "feishu_calendar_event",
                "list",
                Some("work"),
                Some("{\"summary\":\"standup\"}")
            )
            let json = JsonValue.fromStr(out).asObject()
            @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(json.get("status").getOrThrow().asString().getValue(), "scope_missing")
            @Expect(json.get("tool").getOrThrow().asString().getValue(), "feishu_calendar_event")
            @Expect(json.get("category").getOrThrow().asString().getValue(), "calendar")
            @Expect(json.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "calendar:calendar:readonly")
            @Expect(captured[0], "feishu_calendar_event")
            @Expect(captured[1], "feishu_calendar_event")
            @Expect(captured[2], "calendar")
            @Expect(captured[3], "list")
            @Expect(captured[4], "work")
            @Expect(captured[5], "standup")
        } finally {
            debugSetGatewayFeishuOapiToolCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
        }
    }

    @TestCase
    public func invalidParamsJsonReturnsStructuredInvalidRequest(): Unit {
        let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
            "feishu_bitable_app",
            "list",
            None<String>,
            Some("not-json")
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "invalid_request")
        @Expect(json.get("tool").getOrThrow().asString().getValue(), "feishu_bitable_app")
        @Expect(json.get("reason").getOrThrow().asString().getValue().contains("params_json must be a JSON object"), true)
    }

    @TestCase
    public func nativeBoundaryCanReturnScopeMissingAndApiError(): Unit {
        let scopeRequest = feishuOapiBuildRequest("feishu_calendar_event", "list", "work", JsonObject())
        let scopeJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetScopeMissingTokenProvider())
        ).invoke(scopeRequest)
        @Expect(scopeJson.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(scopeJson.get("status").getOrThrow().asString().getValue(), "scope_missing")
        @Expect(scopeJson.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "calendar:calendar.event:read")

        let http = FeishuOapiToolsetErrorHttpClient()
        let apiRequest = feishuOapiBuildRequest("feishu_chat", "get", "ops", JsonObject())
        let apiJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetOkTokenProvider()),
            httpClient: Some<FeishuOapiHttpClient>(http)
        ).invoke(apiRequest)
        @Expect(apiJson.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(apiJson.get("status").getOrThrow().asString().getValue(), "app_scope_missing")
        @Expect(apiJson.get("error").getOrThrow().asString().getValue(), "forbidden")
        @Expect(apiJson.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:chat:read")
        @Expect(http.captured[0], "ops")
        @Expect(http.captured[1], "/open-apis/im/v1/chats/:chat_id")
        @Expect(http.captured[2], "fake-access-token")
    }

    @TestCase
    public func nativeBoundaryDistinguishesAuthRequiredUserScopeMissingAndAppScopeMissing(): Unit {
        let request = feishuOapiBuildRequest("feishu_im_user_message", "send", "tenant-a", JsonObject())
        let authJson = MetisFeishuOapiClient().invoke(request)
        @Expect(authJson.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(authJson.get("auth").getOrThrow().asObject().get("mode").getOrThrow().asString().getValue(), "user_access_token")

        let userScopeJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetScopeMissingTokenProvider())
        ).invoke(request)
        @Expect(userScopeJson.get("status").getOrThrow().asString().getValue(), "scope_missing")
        @Expect(userScopeJson.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:message")

        let appScopeJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetAppScopeMissingTokenProvider())
        ).invoke(request)
        @Expect(appScopeJson.get("status").getOrThrow().asString().getValue(), "app_scope_missing")
        @Expect(appScopeJson.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:message")
        @Expect(appScopeJson.toJsonString().contains("fake-access-token"), false)
    }

    @TestCase
    public func appScopeCheckerSeamRunsBeforeUserTokenAndReportsScopeDiagnostic(): Unit {
        let request = feishuOapiBuildRequest("feishu_im_user_message", "send", "tenant-a", JsonObject())
        let json = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetOkTokenProvider()),
            appScopeChecker: Some<FeishuOapiAppScopeChecker>(FeishuOapiToolsetMissingAppScopeChecker())
        ).invoke(request)

        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "app_scope_missing")
        @Expect(json.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:message.send_as_user")
        let diagnostic = json.get("scope_diagnostic").getOrThrow().asObject()
        @Expect(diagnostic.get("tokenMode").getOrThrow().asString().getValue(), "user_access_token")
        @Expect(diagnostic.get("token_mode").getOrThrow().asString().getValue(), "user_access_token")
        let app = diagnostic.get("app").getOrThrow().asObject()
        @Expect(app.get("status").getOrThrow().asString().getValue(), "app_scope_missing")
        @Expect(app.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:message.send_as_user")
        @Expect(json.toJsonString().contains("fake-access-token"), false)
    }

    @TestCase
    public func successfulUserTokenResultIncludesOfflineAccessAndUserScopeDiagnostic(): Unit {
        let request = feishuOapiBuildRequest("feishu_im_user_message", "send", "tenant-a", JsonObject())
        let json = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetOkTokenProvider()),
            appScopeChecker: Some<FeishuOapiAppScopeChecker>(FeishuOapiToolsetOkAppScopeChecker()),
            httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
                transport: Some<FeishuOapiRawHttpTransport>(FeishuOapiToolsetStaticRawTransport(200, body: "{\"code\":0,\"data\":{\"message_id\":\"om_live_fake\"}}"))
            ))
        ).invoke(request)

        @Expect(json.get("status").getOrThrow().asString().getValue(), "success")
        let diagnostic = json.get("scope_diagnostic").getOrThrow().asObject()
        let app = diagnostic.get("app").getOrThrow().asObject()
        let user = diagnostic.get("user").getOrThrow().asObject()
        let offline = diagnostic.get("offline_access").getOrThrow().asObject()
        @Expect(app.get("status").getOrThrow().asString().getValue(), "ok")
        @Expect(user.get("status").getOrThrow().asString().getValue(), "authorized")
        @Expect(user.get("granted_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:message")
        @Expect(offline.get("required").getOrThrow().asBool().getValue(), true)
        @Expect(offline.get("granted").getOrThrow().asBool().getValue(), false)
        @Expect(offline.get("status").getOrThrow().asString().getValue(), "missing")
        @Expect(json.toJsonString().contains("fake-access-token"), false)
    }

    @TestCase
    public func metisTokenProviderReadsTempStoreAndMapsAuthScopeExpiredAndRefresh(): Unit {
        let root = feishuOapiToolsetTempRoot("token-provider")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            let missing = MetisFeishuOapiTokenProvider(root: root, nowMs: 1000)
            @Expect(missing.userAccessToken("tenant-a", ["im:message:readonly"]).status, "auth_required")

            feishuOapiWriteStoredToken(root, "tenant-a", "stored-access-token", "stored-refresh-token", 100000, ["im:message:readonly"])
            let authorized = MetisFeishuOapiTokenProvider(root: root, nowMs: 1000).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(authorized.status, "authorized")
            @Expect(authorized.accessToken, "stored-access-token")

            let scopeMissing = MetisFeishuOapiTokenProvider(root: root, nowMs: 1000).userAccessToken("tenant-a", ["im:message", "contact:contact.base:readonly"])
            @Expect(scopeMissing.status, "scope_missing")
            @Expect(scopeMissing.missingScopes[0], "im:message")
            @Expect(scopeMissing.missingScopes[1], "contact:contact.base:readonly")

            feishuOapiWriteStoredToken(root, "tenant-a", "expired-access-token", "expired-refresh-token", 900, ["im:message:readonly"])
            let expired = MetisFeishuOapiTokenProvider(root: root, nowMs: 1000).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(expired.status, "expired")
            @Expect(expired.accessToken, "")

            let refresher = FeishuOapiToolsetFakeRefreshClient()
            let refreshed = MetisFeishuOapiTokenProvider(
                root: root,
                refreshClient: Some<FeishuOapiRefreshClient>(refresher),
                nowMs: 1000
            ).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(refreshed.status, "authorized")
            @Expect(refreshed.accessToken, "refreshed-access-token")
            @Expect(refresher.calls[0], "tenant-a")
            @Expect(refresher.calls[1], "expired-refresh-token")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func metisTokenProviderRefreshMapsDeniedPendingSlowDownParseErrorAndRetainsRefreshToken(): Unit {
        let root = feishuOapiToolsetTempRoot("refresh-states")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            feishuOapiWriteStoredToken(root, "tenant-a", "expired-access-token", "keep-refresh-token", 900, ["im:message:readonly"])

            let denied = MetisFeishuOapiTokenProvider(
                root: root,
                refreshClient: Some<FeishuOapiRefreshClient>(FeishuOapiToolsetStateRefreshClient("denied", error: "denied by user")),
                nowMs: 1000
            ).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(denied.status, "denied")

            let pending = MetisFeishuOapiTokenProvider(
                root: root,
                refreshClient: Some<FeishuOapiRefreshClient>(FeishuOapiToolsetStateRefreshClient("authorization_pending")),
                nowMs: 1000
            ).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(pending.status, "authorization_pending")

            let slowDown = MetisFeishuOapiTokenProvider(
                root: root,
                refreshClient: Some<FeishuOapiRefreshClient>(FeishuOapiToolsetStateRefreshClient("slow_down")),
                nowMs: 1000
            ).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(slowDown.status, "slow_down")

            let parseError = MetisFeishuOapiTokenProvider(
                root: root,
                refreshClient: Some<FeishuOapiRefreshClient>(FeishuOapiToolsetStateRefreshClient("parse_error", error: "bad json")),
                nowMs: 1000
            ).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(parseError.status, "parse_error")

            let refreshed = MetisFeishuOapiTokenProvider(
                root: root,
                refreshClient: Some<FeishuOapiRefreshClient>(FeishuOapiToolsetStateRefreshClient("authorized", accessToken: "new-access-token")),
                nowMs: 1000
            ).userAccessToken("tenant-a", ["im:message:readonly"])
            @Expect(refreshed.status, "authorized")
            let persisted = JsonValue.fromStr(String.fromUtf8(File.readFrom(root.join("tenant-a.json")))).asObject().toJsonString()
            @Expect(persisted.contains("new-access-token"), true)
            @Expect(persisted.contains("keep-refresh-token"), true)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func nativeHttpBoundaryBuildsMethodPathQueryBodyHeadersAndRedactsAuthorizationFromJson(): Unit {
        let params = JsonObject()
        params.put("chat_id", JsonString("oc_demo"))
        let query = JsonObject()
        query.put("page_size", JsonString("20"))
        params.put("query", query)
        let body = JsonObject()
        body.put("content", JsonString("hello"))
        params.put("body", body)
        let headers = JsonObject()
        headers.put("X-Metis-Test", JsonString("yes"))
        headers.put("Authorization", JsonString("must-not-win"))
        params.put("headers", headers)

        let request = feishuOapiBuildRequest("feishu_chat_members", "list", "tenant-a", params)
        let transport = FeishuOapiToolsetFakeRawTransport()
        let response = FeishuNativeOapiHttpClient(
            domain: "https://open.feishu.cn/",
            transport: Some<FeishuOapiRawHttpTransport>(transport)
        ).request(request, "boundary-secret-token")

        @Expect(response.ok, true)
        let sent = transport.last.getOrThrow()
        @Expect(sent.accountId, "tenant-a")
        @Expect(sent.method, "GET")
        @Expect(sent.url, "https://open.feishu.cn/open-apis/im/v1/chats/oc_demo/members?page_size=20")
        let sentBody = JsonValue.fromStr(sent.body).asObject()
        @Expect(sentBody.get("content").getOrThrow().asString().getValue(), "hello")
        @Expect(sent.headers.get("X-Metis-Test").getOrThrow(), "yes")
        @Expect(sent.headers.get("Authorization").getOrThrow(), "Bearer boundary-secret-token")
        @Expect(sent.toRedactedJson().toJsonString().contains("boundary-secret-token"), false)
        @Expect(sent.toRedactedJson().toJsonString().contains("must-not-win"), false)
    }

    @TestCase
    public func nativeClientNormalizesSuccessFeishuCodeHttpFailureAndInvalidJson(): Unit {
        let request = feishuOapiBuildRequest("feishu_chat", "get", "tenant-a", JsonObject())
        let tokenProvider = FeishuOapiToolsetOkTokenProvider()

        let success = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(tokenProvider),
            httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
                transport: Some<FeishuOapiRawHttpTransport>(FeishuOapiToolsetStaticRawTransport(200, body: "{\"code\":0,\"data\":{\"chat_id\":\"oc_1\"}}"))
            ))
        ).invoke(request)
        @Expect(success.get("status").getOrThrow().asString().getValue(), "success")

        let feishuCode = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(tokenProvider),
            httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
                transport: Some<FeishuOapiRawHttpTransport>(FeishuOapiToolsetStaticRawTransport(200, body: "{\"code\":\"99991679\",\"msg\":\"user scope denied\"}"))
            ))
        ).invoke(request)
        @Expect(feishuCode.get("status").getOrThrow().asString().getValue(), "scope_missing")
        @Expect(feishuCode.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), "im:chat:read")

        let httpFailure = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(tokenProvider),
            httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
                transport: Some<FeishuOapiRawHttpTransport>(FeishuOapiToolsetStaticRawTransport(503, body: "{\"code\":1255001,\"msg\":\"busy\"}", error: "upstream busy"))
            ))
        ).invoke(request)
        @Expect(httpFailure.get("status").getOrThrow().asString().getValue(), "api_error")
        @Expect(httpFailure.get("error").getOrThrow().asString().getValue(), "upstream busy")

        let invalidJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(tokenProvider),
            httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
                transport: Some<FeishuOapiRawHttpTransport>(FeishuOapiToolsetStaticRawTransport(200, body: "{not-json"))
            ))
        ).invoke(request)
        @Expect(invalidJson.get("status").getOrThrow().asString().getValue(), "api_error")
        @Expect(invalidJson.get("error").getOrThrow().asString().getValue().contains("valid JSON"), true)
    }

    @TestCase
    public func firstDomainAndAStageOpenClawToolNamesRouteThroughEnvelope(): Unit {
        let captured = ArrayList<String>()
        debugSetGatewayFeishuOapiToolCallRunnerForTest(Some({ method: String, payload: JsonObject =>
            captured.add(method)
            captured.add(payload.get("tool").getOrThrow().asString().getValue())
            captured.add(payload.get("category").getOrThrow().asString().getValue())
            captured.add(payload.get("path").getOrThrow().asString().getValue())
            let out = JsonObject()
            out.put("ok", JsonBool(true))
            out.put("status", JsonString("success"))
            out
        }))
        try {
            let toolset = GatewayFeishuOapiToolset()
            let _oauth = toolset.debugFeishuOapiInvokeForTest("feishu_oauth", "status", Some("tenant-a"), Some("{}"))
            let _batch = toolset.debugFeishuOapiInvokeForTest("feishu_oauth_batch_auth", "status", Some("tenant-a"), Some("{}"))
            let _botImage = toolset.debugFeishuOapiInvokeForTest("feishu_im_bot_image", "get", Some("tenant-a"), Some("{\"message_id\":\"om_1\",\"file_key\":\"img_1\",\"query\":{\"type\":\"image\"}}"))
            let _ask = toolset.debugFeishuOapiInvokeForTest("feishu_ask_user_question", "create", Some("tenant-a"), Some("{\"questions\":[]}"))

            @Expect(captured.contains("feishu_oauth"), true)
            @Expect(captured.contains("oauth"), true)
            @Expect(captured.contains("feishu_oauth_batch_auth"), true)
            @Expect(captured.contains("feishu_im_bot_image"), true)
            @Expect(captured.contains("/open-apis/im/v1/messages/:message_id/resources/:file_key"), true)
            @Expect(captured.contains("feishu_ask_user_question"), true)
        } finally {
            debugSetGatewayFeishuOapiToolCallRunnerForTest(None<(String, JsonObject) -> JsonObject>)
        }
    }

    @TestCase
    public func requestBoundaryMapsOpenClawDomains(): Unit {
        let common = feishuOapiBuildRequest("feishu_get_user", "get", "a", JsonObject())
        @Expect(common.category, "user")
        @Expect(common.domain, "common")
        @Expect(common.requiredScopes[0], "contact:contact.base:readonly")

        let chat = feishuOapiBuildRequest("feishu_chat_members", "list", "a", JsonObject())
        @Expect(chat.category, "chat")
        @Expect(chat.domain, "chat")

        let im = feishuOapiBuildRequest("feishu_im_user_get_messages", "list", "a", JsonObject())
        @Expect(im.category, "im")
        @Expect(im.domain, "im")

        let docs = feishuOapiBuildRequest("feishu_fetch_doc", "fetch", "a", JsonObject())
        @Expect(docs.category, "docs")
        @Expect(docs.domain, "docs")

        let wiki = feishuOapiBuildRequest("feishu_wiki_space", "list", "a", JsonObject())
        @Expect(wiki.category, "wiki")
        @Expect(wiki.domain, "wiki")

        let drive = feishuOapiBuildRequest("feishu_drive_file", "list", "a", JsonObject())
        @Expect(drive.category, "drive")
        @Expect(drive.domain, "drive")

        let search = feishuOapiBuildRequest("feishu_search_doc_wiki", "search", "a", JsonObject())
        @Expect(search.category, "search")
        @Expect(search.domain, "search")

        let calendar = feishuOapiBuildRequest("feishu_calendar_calendar", "list", "a", JsonObject())
        @Expect(calendar.category, "calendar")
        @Expect(calendar.domain, "calendar")

        let task = feishuOapiBuildRequest("feishu_task_task", "list", "a", JsonObject())
        @Expect(task.category, "task")
        @Expect(task.domain, "task")

        let sheets = feishuOapiBuildRequest("feishu_sheet", "get", "a", JsonObject())
        @Expect(sheets.category, "sheets")
        @Expect(sheets.domain, "sheets")

        let bitable = feishuOapiBuildRequest("feishu_bitable_app", "list", "a", JsonObject())
        @Expect(bitable.category, "bitable")
        @Expect(bitable.domain, "bitable")
    }

    @TestCase
    public func firstBatchActionMapUsesOpenClawActionKeysPathsMethodsTokenModeAndScopes(): Unit {
        let imSend = feishuOapiBuildRequest("feishu_im_user_message", "send", "a", JsonObject())
        @Expect(imSend.actionKey, "feishu_im_user_message.send")
        @Expect(imSend.path, "/open-apis/im/v1/messages")
        @Expect(imSend.method, "POST")
        @Expect(imSend.tokenMode, "user_access_token")
        @Expect(imSend.requiredScopes[0], "im:message")
        @Expect(imSend.requiredScopes[1], "im:message.send_as_user")

        let imReply = feishuOapiBuildRequest("feishu_im_user_message", "reply", "a", JsonObject())
        @Expect(imReply.actionKey, "feishu_im_user_message.reply")
        @Expect(imReply.path, "/open-apis/im/v1/messages/:message_id/reply")
        @Expect(imReply.method, "POST")

        let chatGet = feishuOapiBuildRequest("feishu_chat", "get", "a", JsonObject())
        @Expect(chatGet.actionKey, "feishu_chat.get")
        @Expect(chatGet.path, "/open-apis/im/v1/chats/:chat_id")
        @Expect(chatGet.requiredScopes[0], "im:chat:read")

        let userSearch = feishuOapiBuildRequest("feishu_search_user", "default", "a", JsonObject())
        @Expect(userSearch.actionKey, "feishu_search_user.default")
        @Expect(userSearch.path, "/open-apis/search/v1/user")
        @Expect(userSearch.method, "GET")
        @Expect(userSearch.requiredScopes[0], "contact:user:search")

        let docFetch = feishuOapiBuildRequest("feishu_fetch_doc", "default", "a", JsonObject())
        @Expect(docFetch.actionKey, "feishu_fetch_doc.default")
        @Expect(docFetch.path, "/open-apis/docx/v1/documents/:document_id/raw_content")
        @Expect(docFetch.requiredScopes[0], "docx:document:readonly")

        let wikiNode = feishuOapiBuildRequest("feishu_wiki_space_node", "get", "a", JsonObject())
        @Expect(wikiNode.actionKey, "feishu_wiki_space_node.get")
        @Expect(wikiNode.path, "/open-apis/wiki/v2/spaces/:space_id/nodes/:node_token")
        @Expect(wikiNode.requiredScopes[0], "wiki:node:read")

        let driveList = feishuOapiBuildRequest("feishu_drive_file", "list", "a", JsonObject())
        @Expect(driveList.actionKey, "feishu_drive_file.list")
        @Expect(driveList.path, "/open-apis/drive/v1/files")
        @Expect(driveList.requiredScopes[0], "space:document:retrieve")

        let searchDocs = feishuOapiBuildRequest("feishu_search_doc_wiki", "search", "a", JsonObject())
        @Expect(searchDocs.actionKey, "feishu_search_doc_wiki.search")
        @Expect(searchDocs.path, "/open-apis/search/v2/data_sources/:data_source_id/search")
        @Expect(searchDocs.requiredScopes[0], "search:docs:read")

        let sheetRead = feishuOapiBuildRequest("feishu_sheet", "read", "a", JsonObject())
        @Expect(sheetRead.actionKey, "feishu_sheet.read")
        @Expect(sheetRead.path, "/open-apis/sheets/v2/spreadsheets/:spreadsheet_token/values/:range")
        @Expect(sheetRead.method, "GET")
        @Expect(sheetRead.requiredScopes[0], "sheets:spreadsheet.meta:read")
    }

    @TestCase
    public func oapiActionMatrixCoversEveryExposedToolFamilyPathMethodAndScope(): Unit {
        let cases = ArrayList<FeishuOapiMatrixCase>()
        cases.add(FeishuOapiMatrixCase("feishu_fetch_doc", "default", "/open-apis/docx/v1/documents/:document_id/raw_content", "GET", "docx:document:readonly"))
        cases.add(FeishuOapiMatrixCase("feishu_create_doc", "default", "/open-apis/docx/v1/documents", "POST", "board:whiteboard:node:create"))
        cases.add(FeishuOapiMatrixCase("feishu_update_doc", "default", "/open-apis/docx/v1/documents/:document_id", "PATCH", "board:whiteboard:node:create"))
        cases.add(FeishuOapiMatrixCase("feishu_doc_comments", "create", "/open-apis/docx/v1/documents/:document_id/comments", "POST", "wiki:node:read"))
        cases.add(FeishuOapiMatrixCase("feishu_doc_media", "insert", "/open-apis/docx/v1/documents/:document_id/media", "POST", "docx:document:write_only"))
        cases.add(FeishuOapiMatrixCase("feishu_wiki_space", "list", "/open-apis/wiki/v2/spaces", "GET", "wiki:space:retrieve"))
        cases.add(FeishuOapiMatrixCase("feishu_wiki_space_node", "move", "/open-apis/wiki/v2/spaces/:space_id/nodes/:node_token/move", "POST", "wiki:node:move"))
        cases.add(FeishuOapiMatrixCase("feishu_drive_file", "delete", "/open-apis/drive/v1/files/:file_token", "DELETE", "space:document:delete"))
        cases.add(FeishuOapiMatrixCase("feishu_search_doc_wiki", "search", "/open-apis/search/v2/data_sources/:data_source_id/search", "POST", "search:docs:read"))
        cases.add(FeishuOapiMatrixCase("feishu_bitable_app", "patch", "/open-apis/bitable/v1/apps/:app_token", "PATCH", "base:app:update"))
        cases.add(FeishuOapiMatrixCase("feishu_bitable_app_table", "batch_create", "/open-apis/bitable/v1/apps/:app_token/tables/batch_create", "POST", "base:table:create"))
        cases.add(FeishuOapiMatrixCase("feishu_bitable_app_table_record", "batch_delete", "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/records/batch_delete", "DELETE", "base:record:delete"))
        cases.add(FeishuOapiMatrixCase("feishu_bitable_app_table_field", "update", "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/fields/:field_id", "PATCH", "base:field:read"))
        cases.add(FeishuOapiMatrixCase("feishu_bitable_app_table_view", "get", "/open-apis/bitable/v1/apps/:app_token/tables/:table_id/views/:view_id", "GET", "base:view:read"))
        cases.add(FeishuOapiMatrixCase("feishu_calendar_calendar", "primary", "/open-apis/calendar/v4/calendars/primary", "GET", "calendar:calendar:read"))
        cases.add(FeishuOapiMatrixCase("feishu_calendar_event", "reply", "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/reply", "POST", "calendar:calendar.event:reply"))
        cases.add(FeishuOapiMatrixCase("feishu_calendar_event_attendee", "create", "/open-apis/calendar/v4/calendars/:calendar_id/events/:event_id/attendees", "POST", "calendar:calendar.event:update"))
        cases.add(FeishuOapiMatrixCase("feishu_calendar_freebusy", "list", "/open-apis/calendar/v4/freebusy/list", "POST", "calendar:calendar.free_busy:read"))
        cases.add(FeishuOapiMatrixCase("feishu_task_task", "append_steps", "/open-apis/task/v2/tasks/:task_guid/append_steps", "POST", "task:task:write"))
        cases.add(FeishuOapiMatrixCase("feishu_task_tasklist", "add_members", "/open-apis/task/v2/tasklists/:tasklist_guid/add_members", "POST", "task:tasklist:write"))
        cases.add(FeishuOapiMatrixCase("feishu_task_attachment", "upload", "/open-apis/task/v2/tasks/:task_guid/attachments", "POST", "task:attachment:write"))
        cases.add(FeishuOapiMatrixCase("feishu_task_section", "tasks", "/open-apis/task/v2/tasklists/:tasklist_guid/sections/:section_guid/tasks", "GET", "task:task"))
        cases.add(FeishuOapiMatrixCase("feishu_task_comment", "create", "/open-apis/task/v2/tasks/:task_guid/comments", "POST", "task:comment:write"))
        cases.add(FeishuOapiMatrixCase("feishu_task_subtask", "list", "/open-apis/task/v2/tasks/:task_guid/subtasks", "GET", "task:task:read"))
        cases.add(FeishuOapiMatrixCase("feishu_task_agent", "update_profile", "/open-apis/task/v2/tasks/:task_guid/collaborators/:user_id", "PATCH", "task:task:write"))
        cases.add(FeishuOapiMatrixCase("feishu_sheet", "append", "/open-apis/sheets/v2/spreadsheets/:spreadsheet_token/values_append", "POST", "sheets:spreadsheet.meta:read"))
        cases.add(FeishuOapiMatrixCase("feishu_chat", "search", "/open-apis/im/v1/chats/search", "GET", "im:chat:read"))
        cases.add(FeishuOapiMatrixCase("feishu_chat_members", "default", "/open-apis/im/v1/chats/:chat_id/members", "GET", "im:chat.members:read"))
        cases.add(FeishuOapiMatrixCase("feishu_get_user", "default", "/open-apis/contact/v3/users/:user_id", "GET", "contact:contact.base:readonly"))
        cases.add(FeishuOapiMatrixCase("feishu_search_user", "default", "/open-apis/search/v1/user", "GET", "contact:user:search"))
        cases.add(FeishuOapiMatrixCase("feishu_im_user_message", "reply", "/open-apis/im/v1/messages/:message_id/reply", "POST", "im:message"))
        cases.add(FeishuOapiMatrixCase("feishu_im_user_get_messages", "default", "/open-apis/im/v1/messages", "GET", "im:chat:read"))
        cases.add(FeishuOapiMatrixCase("feishu_im_user_get_thread_messages", "default", "/open-apis/im/v1/messages", "GET", "im:chat:read"))
        cases.add(FeishuOapiMatrixCase("feishu_im_user_search_messages", "default", "/open-apis/search/v2/data_sources/im_message/search", "GET", "im:chat:read"))
        cases.add(FeishuOapiMatrixCase("feishu_im_user_fetch_resource", "default", "/open-apis/im/v1/messages/:message_id/resources/:file_key", "GET", "im:message.group_msg:get_as_user"))
        cases.add(FeishuOapiMatrixCase("feishu_im_bot_image", "default", "/open-apis/im/v1/messages/:message_id/resources/:file_key", "GET", "im:message.group_msg:get_as_user"))
        cases.add(FeishuOapiMatrixCase("feishu_oauth", "default", "/open-apis/authen/v1/oidc/device_authorize", "POST", "offline_access"))
        cases.add(FeishuOapiMatrixCase("feishu_oauth_batch_auth", "default", "/open-apis/authen/v1/oidc/device_authorize", "POST", "offline_access"))
        cases.add(FeishuOapiMatrixCase("feishu_ask_user_question", "default", "/open-apis/cardkit/v1/cards", "POST", "cardkit:card"))

        for (row in cases) {
            let request = feishuOapiBuildRequest(row.tool, row.action, "tenant-a", JsonObject())
            @Expect(request.path, row.path)
            @Expect(request.method, row.method)
            @Expect(request.tokenMode.isEmpty(), false)
            @Expect(request.requiredScopes[0], row.firstScope)
        }
    }

    @TestCase
    public func openClawActionParityIsTrackedAtActionLevelAndIncludesBasicBatch(): Unit {
        let keys = feishuOapiOpenClawActionKeys()
        @Expect(keys.size >= 96, true)
        @Expect(keys.contains("feishu_get_user.basic_batch"), true)
        @Expect(keys.contains("feishu_chat.get"), true)
        @Expect(keys.contains("feishu_bitable_app_table_record.batch_update"), true)
        @Expect(keys.contains("feishu_sheet.export"), true)

        for (key in keys) {
            @Expect(feishuOapiIsSupportedActionKey(key), true)
            @Expect(feishuOapiPathForActionKeyForTest(key).isEmpty(), false)
            @Expect(feishuOapiMethodForActionKeyForTest(key).isEmpty(), false)
            @Expect(feishuOapiRequiredScopesForActionKeyForTest(key).size > 0, true)
        }
    }

    @TestCase
    public func getUserBasicBatchHasPathScopeTokenModeAndToolsetEntry(): Unit {
        let request = feishuOapiBuildRequest("feishu_get_user", "basic_batch", "tenant-a", JsonObject())
        @Expect(request.actionKey, "feishu_get_user.basic_batch")
        @Expect(request.path, "/open-apis/contact/v3/users/basic_batch")
        @Expect(request.method, "POST")
        @Expect(request.tokenMode, "user_access_token")
        @Expect(request.requiredScopes[0], "contact:user.basic_profile:readonly")
        @Expect(request.supportedActions.contains("basic_batch"), true)

        let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
            "feishu_get_user",
            "basic_batch",
            Some("tenant-a"),
            Some("{\"body\":{\"user_ids\":[\"ou_1\"]},\"query\":{\"user_id_type\":\"open_id\"}}")
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("action_key").getOrThrow().asString().getValue(), "feishu_get_user.basic_batch")
        @Expect(json.get("path").getOrThrow().asString().getValue(), "/open-apis/contact/v3/users/basic_batch")
        @Expect(json.get("required_scopes").getOrThrow().asArray()[0].asString().getValue(), "contact:user.basic_profile:readonly")
    }

    @TestCase
    public func actionAwareTokenModeSelectsUatTatBotAndAppPaths(): Unit {
        let userRequest = feishuOapiBuildRequest("feishu_im_user_message", "send", "tenant-a", JsonObject())
        @Expect(userRequest.tokenMode, "user_access_token")

        let tenantRequest = feishuOapiBuildRequest("feishu_doc_comments", "list_replies", "tenant-a", JsonObject())
        @Expect(tenantRequest.tokenMode, "tenant_access_token")

        let botRequest = feishuOapiBuildRequest("feishu_im_bot_image", "default", "tenant-a", JsonObject())
        @Expect(botRequest.tokenMode, "bot_access_token")

        let appRequest = feishuOapiBuildRequest("feishu_ask_user_question", "default", "tenant-a", JsonObject())
        @Expect(appRequest.tokenMode, "app_access_token")

        let tokenProvider = FeishuOapiToolsetOkTokenProvider()
        let success = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(tokenProvider),
            httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
                transport: Some<FeishuOapiRawHttpTransport>(FeishuOapiToolsetStaticRawTransport(200, body: "{\"code\":0,\"data\":{\"ok\":true}}"))
            ))
        ).invoke(tenantRequest)
        @Expect(success.get("status").getOrThrow().asString().getValue(), "success")
        @Expect(tokenProvider.modes[0], "tenant_access_token")
        let diagnostic = success.get("scope_diagnostic").getOrThrow().asObject()
        @Expect(diagnostic.get("token_mode").getOrThrow().asString().getValue(), "tenant_access_token")
        @Expect(diagnostic.get("offline_access").getOrThrow().asObject().get("required").getOrThrow().asBool().getValue(), false)
    }

    @TestCase
    public func allOpenClawActionsHaveKnownDefaultTokenModes(): Unit {
        let allowed = ["user_access_token", "tenant_access_token", "bot_access_token", "app_access_token"]
        var tenantCount: Int64 = 0
        var botCount: Int64 = 0
        for (key in feishuOapiOpenClawActionKeys()) {
            let parts = key.split(".")
            let request = feishuOapiBuildRequest(parts[0], parts[1], "tenant-a", JsonObject())
            @Expect(allowed.contains(request.tokenMode), true)
            if (request.tokenMode == "tenant_access_token") {
                tenantCount++
            } else if (request.tokenMode == "bot_access_token") {
                botCount++
            }
        }
        @Expect(tenantCount >= 2, true)
        @Expect(botCount >= 1, true)
    }

    @TestCase
    public func lowRiskReadActionsHaveFakeSuccessAuthAndScopeDiagnosticsWithoutNetwork(): Unit {
        let cases = ArrayList<FeishuOapiMatrixCase>()
        cases.add(FeishuOapiMatrixCase("feishu_fetch_doc", "default", "/open-apis/docx/v1/documents/:document_id/raw_content", "GET", "docx:document:readonly"))
        cases.add(FeishuOapiMatrixCase("feishu_wiki_space_node", "get", "/open-apis/wiki/v2/spaces/:space_id/nodes/:node_token", "GET", "wiki:node:read"))
        cases.add(FeishuOapiMatrixCase("feishu_drive_file", "list", "/open-apis/drive/v1/files", "GET", "space:document:retrieve"))
        cases.add(FeishuOapiMatrixCase("feishu_calendar_event", "list", "/open-apis/calendar/v4/calendars/:calendar_id/events", "GET", "calendar:calendar.event:read"))
        cases.add(FeishuOapiMatrixCase("feishu_task_tasklist", "list", "/open-apis/task/v2/tasklists", "GET", "task:tasklist:read"))

        for (row in cases) {
            let request = feishuOapiBuildRequest(row.tool, row.action, "tenant-a", JsonObject())
            @Expect(request.path, row.path)
            @Expect(request.method, row.method)
            @Expect(request.requiredScopes[0], row.firstScope)

            let raw = FeishuOapiToolsetStaticRawTransport(200, body: "{\"code\":0,\"data\":{\"ok\":true}}")
            let success = MetisFeishuOapiClient(
                tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetReadOkTokenProvider()),
                appScopeChecker: Some<FeishuOapiAppScopeChecker>(FeishuOapiToolsetOkAppScopeChecker()),
                httpClient: Some<FeishuOapiHttpClient>(FeishuNativeOapiHttpClient(
                    transport: Some<FeishuOapiRawHttpTransport>(raw)
                ))
            ).invoke(request)
            @Expect(success.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(success.get("status").getOrThrow().asString().getValue(), "success")
            @Expect(success.get("tool").getOrThrow().asString().getValue(), row.tool)
            @Expect(success.get("path").getOrThrow().asString().getValue(), row.path)
            @Expect(success.toJsonString().contains("fake-read"), false)
            @Expect(raw.last.isSome(), true)

            let authHttp = FeishuOapiToolsetCountingHttpClient()
            let auth = MetisFeishuOapiClient(
                tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetAuthRequiredTokenProvider()),
                httpClient: Some<FeishuOapiHttpClient>(authHttp)
            ).invoke(request)
            @Expect(auth.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(auth.get("status").getOrThrow().asString().getValue(), "auth_required")
            @Expect(auth.get("auth").getOrThrow().asObject().get("required").getOrThrow().asBool().getValue(), true)
            @Expect(authHttp.calls, 0)

            let scopeHttp = FeishuOapiToolsetCountingHttpClient()
            let scope = MetisFeishuOapiClient(
                tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetScopeMissingTokenProvider()),
                httpClient: Some<FeishuOapiHttpClient>(scopeHttp)
            ).invoke(request)
            @Expect(scope.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(scope.get("status").getOrThrow().asString().getValue(), "scope_missing")
            @Expect(scope.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), row.firstScope)
            @Expect(scope.get("scope_diagnostic").getOrThrow().asObject().get("token_mode").getOrThrow().asString().getValue(), request.tokenMode)
            @Expect(scopeHttp.calls, 0)

            let appScopeHttp = FeishuOapiToolsetCountingHttpClient()
            let appScope = MetisFeishuOapiClient(
                tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetReadOkTokenProvider()),
                appScopeChecker: Some<FeishuOapiAppScopeChecker>(FeishuOapiToolsetReadMissingAppScopeChecker()),
                httpClient: Some<FeishuOapiHttpClient>(appScopeHttp)
            ).invoke(request)
            @Expect(appScope.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(appScope.get("status").getOrThrow().asString().getValue(), "app_scope_missing")
            @Expect(appScope.get("missing_scopes").getOrThrow().asArray()[0].asString().getValue(), row.firstScope)
            @Expect(appScopeHttp.calls, 0)
        }
    }

    @TestCase
    public func tatMissingAppCredentialsReturnsDiagnosticWithoutTokenOrOapiNetwork(): Unit {
        let request = feishuOapiBuildRequest("feishu_task_task", "append_steps", "tenant-a", JsonObject())
        @Expect(request.tokenMode, "tenant_access_token")
        let appTokenClient = FeishuOapiToolsetFakeAppTokenClient()
        let http = FeishuOapiToolsetCountingHttpClient()
        let json = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(MetisFeishuOapiTokenProvider(
                appTokenClient: Some<FeishuOapiAppTokenClient>(appTokenClient)
            )),
            httpClient: Some<FeishuOapiHttpClient>(http)
        ).invoke(request)
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "missing_credential")
        @Expect(json.get("token_mode").getOrThrow().asString().getValue(), "tenant_access_token")
        let credential = json.get("credential").getOrThrow().asObject()
        @Expect(credential.get("required").getOrThrow().asBool().getValue(), true)
        @Expect(credential.get("redacted").getOrThrow().asBool().getValue(), true)
        @Expect(credential.get("missing_fields").getOrThrow().asArray()[0].asString().getValue(), "app_id")
        @Expect(json.get("scope_diagnostic").getOrThrow().asObject().get("token_mode").getOrThrow().asString().getValue(), "tenant_access_token")
        @Expect(appTokenClient.modes.size, 0)
        @Expect(http.calls, 0)
        @Expect(json.toJsonString().contains("issued-"), false)
        @Expect(json.toJsonString().contains("app-secret-never-visible"), false)
        @Expect(json.toJsonString().contains("Authorization"), false)
    }

    @TestCase
    public func appTokenProviderFetchesCachesTenantBotAndAppTokensWithFakeClient(): Unit {
        let appTokenClient = FeishuOapiToolsetFakeAppTokenClient()
        let http = FeishuOapiToolsetCountingHttpClient()
        let provider = MetisFeishuOapiTokenProvider(
            appId: "app-id",
            appSecret: "app-secret-never-visible",
            appTokenClient: Some<FeishuOapiAppTokenClient>(appTokenClient),
            nowMs: 1000
        )

        let tenantRequest = feishuOapiBuildRequest("feishu_task_task", "append_steps", "tenant-a", JsonObject())
        let firstTenant = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(provider),
            httpClient: Some<FeishuOapiHttpClient>(http)
        ).invoke(tenantRequest)
        @Expect(firstTenant.get("status").getOrThrow().asString().getValue(), "success")
        @Expect(appTokenClient.modes[0], "tenant_access_token")
        @Expect(http.accessTokens[0], "issued-tenant_access_token")

        let secondTenant = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(provider),
            httpClient: Some<FeishuOapiHttpClient>(http)
        ).invoke(tenantRequest)
        @Expect(secondTenant.get("status").getOrThrow().asString().getValue(), "success")
        @Expect(appTokenClient.modes.size, 1)
        @Expect(http.accessTokens[1], "issued-tenant_access_token")

        let botRequest = feishuOapiBuildRequest("feishu_im_bot_image", "default", "tenant-a", JsonObject())
        let botJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(provider),
            httpClient: Some<FeishuOapiHttpClient>(http)
        ).invoke(botRequest)
        @Expect(botJson.get("status").getOrThrow().asString().getValue(), "success")
        @Expect(appTokenClient.modes[1], "bot_access_token")
        @Expect(http.accessTokens[2], "issued-bot_access_token")
        @Expect(botJson.toJsonString().contains("token_mode_unsupported"), false)

        let appRequest = feishuOapiBuildRequest("feishu_ask_user_question", "default", "tenant-a", JsonObject())
        let appJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(provider),
            httpClient: Some<FeishuOapiHttpClient>(http)
        ).invoke(appRequest)
        @Expect(appJson.get("status").getOrThrow().asString().getValue(), "success")
        @Expect(appTokenClient.modes[2], "app_access_token")
        @Expect(http.accessTokens[3], "issued-app_access_token")
        @Expect(appJson.toJsonString().contains("app-secret-never-visible"), false)
        @Expect(appJson.toJsonString().contains("issued-app_access_token"), false)
        @Expect(appJson.toJsonString().contains("token_mode_unsupported"), false)
    }

    @TestCase
    public func appTokenEndpointFailureReturnsApiErrorWithoutOapiNetwork(): Unit {
        let appTokenClient = FeishuOapiToolsetFakeAppTokenClient(status: "api_error", error: "token endpoint unavailable")
        let http = FeishuOapiToolsetCountingHttpClient()
        let request = feishuOapiBuildRequest("feishu_task_task", "append_steps", "tenant-a", JsonObject())
        let json = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(MetisFeishuOapiTokenProvider(
                appId: "app-id",
                appSecret: "app-secret-never-visible",
                appTokenClient: Some<FeishuOapiAppTokenClient>(appTokenClient)
            )),
            httpClient: Some<FeishuOapiHttpClient>(http)
        ).invoke(request)
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "api_error")
        @Expect(json.get("error").getOrThrow().asString().getValue(), "token endpoint unavailable")
        @Expect(appTokenClient.modes[0], "tenant_access_token")
        @Expect(http.calls, 0)
        @Expect(json.toJsonString().contains("app-secret-never-visible"), false)
    }

    @TestCase
    public func scopeDiagnosticIncludesModeSpecificRepairHintsAndPlatformBoundary(): Unit {
        let userRequest = feishuOapiBuildRequest("feishu_im_user_message", "send", "tenant-a", JsonObject())
        let userJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetScopeMissingTokenProvider())
        ).invoke(userRequest)
        let userHints = userJson.get("scope_diagnostic").getOrThrow().asObject()
            .get("repair_hints").getOrThrow().asObject()
        @Expect(userHints.get("token_mode").getOrThrow().asString().getValue(), "user_access_token")
        @Expect(userHints.get("user_authorization").getOrThrow().asObject().get("repair_method").getOrThrow().asString().getValue(), "channels.feishu.auth.start")
        @Expect(userHints.get("app_scope").getOrThrow().asObject().get("repair_method").getOrThrow().asString().getValue(), "feishu_developer_console_scope_grant")

        let tenantRequest = feishuOapiBuildRequest("feishu_task_task", "append_steps", "tenant-a", JsonObject())
        let tenantJson = MetisFeishuOapiClient(
            tokenProvider: Some<FeishuOapiTokenProvider>(MetisFeishuOapiTokenProvider())
        ).invoke(tenantRequest)
        let tenantHints = tenantJson.get("scope_diagnostic").getOrThrow().asObject()
            .get("repair_hints").getOrThrow().asObject()
        @Expect(tenantHints.get("token_mode").getOrThrow().asString().getValue(), "tenant_access_token")
        @Expect(tenantHints.get("app_credentials").getOrThrow().asObject().get("repair_method").getOrThrow().asString().getValue(), "configure_feishu_app_credentials")
        let platform = tenantHints.get("platform").getOrThrow().asObject()
        @Expect(platform.get("app_bot_autocreate").getOrThrow().asString().getValue(), "not_supported")
        @Expect(platform.get("setup_mode").getOrThrow().asString().getValue(), "guided_existing_app_bot")
        @Expect(platform.get("self_manage_scope_is_app_creation").getOrThrow().asBool().getValue(), false)
        @Expect(tenantJson.toJsonString().contains("Authorization"), false)
        @Expect(tenantJson.toJsonString().contains("Bearer"), false)
    }

    @TestCase
    public func smokeDryRunPlanBuildsReadWriteRequestsWithoutNetworkOrSecrets(): Unit {
        let casesRaw =
            "[" +
            "{\"tool\":\"feishu_fetch_doc\",\"action\":\"default\",\"accountId\":\"tenant-a\",\"params\":{\"document_id\":\"doccn_demo\"}}," +
            "{\"tool\":\"feishu_calendar_event\",\"action\":\"create\",\"params\":{\"path\":{\"calendar_id\":\"primary\"},\"body\":{\"summary\":\"smoke\"}}}" +
            "]"
        let plan = feishuOapiSmokeDryRunPlanFromCases(
            casesRaw,
            defaultAccountId: "tenant-a",
            domain: "https://open.feishu.cn"
        )
        @Expect(plan.get("status").getOrThrow().asString().getValue(), "dry_run")
        @Expect(plan.get("networkAttempted").getOrThrow().asBool().getValue(), false)
        @Expect(plan.get("externalResourceRequired").getOrThrow().asBool().getValue(), true)
        @Expect(plan.get("readCount").getOrThrow().asInt().getValue(), 1)
        @Expect(plan.get("writeCount").getOrThrow().asInt().getValue(), 1)
        @Expect(plan.get("writeRequiresLiveOptIn").getOrThrow().asBool().getValue(), true)

        let rows = plan.get("requests").getOrThrow().asArray()
        let read = rows[0].asObject()
        @Expect(read.get("operation").getOrThrow().asString().getValue(), "read")
        @Expect(read.get("method").getOrThrow().asString().getValue(), "GET")
        @Expect(read.get("url").getOrThrow().asString().getValue().contains("/open-apis/docx/v1/documents/doccn_demo/raw_content"), true)

        let write = rows[1].asObject()
        @Expect(write.get("operation").getOrThrow().asString().getValue(), "write")
        @Expect(write.get("method").getOrThrow().asString().getValue(), "POST")
        @Expect(write.get("hasBody").getOrThrow().asBool().getValue(), true)
        @Expect(write.get("url").getOrThrow().asString().getValue().contains("/open-apis/calendar/v4/calendars/primary/events"), true)
        let headers = write.get("headers").getOrThrow().asObject()
        @Expect(headers.get("Authorization").getOrThrow().asString().getValue(), "[redacted]")
        @Expect(plan.toJsonString().contains("live-access-token"), false)
        @Expect(plan.toJsonString().contains("Bearer"), false)
    }

    @TestCase
    public func unknownOapiActionReturnsStructuredUnsupportedActionDiagnostic(): Unit {
        let out = GatewayFeishuOapiToolset().debugFeishuOapiInvokeForTest(
            "feishu_chat",
            "explode",
            Some("tenant-a"),
            Some("{\"chat_id\":\"oc_demo\"}")
        )
        let json = JsonValue.fromStr(out).asObject()
        @Expect(json.get("ok").getOrThrow().asBool().getValue(), false)
        @Expect(json.get("status").getOrThrow().asString().getValue(), "unsupported_action")
        @Expect(json.get("action_key").getOrThrow().asString().getValue(), "feishu_chat.explode")
        @Expect(json.get("supported_actions").getOrThrow().asArray()[0].asString().getValue(), "get")
        @Expect(json.toJsonString().contains("Bearer"), false)
    }

    @TestCase
    public func oapiStatusDiagnosticsRedactSecretBearingErrorText(): Unit {
        let request = feishuOapiBuildRequest("feishu_chat", "get", "tenant-a", JsonObject())
        let statuses = ["auth_required", "scope_missing", "app_scope_missing", "missing_credential", "api_error"]
        for (status in statuses) {
            let json = MetisFeishuOapiClient(
                tokenProvider: Some<FeishuOapiTokenProvider>(FeishuOapiToolsetSecretErrorTokenProvider(status)),
                httpClient: Some<FeishuOapiHttpClient>(FeishuOapiToolsetCountingHttpClient())
            ).invoke(request)
            @Expect(json.get("status").getOrThrow().asString().getValue(), status)
            let raw = json.toJsonString()
            @Expect(raw.contains("[redacted]"), true)
            @Expect(raw.contains("secret-token-value"), false)
            @Expect(raw.contains("Bearer"), false)
            @Expect(raw.contains("Authorization"), false)
            @Expect(raw.contains("refresh_token"), false)
            @Expect(raw.contains("app_secret"), false)
        }
    }

    @TestCase
    public func liveSmokeHarnessDefaultsToSkippedUnlessExplicitEnvGateIsEnabled(): Unit {
        synchronized(MetisProcessEnvironmentLock) {
            let root = feishuOapiToolsetTempRoot("live-oapi-skip")
            let oldSmoke = getVariable("METIS_FEISHU_OAPI_LIVE_SMOKE")
            let oldReport = getVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR")
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
            try {
                setVariable("METIS_FEISHU_OAPI_LIVE_SMOKE", "")
                setVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR", root.toString())
                let result = feishuOapiLiveSmokeHarnessFromEnv()
                @Expect(result.get("status").getOrThrow().asString().getValue(), "skipped")
                @Expect(result.get("reason").getOrThrow().asString().getValue(), "env_gate_disabled")
                @Expect(result.get("live").getOrThrow().asBool().getValue(), false)
                @Expect(result.get("redacted").getOrThrow().asBool().getValue(), true)
                @Expect(result.get("requiresEnv").getOrThrow().asArray()[0].asString().getValue(), "METIS_FEISHU_OAPI_LIVE_SMOKE")
                let reportPath = result.get("reportPath").getOrThrow().asString().getValue()
                @Expect(reportPath.contains(root.toString()), true)
                let report = JsonValue.fromStr(String.fromUtf8(File.readFrom(Path(reportPath)))).asObject()
                @Expect(report.get("status").getOrThrow().asString().getValue(), "skipped")
                @Expect(report.get("redacted").getOrThrow().asBool().getValue(), true)
                @Expect(report.toJsonString().contains("accessToken"), false)
                @Expect(report.toJsonString().contains("Authorization"), false)
            } finally {
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
                match (oldSmoke) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_SMOKE", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_SMOKE", "")
                }
                match (oldReport) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR", "")
                }
            }
        }
    }

    @TestCase
    public func liveSmokeHarnessWithOptInButMissingExternalResourcesSkipsWithoutNetwork(): Unit {
        synchronized(MetisProcessEnvironmentLock) {
            let root = feishuOapiToolsetTempRoot("live-oapi-missing-resource")
            let oldSmoke = getVariable("METIS_FEISHU_OAPI_LIVE_SMOKE")
            let oldReport = getVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR")
            let oldAccessToken = getVariable("METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN")
            let oldUserScopes = getVariable("METIS_FEISHU_OAPI_LIVE_USER_SCOPES")
            let oldAppScopes = getVariable("METIS_FEISHU_OAPI_LIVE_APP_SCOPES")
            let oldCases = getVariable("METIS_FEISHU_OAPI_LIVE_CASES_JSON")
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
            try {
                setVariable("METIS_FEISHU_OAPI_LIVE_SMOKE", "1")
                setVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR", root.toString())
                setVariable("METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN", "")
                setVariable("METIS_FEISHU_OAPI_LIVE_USER_SCOPES", "")
                setVariable("METIS_FEISHU_OAPI_LIVE_APP_SCOPES", "")
                setVariable("METIS_FEISHU_OAPI_LIVE_CASES_JSON", "")

                let result = feishuOapiLiveSmokeHarnessFromEnv()
                @Expect(result.get("status").getOrThrow().asString().getValue(), "skipped")
                @Expect(result.get("reason").getOrThrow().asString().getValue(), "external-resource-required")
                @Expect(result.get("externalResourceRequired").getOrThrow().asBool().getValue(), true)
                @Expect(result.get("missingEnv").getOrThrow().asArray()[0].asString().getValue(), "METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN")
                @Expect(result.get("networkAttempted").getOrThrow().asBool().getValue(), false)
                let reportPath = result.get("reportPath").getOrThrow().asString().getValue()
                let report = JsonValue.fromStr(String.fromUtf8(File.readFrom(Path(reportPath)))).asObject()
                @Expect(report.get("status").getOrThrow().asString().getValue(), "skipped")
                @Expect(report.toJsonString().contains("accessToken"), false)
                @Expect(report.toJsonString().contains("Authorization"), false)
            } finally {
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
                match (oldSmoke) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_SMOKE", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_SMOKE", "")
                }
                match (oldReport) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_REPORT_DIR", "")
                }
                match (oldAccessToken) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_ACCESS_TOKEN", "")
                }
                match (oldUserScopes) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_USER_SCOPES", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_USER_SCOPES", "")
                }
                match (oldAppScopes) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_APP_SCOPES", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_APP_SCOPES", "")
                }
                match (oldCases) {
                    case Some(value) => setVariable("METIS_FEISHU_OAPI_LIVE_CASES_JSON", value)
                    case None => setVariable("METIS_FEISHU_OAPI_LIVE_CASES_JSON", "")
                }
            }
        }
    }

    @TestCase
    public func authRequestMergeHelperProducesOneMergedRequestForSameTurnScopes(): Unit {
        let merger = FeishuOapiAuthRequestMerger()
        let first = merger.merge("turn-1", "tenant-a", "ou_1", ["im:message"], "auth_required")
        @Expect(first.get("status").getOrThrow().asString().getValue(), "auth_required")
        @Expect(first.get("request_count").getOrThrow().asInt().getValue(), 1)

        let second = merger.merge("turn-1", "tenant-a", "ou_1", ["contact:user:search", "im:message"], "scope_missing")
        @Expect(second.get("request_count").getOrThrow().asInt().getValue(), 2)
        @Expect(second.get("status").getOrThrow().asString().getValue(), "auth_required")
        let scopes = second.get("merged_scopes").getOrThrow().asArray().toJsonString()
        @Expect(scopes.contains("im:message"), true)
        @Expect(scopes.contains("contact:user:search"), true)
        @Expect(second.get("merged").getOrThrow().asBool().getValue(), true)
    }
}
