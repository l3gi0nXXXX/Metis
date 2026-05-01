package metis.gateway.core

import metis.core.config.{CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.gateway.model.{ChannelPolicyConfig, ChannelType, ChatType, InboundMessage, OutboundMessage, SendResult}

import std.collection.{ArrayList, HashMap}
import std.env.setVariable
import std.fs.{Directory, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

private class GatewayTelegramNativeTestAdapter <: ChannelAdapter {
    private let inbound = ArrayList<InboundMessage>()
    private let sent = ArrayList<OutboundMessage>()

    public prop name: String {
        get() { "telegram" }
    }

    public func start(): Unit {}

    public func stop(): Unit {}

    public func queue(text: String, sender!: String = "8734062810"): Unit {
        this.inbound.add(InboundMessage(
            ChannelType.Telegram,
            "msg-${this.inbound.size}",
            "8734062810",
            sender,
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

    public func send(message: OutboundMessage): SendResult {
        this.sent.add(message)
        SendResult.Success
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        this.sent.add(message)
        ""
    }

    public func sentText(index: Int64): String {
        match (this.sent.get(index)) {
            case Some(v) => v.text
            case None => ""
        }
    }
}

private func gatewayTelegramNativeTestConfigRoot(): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let defaults = JsonObject()
    defaults.put("workspace", JsonString(""))
    agents.put("defaults", defaults)
    root.put("agents", agents)
    root.put("gateway", JsonObject())
    root.put("session", JsonObject())
    root.put("skills", JsonObject())
    root.put("tools", JsonObject())
    root.put("models", JsonObject())
    root.put("auth", JsonObject())
    root.put("channels", JsonObject())
    root.put("plugins", JsonObject())
    root.put("wizard", JsonObject())
    root.put("meta", JsonObject())
    root
}

private func withGatewayTelegramNativeTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-telegram-native-test-home"
    try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
    Directory.create(testHome, recursive: true)
    setVariable("METIS_HOME", testHome)
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    MetisConfigManager.writeRoot(gatewayTelegramNativeTestConfigRoot())
    CliSettingManager.applyPersistedFieldsToCliConfig()
    try {
        return block()
    } finally {
        try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
    }
}

private func gatewayTelegramNativeService(adapter: GatewayTelegramNativeTestAdapter): GatewayService {
    let policies = HashMap<String, ChannelPolicyConfig>()
    policies["telegram"] = ChannelPolicyConfig(enableDirect: true, allowFrom: ["*"])
    let service = GatewayService(GatewayRouter(policies))
    service.registerAdapter(adapter, channelId: "telegram", accountId: "default")
    service
}

@Test
public class GatewayServiceTelegramNativeTest {
    @TestCase
    public func modelsCommandReturnsTelegramInlineButtonsThroughGatewayService(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["8734062810"]
            user.telegram.actions.inlineKeyboard = true
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/models")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.contains("[inline-keyboard]"), true)
            @Expect(text.contains("callback:models:set:"), true)
            @Expect(text.contains("Telegram model"), true)
        }
    }

    @TestCase
    public func modelCallbackPersistsTelegramChannelModelForAuthorizedSender(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-1\nmessageId=1\ndata=models:set:qwen:qwen3.5-plus\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Telegram model switched to qwen:qwen3.5-plus"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram") ?? "", "qwen:qwen3.5-plus")
        }
    }

    @TestCase
    public func modelCallbackRejectsUnauthorizedSenderBeforeMutation(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-2\nmessageId=1\ndata=models:set:openai:gpt-5.4\nby=123", sender: "123")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Model switch denied"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram") ?? "", "")
        }
    }
}
