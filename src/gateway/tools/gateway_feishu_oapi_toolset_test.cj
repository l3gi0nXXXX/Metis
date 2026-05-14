package metis.gateway.tools

import std.collection.{ArrayList, HashMap}
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
}

private class FeishuOapiToolsetAppScopeMissingTokenProvider <: FeishuOapiTokenProvider {
    public init() {}

    public func userAccessToken(_accountId: String, requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("app_scope_missing", missingScopes: requiredScopes, error: "missing app scope")
    }
}

private class FeishuOapiToolsetOkTokenProvider <: FeishuOapiTokenProvider {
    public init() {}

    public func userAccessToken(_accountId: String, _requiredScopes: Array<String>): FeishuOapiTokenLookup {
        FeishuOapiTokenLookup("authorized", accessToken: "fake-access-token")
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
