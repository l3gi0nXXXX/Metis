package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{CliConfig, GatewayUserSettings, TelegramCustomCommandUserSettings}
import metis.gateway.channels.telegram.{setTelegramTransportRunnerForTest, TelegramTransportRequest, TelegramTransportResponse}
import metis.gateway.channels.feishu.{
    FeishuAuthHttpClient,
    FeishuAuthHttpResponse,
    FeishuFileAuthSessionStore,
    FeishuFileTokenStore,
    FeishuUserToken,
    feishuGatewayNativeAuthRevokeWithClient,
    feishuGatewayNativeAuthStatusWithStores
}
import metis.gateway.core.{
    gatewayChannelManagerSummary,
    gatewayChannelRuntimeMarkFailure,
    gatewayChannelRuntimeMarkMonitorEnabled,
    gatewayChannelRuntimeMarkMonitorTick,
    gatewayChannelRuntimeMarkPull,
    gatewayChannelRuntimeMarkRunning,
    gatewayChannelRuntimeMarkStarting,
    gatewayChannelRuntimePrimeAccount,
    gatewayChannelRuntimeRegisterAccount,
    gatewayPluginManagerSummary,
    setGatewayFeishuNativeAuthCompleteRunnerForTest,
    setGatewayFeishuNativeAuthPollRunnerForTest,
    setGatewayFeishuNativeAuthRevokeRunnerForTest,
    setGatewayFeishuNativeAuthRunnerForTest,
    setGatewayFeishuNativeAuthStatusRunnerForTest,
    setGatewayOpenClawPluginSidecarRunnerForTest
}

import std.convert.Parsable
import std.collection.{ArrayList, HashMap}
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private func channelsTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func channelsTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func channelsTestInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_: Exception) { 0 }
        case None => 0
    }
}

private func channelsRowsContainStringField(rows: JsonArray, key: String, value: String): Bool {
    for (i in 0..rows.size()) {
        try {
            let row = rows[i].asObject()
            if (channelsTestString(row, key) == value) {
                return true
            }
        } catch (_: Exception) {
            ()
        }
    }
    false
}

private func channelsTelegramRouteBinding(agentId: String, peerKind: String, peerId: String): JsonObject {
    let binding = JsonObject()
    binding.put("type", JsonString("route"))
    binding.put("agentId", JsonString(agentId))
    let matchObj = JsonObject()
    matchObj.put("channel", JsonString("telegram"))
    matchObj.put("accountId", JsonString("bot-a"))
    let peer = JsonObject()
    peer.put("kind", JsonString(peerKind))
    peer.put("id", JsonString(peerId))
    matchObj.put("peer", peer)
    binding.put("match", matchObj)
    binding
}

private func channelsTelegramAgent(id: String): JsonObject {
    let agent = JsonObject()
    agent.put("id", JsonString(id))
    agent
}

private func channelsTelegramTeamMember(agentId: String): JsonObject {
    let member = JsonObject()
    member.put("agentId", JsonString(agentId))
    member
}

private func channelsTelegramLiveRouteRoot(): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    agents.put("list", JsonArray([
        channelsTelegramAgent("private-agent"),
        channelsTelegramAgent("group-agent"),
        channelsTelegramAgent("topic-agent"),
        channelsTelegramAgent("writer"),
        channelsTelegramAgent("reviewer")
    ]))
    root.put("agents", agents)

    let bindings = JsonArray([])
    bindings.add(channelsTelegramRouteBinding("private-agent", "direct", "8734062810"))
    bindings.add(channelsTelegramRouteBinding("group-agent", "group", "-1001234567890"))
    bindings.add(channelsTelegramRouteBinding("topic-agent", "topic", "42"))
    root.put("bindings", bindings)

    let team = JsonObject()
    team.put("id", JsonString("content"))
    team.put("defaultAgentId", JsonString("group-agent"))
    team.put("members", JsonArray([
        channelsTelegramTeamMember("writer"),
        channelsTelegramTeamMember("reviewer")
    ]))
    team.put("bindings", JsonArray([
        channelsTelegramRouteBinding("group-agent", "group", "-1001234567890")
    ]))
    let broadcast = JsonObject()
    broadcast.put("enabled", JsonBool(true))
    broadcast.put("members", JsonArray([JsonString("writer"), JsonString("reviewer")]))
    team.put("broadcast", broadcast)
    let agentTeams = JsonObject()
    agentTeams.put("list", JsonArray([team]))
    root.put("agentTeams", agentTeams)
    root
}

private class GatewayChannelsFeishuAuthFakeHttpClient <: FeishuAuthHttpClient {
    public let calls = ArrayList<String>()
    private let tokenBody: String
    private let revokeBody: String

    public init(
        tokenBody!: String = "{\"access_token\":\"refreshed-access-secret\",\"refresh_token\":\"refreshed-refresh-secret\",\"expires_in\":7200,\"scope\":\"offline_access\"}",
        revokeBody!: String = "{\"ok\":true}"
    ) {
        this.tokenBody = tokenBody
        this.revokeBody = revokeBody
    }

    public func postForm(url: String, fields: HashMap<String, String>, _headers: HashMap<String, String>): FeishuAuthHttpResponse {
        this.calls.add(url)
        if (url.contains("/revoke")) {
            @Expect(fields.get("token").getOrThrow().isEmpty(), false)
            return FeishuAuthHttpResponse(200, this.revokeBody)
        }
        if (url.contains("/token")) {
            @Expect(fields.get("grant_type").getOrThrow(), "refresh_token")
            @Expect(fields.get("refresh_token").getOrThrow(), "refresh-secret")
            return FeishuAuthHttpResponse(200, this.tokenBody)
        }
        FeishuAuthHttpResponse(404, "{\"error\":\"not_found\"}")
    }
}

private func withGatewayChannelsTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-channels-test-home"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
    CliConfig.invalidatePathCache()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        CliConfig.invalidatePathCache()
    }
}

@Test
public class GatewayServerMethodsChannelsTest {
    @TestCase
    public func builtinSupportsCaptureFeishuAndQqDifferences(): Unit {
        var user = GatewayUserSettings()
        user.feishu.replyInThread = "enabled"
        user.telegram.replyToMode = "all"
        user.telegram.webhookUrl = "https://example.test/telegram-webhook"
        user.telegram.reactionNotifications = "all"
        user.telegram.reactionLevel = "ack"
        user.telegram.ackReaction = "👀"

        let feishu = gatewayChannelSupportsJson(user, "feishu")
        let qq = gatewayChannelSupportsJson(user, "qq")
        let telegram = gatewayChannelSupportsJson(user, "telegram")

        @Expect(channelsTestBool(feishu, "messageReply"), true)
        @Expect(channelsTestBool(feishu, "threadReply"), true)
        @Expect(channelsTestBool(feishu, "replyInThreadDefault"), true)
        @Expect(channelsTestString(feishu, "transport"), "official-sdk-monitor-host")

        @Expect(channelsTestBool(qq, "messageReply"), true)
        @Expect(channelsTestBool(qq, "threadReply"), false)
        @Expect(channelsTestBool(qq, "officialGateway"), true)
        @Expect(channelsTestString(qq, "transport"), "official-ws")

        @Expect(channelsTestBool(telegram, "threadReply"), true)
        @Expect(channelsTestBool(telegram, "officialGateway"), true)
        @Expect(channelsTestBool(telegram, "webhookIngress"), true)
        @Expect(channelsTestBool(telegram, "pollingIngress"), true)
        @Expect(channelsTestString(telegram, "activeMode"), "webhook")
        @Expect(channelsTestString(telegram, "transport"), "webhook")
        @Expect(channelsTestBool(telegram, "nativeCommands"), true)
        @Expect(channelsTestBool(telegram, "customCommands"), true)
        @Expect(channelsTestBool(telegram, "topicBindings"), true)
        @Expect(channelsTestBool(telegram, "topicActions"), true)
        @Expect(channelsTestBool(telegram, "messageActions"), true)
        @Expect(channelsTestBool(telegram, "actionDiscovery"), true)
        @Expect(channelsTestBool(telegram, "pollActions"), true)
        @Expect(channelsTestBool(telegram, "reactionActions"), true)
        @Expect(channelsTestBool(telegram, "reactionEvents"), true)
        @Expect(channelsTestBool(telegram, "inlineKeyboard"), true)
        @Expect(channelsTestBool(telegram, "callbackQuery"), true)
        @Expect(channelsTestBool(telegram, "ackReaction"), true)
        @Expect(channelsTestBool(telegram, "mediaSticker"), true)
        @Expect(channelsTestBool(telegram, "mediaPhoto"), true)
        @Expect(channelsTestBool(telegram, "mediaDocument"), true)
        @Expect(channelsTestBool(telegram, "mediaAudio"), true)
        @Expect(channelsTestBool(telegram, "mediaVoice"), true)
        @Expect(channelsTestBool(telegram, "mediaVideo"), true)
        @Expect(channelsTestBool(telegram, "mediaVideoNote"), true)
        @Expect(channelsTestBool(telegram, "mediaUnderstanding"), true)
        @Expect(channelsTestBool(telegram, "mediaContextBlock"), true)
        @Expect(channelsTestBool(telegram, "approvalResolver"), true)
        @Expect(channelsTestBool(telegram, "streamingDraft"), true)
        @Expect(channelsTestBool(telegram, "directoryAggregation"), true)
        @Expect(channelsTestBool(telegram, "modelButtons"), true)
        @Expect(channelsTestBool(telegram, "nativeCommandButtons"), true)
        @Expect(channelsTestBool(telegram, "allowedUpdatesAuto"), true)
    }

