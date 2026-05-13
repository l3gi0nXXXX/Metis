package metis.gateway.core

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager, MetisProcessEnvironmentLock, TelegramCustomCommandUserSettings}
import metis.core.{GatewaySpeechTtsDashScopeQwenHttpResult, gatewaySubagentCreateRunRecord, gatewaySubagentListRunRecords, gatewaySubagentRunRecordString, setGatewaySpeechTtsDashScopeQwenRunnerForTest}
import metis.gateway.model.{ChannelPolicyConfig, ChannelType, ChatType, InboundMessage, OutboundMessage, SendResult}
import metis.core.memory.memorySessionStoreForGatewayUser

import magic.core.message.Message
import magic.core.model.{AsyncChatResponse, ChatModel, ChatRequest, ChatResponse}
import magic.jsonable.*
import magic.model.ModelManager

import std.collection.{ArrayList, HashMap}
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

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

    public func queueGroup(text: String, sender!: String = "8734062810", peer!: String = "group:-100"): Unit {
        this.inbound.add(InboundMessage(
            ChannelType.Telegram,
            "group-msg-${this.inbound.size}",
            peer,
            sender,
            ChatType.Group,
            text,
            true,
            DateTime.now()
        ))
    }

    public func queueSystemEvent(text: String, kind!: String = "telegram.message_reaction"): Unit {
        this.inbound.add(InboundMessage(
            ChannelType.Telegram,
            "system-${this.inbound.size}",
            "8734062810",
            "8734062810",
            ChatType.Direct,
            text,
            false,
            DateTime.now(),
            systemEvent: true,
            systemEventKind: kind
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
        "test-message-${this.sent.size}"
    }

    public func sentText(index: Int64): String {
        match (this.sent.get(index)) {
            case Some(v) => v.text
            case None => ""
        }
    }

    public func sentReplyTo(index: Int64): String {
        match (this.sent.get(index)) {
            case Some(v) => v.replyToMessageId ?? ""
            case None => ""
        }
    }

    public func sentCount(): Int64 {
        this.sent.size
    }
}

private class GatewayTelegramSidecarMethodRecorder {
    private let methods = ArrayList<String>()

    public func add(method: String): Unit {
        this.methods.add(method)
    }

    public func count(method: String): Int64 {
        var out: Int64 = 0
        for (value in this.methods.toArray()) {
            if (value == method) {
                out += 1
            }
        }
        out
    }
}

private class GatewayTelegramNativeFakeModel <: ChatModel {
    private var _maxTokens: Option<Int64> = None

    public prop provider: String {
        get() { "fake" }
    }

    public prop name: String {
        get() { "telegram-native" }
    }

    public prop contextLength: Int64 {
        get() { 8192 }
    }

    public mut prop maxTokens: Option<Int64> {
        get() { this._maxTokens }
        set(v) { this._maxTokens = v }
    }

    public func create(_request: ChatRequest): ChatResponse {
        ChatResponse(this.fullName, Message.assistant("fake telegram native session answer"))
    }

    public func asyncCreate(_request: ChatRequest): AsyncChatResponse {
        throw Exception("async not used in telegram native tests")
    }
}

private class GatewayTelegramNativeSilentReplyFakeModel <: ChatModel {
    private var _maxTokens: Option<Int64> = None

    public prop provider: String {
        get() { "fake" }
    }

    public prop name: String {
        get() { "telegram-native-silent" }
    }

    public prop contextLength: Int64 {
        get() { 8192 }
    }

    public mut prop maxTokens: Option<Int64> {
        get() { this._maxTokens }
        set(v) { this._maxTokens = v }
    }

    public func create(_request: ChatRequest): ChatResponse {
        ChatResponse(this.fullName, Message.assistant("<SILENT_REPLY>"))
    }

    public func asyncCreate(_request: ChatRequest): AsyncChatResponse {
        throw Exception("async not used in telegram native tests")
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
    synchronized(MetisProcessEnvironmentLock) {
        let testHome = "/tmp/metis-gateway-telegram-native-test-home"
        try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
        Directory.create(testHome, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", testHome)
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        MetisConfigManager.writeRoot(gatewayTelegramNativeTestConfigRoot())
        CliSettingManager.applyPersistedFieldsToCliConfig()
        try {
            return block()
        } finally {
            setGatewayOpenClawPluginSidecarRunnerForTest(None)
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            CliConfig.invalidatePathCache()
            try { remove(Path(testHome), recursive: true) } catch (_: Exception) { () }
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
        }
    }
}

private func gatewayTelegramNativeService(adapter: GatewayTelegramNativeTestAdapter): GatewayService {
    let policies = HashMap<String, ChannelPolicyConfig>()
    policies["telegram"] = ChannelPolicyConfig(enableDirect: true, allowFrom: ["*"])
    let service = GatewayService(GatewayRouter(policies))
    service.registerAdapter(adapter, channelId: "telegram", accountId: "default")
    service
}

private func gatewayTelegramNativeDashScopeQwenTtsProviders(): JsonObject {
    let providers = JsonObject()
    let provider = JsonObject()
    provider.put("kind", JsonString("dashscope-qwen-tts"))
    provider.put("baseUrl", JsonString("https://dashscope.aliyuncs.com/api/v1"))
    provider.put("apiKey", JsonString("test-dashscope-key"))
    provider.put("model", JsonString("qwen3-tts-flash"))
    provider.put("voice", JsonString("Chelsie"))
    provider.put("languageType", JsonString("Chinese"))
    provider.put("timeoutMs", JsonInt(1000))
    providers.put("dashscope", provider)
    providers
}

private func gatewayTelegramNativeCreateCustomSubagentFixture(id: String, background: Bool): Unit {
    let agentDir = CliConfig.dotDir.join("agents").join(id)
    Directory.create(agentDir, recursive: true)
    File.writeTo(
        agentDir.join("AGENT.md"),
        (
            "id: ${id}\n" +
            "name: ${id}\n" +
            "description: Telegram native custom subagent fixture\n" +
            "model: openai/gpt-test\n" +
            "tools: fileRead,grepSearch\n" +
            "background: ${background}\n" +
            "isolation: shared\n" +
            "maxTurns: 7\n" +
            "---\n" +
            "# Fixture Instructions\n" +
            "Always answer as the telegram native fixture.\n"
        ).toArray()
    )
    CliConfig.invalidatePathCache()
}

@Test
public class GatewayServiceTelegramNativeTest {
    @TestCase
    public func telegramReactionSystemEventBypassesModelAndWritesTranscript(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["8734062810"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queueSystemEvent("[telegram-reaction]\nmessageId=101\nemoji=👍\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentCount(), 0)
            let store = gatewaySessionStoreForUser(user)
            let transcript = store.formatHistoryAsText("telegram:direct:8734062810", 10)
            @Expect(transcript.contains("[system] [telegram-reaction]"), true)
            @Expect(transcript.contains("emoji=👍"), true)
        }
    }

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
            @Expect(text.contains("callback:models:list:"), true)
            @Expect(text.contains("Telegram models"), true)
            @Expect(text.contains("Current:"), true)
        }
    }

    @TestCase
    public func modelsHelpAndStatusRenderTelegramTextInsteadOfUnknownProvider(): Unit {
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
            adapter.queue("/models help")
            adapter.queue("/models status")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Usage: /models [status|help|<provider>|<page>]"), true)
            @Expect(adapter.sentText(0).contains("  /models status"), true)
            @Expect(adapter.sentText(0).contains("  /models help"), true)
            @Expect(adapter.sentText(0).contains("  /models <provider>"), true)
            @Expect(adapter.sentText(0).contains("  /model <provider/model>"), true)
            @Expect(adapter.sentText(0).contains("Unknown provider"), false)
            @Expect(adapter.sentText(0).startsWith("{"), false)
            @Expect(adapter.sentText(1).contains("Telegram models status"), true)
            @Expect(adapter.sentText(1).contains("Current:"), true)
            @Expect(adapter.sentText(1).contains("Unknown provider"), false)
            @Expect(adapter.sentText(1).startsWith("{"), false)
        }
    }

    @TestCase
    public func modelsPageCallbackReturnsModelPageWithoutMutatingConfig(): Unit {
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
            adapter.queue("[telegram-callback]\nid=cb-page\nmessageId=1\ndata=models:page:1\nby=8734062810")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.contains("[inline-keyboard]"), true)
            @Expect(text.contains("callback:models:list:"), true)
            @Expect(text.contains("Telegram models"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram") ?? "", "")
        }
    }

    @TestCase
    public func modelsProviderCommandShowsEightPerPageWithBackAndSetidxCallbacks(): Unit {
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
            adapter.queue("/models qwen")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.contains("Models (qwen)"), true)
            @Expect(text.contains("available"), true)
            @Expect(text.contains("callback:models:setidx:qwen:1:"), true)
            @Expect(text.contains("callback:models:providers"), true)
            @Expect(text.contains("button=Back"), true)
        }
    }

    @TestCase
    public func modelCallbackPersistsTelegramSessionModelForAuthorizedSender(): Unit {
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

            @Expect(adapter.sentText(0).contains("Telegram session model switched to qwen:qwen3.5-plus"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram") ?? "", "")
            @Expect(updated.channelModels.get("telegram:telegram:direct:8734062810") ?? "", "qwen:qwen3.5-plus")
        }
    }

    @TestCase
    public func modelSetidxCallbackPersistsTelegramSessionModelForAuthorizedSender(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-setidx\nmessageId=1\ndata=models:setidx:qwen:1:0\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Telegram session model switched to qwen:qwen3.5-plus"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram:telegram:direct:8734062810") ?? "", "qwen:qwen3.5-plus")
        }
    }

    @TestCase
    public func modelSlashCommandUsesSameSessionOverrideWritePath(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/model qwen/qwen3.6-plus")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Telegram session model switched to qwen:qwen3.6-plus"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram:telegram:direct:8734062810") ?? "", "qwen:qwen3.6-plus")
        }
    }

    @TestCase
    public func t44ModelCallbackHonorsTelegramConfigWritesGate(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            user.telegram.configWrites = false
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-configwrites\nmessageId=1\ndata=models:set:qwen:qwen3.5-plus\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("configWrites is disabled"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram:telegram:direct:8734062810") ?? "", "")
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

    @TestCase
    public func unknownTelegramCallbackIsHandledNativelyWithoutModelPath(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-unknown\nmessageId=1\nactionType=unknown\ndata=unknown:action\nby=8734062810")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.contains("\"action\":\"telegram_callback\""), true)
            @Expect(text.contains("\"reason\":\"unknown callback action\""), true)
        }
    }

    @TestCase
    public func pluginTelegramCallbackReportsNativeNotApplicable(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-plugin\nmessageId=1\nactionType=plugin-not-applicable\ndata=plugin:demo:run\nby=8734062810")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.contains("\"status\":\"not_applicable\""), true)
            @Expect(text.contains("OpenClaw plugin compatibility sidecar is disabled"), true)
        }
    }

    @TestCase
    public func pluginTelegramCallbackDispatchesThroughOpenClawSidecarBridge(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)
            let recorder = GatewayTelegramSidecarMethodRecorder()
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
                recorder.add(method)
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                out.put("matched", (method == "interactive.dispatch").toJsonValue())
                if (method == "interactive.dispatch") {
                    @Expect(payload.get("data").getOrThrow().asString().getValue(), "plugin:demo:run")
                    @Expect(payload.get("callbackId").getOrThrow().asString().getValue(), "cb-plugin")
                    @Expect(payload.get("callbackMessage").getOrThrow().asObject().get("messageId").getOrThrow().asString().getValue(), "77")
                    @Expect(payload.get("auth").getOrThrow().asObject().get("isAuthorizedSender").getOrThrow().asBool().getValue(), true)
                    @Expect(payload.get("isForum").getOrThrow().asBool().getValue(), false)
                    let intents = JsonArray([])
                    let reply = JsonObject()
                    reply.put("type", JsonString("reply"))
                    reply.put("text", JsonString("plugin handled"))
                    intents.add(reply)
                    out.put("intents", intents)
                }
                if (method == "hook.message_sending") {
                    out.put("cancelled", false.toJsonValue())
                    out.put("text", payload.get("text").getOrThrow())
                }
                out
            }))

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-plugin\nmessageId=77\nactionType=plugin-not-applicable\ndata=plugin:demo:run\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0), "plugin handled")
        }
    }

    @TestCase
    public func pluginCallbackWithEnabledSidecarAndNoHandlerReportsNotFound(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, _payload: JsonObject =>
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                out.put("matched", false.toJsonValue())
                if (method == "interactive.dispatch") {
                    out.put("reason", JsonString("handler_not_found"))
                }
                out
            }))

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-missing\nmessageId=77\nactionType=plugin-not-applicable\ndata=plugin:missing:run\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("\"status\":\"not_found\""), true)
            @Expect(adapter.sentText(0).contains("handler_not_found"), true)
        }
    }

    @TestCase
    public func duplicatePluginTelegramCallbackDoesNotRunSidecarTwice(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)
            let recorder = GatewayTelegramSidecarMethodRecorder()
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
                recorder.add(method)
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                out.put("matched", (method == "interactive.dispatch").toJsonValue())
                if (method == "interactive.dispatch") {
                    let intents = JsonArray([])
                    let reply = JsonObject()
                    reply.put("type", JsonString("reply"))
                    reply.put("text", JsonString("plugin handled"))
                    intents.add(reply)
                    out.put("intents", intents)
                }
                if (method == "hook.message_sending") {
                    out.put("cancelled", false.toJsonValue())
                    out.put("text", payload.get("text").getOrThrow())
                }
                out
            }))

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-dup\nmessageId=77\nactionType=plugin-not-applicable\ndata=plugin:demo:run\nby=8734062810")
            adapter.queue("[telegram-callback]\nid=cb-dup\nmessageId=77\nactionType=plugin-not-applicable\ndata=plugin:demo:run\nby=8734062810")
            service.processOnce()

            @Expect(recorder.count("interactive.dispatch"), 1)
            @Expect(adapter.sentText(0), "plugin handled")
            @Expect(adapter.sentText(1).contains("duplicate callback ignored"), true)
        }
    }

    @TestCase
    public func pluginApprovalCallbackDispatchesThroughOpenClawSidecarBridge(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                out.put("matched", (method == "approval.dispatch").toJsonValue())
                if (method == "approval.dispatch") {
                    @Expect(payload.get("data").getOrThrow().asString().getValue(), "plugin-approval:demo:allow:approval-1")
                    let intents = JsonArray([])
                    let reply = JsonObject()
                    reply.put("type", JsonString("reply"))
                    reply.put("text", JsonString("approval handled"))
                    intents.add(reply)
                    out.put("intents", intents)
                }
                if (method == "hook.message_sending") {
                    out.put("cancelled", false.toJsonValue())
                    out.put("text", payload.get("text").getOrThrow())
                }
                if (method == "hook.message_sent") {
                    out.put("status", JsonString("ok"))
                }
                out
            }))

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-approval\nmessageId=77\nactionType=plugin-approval\ndata=plugin-approval:demo:allow:approval-1\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0), "approval handled")
        }
    }

    @TestCase
    public func pluginCommandDispatchAndOutboundHookStayInsideGatewayService(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)
            let recorder = GatewayTelegramSidecarMethodRecorder()
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
                recorder.add(method)
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                if (method == "commands.list") {
                    let commands = JsonArray([])
                    let row = JsonObject()
                    row.put("command", JsonString("plugin_demo"))
                    row.put("description", JsonString("Plugin demo command"))
                    commands.add(row)
                    out.put("commands", commands)
                } else if (method == "command.dispatch") {
                    @Expect(payload.get("commandBody").getOrThrow().asString().getValue(), "/plugin_demo now")
                    @Expect(payload.get("args").getOrThrow().asString().getValue(), "now")
                    @Expect(payload.get("sessionKey").getOrThrow().asString().getValue(), "telegram:direct:8734062810")
                    @Expect(payload.get("from").getOrThrow().asString().getValue(), "8734062810")
                    @Expect(payload.get("to").getOrThrow().asString().getValue(), "8734062810")
                    @Expect(payload.get("accountId").getOrThrow().asString().getValue(), "default")
                    @Expect(payload.get("messageThreadId").getOrThrow().asString().getValue(), "")
                    @Expect(payload.get("isAuthorizedSender").getOrThrow().asBool().getValue(), true)
                    out.put("matched", true.toJsonValue())
                    let intents = JsonArray([])
                    let reply = JsonObject()
                    reply.put("type", JsonString("reply"))
                    reply.put("text", JsonString("command handled"))
                    intents.add(reply)
                    out.put("intents", intents)
                } else if (method == "hook.message_sending") {
                    out.put("cancelled", false.toJsonValue())
                    let text = payload.get("text").getOrThrow().asString().getValue()
                    out.put("text", JsonString(if (text.startsWith("[")) { text } else { "hooked:${text}" }))
                } else if (method == "hook.message_sent") {
                    @Expect(payload.get("sentMessageId").getOrThrow().asString().getValue().startsWith("test-message-"), true)
                    out.put("status", JsonString("ok"))
                } else {
                    out.put("matched", false.toJsonValue())
                }
                out
            }))

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/plugin_demo now")
            service.processOnce()

            @Expect(adapter.sentText(0), "hooked:Running /plugin_demo...")
            @Expect(adapter.sentText(1), "[edit]\ncommand handled")
            @Expect(adapter.sentReplyTo(1), "test-message-1")
            @Expect(recorder.count("hook.message_sending"), 2)
            @Expect(recorder.count("hook.message_sent"), 2)
        }
    }

    @TestCase
    public func pluginCallbackIntentCanEditClearButtonsAndDeleteViaTelegramPayloads(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                out.put("matched", (method == "interactive.dispatch").toJsonValue())
                if (method == "interactive.dispatch") {
                    let intents = JsonArray([])
                    for ((kind, text) in [("answer-callback-query", "ack"), ("edit", "edited"), ("edit-buttons", ""), ("clear-buttons", ""), ("delete", "")]) {
                        let intent = JsonObject()
                        intent.put("type", JsonString(kind))
                        if (!text.isEmpty()) {
                            intent.put("text", JsonString(text))
                        }
                        if (kind == "edit-buttons") {
                            let rows = JsonArray([])
                            let row = JsonArray([])
                            let button = JsonObject()
                            button.put("text", JsonString("OK"))
                            button.put("callback_data", JsonString("plugin:demo:ok"))
                            row.add(button)
                            rows.add(row)
                            intent.put("buttons", rows)
                        }
                        intents.add(intent)
                    }
                    out.put("intents", intents)
                }
                if (method == "hook.message_sending") {
                    out.put("cancelled", false.toJsonValue())
                    out.put("text", payload.get("text").getOrThrow())
                }
                out
            }))

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("[telegram-callback]\nid=cb-intents\nmessageId=77\nactionType=plugin-not-applicable\ndata=plugin:demo:run\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0), "[edit]\nedited")
            @Expect(adapter.sentText(1).contains("[edit-buttons]"), true)
            @Expect(adapter.sentText(1).contains("button=OK|callback:plugin:demo:ok"), true)
            @Expect(adapter.sentText(2), "[clear-buttons]")
            @Expect(adapter.sentText(3), "[delete]")
            @Expect(adapter.sentCount(), 4)
        }
    }

    @TestCase
    public func pluginUnsupportedCapabilityDispatchReturnsStructuredTelegramError(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, _payload: JsonObject =>
                let out = JsonObject()
                if (method == "commands.list") {
                    out.put("ok", true.toJsonValue())
                    let commands = JsonArray([])
                    let row = JsonObject()
                    row.put("command", JsonString("plugin_tool"))
                    row.put("description", JsonString("Unsupported tool command"))
                    commands.add(row)
                    out.put("commands", commands)
                } else if (method == "command.dispatch") {
                    out.put("ok", false.toJsonValue())
                    out.put("matched", true.toJsonValue())
                    out.put("status", JsonString("unsupported"))
                    out.put("reason", JsonString("not implemented by the Metis OpenClaw plugin compatibility sidecar"))
                    let unsupported = JsonObject()
                    unsupported.put("capability", JsonString("api.registerTool"))
                    unsupported.put("runtime", JsonString("metis-openclaw-plugin-compat-sidecar"))
                    unsupported.put("reason", JsonString("not implemented by the Metis OpenClaw plugin compatibility sidecar"))
                    unsupported.put("pluginId", JsonString("fixture"))
                    out.put("unsupportedCapability", unsupported)
                } else if (method == "hook.message_sending") {
                    out.put("ok", true.toJsonValue())
                    out.put("cancelled", false.toJsonValue())
                    out.put("text", _payload.get("text").getOrThrow())
                } else {
                    out.put("ok", true.toJsonValue())
                }
                out
            }))

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/plugin_tool")
            service.processOnce()

            let text = adapter.sentText(1)
            @Expect(text.contains("\"status\":\"unsupported\""), true)
            @Expect(text.contains("\"unsupportedCapability\""), true)
            @Expect(text.contains("api.registerTool"), true)
            @Expect(text.contains("compatibility sidecar"), true)
        }
    }

    @TestCase
    public func t51InteractiveCallbackImperativeCtxRespondAndBindingHelpersWorkThroughGateway(): Unit {
        withGatewayTelegramNativeTestHome {
            let root = Path("/tmp/metis-t51-openclaw-plugin-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
            let pluginRoot = root.join("demo-plugin")
            Directory.create(pluginRoot, recursive: true)
            setGatewayTelegramThreadBindingRootForTest(Some(root.join("bindings")))
            File.writeTo(
                pluginRoot.join("package.json"),
                "{\"name\":\"demo-openclaw-plugin\",\"type\":\"module\",\"main\":\"index.mjs\"}".toArray()
            )
            File.writeTo(
                pluginRoot.join("index.mjs"),
                (
                    "export default function(api) {\n" +
                    "  api.interactive.register({ namespace: 'demo', channel: 'telegram' }, async (ctx) => {\n" +
                    "    if (ctx.callback.payload === 'detach') {\n" +
                    "      await ctx.detachConversationBinding();\n" +
                    "      return;\n" +
                    "    }\n" +
                    "    const current = await ctx.getCurrentConversationBinding();\n" +
                    "    await ctx.respond.reply({ text: 'reply:' + current.sessionKey, buttons: [[{ text: 'OK', callback_data: 'plugin:demo:ok' }]] });\n" +
                    "    await ctx.respond.editMessage({ text: 'edited' });\n" +
                    "    await ctx.respond.editButtons({ buttons: [[{ text: 'Next', callback_data: 'plugin:demo:next' }]] });\n" +
                    "    await ctx.respond.clearButtons();\n" +
                    "    await ctx.respond.deleteMessage();\n" +
                    "    await ctx.requestConversationBinding({ sessionKey: 'agent:main:explicit:demo' });\n" +
                    "  });\n" +
                    "}\n"
                ).toArray()
            )

            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.allowFrom = ["*"]
                user.telegram.actions.callbackQuery = true
                user.telegram.threadBindings.enabled = true
                let plugins = JsonArray([])
                plugins.add(JsonString(pluginRoot.toString()))
                let compat = JsonObject()
                compat.put("enabled", true.toJsonValue())
                compat.put("scriptPath", JsonString(CliConfig.cwd.join("scripts").join("openclaw-plugin-sidecar.mjs").toString()))
                compat.put("plugins", plugins)
                let extra = JsonObject()
                extra.put("openclawPluginCompatibility", compat)
                user.channelsExtra = Some(extra)
                CliSettingManager.writeGatewaySettings(user)

                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("[telegram-callback]\nid=cb-imperative\nmessageId=77\nactionType=plugin-not-applicable\ndata=plugin:demo:run\nby=8734062810")
                service.processOnce()

                @Expect(adapter.sentText(0).contains("[inline-keyboard]"), true)
                @Expect(adapter.sentText(0).contains("reply:telegram:direct:8734062810"), true)
                @Expect(adapter.sentText(1), "[edit]\nedited")
                @Expect(adapter.sentReplyTo(1), "77")
                @Expect(adapter.sentText(2).contains("[edit-buttons]"), true)
                @Expect(adapter.sentText(2).contains("button=Next|callback:plugin:demo:next"), true)
                @Expect(adapter.sentText(3), "[clear-buttons]")
                @Expect(adapter.sentText(4), "[delete]")
                let binding = gatewayTelegramThreadBindingResolve("telegram", "default", "8734062810")
                @Expect(binding.get("sessionKey").getOrThrow().asString().getValue(), "agent:main:explicit:demo")

                adapter.queue("[telegram-callback]\nid=cb-detach\nmessageId=77\nactionType=plugin-not-applicable\ndata=plugin:demo:detach\nby=8734062810")
                service.processOnce()
                @Expect(gatewayTelegramThreadBindingResolve("telegram", "default", "8734062810").size(), 0)
            } finally {
                setGatewayTelegramThreadBindingRootForTest(None)
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
            }
        }
    }

    @TestCase
    public func t51PluginHookPayloadsExposeReceivedMediaAndCanCancelSending(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)
            let recorder = GatewayTelegramSidecarMethodRecorder()
            setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
                recorder.add(method)
                let out = JsonObject()
                out.put("ok", true.toJsonValue())
                if (method == "hook.message_received") {
                    @Expect(payload.get("accountId").getOrThrow().asString().getValue(), "default")
                    @Expect(payload.get("from").getOrThrow().asString().getValue(), "8734062810")
                    @Expect(payload.get("content").getOrThrow().asString().getValue(), "photo caption")
                    @Expect(payload.get("conversationId").getOrThrow().asString().getValue(), "group:-100:topic:42")
                    @Expect(payload.get("threadId").getOrThrow().asString().getValue(), "42")
                    @Expect(payload.get("mediaSummary").getOrThrow().asObject().get("count").getOrThrow().asInt().getValue(), 1)
                    @Expect(payload.get("metadata").getOrThrow().asObject().get("senderId").getOrThrow().asString().getValue(), "8734062810")
                    @Expect(payload.get("mediaSummary").getOrThrow().asObject().get("kinds").getOrThrow().asArray()[0].asString().getValue(), "photo")
                } else if (method == "hook.message_sending") {
                    @Expect(payload.get("to").getOrThrow().asString().getValue(), "group:-100:topic:42")
                    @Expect(payload.get("content").getOrThrow().asString().getValue(), "cancel me")
                    @Expect(payload.get("conversationId").getOrThrow().asString().getValue(), "group:-100:topic:42")
                    @Expect(payload.get("threadId").getOrThrow().asString().getValue(), "42")
                    @Expect(payload.get("reply").getOrThrow().asObject().get("messageId").getOrThrow().asString().getValue(), "77")
                    out.put("cancelled", true.toJsonValue())
                    out.put("reason", JsonString("blocked by fixture"))
                } else if (method == "hook.message_sent") {
                    @Expect(payload.get("success").getOrThrow().asBool().getValue(), false)
                    @Expect(payload.get("error").getOrThrow().asString().getValue(), "blocked by fixture")
                    @Expect(payload.get("delivered").getOrThrow().asBool().getValue(), false)
                    @Expect(payload.get("reason").getOrThrow().asString().getValue(), "blocked by fixture")
                    @Expect(payload.get("messageIds").getOrThrow().asArray().size(), 0)
                }
                out
            }))

            let media = JsonObject()
            let records = JsonArray([])
            let record = JsonObject()
            record.put("mediaKind", JsonString("photo"))
            records.add(record)
            media.put("records", records)
            let _ = gatewayOpenClawPluginSidecarApplyMessageReceivedHook(
                user,
                "telegram",
                "default",
                "group:-100:topic:42",
                "8734062810",
                "msg-media",
                "photo caption",
                true,
                "",
                "{}",
                conversationId: "group:-100:topic:42",
                threadId: "42",
                mediaContext: media
            )

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            let sentId = service.sendTextToPeerDetailed(
                "telegram",
                "group:-100:topic:42",
                "cancel me",
                replyToMessageId: Some("77"),
                replyInThread: true,
                accountId: "default"
            )
            @Expect(sentId, "")
            @Expect(adapter.sentCount(), 0)
            @Expect(recorder.count("hook.message_received"), 1)
            @Expect(recorder.count("hook.message_sending"), 1)
            @Expect(recorder.count("hook.message_sent"), 1)
        }
    }

    @TestCase
    public func t44OpenClawPluginSidecarLoadsLocalPluginAndDispatchesRuntimeFacets(): Unit {
        withGatewayTelegramNativeTestHome {
            let root = Path("/tmp/metis-openclaw-plugin-sidecar-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
            let pluginRoot = root.join("demo-plugin")
            Directory.create(pluginRoot, recursive: true)
            File.writeTo(
                pluginRoot.join("package.json"),
                "{\"name\":\"demo-openclaw-plugin\",\"type\":\"module\",\"main\":\"index.mjs\"}".toArray()
            )
            File.writeTo(
                pluginRoot.join("index.mjs"),
                (
                    "export default function(api) {\n" +
                    "  api.registerCommand({ name: 'demo', description: 'Demo command', handler: async (ctx) => ({ text: 'command ok ' + ctx.args + ' ' + ctx.isAuthorizedSender }) });\n" +
                    "  api.interactive.register({ namespace: 'demo', channel: 'telegram' }, async () => ({ intents: [{ type: 'reply', text: 'interactive ok', buttons: [[{ text: 'OK', callback_data: 'plugin:demo:ok' }]] }] }));\n" +
                    "  api.approvals.register({ namespace: 'demo', channel: 'telegram' }, async (ctx) => ({ type: 'reply', text: 'approval ' + ctx.decision }));\n" +
                    "  api.registerHook('message_sending', async (event, ctx) => ({ content: '[hooked] ' + event.content + ' ' + ctx.accountId }));\n" +
                    "  api.registerHook('message_received', async (event, ctx) => { globalThis.__metis_received = event.metadata.messageId + ':' + ctx.accountId; });\n" +
                    "  api.registerTool({ name: 'unsupported_tool' });\n" +
                    "}\n"
                ).toArray()
            )

            try {
                var user = GatewayUserSettings()
                let plugins = JsonArray([])
                plugins.add(JsonString(pluginRoot.toString()))
                let compat = JsonObject()
                compat.put("enabled", true.toJsonValue())
                compat.put("scriptPath", JsonString(CliConfig.cwd.join("scripts").join("openclaw-plugin-sidecar.mjs").toString()))
                compat.put("plugins", plugins)
                let extra = JsonObject()
                extra.put("openclawPluginCompatibility", compat)
                user.channelsExtra = Some(extra)

                let health = gatewayOpenClawPluginSidecarInvoke(user, "lifecycle.health", JsonObject())
                @Expect(health.get("ok").getOrThrow().asBool().getValue(), true)
                @Expect(health.get("pluginCount").getOrThrow().asInt().getValue(), 1)

                let commands = gatewayOpenClawPluginSidecarInvoke(user, "commands.list", JsonObject())
                let commandRows = commands.get("commands").getOrThrow().asArray()
                @Expect(commandRows.size(), 1)
                @Expect(commandRows[0].asObject().get("command").getOrThrow().asString().getValue(), "demo")
                @Expect(commands.get("diagnostics").getOrThrow().asArray()[0].asObject().get("unsupportedCapability").getOrThrow().asObject().get("capability").getOrThrow().asString().getValue(), "api.registerTool")

                let commandPayload = JsonObject()
                commandPayload.put("command", JsonString("demo"))
                commandPayload.put("args", JsonString("now"))
                commandPayload.put("commandBody", JsonString("/demo now"))
                commandPayload.put("channel", JsonString("telegram"))
                commandPayload.put("accountId", JsonString("default"))
                commandPayload.put("isAuthorizedSender", true.toJsonValue())
                let command = gatewayOpenClawPluginSidecarInvoke(user, "command.dispatch", commandPayload)
                @Expect(command.get("matched").getOrThrow().asBool().getValue(), true)
                @Expect(command.get("intents").getOrThrow().asArray()[0].asObject().get("text").getOrThrow().asString().getValue(), "command ok now true")

                let callbackPayload = JsonObject()
                callbackPayload.put("data", JsonString("plugin:demo:ok"))
                let callback = gatewayOpenClawPluginSidecarInvoke(user, "interactive.dispatch", callbackPayload)
                @Expect(callback.get("matched").getOrThrow().asBool().getValue(), true)
                let callbackIntent = callback.get("intents").getOrThrow().asArray()[0].asObject()
                @Expect(callbackIntent.get("text").getOrThrow().asString().getValue(), "interactive ok")
                @Expect(callbackIntent.get("buttons").getOrThrow().asArray().size(), 1)

                let approvalPayload = JsonObject()
                approvalPayload.put("data", JsonString("plugin-approval:demo:allow"))
                let approval = gatewayOpenClawPluginSidecarInvoke(user, "approval.dispatch", approvalPayload)
                @Expect(approval.get("matched").getOrThrow().asBool().getValue(), true)
                @Expect(approval.get("intents").getOrThrow().asArray()[0].asObject().get("text").getOrThrow().asString().getValue(), "approval allow")

                let hookPayload = JsonObject()
                hookPayload.put("channel", JsonString("telegram"))
                hookPayload.put("accountId", JsonString("default"))
                hookPayload.put("text", JsonString("hello"))
                hookPayload.put("content", JsonString("hello"))
                let hook = gatewayOpenClawPluginSidecarInvoke(user, "hook.message_sending", hookPayload)
                @Expect(hook.get("text").getOrThrow().asString().getValue(), "[hooked] hello default")

                let receivedPayload = JsonObject()
                receivedPayload.put("channel", JsonString("telegram"))
                receivedPayload.put("messageId", JsonString("msg-1"))
                let received = gatewayOpenClawPluginSidecarInvoke(user, "hook.message_received", receivedPayload)
                @Expect(received.get("status").getOrThrow().asString().getValue(), "ok")
            } finally {
                try { remove(root, recursive: true) } catch (_e: Exception) { () }
            }
        }
    }

    @TestCase
    public func telegramNativeCommandsBypassModelForHelpSubagentsSessionsAndApprovals(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/help")
            adapter.queue("/subagents help")
            adapter.queue("/sessions list")
            adapter.queue("/approvals")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Metis Telegram commands"), true)
            @Expect(adapter.sentText(0).startsWith("{"), false)
            @Expect(adapter.sentText(1).contains("Subagents commands"), true)
            @Expect(adapter.sentText(1).contains("/subagents spawn"), true)
            @Expect(adapter.sentText(2).contains("Gateway sessions"), true)
            @Expect(adapter.sentText(3).contains("Pending approvals"), true)
            @Expect(adapter.sentText(3).startsWith("{"), false)
        }
    }

    @TestCase
    public func telegramNativeSubagentsListRendersHumanText(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/subagents list active")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.startsWith("{"), false)
            @Expect(text.contains("Subagents: list"), true)
        }
    }

    @TestCase
    public func telegramNativeSubagentsSpawnAcceptedJsonRendersHumanText(): Unit {
        withGatewayTelegramNativeTestHome {
            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            let text = service.renderTelegramNativeHumanReplyForTest("{\"ok\":true,\"status\":\"accepted\",\"runId\":\"subrun_1778383455269_gateway_spawn_subagent-explorer_\",\"sessionKey\":\"gateway:spawn:subagent-explorer:1778383455269\",\"runtime\":\"subagent\",\"agentId\":\"explorer\",\"task\":\"“以沁园春为词牌，写一首词”\",\"liveRunStarted\":true}")
            @Expect(text.startsWith("{"), false)
            @Expect(text.contains("Subagents: spawn (accepted)"), true)
            @Expect(text.contains("runId="), true)
            @Expect(text.contains("agent=explorer"), true)
            @Expect(text.contains("task=“以沁园春为词牌，写一首词”"), true)
        }
    }

    @TestCase
    public func telegramNativeSubagentsSpawnPersistsTelegramRequesterForCompletionNotice(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.subagents.allowCustomAgents = true
            CliSettingManager.writeGatewaySettings(user)
            gatewayTelegramNativeCreateCustomSubagentFixture("phase-native-telegram", false)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/subagents spawn phase-native-telegram \"inspect unicode 任务\"")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.startsWith("{"), false)
            @Expect(text.contains("Subagents: spawn (accepted)"), true)
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let records = gatewaySubagentListRunRecords(store.sessionsRoot())
            @Expect(records.size, 1)
            let record = records[0]
            @Expect(gatewaySubagentRunRecordString(record, "requesterSessionKey"), "telegram:direct:8734062810")
            @Expect(gatewaySubagentRunRecordString(record, "requesterChannel"), "telegram")
            @Expect(gatewaySubagentRunRecordString(record, "requesterAccountId"), "default")
            @Expect(gatewaySubagentRunRecordString(record, "requesterPeerId"), "8734062810")
            @Expect(gatewaySubagentRunRecordString(record, "requesterConversationId"), "8734062810")
        }
    }

    @TestCase
    public func telegramNativeSubagentsInvalidActionRendersSubagentsText(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/subagents 以沁园春为词牌写一首词，主题是关于vibe coding。")
            service.processOnce()

            let text = adapter.sentText(0)
            @Expect(text.startsWith("{"), false)
            @Expect(text.contains("Telegram command:"), false)
            @Expect(text.contains("Subagents:"), true)
            @Expect(text.contains("unknown subagents action"), true)
        }
    }

    @TestCase
    public func telegramNativeHelpWithSupplementalEntityContextStillRendersText(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/help@metis_fake_bot\n[entities]\n- bot_command: /help@metis_fake_bot")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Metis Telegram commands"), true)
            @Expect(adapter.sentText(0).startsWith("{"), false)
            @Expect(adapter.sentText(0).contains("\"commands\""), false)
        }
    }

    @TestCase
    public func telegramNativeCommandsRenderHumanReadableStatusAndCatalogMeanings(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/commands")
            adapter.queue("/status")
            adapter.queue("/acp")
            adapter.queue("/session idle")
            adapter.queue("/compact summarize older turns")
            adapter.queue("/btw quick side question")
            adapter.queue("/whoami")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Metis Telegram command catalog"), true)
            @Expect(adapter.sentText(0).contains("/acp [not_applicable"), true)
            @Expect(adapter.sentText(0).startsWith("{"), false)
            @Expect(adapter.sentText(1).contains("Telegram status"), true)
            @Expect(adapter.sentText(1).contains("Scope: current Telegram Gateway session usage"), true)
            @Expect(adapter.sentText(1).contains("Token Status"), true)
            @Expect(adapter.sentText(1).contains("Session:"), true)
            @Expect(adapter.sentText(1).contains("local CLI process token manager"), false)
            @Expect(adapter.sentText(1).startsWith("{"), false)
            @Expect(adapter.sentText(2).contains("Not applicable: /acp"), true)
            @Expect(adapter.sentText(2).contains("OpenClaw"), false)
            @Expect(adapter.sentText(3).contains("Not applicable: /session"), true)
            @Expect(adapter.sentText(4).contains("Not applicable: /compact"), true)
            @Expect(adapter.sentText(5).contains("Not applicable: /btw"), true)
            @Expect(adapter.sentText(6).contains("Telegram identity"), true)
            @Expect(adapter.sentText(6).contains("Sender: 8734062810"), true)
            @Expect(adapter.sentText(6).contains("Session: telegram:direct:"), true)
            @Expect(adapter.sentText(6).startsWith("{"), false)
        }
    }

    @TestCase
    public func telegramNativeCatalogCommandsDoNotReturnRawJsonByDefault(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.configWrites = false
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()

            let catalog = gatewayTelegramNativeCommandCatalog()
            for (entry in catalog) {
                adapter.queue(this.safeTelegramNativeCommandInput(entry.command))
            }
            service.processOnce()

            @Expect(adapter.sentCount(), Int64(catalog.size))
            for (i in 0..catalog.size) {
                let reply = adapter.sentText(i)
                @Expect(reply.trimAscii().isEmpty(), false)
                @Expect(reply.trimAscii().startsWith("{"), false)
            }
        }
    }

    @TestCase
    public func telegramToolsCommandRendersHumanReadableToolSummary(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/tools")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Telegram tools"), true)
            @Expect(adapter.sentText(0).contains("gateway_sessions"), true)
            @Expect(adapter.sentText(0).contains("telegram_media"), true)
            @Expect(adapter.sentText(0).contains("subagents"), true)
            @Expect(adapter.sentText(0).contains("OpenClaw plugin sidecar:"), true)
            @Expect(adapter.sentText(0).startsWith("{"), false)
        }
    }

    private func safeTelegramNativeCommandInput(command: String): String {
        match (command) {
            case "allowlist" => "/allowlist list"
            case "approve" => "/approve"
            case "btw" => "/btw test side question"
            case "export-session" => "/export-session catalog-smoke.html"
            case "kill" => "/kill missing-run"
            case "steer" => "/steer missing-run continue"
            case "config" => "/config show"
            case "mcp" => "/mcp show"
            case "plugins" => "/plugins list"
            case "debug" => "/debug show"
            case "usage" => "/usage status"
            case "restart" => "/restart"
            case "send" => "/send status"
            case "think" => "/think status"
            case "verbose" => "/verbose status"
            case "fast" => "/fast status"
            case "reasoning" => "/reasoning status"
            case "elevated" => "/elevated status"
            case "exec" => "/exec status"
            case "queue" => "/queue status"
            case "model" => "/model"
            case "models" => "/models help"
            case "bash" => "/bash echo test"
            case "skill" => "/skill"
            case "tts" => "/tts status"
            case "subagents" => "/subagents help"
            case "sessions" => "/sessions list"
            case "compact" => "/compact"
            case _ => "/${command}"
        }
    }

    @TestCase
    public func telegramFocusUnfocusCommandsUseThreadBindingManager(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.threadBindings.enabled = true
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/focus agent:main:explicit:review")
            service.processOnce()
            @Expect(adapter.sentText(0).contains("Telegram thread binding: focus"), true)
            @Expect(adapter.sentText(0).contains("agent:main:explicit:review"), true)

            let resolved = gatewayTelegramThreadBindingResolve("telegram", "default", "8734062810")
            @Expect(resolved.get("sessionKey").getOrThrow().asString().getValue(), "agent:main:explicit:review")

            adapter.queue("/agents")
            service.processOnce()
            @Expect(adapter.sentText(1).contains("Telegram thread binding: agents"), true)
            @Expect(adapter.sentText(1).contains("agent:main:explicit:review"), true)

            adapter.queue("/unfocus")
            service.processOnce()
            @Expect(adapter.sentText(2).contains("Telegram thread binding: unfocus"), true)
            @Expect(gatewayTelegramThreadBindingResolve("telegram", "default", "8734062810").size(), 0)
        }
    }

    @TestCase
    public func t51CatalogCoversOpenClawNativeCommandNames(): Unit {
        let expected = [
            "help", "commands", "tools", "skill", "status", "tasks", "allowlist", "approve",
            "context", "btw", "export-session", "tts", "whoami", "session", "subagents",
            "acp", "focus", "unfocus", "agents", "kill", "steer", "config", "mcp",
            "plugins", "debug", "usage", "stop", "restart", "activation", "send", "reset",
            "new", "compact", "think", "verbose", "fast", "reasoning", "elevated", "exec",
            "model", "models", "queue", "bash"
        ]
        for (command in expected) {
            @Expect(gatewayFindTelegramNativeCommandSpec(command).isSome(), true)
        }
        @Expect(gatewayFindTelegramNativeCommandSpec("tell").getOrThrow().command, "steer")
        @Expect(gatewayFindTelegramNativeCommandSpec("elev").getOrThrow().command, "elevated")
    }

    @TestCase
    public func t51CommandsOutputShowsImplementedStubAndNotApplicable(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/commands")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Metis Telegram command catalog"), true)
            @Expect(adapter.sentText(0).contains("/bash"), true)
            @Expect(adapter.sentText(0).contains("stub"), false)
            @Expect(adapter.sentText(0).contains("/allowlist"), true)
            @Expect(adapter.sentText(0).contains("not_applicable"), true)
        }
    }

    @TestCase
    public func t53MockAcceptanceUsesTempConfigAndNativeRuntimeBypassesModelPath(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            user.telegram.actions.inlineKeyboard = true
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)

            @Expect(MetisConfigManager.configPath().toString().contains("/tmp/metis-gateway-telegram-native-test-home"), true)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/status")
            adapter.queue("/allowlist list")
            adapter.queue("[telegram-callback]\nid=cb-think\nmessageId=9\ndata=cmd:think:high\nby=8734062810")
            service.sendTextToPeerDetailed("telegram", "8734062810", "[subagent-notice]\nrunId=test-run\nstatus=done", accountId: "default")
            service.processOnce()

            @Expect(adapter.sentText(1).contains("Telegram status"), true)
            @Expect(adapter.sentText(1).contains("Token Status"), true)
            @Expect(adapter.sentText(1).startsWith("{"), false)
            @Expect(adapter.sentText(2).contains("Telegram allowlist"), true)
            @Expect(adapter.sentText(2).contains("Status: ok"), true)
            @Expect(adapter.sentText(3).contains("Telegram option: /think"), true)
            @Expect(adapter.sentText(3).contains("Mode: high"), true)
            @Expect(adapter.sentText(0).contains("[subagent-notice]"), true)
            @Expect(adapter.sentCount(), 4)
        }
    }

    @TestCase
    public func t51ReadOnlyNativeCommandsReturnRealStateWithoutModelPath(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            for (command in ["/tasks", "/context", "/usage status", "/plugins list", "/mcp show", "/config show", "/debug show", "/export-session"]) {
                adapter.queue(command)
            }
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Telegram tasks"), true)
            @Expect(adapter.sentText(1).contains("Telegram context"), true)
            @Expect(adapter.sentText(1).contains("Session: telegram:direct:8734062810"), true)
            @Expect(adapter.sentText(2).contains("Telegram option: /usage"), true)
            @Expect(adapter.sentText(2).contains("Field: responseUsage"), true)
            @Expect(adapter.sentText(3).contains("Telegram plugins"), true)
            @Expect(adapter.sentText(4).contains("Telegram MCP"), true)
            @Expect(adapter.sentText(5).contains("Telegram config"), true)
            @Expect(adapter.sentText(5).contains("Keys:"), true)
            @Expect(adapter.sentText(6).contains("Telegram command: /debug"), true)
            @Expect(adapter.sentText(6).contains("Status: ok"), true)
            @Expect(adapter.sentText(7).contains("Telegram session export"), true)
            @Expect(adapter.sentText(7).contains("/tmp/metis-gateway-telegram-native-test-home"), true)
        }
    }

    @TestCase
    public func t51SessionRuntimeCommandsMutateSessionIndexOrTranscript(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/think high")
            adapter.queue("/verbose on")
            adapter.queue("/fast on")
            adapter.queue("/send off")
            adapter.queue("/new")
            adapter.queue("/compact")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Status: ok"), true)
            @Expect(adapter.sentText(4).contains("Status: ok"), true)
            @Expect(adapter.sentText(4).contains("accepted"), false)
            let store = gatewaySessionStoreForUser(CliSettingManager.readGatewaySettings())
            let indexRoot = store.readSessionsIndexRoot()
            let entry = indexRoot.get("telegram:direct:8734062810").getOrThrow().asObject()
            @Expect(entry.get("thinkingLevel").getOrThrow().asString().getValue(), "high")
            @Expect(entry.get("verboseLevel").getOrThrow().asString().getValue(), "on")
            @Expect(entry.get("fastMode").getOrThrow().asBool().getValue(), true)
            @Expect(entry.get("sendPolicy").getOrThrow().asString().getValue(), "off")
        }
    }

    @TestCase
    public func t51DangerousCommandsRejectUnauthorizedAndDoNotExecute(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/bash echo should-not-run", sender: "123")
            adapter.queue("/config set gateway.telegram.defaultTo user:1", sender: "123")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Status: rejected"), true)
            @Expect(adapter.sentText(1).contains("Status: rejected"), true)
        }
    }

    @TestCase
    public func t51NativeArgMenuCallbacksDispatchThroughSameCommandPath(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.inlineKeyboard = true
            user.telegram.actions.callbackQuery = true
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/think")
            adapter.queue("[telegram-callback]\nid=cb-think\nmessageId=9\ndata=cmd:think:high\nby=8734062810")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("[inline-keyboard]"), true)
            @Expect(adapter.sentText(0).contains("callback:cmd:think:high"), true)
            @Expect(adapter.sentText(1).contains("Telegram option: /think"), true)
            @Expect(adapter.sentText(1).contains("Mode: high"), true)
        }
    }

    @TestCase
    public func t53AllowlistListsConfigAndPairingAndMutationsCreateApprovalOnly(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["tg:8734062810"]
            user.telegram.groupAllowFrom = ["group:-100"]
            CliSettingManager.writeGatewaySettings(user)
            let pairingDir = CliConfig.dotDir.join("gateway-telegram").join("accounts").join("default").join("credentials")
            Directory.create(pairingDir, recursive: true)
            File.writeTo(pairingDir.join("telegram-allowFrom.json"), "[\"555\"]".toArray())

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/allowlist list all")
            adapter.queue("/allowlist add dm 12345")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Telegram allowlist"), true)
            @Expect(adapter.sentText(0).contains("tg:8734062810"), true)
            @Expect(adapter.sentText(0).contains("555"), true)
            @Expect(adapter.sentText(1).contains("Status: approval_required"), true)
            @Expect(adapter.sentText(1).contains("Pending action: telegram.allowlist.add"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.telegram.allowFrom.contains("12345"), false)
        }
    }

    @TestCase
    public func t53SessionsAndApprovalsExposeTelegramReadonlyViews(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)
            let store = gatewaySessionStoreForUser(user)
            store.appendUser("telegram:direct:8734062810", "hello")
            store.appendAssistant("telegram:direct:8734062810", "world")

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/sessions list")
            adapter.queue("/sessions preview telegram:direct:8734062810")
            adapter.queue("/bash echo pending")
            adapter.queue("/approvals")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Gateway sessions"), true)
            @Expect(adapter.sentText(0).contains("telegram:direct:8734062810"), true)
            @Expect(adapter.sentText(1).contains("Session preview: telegram:direct:8734062810"), true)
            @Expect(adapter.sentText(1).contains("[user] hello"), true)
            @Expect(adapter.sentText(3).contains("Pending approvals: 1"), true)
            @Expect(adapter.sentText(3).contains("telegram.bash.exec"), true)
        }
    }

    @TestCase
    public func t53ConfigMcpPluginsDebugWritesCreateApprovalsWithoutMutatingConfig(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)

            let before = MetisConfigManager.configPath().toString()
            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            for (command in [
                "/config set gateway.telegram.defaultTo user:1",
                "/mcp set demo {}",
                "/plugins enable demo",
                "/debug set trace on"
            ]) {
                adapter.queue(command)
            }
            service.processOnce()

            for (i in 0..4) {
                @Expect(adapter.sentText(i).contains("Status: approval_required"), true)
                @Expect(adapter.sentText(i).contains("Approval:"), true)
            }
            @Expect(MetisConfigManager.configPath().toString(), before)
            @Expect(adapter.sentText(0).contains("telegram.config.mutation"), true)
            @Expect(adapter.sentText(1).contains("telegram.mcp.mutation"), true)
            @Expect(adapter.sentText(2).contains("telegram.plugins.mutation"), true)
            @Expect(adapter.sentText(3).contains("telegram.debug.mutation"), true)
        }
    }

    @TestCase
    public func t53BashRestartOnlyCreateApprovalsAndStopCancelsCurrentSubagent(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)
            let store = gatewaySessionStoreForUser(user)
            let run = gatewaySubagentCreateRunRecord(store.sessionsRoot(), "telegram:direct:8734062810", status: "running")
            let runId = run.get("runId").getOrThrow().asString().getValue()

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/bash echo should-not-run")
            adapter.queue("/restart")
            adapter.queue("/stop")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("telegram.bash.exec"), true)
            @Expect(adapter.sentText(1).contains("telegram.gateway.restart"), true)
            @Expect(adapter.sentText(2).contains("Status: cancelled"), true)
            @Expect(adapter.sentText(2).contains("Run: ${runId}"), true)
        }
    }

    @TestCase
    public func tgFreeze01AccessGroupsAuthorizeGroupCommandsOnlyWhenEnabled(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["111"]
            let groups = JsonObject()
            let group = JsonObject()
            group.put("allowFrom", JsonArray([JsonString("222")]))
            groups.put("-100", group)
            user.telegram.groups = Some(groups)
            user.telegram.commands.useAccessGroups = true
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queueGroup("/bash echo allowed", sender: "222")
            adapter.queueGroup("/bash echo denied", sender: "333")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Status: approval_required"), true)
            @Expect(adapter.sentText(0).contains("Pending action: telegram.bash.exec"), true)
            @Expect(adapter.sentText(1).contains("Status: rejected"), true)

            var disabled = CliSettingManager.readGatewaySettings()
            disabled.telegram.commands.useAccessGroups = false
            CliSettingManager.writeGatewaySettings(disabled)
            adapter.queueGroup("/bash echo old-auth", sender: "222")
            service.processOnce()
            @Expect(adapter.sentText(2).contains("Status: rejected"), true)
        }
    }

    @TestCase
    public func tgFreeze02CustomCommandsDispatchOrReturnStructuredMissingHandler(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.customCommands = [
                TelegramCustomCommandUserSettings(command: "deploy", description: "Deploy", reply: "deploying {args}"),
                TelegramCustomCommandUserSettings(command: "noop", description: "No handler")
            ]
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/deploy prod")
            adapter.queue("/noop prod")
            service.processOnce()

            @Expect(adapter.sentText(0), "deploying prod")
            @Expect(adapter.sentText(1).contains("Telegram command: /noop"), true)
            @Expect(adapter.sentText(1).contains("Status: handler_missing"), true)
            @Expect(adapter.sentText(1).startsWith("{"), false)
        }
    }

    @TestCase
    public func tgFreeze03SkillCommandExecutesGatewaySessionTurn(): Unit {
        withGatewayTelegramNativeTestHome {
            let modelName = "metis-test-telegram-native-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            ModelManager.registerChatModel(modelName, { => GatewayTelegramNativeFakeModel() })
            let oldModel = CliConfig.model
            CliConfig.model = modelName
            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.allowFrom = ["*"]
                CliSettingManager.writeGatewaySettings(user)

                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("/skill weather Shanghai")
                service.processOnce()

                @Expect(adapter.sentText(0), "fake telegram native session answer")
                let store = gatewaySessionStoreForUser(CliSettingManager.readGatewaySettings())
                let raw = store.readTranscriptRaw("telegram:direct:8734062810").getOrThrow()
                @Expect(raw.contains("/weather Shanghai"), true)
            } finally {
                CliConfig.model = oldModel
            }
        }
    }

    @TestCase
    public func t53SkillAndBtwAreNativeAndBtwDoesNotAppendConversationTurns(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            CliSettingManager.writeGatewaySettings(user)
            let store = gatewaySessionStoreForUser(user)
            store.appendUser("telegram:direct:8734062810", "before")

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/skill list")
            adapter.queue("/btw what is the side answer?")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Telegram command: /skill"), true)
            @Expect(adapter.sentText(0).startsWith("{"), false)
            @Expect(adapter.sentText(1).contains("Not applicable: /btw"), true)
            let raw = store.readTranscriptRaw("telegram:direct:8734062810").getOrThrow()
            @Expect(raw.contains("what is the side answer"), false)
        }
    }

    @TestCase
    public func t53TtsReportsMissingProviderAndFakeProviderEmitsVoicePayload(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.voice = true
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/tts status")
            adapter.queue("/tts provider fake")
            adapter.queue("/tts audio hello")
            adapter.queue("/tts provider missing-provider")
            adapter.queue("/tts audio hello")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Gateway TTS"), true)
            @Expect(adapter.sentText(0).contains("Status: not_configured"), true)
            @Expect(adapter.sentText(1).contains("Provider: fake"), true)
            @Expect(adapter.sentText(2).startsWith("[voice]"), true)
            @Expect(adapter.sentText(2).contains("/tmp/metis-gateway-telegram-native-test-home"), true)
            @Expect(adapter.sentText(3).contains("Status: not_found"), true)
            @Expect(adapter.sentText(4).contains("Status: not_found"), true)
        }
    }

    @TestCase
    public func t53TtsLegacyCommandProviderEmitsConfiguredAudioPayloadWithMigrationHint(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.audio = true
            let extra = JsonObject()
            let tts = JsonObject()
            tts.put("provider", JsonString("command"))
            tts.put("command", JsonArray([JsonString("sh"), JsonString("-c"), JsonString("printf '%s' \"$1\" > \"$2\""), JsonString("metis-tts"), JsonString("{text}"), JsonString("{output}")]))
            tts.put("outputExtension", JsonString("ogg"))
            tts.put("audioAsVoice", false.toJsonValue())
            tts.put("timeoutMs", 3000.toJsonValue())
            extra.put("telegramTts", tts)
            user.channelsExtra = Some(extra)
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/tts status")
            adapter.queue("/tts audio hello-command-provider")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Status: ok"), true)
            @Expect(adapter.sentText(0).contains("Provider: command"), true)
            @Expect(adapter.sentText(0).contains("Provider kind: command"), true)
            @Expect(adapter.sentText(0).contains("Audio as voice: false"), true)
            @Expect(adapter.sentText(0).contains("gateway.channelsExtra.telegramTts"), true)
            @Expect(adapter.sentText(1).startsWith("[audio]"), true)
            @Expect(adapter.sentText(1).contains("/tmp/metis-gateway-telegram-native-test-home"), true)
            @Expect(adapter.sentText(1).contains("caption=TTS (command)"), true)
        }
    }

    @TestCase
    public func t53TtsUsesTelegramSpeechOverrideBeforeSharedSpeechProvider(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.audio = true
            let sharedProvider = JsonObject()
            sharedProvider.put("kind", JsonString("command"))
            sharedProvider.put("command", JsonArray([JsonString("sh"), JsonString("-c"), JsonString("printf 'shared' > \"$2\""), JsonString("metis-tts"), JsonString("{text}"), JsonString("{output}")]))
            sharedProvider.put("outputExtension", JsonString("ogg"))
            let sharedProviders = JsonObject()
            sharedProviders.put("shared", sharedProvider)
            user.speech.tts.put("enabled", true.toJsonValue())
            user.speech.tts.put("provider", JsonString("shared"))
            user.speech.tts.put("providers", sharedProviders)

            let telegramProvider = JsonObject()
            telegramProvider.put("kind", JsonString("command"))
            telegramProvider.put("command", JsonArray([JsonString("sh"), JsonString("-c"), JsonString("printf 'telegram' > \"$2\""), JsonString("metis-tts"), JsonString("{text}"), JsonString("{output}")]))
            telegramProvider.put("outputExtension", JsonString("ogg"))
            let telegramProviders = JsonObject()
            telegramProviders.put("telegram", telegramProvider)
            user.telegram.speech.tts.put("provider", JsonString("telegram"))
            user.telegram.speech.tts.put("providers", telegramProviders)
            user.telegram.speech.audioAsVoice = Some<Bool>(false)
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/tts status")
            adapter.queue("/tts audio hello-shared-override")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Gateway TTS"), true)
            @Expect(adapter.sentText(0).contains("Provider: telegram"), true)
            @Expect(adapter.sentText(0).contains("Audio as voice: false"), true)
            @Expect(adapter.sentText(1).startsWith("[audio]"), true)
            @Expect(adapter.sentText(1).contains("caption=TTS (telegram)"), true)
        }
    }

    @TestCase
    public func t53TtsFallsBackToSharedSpeechProviderWhenTelegramOverrideMissing(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.audio = true
            let sharedProvider = JsonObject()
            sharedProvider.put("kind", JsonString("command"))
            sharedProvider.put("command", JsonArray([JsonString("sh"), JsonString("-c"), JsonString("printf 'shared' > \"$2\""), JsonString("metis-tts"), JsonString("{text}"), JsonString("{output}")]))
            sharedProvider.put("outputExtension", JsonString("ogg"))
            let sharedProviders = JsonObject()
            sharedProviders.put("shared", sharedProvider)
            user.speech.tts.put("enabled", true.toJsonValue())
            user.speech.tts.put("provider", JsonString("shared"))
            user.speech.tts.put("providers", sharedProviders)
            user.telegram.speech.audioAsVoice = Some<Bool>(false)
            CliSettingManager.writeGatewaySettings(user)

            let adapter = GatewayTelegramNativeTestAdapter()
            let service = gatewayTelegramNativeService(adapter)
            service.start()
            adapter.queue("/tts status")
            adapter.queue("/tts audio hello-shared")
            service.processOnce()

            @Expect(adapter.sentText(0).contains("Provider: shared"), true)
            @Expect(adapter.sentText(1).startsWith("[audio]"), true)
            @Expect(adapter.sentText(1).contains("caption=TTS (shared)"), true)
        }
    }

    @TestCase
    public func t53TtsAudioUsesDashScopeQwenProviderAndEmitsVoicePayload(): Unit {
        withGatewayTelegramNativeTestHome {
            var user = GatewayUserSettings()
            user.telegram.enabled = true
            user.telegram.allowFrom = ["*"]
            user.telegram.actions.audio = true
            user.telegram.speech.audioAsVoice = Some<Bool>(true)
            user.speech.tts.put("enabled", JsonBool(true))
            user.speech.tts.put("provider", JsonString("dashscope"))
            user.speech.tts.put("providers", gatewayTelegramNativeDashScopeQwenTtsProviders())
            CliSettingManager.writeGatewaySettings(user)

            setGatewaySpeechTtsDashScopeQwenRunnerForTest(Some({ request: JsonObject =>
                @Expect(request.get("url").getOrThrow().asString().getValue().endsWith("/services/aigc/multimodal-generation/generation"), true)
                let body = request.get("body").getOrThrow().asObject()
                let input = body.get("input").getOrThrow().asObject()
                @Expect(body.get("model").getOrThrow().asString().getValue(), "qwen3-tts-flash")
                @Expect(input.get("text").getOrThrow().asString().getValue(), "你好，这是 Metis 的 Qwen TTS 测试")
                @Expect(input.get("voice").getOrThrow().asString().getValue(), "Chelsie")
                @Expect(input.get("language_type").getOrThrow().asString().getValue(), "Chinese")
                GatewaySpeechTtsDashScopeQwenHttpResult(200, bodyBytes: "DASH-AUDIO".toArray())
            }))
            try {
                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("/tts status")
                adapter.queue("/tts audio 你好，这是 Metis 的 Qwen TTS 测试")
                service.processOnce()

                @Expect(adapter.sentText(0).contains("Status: ok"), true)
                @Expect(adapter.sentText(0).contains("Provider: dashscope"), true)
                @Expect(adapter.sentText(0).contains("Provider kind: dashscope-qwen-tts"), true)
                @Expect(adapter.sentText(1).startsWith("[voice]"), true)
                @Expect(adapter.sentText(1).contains("caption=TTS (dashscope)"), true)
                @Expect(adapter.sentText(1).contains("语音暂时发送失败"), false)
            } finally {
                setGatewaySpeechTtsDashScopeQwenRunnerForTest(None<(JsonObject) -> GatewaySpeechTtsDashScopeQwenHttpResult>)
            }
        }
    }

    @TestCase
    public func t53VoiceInboundAutoReplyUsesTtsPayloadWhenEnabled(): Unit {
        withGatewayTelegramNativeTestHome {
            let modelName = "metis-test-telegram-auto-tts-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            ModelManager.registerChatModel(modelName, { => GatewayTelegramNativeFakeModel() })
            let oldModel = CliConfig.model
            CliConfig.model = modelName
            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.allowFrom = ["*"]
                user.channelModels["telegram"] = modelName
                user.telegram.speech.autoReplyToVoice = Some<Bool>(true)
                user.telegram.speech.audioAsVoice = Some<Bool>(true)
                user.speech.tts.put("enabled", true.toJsonValue())
                user.speech.tts.put("provider", JsonString("fake"))
                CliSettingManager.writeGatewaySettings(user)

                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("[voice]\nfileId=file-1\nmimeType=audio/ogg\n[media-context]\nchannel=telegram\naccountId=default\npeerId=user:8734062810\nmessageId=900\nmediaKind=voice\ntranscript=语音测试\nunderstandingStatus=ok")
                service.processOnce()

                var foundVoice = false
                var foundPlainAnswer = false
                for (i in 0..adapter.sentCount()) {
                    let sent = adapter.sentText(i)
                    if (sent.startsWith("[voice]") && sent.contains("caption=TTS (fake)")) {
                        foundVoice = true
                    }
                    if (sent == "fake telegram native session answer") {
                        foundPlainAnswer = true
                    }
                }
                @Expect(foundVoice, true)
                @Expect(foundPlainAnswer, false)
            } finally {
                CliConfig.model = oldModel
            }
        }
    }

    @TestCase
    public func t53VoiceInboundAutoReplyUsesDashScopeQwenTtsPayloadWhenEnabled(): Unit {
        withGatewayTelegramNativeTestHome {
            let modelName = "metis-test-telegram-auto-dashscope-tts-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            ModelManager.registerChatModel(modelName, { => GatewayTelegramNativeFakeModel() })
            let oldModel = CliConfig.model
            CliConfig.model = modelName
            setGatewaySpeechTtsDashScopeQwenRunnerForTest(Some({ request: JsonObject =>
                let body = request.get("body").getOrThrow().asObject()
                let input = body.get("input").getOrThrow().asObject()
                @Expect(input.get("text").getOrThrow().asString().getValue(), "fake telegram native session answer")
                @Expect(input.get("voice").getOrThrow().asString().getValue(), "Chelsie")
                GatewaySpeechTtsDashScopeQwenHttpResult(200, bodyBytes: "DASH-AUDIO".toArray())
            }))
            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.allowFrom = ["*"]
                user.channelModels["telegram"] = modelName
                user.telegram.speech.autoReplyToVoice = Some<Bool>(true)
                user.telegram.speech.audioAsVoice = Some<Bool>(true)
                user.speech.tts.put("enabled", JsonBool(true))
                user.speech.tts.put("provider", JsonString("dashscope"))
                user.speech.tts.put("degradeMessage", JsonString("语音暂时发送失败，我先打字陪你。"))
                user.speech.tts.put("providers", gatewayTelegramNativeDashScopeQwenTtsProviders())
                CliSettingManager.writeGatewaySettings(user)

                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("[voice]\nfileId=file-1\nmimeType=audio/ogg\n[media-context]\nchannel=telegram\naccountId=default\npeerId=user:8734062810\nmessageId=903\nmediaKind=voice\ntranscript=语音测试\nunderstandingStatus=ok")
                service.processOnce()

                var foundVoice = false
                var foundPlainAnswer = false
                var foundDegrade = false
                for (i in 0..adapter.sentCount()) {
                    let sent = adapter.sentText(i)
                    if (sent.startsWith("[voice]") && sent.contains("caption=TTS (dashscope)")) {
                        foundVoice = true
                    }
                    if (sent == "fake telegram native session answer") {
                        foundPlainAnswer = true
                    }
                    if (sent.contains("语音暂时发送失败")) {
                        foundDegrade = true
                    }
                }
                @Expect(foundVoice, true)
                @Expect(foundPlainAnswer, false)
                @Expect(foundDegrade, false)
            } finally {
                CliConfig.model = oldModel
                setGatewaySpeechTtsDashScopeQwenRunnerForTest(None<(JsonObject) -> GatewaySpeechTtsDashScopeQwenHttpResult>)
            }
        }
    }

    @TestCase
    public func t53VoiceInboundAutoReplyFallsBackToVoiceWhenModelReturnsSilentReplyToken(): Unit {
        withGatewayTelegramNativeTestHome {
            let modelName = "metis-test-telegram-auto-tts-silent-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            ModelManager.registerChatModel(modelName, { => GatewayTelegramNativeSilentReplyFakeModel() })
            let oldModel = CliConfig.model
            CliConfig.model = modelName
            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.allowFrom = ["*"]
                user.channelModels["telegram"] = modelName
                user.telegram.speech.autoReplyToVoice = Some<Bool>(true)
                user.telegram.speech.audioAsVoice = Some<Bool>(true)
                user.speech.tts.put("enabled", true.toJsonValue())
                user.speech.tts.put("provider", JsonString("fake"))
                CliSettingManager.writeGatewaySettings(user)

                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("[voice]\nfileId=file-1\nmimeType=audio/ogg\n[media-context]\nchannel=telegram\naccountId=default\npeerId=user:8734062810\nmessageId=902\nmediaKind=voice\ntranscript=语音测试\nunderstandingStatus=ok")
                service.processOnce()

                var foundVoice = false
                var foundSilentText = false
                for (i in 0..adapter.sentCount()) {
                    let sent = adapter.sentText(i)
                    if (sent.startsWith("[voice]") && sent.contains("caption=TTS (fake)")) {
                        foundVoice = true
                    }
                    if (sent.trimAscii().toAsciiLower() == "<silent_reply>" || sent.trimAscii().toAsciiLower() == "silent_reply") {
                        foundSilentText = true
                    }
                }
                @Expect(foundVoice, true)
                @Expect(foundSilentText, false)
            } finally {
                CliConfig.model = oldModel
            }
        }
    }

    @TestCase
    public func t53TextExplicitVoiceRequestDoesNotUseKeywordDrivenTtsVoicePayload(): Unit {
        withGatewayTelegramNativeTestHome {
            let modelName = "metis-test-telegram-text-tts-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            ModelManager.registerChatModel(modelName, { => GatewayTelegramNativeFakeModel() })
            let oldModel = CliConfig.model
            CliConfig.model = modelName
            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.allowFrom = ["*"]
                user.channelModels["telegram"] = modelName
                user.telegram.speech.audioAsVoice = Some<Bool>(true)
                user.speech.tts.put("enabled", true.toJsonValue())
                user.speech.tts.put("provider", JsonString("fake"))
                CliSettingManager.writeGatewaySettings(user)

                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("发一条语音信息给我，随便说点什么。")
                service.processOnce()

                var foundVoice = false
                var foundPlainAnswer = false
                for (i in 0..adapter.sentCount()) {
                    let sent = adapter.sentText(i)
                    if (sent.startsWith("[voice]") && sent.contains("caption=TTS (fake)")) {
                        foundVoice = true
                    }
                    if (sent == "fake telegram native session answer") {
                        foundPlainAnswer = true
                    }
                }
                @Expect(foundVoice, false)
                @Expect(foundPlainAnswer, true)
            } finally {
                CliConfig.model = oldModel
            }
        }
    }

    @TestCase
    public func t53VoiceInboundAutoReplyFallsBackToTextWhenDisabled(): Unit {
        withGatewayTelegramNativeTestHome {
            let modelName = "metis-test-telegram-auto-tts-off-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            ModelManager.registerChatModel(modelName, { => GatewayTelegramNativeFakeModel() })
            let oldModel = CliConfig.model
            CliConfig.model = modelName
            try {
                var user = GatewayUserSettings()
                user.telegram.enabled = true
                user.telegram.allowFrom = ["*"]
                user.telegram.speech.autoReplyToVoice = Some<Bool>(false)
                user.telegram.speech.audioAsVoice = Some<Bool>(true)
                user.speech.tts.put("enabled", true.toJsonValue())
                user.speech.tts.put("provider", JsonString("fake"))
                CliSettingManager.writeGatewaySettings(user)

                let adapter = GatewayTelegramNativeTestAdapter()
                let service = gatewayTelegramNativeService(adapter)
                service.start()
                adapter.queue("[voice]\nfileId=file-1\nmimeType=audio/ogg\n[media-context]\nchannel=telegram\naccountId=default\npeerId=user:8734062810\nmessageId=901\nmediaKind=voice\ntranscript=语音测试\nunderstandingStatus=ok")
                service.processOnce()

                var foundPlainAnswer = false
                for (i in 0..adapter.sentCount()) {
                    if (adapter.sentText(i) == "fake telegram native session answer") {
                        foundPlainAnswer = true
                    }
                }
                @Expect(foundPlainAnswer, true)
            } finally {
                CliConfig.model = oldModel
            }
        }
    }
}
