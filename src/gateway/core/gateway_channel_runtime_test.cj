package metis.gateway.core

import metis.core.config.CliConfig
import metis.gateway.model.{ChannelType, ChatType, InboundMessage, OutboundMessage, SendResult}

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.JsonObject

private func gatewayChannelRuntimeTestReadState(): String {
    let path = Path(gatewayChannelRuntimeStatePath())
    if (!exists(path)) {
        return ""
    }
    String.fromUtf8(File.readFrom(path))
}

private func gatewayChannelRuntimeTestWriteState(content: String): Unit {
    File.writeTo(Path(gatewayChannelRuntimeStatePath()), content.toArray())
}

private func withGatewayChannelRuntimeTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-channel-runtime-test-home"
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

private class GatewayChannelRuntimeFailingInboundAdapter <: ChannelAdapter {
    private let inbound = ArrayList<InboundMessage>()
    public var sentCount: Int64 = 0

    public prop name: String {
        get() { "telegram" }
    }

    public func start(): Unit {}

    public func stop(): Unit {}

    public func queue(text: String): Unit {
        this.inbound.add(InboundMessage(
            ChannelType.Telegram,
            "msg-${this.inbound.size}",
            "user:42",
            "42",
            ChatType.Direct,
            text,
            false,
            DateTime.now()
        ))
    }

    public func pullInbound(): Array<InboundMessage> {
        let out = this.inbound.toArray()
        this.inbound.clear()
        out
    }

    public func send(_message: OutboundMessage): SendResult {
        this.sentCount += 1
        SendResult.Success
    }

    public func sendWithMessageId(_message: OutboundMessage): String {
        this.sentCount += 1
        "msg-out"
    }
}

private class GatewayChannelLifecycleFakeAdapter <: ChannelAdapter {
    private let adapterName: String
    private let accountId: String
    private let events: ArrayList<String>
    public var startCount: Int64 = 0
    public var stopCount: Int64 = 0

    public init(adapterName: String, accountId: String, events!: ArrayList<String> = ArrayList<String>()) {
        this.adapterName = adapterName
        this.accountId = accountId
        this.events = events
    }

    public prop name: String {
        get() { this.adapterName }
    }

    public func start(): Unit {
        this.startCount += 1
        this.events.add("start:${this.accountId}")
    }

    public func stop(): Unit {
        this.stopCount += 1
        this.events.add("stop:${this.accountId}")
    }

    public func pullInbound(): Array<InboundMessage> {
        []
    }

    public func send(_message: OutboundMessage): SendResult {
        SendResult.Success
    }

    public func sendWithMessageId(_message: OutboundMessage): String {
        "fake-message"
    }
}

private func gatewayRuntimeTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayRuntimeTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

@Test
public class GatewayChannelRuntimeTest {
    @TestCase
    public func autoEnabledPrimeClearsStaleManualStop(): Unit {
        withGatewayChannelRuntimeTestHome {
            gatewayChannelRuntimeRegisterAccount("qq", accountId: "qq:test")
            gatewayChannelRuntimeMarkStopped("qq", accountId: "qq:test", reason: "manual-stop", manualStop: true)
            @Expect(gatewayChannelRuntimeCanStart("qq", accountId: "qq:test"), false)

            let primed = gatewayChannelRuntimePrimeAccount(
                "qq",
                accountId: "qq:test",
                configuredBinding: true,
                autoEnabled: true
            )
            @Expect(primed.get("manualStop").getOrThrow().asBool().getValue(), false)
            @Expect(primed.get("abortState").getOrThrow().asString().getValue(), "clear")
            @Expect(gatewayChannelRuntimeCanStart("qq", accountId: "qq:test"), true)
        }
    }