    @TestCase
    public func pluginSupportsExposeUnifiedBindingCapabilities(): Unit {
        let user = GatewayUserSettings()
        let supports = gatewayPluginSupportsJson(user, "dingtalk")

        @Expect(channelsTestBool(supports, "conversationBinding"), true)
        @Expect(channelsTestBool(supports, "accountBinding"), true)
        @Expect(channelsTestBool(supports, "threadReply"), true)
        @Expect(channelsTestString(supports, "provider"), "dingtalk")
    }

    @TestCase
    public func channelGetAndStatusExposeSupports(): Unit {
        var user = GatewayUserSettings()
        user.feishu.replyInThread = "enabled"
        user.telegram.reactionNotifications = "all"

        let channel = gatewayChannelGetJson(user, "feishu")
        @Expect(channel.get("supports").isSome(), true)

        let status = handleGatewayChannelsFamily("channels.status", user).getOrThrow().result.asObject()
        let meta = status.get("channelMeta").getOrThrow().asObject()
        let feishuMeta = meta.get("feishu").getOrThrow().asObject()
        let metaSupports = feishuMeta.get("supports").getOrThrow().asObject()
        @Expect(channelsTestBool(metaSupports, "threadReply"), true)
        @Expect(channelsTestString(metaSupports, "transport"), "official-sdk-monitor-host")
        let telegramMeta = meta.get("telegram").getOrThrow().asObject()
        let telegramSupports = telegramMeta.get("supports").getOrThrow().asObject()
        @Expect(channelsTestBool(telegramSupports, "reactionEvents"), true)
        @Expect(channelsTestBool(telegramSupports, "mediaPhoto"), true)
        @Expect(channelsTestBool(telegramSupports, "mediaAudio"), true)
        @Expect(channelsTestBool(telegramSupports, "mediaVideoNote"), true)
    }

