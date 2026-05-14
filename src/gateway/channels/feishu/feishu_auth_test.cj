package metis.gateway.channels.feishu

import metis.core.config.GatewayUserSettings
import metis.gateway.tools.MetisFeishuOapiTokenProvider

import std.collection.{ArrayList, HashMap}
import std.fs.{Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private class FeishuAuthFakeHttpClient <: FeishuAuthHttpClient {
    public let calls = ArrayList<String>()
    public let capturedFields = ArrayList<String>()
    private let tokenBody: String
    private let tokenStatusCode: Int64
    private let tokenError: String

    public init(
        tokenBody!: String = "{\"access_token\":\"uat-secret\",\"refresh_token\":\"refresh-secret\",\"expires_in\":7200,\"scope\":\"offline_access im:message\"}",
        tokenStatusCode!: Int64 = 200,
        tokenError!: String = ""
    ) {
        this.tokenBody = tokenBody
        this.tokenStatusCode = tokenStatusCode
        this.tokenError = tokenError
    }

    public func postForm(url: String, fields: HashMap<String, String>, _headers: HashMap<String, String>): FeishuAuthHttpResponse {
        this.calls.add(url)
        if (fields.get("client_id").isSome()) {
            this.capturedFields.add(fields.get("client_id").getOrThrow())
        }
        if (fields.get("client_secret").isSome()) {
            this.capturedFields.add(fields.get("client_secret").getOrThrow())
        }
        if (fields.get("scope").isSome()) {
            this.capturedFields.add(fields.get("scope").getOrThrow())
        }
        if (url.contains("/device_authorize")) {
            @Expect(fields.get("scope").getOrThrow().contains("offline_access"), true)
            return FeishuAuthHttpResponse(
                200,
                "{\"device_code\":\"device-1\",\"user_code\":\"ABCD-EFGH\",\"verification_uri\":\"https://verify.example/activate\",\"expires_in\":600,\"interval\":5}"
            )
        }
        if (url.contains("/token")) {
            @Expect(fields.get("device_code").getOrThrow(), "device-1")
            return FeishuAuthHttpResponse(this.tokenStatusCode, this.tokenBody, error: this.tokenError)
        }
        FeishuAuthHttpResponse(404, "{\"error\":\"not_found\"}")
    }
}

@Test
public class FeishuAuthFoundationTest {
    @TestCase
    public func deviceFlowUsesInjectedHttpClientAndRedactsTokensFromStatus(): Unit {
        let http = FeishuAuthFakeHttpClient()
        let client = FeishuDeviceFlowClient(
            http,
            domain: "https://open.feishu.cn",
            appId: "app-id",
            appSecret: "app-secret-never-visible"
        )

        let started = client.start(scopes: ["im:message"])
        @Expect(started.status, "pending")
        @Expect(started.verificationUri, "https://verify.example/activate")
        @Expect(started.userCode, "ABCD-EFGH")
        @Expect(started.toRedactedJson().toJsonString().contains("app-secret-never-visible"), false)

        let token = client.poll("device-1")
        @Expect(token.status, "authorized")
        @Expect(token.accessToken, "uat-secret")
        @Expect(token.toRedactedJson().toJsonString().contains("uat-secret"), false)
        @Expect(http.calls.size, 2)
    }

    @TestCase
    public func deviceFlowMapsPendingSlowDownDeniedExpiredParseAndNetworkStatuses(): Unit {
        let pending = FeishuDeviceFlowClient(FeishuAuthFakeHttpClient(tokenBody: "{\"error\":\"authorization_pending\"}"))
        @Expect(pending.start().status, "pending")
        @Expect(pending.poll("device-1").status, "authorization_pending")

        let slowDown = FeishuDeviceFlowClient(FeishuAuthFakeHttpClient(tokenBody: "{\"error\":\"slow_down\"}"))
        @Expect(slowDown.poll("device-1").status, "slow_down")

        let denied = FeishuDeviceFlowClient(FeishuAuthFakeHttpClient(tokenBody: "{\"error\":\"access_denied\"}"))
        @Expect(denied.poll("device-1").status, "denied")

        let expired = FeishuDeviceFlowClient(FeishuAuthFakeHttpClient(tokenBody: "{\"error\":\"expired_token\"}"))
        @Expect(expired.poll("device-1").status, "expired")

        let parseError = FeishuDeviceFlowClient(FeishuAuthFakeHttpClient(tokenBody: "{not-json"))
        @Expect(parseError.poll("device-1").status, "parse_error")

        let networkError = FeishuDeviceFlowClient(FeishuAuthFakeHttpClient(tokenBody: "{\"error\":\"bad_gateway\"}", tokenStatusCode: 502, tokenError: "upstream down"))
        @Expect(networkError.poll("device-1").status, "network_error")

        let secretError = FeishuDeviceFlowClient(FeishuAuthFakeHttpClient(tokenBody: "{\"error\":\"bad_gateway\"}", tokenStatusCode: 502, tokenError: "Authorization: Bearer uat-secret"))
        let secretRaw = secretError.poll("device-1").toRedactedJson().toJsonString()
        @Expect(secretRaw.contains("uat-secret"), false)
        @Expect(secretRaw.contains("[redacted]"), true)
    }

    @TestCase
    public func tempTokenStorePersistsAndReturnsOnlyRedactedStatus(): Unit {
        let root = Path("/tmp/metis-feishu-token-store-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            let store = FeishuFileTokenStore(root)
            store.save("tenant-a", FeishuUserToken(
                accessToken: "access-secret",
                refreshToken: "refresh-secret",
                expiresAtMs: 4102444800000,
                scopes: ["offline_access", "im:message"]
            ))
            let loaded = store.load("tenant-a").getOrThrow()
            @Expect(loaded.accessToken, "access-secret")
            let status = store.status("tenant-a")
            let raw = status.toJsonString()
            @Expect(raw.contains("authorized"), true)
            @Expect(raw.contains("im:message"), true)
            @Expect(raw.contains("access-secret"), false)
            @Expect(raw.contains("refresh-secret"), false)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func authorizedTokenResultPersistsThroughTokenStoreAbstraction(): Unit {
        let root = Path("/tmp/metis-feishu-token-store-save-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            let firstStore = FeishuFileTokenStore(root)
            let result = FeishuDeviceTokenResult(
                status: "authorized",
                accessToken: "access-secret",
                refreshToken: "refresh-secret",
                expiresInSeconds: 3600,
                scopes: ["offline_access", "im:message"]
            )
            let status = feishuSaveAuthorizedUserToken(firstStore, "tenant-a", result, nowMs: 1000)
            @Expect(status.toJsonString().contains("access-secret"), false)
            @Expect(status.toJsonString().contains("refresh-secret"), false)

            let restartedStore = FeishuFileTokenStore(root)
            let loadedStatus = restartedStore.status("tenant-a").toJsonString()
            @Expect(loadedStatus.contains("authorized"), true)
            @Expect(loadedStatus.contains("im:message"), true)
            @Expect(loadedStatus.contains("access-secret"), false)
            @Expect(loadedStatus.contains("refresh-secret"), false)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func nativeAuthAndOapiClientReadTheSameTokenStoreShapeWithoutSecretsInStatus(): Unit {
        let root = Path("/tmp/metis-feishu-shared-token-store-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            let nativeStore = FeishuFileTokenStore(root)
            nativeStore.save("tenant-a", FeishuUserToken(
                accessToken: "shared-access-secret",
                refreshToken: "shared-refresh-secret",
                expiresAtMs: 4102444800000,
                scopes: ["offline_access", "im:message", "im:message.send_as_user"]
            ))

            let oapiLookup = MetisFeishuOapiTokenProvider(root: root, nowMs: 1000)
                .userAccessToken("tenant-a", ["im:message", "im:message.send_as_user"])
            @Expect(oapiLookup.status, "authorized")
            @Expect(oapiLookup.accessToken, "shared-access-secret")

            let status = nativeStore.status("tenant-a").toJsonString()
            @Expect(status.contains("authorized"), true)
            @Expect(status.contains("im:message.send_as_user"), true)
            @Expect(status.contains("shared-access-secret"), false)
            @Expect(status.contains("shared-refresh-secret"), false)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func nativeAuthStartUsesResolvedCredentialsAndReturnsRedactedPendingDeviceFlow(): Unit {
        let root = Path("/tmp/metis-feishu-native-auth-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.domain = "https://open.feishu.cn"
            user.feishu.defaultAccount = "tenant-a"
            user.feishu.appId = ""
            user.feishu.appSecret = "root-secret-never-visible"
            let account = JsonObject()
            account.put("appId", JsonString("tenant-app"))
            let accounts = JsonObject()
            accounts.put("tenant-a", account)
            user.feishu.accounts = Some(accounts)

            let http = FeishuAuthFakeHttpClient()
            let result = feishuGatewayNativeAuthStartWithClient(
                "tenant-a",
                user,
                http,
                FeishuFileTokenStore(root),
                nowMs: 1000
            )
            let raw = result.toJsonString()
            @Expect(feishuAuthTestString(result, "status"), "pending")
            @Expect(feishuAuthTestString(result, "verificationUri"), "https://verify.example/activate")
            @Expect(feishuAuthTestString(result, "userCode"), "ABCD-EFGH")
            @Expect(feishuAuthTestString(result, "expiresInSeconds"), "600")
            @Expect(feishuAuthTestString(result, "tokenStatus"), "missing")
            @Expect(http.calls.size, 1)
            @Expect(raw.contains("tenant-app"), false)
            @Expect(raw.contains("root-secret-never-visible"), false)
            @Expect(raw.contains("device-1"), false)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func nativeAuthStartUsesResolvedAccountAppSecretAndDomain(): Unit {
        let root = Path("/tmp/metis-feishu-native-auth-resolved-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.domain = "https://open.feishu.cn"
            user.feishu.defaultAccount = "tenant-a"
            user.feishu.appId = "top-app"
            user.feishu.appSecret = "top-secret-never-visible"
            let account = JsonObject()
            account.put("appId", JsonString("tenant-app"))
            account.put("appSecret", JsonString("tenant-secret-never-visible"))
            account.put("domain", JsonString("https://open.larksuite.com/"))
            let accounts = JsonObject()
            accounts.put("tenant-a", account)
            user.feishu.accounts = Some(accounts)

            let http = FeishuAuthFakeHttpClient()
            let result = feishuGatewayNativeAuthStartWithClient(
                "",
                user,
                http,
                FeishuFileTokenStore(root),
                nowMs: 1000
            )
            let raw = result.toJsonString()
            @Expect(feishuAuthTestString(result, "status"), "pending")
            @Expect(http.calls[0], "https://open.larksuite.com/open-apis/authen/v1/oidc/device_authorize")
            @Expect(http.capturedFields[0], "tenant-app")
            @Expect(http.capturedFields[1], "tenant-secret-never-visible")
            @Expect(http.capturedFields[2].contains("offline_access"), true)
            @Expect(raw.contains("tenant-app"), false)
            @Expect(raw.contains("tenant-secret-never-visible"), false)
            @Expect(raw.contains("top-secret-never-visible"), false)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func nativeAuthStartReturnsStoredTokenStatusWithoutStartingDeviceFlow(): Unit {
        let root = Path("/tmp/metis-feishu-native-auth-stored-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.appId = "app"
            user.feishu.appSecret = "secret-never-visible"
            let store = FeishuFileTokenStore(root)
            store.save("default", FeishuUserToken(
                accessToken: "stored-access-secret",
                refreshToken: "stored-refresh-secret",
                expiresAtMs: 4102444800000,
                scopes: ["offline_access", "im:message"]
            ))
            let http = FeishuAuthFakeHttpClient()
            let result = feishuGatewayNativeAuthStartWithClient("default", user, http, store, nowMs: 1000)
            let raw = result.toJsonString()
            @Expect(feishuAuthTestString(result, "status"), "authorized")
            @Expect(feishuAuthTestString(result, "tokenStatus"), "authorized")
            @Expect(raw.contains("im:message"), true)
            @Expect(http.calls.size, 0)
            @Expect(raw.contains("stored-access-secret"), false)
            @Expect(raw.contains("stored-refresh-secret"), false)
            @Expect(raw.contains("secret-never-visible"), false)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func nativeAuthLifecycleStatusPollCompleteAndRevokeUseLocalStoresWithoutLeakingSecrets(): Unit {
        let root = Path("/tmp/metis-feishu-native-auth-lifecycle-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            user.feishu.appId = "app-id"
            user.feishu.appSecret = "app-secret-never-visible"
            let tokenStore = FeishuFileTokenStore(root.join("tokens"))
            let sessionStore = FeishuFileAuthSessionStore(root.join("sessions"))
            let http = FeishuAuthFakeHttpClient()
            let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()

            let started = feishuGatewayNativeAuthStartWithClient(
                "tenant-a",
                user,
                http,
                tokenStore,
                sessionStore: sessionStore,
                nowMs: nowMs
            )
            @Expect(feishuAuthTestString(started, "status"), "pending")
            @Expect(started.toJsonString().contains("device-1"), false)
            @Expect(sessionStore.load("tenant-a").isSome(), true)

            let status = feishuGatewayNativeAuthStatusWithStores(
                "tenant-a",
                user,
                tokenStore,
                sessionStore,
                nowMs: nowMs
            )
            @Expect(feishuAuthTestString(status, "status"), "pending")
            @Expect(status.toJsonString().contains("ABCD-EFGH"), true)
            @Expect(status.toJsonString().contains("device-1"), false)

            let polled = feishuGatewayNativeAuthPollWithClient(
                "tenant-a",
                user,
                http,
                tokenStore,
                sessionStore,
                nowMs: nowMs + 1000
            )
            let polledRaw = polled.toJsonString()
            @Expect(feishuAuthTestString(polled, "status"), "authorized")
            @Expect(feishuAuthTestString(polled, "tokenStatus"), "authorized")
            @Expect(tokenStore.load("tenant-a").isSome(), true)
            @Expect(sessionStore.load("tenant-a").isNone(), true)
            @Expect(polledRaw.contains("uat-secret"), false)
            @Expect(polledRaw.contains("refresh-secret"), false)
            @Expect(polledRaw.contains("app-secret-never-visible"), false)
            @Expect(polledRaw.contains("device-1"), false)

            let completed = feishuGatewayNativeAuthCompleteWithClient(
                "tenant-a",
                user,
                http,
                tokenStore,
                sessionStore,
                nowMs: nowMs + 2000
            )
            @Expect(feishuAuthTestString(completed, "status"), "authorized")
            @Expect(completed.toJsonString().contains("uat-secret"), false)

            let revoked = feishuGatewayNativeAuthRevokeWithStores(
                "tenant-a",
                user,
                tokenStore,
                sessionStore
            )
            @Expect(feishuAuthTestString(revoked, "status"), "revoked")
            @Expect(tokenStore.load("tenant-a").isNone(), true)
            @Expect(revoked.toJsonString().contains("refresh-secret"), false)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func nativeAuthLifecyclePollMapsPendingRetryDeniedRemoteExpiredAndLocalTimeout(): Unit {
        let root = Path("/tmp/metis-feishu-native-auth-poll-statuses-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            user.feishu.appId = "app-id"
            user.feishu.appSecret = "app-secret-never-visible"
            let tokenStore = FeishuFileTokenStore(root.join("tokens"))
            let sessionStore = FeishuFileAuthSessionStore(root.join("sessions"))

            for ((body, expected) in [
                ("{\"error\":\"authorization_pending\"}", "authorization_pending"),
                ("{\"error\":\"slow_down\"}", "slow_down"),
                ("{\"error\":\"access_denied\"}", "denied"),
                ("{\"error\":\"expired_token\"}", "expired")
            ]) {
                sessionStore.save("tenant-a", FeishuPendingUserAuth(
                    deviceCode: "device-1",
                    userCode: "ABCD-EFGH",
                    verificationUri: "https://verify.example/activate",
                    expiresAtMs: 600000,
                    intervalSeconds: 5
                ))
                let result = feishuGatewayNativeAuthPollWithClient(
                    "tenant-a",
                    user,
                    FeishuAuthFakeHttpClient(tokenBody: body),
                    tokenStore,
                    sessionStore,
                    nowMs: 2000
                )
                @Expect(feishuAuthTestString(result, "status"), expected)
                @Expect(result.toJsonString().contains("app-secret-never-visible"), false)
                @Expect(result.toJsonString().contains("device-1"), false)
            }

            sessionStore.save("tenant-a", FeishuPendingUserAuth(
                deviceCode: "device-1",
                userCode: "ABCD-EFGH",
                verificationUri: "https://verify.example/activate",
                expiresAtMs: 1000,
                intervalSeconds: 5
            ))
            let timeoutHttp = FeishuAuthFakeHttpClient()
            let timeout = feishuGatewayNativeAuthPollWithClient(
                "tenant-a",
                user,
                timeoutHttp,
                tokenStore,
                sessionStore,
                nowMs: 2000
            )
            @Expect(feishuAuthTestString(timeout, "status"), "expired")
            @Expect(timeoutHttp.calls.size, 0)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }
}

private func feishuAuthTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) {
            try { v.asInt().getValue().toString() } catch (_inner: Exception) { "" }
        }
        case None => ""
    }
}
