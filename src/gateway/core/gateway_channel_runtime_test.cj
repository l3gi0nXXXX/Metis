package metis.gateway.core

import metis.core.config.CliConfig
import metis.gateway.model.{ChannelType, ChatType, InboundMessage, OutboundMessage, SendResult}

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*

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
}
