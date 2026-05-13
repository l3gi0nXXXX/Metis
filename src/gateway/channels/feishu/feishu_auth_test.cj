package metis.gateway.channels.feishu

import std.collection.{ArrayList, HashMap}
import std.fs.{Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private class FeishuAuthFakeHttpClient <: FeishuAuthHttpClient {
    public let calls = ArrayList<String>()

    public init() {}

    public func postForm(url: String, fields: HashMap<String, String>, _headers: HashMap<String, String>): FeishuAuthHttpResponse {
        this.calls.add(url)
        if (url.contains("/device_authorize")) {
            @Expect(fields.get("scope").getOrThrow().contains("offline_access"), true)
            return FeishuAuthHttpResponse(
                200,
                "{\"device_code\":\"device-1\",\"user_code\":\"ABCD-EFGH\",\"verification_uri\":\"https://verify.example/activate\",\"expires_in\":600,\"interval\":5}"
            )
        }
        if (url.contains("/token")) {
            @Expect(fields.get("device_code").getOrThrow(), "device-1")
            return FeishuAuthHttpResponse(
                200,
                "{\"access_token\":\"uat-secret\",\"refresh_token\":\"refresh-secret\",\"expires_in\":7200,\"scope\":\"offline_access im:message\"}"
            )
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
}
