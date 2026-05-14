package metis.gateway.core

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.model.{ChannelPolicyConfig, ChannelType, ChatType, InboundMessage, OutboundMessage, SendResult}

import std.collection.{ArrayList, HashMap}
import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

private class GatewayFeishuNativeTestAdapter <: ChannelAdapter {
    private let inbound = ArrayList<InboundMessage>()
    private let sent = ArrayList<OutboundMessage>()
    private let accountId: String

    public init(accountId!: String = "default") {
        this.accountId = if (accountId.trimAscii().isEmpty()) { "default" } else { accountId.trimAscii() }
    }

    public prop name: String {
        get() { "feishu" }
    }

    public func start(): Unit {}

    public func stop(): Unit {}

    public func queueDirect(text: String): Unit {
        this.inbound.add(InboundMessage(
            ChannelType.Feishu,
            "om-${this.inbound.size}",
            "ou_peer",
            "ou_sender",
            ChatType.Direct,
            text,
            true,
            DateTime.now(),
            accountId: this.accountId
        ))
    }

    public func queueDirectWithRoute(text: String, mediaContext: JsonObject): Unit {
        this.inbound.add(InboundMessage(
            ChannelType.Feishu,
            "om-${this.inbound.size}",
            "ou_peer",
            "ou_sender",
            ChatType.Direct,
            text,
            true,
            DateTime.now(),
            accountId: this.accountId,
            mediaContext: mediaContext
        ))
    }

    public func queueGroup(text: String): Unit {
        this.inbound.add(InboundMessage(
            ChannelType.Feishu,
            "om-group-${this.inbound.size}",
            "oc_group",
            "ou_sender",
            ChatType.Group,
            text,
            false,
            DateTime.now(),
            accountId: this.accountId
        ))
    }

    public func pullInbound(): Array<InboundMessage> {
        let out = this.inbound.toArray()
        this.inbound.clear()
        out
    }

    public func send(message: OutboundMessage): SendResult {
        this.sent.add(message)
        SendResult.Success
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        this.sent.add(message)
        "feishu-native-${this.sent.size}"
    }

    public func sentText(index: Int64): String {
        match (this.sent.get(index)) {
            case Some(v) => v.text
            case None => ""
        }
    }

    public func sentCount(): Int64 {
        this.sent.size
    }
}

private func gatewayFeishuNativeTestRoot(appSecret!: String = ""): JsonObject {
    let root = JsonObject()
    let gateway = JsonObject()
    let feishu = JsonObject()
    feishu.put("enabled", JsonBool(true))
    feishu.put("defaultAccount", JsonString("default"))
    feishu.put("receiveMode", JsonString("long_connect"))
    feishu.put("domain", JsonString("https://open.feishu.cn"))
    feishu.put("appId", JsonString("cli_test_app"))
    feishu.put("appSecret", JsonString(appSecret))
    gateway.put("feishu", feishu)
    root.put("gateway", gateway)
    root.put("agents", JsonArray([]))
    root.put("bindings", JsonArray([]))
    root
}

private func gatewayFeishuNativeBroadcastAgent(id: String, isDefault!: Bool = false): JsonObject {
    let agent = JsonObject()
    agent.put("id", JsonString(id))
    if (isDefault) {
        agent.put("default", JsonBool(true))
    }
    let model = JsonObject()
    model.put("primary", JsonString("fake:${id}"))
    agent.put("model", model)
    agent
}

private func gatewayFeishuNativeBroadcastBinding(agentId: String): JsonObject {
    let binding = JsonObject()
    binding.put("type", JsonString("route"))
    binding.put("agentId", JsonString(agentId))
    let matchObj = JsonObject()
    matchObj.put("channel", JsonString("feishu"))
    matchObj.put("accountId", JsonString("*"))
    let peer = JsonObject()
    peer.put("kind", JsonString("direct"))
    peer.put("id", JsonString("ou_peer"))
    matchObj.put("peer", peer)
    binding.put("match", matchObj)
    binding
}

private func gatewayFeishuNativeBroadcastMember(agentId: String): JsonObject {
    let member = JsonObject()
    member.put("agentId", JsonString(agentId))
    member
}

