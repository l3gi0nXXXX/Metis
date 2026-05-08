package metis.gateway.core

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.gateway.model.{ChannelPolicyConfig, ChannelType, ChatType, InboundMessage, OutboundMessage, SendResult}

import magic.jsonable.*

import std.collection.{ArrayList, HashMap}
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, remove}
import std.sync.Mutex
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

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
        "test-message-${this.sent.size}"
    }

    public func sentText(index: Int64): String {
        match (this.sent.get(index)) {
            case Some(v) => v.text
            case None => ""
        }
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

private let gatewayTelegramNativeTestLock: Mutex = Mutex()

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
    synchronized(gatewayTelegramNativeTestLock) {
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
            @Expect(text.contains("Page:"), true)
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
            @Expect(text.contains("callback:models:set:"), true)
            @Expect(text.contains("Telegram model"), true)
            let updated = CliSettingManager.readGatewaySettings()
            @Expect(updated.channelModels.get("telegram") ?? "", "")
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
                    out.put("text", JsonString("hooked:${text}"))
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

            @Expect(adapter.sentText(0), "hooked:command handled")
            @Expect(recorder.count("hook.message_sending"), 1)
            @Expect(recorder.count("hook.message_sent"), 1)
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
                    for ((kind, text) in [("edit", "edited"), ("edit-buttons", ""), ("clear-buttons", ""), ("delete", "")]) {
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
                    "  api.commands.register({ command: 'demo', description: 'Demo command' }, async () => ({ type: 'reply', text: 'command ok' }));\n" +
                    "  api.interactive.register({ namespace: 'demo', channel: 'telegram' }, async () => ({ intents: [{ type: 'reply', text: 'interactive ok', buttons: [[{ text: 'OK', callback_data: 'plugin:demo:ok' }]] }] }));\n" +
                    "  api.approvals.register({ namespace: 'demo', channel: 'telegram' }, async (ctx) => ({ type: 'reply', text: 'approval ' + ctx.decision }));\n" +
                    "  api.hooks.message_sending(async (ctx) => ({ text: '[hooked] ' + ctx.text }));\n" +
                    "  api.hooks.message_received(async (ctx) => { globalThis.__metis_received = ctx.messageId; });\n" +
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
                hookPayload.put("text", JsonString("hello"))
                let hook = gatewayOpenClawPluginSidecarInvoke(user, "hook.message_sending", hookPayload)
                @Expect(hook.get("text").getOrThrow().asString().getValue(), "[hooked] hello")

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

            @Expect(JsonValue.fromStr(adapter.sentText(0)).asObject().get("action").getOrThrow().asString().getValue(), "help")
            @Expect(JsonValue.fromStr(adapter.sentText(1)).asObject().get("action").getOrThrow().asString().getValue(), "help")
            @Expect(adapter.sentText(1).contains("/subagents spawn"), true)
            @Expect(JsonValue.fromStr(adapter.sentText(2)).asObject().get("action").getOrThrow().asString().getValue(), "sessions")
            @Expect(JsonValue.fromStr(adapter.sentText(3)).asObject().get("action").getOrThrow().asString().getValue(), "approvals")
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
            @Expect(adapter.sentText(0).contains("\"action\":\"focus\""), true)
            @Expect(adapter.sentText(0).contains("agent:main:explicit:review"), true)

            let resolved = gatewayTelegramThreadBindingResolve("telegram", "default", "8734062810")
            @Expect(resolved.get("sessionKey").getOrThrow().asString().getValue(), "agent:main:explicit:review")

            adapter.queue("/agents")
            service.processOnce()
            @Expect(adapter.sentText(1).contains("\"action\":\"agents\""), true)
            @Expect(adapter.sentText(1).contains("agent:main:explicit:review"), true)

            adapter.queue("/unfocus")
            service.processOnce()
            @Expect(adapter.sentText(2).contains("\"action\":\"unfocus\""), true)
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

            let root = JsonValue.fromStr(adapter.sentText(0)).asObject()
            let native = root.get("native").getOrThrow().asArray()
            @Expect(adapter.sentText(0).contains("\"/bash\""), true)
            @Expect(adapter.sentText(0).contains("\"status\": \"stub\""), true)
            @Expect(adapter.sentText(0).contains("\"status\": \"not_applicable\""), true)
            @Expect(native.size() >= 43, true)
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

            @Expect(JsonValue.fromStr(adapter.sentText(0)).asObject().get("action").getOrThrow().asString().getValue(), "tasks")
            @Expect(JsonValue.fromStr(adapter.sentText(1)).asObject().get("sessionKey").isSome(), true)
            @Expect(JsonValue.fromStr(adapter.sentText(2)).asObject().get("field").getOrThrow().asString().getValue(), "responseUsage")
            @Expect(JsonValue.fromStr(adapter.sentText(3)).asObject().get("commands").isSome(), true)
            @Expect(JsonValue.fromStr(adapter.sentText(4)).asObject().get("mcpServers").isSome(), true)
            @Expect(JsonValue.fromStr(adapter.sentText(5)).asObject().get("keys").isSome(), true)
            @Expect(JsonValue.fromStr(adapter.sentText(6)).asObject().get("status").getOrThrow().asString().getValue(), "ok")
            let exported = JsonValue.fromStr(adapter.sentText(7)).asObject()
            @Expect(exported.get("path").getOrThrow().asString().getValue().contains("/tmp/metis-gateway-telegram-native-test-home"), true)
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

            @Expect(adapter.sentText(0).contains("\"status\": \"ok\""), true)
            @Expect(adapter.sentText(4).contains("\"status\": \"ok\""), true)
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

            @Expect(adapter.sentText(0).contains("\"status\": \"rejected\""), true)
            @Expect(adapter.sentText(1).contains("\"status\": \"rejected\""), true)
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
            @Expect(adapter.sentText(1).contains("\"action\": \"think\""), true)
            @Expect(adapter.sentText(1).contains("\"mode\": \"high\""), true)
        }
    }
}