    @TestCase
    public func feishuAuthStartRpcUsesGatewayRunnerAndRedactsSecrets(): Unit {
        try {
            setGatewayFeishuNativeAuthRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("pending"))
                out.put("accountId", JsonString(accountId))
                out.put("verificationUri", JsonString("https://verify.example/activate"))
                out.put("userCode", JsonString("ABCD-EFGH"))
                out.put("accessToken", JsonString("secret-access-token"))
                out.put("refreshToken", JsonString("secret-refresh-token"))
                out.put("authorization", JsonString("Bearer secret-authorization-token"))
                out.put("redacted", JsonBool(false))
                out
            }))

            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            let params = JsonObject()
            params.put("accountId", JsonString("tenant-a"))
            let response = handleGatewayChannelsFamily(
                "channels.feishu.auth.start",
                user,
                request: Some(GatewayRpcRequest("channels.feishu.auth.start", params: params))
            ).getOrThrow()

            @Expect(response.ok, true)
            let result = response.result.asObject()
            @Expect(channelsTestString(result, "status"), "pending")
            @Expect(channelsTestString(result, "accountId"), "tenant-a")
            @Expect(channelsTestString(result, "verificationUri"), "https://verify.example/activate")
            @Expect(result.toJsonString().contains("secret-access-token"), false)
            @Expect(result.toJsonString().contains("secret-refresh-token"), false)
            @Expect(result.toJsonString().contains("secret-authorization-token"), false)
            @Expect(channelsTestBool(result, "redacted"), true)
        } finally {
            setGatewayFeishuNativeAuthRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
        }
    }

    @TestCase
    public func feishuAuthLifecycleRpcUsesGatewayRunnersAndRedactsSecrets(): Unit {
        try {
            setGatewayFeishuNativeAuthStatusRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("pending"))
                out.put("accountId", JsonString(accountId))
                out.put("verificationUri", JsonString("https://verify.example/activate"))
                out.put("userCode", JsonString("ABCD-EFGH"))
                out.put("deviceCode", JsonString("device-secret"))
                out.put("accessToken", JsonString("secret-access-token"))
                out.put("error", JsonString("Authorization: Bearer secret-error-token"))
                out.put("redacted", JsonBool(false))
                out
            }))
            setGatewayFeishuNativeAuthPollRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("authorized"))
                out.put("accountId", JsonString(accountId))
                out.put("tokenStatus", JsonString("authorized"))
                out.put("refreshToken", JsonString("secret-refresh-token"))
                out.put("redacted", JsonBool(false))
                out
            }))
            setGatewayFeishuNativeAuthCompleteRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("authorized"))
                out.put("accountId", JsonString(accountId))
                out.put("authorization", JsonString("Bearer secret-authorization-token"))
                out.put("redacted", JsonBool(false))
                out
            }))
            setGatewayFeishuNativeAuthRevokeRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("revoked"))
                out.put("accountId", JsonString(accountId))
                out.put("appSecret", JsonString("secret-app-secret"))
                out.put("redacted", JsonBool(false))
                out
            }))

            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            let params = JsonObject()
            params.put("accountId", JsonString("tenant-a"))
            for ((method, expected) in [
                ("channels.feishu.auth.status", "pending"),
                ("channels.feishu.auth.poll", "authorized"),
                ("channels.feishu.auth.complete", "authorized"),
                ("channels.feishu.auth.revoke", "revoked")
            ]) {
                let response = handleGatewayChannelsFamily(
                    method,
                    user,
                    request: Some(GatewayRpcRequest(method, params: params))
                ).getOrThrow()
                @Expect(response.ok, true)
                let result = response.result.asObject()
                let raw = result.toJsonString()
                @Expect(channelsTestString(result, "status"), expected)
                @Expect(channelsTestString(result, "accountId"), "tenant-a")
                @Expect(raw.contains("secret-access-token"), false)
                @Expect(raw.contains("secret-refresh-token"), false)
                @Expect(raw.contains("secret-authorization-token"), false)
                @Expect(raw.contains("secret-app-secret"), false)
                @Expect(raw.contains("secret-error-token"), false)
                @Expect(raw.contains("device-secret"), false)
                @Expect(channelsTestBool(result, "redacted"), true)
            }
        } finally {
            setGatewayFeishuNativeAuthStatusRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
            setGatewayFeishuNativeAuthPollRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
            setGatewayFeishuNativeAuthCompleteRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
            setGatewayFeishuNativeAuthRevokeRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
        }
    }

    @TestCase
    public func feishuAuthLiveSmokeRpcSkipsWithoutOptInAndWritesRedactedTempReport(): Unit {
        let root = Path("/tmp/metis-gateway-feishu-auth-live-rpc-${DateTime.now().toUnixTimeStamp().toNanoseconds()}")
        let oldOptIn = getVariable("METIS_FEISHU_LIVE_AUTH_SMOKE")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            setVariable("METIS_FEISHU_LIVE_AUTH_SMOKE", "")
            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            user.feishu.appId = "app-id"
            user.feishu.appSecret = "app-secret-never-visible"
            let params = JsonObject()
            params.put("accountId", JsonString("tenant-a"))
            params.put("outputDir", JsonString(root.toString()))

            let response = handleGatewayChannelsFamily(
                "channels.feishu.auth.liveSmoke",
                user,
                request: Some(GatewayRpcRequest("channels.feishu.auth.liveSmoke", params: params))
            ).getOrThrow()
            let result = response.result.asObject()
            let reportPath = channelsTestString(result, "reportPath")
            let raw = String.fromUtf8(File.readFrom(Path(reportPath)))

            @Expect(response.ok, true)
            @Expect(channelsTestString(result, "status"), "skipped")
            @Expect(channelsTestString(result, "reason"), "env_gate_disabled")
            @Expect(channelsTestString(result, "fixtureRoot"), root.toString())
            @Expect(exists(Path(reportPath)), true)
            @Expect(raw.contains("start"), true)
            @Expect(raw.contains("revoke"), true)
            @Expect(raw.contains("app-secret-never-visible"), false)
            @Expect(raw.contains("Authorization"), false)
        } finally {
            match (oldOptIn) {
                case Some(value) => setVariable("METIS_FEISHU_LIVE_AUTH_SMOKE", value)
                case None => setVariable("METIS_FEISHU_LIVE_AUTH_SMOKE", "")
            }
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func channelsStatusExposesRedactedFeishuAuthLifecycleSummary(): Unit {
        try {
            setGatewayFeishuNativeAuthStatusRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("authorized"))
                out.put("accountId", JsonString(accountId))
                out.put("tokenStatus", JsonString("authorized"))
                out.put("scopeSummary", JsonString("offline_access im:message"))
                out.put("accessToken", JsonString("secret-access-token"))
                out.put("refreshToken", JsonString("secret-refresh-token"))
                out.put("authorization", JsonString("Bearer secret-authorization-token"))
                out.put("redacted", JsonBool(false))
                out
            }))

            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            let response = handleGatewayChannelsFamily("channels.status", user).getOrThrow()
            @Expect(response.ok, true)
            let result = response.result.asObject()
            let feishu = result.get("channels").getOrThrow().asObject().get("feishu").getOrThrow().asObject()
            let auth = feishu.get("auth").getOrThrow().asObject()
            let oauth = feishu.get("oauth").getOrThrow().asObject()
            let raw = result.toJsonString()

            @Expect(channelsTestString(auth, "accountId"), "tenant-a")
            @Expect(channelsTestString(auth, "status"), "authorized")
            @Expect(channelsTestString(auth, "tokenStatus"), "authorized")
            @Expect(channelsTestString(auth, "scopeSummary"), "offline_access im:message")
            @Expect(channelsTestBool(auth, "redacted"), true)
            @Expect(channelsTestString(oauth, "tokenStatus"), "authorized")
            @Expect(raw.contains("secret-access-token"), false)
            @Expect(raw.contains("secret-refresh-token"), false)
            @Expect(raw.contains("secret-authorization-token"), false)
        } finally {
            setGatewayFeishuNativeAuthStatusRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
        }
    }

    @TestCase
    public func feishuAuthStatusRefreshesExpiredTokenWithFakeClientAndReportsScopeDiagnostic(): Unit {
        let root = Path("/tmp/metis-gateway-feishu-auth-refresh-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            user.feishu.appId = "app-id"
            user.feishu.appSecret = "app-secret-never-visible"
            let tokenStore = FeishuFileTokenStore(root.join("tokens"))
            let sessionStore = FeishuFileAuthSessionStore(root.join("sessions"))
            let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
            tokenStore.save("tenant-a", FeishuUserToken(
                accessToken: "expired-access-secret",
                refreshToken: "refresh-secret",
                expiresAtMs: nowMs - 1000,
                scopes: ["offline_access", "im:message"]
            ))
            let http = GatewayChannelsFeishuAuthFakeHttpClient(
                tokenBody: "{\"access_token\":\"refreshed-access-secret\",\"refresh_token\":\"refreshed-refresh-secret\",\"expires_in\":7200,\"scope\":\"offline_access im:message im:message.send_as_user\"}"
            )

            let status = feishuGatewayNativeAuthStatusWithStores(
                "tenant-a",
                user,
                tokenStore,
                sessionStore,
                nowMs: nowMs,
                http: Some<FeishuAuthHttpClient>(http)
            )
            let diagnostic = status.get("scopeDiagnostic").getOrThrow().asObject()
            let raw = status.toJsonString()

            @Expect(channelsTestString(status, "status"), "authorized")
            @Expect(channelsTestString(status, "tokenStatus"), "authorized")
            @Expect(channelsTestString(status, "refreshStatus"), "refreshed")
            @Expect(channelsTestBool(diagnostic, "offlineAccess"), true)
            @Expect(raw.contains("refreshed-access-secret"), false)
            @Expect(raw.contains("refreshed-refresh-secret"), false)
            @Expect(raw.contains("app-secret-never-visible"), false)
            @Expect(http.calls.size, 1)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func feishuAuthRefreshWithoutCredentialsReturnsDiagnosticWithoutNetwork(): Unit {
        let root = Path("/tmp/metis-gateway-feishu-auth-refresh-missing-creds-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            let tokenStore = FeishuFileTokenStore(root.join("tokens"))
            let sessionStore = FeishuFileAuthSessionStore(root.join("sessions"))
            let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
            tokenStore.save("tenant-a", FeishuUserToken(
                accessToken: "expired-access-secret",
                refreshToken: "refresh-secret",
                expiresAtMs: nowMs - 1000,
                scopes: ["offline_access"]
            ))
            let http = GatewayChannelsFeishuAuthFakeHttpClient()

            let status = feishuGatewayNativeAuthStatusWithStores(
                "tenant-a",
                user,
                tokenStore,
                sessionStore,
                nowMs: nowMs,
                http: Some<FeishuAuthHttpClient>(http)
            )

            @Expect(channelsTestString(status, "status"), "expired")
            @Expect(channelsTestString(status, "refreshStatus"), "missing_app_credentials")
            @Expect(status.toJsonString().contains("expired-access-secret"), false)
            @Expect(http.calls.size, 0)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func feishuAuthServerRevokeUsesFakeClientAndNeverLogsTokens(): Unit {
        let root = Path("/tmp/metis-gateway-feishu-auth-server-revoke-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(root, recursive: true) } catch (_e: Exception) { () }
        try {
            var user = GatewayUserSettings()
            user.feishu.defaultAccount = "tenant-a"
            user.feishu.appId = "app-id"
            user.feishu.appSecret = "app-secret-never-visible"
            let tokenStore = FeishuFileTokenStore(root.join("tokens"))
            let sessionStore = FeishuFileAuthSessionStore(root.join("sessions"))
            tokenStore.save("tenant-a", FeishuUserToken(
                accessToken: "access-secret",
                refreshToken: "refresh-secret",
                expiresAtMs: 4102444800000,
                scopes: ["offline_access"]
            ))
            let http = GatewayChannelsFeishuAuthFakeHttpClient(revokeBody: "{\"ok\":true}")

            let revoked = feishuGatewayNativeAuthRevokeWithClient(
                "tenant-a",
                user,
                http,
                tokenStore,
                sessionStore,
                serverRevoke: true
            )
            let raw = revoked.toJsonString()

            @Expect(channelsTestString(revoked, "status"), "revoked")
            @Expect(channelsTestString(revoked, "serverRevokeStatus"), "revoked")
            @Expect(channelsTestBool(revoked, "localRevoked"), true)
            @Expect(tokenStore.load("tenant-a").isNone(), true)
            @Expect(raw.contains("access-secret"), false)
            @Expect(raw.contains("refresh-secret"), false)
            @Expect(raw.contains("app-secret-never-visible"), false)
            @Expect(http.calls.size, 1)
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramChannelGetExposesNativeConfigAndActions(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.commandsNative = "auto"
        user.telegram.customCommands = [TelegramCustomCommandUserSettings(command: "deploy", description: "Deploy")]
        user.telegram.reactionNotifications = "all"
        user.telegram.reactionLevel = "ack"
        user.telegram.webhookUrl = "https://example.test/telegram-webhook"
        user.telegram.groupHistoryEnabled = false
        user.telegram.groupHistoryLimit = 7
        user.telegram.network.envProxyEnabled = true
        user.telegram.actions.photo = true
        user.telegram.actions.document = true
        user.telegram.actions.inlineKeyboard = true
        user.telegram.actions.callbackQuery = true
        user.telegram.media.downloadEnabled = false
        user.telegram.media.mediaMaxBytes = 4096
        user.telegram.media.allowedMimes = ["image/*", "application/pdf"]
        user.telegram.media.outboundAllowUrl = true
        user.telegram.media.outboundAllowLocalPath = true
        user.telegram.media.outboundLocalRoots = ["/tmp/metis-media"]
        user.telegram.media.albumPolicy = "metadata-only"

        let channel = gatewayChannelGetJson(user, "telegram")
        @Expect(channelsTestString(channel, "kind"), "builtin")
        @Expect(channelsTestBool(channel, "enabled"), true)
        @Expect(channelsTestBool(channel, "configured"), true)
        @Expect(channelsTestString(channel, "commandsNative"), "auto")
        @Expect(channelsTestInt(channel, "customCommandCount"), 1)
        @Expect(channelsTestBool(channel, "groupHistoryEnabled"), false)
        @Expect(channelsTestInt(channel, "groupHistoryLimit"), 7)
        let network = channel.get("network").getOrThrow().asObject()
        @Expect(channelsTestBool(network, "envProxyEnabled"), true)
        @Expect(channelsTestString(network, "apiRoot"), "https://api.telegram.org")
        @Expect(channelsTestBool(network, "autoSelectFamily"), true)
        let actions = channel.get("actions").getOrThrow().asObject()
        @Expect(channelsTestBool(actions, "photo"), true)
        @Expect(channelsTestBool(actions, "document"), true)
        @Expect(channelsTestBool(actions, "inlineKeyboard"), true)
        @Expect(channelsTestBool(actions, "callbackQuery"), true)
        let actionSchemas = channel.get("actionSchemas").getOrThrow().asArray()
        @Expect(actionSchemas.size() >= 14, true)
        @Expect(actionSchemas.toJsonString().contains("inlineKeyboard"), true)
        @Expect(actionSchemas.toJsonString().contains("callbackQuery"), true)
        @Expect(actionSchemas.toJsonString().contains("sendPhoto"), true)
        @Expect(actionSchemas.toJsonString().contains("sendVideoNote"), true)
        let media = channel.get("media").getOrThrow().asObject()
        @Expect(channelsTestBool(media, "downloadEnabled"), false)
        @Expect(channelsTestInt(media, "mediaMaxBytes"), 4096)
        @Expect(media.get("allowedMimes").getOrThrow().asArray().toJsonString().contains("application/pdf"), true)
        @Expect(channelsTestBool(media, "outboundAllowUrl"), true)
        @Expect(channelsTestBool(media, "outboundAllowLocalPath"), true)
        @Expect(media.get("outboundLocalRoots").getOrThrow().asArray().toJsonString().contains("/tmp/metis-media"), true)
        @Expect(channelsTestString(media, "albumPolicy"), "metadata-only")
        let setup = channel.get("setup").getOrThrow().asObject()
        @Expect(channelsTestBool(setup, "probeAvailable"), true)
        @Expect(channelsTestBool(setup, "configMutationSafe"), true)
        @Expect(channelsTestBool(setup, "writesConfig"), false)
        let directory = channel.get("directory").getOrThrow().asObject()
        @Expect(directory.get("groups").isSome(), true)
        @Expect(directory.get("accounts").isSome(), true)
        @Expect(directory.get("targets").isSome(), true)
        @Expect(directory.get("rows").isSome(), true)
        @Expect(directory.get("aggregationSources").isSome(), true)
        let accountInspect = channel.get("accountInspect").getOrThrow().asObject()
        @Expect(accountInspect.get("tokenRedacted").getOrThrow().asBool().getValue(), true)
        let accountOps = channel.get("accountOps").getOrThrow().asObject()
        @Expect(channelsTestBool(accountOps, "setup"), true)
        @Expect(channelsTestBool(accountOps, "probe"), true)
        @Expect(channelsTestBool(accountOps, "directory"), true)
        @Expect(channelsTestBool(accountOps, "logout"), true)
        let supports = channel.get("supports").getOrThrow().asObject()
        @Expect(channelsTestBool(supports, "allowedUpdatesAuto"), true)
    }

    @TestCase
    public func telegramChannelDirectoryIncludesConfiguredGroupsTopicsAndAccounts(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.defaultAccount = "main"
        user.telegram.defaultTo = "user:8734062810"
        let groups = JsonObject()
        let groupRule = JsonObject()
        let topics = JsonObject()
        topics.put("42", JsonObject())
        groupRule.put("topics", topics)
        groups.put("-1001234567890", groupRule)
        user.telegram.groups = Some(groups)
        let accounts = JsonObject()
        let mainAccount = JsonObject()
        mainAccount.put("botToken", JsonString("secret-main-token"))
        mainAccount.put("allowFrom", JsonArray([JsonString("8734062810")]))
        mainAccount.put("media", JsonObject())
        mainAccount.put("network", JsonObject())
        accounts.put("main", mainAccount)
        accounts.put("work", JsonObject())
        user.telegram.accounts = Some(accounts)

        let channel = gatewayChannelGetJson(user, "telegram")
        let directory = channel.get("directory").getOrThrow().asObject()
        @Expect(directory.get("groups").getOrThrow().asArray().toJsonString().contains("-1001234567890"), true)
        @Expect(directory.get("accounts").getOrThrow().asArray().toJsonString().contains("main"), true)
        let targets = directory.get("targets").getOrThrow().asArray().toJsonString()
        @Expect(targets.contains("user:8734062810"), true)
        @Expect(targets.contains("group:-1001234567890"), true)
        @Expect(targets.contains("group:-1001234567890:topic:42"), true)
        let rowsValue = directory.get("rows").getOrThrow().asArray()
        @Expect(channelsRowsContainStringField(rowsValue, "accountId", "main"), true)
        let rows = rowsValue.toJsonString()
        @Expect(rows.contains("8734062810"), true)
        @Expect(rows.contains("-1001234567890"), true)
        @Expect(rows.contains("topic:42"), true)
        let inspect = channel.get("accountInspect").getOrThrow().asObject()
        @Expect(channelsTestString(inspect, "defaultAccountId"), "main")
        let inspectRows = inspect.get("accounts").getOrThrow().asArray()
        @Expect(channelsRowsContainStringField(inspectRows, "accountId", "main"), true)
        @Expect(channelsRowsContainStringField(inspectRows, "accountId", "work"), true)
        @Expect(inspect.toJsonString().contains("secret-main-token"), false)
        @Expect(inspect.toJsonString().contains("account-botToken"), true)
        @Expect(inspect.toJsonString().contains("hasMediaOverride"), true)
    }

    @TestCase
    public func feishuChannelGetExposesAccountsPolicyAndRedactedSecrets(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.defaultAccount = "tenant-a"
        user.feishu.appId = "legacy-app"
        user.feishu.appSecret = "legacy-secret"
        user.feishu.groupPolicy = "allowlist"
        user.feishu.groupAllowFrom = ["oc_team"]
        user.feishu.threadSession = true
        user.feishu.requireMention = true
        user.feishu.media.downloadEnabled = true
        user.feishu.media.downloadRoot = "/tmp/metis-feishu-runtime-media"
        let accounts = JsonObject()
        let tenantAccount = JsonObject()
        tenantAccount.put("appId", JsonString("tenant-app"))
        tenantAccount.put("appSecret", JsonString("tenant-secret"))
        tenantAccount.put("enabled", true.toJsonValue())
        accounts.put("tenant-a", tenantAccount)
        accounts.put("tenant-b", JsonObject())
        user.feishu.accounts = Some(accounts)
        let groups = JsonObject()
        groups.put("oc_team", JsonObject())
        user.feishu.groups = Some(groups)

        let channel = gatewayChannelGetJson(user, "feishu")
        @Expect(channelsTestString(channel, "defaultAccountId"), "tenant-a")
        @Expect(channelsTestString(channel, "groupPolicy"), "allowlist")
        @Expect(channelsTestBool(channel, "threadSession"), true)
        let directory = channel.get("directory").getOrThrow().asObject()
        @Expect(directory.get("accounts").getOrThrow().asArray().toJsonString().contains("tenant-a"), true)
        @Expect(directory.get("groups").getOrThrow().asArray().toJsonString().contains("oc_team"), true)
        let inspect = channel.get("accountInspect").getOrThrow().asObject()
        @Expect(channelsTestString(inspect, "defaultAccountId"), "tenant-a")
        @Expect(inspect.get("tokenRedacted").getOrThrow().asBool().getValue(), true)
        @Expect(inspect.get("accounts").getOrThrow().asArray().toJsonString().contains("tenant-b"), true)
        @Expect(inspect.toJsonString().contains("tenant-secret"), false)
        let media = channel.get("media").getOrThrow().asObject()
        @Expect(channelsTestString(media, "downloadRoot"), "/tmp/metis-feishu-runtime-media")
        let accountOps = channel.get("accountOps").getOrThrow().asObject()
        @Expect(channelsTestBool(accountOps, "list"), true)
        @Expect(channelsTestBool(accountOps, "describe"), true)
        @Expect(channelsTestBool(accountOps, "enable"), true)
        @Expect(channelsTestBool(accountOps, "disable"), true)
        @Expect(channelsTestBool(accountOps, "validate"), true)
    }

    @TestCase
    public func feishuChannelGetExposesExecutableDiagnosticsForAccountsThreadGroupMediaAndIgnoredFields(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.defaultAccount = "tenant-a"
        user.feishu.receiveMode = "webhook"
        user.feishu.appId = "legacy-app"
        user.feishu.appSecret = "legacy-secret-never-visible"
        user.feishu.groupPolicy = "allowlist"
        user.feishu.groupAllowFrom = ["oc_team"]
        user.feishu.threadSession = true
        user.feishu.requireMention = false
        user.feishu.allowBots = true
        user.feishu.media.downloadEnabled = true
        user.feishu.media.mediaMaxBytes = 8192
        user.feishu.media.allowedMimes = ["image/*", "application/pdf"]
        user.feishu.media.downloadRoot = "/tmp/metis-feishu-status-media"

        let accountGroup = JsonObject()
        accountGroup.put("respondToMentionAll", true.toJsonValue())
        let accountGroups = JsonObject()
        accountGroups.put("oc_team", accountGroup)
        let tenant = JsonObject()
        tenant.put("appSecret", JsonString("tenant-secret-never-visible"))
        tenant.put("footer", JsonObject())
        tenant.put("uat", JsonObject())
        tenant.put("dedup", JsonObject())
        tenant.put("groups", accountGroups)
        let accounts = JsonObject()
        accounts.put("tenant-a", tenant)
        user.feishu.accounts = Some(accounts)

        let channel = gatewayChannelGetJson(user, "feishu")
        let diagnostics = channel.get("diagnostics").getOrThrow().asObject()
        @Expect(channelsTestString(diagnostics, "channel"), "feishu")
        @Expect(channelsTestBool(diagnostics, "redacted"), true)
        @Expect(diagnostics.get("checkedInputs").getOrThrow().asArray().toJsonString().contains("threadSession"), true)
        @Expect(diagnostics.get("checkedInputs").getOrThrow().asArray().toJsonString().contains("media"), true)
        let account = diagnostics.get("account").getOrThrow().asObject()
        @Expect(channelsTestString(account, "defaultAccountId"), "tenant-a")
        @Expect(account.toJsonString().contains("tenant-secret-never-visible"), false)
        let receiveMode = diagnostics.get("receiveMode").getOrThrow().asObject()
        @Expect(channelsTestString(receiveMode, "mode"), "webhook")
        let groupPolicy = diagnostics.get("groupPolicy").getOrThrow().asObject()
        @Expect(channelsTestString(groupPolicy, "mode"), "allowlist")
        @Expect(channelsTestBool(groupPolicy, "requireMention"), false)
        @Expect(channelsTestBool(groupPolicy, "allowBots"), true)
        let threadSession = diagnostics.get("threadSession").getOrThrow().asObject()
        @Expect(channelsTestBool(threadSession, "enabled"), true)
        @Expect(threadSession.get("skippedReasons").getOrThrow().asArray().toJsonString().contains("thread_not_capable"), true)
        let media = diagnostics.get("media").getOrThrow().asObject()
        @Expect(channelsTestBool(media, "downloadEnabled"), true)
        @Expect(channelsTestInt(media, "mediaMaxBytes"), 8192)
        let raw = diagnostics.toJsonString()
        @Expect(raw.contains("unsupportedFields"), true)
        @Expect(raw.contains("ignoredFields"), true)
        @Expect(raw.contains("accounts.tenant-a.footer"), true)
        @Expect(raw.contains("accounts.tenant-a.uat"), true)
        @Expect(raw.contains("accounts.tenant-a.dedup"), true)
        @Expect(raw.contains("accounts.tenant-a.groups.oc_team.respondToMentionAll"), true)
        @Expect(raw.contains("legacy-secret-never-visible"), false)
        @Expect(raw.contains("tenant-secret-never-visible"), false)
    }

    @TestCase
    public func feishuChannelGetExposesNativeCommandAndGatewayRpcDiagnostics(): Unit {
        var user = GatewayUserSettings()
        user.feishu.enabled = true
        user.feishu.defaultAccount = "tenant-a"
        user.feishu.appId = "legacy-app"
        user.feishu.appSecret = "legacy-secret-never-visible"
        let accounts = JsonObject()
        let tenant = JsonObject()
        tenant.put("appId", JsonString("tenant-app"))
        accounts.put("tenant-a", tenant)
        user.feishu.accounts = Some(accounts)

        let channel = gatewayChannelGetJson(user, "feishu")
        let nativeCommands = channel.get("nativeCommands").getOrThrow().asObject()
        let diagnostics = channel.get("diagnostics").getOrThrow().asObject()
        let commands = nativeCommands.get("commands").getOrThrow().asArray().toJsonString()
        let rpcActions = nativeCommands.get("gatewayRpcActions").getOrThrow().asArray().toJsonString()
        let raw = channel.toJsonString()

        @Expect(channelsTestBool(nativeCommands, "supported"), true)
        @Expect(channelsTestString(nativeCommands, "surface"), "feishu-im-native-command")
        @Expect(commands.contains("/feishu start"), true)
        @Expect(commands.contains("/feishu doctor"), true)
        @Expect(commands.contains("/feishu auth"), true)
        @Expect(rpcActions.contains("channels.feishu.auth.start"), true)
        @Expect(rpcActions.contains("channels.feishu.auth.status"), true)
        @Expect(diagnostics.get("nativeCommands").isSome(), true)
        @Expect(raw.contains("tenant-app"), false)
        @Expect(raw.contains("legacy-secret-never-visible"), false)
    }

    @TestCase
    public func telegramChannelsRuntimeExposesNativeRuntimeView(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.webhookUrl = "https://example.test/telegram-webhook"
        user.telegram.reactionNotifications = "all"
        user.telegram.reactionLevel = "ack"
        user.telegram.ackReaction = "👀"
        user.telegram.groupHistoryLimit = 9
        user.telegram.network.envProxyEnabled = true
        user.telegram.actions.callbackQuery = true
        user.telegram.actions.inlineKeyboard = true
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        params.put("probe", true.toJsonValue())
        let result = handleGatewayChannelsFamily(
            "channels.runtime",
            user,
            request: Some(GatewayRpcRequest("channels.runtime", params: params))
        ).getOrThrow().result.asObject()
        let telegram = result.get("telegram").getOrThrow().asObject()
        @Expect(channelsTestString(telegram, "mode"), "webhook")
        @Expect(channelsTestBool(telegram, "webhookConfigured"), true)
        @Expect(channelsTestBool(telegram, "allowedUpdatesAuto"), true)
        @Expect(channelsTestBool(telegram, "groupHistoryEnabled"), true)
        @Expect(channelsTestInt(telegram, "groupHistoryLimit"), 9)
        let runtimeNetwork = telegram.get("network").getOrThrow().asObject()
        @Expect(channelsTestBool(runtimeNetwork, "envProxyEnabled"), true)
        let allowed = telegram.get("allowedUpdates").getOrThrow().asArray()
        @Expect(allowed.size() >= 5, true)
        @Expect(allowed[4].asString().getValue(), "message_reaction")
        @Expect(allowed.toJsonString().contains("callback_query"), true)
        let registration = telegram.get("registrationPayload").getOrThrow().asObject()
        @Expect(registration.get("allowed_updates").isSome(), true)
        let health = telegram.get("healthSnapshot").getOrThrow().asObject()
        @Expect(health.get("summary").isSome(), true)
        @Expect(health.get("webhook").isSome(), true)
        let capabilityState = telegram.get("capabilityState").getOrThrow().asObject()
        @Expect(channelsTestString(capabilityState, "approvalResolverState"), "button-resolver-ready")
        @Expect(channelsTestString(capabilityState, "directoryAggregationState"), "config-session-history-ready")
        @Expect(channelsTestString(capabilityState, "modelButtonState"), "available")
        @Expect(channelsTestString(capabilityState, "videoUnderstandingState"), "not_configured")
        @Expect(channelsTestString(capabilityState, "videoGenerationState"), "not_configured")
        let summary = health.get("summary").getOrThrow().asObject()
        @Expect(channelsTestBool(summary, "offsetPersistenceEnabled"), true)
        @Expect(summary.get("lastInboundUpdateId").isSome(), true)
        let offset = health.get("offset").getOrThrow().asObject()
        @Expect(channelsTestBool(offset, "persistenceEnabled"), true)
        @Expect(offset.get("statePath").isSome(), true)
        let liveProbe = telegram.get("liveProbe").getOrThrow().asObject()
        @Expect(channelsTestBool(liveProbe, "supported"), true)
        @Expect(channelsTestBool(liveProbe, "executed"), true)
    }

    @TestCase
    public func telegramChannelsHealthExposesNativeHealthView(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.webhookUrl = "https://example.test/telegram-webhook"
        user.telegram.reactionNotifications = "all"
        user.telegram.actions.photo = true
        user.telegram.actions.videoNote = true
        let params = JsonObject()
        params.put("probe", true.toJsonValue())

        let result = handleGatewayChannelsFamily(
            "channels.health",
            user,
            request: Some(GatewayRpcRequest("channels.health", params: params))
        ).getOrThrow().result.asObject()
        let telegram = result.get("telegram").getOrThrow().asObject()
        @Expect(channelsTestString(telegram, "mode"), "webhook")
        @Expect(channelsTestBool(telegram, "webhookConfigured"), true)
        @Expect(channelsTestBool(telegram, "allowedUpdatesAuto"), true)
        let supports = telegram.get("supports").getOrThrow().asObject()
        @Expect(channelsTestBool(supports, "mediaPhoto"), true)
        @Expect(channelsTestBool(supports, "mediaVideoNote"), true)
        let actions = telegram.get("actions").getOrThrow().asObject()
        @Expect(channelsTestBool(actions, "photo"), true)
        @Expect(channelsTestBool(actions, "videoNote"), true)
        let registration = telegram.get("registrationPayload").getOrThrow().asObject()
        @Expect(registration.get("allowed_updates").isSome(), true)
        let health = telegram.get("healthSnapshot").getOrThrow().asObject()
        @Expect(health.get("summary").isSome(), true)
        let summary = health.get("summary").getOrThrow().asObject()
        @Expect(channelsTestBool(summary, "offsetPersistenceEnabled"), true)
        let offset = health.get("offset").getOrThrow().asObject()
        @Expect(channelsTestBool(offset, "persistenceEnabled"), true)
        let liveProbe = telegram.get("liveProbe").getOrThrow().asObject()
        @Expect(channelsTestBool(liveProbe, "supported"), true)
        @Expect(channelsTestBool(liveProbe, "executed"), true)
    }

    @TestCase
    public func telegramChannelsAuditExposesUnifiedClosureSurface(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.webhookUrl = "https://example.test/telegram-webhook"
        user.telegram.reactionNotifications = "all"
        user.telegram.actions.photo = true
        user.telegram.actions.videoNote = true

        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        let result = handleGatewayChannelsFamily(
            "channels.audit",
            user,
            request: Some(GatewayRpcRequest("channels.audit", params: params))
        ).getOrThrow().result.asObject()
        let audit = result.get("audit").getOrThrow().asObject()
        @Expect(channelsTestString(audit, "kind"), "gateway-channels-audit")
        let summary = audit.get("summary").getOrThrow().asObject()
        @Expect(channelsTestString(summary, "phase"), "T12")
        let closure = summary.get("closure").getOrThrow().asObject()
        @Expect(channelsTestBool(closure, "telegramNativeRuntimeVisible"), true)
        @Expect(channelsTestBool(closure, "telegramLiveProbeRuntimeVisible"), true)
        @Expect(channelsTestBool(closure, "telegramReactionRuntimeVisible"), true)
        @Expect(channelsTestBool(closure, "telegramMediaRuntimeVisible"), true)
        @Expect(channelsTestBool(closure, "telegramMediaPersistenceVisible"), true)
        @Expect(channelsTestBool(closure, "controlUiSessionsHttpAvailable"), true)
        @Expect(channelsTestBool(closure, "controlUiSessionsWsAvailable"), true)
        @Expect(channelsTestBool(closure, "telegramThreadBindingVisibleInDashboardSessions"), true)
        @Expect(channelsTestBool(closure, "telegramThreadBindingVisibleInControlUiSessions"), true)
        @Expect(channelsTestBool(closure, "telegramThreadBindingVisibleInControlUiWsSessions"), true)
        let consumers = summary.get("consumers").getOrThrow().asObject()
        @Expect(channelsTestBool(consumers, "mcpOverHttp"), true)
        @Expect(channelsTestBool(consumers, "dashboardSessions"), true)
        @Expect(channelsTestBool(consumers, "controlUiSessionsHttp"), true)
        @Expect(channelsTestBool(consumers, "controlUiSessionsWs"), true)
        let runtime = audit.get("runtime").getOrThrow().asObject()
        let telegram = runtime.get("telegram").getOrThrow().asObject()
        @Expect(telegram.get("healthSnapshot").isSome(), true)
        let liveProbe = telegram.get("liveProbe").getOrThrow().asObject()
        @Expect(channelsTestBool(liveProbe, "supported"), true)
        @Expect(channelsTestBool(liveProbe, "executed"), true)
        let media = telegram.get("media").getOrThrow().asObject()
        @Expect(channelsTestBool(media, "persistenceEnabled"), true)
        @Expect(channelsTestBool(media, "downloadEnabled"), true)
        @Expect(telegram.get("supports").isSome(), true)
        @Expect(telegram.get("actions").isSome(), true)
        let accepted = audit.get("acceptance").getOrThrow().asArray()
        @Expect(accepted.toJsonString().contains("telegram-live-probe-runtime-is-visible-across-consumers"), true)
        @Expect(accepted.toJsonString().contains("telegram-reaction-and-media-runtime-are-visible-across-consumers"), true)
        @Expect(accepted.toJsonString().contains("telegram-media-download-and-file-persistence-are-visible-across-consumers"), true)
        let remaining = audit.get("remaining").getOrThrow().asArray()
        @Expect(remaining.toJsonString().contains("telegram-webhook-live-probe-remains-ops-followup"), false)
        @Expect(remaining.toJsonString().contains("telegram-media-download-and-file-persistence-remain-followups"), false)
    }

    @TestCase
    public func telegramT11DiagnosticsExposeSecurityAndRuntimeFindings(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.allowFrom = ["alice", "tg:8734062810"]
        user.telegram.groupAllowFrom = ["*", "user:notnumeric"]
        user.telegram.media.allowedMimes = []
        user.telegram.media.mediaMaxBytes = 0
        user.telegram.webhookUrl = "https://example.test/telegram-webhook"
        user.telegram.webhookMaxBodyBytes = 0
        user.telegram.webhookRateLimitWindowMs = 0
        user.telegram.media.outboundAllowLocalPath = true
        user.telegram.actions.deleteMessage = true
        user.telegram.network.dangerouslyAllowPrivateNetwork = true

        let runtime = JsonObject()
        runtime.put("mode", JsonString("polling"))
        let liveProbe = JsonObject()
        liveProbe.put("status", JsonString("degraded"))
        runtime.put("liveProbe", liveProbe)
        let health = JsonObject()
        let webhook = JsonObject()
        webhook.put("url", JsonString("https://example.test/old-webhook"))
        health.put("webhook", webhook)
        let webhookLifecycle = JsonObject()
        webhookLifecycle.put("cleanupError", JsonString("409 Conflict"))
        health.put("webhookLifecycle", webhookLifecycle)
        let polling = JsonObject()
        polling.put("lastOutcome", JsonString("http-409-conflict"))
        health.put("polling", polling)
        runtime.put("healthSnapshot", health)

        let diagnostics = gatewayTelegramDiagnosticsJson(user, runtime: runtime)
        let summary = diagnostics.get("summary").getOrThrow().asObject()
        @Expect(channelsTestBool(summary, "healthy"), false)
        @Expect(channelsTestBool(summary, "curlConfigRuntimeResidual"), false)
        @Expect(channelsTestString(summary, "transport"), "native-http")
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-token-missing"), true)
        @Expect(findings.contains("telegram-getme-failed"), true)
        @Expect(findings.contains("telegram-webhook-conflict"), true)
        @Expect(findings.contains("telegram-polling-409"), true)
        @Expect(findings.contains("telegram-allowfrom-nonnumeric"), true)
        @Expect(findings.contains("telegram-groupallowfrom-nonnumeric"), true)
        @Expect(findings.contains("telegram-groupallowfrom-wildcard"), true)
        @Expect(findings.contains("telegram-media-allowed-mimes-missing"), true)
        @Expect(findings.contains("telegram-media-size-limit-missing"), true)
        @Expect(findings.contains("telegram-webhook-body-limit-missing"), true)
        @Expect(findings.contains("telegram-webhook-rate-limit-missing"), true)
        @Expect(findings.contains("telegram-webhook-secret-missing"), true)
        @Expect(findings.contains("telegram-media-local-roots-missing"), true)
        @Expect(findings.contains("telegram-high-risk-actions-enabled"), true)
        @Expect(findings.contains("telegram-network-env-proxy"), true)
        @Expect(findings.contains("telegram-group-history-silent-ingest"), true)
        @Expect(findings.contains("telegram-curl-runtime-residual"), true)
    }

    @TestCase
    public func telegramDiagnosticsFlagUnsafeCustomApiRoot(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.apiRoot = "http://127.0.0.1:8081"
        user.telegram.network.dangerouslyAllowPrivateNetwork = false

        let diagnostics = gatewayTelegramDiagnosticsJson(user)
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-custom-api-root-risk"), true)
        @Expect(findings.contains("private_custom_api_root") || findings.contains("non_https_custom_api_root"), true)
    }

    @TestCase
    public func telegramDiagnosticsExposeVideoUnderstandingAndGenerationConfig(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"

        let videoProvider = JsonObject()
        videoProvider.put("kind", JsonString("qwen-vl-video"))
        videoProvider.put("model", JsonString("qwen-vl-max-latest"))
        let videoProviders = JsonObject()
        videoProviders.put("qwen-video-understanding", videoProvider)
        let video = JsonObject()
        video.put("enabled", true.toJsonValue())
        video.put("provider", JsonString("qwen-video-understanding"))
        video.put("providers", videoProviders)
        user.telegram.video = video

        let generationProvider = JsonObject()
        generationProvider.put("kind", JsonString("dashscope-qwen-video-generation"))
        generationProvider.put("model", JsonString("wanx2.1-t2v-turbo"))
        let generationProviders = JsonObject()
        generationProviders.put("qwen-video-generation", generationProvider)
        let generation = JsonObject()
        generation.put("enabled", true.toJsonValue())
        generation.put("provider", JsonString("qwen-video-generation"))
        generation.put("outputRoot", JsonString("/tmp/metis-video-generation-test"))
        generation.put("providers", generationProviders)
        user.media.videoGeneration = generation

        let diagnostics = gatewayTelegramDiagnosticsJson(user)
        let checkedInputs = diagnostics.get("checkedInputs").getOrThrow().asArray().toJsonString()
        @Expect(checkedInputs.contains("videoGeneration"), true)
        let videoUnderstanding = diagnostics.get("videoUnderstanding").getOrThrow().asObject()
        @Expect(channelsTestBool(videoUnderstanding, "configured"), true)
        @Expect(channelsTestString(videoUnderstanding, "provider"), "qwen-video-understanding")
        @Expect(channelsTestString(videoUnderstanding, "model"), "qwen-vl-max-latest")
        let videoGeneration = diagnostics.get("videoGeneration").getOrThrow().asObject()
        @Expect(channelsTestBool(videoGeneration, "configured"), true)
        @Expect(channelsTestString(videoGeneration, "provider"), "qwen-video-generation")
        @Expect(channelsTestString(videoGeneration, "model"), "wanx2.1-t2v-turbo")
        @Expect(channelsTestString(videoGeneration, "outputRoot"), "/tmp/metis-video-generation-test")
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-video-understanding-config"), true)
        @Expect(findings.contains("telegram-video-generation-config"), true)
        @Expect(findings.contains("telegram-token"), false)
    }

    @TestCase
    public func telegramDiagnosticsExposeImageGenerationConfigAndPhotoAction(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.actions.photo = true

        let provider = JsonObject()
        provider.put("kind", JsonString("openai-images"))
        provider.put("model", JsonString("gpt-image-1"))
        provider.put("apiKey", JsonString("secret-image-key"))
        let providers = JsonObject()
        providers.put("openai-image", provider)
        let generation = JsonObject()
        generation.put("enabled", true.toJsonValue())
        generation.put("provider", JsonString("openai-image"))
        generation.put("outputRoot", JsonString("/tmp/metis-image-generation-test"))
        generation.put("providers", providers)
        user.media.imageGeneration = generation

        let diagnostics = gatewayTelegramDiagnosticsJson(user)
        let checkedInputs = diagnostics.get("checkedInputs").getOrThrow().asArray().toJsonString()
        @Expect(checkedInputs.contains("imageGeneration"), true)
        let imageGeneration = diagnostics.get("imageGeneration").getOrThrow().asObject()
        @Expect(channelsTestBool(imageGeneration, "configured"), true)
        @Expect(channelsTestBool(imageGeneration, "photoActionEnabled"), true)
        @Expect(channelsTestString(imageGeneration, "provider"), "openai-image")
        @Expect(channelsTestString(imageGeneration, "model"), "gpt-image-1")
        @Expect(channelsTestString(imageGeneration, "outputRoot"), "/tmp/metis-image-generation-test")
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-image-generation-config"), true)
        @Expect(findings.contains("secret-image-key"), false)
    }

    @TestCase
    public func telegramT11DiagnosticsDetectGroupWithoutSenderAllowlist(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.groupPolicy = "allowlist"
        user.telegram.allowFrom = []
        user.telegram.groupAllowFrom = []

        let diagnostics = gatewayTelegramDiagnosticsJson(user)
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-group-no-sender-allowlist"), true)
    }

    @TestCase
    public func telegramDiagnosticsExposeRouteBroadcastLiveReadinessPreflight(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "123456:secret-live-ready-token"
        user.telegram.groupPolicy = "allowlist"
        user.telegram.groupAllowFrom = ["8734062810"]

        let diagnostics = gatewayTelegramDiagnosticsJson(user, routeRoot: channelsTelegramLiveRouteRoot())
        let readiness = diagnostics.get("routeBroadcastReadiness").getOrThrow().asObject()
        @Expect(channelsTestBool(readiness, "liveReady"), true)
        @Expect(channelsTestInt(readiness, "privateBindingCount"), 1)
        @Expect(channelsTestInt(readiness, "groupBindingCount"), 2)
        @Expect(channelsTestInt(readiness, "topicBindingCount"), 1)
        @Expect(channelsTestInt(readiness, "broadcastTeamCount"), 1)
        @Expect(channelsTestInt(readiness, "selectedMemberCount"), 2)
        @Expect(readiness.get("missingRequirements").getOrThrow().asArray().size(), 0)
        let selectedAgentIds = readiness.get("selectedAgentIds").getOrThrow().asArray().toJsonString()
        @Expect(selectedAgentIds.contains("writer"), true)
        @Expect(selectedAgentIds.contains("reviewer"), true)
        let evidenceFields = readiness.get("broadcastEvidenceFields").getOrThrow().asArray().toJsonString()
        @Expect(evidenceFields.contains("selectedAgentIds"), true)
        @Expect(evidenceFields.contains("agents[].sessionKey"), true)
        @Expect(evidenceFields.contains("agents[].deliveryStatus"), true)

        let checkedInputs = diagnostics.get("checkedInputs").getOrThrow().asArray().toJsonString()
        @Expect(checkedInputs.contains("routeBindingPreflight"), true)
        @Expect(checkedInputs.contains("teamBroadcast"), true)
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-route-broadcast-live-ready"), true)
        @Expect(findings.contains("secret-live-ready-token"), false)
    }

    @TestCase
    public func telegramDiagnosticsReportsConfiguredVideoUnderstandingWithoutSecrets(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true
        user.telegram.botToken = "telegram-token"
        user.telegram.video.put("provider", JsonString("gemini"))
        let provider = JsonObject()
        provider.put("kind", JsonString("gemini-inline-video"))
        provider.put("apiKey", JsonString("secret-video-key"))
        let providers = JsonObject()
        providers.put("gemini", provider)
        user.telegram.video.put("providers", providers)

        let diagnostics = gatewayTelegramDiagnosticsJson(user)
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-video-understanding-config"), true)
        @Expect(findings.contains("videoUnderstanding=configured"), true)
        @Expect(findings.contains("gemini-inline-video"), true)
        @Expect(findings.contains("secret-video-key"), false)
    }

    @TestCase
    public func telegramChannelsHealthExposesT11Diagnostics(): Unit {
        var user = GatewayUserSettings()
        user.telegram.enabled = true

        let result = handleGatewayChannelsFamily("channels.health", user).getOrThrow().result.asObject()
        let channels = result.get("channels").getOrThrow().asObject()
        let diagnostics = channels.get("telegramDiagnostics").getOrThrow().asObject()
        let findings = diagnostics.get("findings").getOrThrow().asArray().toJsonString()
        @Expect(findings.contains("telegram-token-missing"), true)
        @Expect(result.get("telegram").isSome(), true)
    }

    @TestCase
    public func deliveryPolicyDegradesUnsupportedThreadReply(): Unit {
        let user = GatewayUserSettings()
        let delivery = gatewayApplyChannelDeliveryPolicy(
            user,
            "qq",
            gatewayChannelsDeliveryJson("qq", "group:chat-1", "qq:default", replyToMessageId: "msg-1", replyInThread: true, deliverable: true)
        )
        @Expect(channelsTestBool(delivery, "requestedReplyInThread"), true)
        @Expect(channelsTestBool(delivery, "effectiveReplyInThread"), false)
        @Expect(channelsTestBool(delivery, "degraded"), true)
        @Expect(channelsTestString(delivery, "policyReason"), "thread-reply-unsupported")
    }

    @TestCase
    public func pluginDeliveryPolicyPreservesEffectiveMessageReplyButDisablesThreadReply(): Unit {
        let user = GatewayUserSettings()
        let delivery = gatewayApplyChannelDeliveryPolicy(
            user,
            "qq",
            gatewayChannelsDeliveryJson("qq", "group:chat-2", "qq:default", replyToMessageId: "msg-2", replyInThread: true, deliverable: true)
        )
        @Expect(channelsTestString(delivery, "effectiveReplyToMessageId"), "msg-2")
        @Expect(channelsTestBool(delivery, "effectiveReplyInThread"), false)
        @Expect(channelsTestString(delivery, "policyState"), "degraded")
    }

    @TestCase
    public func channelManagerSummaryExposesRuntimeManagerFields(): Unit {
        withGatewayChannelsTestHome {
            gatewayChannelRuntimeRegisterAccount("phase15-manager", accountId: "acct-a", pluginId: "dingtalk")
            gatewayChannelRuntimePrimeAccount("phase15-manager", accountId: "acct-a", autoEnabled: true)
            gatewayChannelRuntimeMarkStarting("phase15-manager", accountId: "acct-a")
            gatewayChannelRuntimeMarkRunning("phase15-manager", accountId: "acct-a")
            gatewayChannelRuntimeMarkPull("phase15-manager", accountId: "acct-a", inboundCount: 2)
            gatewayChannelRuntimeMarkMonitorEnabled("phase15-manager", accountId: "acct-a", enabled: true)
            gatewayChannelRuntimeMarkMonitorTick("phase15-manager", accountId: "acct-a")
            gatewayChannelRuntimeMarkFailure(
                "phase15-manager",
                accountId: "acct-a",
                lifecycleState: "backoff",
                error: "dial failed",
                backoffMs: 15000
            )

            let manager = gatewayChannelManagerSummary("phase15-manager")
            @Expect(channelsTestInt(manager, "count"), 1)
            @Expect(channelsTestInt(manager, "backoff"), 1)
            @Expect(channelsTestString(manager, "lifecycleState"), "backoff")
            @Expect(channelsTestString(manager, "taskState"), "recovering")
            @Expect(channelsTestInt(manager, "taskGeneration") > 0, true)
            @Expect(channelsTestString(manager, "monitorState"), "enabled")
            @Expect(channelsTestInt(manager, "monitorEnabledAtMs") > 0, true)
            @Expect(channelsTestInt(manager, "lastMonitorAtMs") > 0, true)
            @Expect(channelsTestInt(manager, "lastEventAtMs") > 0, true)
            @Expect(channelsTestString(manager, "lastError"), "dial failed")
            @Expect(channelsTestInt(manager, "nextRestartAtMs") > 0, true)
            @Expect(channelsTestInt(manager, "restartBudget"), 1)
            @Expect(channelsTestString(manager, "restartBudgetState"), "budgeting")
        }
    }

    @TestCase
    public func pluginManagerSummaryAggregatesPluginRuntimeManagerFields(): Unit {
        withGatewayChannelsTestHome {
            gatewayChannelRuntimeRegisterAccount("phase15-plugin-a", accountId: "acct-a", pluginId: "phase15-plugin")
            gatewayChannelRuntimeRegisterAccount("phase15-plugin-b", accountId: "acct-b", pluginId: "phase15-plugin")
            gatewayChannelRuntimeMarkStarting("phase15-plugin-a", accountId: "acct-a")
            gatewayChannelRuntimeMarkRunning("phase15-plugin-a", accountId: "acct-a")
            gatewayChannelRuntimeMarkMonitorEnabled("phase15-plugin-a", accountId: "acct-a", enabled: true)
            gatewayChannelRuntimeMarkPull("phase15-plugin-a", accountId: "acct-a", inboundCount: 1)
            gatewayChannelRuntimeMarkFailure(
                "phase15-plugin-b",
                accountId: "acct-b",
                lifecycleState: "backoff",
                error: "plugin error",
                backoffMs: 8000
            )

            let manager = gatewayPluginManagerSummary("phase15-plugin")
            @Expect(channelsTestInt(manager, "count"), 2)
            @Expect(channelsTestInt(manager, "running"), 1)
            @Expect(channelsTestString(manager, "monitorState"), "enabled")
            @Expect(channelsTestInt(manager, "monitorEnabledAtMs") > 0, true)
            @Expect(channelsTestInt(manager, "lastEventAtMs") > 0, true)
            @Expect(channelsTestString(manager, "lastError"), "plugin error")
            @Expect(channelsTestInt(manager, "nextRestartAtMs") > 0, true)
            @Expect(channelsTestInt(manager, "restartBudget"), 1)
            @Expect(channelsTestString(manager, "restartBudgetState"), "budgeting")
        }
    }

    @TestCase
    public func pluginsHealthActionsExposeActionsNeeded(): Unit {
        let user = GatewayUserSettings()
        let result = handleGatewayChannelsFamily("plugins.health.actions", user).getOrThrow().result.asObject()
        @Expect(result.get("actionsNeeded").isSome(), true)
        @Expect(result.get("byHealthState").isSome(), true)
    }

    @TestCase
    public func pluginsHealthMonitorExposesRestartBudgetLimit(): Unit {
        withGatewayChannelsTestHome {
            let user = GatewayUserSettings()
            let result = handleGatewayChannelsFamily("plugins.health", user).getOrThrow().result.asObject()
            let plugins = result.get("plugins").getOrThrow().asObject()
            let items = plugins.get("items").getOrThrow().asArray()
            if (items.size() > 0) {
                let first = items[0].asObject()
                let monitor = first.get("monitor").getOrThrow().asObject()
                @Expect(monitor.get("maxRestartsPerHour").isSome(), true)
            } else {
                @Expect(items.size(), 0)
            }
        }
    }

    @TestCase
    public func pluginsHealthPolicyExposesConfiguredAndRestartBudgetConstraints(): Unit {
        withGatewayChannelsTestHome {
            let user = GatewayUserSettings()
            let result = handleGatewayChannelsFamily("plugins.health", user).getOrThrow().result.asObject()
            let plugins = result.get("plugins").getOrThrow().asObject()
            let items = plugins.get("items").getOrThrow().asArray()
            if (items.size() > 0) {
                let first = items[0].asObject()
                let monitor = first.get("monitor").getOrThrow().asObject()
                let constraints = monitor.get("constraints").getOrThrow().asArray()
                var sawConfigured = false
                var sawRestartBudget = false
                for (i in 0..constraints.size()) {
                    let row = constraints[i].asObject()
                    let name = channelsTestString(row, "name")
                    if (name == "plugin-configured") {
                        sawConfigured = true
                    }
                    if (name == "restart-budget") {
                        sawRestartBudget = true
                    }
                }
                @Expect(sawConfigured, true)
                @Expect(sawRestartBudget, true)
            } else {
                @Expect(items.size(), 0)
            }
        }
    }

    @TestCase
    public func channelPolicySummaryAggregatesRemediationActions(): Unit {
        let user = GatewayUserSettings()
        let result = handleGatewayChannelsFamily("channels.policy", user).getOrThrow().result.asObject()
        let policy = result.get("policy").getOrThrow().asObject()
        @Expect(policy.get("actions").isSome(), true)
        @Expect(policy.get("actionCount").isSome(), true)
        @Expect(policy.get("remediationState").isSome(), true)
    }

    @TestCase
    public func pluginSurfacesAggregateActionsNeededFromItems(): Unit {
        let user = GatewayUserSettings()

        let approvals = handleGatewayChannelsFamily("plugins.approvals", user).getOrThrow().result.asObject()
        @Expect(approvals.get("actionsNeeded").isSome(), true)
        @Expect(approvals.get("actions").isSome(), true)

        let packageState = handleGatewayChannelsFamily("plugins.package_state", user).getOrThrow().result.asObject()
        @Expect(packageState.get("actionsNeeded").isSome(), true)
        @Expect(packageState.get("actions").isSome(), true)

        let setup = handleGatewayChannelsFamily("plugins.setup", user).getOrThrow().result.asObject()
        @Expect(setup.get("actionsNeeded").isSome(), true)
        @Expect(setup.get("actions").isSome(), true)
    }

    @TestCase
    public func channelsLogoutExposesTopLevelPayloadFields(): Unit {
        let user = GatewayUserSettings()
        let params = JsonObject()
        params.put("channel", JsonString("feishu"))
        let response = handleGatewayChannelsFamily(
            "channels.logout",
            user,
            request: Some(GatewayRpcRequest("channels.logout", params: params, clientId: "phase15-logout"))
        ).getOrThrow().result.asObject()

        @Expect(channelsTestString(response, "channel"), "feishu")
        @Expect(channelsTestString(response, "channelId"), "feishu")
        @Expect(response.get("cleared").isSome(), true)
        @Expect(response.get("loggedOut").isSome(), true)
        @Expect(channelsTestBool(response, "cleared"), false)
        @Expect(channelsTestBool(response, "loggedOut"), false)
    }

    @TestCase
    public func hostCompatibleChannelsLogoutAlsoExposeTopLevelLogoutFields(): Unit {
        withGatewayChannelsTestHome {
            let user = GatewayUserSettings()
            let params = JsonObject()
            params.put("channel", JsonString("metis-fixture"))
            params.put("accountId", JsonString("fixture:default"))
            let response = handleGatewayChannelsFamily(
                "channels.logout",
                user,
                request: Some(GatewayRpcRequest("channels.logout", params: params, clientId: "phase15-channel-logout"))
            ).getOrThrow().result.asObject()

            @Expect(response.get("channelId").isSome(), true)
            @Expect(response.get("loggedOut").isSome(), true)
            @Expect(response.get("cleared").isSome(), true)
            if (response.get("supported").isSome() && !channelsTestBool(response, "supported")) {
                @Expect(channelsTestString(response, "reason"), "channel-not-legacy-compatible")
            } else {
                @Expect(channelsTestString(response, "channel"), "metis-fixture")
                @Expect(channelsTestString(response, "channelId"), "metis-fixture")
            }
        }
    }

    @TestCase
    public func channelsSendUsesNativeTelegramAdapterForPhotoPayload(): Unit {
        let hookMethods = ArrayList<String>()
        setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
            if (request.context.startsWith("send:photo") && request.url.contains("/sendPhoto")) {
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":8801}}", outcome: "ok")
            }
            TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
        }))
        setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
            hookMethods.add(method)
            let out = JsonObject()
            out.put("ok", true.toJsonValue())
            out.put("status", JsonString("ok"))
            if (method == "hook.message_sending") {
                out.put("cancelled", false.toJsonValue())
                out.put("text", payload.get("text").getOrThrow())
            }
            out
        }))
        try {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.botToken = "telegram-token"
            user.telegram.actions.photo = true
            let params = JsonObject()
            params.put("channel", JsonString("telegram"))
            params.put("to", JsonString("user:8734062810"))
            params.put("message", JsonString("[photo]\nfileId=photo-file-id\ncaption=hello"))
            let response = handleGatewayChannelsFamily(
                "channels.send",
                user,
                request: Some(GatewayRpcRequest("channels.send", params: params, clientId: "telegram-native-send-photo"))
            ).getOrThrow().result.asObject()

            @Expect(channelsTestBool(response, "ok"), true)
            @Expect(channelsTestString(response, "channelId"), "telegram")
            @Expect(channelsTestString(response, "compatibilityMode"), "native-cangjie")
            @Expect(channelsTestString(response, "messageId"), "8801")
            @Expect(hookMethods.contains("hook.message_sending"), true)
            @Expect(hookMethods.contains("hook.message_sent"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            setGatewayOpenClawPluginSidecarRunnerForTest(None)
        }
    }

    @TestCase
    public func channelsSendTelegramQuoteTextUsesReplyParameters(): Unit {
        withGatewayChannelsTestHome {
            let bodies = ArrayList<String>()
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                bodies.add(request.body)
                if (request.url.contains("/sendMessage")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":8802}}", outcome: "ok")
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }))
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                if (method == "hook.message_sending") {
                    out.put("cancelled", false.toJsonValue())
                    out.put("text", payload.get("text").getOrThrow())
                }
                out
            }))
            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.botToken = "telegram-token"
                user.telegram.replyToMode = "all"
                let params = JsonObject()
                params.put("channel", JsonString("telegram"))
                params.put("to", JsonString("user:8734062810"))
                params.put("message", JsonString("quoted reply"))
                params.put("replyToMessageId", JsonString("88"))
                params.put("quoteText", JsonString("original quote"))
                let response = handleGatewayChannelsFamily(
                    "channels.send",
                    user,
                    request: Some(GatewayRpcRequest("channels.send", params: params, clientId: "telegram-native-send-quote"))
                ).getOrThrow().result.asObject()

                @Expect(channelsTestBool(response, "ok"), true)
                var sawReplyParameters = false
                for (body in bodies) {
                    if (
                        body.contains("\"reply_parameters\"") &&
                        body.contains("\"quote\"") &&
                        body.contains("original quote") &&
                        body.contains("\"message_id\"") &&
                        body.contains("\"88\"")
                    ) {
                        sawReplyParameters = true
                    }
                }
                @Expect(sawReplyParameters, true)
            } finally {
                setTelegramTransportRunnerForTest(None)
                setGatewayOpenClawPluginSidecarRunnerForTest(None)
            }
        }
    }

    @TestCase
    public func pluginsLogoutMarksRuntimeAsLoggedOutWhenHostClearsSession(): Unit {
        withGatewayChannelsTestHome {
            let user = GatewayUserSettings()
            let params = JsonObject()
            params.put("pluginId", JsonString("metis-fixture"))
            params.put("accountId", JsonString("fixture:default"))
            let response = handleGatewayChannelsFamily(
                "plugins.logout",
                user,
                request: Some(GatewayRpcRequest("plugins.logout", params: params, clientId: "phase15-plugin-logout"))
            ).getOrThrow().result.asObject()

            @Expect(response.get("pluginId").isSome(), true)
            if (response.get("supported").isSome() && !channelsTestBool(response, "supported")) {
                @Expect(channelsTestString(response, "reason"), "not-legacy-compatible")
            } else {
                @Expect(channelsTestString(response, "plugin"), "metis-fixture")
                @Expect(channelsTestBool(response, "loggedOut"), true)
                let runtime = response.get("runtime").getOrThrow().asObject()
                @Expect(channelsTestString(runtime, "lastError"), "logged out")
            }
        }
    }
}