private func gatewayFeishuNativeBroadcastRoot(): JsonObject {
    let root = gatewayFeishuNativeTestRoot()
    let agents = JsonObject()
    agents.put("list", JsonArray([
        gatewayFeishuNativeBroadcastAgent("main", isDefault: true),
        gatewayFeishuNativeBroadcastAgent("ops"),
        gatewayFeishuNativeBroadcastAgent("writer"),
        gatewayFeishuNativeBroadcastAgent("reviewer")
    ]))
    root.put("agents", agents)

    let bindings = JsonArray([])
    bindings.add(gatewayFeishuNativeBroadcastBinding("ops"))
    root.put("bindings", bindings)

    let team = JsonObject()
    team.put("id", JsonString("content"))
    team.put("displayName", JsonString("Content Team"))
    team.put("defaultAgentId", JsonString("ops"))
    team.put("members", JsonArray([
        gatewayFeishuNativeBroadcastMember("ops"),
        gatewayFeishuNativeBroadcastMember("writer"),
        gatewayFeishuNativeBroadcastMember("reviewer")
    ]))
    team.put("bindings", JsonArray([gatewayFeishuNativeBroadcastBinding("ops")]))
    let broadcast = JsonObject()
    broadcast.put("enabled", JsonBool(true))
    broadcast.put("members", JsonArray([
        JsonString("writer"),
        JsonString("reviewer")
    ]))
    team.put("broadcast", broadcast)
    let agentTeams = JsonObject()
    agentTeams.put("list", JsonArray([team]))
    root.put("agentTeams", agentTeams)
    root
}

private func gatewayFeishuNativeBroadcastMediaContext(): JsonObject {
    let media = JsonObject()
    let context = JsonObject()
    let route = JsonObject()
    route.put("accountId", JsonString("default"))
    route.put("defaultAccountId", JsonString("default"))
    route.put("peerKind", JsonString("direct"))
    route.put("peerId", JsonString("ou_peer"))
    context.put("imRoute", route)
    media.put("context", context)
    media
}

private func withGatewayFeishuNativeTestHome<T>(label: String, root: JsonObject, block: () -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let testHome = "/tmp/metis-gateway-feishu-native-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(testHome), recursive: true) } catch (_e: Exception) { () }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        MetisConfigManager.writeRoot(root)
        CliSettingManager.applyPersistedFieldsToCliConfig()
        try {
            return block()
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            CliConfig.invalidatePathCache()
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            try { remove(Path(testHome), recursive: true) } catch (_e: Exception) { () }
        }
    }
}

private func gatewayFeishuNativeService(adapter: GatewayFeishuNativeTestAdapter, enableGroup!: Bool = true, accountId!: String = "default"): GatewayService {
    let policies = HashMap<String, ChannelPolicyConfig>()
    policies["feishu"] = ChannelPolicyConfig(enableDirect: true, enableGroup: enableGroup, requireMentionInGroup: true)
    let service = GatewayService(GatewayRouter(policies))
    service.registerAdapter(adapter, channelId: "feishu", accountId: accountId)
    service
}

@Test
public class GatewayServiceFeishuNativeTest {
    @TestCase
    public func feishuStartNativeCommandBypassesGroupGate(): Unit {
        withGatewayFeishuNativeTestHome("start", gatewayFeishuNativeTestRoot(), { =>
            let adapter = GatewayFeishuNativeTestAdapter()
            let service = gatewayFeishuNativeService(adapter, enableGroup: false)
            service.start()
            try {
                adapter.queueGroup("/feishu start")
                service.processOnce()
                @Expect(adapter.sentCount(), 1)
                @Expect(adapter.sentText(0).contains("Metis Feishu start"), true)
                @Expect(adapter.sentText(0).contains("accountId: default"), true)
            } finally {
                service.stop()
            }
        })
    }

    @TestCase
    public func feishuDoctorReportsMissingBindingsAndRedactsSecret(): Unit {
        withGatewayFeishuNativeTestHome("doctor", gatewayFeishuNativeTestRoot(appSecret: "top-secret"), { =>
            let adapter = GatewayFeishuNativeTestAdapter()
            let service = gatewayFeishuNativeService(adapter)
            service.start()
            try {
                adapter.queueDirect("/feishu doctor")
                service.processOnce()
                let reply = adapter.sentText(0)
                @Expect(adapter.sentCount(), 1)
                @Expect(reply.contains("Metis Feishu doctor"), true)
                @Expect(reply.contains("credentials: configured"), true)
                @Expect(reply.contains("bindings: missing"), true)
                @Expect(reply.contains("top-secret"), false)
            } finally {
                service.stop()
            }
        })
    }

    @TestCase
    public func feishuAuthCommandReturnsExplicitAuthorizationGuidance(): Unit {
        withGatewayFeishuNativeTestHome("auth", gatewayFeishuNativeTestRoot(), { =>
            let adapter = GatewayFeishuNativeTestAdapter()
            let service = gatewayFeishuNativeService(adapter)
            service.start()
            try {
                adapter.queueDirect("/feishu auth")
                service.processOnce()
                let reply = adapter.sentText(0)
                @Expect(adapter.sentCount(), 1)
                @Expect(reply.contains("Metis Feishu auth"), true)
                @Expect(reply.contains("OAuth/user authorization: not completed"), true)
            } finally {
                service.stop()
            }
        })
    }