    @TestCase
    public func inboundTurnFailureDoesNotMarkChannelFailed(): Unit {
        withGatewayChannelRuntimeTestHome {
            let manager = GatewayChannelManager()
            let adapter = GatewayChannelRuntimeFailingInboundAdapter()
            manager.registerAdapter(adapter, channelId: "telegram", accountId: "telegram:default")
            manager.startChannels()
            adapter.queue("hello")

            manager.processOnce({ _message, _accountId =>
                throw Exception("delivery failed")
            })

            let accounts = gatewayChannelRuntimeAccountsJson("telegram")
            @Expect(accounts.size(), 1)
            let row = accounts[0].asObject()
            @Expect(row.get("running").getOrThrow().asBool().getValue(), true)
            @Expect(row.get("lifecycleState").getOrThrow().asString().getValue(), "running")
            @Expect(row.get("phase").getOrThrow().asString().getValue(), "active")
            @Expect(row.get("taskState").getOrThrow().asString().getValue(), "running")
            @Expect(row.get("lastError").getOrThrow().asString().getValue(), "delivery failed")

            adapter.queue("second")
            manager.processOnce({ message, _accountId =>
                let _ = adapter.send(OutboundMessage(message.channel, message.peerId, "ok"))
            })
            @Expect(adapter.sentCount, 1)
        }
    }

    @TestCase
    public func runtimeStatusRedactsSecretBearingErrors(): Unit {
        withGatewayChannelRuntimeTestHome {
            gatewayChannelRuntimeRegisterAccount("feishu", accountId: "tenant-a")
            gatewayChannelRuntimeMarkFailure(
                "feishu",
                accountId: "tenant-a",
                error: "Authorization: Bearer access-secret appSecret=app-secret refresh_token=refresh-secret"
            )

            let rendered = gatewayChannelRuntimeSummary("feishu").toJsonString()
            @Expect(rendered.contains("access-secret"), false)
            @Expect(rendered.contains("app-secret"), false)
            @Expect(rendered.contains("refresh-secret"), false)
            @Expect(rendered.contains("[redacted]"), true)
        }
    }

    @TestCase
    public func startChannelWithAccountStartsOnlyTargetAccount(): Unit {
        withGatewayChannelRuntimeTestHome {
            let manager = GatewayChannelManager()
            let telegramDefault = GatewayChannelLifecycleFakeAdapter("telegram", "default")
            let telegramWriter = GatewayChannelLifecycleFakeAdapter("telegram", "tg-writer")
            let feishuDefault = GatewayChannelLifecycleFakeAdapter("feishu", "default")
            manager.registerAdapter(telegramDefault, channelId: "telegram", accountId: "default")
            manager.registerAdapter(telegramWriter, channelId: "telegram", accountId: "tg-writer")
            manager.registerAdapter(feishuDefault, channelId: "feishu", accountId: "default")

            let result = manager.startChannel("telegram", accountId: "tg-writer")

            @Expect(gatewayRuntimeTestBool(result, "started"), true)
            @Expect(gatewayRuntimeTestString(result, "accountId"), "tg-writer")
            @Expect(telegramDefault.startCount, 0)
            @Expect(telegramWriter.startCount, 1)
            @Expect(feishuDefault.startCount, 0)
        }
    }

    @TestCase
    public func startChannelWithoutAccountStartsOnlyThatChannel(): Unit {
        withGatewayChannelRuntimeTestHome {
            let manager = GatewayChannelManager()
            let telegramDefault = GatewayChannelLifecycleFakeAdapter("telegram", "default")
            let telegramWriter = GatewayChannelLifecycleFakeAdapter("telegram", "tg-writer")
            let feishuDefault = GatewayChannelLifecycleFakeAdapter("feishu", "default")
            manager.registerAdapter(telegramDefault, channelId: "telegram", accountId: "default")
            manager.registerAdapter(telegramWriter, channelId: "telegram", accountId: "tg-writer")
            manager.registerAdapter(feishuDefault, channelId: "feishu", accountId: "default")

            let result = manager.startChannel("telegram")

            @Expect(gatewayRuntimeTestBool(result, "started"), true)
            @Expect(telegramDefault.startCount, 1)
            @Expect(telegramWriter.startCount, 1)
            @Expect(feishuDefault.startCount, 0)
        }
    }

