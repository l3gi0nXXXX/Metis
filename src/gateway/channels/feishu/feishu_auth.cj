package metis.gateway.channels.feishu

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists, remove}
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

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
            out.put("error", JsonString(this.error))
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
            out.put("error", JsonString(this.error))
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
        let out = JsonObject()
        out.put("accountId", JsonString(gatewayFeishuNormalizeAccountId(accountId)))
        out.put("status", JsonString(if (this.accessToken.isEmpty()) { "missing" } else { "authorized" }))
        out.put("authorized", JsonBool(!this.accessToken.isEmpty()))
        out.put("hasAccessToken", JsonBool(!this.accessToken.isEmpty()))
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
        case "expired_token" => "expired_token"
        case "access_denied" => "access_denied"
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