    @TestCase
    public func feishuAuthCommandUsesDefaultAccountCredentialOverrides(): Unit {
        let root = gatewayFeishuNativeTestRoot(appSecret: "top-secret-never-visible")
        let gateway = root.get("gateway").getOrThrow().asObject()
        let feishu = gateway.get("feishu").getOrThrow().asObject()
        feishu.put("defaultAccount", JsonString("tenant-a"))
        feishu.put("appId", JsonString(""))
        let accounts = JsonObject()
        let tenant = JsonObject()
        tenant.put("appId", JsonString("tenant-app"))
        accounts.put("tenant-a", tenant)
        feishu.put("accounts", accounts)

        withGatewayFeishuNativeTestHome("auth-account-override", root, { =>
            let adapter = GatewayFeishuNativeTestAdapter(accountId: "tenant-a")
            let service = gatewayFeishuNativeService(adapter, accountId: "tenant-a")
            service.start()
            try {
                adapter.queueDirect("/feishu auth")
                service.processOnce()
                let reply = adapter.sentText(0)
                @Expect(adapter.sentCount(), 1)
                @Expect(reply.contains("accountId: tenant-a"), true)
                @Expect(reply.contains("app credentials: configured"), true)
                @Expect(reply.contains("authStatus: not_configured"), true)
                @Expect(reply.contains("tenant-app"), false)
                @Expect(reply.contains("top-secret-never-visible"), false)
            } finally {
                service.stop()
            }
        })
    }

    @TestCase
    public func feishuAuthCommandUsesInjectedDeviceFlowWithoutLeakingSecrets(): Unit {
        withGatewayFeishuNativeTestHome("auth-flow", gatewayFeishuNativeTestRoot(appSecret: "native-secret"), { =>
            setGatewayFeishuNativeAuthRunnerForTest(Some({ accountId: String, _user: GatewayUserSettings =>
                let out = JsonObject()
                out.put("status", JsonString("pending"))
                out.put("accountId", JsonString(accountId))
                out.put("verificationUri", JsonString("https://verify.example/activate"))
                out.put("userCode", JsonString("ABCD-EFGH"))
                out.put("expiresInSeconds", JsonString("600"))
                out.put("tokenStatus", JsonString("missing"))
                out.put("scopeSummary", JsonString("offline_access im:message"))
                out.put("accessToken", JsonString("must-not-render"))
                out
            }))
            let adapter = GatewayFeishuNativeTestAdapter()
            let service = gatewayFeishuNativeService(adapter)
            service.start()
            try {
                adapter.queueDirect("/feishu auth")
                service.processOnce()
                let reply = adapter.sentText(0)
                @Expect(adapter.sentCount(), 1)
                @Expect(reply.contains("Metis Feishu auth"), true)
                @Expect(reply.contains("OAuth/user authorization: pending"), true)
                @Expect(reply.contains("storedToken: missing"), true)
                @Expect(reply.contains("https://verify.example/activate"), true)
                @Expect(reply.contains("ABCD-EFGH"), true)
                @Expect(reply.contains("offline_access im:message"), true)
                @Expect(reply.contains("native-secret"), false)
                @Expect(reply.contains("must-not-render"), false)
            } finally {
                service.stop()
                setGatewayFeishuNativeAuthRunnerForTest(None<(String, GatewayUserSettings) -> JsonObject>)
            }
        })
    }

    @TestCase
    public func feishuAgentTeamBroadcastExecutesSelectedMembersOnly(): Unit {
        withGatewayFeishuNativeTestHome("broadcast", gatewayFeishuNativeBroadcastRoot(), { =>
            let adapter = GatewayFeishuNativeTestAdapter()
            let service = gatewayFeishuNativeService(adapter)
            let capturedAgents = ArrayList<String>()
            setGatewayAgentBridgeReplyRunnerForTest(Some({
                _sessionKey: String,
                _prompt: String,
                _channelName: String,
                agentId: String,
                _streamingEnabled: Bool,
                _streamChunkHook: Option<(String) -> Unit> =>
                    capturedAgents.add(agentId)
                    "reply:${agentId}"
            }))
            service.start()
            try {
                adapter.queueDirectWithRoute("hello team", gatewayFeishuNativeBroadcastMediaContext())
                service.processOnce()
                @Expect(adapter.sentCount(), 2)
                @Expect(capturedAgents.size, 2)
                @Expect(capturedAgents.contains("writer"), true)
                @Expect(capturedAgents.contains("reviewer"), true)
                @Expect(capturedAgents.contains("ops"), false)
                @Expect(adapter.sentText(0).contains("reply:"), true)
                @Expect(adapter.sentText(1).contains("reply:"), true)
            } finally {
                service.stop()
                setGatewayAgentBridgeReplyRunnerForTest(None<(String, String, String, String, Bool, Option<(String) -> Unit>) -> String>)
            }
        })
    }
}