    @TestCase
    public func startChannelCanStartAccountRegisteredAfterGlobalStart(): Unit {
        withGatewayChannelRuntimeTestHome {
            let manager = GatewayChannelManager()
            let telegramDefault = GatewayChannelLifecycleFakeAdapter("telegram", "default")
            let telegramLive = GatewayChannelLifecycleFakeAdapter("telegram", "tg-live")
            manager.registerAdapter(telegramDefault, channelId: "telegram", accountId: "default")
            manager.startChannels()
            manager.registerAdapter(telegramLive, channelId: "telegram", accountId: "tg-live")

            let result = manager.startChannel("telegram", accountId: "tg-live")

            @Expect(gatewayRuntimeTestBool(result, "started"), true)
            @Expect(telegramDefault.startCount, 1)
            @Expect(telegramLive.startCount, 1)
        }
    }

    @TestCase
    public func startChannelCanonicalizesChannelPrefixedAccountId(): Unit {
        withGatewayChannelRuntimeTestHome {
            let manager = GatewayChannelManager()
            let telegramWriter = GatewayChannelLifecycleFakeAdapter("telegram", "tg-writer")
            manager.registerAdapter(telegramWriter, channelId: "telegram", accountId: "tg-writer")

            let result = manager.startChannel("telegram", accountId: "telegram:tg-writer")
            let accounts = gatewayChannelRuntimeAccountsJson("telegram")
            let row = accounts[0].asObject()

            @Expect(gatewayRuntimeTestBool(result, "started"), true)
            @Expect(gatewayRuntimeTestString(result, "accountId"), "tg-writer")
            @Expect(gatewayRuntimeTestString(row, "accountId"), "tg-writer")
        }
    }

    @TestCase
    public func stopChannelWithAccountDoesNotStopSiblingAccounts(): Unit {
        withGatewayChannelRuntimeTestHome {
            let manager = GatewayChannelManager()
            let telegramDefault = GatewayChannelLifecycleFakeAdapter("telegram", "default")
            let telegramWriter = GatewayChannelLifecycleFakeAdapter("telegram", "tg-writer")
            manager.registerAdapter(telegramDefault, channelId: "telegram", accountId: "default")
            manager.registerAdapter(telegramWriter, channelId: "telegram", accountId: "tg-writer")
            manager.startChannel("telegram")

            let result = manager.stopChannel("telegram", accountId: "tg-writer")

            @Expect(gatewayRuntimeTestBool(result, "stopped"), true)
            @Expect(telegramDefault.stopCount, 0)
            @Expect(telegramWriter.stopCount, 1)
            @Expect(telegramDefault.startCount, 1)
        }
    }

    @TestCase
    public func restartChannelWithAccountStopsThenStartsSameAccount(): Unit {
        withGatewayChannelRuntimeTestHome {
            let events = ArrayList<String>()
            let manager = GatewayChannelManager()
            let telegramWriter = GatewayChannelLifecycleFakeAdapter("telegram", "tg-writer", events: events)
            manager.registerAdapter(telegramWriter, channelId: "telegram", accountId: "tg-writer")
            manager.startChannel("telegram", accountId: "tg-writer")
            events.clear()

            let result = manager.restartChannel("telegram", accountId: "tg-writer")

            @Expect(gatewayRuntimeTestBool(result, "restarted"), true)
            @Expect(events.size, 2)
            @Expect(events[0], "stop:tg-writer")
            @Expect(events[1], "start:tg-writer")
        }
    }

    @TestCase
    public func stopChannelMissingAccountReturnsDiagnosticWithoutTouchingSiblings(): Unit {
        withGatewayChannelRuntimeTestHome {
            let manager = GatewayChannelManager()
            let telegramDefault = GatewayChannelLifecycleFakeAdapter("telegram", "default")
            manager.registerAdapter(telegramDefault, channelId: "telegram", accountId: "default")
            manager.startChannel("telegram")

            let result = manager.stopChannel("telegram", accountId: "missing")

            @Expect(gatewayRuntimeTestBool(result, "ok"), false)
            @Expect(gatewayRuntimeTestString(result, "reason"), "account-not-registered")
            @Expect(telegramDefault.stopCount, 0)
            @Expect(telegramDefault.startCount, 1)
        }
    }
}
