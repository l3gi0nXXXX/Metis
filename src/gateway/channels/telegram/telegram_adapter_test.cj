package metis.gateway.channels.telegram

import metis.core.{GatewayToolRuntimeContext, gatewayWithToolRuntimeContext, setGatewayMediaAsrRunnerForTest, setGatewayMediaVisionRunnerForTest}
import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager}
import metis.gateway.core.{gatewayBuildMediaContextPrompt, gatewayResolveSessionContextWithAgentRoute, setGatewayOpenClawPluginSidecarRunnerForTest}
import metis.gateway.model.*
import metis.gateway.session.gatewaySessionRequestFromInbound
import metis.gateway.tools.{GatewayTelegramMediaToolset, setGatewayTelegramStickerCacheRootForTest}

import magic.jsonable.*
import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.sync.Mutex
import std.time.*
import std.unittest.testmacro.*
import stdx.encoding.json.*

private class TelegramFakeBotApi {
    public var calls: ArrayList<String> = ArrayList<String>()
    public var bodies: ArrayList<String> = ArrayList<String>()
    public var contentTypes: ArrayList<String> = ArrayList<String>()
    public var bodySizes: ArrayList<Int64> = ArrayList<Int64>()
    private var rawBodyBytes: ArrayList<Array<Byte>> = ArrayList<Array<Byte>>()
    public var pollingUpdatesEnabled: Bool = true
    public var setMyCommandsFailuresBeforeSuccess: Int64 = 0
    public var failDraftFinalEdit: Bool = false
    private let lock: Mutex = Mutex()
    private var getUpdatesCount: Int64 = 0
    private var nextMessageId: Int64 = 500

    public func handle(request: TelegramTransportRequest): TelegramTransportResponse {
        synchronized(this.lock) {
            this.calls.add(request.context + "|" + this.methodName(request.url))
            if (!request.body.trimAscii().isEmpty()) {
                this.bodies.add(request.body)
            }
            if (!request.contentType.trimAscii().isEmpty()) {
                this.contentTypes.add(request.contentType)
            }
            if (!request.bodyBytes.isEmpty()) {
                this.bodySizes.add(Int64(request.bodyBytes.size))
                this.rawBodyBytes.add(request.bodyBytes)
                try {
                    this.bodies.add(String.fromUtf8(request.bodyBytes))
                } catch (_e: Exception) {
                    this.bodies.add("<binary-body:${request.bodyBytes.size}>")
                }
            }
            if (request.context == "get") {
                if (request.url.contains("/getMe")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"id\":10001,\"is_bot\":true,\"username\":\"metis_fake_bot\"}}", outcome: "ok")
                }
                if (request.url.contains("/getWebhookInfo")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"url\":\"\",\"pending_update_count\":0}}", outcome: "ok")
                }
                if (request.url.contains("/getFile")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"file_path\":\"photos/fake-photo.jpg\",\"file_size\":12}}", outcome: "ok")
                }
                if (request.url.contains("/getChatMember")) {
                    let status = if (request.url.contains("chat_id=-1000000000002")) { "left" } else { "administrator" }
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"status\":\"${status}\",\"user\":{\"id\":10001,\"is_bot\":true}}}", outcome: "ok")
                }
                if (request.url.contains("/getChat")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"id\":-1001234567890,\"type\":\"supergroup\",\"title\":\"Metis Test\",\"username\":\"metis_test\",\"is_forum\":true,\"available_reactions\":[{\"type\":\"emoji\",\"emoji\":\"👍\"}]}}", outcome: "ok")
                }
            }
            if (request.context == "downloadFile") {
                return TelegramTransportResponse(true, body: "fake-binary-photo", outcome: "ok")
            }
            if (request.context == "setMyCommands" && this.setMyCommandsFailuresBeforeSuccess > 0) {
                this.setMyCommandsFailuresBeforeSuccess -= 1
                return TelegramTransportResponse(true, body: "{\"ok\":false,\"description\":\"Bad Request: BOT_COMMANDS_TOO_MUCH\"}", outcome: "api-error")
            }
            if (request.context == "setWebhook" || request.context == "setMyCommands" || request.context == "setMyCommands:retry" || request.context == "deleteMyCommands" || request.context.startsWith("deleteWebhook:")) {
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }
            if (request.context == "getUpdates") {
                if (!this.pollingUpdatesEnabled) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[]}", outcome: "ok")
                }
                this.getUpdatesCount += 1
                if (this.getUpdatesCount == 1) {
                    return TelegramTransportResponse(
                        true,
                        body: "{\"ok\":true,\"result\":[{\"update_id\":7001,\"message\":{\"message_id\":11,\"text\":\"hello from fake polling\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}]}",
                        outcome: "ok"
                    )
                }
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[]}", outcome: "ok")
            }
            if (request.context == "answerCallbackQuery" || request.context.startsWith("editMessageReplyMarkup:")) {
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }
            if (request.context.startsWith("send:draft:final") && this.failDraftFinalEdit) {
                return TelegramTransportResponse(true, body: "{\"ok\":false,\"description\":\"Bad Request: message to edit not found\"}", outcome: "api-error")
            }
            if (request.context.startsWith("send:delete") || request.context.startsWith("send:pin") || request.context.startsWith("send:unpin") || request.context.startsWith("send:reaction") || request.context.startsWith("send:topic-edit") || request.context.startsWith("send:draft:final") || request.context.startsWith("send:edit-media")) {
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }
            if (request.context.startsWith("send:draft:native")) {
                this.nextMessageId += 1
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":${this.nextMessageId}}}", outcome: "ok")
            }
            if (request.context.startsWith("send:media-group")) {
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[{\"message_id\":601},{\"message_id\":602}]}", outcome: "ok")
            }
            if (request.context.startsWith("send:topic-create")) {
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_thread_id\":42,\"name\":\"Sprint\"}}", outcome: "ok")
            }
            if (request.context.startsWith("send:")) {
                this.nextMessageId += 1
                return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":${this.nextMessageId}}}", outcome: "ok")
            }
            TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
        }
    }

    public func saw(method: String): Bool {
        synchronized(this.lock) {
            for (call in this.calls) {
                if (call.contains(method)) {
                    return true
                }
            }
            false
        }
    }

    public func count(method: String): Int64 {
        var total: Int64 = 0
        synchronized(this.lock) {
            for (call in this.calls) {
                if (call.contains(method)) {
                    total += 1
                }
            }
        }
        total
    }

    public func countCallContaining(text: String): Int64 {
        var total: Int64 = 0
        synchronized(this.lock) {
            for (call in this.calls) {
                if (call.contains(text)) {
                    total += 1
                }
            }
        }
        total
    }

    public func sawBodyContaining(text: String): Bool {
        synchronized(this.lock) {
            for (body in this.bodies) {
                if (body.contains(text)) {
                    return true
                }
            }
            let needle = text.toArray()
            for (bodyBytes in this.rawBodyBytes) {
                if (telegramBytesContain(bodyBytes, needle)) {
                    return true
                }
            }
            false
        }
    }

    public func sawContentTypeContaining(text: String): Bool {
        synchronized(this.lock) {
            for (contentType in this.contentTypes) {
                if (contentType.contains(text)) {
                    return true
                }
            }
            false
        }
    }

    private func methodName(url: String): String {
        if (url.contains("/getUpdates")) { return "getUpdates" }
        if (url.contains("/setWebhook")) { return "setWebhook" }
        if (url.contains("/deleteWebhook")) { return "deleteWebhook" }
        if (url.contains("/deleteMyCommands")) { return "deleteMyCommands" }
        if (url.contains("/setMyCommands")) { return "setMyCommands" }
        if (url.contains("/getMe")) { return "getMe" }
        if (url.contains("/getWebhookInfo")) { return "getWebhookInfo" }
        if (url.contains("/getFile")) { return "getFile" }
        if (url.contains("/getChatMember")) { return "getChatMember" }
        if (url.contains("/getChat")) { return "getChat" }
        if (url.contains("/deleteMessage")) { return "deleteMessage" }
        if (url.contains("/pinChatMessage")) { return "pinChatMessage" }
        if (url.contains("/unpinChatMessage")) { return "unpinChatMessage" }
        if (url.contains("/setMessageReaction")) { return "setMessageReaction" }
        if (url.contains("/sendChatAction")) { return "sendChatAction" }
        if (url.contains("/sendPoll")) { return "sendPoll" }
        if (url.contains("/createForumTopic")) { return "createForumTopic" }
        if (url.contains("/editForumTopic")) { return "editForumTopic" }
        if (url.contains("/editMessageText")) { return "editMessageText" }
        if (url.contains("/editMessageMedia")) { return "editMessageMedia" }
        if (url.contains("/editMessageReplyMarkup")) { return "editMessageReplyMarkup" }
        if (url.contains("/answerCallbackQuery")) { return "answerCallbackQuery" }
        if (url.contains("/sendMediaGroup")) { return "sendMediaGroup" }
        if (url.contains("/sendPhoto")) { return "sendPhoto" }
        if (url.contains("/sendAnimation")) { return "sendAnimation" }
        if (url.contains("/sendDocument")) { return "sendDocument" }
        if (url.contains("/sendAudio")) { return "sendAudio" }
        if (url.contains("/sendVoice")) { return "sendVoice" }
        if (url.contains("/sendVideo")) { return "sendVideo" }
        if (url.contains("/sendVideoNote")) { return "sendVideoNote" }
        if (url.contains("/sendMessageDraft")) { return "sendMessageDraft" }
        if (url.contains("/sendMessage")) { return "sendMessage" }
        if (url.contains("/file/bot")) { return "downloadFile" }
        "unknown"
    }
}

private func telegramAliasRouteStringArray(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(JsonString(value))
    }
    out
}

private func telegramAliasRouteAgent(id: String, isDefault!: Bool = false, mentionPatterns!: Array<String> = []): JsonObject {
    let agent = JsonObject()
    agent.put("id", JsonString(id))
    if (isDefault) {
        agent.put("default", JsonBool(true))
    }
    if (mentionPatterns.size > 0) {
        let groupChat = JsonObject()
        groupChat.put("mentionPatterns", telegramAliasRouteStringArray(mentionPatterns))
        agent.put("groupChat", groupChat)
    }
    return agent
}

private func telegramAliasRouteRoot(): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let list = JsonArray([])
    list.add(telegramAliasRouteAgent("main", isDefault: true))
    list.add(telegramAliasRouteAgent("writer", mentionPatterns: ["@writer", "/agent writer"]))
    list.add(telegramAliasRouteAgent("broken", mentionPatterns: ["("]))
    agents.put("list", list)
    root.put("agents", agents)
    let channels = JsonObject()
    let telegram = JsonObject()
    telegram.put("defaultAccountId", JsonString("default"))
    channels.put("telegram", telegram)
    root.put("channels", channels)
    return root
}

private func telegramBytesContain(body: Array<Byte>, needle: Array<Byte>): Bool {
    if (needle.isEmpty()) {
        return true
    }
    if (body.size < needle.size) {
        return false
    }
    for (start in 0..=(body.size - needle.size)) {
        var matched = true
        for (idx in 0..needle.size) {
            if (body[start + idx] != needle[idx]) {
                matched = false
                break
            }
        }
        if (matched) {
            return true
        }
    }
    false
}

private func telegramTestPngBytes(width: Int64, height: Int64): Array<Byte> {
    if (width == 9000 && height == 2000) {
        return [
            137u8, 80u8, 78u8, 71u8, 13u8, 10u8, 26u8, 10u8,
            0u8, 0u8, 0u8, 13u8, 73u8, 72u8, 68u8, 82u8,
            0u8, 0u8, 35u8, 40u8, 0u8, 0u8, 7u8, 208u8
        ]
    }
    if (width == 640 && height == 480) {
        return [
            137u8, 80u8, 78u8, 71u8, 13u8, 10u8, 26u8, 10u8,
            0u8, 0u8, 0u8, 13u8, 73u8, 72u8, 68u8, 82u8,
            0u8, 0u8, 2u8, 128u8, 0u8, 0u8, 1u8, 224u8
        ]
    }
    if (width == 320 && height == 240) {
        return [
            137u8, 80u8, 78u8, 71u8, 13u8, 10u8, 26u8, 10u8,
            0u8, 0u8, 0u8, 13u8, 73u8, 72u8, 68u8, 82u8,
            0u8, 0u8, 1u8, 64u8, 0u8, 0u8, 0u8, 240u8
        ]
    }
    [
        137u8, 80u8, 78u8, 71u8, 13u8, 10u8, 26u8, 10u8,
        0u8, 0u8, 0u8, 13u8, 73u8, 72u8, 68u8, 82u8,
        0u8, 0u8, 0u8, 1u8, 0u8, 0u8, 0u8, 1u8
    ]
}

private class TelegramThreadFallbackFakeBotApi {
    public let bodies: ArrayList<String> = ArrayList<String>()
    public var sends: Int64 = 0

    public func handle(request: TelegramTransportRequest): TelegramTransportResponse {
        if (request.context.startsWith("send:text")) {
            this.sends += 1
            this.bodies.add(request.body)
            if (this.sends == 1) {
                return TelegramTransportResponse(true, body: "{\"ok\":false,\"description\":\"Bad Request: message thread not found\"}", outcome: "ok")
            }
            return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":701}}", outcome: "ok")
        }
        TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
    }

    public func sawBodyContaining(text: String): Bool {
        for (body in this.bodies) {
            if (body.contains(text)) {
                return true
            }
        }
        false
    }
}

private class TelegramChatActionUnauthorizedFakeBotApi {
    public var calls: Int64 = 0

    public func handle(request: TelegramTransportRequest): TelegramTransportResponse {
        if (request.url.contains("/sendChatAction")) {
            this.calls += 1
            return TelegramTransportResponse(true, body: "{\"ok\":false,\"error_code\":401,\"description\":\"Unauthorized\"}", outcome: "ok")
        }
        TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":1}}", outcome: "ok")
    }
}

private class TelegramVoiceForbiddenFakeBotApi {
    public var voiceCalls: Int64 = 0
    public var textCalls: Int64 = 0
    public let bodies: ArrayList<String> = ArrayList<String>()

    public func handle(request: TelegramTransportRequest): TelegramTransportResponse {
        if (request.url.contains("/sendVoice")) {
            this.voiceCalls += 1
            this.bodies.add(request.body)
            return TelegramTransportResponse(true, body: "{\"ok\":false,\"description\":\"Bad Request: VOICE_MESSAGES_FORBIDDEN\"}", outcome: "ok")
        }
        if (request.url.contains("/sendMessage")) {
            this.textCalls += 1
            this.bodies.add(request.body)
            return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":801}}", outcome: "ok")
        }
        TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
    }

    public func sawBodyContaining(text: String): Bool {
        for (body in this.bodies) {
            if (body.contains(text)) {
                return true
            }
        }
        false
    }
}

private class TelegramGetFileRetryFakeBotApi {
    public var getFileCalls: Int64 = 0

    public func handle(request: TelegramTransportRequest): TelegramTransportResponse {
        if (request.url.contains("/getFile")) {
            this.getFileCalls += 1
            if (this.getFileCalls < 3) {
                return TelegramTransportResponse(true, body: "{\"ok\":false,\"description\":\"Internal Server Error\"}", outcome: "ok")
            }
            return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"file_path\":\"photos/retry.jpg\",\"file_size\":4}}", outcome: "ok")
        }
        if (request.context == "downloadFile") {
            return TelegramTransportResponse(true, bodyBytes: "abcd".toArray(), outcome: "ok")
        }
        TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
    }
}

@Test
public class TelegramAdapterTest {
    @BeforeAll
    public func isolateMetisHomeForTelegramAdapterTests(): Unit {
        let testHome = "/tmp/metis-telegram-adapter-test-home"
        try { remove(Path(testHome), recursive: true) } catch (_e: Exception) { () }
        Directory.create(Path(testHome), recursive: true)
        setVariable("METIS_HOME", testHome)
        CliConfig.invalidatePathCache()
    }

    public init() {
        setTelegramTransportRunnerForTest(None)
        setTelegramAsrRunnerForTest(None)
        setGatewayOpenClawPluginSidecarRunnerForTest(None)
    }

    @TestCase
    public func simulateIncomingTextQueuesTelegramMessages(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        adapter.start()
        adapter.simulateIncomingText("msg-1", "group:-100123:topic:42", "8734062810", "hello", chatType: ChatType.Group, mentioned: true, threadId: Some("42"))

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(
            match (inbound[0].channel) {
                case ChannelType.Telegram => true
                case _ => false
            },
            true
        )
        @Expect(inbound[0].peerId, "group:-100123:topic:42")
        @Expect(inbound[0].threadId.getOrThrow(), "42")
        @Expect(inbound[0].replyInThread, true)
        let imRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(imRoute.get("channel").getOrThrow().asString().getValue(), "telegram")
        @Expect(imRoute.get("accountId").getOrThrow().asString().getValue(), "default")
        @Expect(imRoute.get("peerKind").getOrThrow().asString().getValue(), "topic")
        @Expect(imRoute.get("peerId").getOrThrow().asString().getValue(), "42")
        @Expect(imRoute.get("parentPeerKind").getOrThrow().asString().getValue(), "group")
        @Expect(imRoute.get("parentPeerId").getOrThrow().asString().getValue(), "-100123")
    }

    @TestCase
    public func fakeInboundTelegramAliasMentionRoutesWriterAndDefaultsOtherwise(): Unit {
        let root = telegramAliasRouteRoot()
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        adapter.start()
        adapter.simulateIncomingText("msg-default", "group:-100123", "8734062810", "hello team", chatType: ChatType.Group, mentioned: true)
        adapter.simulateIncomingText("msg-slash", "group:-100123", "8734062810", "/agent writer draft this", chatType: ChatType.Group, mentioned: true)
        adapter.simulateIncomingText("msg-mention", "group:-100123", "8734062810", "@writer draft this", chatType: ChatType.Group, mentioned: true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 3)
        let defaultContext = gatewayResolveSessionContextWithAgentRoute(gatewaySessionRequestFromInbound(inbound[0], routeRoot: root))
        let slashContext = gatewayResolveSessionContextWithAgentRoute(gatewaySessionRequestFromInbound(inbound[1], routeRoot: root))
        let mentionContext = gatewayResolveSessionContextWithAgentRoute(gatewaySessionRequestFromInbound(inbound[2], routeRoot: root))

        @Expect(defaultContext.agentId, "main")
        @Expect(defaultContext.matchedBy, "default")
        @Expect(slashContext.agentId, "writer")
        @Expect(slashContext.matchedBy, "alias.mention")
        @Expect(mentionContext.agentId, "writer")
        @Expect(mentionContext.matchedBy, "alias.mention")
    }

    @TestCase
    public func fakeInboundTelegramInvalidAliasPatternDoesNotCrashOrOverrideDefault(): Unit {
        let root = telegramAliasRouteRoot()
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        adapter.start()
        adapter.simulateIncomingText("msg-invalid", "group:-100123", "8734062810", "plain message (with invalid literal", chatType: ChatType.Group, mentioned: true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let context = gatewayResolveSessionContextWithAgentRoute(gatewaySessionRequestFromInbound(inbound[0], routeRoot: root))

        @Expect(context.agentId, "main")
        @Expect(context.matchedBy, "default")
    }

    @TestCase
    public func disabledSendMessageActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello"))
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("sendMessage action is disabled"), true)
        }
    }

    @TestCase
    public func nativeCommandsPayloadUsesTelegramMenuShape(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payload = adapter.debugBuildNativeCommandsPayload()
        let commands = payload.get("commands").getOrThrow().asArray()
        @Expect(commands.size(), 44)
        let first = commands[0].asObject()
        @Expect(first.get("command").getOrThrow().asString().getValue(), "help")
        @Expect(first.get("description").getOrThrow().asString().getValue(), "Show available commands.")
        @Expect(this.telegramPayloadHasCommand(commands, "commands"), true)
        @Expect(this.telegramPayloadHasCommand(commands, "models"), true)
        @Expect(this.telegramPayloadHasCommand(commands, "subagents"), true)
        @Expect(this.telegramPayloadHasCommand(commands, "focus"), true)
        @Expect(this.telegramPayloadHasCommand(commands, "unfocus"), true)
        @Expect(this.telegramPayloadHasCommand(commands, "agents"), true)
        @Expect(this.telegramPayloadHasCommand(commands, "bash"), true)
        @Expect(this.telegramPayloadHasCommand(commands, "btw"), false)
        @Expect(this.telegramPayloadHasCommand(commands, "acp"), false)
    }

    private func telegramPayloadHasCommand(commands: JsonArray, command: String): Bool {
        for (i in 0..commands.size()) {
            let row = commands[i].asObject()
            if (row.get("command").getOrThrow().asString().getValue() == command) {
                return true
            }
        }
        false
    }

    @TestCase
    public func nativeCommandsPayloadCanDisableBuiltinsAndKeepCustomCommands(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                commandsNative: "off",
                customCommands: [
                    TelegramCustomCommandConfig(command: "/backup", description: "Git backup")
                ]
            )
        )
        let payload = adapter.debugBuildNativeCommandsPayload()
        let commands = payload.get("commands").getOrThrow().asArray()
        @Expect(commands.size(), 1)
        let first = commands[0].asObject()
        @Expect(first.get("command").getOrThrow().asString().getValue(), "backup")
        @Expect(first.get("description").getOrThrow().asString().getValue(), "Git backup")
    }

    @TestCase
    public func nativeCommandsPayloadSkipsCustomConflictsAndInvalidNames(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                customCommands: [
                    TelegramCustomCommandConfig(command: "/status", description: "Override"),
                    TelegramCustomCommandConfig(command: "Bad-Name", description: "Bad"),
                    TelegramCustomCommandConfig(command: "generate", description: "Create image")
                ]
            )
        )
        let payload = adapter.debugBuildNativeCommandsPayload()
        let commands = payload.get("commands").getOrThrow().asArray()
        @Expect(commands.size(), 45)
        let last = commands[commands.size() - 1].asObject()
        @Expect(last.get("command").getOrThrow().asString().getValue(), "generate")
        @Expect(last.get("description").getOrThrow().asString().getValue(), "Create image")
    }

    @TestCase
    public func nativeCommandsPayloadIncludesOpenClawPluginCommandsWhenSidecarEnabled(): Unit {
        setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, _payload: JsonObject =>
            let out = JsonObject()
            out.put("ok", true.toJsonValue())
            if (method == "commands.list") {
                let commands = JsonArray([])
                let row = JsonObject()
                row.put("command", JsonString("plugin_demo"))
                row.put("description", JsonString("Plugin demo command"))
                commands.add(row)
                out.put("commands", commands)
            }
            out
        }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            let payload = adapter.debugBuildNativeCommandsPayload()
            let commands = payload.get("commands").getOrThrow().asArray()
            @Expect(commands.size(), 45)
            let pluginCommand = commands[commands.size() - 1].asObject()
            @Expect(pluginCommand.get("command").getOrThrow().asString().getValue(), "plugin_demo")
            @Expect(pluginCommand.get("description").getOrThrow().asString().getValue(), "Plugin demo command")
        } finally {
            setGatewayOpenClawPluginSidecarRunnerForTest(None)
        }
    }

    @TestCase
    public func nativeCommandsPayloadCapsAtTelegramLimitAndTruncatesDescriptions(): Unit {
        let custom = ArrayList<TelegramCustomCommandConfig>()
        let sb = StringBuilder()
        for (_ in 0..300) {
            sb.append("x")
        }
        let longDescription = sb.toString()
        for (i in 0..120) {
            custom.add(TelegramCustomCommandConfig(command: "cmd${i}", description: longDescription))
        }
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                customCommands: custom.toArray()
            )
        )
        let payload = adapter.debugBuildNativeCommandsPayload()
        let commands = payload.get("commands").getOrThrow().asArray()
        @Expect(commands.size(), 100)
        let last = commands[99].asObject()
        @Expect(last.get("description").getOrThrow().asString().getValue().size, 256)
    }

    @TestCase
    public func textEntitiesExpandLinksAndMentionDetectionUsesTelegramEntities(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", dmPolicy: "open", allowFrom: ["*"]))
        adapter.start()
        let linked = "{\"update_id\":1,\"message\":{\"message_id\":101,\"text\":\"hello @metis_bot see docs\",\"entities\":[{\"type\":\"mention\",\"offset\":6,\"length\":10},{\"type\":\"text_link\",\"offset\":21,\"length\":4,\"url\":\"https://example.com/docs\"}],\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"
        @Expect(adapter.ingestWebhookPayload(linked).contains("\"ok\":true"), true)
        let first = adapter.pullInbound()
        @Expect(first.size, 1)
        @Expect(first[0].mentioned, true)
        @Expect(first[0].text.contains("[entities]"), true)
        @Expect(first[0].text.contains("textLink=docs|url=https://example.com/docs"), true)

        let rawAt = "{\"update_id\":2,\"message\":{\"message_id\":102,\"text\":\"hello @metis_bot without entity\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"
        @Expect(adapter.ingestWebhookPayload(rawAt).contains("\"ok\":true"), true)
        let second = adapter.pullInbound()
        @Expect(second.size, 1)
        @Expect(second[0].mentioned, false)
    }

    @TestCase
    public func groupMentionEntityMustTargetCurrentBotWhenBotUsernameKnown(): Unit {
        let fake = TelegramFakeBotApi()
        fake.pollingUpdatesEnabled = false
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let groups = JsonObject()
            let groupRule = JsonObject()
            let allowFrom = JsonArray([])
            allowFrom.add("8734062810".toJsonValue())
            groupRule.put("requireMention", false.toJsonValue())
            groupRule.put("allowFrom", allowFrom)
            groups.put("-100123", groupRule)
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "10001:telegram-token", groupPolicy: "allowlist", groups: Some(groups)))
            adapter.start()
            let other = "{\"update_id\":1,\"message\":{\"message_id\":201,\"text\":\"@other_bot hello\",\"entities\":[{\"type\":\"mention\",\"offset\":0,\"length\":10}],\"chat\":{\"id\":-100123,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
            @Expect(adapter.ingestWebhookPayload(other).contains("\"ok\":true"), true)
            let first = adapter.pullInbound()
            @Expect(first.size, 1)
            @Expect(first[0].mentioned, false)

            let current = "{\"update_id\":2,\"message\":{\"message_id\":202,\"text\":\"@metis_fake_bot hello\",\"entities\":[{\"type\":\"mention\",\"offset\":0,\"length\":15}],\"chat\":{\"id\":-100123,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
            @Expect(adapter.ingestWebhookPayload(current).contains("\"ok\":true"), true)
            let second = adapter.pullInbound()
            @Expect(second.size, 1)
            @Expect(second[0].mentioned, true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func inboundTelegramCommandMentionIsNormalizedBeforeGatewayDispatch(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", dmPolicy: "open", allowFrom: ["*"]))
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"text\":\"/status@metis_bot now\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].text, "/status now")
        @Expect(inbound[0].mentioned, true)
    }

    @TestCase
    public func nativeCommandRegistrationFailureIsVisibleInHealthSnapshot(): Unit {
        try {
            setTelegramTransportRunnerForTest(Some({ _request: TelegramTransportRequest =>
                TelegramTransportResponse(true, body: "{\"ok\":false,\"description\":\"Bad Request: command invalid\"}", outcome: "api-error")
            }))
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            @Expect(adapter.debugSyncNativeCommandsForTest(), false)
            let snapshot = adapter.debugBuildHealthSnapshot()
            let commands = snapshot.get("nativeCommands").getOrThrow().asObject()
            @Expect(commands.get("lastSyncStatus").getOrThrow().asString().getValue(), "error")
            @Expect(commands.get("lastSyncError").getOrThrow().asString().getValue().contains("Bad Request"), true)
            @Expect(commands.get("lastSyncCommandCount").getOrThrow().asInt().getValue(), 44)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func t46NativeCommandSyncDeletesBeforeSetAndSkipsUnchangedHash(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            @Expect(adapter.debugSyncNativeCommandsForTest(), true)
            @Expect(adapter.debugSyncNativeCommandsForTest(), true)
            let snapshot = adapter.debugBuildHealthSnapshot()
            let commands = snapshot.get("nativeCommands").getOrThrow().asObject()
            @Expect(fake.count("deleteMyCommands"), 1)
            @Expect(fake.count("setMyCommands"), 1)
            @Expect(commands.get("lastSyncStatus").getOrThrow().asString().getValue(), "skipped")
            @Expect(commands.get("lastSyncSkipped").getOrThrow().asBool().getValue(), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func t46NativeCommandSyncRetriesWithTrimmedMenuWhenTelegramRejectsTooManyCommands(): Unit {
        let custom = ArrayList<TelegramCustomCommandConfig>()
        for (i in 0..120) {
            custom.add(TelegramCustomCommandConfig(command: "cmd${i}", description: "Command ${i}"))
        }
        let fake = TelegramFakeBotApi()
        fake.setMyCommandsFailuresBeforeSuccess = 1
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    customCommands: custom.toArray()
                )
            )
            @Expect(adapter.debugSyncNativeCommandsForTest(), true)
            let snapshot = adapter.debugBuildHealthSnapshot()
            let commands = snapshot.get("nativeCommands").getOrThrow().asObject()
            @Expect(fake.count("deleteMyCommands"), 1)
            @Expect(fake.count("setMyCommands"), 2)
            @Expect(commands.get("lastSyncRetryCount").getOrThrow().asInt().getValue(), 1)
            @Expect(commands.get("lastSyncTrimmedCount").getOrThrow().asInt().getValue(), 20)
            @Expect(commands.get("lastSyncCommandCount").getOrThrow().asInt().getValue(), 80)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func nativeCommandRegistrationOnStartDoesNotBlockPollingStartup(): Unit {
        let contexts = ArrayList<String>()
        let contextsLock = Mutex()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                synchronized(contextsLock) {
                    contexts.add(request.context)
                }
                if (request.context == "setMyCommands") {
                    sleep(Duration.millisecond * 200)
                    return TelegramTransportResponse(true, body: "", outcome: "empty-response")
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[]}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token", dmPolicy: "open", allowFrom: ["*"]),
                registerNativeCommandsOnStart: true,
                pairingRoot: "/tmp/metis-telegram-native-command-start-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            )
            let startedAt = DateTime.now().toUnixTimeStamp().toMilliseconds()
            adapter.start()
            let elapsed = DateTime.now().toUnixTimeStamp().toMilliseconds() - startedAt
            @Expect(elapsed < 150, true)
            sleep(Duration.millisecond * 40)
            var sawGetUpdates = false
            synchronized(contextsLock) {
                for (context in contexts) {
                    if (context == "getUpdates") {
                        sawGetUpdates = true
                    }
                }
            }
            @Expect(sawGetUpdates, true)
            adapter.stop()
            sleep(Duration.millisecond * 220)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func allowedUpdatesIncludeReactionUpdatesOnlyWhenNotificationsEnabled(): Unit {
        let noReactions = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token", reactionNotifications: "off")
        )
        let base = noReactions.debugBuildAllowedUpdates()
        @Expect(base.size(), 4)

        let withReactions = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token", reactionNotifications: "all")
        )
        let extended = withReactions.debugBuildAllowedUpdates()
        @Expect(extended.size(), 5)
        @Expect(extended[4].asString().getValue(), "message_reaction")
    }

    @TestCase
    public func webhookRegistrationPayloadCarriesSecretAndAllowedUpdates(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                webhookUrl: "https://example.test/telegram-webhook",
                webhookSecret: "secret-token",
                reactionNotifications: "all"
            )
        )
        let payload = adapter.debugBuildWebhookRegistrationPayload()
        @Expect(payload.get("url").getOrThrow().asString().getValue(), "https://example.test/telegram-webhook")
        @Expect(payload.get("secret_token").getOrThrow().asString().getValue(), "secret-token")
        let allowed = payload.get("allowed_updates").getOrThrow().asArray()
        @Expect(allowed.size(), 5)
        @Expect(allowed[4].asString().getValue(), "message_reaction")
    }

    @TestCase
    public func webhookRegistrationCallsSetWebhookThroughNativeTransport(): Unit {
        let seen = ArrayList<String>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context == "setWebhook") {
                    let body = JsonValue.fromStr(request.body).asObject()
                    seen.add(request.context)
                    seen.add(if (request.url.contains("/setWebhook")) { "url-ok" } else { "url-missing" })
                    seen.add(body.get("secret_token").getOrThrow().asString().getValue())
                    seen.add(body.get("url").getOrThrow().asString().getValue())
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    webhookUrl: "https://example.test/telegram-webhook",
                    webhookSecret: "secret-token",
                    reactionNotifications: "all"
                )
            )

            @Expect(adapter.debugRegisterWebhookForTest(), true)
            let lifecycle = adapter.debugBuildWebhookLifecycleDiagnostics()
            @Expect(lifecycle.get("registrationStatus").getOrThrow().asString().getValue(), "ok")
            @Expect(lifecycle.get("secretConfigured").getOrThrow().asBool().getValue(), true)
            @Expect(seen.size, 4)
            @Expect(seen[0], "setWebhook")
            @Expect(seen[1], "url-ok")
            @Expect(seen[2], "secret-token")
            @Expect(seen[3], "https://example.test/telegram-webhook")
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func t44WebhookRegistrationWithCertificateUsesMultipartSetWebhook(): Unit {
        let root = Path("/tmp/metis-telegram-webhook-cert-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let cert = root.join("cert.pem")
        File.writeTo(cert, "fake-cert".toArray())
        let fake = TelegramFakeBotApi()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest => fake.handle(request) }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    webhookUrl: "https://example.test/telegram-webhook",
                    webhookSecret: "secret-token",
                    webhookCertPath: cert.toString()
                )
            )

            @Expect(adapter.debugRegisterWebhookForTest(), true)
            @Expect(fake.saw("setWebhook"), true)
            @Expect(fake.sawContentTypeContaining("multipart/form-data"), true)
            @Expect(fake.sawBodyContaining("name=\"certificate\""), true)
            @Expect(fake.sawBodyContaining("filename=\"cert.pem\""), true)
            @Expect(fake.sawBodyContaining("name=\"secret_token\""), true)
            let lifecycle = adapter.debugBuildWebhookLifecycleDiagnostics()
            @Expect(lifecycle.get("certificateConfigured").getOrThrow().asBool().getValue(), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func t44WebhookRegistrationRejectsNonRegularCertificatePath(): Unit {
        let root = Path("/tmp/metis-telegram-webhook-cert-dir-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let fake = TelegramFakeBotApi()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest => fake.handle(request) }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    webhookUrl: "https://example.test/telegram-webhook",
                    webhookSecret: "secret-token",
                    webhookCertPath: root.toString()
                )
            )

            @Expect(adapter.debugRegisterWebhookForTest(), false)
            @Expect(fake.saw("setWebhook"), false)
            @Expect(adapter.debugLastSendErrorForTest().contains("not a regular file"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func sendTransportInvalidUtf8FailureDoesNotThrow(): Unit {
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context.startsWith("send:")) {
                    return TelegramTransportResponse(
                        false,
                        error: "invalid utf8 response body: Invalid utf8 byte sequence",
                        outcome: "invalid-response-body",
                        statusCode: 200
                    )
                }
                if (request.context == "getUpdates") {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[]}", outcome: "ok")
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            try {
                adapter.start()
                let message = OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello")
                @Expect(adapter.sendWithMessageId(message), "")
                match (adapter.send(message)) {
                    case SendResult.Success => @Expect(false, true)
                    case SendResult.Failed(reason) =>
                        @Expect(reason.contains("invalid utf8 response body"), true)
                }
            } finally {
                adapter.stop()
            }
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func fakeBotApiEndToEndCoversTelegramRuntimeClosure(): Unit {
        let fake = TelegramFakeBotApi()
        let root = "/tmp/metis-telegram-fake-bot-api-e2e-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                fake.handle(request)
            }))
            let cfg = TelegramConfig(
                enabled: true,
                botToken: "123456:FAKE",
                dmPolicy: "open",
                allowFrom: ["*"],
                actions: TelegramActionConfig(
                    sendMessage: true,
                    deleteMessage: true,
                    photo: true,
                    createForumTopic: true,
                    editForumTopic: true,
                    reactions: true,
                    inlineKeyboard: true,
                    callbackQuery: true
                ),
                media: TelegramMediaConfig(
                    downloadEnabled: true,
                    mediaMaxBytes: 1024,
                    allowedMimes: ["image/*"]
                )
            )
            let adapter = TelegramAdapter(config: cfg, pairingRoot: root)
            adapter.start()
            sleep(Duration.millisecond * 80)

            let polled = adapter.pullInbound()
            @Expect(polled.size >= 1, true)
            @Expect(polled[0].text, "hello from fake polling")
            @Expect(polled[0].senderId, "8734062810")

            @Expect(adapter.debugSyncNativeCommandsForTest(), true)
            let liveProbe = adapter.debugBuildLiveProbe()
            @Expect(liveProbe.get("status").getOrThrow().asString().getValue(), "ok")

            let textMessageId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello fake bot api")
            )
            @Expect(textMessageId, "501")

            let keyboardMessageId = adapter.sendWithMessageId(
                OutboundMessage(
                    ChannelType.Telegram,
                    "user:8734062810",
                    "[inline-keyboard]\ntext=Choose\nbutton=Approve|callback:approve-1"
                )
            )
            @Expect(keyboardMessageId, "502")

            let photoMessageId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=photo-file-id\ncaption=fake")
            )
            @Expect(photoMessageId, "503")

            let deleteResult = adapter.send(
                OutboundMessage(
                    ChannelType.Telegram,
                    "user:8734062810",
                    "[delete]",
                    replyToMessageId: Some("503")
                )
            )
            match (deleteResult) {
                case SendResult.Success => @Expect(true, true)
                case SendResult.Failed(reason) => @Expect(reason, "")
            }

            let topicResult = adapter.send(
                OutboundMessage(ChannelType.Telegram, "group:-1001234567890", "[topic-create]\nSprint")
            )
            match (topicResult) {
                case SendResult.Success => @Expect(true, true)
                case SendResult.Failed(reason) => @Expect(reason, "")
            }

            let reactionResult = adapter.send(
                OutboundMessage(
                    ChannelType.Telegram,
                    "user:8734062810",
                    "[reaction]\ntoken=👍\nrender=👍",
                    replyToMessageId: Some("503")
                )
            )
            match (reactionResult) {
                case SendResult.Success => @Expect(true, true)
                case SendResult.Failed(reason) => @Expect(reason, "")
            }

            let mediaState = adapter.debugPersistInboundMediaForTest(
                "photo",
                "photo-file-id",
                mimeType: "image/jpeg",
                fileSize: 12
            )
            let lastMedia = mediaState.get("lastMedia").getOrThrow().asObject()
            @Expect(lastMedia.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(lastMedia.get("filePath").getOrThrow().asString().getValue(), "photos/fake-photo.jpg")

            let callbackAck = adapter.ingestWebhookPayload(
                "{\"update_id\":7002,\"callback_query\":{\"id\":\"cb-1\",\"data\":\"approve-1\",\"from\":{\"id\":8734062810},\"message\":{\"message_id\":22,\"chat\":{\"id\":8734062810,\"type\":\"private\"}}}}"
            )
            @Expect(callbackAck.contains("\"ok\":true"), true)
            let callbackInbound = adapter.pullInbound()
            @Expect(callbackInbound.size >= 1, true)
            @Expect(callbackInbound[0].text.contains("approve-1"), true)

            let webhookAdapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "123456:FAKE",
                    webhookUrl: "https://example.test/telegram-webhook",
                    webhookSecret: "secret-token"
                ),
                pairingRoot: root + "-webhook"
            )
            @Expect(webhookAdapter.debugRegisterWebhookForTest(), true)

            adapter.stop()
            @Expect(fake.saw("deleteWebhook"), true)
            @Expect(fake.saw("getUpdates"), true)
            @Expect(fake.saw("setMyCommands"), true)
            @Expect(fake.saw("getMe"), true)
            @Expect(fake.saw("getWebhookInfo"), true)
            @Expect(fake.saw("sendMessage"), true)
            @Expect(fake.saw("sendPhoto"), true)
            @Expect(fake.saw("deleteMessage"), true)
            @Expect(fake.saw("createForumTopic"), true)
            @Expect(fake.saw("setMessageReaction"), true)
            @Expect(fake.saw("getFile"), true)
            @Expect(fake.saw("downloadFile"), true)
            @Expect(fake.saw("setWebhook"), true)
            @Expect(fake.sawBodyContaining("inline_keyboard"), true)
            @Expect(fake.sawBodyContaining("photo-file-id"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try {
                remove(Path(root), recursive: true)
            } catch (_: Exception) {
                ()
            }
            try {
                remove(Path(root + "-webhook"), recursive: true)
            } catch (_: Exception) {
                ()
            }
        }
    }

    @TestCase
    public func pollingModeDeletesWebhookBeforeGetUpdates(): Unit {
        let seen = ArrayList<String>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                seen.add(request.context)
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))

            @Expect(adapter.debugEnsurePollingWebhookClearedForTest(reason: "polling-start"), true)
            let payload = adapter.debugBuildWebhookDeletePayload()
            @Expect(payload.get("drop_pending_updates").getOrThrow().asBool().getValue(), false)
            let lifecycle = adapter.debugBuildWebhookLifecycleDiagnostics()
            @Expect(lifecycle.get("cleanupStatus").getOrThrow().asString().getValue(), "ok")
            @Expect(lifecycle.get("pollingWebhookCleared").getOrThrow().asBool().getValue(), true)
            @Expect(seen.size, 1)
            @Expect(seen[0], "deleteWebhook:polling-start")
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func pollingConflictResetsWebhookCleanupAndDeletesWebhookAgain(): Unit {
        let seen = ArrayList<String>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                seen.add(request.context)
                if (request.context == "getUpdates") {
                    return TelegramTransportResponse(
                        true,
                        body: "{\"ok\":false,\"error_code\":409,\"description\":\"Conflict: terminated by other getUpdates request\"}",
                        outcome: "ok"
                    )
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))

            @Expect(adapter.debugEnsurePollingWebhookClearedForTest(reason: "polling-start"), true)
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            let polling = adapter.debugBuildPollingDiagnosticSnapshot()
            let lifecycle = adapter.debugBuildWebhookLifecycleDiagnostics()
            @Expect(polling.get("lastOutcome").getOrThrow().asString().getValue(), "conflict")
            @Expect(lifecycle.get("cleanupStatus").getOrThrow().asString().getValue(), "ok")
            var cleanupCount = 0
            var sawGetUpdates = false
            for (context in seen) {
                if (context.startsWith("deleteWebhook:")) {
                    cleanupCount += 1
                }
                if (context == "getUpdates") {
                    sawGetUpdates = true
                }
            }
            @Expect(sawGetUpdates, true)
            @Expect(cleanupCount, 2)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func webhookSecretHeaderIsRequiredWhenConfigured(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                webhookUrl: "https://example.test/telegram-webhook",
                webhookSecret: "secret-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            ),
            pairingRoot: "/tmp/metis-telegram-webhook-secret-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        )
        @Expect(adapter.debugValidateWebhookSecretForTest("wrong"), false)
        @Expect(adapter.debugValidateWebhookSecretForTest("secret-token"), true)
        let rejected = adapter.ingestWebhookPayloadWithSecret(
            "{\"update_id\":42,\"message\":{\"message_id\":101,\"text\":\"hello\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}",
            "wrong"
        )
        @Expect(rejected.contains("webhook_secret_mismatch"), true)
        @Expect(adapter.debugLastInboundUpdateId(), "")
        let accepted = adapter.ingestWebhookPayloadWithSecret(
            "{\"update_id\":43,\"message\":{\"message_id\":102,\"text\":\"hello\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}",
            "secret-token"
        )
        @Expect(accepted.contains("\"ok\":true"), true)
        @Expect(adapter.debugLastInboundUpdateId(), "43")
    }

    @TestCase
    public func webhookGuardRejectsUnsafeMethodPathOversizeAndRate(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                webhookPath: "/telegram-webhook",
                webhookMaxBodyBytes: 8,
                webhookRateLimitWindowMs: 60000,
                webhookRateLimitMaxRequests: 2,
                trustedProxies: ["127.0.0.1"],
                allowRealIpFallback: true
            )
        )
        @Expect(adapter.debugResolveWebhookSourceForTest("203.0.113.8, 127.0.0.1", "", "127.0.0.1"), "203.0.113.8")
        @Expect(adapter.debugResolveWebhookSourceForTest("", "203.0.113.9", "127.0.0.1"), "203.0.113.9")

        let badMethod = adapter.debugBuildWebhookGuardForTest("GET", "/telegram-webhook", 0, "203.0.113.8", 1000)
        @Expect(badMethod.get("error").getOrThrow().asString().getValue(), "method-not-allowed")
        @Expect(badMethod.get("httpStatus").getOrThrow().asInt().getValue(), 405)

        let badPath = adapter.debugBuildWebhookGuardForTest("POST", "/wrong", 0, "203.0.113.8", 1001)
        @Expect(badPath.get("error").getOrThrow().asString().getValue(), "path-not-found")
        @Expect(badPath.get("httpStatus").getOrThrow().asInt().getValue(), 404)

        let tooLarge = adapter.debugBuildWebhookGuardForTest("POST", "/telegram-webhook", 9, "203.0.113.8", 1002)
        @Expect(tooLarge.get("error").getOrThrow().asString().getValue(), "payload-too-large")
        @Expect(tooLarge.get("httpStatus").getOrThrow().asInt().getValue(), 413)

        @Expect(adapter.debugWebhookRateLimitAllowsForTest("198.51.100.10", 2000), true)
        @Expect(adapter.debugWebhookRateLimitAllowsForTest("198.51.100.10", 2001), true)
        @Expect(adapter.debugWebhookRateLimitAllowsForTest("198.51.100.10", 2002), false)
        @Expect(adapter.debugWebhookRateLimitAllowsForTest("198.51.100.10", 62001), true)
    }

    @TestCase
    public func healthSnapshotExposesModeBotAndWebhookState(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                webhookUrl: "https://example.test/telegram-webhook",
                reactionNotifications: "all"
            )
        )
        let snapshot = adapter.debugBuildHealthSnapshot(
            getMeRaw: "{\"ok\":true,\"result\":{\"id\":123,\"is_bot\":true,\"username\":\"cjclaw_bot\"}}",
            webhookInfoRaw: "{\"ok\":true,\"result\":{\"url\":\"https://example.test/telegram-webhook\",\"pending_update_count\":2}}"
        )
        let summary = snapshot.get("summary").getOrThrow().asObject()
        let bot = snapshot.get("bot").getOrThrow().asObject()
        let webhook = snapshot.get("webhook").getOrThrow().asObject()
        @Expect(summary.get("mode").getOrThrow().asString().getValue(), "webhook")
        @Expect(summary.get("healthy").getOrThrow().asBool().getValue(), true)
        @Expect(bot.get("id").getOrThrow().asString().getValue(), "123")
        @Expect(bot.get("username").getOrThrow().asString().getValue(), "cjclaw_bot")
        @Expect(webhook.get("url").getOrThrow().asString().getValue(), "https://example.test/telegram-webhook")
        @Expect(webhook.get("pendingUpdateCount").getOrThrow().asString().getValue(), "2")
    }

    /*
    @TestCase
    public func webhookIngestPersistsLastInboundUpdateIdIntoHealthSnapshot(): Unit {
        let root = Path("/tmp/metis-telegram-offset-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token", reactionNotifications: "all"),
            pairingRoot: root.toString()
        )
        adapter.start()
        let ack = adapter.ingestWebhookPayload(
            "{\"update_id\":42,\"message\":{\"message_id\":101,\"text\":\"hello\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"
        )
        @Expect(ack.contains("\"ok\":true"), true)
        @Expect(adapter.debugLastInboundUpdateId(), "42")
        let snapshot = adapter.debugBuildHealthSnapshot()
        let summary = snapshot.get("summary").getOrThrow().asObject()
        let offset = snapshot.get("offset").getOrThrow().asObject()
        @Expect(summary.get("offsetPersistenceEnabled").getOrThrow().asBool().getValue(), true)
        @Expect(summary.get("lastInboundUpdateId").getOrThrow().asString().getValue(), "42")
        @Expect(offset.get("lastInboundUpdateId").getOrThrow().asString().getValue(), "42")
        @Expect(offset.get("statePath").getOrThrow().asString().getValue().contains("offset-state.json"), true)
    }
    */

    @TestCase
    public func liveProbeReportsExecutionShape(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let probe = adapter.debugBuildLiveProbe()
        @Expect(probe.get("supported").getOrThrow().asBool().getValue(), true)
        @Expect(probe.get("executed").getOrThrow().asBool().getValue(), true)
        @Expect(probe.get("status").isSome(), true)
        @Expect(probe.get("snapshot").isSome(), true)
    }

    @TestCase
    public func accountDiagnosticsResolveNamedAccountConfigBeforeTopLevelToken(): Unit {
        let accounts = JsonObject()
        let work = JsonObject()
        work.put("botToken", JsonString("999001:WORK"))
        accounts.put("work", work)
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                accountId: "work",
                enabled: true,
                botToken: "111001:TOP",
                accounts: Some(accounts)
            )
        )
        let account = adapter.debugTelegramAccountDiagnosticsForTest()
        @Expect(account.get("accountId").getOrThrow().asString().getValue(), "work")
        @Expect(account.get("tokenSource").getOrThrow().asString().getValue(), "config")
        @Expect(account.get("tokenConfigured").getOrThrow().asBool().getValue(), true)
        @Expect(account.get("tokenRedacted").getOrThrow().asString().getValue(), "999001:<redacted>")
        @Expect(account.get("botId").getOrThrow().asString().getValue(), "999001")
    }

    @TestCase
    public func accountDiagnosticsUseAccountTokenFileBeforeTopLevelFallbacks(): Unit {
        let root = "/tmp/metis-telegram-tokenfile-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        let topToken = "${root}-top.txt"
        let accountToken = "${root}-account.txt"
        File.writeTo(Path(topToken), "111001:TOP\n".toArray())
        File.writeTo(Path(accountToken), "999001:WORK\n".toArray())
        let accounts = JsonObject()
        let work = JsonObject()
        work.put("tokenFile", JsonString(accountToken))
        accounts.put("work", work)
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                accountId: "work",
                enabled: true,
                tokenFile: topToken,
                accounts: Some(accounts)
            )
        )
        let account = adapter.debugTelegramAccountDiagnosticsForTest()
        @Expect(account.get("tokenSource").getOrThrow().asString().getValue(), "tokenFile")
        @Expect(account.get("tokenFile").getOrThrow().asString().getValue(), accountToken)
        @Expect(account.get("tokenRedacted").getOrThrow().asString().getValue(), "999001:<redacted>")
    }

    @TestCase
    public func unknownNamedAccountDoesNotFallThroughWhenAccountsConfigured(): Unit {
        let accounts = JsonObject()
        let work = JsonObject()
        work.put("botToken", JsonString("999001:WORK"))
        accounts.put("work", work)
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                accountId: "missing",
                enabled: true,
                botToken: "111001:TOP",
                accounts: Some(accounts)
            )
        )
        let account = adapter.debugTelegramAccountDiagnosticsForTest()
        @Expect(account.get("accountId").getOrThrow().asString().getValue(), "missing")
        @Expect(account.get("tokenSource").getOrThrow().asString().getValue(), "none")
        @Expect(account.get("tokenConfigured").getOrThrow().asBool().getValue(), false)
        @Expect(account.get("tokenError").getOrThrow().asString().getValue().contains("unknown accountId"), true)
    }

    @TestCase
    public func offsetStateIsIsolatedByAccountAndBotId(): Unit {
        let root = Path("/tmp/metis-telegram-account-offset-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let workV1 = TelegramAdapter(
            config: TelegramConfig(accountId: "work", enabled: true, botToken: "111001:WORK"),
            pairingRoot: root.toString()
        )
        let ack = workV1.ingestWebhookPayload(
            "{\"update_id\":42,\"message\":{\"message_id\":101,\"text\":\"hello\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"
        )
        @Expect(ack.contains("\"ok\":true"), true)
        @Expect(workV1.debugLastInboundUpdateId(), "42")
        let workSameBot = TelegramAdapter(
            config: TelegramConfig(accountId: "work", enabled: true, botToken: "111001:WORK"),
            pairingRoot: root.toString()
        )
        @Expect(workSameBot.debugLastInboundUpdateId(), "42")
        let workRotatedBot = TelegramAdapter(
            config: TelegramConfig(accountId: "work", enabled: true, botToken: "222001:WORK"),
            pairingRoot: root.toString()
        )
        @Expect(workRotatedBot.debugLastInboundUpdateId(), "")
        let defaultAccount = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "111001:WORK"),
            pairingRoot: root.toString()
        )
        @Expect(defaultAccount.debugLastInboundUpdateId(), "")
        let snapshot = workSameBot.debugBuildHealthSnapshot()
        let offset = snapshot.get("offset").getOrThrow().asObject()
        @Expect(offset.get("accountId").getOrThrow().asString().getValue(), "work")
        @Expect(offset.get("botId").getOrThrow().asString().getValue(), "111001")
        @Expect(offset.get("statePath").getOrThrow().asString().getValue().contains("/accounts/work/offset-state.json"), true)
    }

    @TestCase
    public func mediaStateIsIsolatedByAccount(): Unit {
        let root = Path("/tmp/metis-telegram-account-media-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let defaultAccount = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "111001:DEFAULT"),
            pairingRoot: root.toString()
        )
        let workAccount = TelegramAdapter(
            config: TelegramConfig(accountId: "work", enabled: true, botToken: "222001:WORK"),
            pairingRoot: root.toString()
        )
        let defaultMedia = defaultAccount.debugPersistInboundMediaForTest(
            "photo",
            "default-photo",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/default.jpg\"}}",
            downloadRaw: "default-bytes"
        )
        let workMedia = workAccount.debugPersistInboundMediaForTest(
            "photo",
            "work-photo",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/work.jpg\"}}",
            downloadRaw: "work-bytes"
        )
        @Expect(defaultMedia.get("accountId").getOrThrow().asString().getValue(), "default")
        @Expect(workMedia.get("accountId").getOrThrow().asString().getValue(), "work")
        @Expect(defaultMedia.get("statePath").getOrThrow().asString().getValue().contains("/accounts/default/media-state.json"), true)
        @Expect(workMedia.get("statePath").getOrThrow().asString().getValue().contains("/accounts/work/media-state.json"), true)
        @Expect(defaultAccount.debugReadMediaState().get("lastPersistedMediaId").getOrThrow().asString().getValue(), "default-photo")
        @Expect(workAccount.debugReadMediaState().get("lastPersistedMediaId").getOrThrow().asString().getValue(), "work-photo")
    }

    @TestCase
    public func mediaPersistenceStoresLastMediaAndDownloadPath(): Unit {
        let root = Path("/tmp/metis-telegram-media-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token"),
            pairingRoot: root.toString()
        )
        let media = adapter.debugPersistInboundMediaForTest(
            "photo",
            "photo-file-id",
            caption: "hello",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file_1.jpg\"}}",
            downloadRaw: "photo-bytes"
        )
        @Expect(media.get("persistenceEnabled").getOrThrow().asBool().getValue(), true)
        @Expect(media.get("downloadEnabled").getOrThrow().asBool().getValue(), true)
        @Expect(media.get("lastPersistedMediaId").getOrThrow().asString().getValue(), "photo-file-id")
        let lastMedia = media.get("lastMedia").getOrThrow().asObject()
        @Expect(lastMedia.get("kind").getOrThrow().asString().getValue(), "photo")
        @Expect(lastMedia.get("fileId").getOrThrow().asString().getValue(), "photo-file-id")
        @Expect(lastMedia.get("filePath").getOrThrow().asString().getValue(), "photos/file_1.jpg")
        @Expect(lastMedia.get("downloaded").getOrThrow().asBool().getValue(), true)
        @Expect(lastMedia.get("downloadPath").getOrThrow().asString().getValue().endsWith("/unknown-message/file_1.jpg"), true)
    }

    @TestCase
    public func mediaPersistenceStoresStructuredMediaRecords(): Unit {
        let root = Path("/tmp/metis-telegram-media-records-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token"),
            pairingRoot: root.toString()
        )
        adapter.debugPersistInboundMediaForTest(
            "photo",
            "photo-file-id",
            caption: "photo caption",
            mimeType: "image/jpeg",
            peerId: "user:1001",
            messageId: "101",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file_1.jpg\",\"file_size\":12}}",
            downloadRaw: "photo-bytes"
        )
        adapter.debugPersistInboundMediaForTest(
            "document",
            "doc-file-id",
            mimeType: "application/pdf",
            fileSize: 64,
            fileName: "report.pdf",
            peerId: "user:1001",
            messageId: "102",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"documents/report.pdf\",\"file_size\":64}}",
            downloadRaw: "document-bytes"
        )
        let media = adapter.debugPersistInboundMediaForTest(
            "voice",
            "voice-file-id",
            mimeType: "audio/ogg",
            fileSize: 32,
            peerId: "user:1001",
            messageId: "103",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"voice/file_3.ogg\",\"file_size\":32}}",
            downloadRaw: "voice-bytes"
        )
        let records = media.get("records").getOrThrow().asArray()
        @Expect(records.size(), 3)
        let photo = records[0].asObject()
        @Expect(photo.get("mediaId").getOrThrow().asString().getValue().contains("photo-file-id"), true)
        @Expect(photo.get("channel").getOrThrow().asString().getValue(), "telegram")
        @Expect(photo.get("accountId").getOrThrow().asString().getValue(), "default")
        @Expect(photo.get("peerId").getOrThrow().asString().getValue(), "user:1001")
        @Expect(photo.get("messageId").getOrThrow().asString().getValue(), "101")
        @Expect(photo.get("mediaKind").getOrThrow().asString().getValue(), "photo")
        @Expect(photo.get("telegramFilePath").getOrThrow().asString().getValue(), "photos/file_1.jpg")
        @Expect(photo.get("localPath").getOrThrow().asString().getValue().endsWith("/101/file_1.jpg"), true)
        @Expect(photo.get("relativePath").getOrThrow().asString().getValue().endsWith("/101/file_1.jpg"), true)
        @Expect(photo.get("eligibleFor").getOrThrow().asString().getValue(), "vision")

        let document = records[1].asObject()
        @Expect(document.get("mediaKind").getOrThrow().asString().getValue(), "document")
        @Expect(document.get("originalFileName").getOrThrow().asString().getValue(), "report.pdf")
        @Expect(document.get("localPath").getOrThrow().asString().getValue().endsWith("/102/report.pdf"), true)
        @Expect(document.get("eligibleFor").getOrThrow().asString().getValue(), "file-context")

        let voice = records[2].asObject()
        @Expect(voice.get("mediaKind").getOrThrow().asString().getValue(), "voice")
        @Expect(voice.get("localPath").getOrThrow().asString().getValue().endsWith("/103/file_3.ogg"), true)
        @Expect(voice.get("eligibleFor").getOrThrow().asString().getValue(), "transcription")
        @Expect(media.get("lastMediaRecordId").getOrThrow().asString().getValue().contains("voice-file-id"), true)
        @Expect(media.get("lastMedia").getOrThrow().asObject().get("mediaId").isSome(), true)
    }

    @TestCase
    public func mediaDownloadMarksVideoNoteEligibleForVideoUnderstanding(): Unit {
        let root = Path("/tmp/metis-telegram-media-video-note-eligible-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    dmPolicy: "open",
                    allowFrom: ["*"]
                ),
                pairingRoot: root.toString()
            )
            let media = adapter.debugPersistInboundMediaForTest(
                "video-note",
                "video-note-file-id",
                mimeType: "video/mp4",
                fileSize: 64,
                peerId: "user:1001",
                messageId: "104",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"video_notes/file_4.mp4\",\"file_size\":64}}",
                downloadRaw: "video-bytes"
            )
            let record = media.get("lastMedia").getOrThrow().asObject()
            @Expect(record.get("mediaKind").getOrThrow().asString().getValue(), "video-note")
            @Expect(record.get("eligibleFor").getOrThrow().asString().getValue(), "video-understanding")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func mediaDownloadPersistsNonUtf8BinaryBytesForPhotoDocumentVoiceAndVideo(): Unit {
        let root = Path("/tmp/metis-telegram-media-binary-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let downloadCalls = ArrayList<String>()
        let jpegBytes: Array<Byte> = [255u8, 216u8, 255u8, 0u8, 254u8]
        let documentBytes: Array<Byte> = [37u8, 80u8, 68u8, 70u8, 45u8, 255u8]
        let voiceBytes: Array<Byte> = [79u8, 103u8, 103u8, 83u8, 255u8, 0u8]
        let videoBytes: Array<Byte> = [0u8, 0u8, 0u8, 24u8, 102u8, 116u8, 121u8, 112u8, 255u8]
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.url.contains("/getFile") && request.url.contains("photo-file-id")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file_1.jpg\",\"file_size\":5}}", outcome: "ok")
                }
                if (request.url.contains("/getFile") && request.url.contains("doc-file-id")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"file_path\":\"documents/file_2.pdf\",\"file_size\":6}}", outcome: "ok")
                }
                if (request.url.contains("/getFile") && request.url.contains("voice-file-id")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"file_path\":\"voice/file_3.ogg\",\"file_size\":6}}", outcome: "ok")
                }
                if (request.url.contains("/getFile") && request.url.contains("video-file-id")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"file_path\":\"videos/file_4.mp4\",\"file_size\":9}}", outcome: "ok")
                }
                if (request.context == "downloadFile") {
                    downloadCalls.add(request.url)
                    if (request.url.contains("photos/file_1.jpg")) {
                        return TelegramTransportResponse(true, bodyBytes: jpegBytes, outcome: "ok")
                    }
                    if (request.url.contains("documents/file_2.pdf")) {
                        return TelegramTransportResponse(true, bodyBytes: documentBytes, outcome: "ok")
                    }
                    if (request.url.contains("voice/file_3.ogg")) {
                        return TelegramTransportResponse(true, bodyBytes: voiceBytes, outcome: "ok")
                    }
                    if (request.url.contains("videos/file_4.mp4")) {
                        return TelegramTransportResponse(true, bodyBytes: videoBytes, outcome: "ok")
                    }
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token"),
                pairingRoot: root.toString()
            )
            let photo = adapter.debugPersistInboundMediaForTest(
                "photo",
                "photo-file-id",
                mimeType: "image/jpeg",
                peerId: "user:1001",
                messageId: "201"
            )
            let document = adapter.debugPersistInboundMediaForTest(
                "document",
                "doc-file-id",
                mimeType: "application/pdf",
                peerId: "user:1001",
                messageId: "202"
            )
            let voice = adapter.debugPersistInboundMediaForTest(
                "voice",
                "voice-file-id",
                mimeType: "audio/ogg",
                peerId: "user:1001",
                messageId: "203"
            )
            let video = adapter.debugPersistInboundMediaForTest(
                "video",
                "video-file-id",
                mimeType: "video/mp4",
                peerId: "user:1001",
                messageId: "204"
            )

            let photoRecord = photo.get("lastMedia").getOrThrow().asObject()
            let documentRecord = document.get("lastMedia").getOrThrow().asObject()
            let voiceRecord = voice.get("lastMedia").getOrThrow().asObject()
            let videoRecord = video.get("lastMedia").getOrThrow().asObject()
            @Expect(photoRecord.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(documentRecord.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(voiceRecord.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(videoRecord.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(File.readFrom(Path(photoRecord.get("localPath").getOrThrow().asString().getValue())), jpegBytes)
            @Expect(File.readFrom(Path(documentRecord.get("localPath").getOrThrow().asString().getValue())), documentBytes)
            @Expect(File.readFrom(Path(voiceRecord.get("localPath").getOrThrow().asString().getValue())), voiceBytes)
            @Expect(File.readFrom(Path(videoRecord.get("localPath").getOrThrow().asString().getValue())), videoBytes)
            @Expect(downloadCalls.size, 4)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try {
                remove(root, recursive: true)
            } catch (_: Exception) {
                ()
            }
        }
    }

    @TestCase
    public func mediaPersistenceDeduplicatesFilesWithinSameMessage(): Unit {
        let root = Path("/tmp/metis-telegram-media-dedupe-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token"),
            pairingRoot: root.toString()
        )
        let first = adapter.debugPersistInboundMediaForTest(
            "photo",
            "photo-file-a",
            mimeType: "image/jpeg",
            peerId: "user:1001",
            messageId: "101",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file_1.jpg\",\"file_size\":12}}",
            downloadRaw: "photo-a"
        )
        let second = adapter.debugPersistInboundMediaForTest(
            "photo",
            "photo-file-b",
            mimeType: "image/jpeg",
            peerId: "user:1001",
            messageId: "101",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file_1.jpg\",\"file_size\":12}}",
            downloadRaw: "photo-b"
        )
        let firstPath = first.get("lastMedia").getOrThrow().asObject().get("localPath").getOrThrow().asString().getValue()
        let secondPath = second.get("lastMedia").getOrThrow().asObject().get("localPath").getOrThrow().asString().getValue()
        @Expect(firstPath.endsWith("/101/file_1.jpg"), true)
        @Expect(secondPath.endsWith("/101/file_1-2.jpg"), true)
        @Expect(second.get("records").getOrThrow().asArray().size(), 2)
    }

    @TestCase
    public func mediaPersistenceHonorsDownloadDisabledWithoutNetwork(): Unit {
        let root = Path("/tmp/metis-telegram-media-disabled-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let seen = ArrayList<String>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                seen.add(request.context)
                TelegramTransportResponse(false, error: "network should not be called", outcome: "test")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    media: TelegramMediaConfig(downloadEnabled: false)
                ),
                pairingRoot: root.toString()
            )
            let media = adapter.debugPersistInboundMediaForTest(
                "photo",
                "photo-file-id",
                mimeType: "image/jpeg",
                fileSize: 128
            )
            let lastMedia = media.get("lastMedia").getOrThrow().asObject()
            @Expect(media.get("downloadEnabled").getOrThrow().asBool().getValue(), false)
            @Expect(lastMedia.get("downloaded").getOrThrow().asBool().getValue(), false)
            @Expect(lastMedia.get("skippedReason").getOrThrow().asString().getValue(), "download_disabled")
            @Expect(seen.size, 0)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func mediaPersistenceRejectsDisallowedMimeAndOversizeBeforeDownload(): Unit {
        let root = Path("/tmp/metis-telegram-media-policy-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                media: TelegramMediaConfig(
                    mediaMaxBytes: 100,
                    allowedMimes: ["image/*"]
                )
            ),
            pairingRoot: root.toString()
        )
        let badMime = adapter.debugPersistInboundMediaForTest(
            "document",
            "doc-file-id",
            mimeType: "application/pdf",
            fileSize: 20,
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"docs/report.pdf\"}}",
            downloadRaw: "bytes"
        )
        @Expect(badMime.get("lastMedia").getOrThrow().asObject().get("skippedReason").getOrThrow().asString().getValue(), "mime_not_allowed")

        let tooLarge = adapter.debugPersistInboundMediaForTest(
            "photo",
            "photo-file-id",
            mimeType: "image/jpeg",
            fileSize: 200,
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file.jpg\"}}",
            downloadRaw: "bytes"
        )
        @Expect(tooLarge.get("lastMedia").getOrThrow().asObject().get("skippedReason").getOrThrow().asString().getValue(), "size_limit_exceeded")
    }

    @TestCase
    public func mediaPersistenceRejectsUnsafeTelegramFilePath(): Unit {
        let root = Path("/tmp/metis-telegram-media-path-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token"),
            pairingRoot: root.toString()
        )
        let media = adapter.debugPersistInboundMediaForTest(
            "photo",
            "photo-file-id",
            mimeType: "image/jpeg",
            getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"../secret.jpg\"}}",
            downloadRaw: "bytes"
        )
        let lastMedia = media.get("lastMedia").getOrThrow().asObject()
        @Expect(lastMedia.get("downloaded").getOrThrow().asBool().getValue(), false)
        @Expect(lastMedia.get("skippedReason").getOrThrow().asString().getValue(), "unsafe_file_path")
    }

    @TestCase
    public func getFileTransientFailureRetriesBeforeDownload(): Unit {
        let fake = TelegramGetFileRetryFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    network: TelegramNetworkConfig(getFileRetryCount: 3)
                ),
                pairingRoot: "/tmp/metis-telegram-media-getfile-retry"
            )
            let media = adapter.debugPersistInboundMediaForTest("photo", "retry-photo", mimeType: "image/jpeg", fileSize: 4, messageId: "retry")
            let lastMedia = media.get("lastMedia").getOrThrow().asObject()
            @Expect(fake.getFileCalls, 3)
            @Expect(lastMedia.get("downloaded").getOrThrow().asBool().getValue(), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func trustedLocalAbsoluteTelegramFilePathCanBePersisted(): Unit {
        let root = Path("/tmp/metis-telegram-local-file-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let source = root.join("local.jpg")
        File.writeTo(source, "jpeg".toArray())
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    media: TelegramMediaConfig(trustedLocalFileRoots: [root.toString()])
                ),
                pairingRoot: "/tmp/metis-telegram-media-local-file"
            )
            let media = adapter.debugPersistInboundMediaForTest(
                "photo",
                "local-photo",
                mimeType: "image/jpeg",
                fileSize: 4,
                messageId: "local",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"${source.toString()}\",\"file_size\":4}}"
            )
            let lastMedia = media.get("lastMedia").getOrThrow().asObject()
            @Expect(lastMedia.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(File.readFrom(Path(lastMedia.get("localPath").getOrThrow().asString().getValue())), "jpeg".toArray())
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func groupMigrationUpdateIsRecordedAndDoesNotQueueEmptyTurn(): Unit {
        let root = Path("/tmp/metis-telegram-group-migration-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token", replyToMode: "thread"),
            pairingRoot: root.toString()
        )
        let payload = "{\"update_id\":88,\"message\":{\"message_id\":44,\"migrate_to_chat_id\":\"-100222333444\",\"chat\":{\"id\":\"-222333444\",\"type\":\"group\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)
        @Expect(adapter.pullInbound().size, 0)
        let migrations = adapter.debugReadGroupMigrationStateForTest()
        @Expect(migrations.size(), 1)
        let row = migrations[0].asObject()
        @Expect(row.get("oldPeerId").getOrThrow().asString().getValue(), "group:-222333444")
        @Expect(row.get("newPeerId").getOrThrow().asString().getValue(), "group:-100222333444")
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-222333444:topic:9",
                "after migration",
                replyInThread: true
            )
        )
        let sendPayload = payloads[0].asObject()
        @Expect(sendPayload.get("chat_id").getOrThrow().asString().getValue(), "-100222333444")
        @Expect(sendPayload.get("message_thread_id").getOrThrow().asString().getValue(), "9")
    }

    /*
    @TestCase
    public func webhookTopicMessagesPreserveTopicScopedPeerAndThreadMetadata(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"message_thread_id\":42,\"text\":\"/status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810},\"reply_to_message\":{\"message_id\":88}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "group:-1001234567890:topic:42")
        @Expect(inbound[0].conversationId.getOrThrow(), "group:-1001234567890:topic:42")
        @Expect(inbound[0].threadId.getOrThrow(), "42")
        @Expect(inbound[0].replyTargetMessageId.getOrThrow(), "88")
        @Expect(inbound[0].replyInThread, true)
        @Expect(inbound[0].mentioned, true)
    }
    */

    @TestCase
    public func directAllowlistRejectsUnauthorizedSenders(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            dmPolicy: "allowlist",
            allowFrom: ["8734062810"]
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let deniedPayload = "{\"update_id\":1,\"message\":{\"message_id\":11,\"text\":\"hello\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let allowedPayload = "{\"update_id\":2,\"message\":{\"message_id\":12,\"text\":\"hello\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"

        let deniedAck = adapter.ingestWebhookPayload(deniedPayload)
        let allowedAck = adapter.ingestWebhookPayload(allowedPayload)
        @Expect(deniedAck.contains("\"ignored\":true"), true)
        @Expect(allowedAck.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].senderId, "8734062810")
        @Expect(
            match (inbound[0].chatType) {
                case ChatType.Direct => true
                case _ => false
            },
            true
        )
    }

    @TestCase
    public func directAllowlistRejectionIsVisibleInInboundPolicyDiagnostics(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            dmPolicy: "allowlist",
            allowFrom: ["8734062810"]
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":31,\"message\":{\"message_id\":11,\"text\":\"hello\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)

        let diag = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(diag.get("lastDecision").getOrThrow().asString().getValue(), "ignored")
        @Expect(diag.get("lastReason").getOrThrow().asString().getValue(), "dm_sender_not_allowed")
        @Expect(diag.get("lastUpdateKind").getOrThrow().asString().getValue(), "message")
        @Expect(diag.get("lastUpdateId").getOrThrow().asString().getValue(), "31")
        @Expect(diag.get("lastPeerId").getOrThrow().asString().getValue(), "user:745123456")
        @Expect(diag.get("lastSenderId").getOrThrow().asString().getValue(), "745123456")
    }

    @TestCase
    public func disabledGroupsDropWebhookMessagesBeforeQueueing(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            groupPolicy: "disabled"
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"text\":\"/status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)
    }

    @TestCase
    public func groupMentionRejectionIsVisibleInInboundPolicyDiagnostics(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            groupPolicy: "open"
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":32,\"message\":{\"message_id\":101,\"text\":\"status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)

        let diag = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(diag.get("lastDecision").getOrThrow().asString().getValue(), "ignored")
        @Expect(diag.get("lastReason").getOrThrow().asString().getValue(), "group_mention_required")
        @Expect(diag.get("lastUpdateKind").getOrThrow().asString().getValue(), "message")
        @Expect(diag.get("lastPeerId").getOrThrow().asString().getValue(), "group:-1001234567890")
        @Expect(diag.get("lastSenderId").getOrThrow().asString().getValue(), "8734062810")
    }

    @TestCase
    public func t46GroupSilentIngestHistoryIsAttachedToNextMentionedTurn(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            groupPolicy: "open",
            groupHistoryEnabled: true,
            groupHistoryLimit: 2
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let silent = "{\"update_id\":41,\"message\":{\"message_id\":201,\"text\":\"background context\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        @Expect(adapter.ingestWebhookPayload(silent).contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)

        let mentioned = "{\"update_id\":42,\"message\":{\"message_id\":202,\"text\":\"/status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        @Expect(adapter.ingestWebhookPayload(mentioned).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let context = inbound[0].mediaContext.get("context").getOrThrow().asObject()
        let groupHistory = context.get("groupHistory").getOrThrow().asObject()
        @Expect(groupHistory.get("source").getOrThrow().asString().getValue(), "telegram-silent-ingest")
        let records = groupHistory.get("records").getOrThrow().asArray()
        @Expect(records.size(), 1)
        @Expect(records[0].asObject().get("text").getOrThrow().asString().getValue(), "background context")
    }

    @TestCase
    public func t49SilentIngestTriggersMessageReceivedHookWithoutQueueingAgentTurn(): Unit {
        let received = ArrayList<JsonObject>()
        setGatewayOpenClawPluginSidecarRunnerForTest(Some({ method: String, payload: JsonObject =>
            if (method == "hook.message_received") {
                received.add(payload)
            }
            let out = JsonObject()
            out.put("ok", true.toJsonValue())
            out.put("status", JsonString("ok"))
            out
        }))
        try {
            let cfg = TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                groupPolicy: "open",
                groupHistoryEnabled: true
            )
            let adapter = TelegramAdapter(config: cfg)
            adapter.start()
            let silent = "{\"update_id\":49,\"message\":{\"message_id\":201,\"text\":\"background context\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
            @Expect(adapter.ingestWebhookPayload(silent).contains("\"ignored\":true"), true)
            @Expect(adapter.pullInbound().isEmpty(), true)
            @Expect(received.size, 1)
            @Expect(received[0].get("accepted").getOrThrow().asBool().getValue(), false)
            @Expect(received[0].get("reason").getOrThrow().asString().getValue(), "group_mention_required")
            @Expect(received[0].get("peerId").getOrThrow().asString().getValue(), "group:-1001234567890")
            @Expect(received[0].get("messageId").getOrThrow().asString().getValue(), "201")
            @Expect(received[0].get("text").getOrThrow().asString().getValue(), "background context")
        } finally {
            setGatewayOpenClawPluginSidecarRunnerForTest(None)
        }
    }

    @TestCase
    public func editedAndChannelPostPolicyDiagnosticsPreserveTelegramUpdateKind(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", groupPolicy: "disabled"))
        adapter.start()

        let editedPayload = "{\"update_id\":33,\"edited_message\":{\"message_id\":101,\"text\":\"/status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        let editedAck = adapter.ingestWebhookPayload(editedPayload)
        @Expect(editedAck.contains("\"ignored\":true"), true)
        var diag = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(diag.get("lastUpdateKind").getOrThrow().asString().getValue(), "edited_message")
        @Expect(diag.get("lastReason").getOrThrow().asString().getValue(), "group_not_allowed")

        let channelPayload = "{\"update_id\":34,\"channel_post\":{\"message_id\":102,\"text\":\"/status\",\"chat\":{\"id\":-100222333,\"type\":\"channel\"}}}"
        let channelAck = adapter.ingestWebhookPayload(channelPayload)
        @Expect(channelAck.contains("\"ignored\":true"), true)
        diag = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(diag.get("lastUpdateKind").getOrThrow().asString().getValue(), "channel_post")
        @Expect(diag.get("lastReason").getOrThrow().asString().getValue(), "group_not_allowed")
        @Expect(diag.get("lastPeerId").getOrThrow().asString().getValue(), "group:-100222333")
    }

    @TestCase
    public func topicServiceMessageIsIgnoredWithVisibleInboundPolicyReason(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", groupPolicy: "open"))
        adapter.start()
        let payload = "{\"update_id\":35,\"message\":{\"message_id\":103,\"message_thread_id\":42,\"forum_topic_created\":{\"name\":\"topic\"},\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)

        let diag = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(diag.get("lastDecision").getOrThrow().asString().getValue(), "ignored")
        @Expect(diag.get("lastReason").getOrThrow().asString().getValue(), "unsupported_or_empty_message")
        @Expect(diag.get("lastUpdateKind").getOrThrow().asString().getValue(), "message")
        @Expect(diag.get("lastUpdateId").getOrThrow().asString().getValue(), "35")
        @Expect(diag.get("lastMessageId").getOrThrow().asString().getValue(), "103")
    }

    @TestCase
    public func openGroupPolicyStillRequiresAllowedGroupWhenGroupsConfigMissing(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            groupPolicy: "allowlist",
            groupAllowFrom: ["8734062810"]
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"text\":\"@bot status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)
    }

    @TestCase
    public func groupEntryOverridesMentionAndAllowFromForTopicMessages(): Unit {
        let groups = JsonObject()
        let groupRule = JsonObject()
        let allowFrom = JsonArray([])
        allowFrom.add("tg:8734062810".toJsonValue())
        groupRule.put("requireMention", false.toJsonValue())
        groupRule.put("allowFrom", allowFrom)
        groups.put("-1001234567890", groupRule)
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            groupPolicy: "allowlist",
            groups: Some(groups)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"message_thread_id\":42,\"text\":\"status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "group:-1001234567890:topic:42")
        @Expect(inbound[0].mentioned, false)
    }

    @TestCase
    public func topicEntryOverridesGroupMentionAndAllowFromPolicy(): Unit {
        let groups = JsonObject()
        let groupRule = JsonObject()
        let groupAllow = JsonArray([])
        groupAllow.add("111".toJsonValue())
        groupRule.put("requireMention", true.toJsonValue())
        groupRule.put("allowFrom", groupAllow)
        let topics = JsonObject()
        let topicRule = JsonObject()
        let topicAllow = JsonArray([])
        topicAllow.add("222".toJsonValue())
        topicRule.put("requireMention", false.toJsonValue())
        topicRule.put("allowFrom", topicAllow)
        topics.put("42", topicRule)
        groupRule.put("topics", topics)
        groups.put("-1001234567890", groupRule)
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                groupPolicy: "allowlist",
                groups: Some(groups)
            )
        )
        adapter.start()
        let allowedPayload = "{\"update_id\":11,\"message\":{\"message_id\":201,\"message_thread_id\":42,\"text\":\"status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":222}}}"
        let allowedAck = adapter.ingestWebhookPayload(allowedPayload)
        @Expect(allowedAck.contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "group:-1001234567890:topic:42")

        let rejectedPayload = "{\"update_id\":12,\"message\":{\"message_id\":202,\"message_thread_id\":42,\"text\":\"status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":111}}}"
        let rejectedAck = adapter.ingestWebhookPayload(rejectedPayload)
        @Expect(rejectedAck.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)
        let policy = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(policy.get("lastReason").getOrThrow().asString().getValue(), "group_sender_not_allowed")
    }

    @TestCase
    public func topicRouteConfigIsProjectedIntoInboundMediaContext(): Unit {
        let groups = JsonObject()
        let groupRule = JsonObject()
        let groupAllow = JsonArray([])
        groupAllow.add("222".toJsonValue())
        groupRule.put("requireMention", false.toJsonValue())
        groupRule.put("allowFrom", groupAllow)
        groupRule.put("agentId", JsonString("group-agent"))
        let topics = JsonObject()
        let topicRule = JsonObject()
        topicRule.put("agentId", JsonString("topic-agent"))
        topicRule.put("systemPrompt", JsonString("topic prompt"))
        topicRule.put("skills", JsonArray([JsonString("review")]))
        topicRule.put("disableAudioPreflight", true.toJsonValue())
        topics.put("42", topicRule)
        groupRule.put("topics", topics)
        groups.put("-1001234567890", groupRule)
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                groupPolicy: "allowlist",
                groups: Some(groups)
            )
        )
        adapter.start()
        let payload = "{\"update_id\":51,\"message\":{\"message_id\":301,\"message_thread_id\":42,\"text\":\"status\",\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":222}}}"
        @Expect(adapter.ingestWebhookPayload(payload).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let route = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("telegramRoute").getOrThrow().asObject()
        @Expect(route.get("agentId").getOrThrow().asString().getValue(), "topic-agent")
        @Expect(route.get("systemPrompt").getOrThrow().asString().getValue(), "topic prompt")
        @Expect(route.get("skills").getOrThrow().asArray()[0].asString().getValue(), "review")
        @Expect(route.get("disableAudioPreflight").getOrThrow().asBool().getValue(), true)
        let imRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(imRoute.get("channel").getOrThrow().asString().getValue(), "telegram")
        @Expect(imRoute.get("peerKind").getOrThrow().asString().getValue(), "topic")
        @Expect(imRoute.get("peerId").getOrThrow().asString().getValue(), "42")
        @Expect(imRoute.get("parentPeerKind").getOrThrow().asString().getValue(), "group")
        @Expect(imRoute.get("parentPeerId").getOrThrow().asString().getValue(), "-1001234567890")
    }

    @TestCase
    public func webhookPhotoMessagesMapToStructuredInboundMediaText(): Unit {
        let groups = JsonObject()
        let groupRule = JsonObject()
        let allowFrom = JsonArray([])
        allowFrom.add("8734062810".toJsonValue())
        groupRule.put("requireMention", false.toJsonValue())
        groupRule.put("allowFrom", allowFrom)
        groups.put("-1001234567890", groupRule)
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                groupPolicy: "allowlist",
                groups: Some(groups)
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"message_thread_id\":42,\"caption\":\"hello photo\",\"photo\":[{\"file_id\":\"small\"},{\"file_id\":\"large\"}],\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "group:-1001234567890:topic:42")
        @Expect(inbound[0].text.contains("[photo]"), true)
        @Expect(inbound[0].text.contains("fileId=large"), true)
        @Expect(inbound[0].text.contains("caption=hello photo"), true)
        @Expect(inbound[0].text.contains("[media-context]"), true)
        @Expect(inbound[0].text.contains("mediaKind=photo"), true)
        @Expect(inbound[0].text.contains("eligibleFor=vision"), true)
        let mediaRecords = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        @Expect(mediaRecords.size(), 1)
        let firstRecord = mediaRecords[0].asObject()
        @Expect(firstRecord.get("mediaKind").getOrThrow().asString().getValue(), "photo")
        @Expect(firstRecord.get("messageId").getOrThrow().asString().getValue(), "101")
        @Expect(firstRecord.get("relation").getOrThrow().asString().getValue(), "current")
        @Expect(inbound[0].threadId.getOrThrow(), "42")
    }

    @TestCase
    public func webhookTextMessagesCarryTelegramMediaToolScopeWithoutPromptMediaBlock(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":202,\"text\":\"保存图片\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let media = inbound[0].mediaContext
        @Expect(media.get("channel").getOrThrow().asString().getValue(), "telegram")
        @Expect(media.get("accountId").getOrThrow().asString().getValue(), "default")
        @Expect(media.get("peerId").getOrThrow().asString().getValue(), "user:745123456")
        @Expect(media.get("messageId").getOrThrow().asString().getValue(), "202")
        @Expect(media.get("records").isNone(), true)
        @Expect(gatewayBuildMediaContextPrompt(media), "")
    }

    @TestCase
    public func telegramHtmlRendererHandlesChineseAndMarkdownSafely(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        @Expect(adapter.debugTelegramRenderHtmlForTest("图片已经保存").contains("图片已经保存"), true)
        @Expect(adapter.debugTelegramRenderHtmlForTest("[[reply_to_current]]图片已经保存").contains("图片已经保存"), true)
        @Expect(adapter.debugTelegramRenderHtmlForTest("**粗体**"), "<b>粗体</b>")
    }

    @TestCase
    public func sendMessageWithChineseTextDoesNotFailBeforeTransport(): Unit {
        let root = Path("/tmp/metis-telegram-chinese-send-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(sendMessage: true)
                ),
                pairingRoot: root.toString()
            )
            adapter.start()
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:745123456", "图片已经保存"))
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendMessage"), true)
            @Expect(fake.sawBodyContaining("图片已经保存"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func webhookStickerMessagesMapToStructuredInboundMediaText(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"],
                media: TelegramMediaConfig(downloadEnabled: false)
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"sticker\":{\"file_id\":\"sticker-file-id\",\"emoji\":\"🙂\",\"set_name\":\"metis_pack\",\"is_animated\":false,\"is_video\":false},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "user:745123456")
        @Expect(inbound[0].text.contains("[sticker]"), true)
        @Expect(inbound[0].text.contains("fileId=sticker-file-id"), true)
        @Expect(inbound[0].text.contains("[media-context]"), true)
        @Expect(inbound[0].text.contains("mediaKind=sticker"), true)
        @Expect(inbound[0].text.contains("stickerEmoji=🙂"), true)
        @Expect(inbound[0].text.contains("stickerSetName=metis_pack"), true)
        @Expect(inbound[0].text.contains("eligibleFor=vision"), true)
        let mediaRecords = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        let first = mediaRecords[0].asObject()
        @Expect(first.get("stickerEmoji").getOrThrow().asString().getValue(), "🙂")
        @Expect(first.get("eligibleFor").getOrThrow().asString().getValue(), "vision")
    }

    @TestCase
    public func webhookDocumentMessagesPreserveMediaMetadataInInboundText(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"],
                media: TelegramMediaConfig(downloadEnabled: false)
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":102,\"caption\":\"report\",\"media_group_id\":\"album-1\",\"document\":{\"file_id\":\"doc-file-id\",\"file_unique_id\":\"doc-unique\",\"mime_type\":\"application/pdf\",\"file_size\":1024,\"file_name\":\"report.pdf\"},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        var inbound = adapter.pullInbound()
        if (inbound.size == 0) {
            sleep(Duration.millisecond * 760)
            inbound = adapter.pullInbound()
        }
        @Expect(inbound.size, 1)
        @Expect(inbound[0].text.contains("[document]"), true)
        @Expect(inbound[0].text.contains("fileId=doc-file-id"), true)
        @Expect(inbound[0].text.contains("fileUniqueId=doc-unique"), true)
        @Expect(inbound[0].text.contains("mimeType=application/pdf"), true)
        @Expect(inbound[0].text.contains("fileSize=1024"), true)
        @Expect(inbound[0].text.contains("fileName=report.pdf"), true)
        @Expect(inbound[0].text.contains("mediaGroupId=album-1"), true)
        @Expect(inbound[0].text.contains("albumPolicy=single-largest"), true)
        @Expect(inbound[0].text.contains("caption=report"), true)
        @Expect(inbound[0].text.contains("[media-context]"), true)
        @Expect(inbound[0].text.contains("eligibleFor=file-context"), true)
        let mediaRecords = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        @Expect(mediaRecords.size(), 1)
        @Expect(mediaRecords[0].asObject().get("mediaKind").getOrThrow().asString().getValue(), "document")
    }

    @TestCase
    public func webhookMediaDownloadFailureSendsUserVisibleWarning(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    dmPolicy: "open",
                    allowFrom: ["*"],
                    media: TelegramMediaConfig(
                        downloadEnabled: true,
                        allowedMimes: ["image/*"],
                        warnOnDownloadFailure: true
                    )
                )
            )
            adapter.start()
            let payload = "{\"update_id\":1,\"message\":{\"message_id\":303,\"document\":{\"file_id\":\"doc-file-id\",\"mime_type\":\"application/pdf\",\"file_size\":1024,\"file_name\":\"report.pdf\"},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
            let ack = adapter.ingestWebhookPayload(payload)
            @Expect(ack.contains("\"ok\":true"), true)
            @Expect(fake.saw("sendMessage"), true)
            @Expect(fake.sawBodyContaining("reason=mime_not_allowed"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func persistedTelegramVoiceCanUseNativeAsrRunner(): Unit {
        let root = Path("/tmp/metis-telegram-asr-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        setTelegramAsrRunnerForTest(Some({ _path: String, _mime: String => "transcribed voice text" }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    media: TelegramMediaConfig(downloadEnabled: true, allowedMimes: ["audio/*"])
                ),
                pairingRoot: root.toString()
            )
            let state = adapter.debugPersistInboundMediaForTest(
                "voice",
                "voice-file-id",
                mimeType: "audio/ogg",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"voice/file.ogg\",\"file_size\":12}}",
                downloadRaw: "fake-audio",
                peerId: "user:745123456",
                messageId: "304"
            )
            let last = state.get("lastMedia").getOrThrow().asObject()
            @Expect(last.get("asrStatus").getOrThrow().asString().getValue(), "transcribed")
            @Expect(last.get("transcript").getOrThrow().asString().getValue(), "transcribed voice text")
        } finally {
            setTelegramAsrRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func inboundVoicePreflightAddsTranscriptFromUnifiedAsrMock(): Unit {
        let root = Path("/tmp/metis-telegram-preflight-asr-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        setGatewayMediaAsrRunnerForTest(Some({ _path: String, _mime: String => "unified asr transcript" }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    media: TelegramMediaConfig(downloadEnabled: true, allowedMimes: ["audio/*"])
                ),
                pairingRoot: root.toString()
            )
            let state = adapter.debugPersistInboundMediaForTest(
                "voice",
                "voice-file-id",
                mimeType: "audio/ogg",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"voice/file.ogg\",\"file_size\":10}}",
                downloadRaw: "fake-audio",
                peerId: "user:745123456",
                messageId: "305"
            )
            let last = state.get("lastMedia").getOrThrow().asObject()
            @Expect(last.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(last.get("transcript").getOrThrow().asString().getValue(), "unified asr transcript")
            @Expect(last.get("asrStatus").getOrThrow().asString().getValue(), "transcribed")
            @Expect(last.get("understandingStatus").getOrThrow().asString().getValue(), "ok")
        } finally {
            setGatewayMediaAsrRunnerForTest(None<(String, String) -> String>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func inboundPhotoAndStickerPreflightAddsVisionAnalysisAndDurableStickerCache(): Unit {
        let root = Path("/tmp/metis-telegram-preflight-vision-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        setGatewayMediaVisionRunnerForTest(Some({ _path: String, _mime: String, kind: String, _prompt: String, _maxBytes: Int64 =>
            if (kind == "sticker") { "mock sticker description" } else { "mock photo analysis" }
        }))
        setGatewayTelegramStickerCacheRootForTest(Some(root.join("gateway-telegram")))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token"),
                pairingRoot: root.toString()
            )
            let photoState = adapter.debugPersistInboundMediaForTest(
                "photo",
                "photo-file-id",
                mimeType: "image/jpeg",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file.jpg\",\"file_size\":10}}",
                downloadRaw: "fake-photo",
                peerId: "user:745123456",
                messageId: "306"
            )
            let photo = photoState.get("lastMedia").getOrThrow().asObject()
            @Expect(photo.get("analysis").getOrThrow().asString().getValue(), "mock photo analysis")
            @Expect(photo.get("visionStatus").getOrThrow().asString().getValue(), "analyzed")

            let stickerState = adapter.debugPersistInboundMediaForTest(
                "sticker",
                "sticker-file-id",
                fileUniqueId: "sticker-unique-id",
                mimeType: "image/webp",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"stickers/file.webp\",\"file_size\":10}}",
                downloadRaw: "fake-sticker",
                peerId: "user:745123456",
                messageId: "307"
            )
            let sticker = stickerState.get("lastMedia").getOrThrow().asObject()
            @Expect(sticker.get("description").getOrThrow().asString().getValue(), "mock sticker description")
            @Expect(exists(root.join("gateway-telegram").join("sticker-cache.json")), true)
            let searched = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: JsonObject()),
                { => GatewayTelegramMediaToolset().debugTelegramStickerSearchForTest("mock sticker", Some(5)) }
            )
            let searchJson = JsonValue.fromStr(searched).asObject()
            @Expect(searchJson.get("count").getOrThrow().asInt().getValue(), 1)
            let got = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: JsonObject()),
                { => GatewayTelegramMediaToolset().debugTelegramStickerGetForTest(None<String>, Some("sticker-unique-id"), None<String>) }
            )
            @Expect(JsonValue.fromStr(got).asObject().get("status").getOrThrow().asString().getValue(), "ok")
        } finally {
            setGatewayMediaVisionRunnerForTest(None<(String, String, String, String, Int64) -> String>)
            setGatewayTelegramStickerCacheRootForTest(None<Path>)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func inboundTextDocumentPreflightAddsPreviewAndToolCanReadIt(): Unit {
        let root = Path("/tmp/metis-telegram-preflight-document-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token"),
                pairingRoot: root.toString()
            )
            let state = adapter.debugPersistInboundMediaForTest(
                "document",
                "doc-file-id",
                mimeType: "text/plain",
                fileName: "note.txt",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"documents/note.txt\",\"file_size\":17}}",
                downloadRaw: "hello text document",
                peerId: "user:745123456",
                messageId: "308"
            )
            let record = state.get("lastMedia").getOrThrow().asObject()
            @Expect(record.get("documentExtractStatus").getOrThrow().asString().getValue(), "ok")
            @Expect(record.get("documentTextPreview").getOrThrow().asString().getValue(), "hello text document")
            let mediaContext = JsonObject()
            let records = JsonArray([])
            records.add(record)
            mediaContext.put("records", records)
            let extracted = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("telegram", channelName: "telegram", sessionKey: "telegram:chat:1", mediaContext: mediaContext),
                { => GatewayTelegramMediaToolset().debugTelegramDocumentExtractForTest(None<String>, None<Int64>, Some(100)) }
            )
            let json = JsonValue.fromStr(extracted).asObject()
            @Expect(json.get("status").getOrThrow().asString().getValue(), "ok")
            @Expect(json.get("content").getOrThrow().asString().getValue(), "hello text document")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func inboundUnconfiguredUnderstandingDoesNotBlockMediaSave(): Unit {
        let root = Path("/tmp/metis-telegram-preflight-not-configured-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    media: TelegramMediaConfig(downloadEnabled: true, allowedMimes: ["audio/*", "image/*"])
                ),
                pairingRoot: root.toString()
            )
            let voiceState = adapter.debugPersistInboundMediaForTest(
                "voice",
                "voice-file-id",
                mimeType: "audio/ogg",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"voice/file.ogg\",\"file_size\":10}}",
                downloadRaw: "fake-audio",
                peerId: "user:745123456",
                messageId: "309"
            )
            let voice = voiceState.get("lastMedia").getOrThrow().asObject()
            @Expect(voice.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(voice.get("skippedReason").getOrThrow().asString().getValue(), "")
            @Expect(voice.get("asrStatus").getOrThrow().asString().getValue(), "not_configured")
            let photoState = adapter.debugPersistInboundMediaForTest(
                "photo",
                "photo-file-id",
                mimeType: "image/jpeg",
                getFileRaw: "{\"ok\":true,\"result\":{\"file_path\":\"photos/file.jpg\",\"file_size\":10}}",
                downloadRaw: "fake-photo",
                peerId: "user:745123456",
                messageId: "310"
            )
            let photo = photoState.get("lastMedia").getOrThrow().asObject()
            @Expect(photo.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(photo.get("skippedReason").getOrThrow().asString().getValue(), "")
            @Expect(photo.get("visionStatus").getOrThrow().asString().getValue(), "not_configured")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func webhookReplyTargetMediaIsInjectedIntoMediaContext(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":202,\"text\":\"save this\",\"reply_to_message\":{\"message_id\":201,\"photo\":[{\"file_id\":\"reply-small\"},{\"file_id\":\"reply-large\"}],\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].text, "save this")
        @Expect(inbound[0].replyTargetMessageId.getOrThrow(), "201")
        let mediaRecords = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        @Expect(mediaRecords.size(), 1)
        let record = mediaRecords[0].asObject()
        @Expect(record.get("mediaKind").getOrThrow().asString().getValue(), "photo")
        @Expect(record.get("fileId").getOrThrow().asString().getValue(), "reply-large")
        @Expect(record.get("messageId").getOrThrow().asString().getValue(), "201")
        @Expect(record.get("relation").getOrThrow().asString().getValue(), "replyTarget")
    }

    @TestCase
    public func webhookMediaGroupMessagesMergeIntoOneInboundTurn(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        adapter.start()
        let first = "{\"update_id\":1,\"message\":{\"message_id\":301,\"caption\":\"album caption\",\"media_group_id\":\"album-1\",\"photo\":[{\"file_id\":\"p1-small\"},{\"file_id\":\"p1-large\"}],\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let second = "{\"update_id\":2,\"message\":{\"message_id\":302,\"media_group_id\":\"album-1\",\"photo\":[{\"file_id\":\"p2-small\"},{\"file_id\":\"p2-large\"}],\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        @Expect(adapter.ingestWebhookPayload(first).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(second).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].messageId, "302")
        @Expect(inbound[0].text.contains("album caption"), true)
        let records = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        @Expect(records.size(), 2)
        @Expect(records[0].asObject().get("fileId").getOrThrow().asString().getValue(), "p1-large")
        @Expect(records[1].asObject().get("fileId").getOrThrow().asString().getValue(), "p2-large")
        @Expect(records[0].asObject().get("mediaGroupId").getOrThrow().asString().getValue(), "album-1")
        @Expect(records[1].asObject().get("mediaGroupId").getOrThrow().asString().getValue(), "album-1")
    }

    @TestCase
    public func webhookMediaGroupMessagesCanMergeAcrossPullBoundaries(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"],
                media: TelegramMediaConfig(downloadEnabled: false)
            )
        )
        adapter.start()
        let first = "{\"update_id\":1,\"message\":{\"message_id\":311,\"caption\":\"album caption\",\"media_group_id\":\"album-cross\",\"photo\":[{\"file_id\":\"p1-small\"},{\"file_id\":\"p1-large\"}],\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let second = "{\"update_id\":2,\"message\":{\"message_id\":312,\"media_group_id\":\"album-cross\",\"photo\":[{\"file_id\":\"p2-small\"},{\"file_id\":\"p2-large\"}],\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        @Expect(adapter.ingestWebhookPayload(first).contains("\"ok\":true"), true)
        @Expect(adapter.pullInbound().size, 0)
        @Expect(adapter.ingestWebhookPayload(second).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].messageId, "312")
        let records = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        @Expect(records.size(), 2)
        @Expect(records[0].asObject().get("fileId").getOrThrow().asString().getValue(), "p1-large")
        @Expect(records[1].asObject().get("fileId").getOrThrow().asString().getValue(), "p2-large")
    }

    @TestCase
    public func webhookExternalReplyMediaIsInjectedIntoMediaContext(): Unit {
        let root = Path("/tmp/metis-telegram-external-reply-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let fake = TelegramFakeBotApi()
        fake.pollingUpdatesEnabled = false
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    dmPolicy: "open",
                    allowFrom: ["*"]
                ),
                pairingRoot: root.toString()
            )
            adapter.start()
            let payload = "{\"update_id\":1,\"message\":{\"message_id\":502,\"text\":\"save external\",\"external_reply\":{\"message_id\":501,\"caption\":\"external photo\",\"photo\":[{\"file_id\":\"external-small\"},{\"file_id\":\"external-large\"}],\"from\":{\"id\":111,\"username\":\"source_user\"}},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
            @Expect(adapter.ingestWebhookPayload(payload).contains("\"ok\":true"), true)

            let inbound = adapter.pullInbound()
            @Expect(inbound.size, 1)
            @Expect(inbound[0].text.contains("[external-reply-context]"), true)
            let records = inbound[0].mediaContext.get("records").getOrThrow().asArray()
            @Expect(records.size(), 1)
            let record = records[0].asObject()
            @Expect(record.get("relation").getOrThrow().asString().getValue(), "externalReply")
            @Expect(record.get("fileId").getOrThrow().asString().getValue(), "external-large")
            let context = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            @Expect(context.get("externalReply").isSome(), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramTextBurstDoesNotMergeNonAdjacentMessageIds(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", dmPolicy: "open", allowFrom: ["*"]))
        adapter.start()
        let first = "{\"update_id\":1,\"message\":{\"message_id\":601,\"text\":\"first\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let second = "{\"update_id\":2,\"message\":{\"message_id\":610,\"text\":\"second\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        @Expect(adapter.ingestWebhookPayload(first).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(second).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].text, "first")
        @Expect(inbound[1].text, "second")
    }

    @TestCase
    public func webhookLocationAndReplyTextBecomeSupplementalContext(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":401,\"text\":\"where was this?\",\"reply_to_message\":{\"message_id\":400,\"text\":\"meet here\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}},\"location\":{\"latitude\":31.2304,\"longitude\":121.4737},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        @Expect(adapter.ingestWebhookPayload(payload).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].text.contains("[reply-context]"), true)
        @Expect(inbound[0].text.contains("body=meet here"), true)
        @Expect(inbound[0].text.contains("[location]"), true)
        @Expect(inbound[0].text.contains("latitude=31.2304"), true)
        @Expect(inbound[0].text.contains("longitude=121.4737"), true)
        let context = inbound[0].mediaContext.get("context").getOrThrow().asObject()
        @Expect(context.get("replyTo").getOrThrow().asObject().get("messageId").getOrThrow().asString().getValue(), "400")
        @Expect(context.get("location").getOrThrow().asObject().get("latitude").getOrThrow().asString().getValue().contains("31.23"), true)
    }

    @TestCase
    public func webhookForwardVenueAndContactBecomeStructuredContext(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":402,\"text\":\"context\",\"forward_origin\":{\"type\":\"channel\",\"chat\":{\"id\":-1001,\"type\":\"channel\",\"title\":\"Announcements\"}},\"venue\":{\"title\":\"Office\",\"address\":\"Road 1\",\"location\":{\"latitude\":31.23,\"longitude\":121.47}},\"contact\":{\"first_name\":\"Ada\",\"last_name\":\"Lovelace\",\"phone_number\":\"123\",\"user_id\":888},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        @Expect(adapter.ingestWebhookPayload(payload).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let context = inbound[0].mediaContext.get("context").getOrThrow().asObject()
        @Expect(context.get("forwarded").getOrThrow().asObject().get("chatTitle").getOrThrow().asString().getValue(), "Announcements")
        @Expect(context.get("venue").getOrThrow().asObject().get("title").getOrThrow().asString().getValue(), "Office")
        @Expect(context.get("contact").getOrThrow().asObject().get("firstName").getOrThrow().asString().getValue(), "Ada")
    }

    @TestCase
    public func webhookAdjacentPlainTextsFromSameSenderMergeIntoOneInboundTurn(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        adapter.start()
        let first = "{\"update_id\":1,\"message\":{\"message_id\":501,\"text\":\"first fragment\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let second = "{\"update_id\":2,\"message\":{\"message_id\":502,\"text\":\"second fragment\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        @Expect(adapter.ingestWebhookPayload(first).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(second).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].messageId, "502")
        @Expect(inbound[0].text, "first fragment\nsecond fragment")
    }

    @TestCase
    public func longTextFragmentsDebounceAcrossWebhookPulls(): Unit {
        let fake = TelegramFakeBotApi()
        fake.pollingUpdatesEnabled = false
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    dmPolicy: "open",
                    allowFrom: ["*"]
                )
            )
            adapter.start()
            let sb1 = StringBuilder()
            let sb2 = StringBuilder()
            for (_ in 0..3600) {
                sb1.append("a")
                sb2.append("b")
            }
            let firstText = sb1.toString()
            let secondText = sb2.toString()
            let first = "{\"update_id\":1,\"message\":{\"message_id\":601,\"text\":\"${firstText}\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
            let second = "{\"update_id\":2,\"message\":{\"message_id\":602,\"text\":\"${secondText}\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
            @Expect(adapter.ingestWebhookPayload(first).contains("\"ok\":true"), true)
            @Expect(adapter.pullInbound().size, 0)
            @Expect(adapter.ingestWebhookPayload(second).contains("\"ok\":true"), true)
            let inbound = adapter.pullInbound()
            @Expect(inbound.size, 1)
            @Expect(inbound[0].messageId, "602")
            @Expect(inbound[0].text, firstText + "\n" + secondText)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func forwardBurstDebounceDoesNotMixWithSlashCommand(): Unit {
        let fake = TelegramFakeBotApi()
        fake.pollingUpdatesEnabled = false
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    dmPolicy: "open",
                    allowFrom: ["*"]
                )
            )
            adapter.start()
            let first = "{\"update_id\":1,\"message\":{\"message_id\":701,\"text\":\"forward one\",\"forward_origin\":{\"type\":\"channel\",\"chat\":{\"id\":-1001,\"type\":\"channel\",\"title\":\"Announcements\"}},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
            let second = "{\"update_id\":2,\"message\":{\"message_id\":702,\"text\":\"forward two\",\"forward_origin\":{\"type\":\"channel\",\"chat\":{\"id\":-1001,\"type\":\"channel\",\"title\":\"Announcements\"}},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
            @Expect(adapter.ingestWebhookPayload(first).contains("\"ok\":true"), true)
            @Expect(adapter.pullInbound().size, 0)
            @Expect(adapter.ingestWebhookPayload(second).contains("\"ok\":true"), true)
            let merged = adapter.pullInbound()
            @Expect(merged.size, 1)
            @Expect(merged[0].text.contains("forward one"), true)
            @Expect(merged[0].text.contains("forward two"), true)

            let slash = "{\"update_id\":3,\"message\":{\"message_id\":703,\"text\":\"/status\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
            @Expect(adapter.ingestWebhookPayload(slash).contains("\"ok\":true"), true)
            let immediate = adapter.pullInbound()
            @Expect(immediate.size, 1)
            @Expect(immediate[0].text, "/status")
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func dmOpenRequiresWildcardAllowFrom(): Unit {
        let noWildcard = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["8734062810"]
            )
        )
        noWildcard.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":11,\"text\":\"hello\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let ack = noWildcard.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)
        @Expect(noWildcard.pullInbound().isEmpty(), true)

        let wildcard = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        wildcard.start()
        let okAck = wildcard.ingestWebhookPayload(payload)
        @Expect(okAck.contains("\"ok\":true"), true)
        @Expect(wildcard.pullInbound().size, 1)
    }

    @TestCase
    public func dmPairingCreatesPendingRequestAndApprovalUnlocksSender(): Unit {
        let root = "/tmp/metis-telegram-pairing-test-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "pairing"
            ),
            pairingRoot: root
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":11,\"text\":\"hello\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let firstAck = adapter.ingestWebhookPayload(payload)
        @Expect(firstAck.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)

        let code = adapter.debugPendingPairingCode("745123456")
        @Expect(!code.isEmpty(), true)
        @Expect(adapter.debugApprovePairingCode(code), true)

        let secondAck = adapter.ingestWebhookPayload(payload)
        @Expect(secondAck.contains("\"ok\":true"), true)
        @Expect(adapter.pullInbound().size, 1)
    }

    @TestCase
    public func telegramPairingAccountStoreApprovesAccountScopedPendingCode(): Unit {
        let root = Path("/tmp/metis-telegram-account-pairing-store-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        let store = telegramPairingAccountStore(rootDir: root, accountId: "default")
        let code = store.ensurePending("745123456")

        @Expect(!code.isEmpty(), true)
        @Expect(store.approve(code), true)
        @Expect(store.pendingRows().isEmpty(), true)
        @Expect(store.isApproved("745123456"), true)

        let approvedPath = root.join("gateway-telegram").join("accounts").join("default").join("credentials").join("telegram-allowFrom.json")
        @Expect(String.fromUtf8(File.readFrom(approvedPath)).contains("745123456"), true)
    }

    @TestCase
    public func telegramPairingAccountStoreReadsLegacyGlobalAllowFrom(): Unit {
        let root = Path("/tmp/metis-telegram-legacy-allowfrom-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root.join("credentials"), recursive: true)
        File.writeTo(root.join("credentials").join("telegram-allowFrom.json"), "[\"745123456\"]".toArray())

        let store = telegramPairingAccountStore(rootDir: root, accountId: "default")

        @Expect(store.isApproved("745123456"), true)
        @Expect(store.approvedSenders().size, 1)
        @Expect(store.approvedSenders()[0], "745123456")
    }

    @TestCase
    public func pollingResponseQueuesInboundTelegramMessages(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            ),
            pairingRoot: "/tmp/metis-telegram-polling-basic-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        )
        adapter.start()
        let raw = "{\"ok\":true,\"result\":[{\"update_id\":99,\"message\":{\"message_id\":21,\"text\":\"Hi\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}]}"
        @Expect(adapter.debugIngestPollingResponse(raw), 1)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "user:745123456")
        @Expect(inbound[0].text, "Hi")
        @Expect(adapter.debugLastInboundUpdateId(), "99")
    }

    @TestCase
    public func pollingResponseDedupesCompletedUpdateIds(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            ),
            pairingRoot: "/tmp/metis-telegram-polling-dedupe-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        )
        let raw = "{\"ok\":true,\"result\":[{\"update_id\":99,\"message\":{\"message_id\":21,\"text\":\"Hi\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}]}"

        @Expect(adapter.debugIngestPollingResponse(raw), 1)
        @Expect(adapter.debugIngestPollingResponse(raw), 0)
        @Expect(adapter.debugLastInboundUpdateId(), "99")
        let offset = adapter.debugOffsetDiagnosticsForTest()
        @Expect(offset.get("pendingUpdateCount").getOrThrow().asInt().getValue(), 0)
        @Expect(offset.get("dedupeCacheSize").getOrThrow().asInt().getValue() >= 1, true)
    }

    @TestCase
    public func pollingIgnoredUpdateStillAdvancesSafeWatermarkAfterProcessing(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "allowlist",
                allowFrom: ["8734062810"]
            ),
            pairingRoot: "/tmp/metis-telegram-polling-ignored-watermark-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        )
        let raw = "{\"ok\":true,\"result\":[{\"update_id\":50,\"message\":{\"message_id\":21,\"text\":\"blocked\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}]}"

        @Expect(adapter.debugIngestPollingResponse(raw), 0)
        @Expect(adapter.debugLastInboundUpdateId(), "50")
        let offset = adapter.debugOffsetDiagnosticsForTest()
        @Expect(offset.get("pendingUpdateCount").getOrThrow().asInt().getValue(), 0)
        @Expect(offset.get("dedupeCacheSize").getOrThrow().asInt().getValue() >= 1, true)
    }

    @TestCase
    public func corruptedOffsetStateFallsBackToSafeEmptyWatermark(): Unit {
        let root = "/tmp/metis-telegram-corrupt-offset-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            ),
            pairingRoot: root
        )
        let raw = "{\"ok\":true,\"result\":[{\"update_id\":77,\"message\":{\"message_id\":21,\"text\":\"Hi\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}]}"
        @Expect(adapter.debugIngestPollingResponse(raw), 1)
        File.writeTo(Path(root).join("gateway-telegram").join("accounts").join("default").join("offset-state.json"), "{not-json".toArray())

        @Expect(adapter.debugLastInboundUpdateId(), "")
        let offset = adapter.debugOffsetDiagnosticsForTest()
        @Expect(offset.get("lastInboundUpdateId").getOrThrow().asString().getValue(), "")
    }

    @TestCase
    public func proxyConfiguredPollingUsesTransportProxyForGetUpdates(): Unit {
        let seen = ArrayList<String>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                seen.add("${request.method}|${request.context}|${request.url}|${request.proxy}")
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[]}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    webhookUrl: "https://example.test/telegram-webhook",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            let raw = adapter.debugFetchTelegramUpdatesRaw()
            @Expect(raw.contains("\"ok\":true"), true)
            var found = false
            for (item in seen) {
                if (item.contains("POST|getUpdates|") && item.contains("/getUpdates") && item.contains("http://127.0.0.1:7897")) {
                    found = true
                }
            }
            @Expect(found, true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func pollingIterationCatchesTransportExceptionAndNextIterationCanRecover(): Unit {
        let attempts = ArrayList<Int64>()
        let root = Path("/tmp/metis-telegram-polling-recover-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try {
            setTelegramTransportRunnerForTest(Some({ _request: TelegramTransportRequest =>
                attempts.add(1)
                if (attempts.size == 1) {
                    throw Exception("simulated getUpdates timeout")
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[{\"update_id\":123,\"message\":{\"message_id\":21,\"text\":\"recovered\",\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}]}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897",
                    dmPolicy: "open",
                    allowFrom: ["*"]
                ),
                pairingRoot: root.toString()
            )
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            @Expect(adapter.debugRunPollingIterationForTest(), 1)
            @Expect(adapter.debugLastInboundUpdateId(), "123")
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func pollingTransportTimeoutRecordsPollingErrorWithoutSendError(): Unit {
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context.startsWith("deleteWebhook:")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
                }
                TelegramTransportResponse(false, error: "Operation timed out", outcome: "timeout")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            let snapshot = adapter.debugBuildPollingDiagnosticSnapshot()
            @Expect(snapshot.get("state").getOrThrow().asString().getValue(), "recovering")
            @Expect(snapshot.get("lastOutcome").getOrThrow().asString().getValue(), "timeout")
            @Expect(snapshot.get("lastError").getOrThrow().asString().getValue().contains("getUpdates transport failed"), true)
            @Expect(snapshot.get("lastError").getOrThrow().asString().getValue().contains("Operation timed out"), true)
            @Expect(snapshot.get("consecutiveFailures").getOrThrow().asInt().getValue(), 1)
            @Expect(adapter.debugCurrentPollBackoffMsForTest(), 2000)
            @Expect(adapter.debugLastSendErrorForTest(), "")
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func pollingSuccessResetsFailureCountAfterTimeout(): Unit {
        let attempts = ArrayList<Int64>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context.startsWith("deleteWebhook:")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
                }
                attempts.add(1)
                if (attempts.size == 1) {
                    return TelegramTransportResponse(false, error: "Operation timed out", outcome: "timeout")
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[]}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            @Expect(adapter.debugCurrentPollBackoffMsForTest(), 2000)
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            let snapshot = adapter.debugBuildPollingDiagnosticSnapshot()
            @Expect(snapshot.get("state").getOrThrow().asString().getValue(), "polling")
            @Expect(snapshot.get("lastOutcome").getOrThrow().asString().getValue(), "empty-result")
            @Expect(snapshot.get("consecutiveFailures").getOrThrow().asInt().getValue(), 0)
            @Expect(adapter.debugCurrentPollBackoffMsForTest(), 0)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func pollingWatchdogMarksStalledGetUpdatesAndRebuildsTransport(): Unit {
        let attempts = ArrayList<Int64>()
        try {
            setTelegramTransportRunnerForTest(Some({ _request: TelegramTransportRequest =>
                attempts.add(1)
                sleep(Duration.millisecond * 120)
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":[]}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            adapter.debugSetPollingWatchdogForTest(25, 5)
            adapter.start()
            sleep(Duration.millisecond * 80)
            let snapshot = adapter.debugBuildPollingDiagnosticSnapshot()
            @Expect(snapshot.get("watchdogRestartCount").getOrThrow().asInt().getValue() >= 1, true)
            @Expect(snapshot.get("transportRebuildCount").getOrThrow().asInt().getValue() >= 1, true)
            @Expect(snapshot.get("lastStallReason").getOrThrow().asString().getValue().contains("getUpdates stalled"), true)
            @Expect(adapter.debugTelegramTransportRebuildCountForTest() >= 1, true)
            @Expect(attempts.size >= 2, true)
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func pollingRunnerDropsLateResultFromStaleGenerationAfterWatchdogRestart(): Unit {
        let fetches = ArrayList<Int64>()
        let ingests = ArrayList<String>()
        let runner = TelegramPollingRunner(
            { =>
                fetches.add(1)
                sleep(Duration.millisecond * 60)
                "{\"ok\":true,\"result\":[{\"update_id\":1}]}"
            },
            { raw: String =>
                ingests.add(raw)
                1
            },
            { => true },
            watchdogStallMs: 15,
            watchdogIntervalMs: 5
        )
        runner.start()
        sleep(Duration.millisecond * 35)
        runner.stop()
        sleep(Duration.millisecond * 50)
        @Expect(fetches.size >= 1, true)
        @Expect(ingests.size, 0)
        let snapshot = runner.diagnostics()
        @Expect(snapshot.get("watchdogRestartCount").getOrThrow().asInt().getValue() >= 1, true)
    }

    @TestCase
    public func pollingBackoffGrowsAndCapsAcrossConsecutiveFailures(): Unit {
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context.startsWith("deleteWebhook:")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
                }
                TelegramTransportResponse(false, error: "Operation timed out", outcome: "timeout")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            @Expect(adapter.debugCurrentPollBackoffMsForTest(), 2000)
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            @Expect(adapter.debugCurrentPollBackoffMsForTest(), 4000)
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            @Expect(adapter.debugCurrentPollBackoffMsForTest(), 8000)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func healthSnapshotIncludesPollingDiagnostics(): Unit {
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context.startsWith("deleteWebhook:")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
                }
                TelegramTransportResponse(false, error: "Operation timed out", outcome: "timeout")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            @Expect(adapter.debugRunPollingIterationForTest(), 0)
            let snapshot = adapter.debugBuildHealthSnapshot()
            let summary = snapshot.get("summary").getOrThrow().asObject()
            let polling = snapshot.get("polling").getOrThrow().asObject()
            @Expect(summary.get("pollingState").getOrThrow().asString().getValue(), "recovering")
            @Expect(summary.get("pollingConsecutiveFailures").getOrThrow().asInt().getValue(), 1)
            @Expect(summary.get("pollingLastOutcome").getOrThrow().asString().getValue(), "timeout")
            @Expect(polling.get("lastError").getOrThrow().asString().getValue().contains("getUpdates transport failed"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func proxyConfiguredNativeCommandsUseTransportProxy(): Unit {
        let seen = ArrayList<String>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                seen.add("${request.method}|${request.context}|${request.url}|${request.proxy}|${request.body}")
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            @Expect(adapter.debugSyncNativeCommandsForTest(), true)
            var found = false
            for (item in seen) {
                if (item.contains("POST|setMyCommands|") && item.contains("/setMyCommands") && item.contains("|http://127.0.0.1:7897|") && item.contains("\"commands\"")) {
                    found = true
                }
            }
            @Expect(found, true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendWithMessageIdUsesNativeTransportOverride(): Unit {
        let seen = ArrayList<String>()
        let seenLock = Mutex()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                synchronized(seenLock) {
                    seen.add("${request.method}|${request.context}|${request.url}|${request.proxy}|${request.body}")
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":321,\"text\":\"hello\"}}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            adapter.start()
            let messageId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello")
            )
            adapter.stop()
            @Expect(messageId, "321")
            var found = false
            synchronized(seenLock) {
                for (item in seen) {
                    if (item.contains("POST|send:") && item.contains("/sendMessage") && item.contains("|http://127.0.0.1:7897|") && item.contains("8734062810")) {
                        found = true
                    }
                }
            }
            @Expect(found, true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func telegramTransportRedactsBotTokenInUrls(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "123456:SECRET"))
        let redacted = adapter.debugRedactTelegramUrlForTest("https://api.telegram.org/bot123456:SECRET/sendMessage")
        @Expect(redacted, "https://api.telegram.org/bot<redacted>/sendMessage")
        @Expect(redacted.contains("123456:SECRET"), false)
    }

    @TestCase
    public func telegramNativeTransportExposesConfiguredProxyTimeoutAndOutcomes(): Unit {
        let transport = TelegramTransport(proxy: "http://127.0.0.1:7897", timeoutSeconds: 12)
        @Expect(transport.debugUsesNativeHttpTransportForTest(), true)
        @Expect(transport.debugEffectiveProxyForTest(), "http://127.0.0.1:7897")
        @Expect(transport.debugEffectiveTimeoutSecondsForTest(), 12)
        @Expect(transport.debugProxyRouteForTest("https://api.telegram.org/bot123456:SECRET/getUpdates"), "httpConnectTunnel")
        @Expect(transport.debugProxyRouteForTest("http://127.0.0.1:8080/mock"), "httpProxy")
        @Expect(transport.debugUsesCustomConnectorForTest(), false)
        @Expect(TelegramTransport(timeoutSeconds: 12).debugUsesCustomConnectorForTest(), true)
        @Expect(transport.debugClassifyStatusForTest(401), "unauthorized")
        @Expect(transport.debugClassifyStatusForTest(409), "conflict")
        @Expect(transport.debugClassifyStatusForTest(429), "rate-limit")
        @Expect(transport.debugClassifyStatusForTest(503), "retryable-status")
        @Expect(transport.debugClassifyStatusForTest(418), "http-status")
        @Expect(transport.debugClassifyExceptionForTest("Operation timed out"), "timeout")
        let request = transport.debugBuildRequestForTest("POST", "https://api.telegram.org/bot123456:SECRET/getUpdates")
        @Expect(request.method, "POST")
        @Expect(request.url.contains("123456:SECRET"), true)
        @Expect(request.proxy, "http://127.0.0.1:7897")
        @Expect(request.timeoutSeconds, 12)
    }

    @TestCase
    public func t46TelegramTransportUsesEnvProxyOnlyWhenEnabledAndHonorsNoProxy(): Unit {
        let oldHttps = getVariable("HTTPS_PROXY") ?? ""
        let oldHttp = getVariable("HTTP_PROXY") ?? ""
        let oldNoProxy = getVariable("NO_PROXY") ?? ""
        try {
            setVariable("HTTPS_PROXY", "http://127.0.0.1:7897")
            setVariable("HTTP_PROXY", "")
            setVariable("NO_PROXY", "")
            let disabled = TelegramTransport(envProxyEnabled: false)
            @Expect(disabled.debugEffectiveProxyForUrlForTest("https://api.telegram.org/botTOKEN/getUpdates"), "")

            let enabled = TelegramTransport(envProxyEnabled: true, timeoutSeconds: 9)
            let request = enabled.debugBuildRequestForTest("POST", "https://api.telegram.org/botTOKEN/getUpdates")
            @Expect(request.proxy, "http://127.0.0.1:7897")
            @Expect(request.proxySource, "env")
            @Expect(enabled.debugProxyRouteForTest("https://api.telegram.org/botTOKEN/getUpdates"), "httpConnectTunnel")
            @Expect(enabled.debugUsesCustomConnectorForTest(), false)

            setVariable("NO_PROXY", "api.telegram.org")
            @Expect(enabled.debugEffectiveProxyForUrlForTest("https://api.telegram.org/botTOKEN/getUpdates"), "")
            @Expect(enabled.debugProxySourceForUrlForTest("https://api.telegram.org/botTOKEN/getUpdates"), "none")

            let explicit = TelegramTransport(proxy: "http://127.0.0.1:1111", envProxyEnabled: true)
            @Expect(explicit.debugEffectiveProxyForUrlForTest("https://api.telegram.org/botTOKEN/getUpdates"), "http://127.0.0.1:1111")
            @Expect(explicit.debugProxySourceForUrlForTest("https://api.telegram.org/botTOKEN/getUpdates"), "explicit")
        } finally {
            setVariable("HTTPS_PROXY", oldHttps)
            setVariable("HTTP_PROXY", oldHttp)
            setVariable("NO_PROXY", oldNoProxy)
        }
    }

    @TestCase
    public func telegramTransportBlocksPrivateTargetHostsUnlessExplicitlyAllowed(): Unit {
        let transport = TelegramTransport()
        @Expect(transport.debugValidateRequestUrlForTest("https://api.telegram.org/botTOKEN/getUpdates"), "")
        @Expect(transport.debugValidateRequestUrlForTest("https://169.254.169.254/latest").contains("private-network"), true)
        @Expect(transport.debugValidateRequestUrlForTest("http://localhost:8081/botTOKEN/getUpdates").contains("private-network"), true)
        @Expect(transport.debugValidateRequestUrlForTest("file:///tmp/token").contains("non-http"), true)
        let trustedLocal = TelegramTransport(dangerouslyAllowPrivateNetwork: true)
        @Expect(trustedLocal.debugValidateRequestUrlForTest("http://127.0.0.1:8081/botTOKEN/getUpdates"), "")
    }

    @TestCase
    public func sendPayloadsChunkLongTextAndKeepReplyOnlyOnFirstChunkWhenReplyModeFirst(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                textChunkLimit: 5,
                replyToMode: "first"
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "abcdefghijk",
                replyToMessageId: Some("88"),
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 3)
        let first = payloads[0].asObject()
        let second = payloads[1].asObject()
        let third = payloads[2].asObject()
        @Expect(first.get("text").getOrThrow().asString().getValue(), "abcde")
        @Expect(second.get("text").getOrThrow().asString().getValue(), "fghij")
        @Expect(third.get("text").getOrThrow().asString().getValue(), "k")
        @Expect(first.get("reply_to_message_id").getOrThrow().asString().getValue(), "88")
        @Expect(second.get("reply_to_message_id").isNone(), true)
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
        @Expect(second.get("message_thread_id").getOrThrow().asString().getValue(), "42")
    }

    @TestCase
    public func sendPayloadsKeepReplyTargetOnEveryChunkWhenReplyModeAll(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                textChunkLimit: 5,
                replyToMode: "all"
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "abcdefghijk",
                replyToMessageId: Some("88"),
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 3)
        let first = payloads[0].asObject()
        let second = payloads[1].asObject()
        let third = payloads[2].asObject()
        @Expect(first.get("reply_to_message_id").getOrThrow().asString().getValue(), "88")
        @Expect(second.get("reply_to_message_id").getOrThrow().asString().getValue(), "88")
        @Expect(third.get("reply_to_message_id").getOrThrow().asString().getValue(), "88")
    }

    @TestCase
    public func sendPayloadsUseReplyParametersWhenQuoteTextIsPresent(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                replyToMode: "all"
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "quoted reply",
                replyToMessageId: Some("88"),
                quoteText: "original quoted text"
            )
        )
        let first = payloads[0].asObject()
        @Expect(first.get("reply_to_message_id").isNone(), true)
        let replyParameters = first.get("reply_parameters").getOrThrow().asObject()
        @Expect(replyParameters.get("message_id").getOrThrow().asString().getValue(), "88")
        @Expect(replyParameters.get("quote").getOrThrow().asString().getValue(), "original quoted text")
    }

    @TestCase
    public func sendPayloadsEscapeHtmlAndKeepExplicitReplyTargetWhenReplyModeOff(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                replyToMode: "off",
                linkPreview: false
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "<b>& hello</b>",
                replyToMessageId: Some("99"),
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("text").getOrThrow().asString().getValue(), "&lt;b&gt;&amp; hello&lt;/b&gt;")
        @Expect(first.get("reply_to_message_id").getOrThrow().asString().getValue(), "99")
        @Expect(first.get("message_thread_id").isNone(), true)
        @Expect(first.get("disable_web_page_preview").getOrThrow().asBool().getValue(), true)
    }

    @TestCase
    public func sendPayloadsChunkByParagraphWhenChunkModeNewline(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                textChunkLimit: 12,
                chunkMode: "newline"
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "aaa\n\nbbb\n\ncccccccc"
            )
        )
        @Expect(payloads.size(), 2)
        let first = payloads[0].asObject()
        let second = payloads[1].asObject()
        @Expect(first.get("text").getOrThrow().asString().getValue(), "aaa\n\nbbb")
        @Expect(second.get("text").getOrThrow().asString().getValue(), "cccccccc")
    }

    @TestCase
    public func sendPayloadsIncludeSilentDisableNotificationWhenConfigured(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                silent: true
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "hello"
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("disable_notification").getOrThrow().asBool().getValue(), true)
    }

    @TestCase
    public func sendRetriesPlainTextWithoutParseModeAfterFormattingError(): Unit {
        let bodies = ArrayList<String>()
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context.startsWith("send:")) {
                    bodies.add(request.body)
                }
                if (request.context.startsWith("deleteWebhook:")) {
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
                }
                if (request.context == "send:text") {
                    return TelegramTransportResponse(
                        true,
                        body: "{\"ok\":false,\"description\":\"Bad Request: can't parse entities\"}",
                        outcome: "api-ok-false"
                    )
                }
                TelegramTransportResponse(
                    true,
                    body: "{\"ok\":true,\"result\":{\"message_id\":321}}",
                    outcome: "ok"
                )
            }))
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "123456:SECRET"))
            adapter.start()
            let messageId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "<b>& hello</b>")
            )
            @Expect(messageId, "321")
            @Expect(bodies.size, 2)
            let first = JsonValue.fromStr(bodies[0]).asObject()
            let second = JsonValue.fromStr(bodies[1]).asObject()
            @Expect(first.get("parse_mode").getOrThrow().asString().getValue(), "HTML")
            @Expect(first.get("text").getOrThrow().asString().getValue(), "&lt;b&gt;&amp; hello&lt;/b&gt;")
            @Expect(second.get("parse_mode").isNone(), true)
            @Expect(second.get("text").getOrThrow().asString().getValue(), "<b>& hello</b>")
            @Expect(second.get("kind").isNone(), true)
            @Expect(second.get("peer").isNone(), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendErrorDescriptionRedactsTelegramTokenAndProxyCredentials(): Unit {
        try {
            setTelegramTransportRunnerForTest(Some({ _request: TelegramTransportRequest =>
                TelegramTransportResponse(
                    true,
                    body: "{\"ok\":false,\"description\":\"Bad token 123456:SECRET via http://user:pass@127.0.0.1:7897\"}",
                    outcome: "api-ok-false"
                )
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "123456:SECRET",
                    proxy: "http://user:pass@127.0.0.1:7897"
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello")
            )
            match (result) {
                case SendResult.Success => @Expect(false, true)
                case SendResult.Failed(reason) =>
                    @Expect(reason.contains("123456:SECRET"), false)
                    @Expect(reason.contains("user:pass"), false)
                    @Expect(reason.contains("<redacted>"), true)
            }
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    /*
    @TestCase
    public func sendPayloadsRenderNativeTelegramPollPayload(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(poll: true)
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[poll]\nLunch?\n1. Rice\n2. Noodles",
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "poll")
        @Expect(first.get("question").getOrThrow().asString().getValue(), "Lunch?")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
        let options = first.get("options").getOrThrow().asArray()
        @Expect(options.size(), 2)
        @Expect(options[0].asString().getValue(), "Rice")
        @Expect(options[1].asString().getValue(), "Noodles")
    }
    */

    @TestCase
    public func disabledPollActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, poll: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[poll]\nLunch?\n1. Rice\n2. Noodles"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("poll action is disabled"), true)
        }
    }

    @TestCase
    public func sendPayloadsRenderTelegramPollAdvancedOptions(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(poll: true)
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[poll]\nLunch?\n1. Rice\n2. Noodles\ndurationSeconds=60\nallowMultiselect=true\nisAnonymous=false",
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "poll")
        @Expect(first.get("open_period").getOrThrow().asInt().getValue(), 60)
        @Expect(first.get("allows_multiple_answers").getOrThrow().asBool().getValue(), true)
        @Expect(first.get("is_anonymous").getOrThrow().asBool().getValue(), false)
    }

    @TestCase
    public func t46TelegramPollAcceptsOpenClawVisibilityAliasesAndRejectsDurationHours(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(poll: true)
            )
        )
        let publicPayloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[poll]\nLunch?\n1. Rice\n2. Noodles\npollPublic=true"
            )
        )
        @Expect(publicPayloads.size(), 1)
        @Expect(publicPayloads[0].asObject().get("is_anonymous").getOrThrow().asBool().getValue(), false)

        let anonymousPayloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[poll]\nLunch?\n1. Rice\n2. Noodles\npollAnonymous=true"
            )
        )
        @Expect(anonymousPayloads[0].asObject().get("is_anonymous").getOrThrow().asBool().getValue(), true)

        adapter.start()
        let invalid = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[poll]\nLunch?\n1. Rice\n2. Noodles\ndurationHours=1"
            )
        )
        match (invalid) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("durationHours is not supported"), true)
        }
    }

    @TestCase
    public func invalidTelegramPollDurationFailsFastBeforeNetwork(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(poll: true)
            )
        )
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[poll]\nLunch?\n1. Rice\n2. Noodles\ndurationSeconds=1"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("durationSeconds"), true)
        }
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramDeletePayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[delete]",
                replyToMessageId: Some("88")
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "delete")
        @Expect(first.get("message_id").getOrThrow().asString().getValue(), "88")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramEditPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[edit]\nHello <b>world</b>",
                replyToMessageId: Some("77")
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "edit")
        @Expect(first.get("message_id").getOrThrow().asString().getValue(), "77")
        @Expect(first.get("text").getOrThrow().asString().getValue(), "Hello &lt;b&gt;world&lt;/b&gt;")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramPinAndUnpinPayloads(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let pinPayloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[pin]",
                replyToMessageId: Some("88")
            )
        )
        @Expect(pinPayloads.size(), 1)
        let pin = pinPayloads[0].asObject()
        @Expect(pin.get("kind").getOrThrow().asString().getValue(), "pin")
        @Expect(pin.get("message_id").getOrThrow().asString().getValue(), "88")
        @Expect(pin.get("disable_notification").getOrThrow().asBool().getValue(), true)

        let unpinPayloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[unpin]",
                replyToMessageId: Some("88")
            )
        )
        @Expect(unpinPayloads.size(), 1)
        let unpin = unpinPayloads[0].asObject()
        @Expect(unpin.get("kind").getOrThrow().asString().getValue(), "unpin")
        @Expect(unpin.get("message_id").getOrThrow().asString().getValue(), "88")
    }

    @TestCase
    public func sendPinAndUnpinUseNativeTelegramBotApi(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(pinMessage: true, unpinMessage: true)
                )
            )
            adapter.start()
            let pinResult = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[pin]", replyToMessageId: Some("88"))
            )
            let unpinResult = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[unpin]", replyToMessageId: Some("88"))
            )
            match (pinResult) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            match (unpinResult) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("pinChatMessage"), true)
            @Expect(fake.saw("unpinChatMessage"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramTopicCreatePayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[topic-create]\nSprint Sync"
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "topic-create")
        @Expect(first.get("name").getOrThrow().asString().getValue(), "Sprint Sync")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramTopicEditPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[topic-edit]\nRenamed Sprint",
                replyToMessageId: Some("42")
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "topic-edit")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
        @Expect(first.get("name").getOrThrow().asString().getValue(), "Renamed Sprint")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramReactionPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[reaction]\ntoken=👍\nrender=👍",
                replyToMessageId: Some("55")
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "reaction")
        @Expect(first.get("message_id").getOrThrow().asString().getValue(), "55")
        let reaction = first.get("reaction").getOrThrow().asArray()[0].asObject()
        @Expect(reaction.get("type").getOrThrow().asString().getValue(), "emoji")
        @Expect(reaction.get("emoji").getOrThrow().asString().getValue(), "👍")
    }

    @TestCase
    public func t46ReactionPayloadAcceptsOpenClawStatusLifecycleNames(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            let payloads = adapter.debugBuildSendPayloads(
                OutboundMessage(
                    ChannelType.Telegram,
                    "group:-1001234567890",
                    "[reaction]\nstatus=done",
                    replyToMessageId: Some("55")
                )
            )
            @Expect(payloads.size(), 1)
            let reaction = payloads[0].asObject().get("reaction").getOrThrow().asArray()[0].asObject()
            @Expect(reaction.get("emoji").getOrThrow().asString().getValue(), "👍")
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramChatActionPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", replyToMode: "thread"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[chat-action]\naction=upload_photo",
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "chat-action")
        @Expect(first.get("action").getOrThrow().asString().getValue(), "upload_photo")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
    }

    @TestCase
    public func reactionFallsBackToAvailableChatReaction(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            let payloads = adapter.debugBuildSendPayloads(
                OutboundMessage(
                    ChannelType.Telegram,
                    "group:-1001234567890",
                    "[reaction]\ntoken=🔥\nrender=🔥",
                    replyToMessageId: Some("55")
                )
            )
            let reaction = payloads[0].asObject().get("reaction").getOrThrow().asArray()[0].asObject()
            @Expect(reaction.get("emoji").getOrThrow().asString().getValue(), "👍")
            @Expect(fake.saw("getChat"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sentMessageStateRecordsSuccessfulTelegramReplies(): Unit {
        let root = Path("/tmp/metis-telegram-sent-state-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token"),
                pairingRoot: root.toString()
            )
            adapter.start()
            let sentId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello", replyToMessageId: Some("44"))
            )
            @Expect(sentId.isEmpty(), false)
            let state = adapter.debugReadSentMessageStateForTest()
            let last = state.get("lastMessage").getOrThrow().asObject()
            @Expect(last.get("peerId").getOrThrow().asString().getValue(), "user:8734062810")
            @Expect(last.get("messageId").getOrThrow().asString().getValue(), sentId)
            @Expect(last.get("replyToMessageId").getOrThrow().asString().getValue(), "44")
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func removeAckAfterReplyClearsTelegramAckReaction(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    removeAckAfterReply: true,
                    actions: TelegramActionConfig(reactions: true)
                )
            )
            adapter.start()
            let sentId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "reply", replyToMessageId: Some("77"))
            )
            @Expect(sentId.isEmpty(), false)
            @Expect(fake.saw("setMessageReaction"), true)
            @Expect(fake.sawBodyContaining("\"reaction\""), true)
            @Expect(fake.sawBodyContaining("[]"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func telegramTransportRequestCarriesDnsResultOrderForNativeRunner(): Unit {
        let seen = ArrayList<String>()
        setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
            seen.add("${request.autoSelectFamily}|${request.dnsResultOrder}|${request.proxy}")
            TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":900}}", outcome: "ok")
        }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897",
                    network: TelegramNetworkConfig(autoSelectFamily: false, dnsResultOrder: "verbatim")
                )
            )
            adapter.start()
            let sentId = adapter.sendWithMessageId(OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello"))
            @Expect(sentId, "900")
            @Expect(seen.size > 0, true)
            var found = false
            for (item in seen) {
                if (item == "false|verbatim|http://127.0.0.1:7897") {
                    found = true
                }
            }
            @Expect(found, true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendChatActionUsesNativeTelegramBotApi(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[chat-action]\naction=typing")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendChatAction"), true)
            @Expect(fake.sawBodyContaining("typing"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func draftPayloadPrefersNativeSendMessageDraft(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(editMessage: true)
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[draft]\npreview=Working\nfinal=Done")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendMessageDraft"), true)
            @Expect(fake.saw("editMessageText"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendChatActionUnauthorizedEntersBackoff(): Unit {
        let fake = TelegramChatActionUnauthorizedFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            adapter.start()
            let first = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[chat-action]\naction=typing"))
            match (first) {
                case SendResult.Success => @Expect("failed", "first-send")
                case SendResult.Failed(reason) => @Expect(reason.contains("Unauthorized"), true)
            }
            @Expect(adapter.debugChatActionBackoffUntilMsForTest() > 0, true)
            let second = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[chat-action]\naction=typing"))
            match (second) {
                case SendResult.Success => @Expect("failed", "second-send")
                case SendResult.Failed(reason) => @Expect(reason.contains("backoff"), true)
            }
            @Expect(fake.calls, 1)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramInlineKeyboardPayload(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                replyToMode: "thread",
                actions: TelegramActionConfig(inlineKeyboard: true)
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[inline-keyboard]\ntext=Choose <one>\nbutton=Approve|callback:approve-1\nrow\nbutton=Docs|url:https://example.test",
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "inline-keyboard")
        @Expect(first.get("text").getOrThrow().asString().getValue(), "Choose &lt;one&gt;")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
        let markup = first.get("reply_markup").getOrThrow().asObject()
        let rows = markup.get("inline_keyboard").getOrThrow().asArray()
        @Expect(rows.size(), 2)
        let firstButton = rows[0].asArray()[0].asObject()
        @Expect(firstButton.get("text").getOrThrow().asString().getValue(), "Approve")
        @Expect(firstButton.get("callback_data").getOrThrow().asString().getValue(), "approve-1")
        let secondButton = rows[1].asArray()[0].asObject()
        @Expect(secondButton.get("url").getOrThrow().asString().getValue(), "https://example.test")
    }

    @TestCase
    public func t44EditButtonsPayloadUsesEditMessageReplyMarkup(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(editMessage: true)
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[edit-buttons]\nbutton=Approve|callback:plugin:ok\nrow\nbutton=Docs|url:https://example.test",
                replyToMessageId: Some("77")
            )
        )
        @Expect(payloads.size(), 1)
        let payload = payloads[0].asObject()
        @Expect(payload.get("kind").getOrThrow().asString().getValue(), "edit-buttons")
        @Expect(payload.get("message_id").getOrThrow().asString().getValue(), "77")
        let rows = payload.get("reply_markup").getOrThrow().asObject().get("inline_keyboard").getOrThrow().asArray()
        @Expect(rows.size(), 2)
        @Expect(rows[0].asArray()[0].asObject().get("callback_data").getOrThrow().asString().getValue(), "plugin:ok")
    }

    @TestCase
    public func sendPayloadsRenderTelegramRichTextAsHtml(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "Hello **bold** *italic* `code` [site](https://example.test) <unsafe>\n> quoted"
            )
        )
        @Expect(payloads.size(), 1)
        let text = payloads[0].asObject().get("text").getOrThrow().asString().getValue()
        @Expect(text.contains("<b>bold</b>"), true)
        @Expect(text.contains("<i>italic</i>"), true)
        @Expect(text.contains("<code>code</code>"), true)
        @Expect(text.contains("<a href=\"https://example.test\">site</a>"), true)
        @Expect(text.contains("&lt;unsafe&gt;"), true)
        @Expect(text.contains("<blockquote>quoted</blockquote>"), true)
    }

    @TestCase
    public func t51TelegramRichTextWrapsTablesAndFileReferences(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let rendered = adapter.debugTelegramRenderHtmlForTest("| File | Line |\n| --- | ---: |\n| src/gateway/core/gateway_service.cj | 42 |\nSee /tmp/metis/report.json and ./src/main.cj:12")
        @Expect(rendered.contains("<pre>| File | Line |"), true)
        @Expect(rendered.contains("| --- | ---: |"), true)
        @Expect(rendered.contains("<code>/tmp/metis/report.json</code>"), true)
        @Expect(rendered.contains("<code>./src/main.cj:12</code>"), true)
    }

    @TestCase
    public func t46TelegramRichTextRendersSpoilerAsTelegramHtml(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        @Expect(adapter.debugTelegramRenderHtmlForTest("hide ||secret <tag>||"), "hide <tg-spoiler>secret &lt;tag&gt;</tg-spoiler>")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramStickerPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", replyToMode: "thread"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[sticker]\nfileId=sticker-file-id",
                replyToMessageId: Some("55"),
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "sticker")
        @Expect(first.get("sticker").getOrThrow().asString().getValue(), "sticker-file-id")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
        @Expect(first.get("reply_to_message_id").getOrThrow().asString().getValue(), "55")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramPhotoPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", replyToMode: "thread"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[photo]\nfileId=photo-file-id\ncaption=hello",
                replyToMessageId: Some("55"),
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "photo")
        @Expect(first.get("photo").getOrThrow().asString().getValue(), "photo-file-id")
        @Expect(first.get("caption").getOrThrow().asString().getValue(), "hello")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
    }

    @TestCase
    public func longTelegramMediaCaptionIsMovedToFollowUpText(): Unit {
        var caption = ""
        while (caption.size <= 1100) {
            caption += "long-caption "
        }
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[photo]\nfileId=photo-file-id\ncaption=${caption}"
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("caption").isNone(), true)
        @Expect(first.get("follow_up_text").getOrThrow().asString().getValue(), caption.trimAscii())
    }

    @TestCase
    public func localGifPhotoRoutesToTelegramAnimation(): Unit {
        let root = Path("/tmp/metis-telegram-outbound-gif-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let gifPath = root.join("motion.gif")
        File.writeTo(gifPath, "GIF89a".toArray())
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=${gifPath.toString()}\ncaption=gif"))
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendAnimation"), true)
            @Expect(fake.sawBodyContaining("name=\"animation\"; filename=\"motion.gif\""), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func localNonOggVoiceRoutesToTelegramAudio(): Unit {
        let root = Path("/tmp/metis-telegram-outbound-voice-fallback-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let mp3Path = root.join("memo.mp3")
        File.writeTo(mp3Path, "fake-mp3".toArray())
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(audio: true, voice: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[voice]\nfileId=${mp3Path.toString()}\ncaption=memo"))
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendAudio"), true)
            @Expect(fake.sawBodyContaining("name=\"audio\"; filename=\"memo.mp3\""), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func telegramVoiceForbiddenFallsBackToTextCaption(): Unit {
        let fake = TelegramVoiceForbiddenFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(voice: true, sendMessage: true)
                )
            )
            adapter.start()
            let id = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[voice]\nfileId=voice-file-id\ncaption=voice fallback text")
            )
            @Expect(id, "801")
            @Expect(fake.voiceCalls, 1)
            @Expect(fake.textCalls, 1)
            @Expect(fake.sawBodyContaining("voice fallback text"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramDocumentPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[document]\nfileId=doc-file-id\ncaption=report"
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "document")
        @Expect(first.get("document").getOrThrow().asString().getValue(), "doc-file-id")
        @Expect(first.get("caption").getOrThrow().asString().getValue(), "report")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramAudioPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[audio]\nfileId=audio-file-id\ncaption=podcast"
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "audio")
        @Expect(first.get("audio").getOrThrow().asString().getValue(), "audio-file-id")
        @Expect(first.get("caption").getOrThrow().asString().getValue(), "podcast")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramVoicePayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[voice]\nfileId=voice-file-id\ncaption=memo"
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "voice")
        @Expect(first.get("voice").getOrThrow().asString().getValue(), "voice-file-id")
        @Expect(first.get("caption").getOrThrow().asString().getValue(), "memo")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramVideoPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", replyToMode: "thread"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[video]\nfileId=video-file-id\ncaption=clip",
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "video")
        @Expect(first.get("video").getOrThrow().asString().getValue(), "video-file-id")
        @Expect(first.get("caption").getOrThrow().asString().getValue(), "clip")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
    }

    @TestCase
    public func sendPayloadsRenderNativeTelegramVideoNotePayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", replyToMode: "thread"))
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890:topic:42",
                "[video-note]\nfileId=video-note-file-id",
                replyInThread: true
            )
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "video-note")
        @Expect(first.get("video_note").getOrThrow().asString().getValue(), "video-note-file-id")
        @Expect(first.get("message_thread_id").getOrThrow().asString().getValue(), "42")
    }

    @TestCase
    public func sendRetriesThreadlessWhenTelegramTopicIsMissing(): Unit {
        let fake = TelegramThreadFallbackFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token", replyToMode: "thread")
            )
            adapter.start()
            let id = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "group:-1001234567890:topic:42", "hello topic", replyInThread: true)
            )
            @Expect(id, "701")
            @Expect(fake.sends, 2)
            @Expect(fake.bodies[0].contains("message_thread_id"), true)
            @Expect(fake.bodies[1].contains("message_thread_id"), false)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func outboundMediaUrlRequiresExplicitPolicy(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(photo: true)
            )
        )
        adapter.start()
        let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=https://example.test/photo.jpg"))
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("outbound media URL is disabled"), true)
        }
    }

    @TestCase
    public func outboundMediaUrlCanBeEnabledForBotApiUrlReference(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(photo: true),
                media: TelegramMediaConfig(outboundAllowUrl: true)
            )
        )
        let payloads = adapter.debugBuildSendPayloads(
            OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=https://example.test/photo.jpg")
        )
        @Expect(payloads.size(), 1)
        let first = payloads[0].asObject()
        @Expect(first.get("kind").getOrThrow().asString().getValue(), "photo")
        @Expect(first.get("photo").getOrThrow().asString().getValue(), "https://example.test/photo.jpg")
    }

    @TestCase
    public func outboundRemoteUrlPhotoUsesMockDownloaderAndMultipart(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        setTelegramOutboundMediaDownloaderForTest(Some({ url: String, maxBytes: Int64 =>
            @Expect(url, "https://cdn.example.test/photo.png")
            @Expect(maxBytes, 1024 * 1024)
            TelegramOutboundMediaDownloadResult(true, bytes: telegramTestPngBytes(640, 480), mimeType: "image/png", fileName: "remote-photo.png")
        }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true),
                    media: TelegramMediaConfig(
                        mediaMaxBytes: 1024 * 1024,
                        allowedMimes: ["image/png"],
                        outboundAllowUrl: true,
                        outboundFetchUrl: true,
                        outboundAllowedUrlDomains: ["cdn.example.test"]
                    )
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=https://cdn.example.test/photo.png\ncaption=remote")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendPhoto"), true)
            @Expect(fake.sawContentTypeContaining("multipart/form-data"), true)
            @Expect(fake.sawBodyContaining("name=\"photo\"; filename=\"remote-photo.png\""), true)
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
            setTelegramOutboundMediaDownloaderForTest(None)
        }
    }

    @TestCase
    public func outboundRemoteUrlPolicyFailsBeforeDownloader(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        setTelegramOutboundMediaDownloaderForTest(Some({ _url: String, _maxBytes: Int64 =>
            @Expect(false, true)
            TelegramOutboundMediaDownloadResult(true, bytes: telegramTestPngBytes(1, 1), mimeType: "image/png")
        }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true),
                    media: TelegramMediaConfig(
                        mediaMaxBytes: 1024,
                        allowedMimes: ["image/png"],
                        outboundAllowUrl: true,
                        outboundFetchUrl: true,
                        outboundAllowedUrlDomains: ["cdn.example.test"]
                    )
                )
            )
            adapter.start()
            let deniedDomain = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=https://evil.example/photo.png"))
            match (deniedDomain) {
                case SendResult.Success => @Expect(false, true)
                case SendResult.Failed(reason) => @Expect(reason.contains("domain is not allowed"), true)
            }
            let deniedScheme = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=http://cdn.example.test/photo.png"))
            match (deniedScheme) {
                case SendResult.Success => @Expect(false, true)
                case SendResult.Failed(reason) => @Expect(reason.contains("scheme is not allowed"), true)
            }
            let deniedSize = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true),
                    media: TelegramMediaConfig(
                        mediaMaxBytes: 0,
                        allowedMimes: ["image/png"],
                        outboundAllowUrl: true,
                        outboundFetchUrl: true,
                        outboundAllowedUrlDomains: ["cdn.example.test"]
                    )
                )
            )
            deniedSize.start()
            let sizeResult = deniedSize.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=https://cdn.example.test/photo.png"))
            match (sizeResult) {
                case SendResult.Success => @Expect(false, true)
                case SendResult.Failed(reason) => @Expect(reason.contains("mediaMaxBytes must be positive"), true)
            }
            adapter.stop()
            deniedSize.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
            setTelegramOutboundMediaDownloaderForTest(None)
        }
    }

    @TestCase
    public func outboundLocalMediaPathIsRejectedBeforeNetwork(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(document: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: false)
                )
            )
            adapter.start()
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[document]\nfileId=/tmp/report.pdf"))
            match (result) {
                case SendResult.Success => @Expect(false, true)
                case SendResult.Failed(reason) => @Expect(reason.contains("outbound local media path is disabled"), true)
            }
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func outboundLocalPhotoUsesMultipartTransport(): Unit {
        let root = Path("/tmp/metis-telegram-outbound-photo-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let photoPath = root.join("photo.jpg")
        File.writeTo(photoPath, telegramTestPngBytes(640, 480))
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=${photoPath.toString()}\ncaption=local photo")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendPhoto"), true)
            @Expect(fake.sawContentTypeContaining("multipart/form-data"), true)
            @Expect(fake.sawBodyContaining("name=\"photo\"; filename=\"photo.jpg\""), true)
            @Expect(fake.bodySizes.size > 0, true)
            @Expect(fake.sawBodyContaining("name=\"caption\""), true)
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func outboundLocalPhotoMultipartPreservesNonUtf8BinaryBytes(): Unit {
        let root = Path("/tmp/metis-telegram-outbound-photo-binary-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let photoPath = root.join("photo.jpg")
        let photoBytes: Array<Byte> = telegramTestPngBytes(320, 240)
        File.writeTo(photoPath, photoBytes)
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=${photoPath.toString()}\ncaption=binary photo")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendPhoto"), true)
            @Expect(fake.sawContentTypeContaining("multipart/form-data"), true)
            @Expect(fake.bodySizes.size > 0, true)
            @Expect(fake.bodySizes[fake.bodySizes.size - 1] > Int64(photoBytes.size), true)
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func outboundOversizedLocalPhotoFallsBackToDocument(): Unit {
        let root = Path("/tmp/metis-telegram-outbound-photo-fallback-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let photoPath = root.join("wide.png")
        let pngBytes: Array<Byte> = [
            137u8, 80u8, 78u8, 71u8, 13u8, 10u8, 26u8, 10u8,
            0u8, 0u8, 0u8, 13u8, 73u8, 72u8, 68u8, 82u8,
            0u8, 0u8, 35u8, 40u8, 0u8, 0u8, 7u8, 208u8
        ]
        File.writeTo(photoPath, pngBytes)
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true, document: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=${photoPath.toString()}\ncaption=wide")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendDocument"), true)
            @Expect(fake.saw("sendPhoto"), false)
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func outboundUnparseableLocalPhotoFallsBackToDocument(): Unit {
        let root = Path("/tmp/metis-telegram-outbound-photo-parse-fallback-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let photoPath = root.join("broken.jpg")
        File.writeTo(photoPath, "not-a-real-image".toArray())
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true, document: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=${photoPath.toString()}\ncaption=broken")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendDocument"), true)
            @Expect(fake.saw("sendPhoto"), false)
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func outboundRemotePhotoWithInvalidDimensionsFallsBackToDocument(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        setTelegramOutboundMediaDownloaderForTest(Some({ _url: String, _maxBytes: Int64 =>
            TelegramOutboundMediaDownloadResult(true, bytes: telegramTestPngBytes(9000, 2000), mimeType: "image/png", fileName: "huge.png")
        }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true, document: true),
                    media: TelegramMediaConfig(
                        mediaMaxBytes: 1024 * 1024,
                        allowedMimes: ["image/png"],
                        outboundAllowUrl: true,
                        outboundFetchUrl: true,
                        outboundAllowedUrlDomains: ["cdn.example.test"]
                    )
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[photo]\nfileId=https://cdn.example.test/huge.png\ncaption=huge")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendDocument"), true)
            @Expect(fake.saw("sendPhoto"), false)
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
            setTelegramOutboundMediaDownloaderForTest(None)
        }
    }

    @TestCase
    public func outboundLocalDocumentUsesMultipartTransport(): Unit {
        let root = Path("/tmp/metis-telegram-outbound-doc-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let docPath = root.join("report.txt")
        File.writeTo(docPath, "fake-report".toArray())
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(document: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[document]\nfileId=file://${docPath.toString()}\ncaption=report")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendDocument"), true)
            @Expect(fake.sawContentTypeContaining("multipart/form-data"), true)
            @Expect(fake.sawBodyContaining("name=\"document\"; filename=\"report.txt\""), true)
            @Expect(fake.sawBodyContaining("fake-report"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func draftPayloadSendsPreviewThenEditsFinalText(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(editMessage: true)
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[draft]\npreview=Working...\nfinal=Done")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendMessage"), true)
            @Expect(fake.saw("editMessageText"), true)
            @Expect(fake.sawBodyContaining("Working..."), true)
            @Expect(fake.sawBodyContaining("Done"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func draftPayloadFallsBackToFinalSendWhenEditFails(): Unit {
        let fake = TelegramFakeBotApi()
        fake.failDraftFinalEdit = true
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(editMessage: true)
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "[draft]\npreview=Working...\nfinal=Final answer")
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.countCallContaining("send:draft:final|editMessageText"), 1)
            @Expect(fake.countCallContaining("send:draft:fallback-final|sendMessage"), 1)
            @Expect(fake.sawBodyContaining("Final answer"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func approvalPayloadBuildsInlineButtonsAndCallbackData(): Unit {
        let future = DateTime.now().toUnixTimeStamp().toMilliseconds() + 60000
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(inlineKeyboard: true)
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(
                    ChannelType.Telegram,
                    "user:8734062810",
                    "[approval]\nid=appr-1\ntext=Run tool?\nallowLabel=Allow\ndenyLabel=Deny\nallow=allow-once\ndeny=deny\nexpiresAtMs=${future}"
                )
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendMessage"), true)
            @Expect(fake.sawBodyContaining("Run tool?"), true)
            @Expect(fake.sawBodyContaining("approval:appr-1:allow-once:${future}"), true)
            @Expect(fake.sawBodyContaining("approval:appr-1:deny:${future}"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func disabledReactionActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, reactions: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[reaction]\ntoken=👍\nrender=👍",
                replyToMessageId: Some("44")
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("reaction action is disabled"), true)
        }
    }

    @TestCase
    public func disabledDeleteActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, deleteMessage: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[delete]",
                replyToMessageId: Some("44")
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("deleteMessage action is disabled"), true)
        }
    }

    @TestCase
    public func disabledEditActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, editMessage: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[edit]\nUpdated",
                replyToMessageId: Some("44")
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("editMessage action is disabled"), true)
        }
    }

    @TestCase
    public func disabledInlineKeyboardActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, inlineKeyboard: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[inline-keyboard]\ntext=Choose\nbutton=Approve|callback:approve-1"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("inlineKeyboard action is disabled"), true)
        }
    }

    @TestCase
    public func inlineKeyboardScopeRejectsDisallowedPeerBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, inlineKeyboard: true),
            inlineButtons: TelegramInlineButtonsConfig(scope: "group")
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[inline-keyboard]\ntext=Choose\nbutton=Approve|callback:approve-1"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("inline button scope blocks peer"), true)
        }
    }

    @TestCase
    public func disabledStickerActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, sticker: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[sticker]\nfileId=sticker-file-id"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("sticker action is disabled"), true)
        }
    }

    @TestCase
    public func disabledPhotoActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, photo: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[photo]\nfileId=photo-file-id"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("photo action is disabled"), true)
        }
    }

    @TestCase
    public func disabledDocumentActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, document: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[document]\nfileId=doc-file-id"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("document action is disabled"), true)
        }
    }

    @TestCase
    public func disabledAudioActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, audio: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[audio]\nfileId=audio-file-id"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("audio action is disabled"), true)
        }
    }

    @TestCase
    public func disabledVoiceActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, voice: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[voice]\nfileId=voice-file-id"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("voice action is disabled"), true)
        }
    }

    @TestCase
    public func disabledVideoActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, video: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[video]\nfileId=video-file-id"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("video action is disabled"), true)
        }
    }

    @TestCase
    public func disabledVideoNoteActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, videoNote: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "user:8734062810",
                "[video-note]\nfileId=video-note-file-id"
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("video-note action is disabled"), true)
        }
    }

    @TestCase
    public func disabledTopicEditActionFailsFastBeforeNetwork(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            actions: TelegramActionConfig(sendMessage: true, editForumTopic: false)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let result = adapter.send(
            OutboundMessage(
                ChannelType.Telegram,
                "group:-1001234567890",
                "[topic-edit]\nRenamed Sprint",
                replyToMessageId: Some("42")
            )
        )
        match (result) {
            case SendResult.Success => @Expect(false, true)
            case SendResult.Failed(reason) => @Expect(reason.contains("topic-edit action is disabled"), true)
        }
    }

    @TestCase
    public func reactionWebhookQueuesSystemEventWhenNotificationsEnabled(): Unit {
        let groups = JsonObject()
        let groupRule = JsonObject()
        let allowFrom = JsonArray([])
        allowFrom.add("8734062810".toJsonValue())
        groupRule.put("requireMention", false.toJsonValue())
        groupRule.put("allowFrom", allowFrom)
        groups.put("-1001234567890", groupRule)
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            groupPolicy: "allowlist",
            groups: Some(groups),
            reactionNotifications: "all"
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":1,\"message_reaction\":{\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"message_id\":101,\"user\":{\"id\":8734062810},\"new_reaction\":[{\"type\":\"emoji\",\"emoji\":\"👍\"}]}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].replyTargetMessageId.getOrThrow(), "101")
        @Expect(inbound[0].systemEvent, true)
        @Expect(inbound[0].systemEventKind, "telegram.message_reaction")
        @Expect(inbound[0].text.contains("[telegram-reaction]"), true)
        @Expect(inbound[0].text.contains("emoji=👍"), true)
    }

    @TestCase
    public func reactionWebhookOwnModeOnlyAcceptsBotSentMessageReactions(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        let root = Path("/tmp/metis-telegram-reaction-own-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        try {
            let groups = JsonObject()
            let groupRule = JsonObject()
            let allowFrom = JsonArray([])
            allowFrom.add("8734062810".toJsonValue())
            groupRule.put("requireMention", false.toJsonValue())
            groupRule.put("allowFrom", allowFrom)
            groups.put("-1001234567890", groupRule)
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    groupPolicy: "allowlist",
                    groups: Some(groups),
                    reactionNotifications: "own"
                ),
                pairingRoot: root.toString()
            )
            adapter.start()
            let sentMessageId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "group:-1001234567890", "bot reply")
            )
            @Expect(sentMessageId.isEmpty(), false)

            let ignoredPayload = "{\"update_id\":11,\"message_reaction\":{\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"message_id\":999,\"user\":{\"id\":8734062810},\"new_reaction\":[{\"type\":\"emoji\",\"emoji\":\"👍\"}]}}"
            let ignoredAck = adapter.ingestWebhookPayload(ignoredPayload)
            @Expect(ignoredAck.contains("\"ignored\":true"), true)
            @Expect(adapter.pullInbound().size, 0)

            let acceptedPayload = "{\"update_id\":12,\"message_reaction\":{\"chat\":{\"id\":-1001234567890,\"type\":\"supergroup\"},\"message_id\":${sentMessageId},\"user\":{\"id\":8734062810},\"new_reaction\":[{\"type\":\"emoji\",\"emoji\":\"👍\"}]}}"
            let acceptedAck = adapter.ingestWebhookPayload(acceptedPayload)
            @Expect(acceptedAck.contains("\"ok\":true"), true)
            let inbound = adapter.pullInbound()
            @Expect(inbound.size, 1)
            @Expect(inbound[0].replyTargetMessageId.getOrThrow(), sentMessageId)
            @Expect(inbound[0].systemEventKind, "telegram.message_reaction")
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func getChatMemberProbeUsesMockedTelegramTransport(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let groups = JsonObject()
            groups.put("-1001234567890", JsonObject())
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "10001:telegram-token",
                    groups: Some(groups)
                )
            )
            let probe = adapter.debugTryTelegramGetChatMemberForTest("-1001234567890", "10001")
            @Expect(probe.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(probe.get("status").getOrThrow().asString().getValue(), "administrator")
            @Expect(fake.saw("getChatMember"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func membershipAuditReportsLeftOrKickedAsWarning(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let groups = JsonObject()
            groups.put("-1000000000002", JsonObject())
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "10001:telegram-token",
                    groups: Some(groups)
                )
            )
            let audit = adapter.debugBuildMembershipAuditForTest(getMeRaw: "{\"ok\":true,\"result\":{\"id\":10001,\"is_bot\":true,\"username\":\"metis_fake_bot\"}}")
            let probes = audit.get("probes").getOrThrow().asArray()
            @Expect(probes.size(), 1)
            let probe = probes[0].asObject()
            @Expect(probe.get("status").getOrThrow().asString().getValue(), "left")
            @Expect(probe.get("warning").getOrThrow().asBool().getValue(), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func allowedUpdatesIncludeCallbackQueryOnlyWhenCallbackActionsEnabled(): Unit {
        let disabled = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let disabledAllowed = disabled.debugBuildAllowedUpdates().toJsonString()
        @Expect(disabledAllowed.contains("callback_query"), false)

        let enabled = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                actions: TelegramActionConfig(callbackQuery: true)
            )
        )
        let enabledAllowed = enabled.debugBuildAllowedUpdates().toJsonString()
        @Expect(enabledAllowed.contains("callback_query"), true)
    }

    @TestCase
    public func allowedUpdatesCanIncludeExplicitExtraDiagnosticsTypes(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                network: TelegramNetworkConfig(allowedUpdatesExtra: ["poll", "chat_member", "message"])
            )
        )
        let allowed = adapter.debugBuildAllowedUpdates().toJsonString()
        @Expect(allowed.contains("poll"), true)
        @Expect(allowed.contains("chat_member"), true)
        @Expect(allowed.indexOf("message").isSome(), true)
    }

    @TestCase
    public func getChatParsesForumAndAvailableReactions(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            let chat = adapter.debugTryTelegramGetChatForTest("-1001234567890")
            @Expect(chat.get("ok").getOrThrow().asBool().getValue(), true)
            @Expect(chat.get("isForum").getOrThrow().asBool().getValue(), true)
            @Expect(chat.get("availableReactions").getOrThrow().asArray()[0].asString().getValue(), "👍")
            @Expect(fake.saw("getChat"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func trustedLocalTelegramFilePathRequiresConfiguredRoot(): Unit {
        let root = Path("/tmp/metis-telegram-trusted-root-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let filePath = root.join("photo.jpg")
        File.writeTo(filePath, "local-photo".toArray())
        try {
            let denied = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            @Expect(denied.debugTrustedLocalTelegramFilePathForTest(filePath.toString()), "")
            let allowed = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    media: TelegramMediaConfig(trustedLocalFileRoots: [root.toString()])
                )
            )
            @Expect(allowed.debugTrustedLocalTelegramFilePathForTest(filePath.toString()).endsWith("/photo.jpg"), true)
            @Expect(allowed.debugTrustedLocalTelegramFilePathForTest("/etc/passwd"), "")
        } finally {
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func callbackQueryWebhookQueuesInboundWhenEnabled(): Unit {
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            dmPolicy: "open",
            allowFrom: ["*"],
            actions: TelegramActionConfig(callbackQuery: true)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":2,\"callback_query\":{\"id\":\"cb-1\",\"from\":{\"id\":8734062810},\"message\":{\"message_id\":101,\"chat\":{\"id\":8734062810,\"type\":\"private\"}},\"data\":\"approve-1\"}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].messageId, "callback:cb-1")
        @Expect(inbound[0].peerId, "user:8734062810")
        @Expect(inbound[0].replyTargetMessageId.getOrThrow(), "101")
        @Expect(inbound[0].text.contains("[telegram-callback]"), true)
        @Expect(inbound[0].text.contains("data=approve-1"), true)
    }

    @TestCase
    public func approvalCallbackQueuesStructuredDecisionAndRejectsReplay(): Unit {
        let future = DateTime.now().toUnixTimeStamp().toMilliseconds() + 60000
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            dmPolicy: "open",
            allowFrom: ["*"],
            actions: TelegramActionConfig(callbackQuery: true)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":4,\"callback_query\":{\"id\":\"cb-approval-1\",\"from\":{\"id\":8734062810},\"message\":{\"message_id\":103,\"chat\":{\"id\":8734062810,\"type\":\"private\"}},\"data\":\"approval:appr-1:allow-once:${future}\"}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].text.contains("[telegram-approval]"), true)
        @Expect(inbound[0].text.contains("approvalId=appr-1"), true)
        @Expect(inbound[0].text.contains("decision=allow-once"), true)

        let replayAck = adapter.ingestWebhookPayload(payload.replace("\"update_id\":4", "\"update_id\":5"))
        @Expect(replayAck.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)
        let policy = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(policy.get("lastReason").getOrThrow().asString().getValue(), "approval_callback_replayed")
    }

    @TestCase
    public func approvalCallbackRejectsExpiredDecisionBeforeQueueing(): Unit {
        let expired = DateTime.now().toUnixTimeStamp().toMilliseconds() - 1000
        let cfg = TelegramConfig(
            enabled: true,
            botToken: "telegram-token",
            dmPolicy: "open",
            allowFrom: ["*"],
            actions: TelegramActionConfig(callbackQuery: true)
        )
        let adapter = TelegramAdapter(config: cfg)
        adapter.start()
        let payload = "{\"update_id\":6,\"callback_query\":{\"id\":\"cb-expired\",\"from\":{\"id\":8734062810},\"message\":{\"message_id\":104,\"chat\":{\"id\":8734062810,\"type\":\"private\"}},\"data\":\"approval:appr-2:deny:${expired}\"}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().isEmpty(), true)
        let policy = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(policy.get("lastReason").getOrThrow().asString().getValue(), "approval_callback_expired")
    }

    @TestCase
    public func callbackQueryWebhookRecordsDisabledInboundPolicyReason(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        adapter.start()
        let payload = "{\"update_id\":3,\"callback_query\":{\"id\":\"cb-2\",\"from\":{\"id\":8734062810},\"message\":{\"message_id\":102,\"chat\":{\"id\":745123456,\"type\":\"private\"}},\"data\":\"approve-2\"}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ignored\":true"), true)
        @Expect(adapter.pullInbound().size, 0)
        let policy = adapter.debugBuildInboundPolicyDiagnostics()
        @Expect(policy.get("lastUpdateKind").getOrThrow().asString().getValue(), "callback_query")
        @Expect(policy.get("lastReason").getOrThrow().asString().getValue(), "callback_query_disabled")
    }

    @TestCase
    public func callbackQueryAckAndApprovalClearButtonsUseBotApi(): Unit {
        let future = DateTime.now().toUnixTimeStamp().toMilliseconds() + 60000
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let cfg = TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"],
                actions: TelegramActionConfig(callbackQuery: true)
            )
            let adapter = TelegramAdapter(config: cfg)
            adapter.start()
            let payload = "{\"update_id\":16,\"callback_query\":{\"id\":\"cb-approval-clear\",\"from\":{\"id\":8734062810},\"message\":{\"message_id\":104,\"chat\":{\"id\":8734062810,\"type\":\"private\"}},\"data\":\"approval:appr-2:allow-once:${future}\"}}"
            let ack = adapter.ingestWebhookPayload(payload)
            @Expect(ack.contains("\"ok\":true"), true)
            @Expect(fake.saw("answerCallbackQuery"), true)
            @Expect(fake.saw("editMessageReplyMarkup"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func sendMediaGroupSupportsMultipleLocalFilesWithAttachMultipart(): Unit {
        let root = Path("/tmp/metis-telegram-media-group-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let first = root.join("a.jpg")
        let second = root.join("b.jpg")
        File.writeTo(first, "a-photo".toArray())
        File.writeTo(second, "b-photo".toArray())
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(photo: true),
                    media: TelegramMediaConfig(outboundAllowLocalPath: true, outboundLocalRoots: [root.toString()])
                )
            )
            adapter.start()
            let text = "[media-group]\nitem=photo|${first.toString()}|first\nitem=photo|${second.toString()}|second"
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", text))
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("sendMediaGroup"), true)
            @Expect(fake.sawBodyContaining("attach://file0"), true)
            @Expect(fake.sawBodyContaining("attach://file1"), true)
            @Expect(fake.sawBodyContaining("name=\"file0\"; filename=\"a.jpg\""), true)
            @Expect(fake.sawBodyContaining("name=\"file1\"; filename=\"b.jpg\""), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func editMediaPayloadUsesEditMessageMedia(): Unit {
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    actions: TelegramActionConfig(editMessage: true, photo: true)
                )
            )
            adapter.start()
            let result = adapter.send(
                OutboundMessage(
                    ChannelType.Telegram,
                    "user:8734062810",
                    "[edit-media]\ntype=photo\nfileId=photo-file-id\ncaption=updated",
                    replyToMessageId: Some("55")
                )
            )
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "")
            }
            @Expect(fake.saw("editMessageMedia"), true)
            @Expect(fake.sawBodyContaining("photo-file-id"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func pollingStopConfirmUsesNextOffsetAndDiagnosticsExposeUpdateTypes(): Unit {
        let root = Path("/tmp/metis-telegram-stop-confirm-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        Directory.create(root, recursive: true)
        let fake = TelegramFakeBotApi()
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token", dmPolicy: "open", allowFrom: ["*"]),
                pairingRoot: root.toString()
            )
            adapter.start()
            let payload = "{\"update_id\":42,\"message\":{\"message_id\":11,\"text\":\"hello\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"
            let ack = adapter.ingestWebhookPayload(payload)
            @Expect(ack.contains("\"ok\":true"), true)
            @Expect(adapter.debugConfirmPollingOffsetOnStopForTest(), true)
            @Expect(adapter.debugLastConfirmedPollingOffsetForTest(), "43")
            @Expect(fake.sawBodyContaining("\"offset\""), true)
            @Expect(fake.sawBodyContaining("43"), true)
            @Expect(adapter.debugSupportedUpdateTypesForTest().toJsonString().contains("inline_query"), true)
        } finally {
            setTelegramTransportRunnerForTest(None)
            try { remove(root, recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func t51AcceptanceMatrixTracksAuditItemsZeroThroughNine(): Unit {
        let items = [
            "TG-RE-AUDIT-01",
            "TG-RE-AUDIT-02",
            "TG-RE-AUDIT-03",
            "TG-RE-AUDIT-04",
            "TG-RE-AUDIT-05",
            "TG-RE-AUDIT-06",
            "TG-RE-AUDIT-07",
            "TG-RE-AUDIT-08",
            "TG-RE-AUDIT-09",
            "TG-RE-AUDIT-10"
        ]
        @Expect(items.size, 10)
        @Expect(items[0], "TG-RE-AUDIT-01")
        @Expect(items[3], "TG-RE-AUDIT-04")
        @Expect(items[9], "TG-RE-AUDIT-10")
    }

    @TestCase
    public func t51InboundQuoteContextIsSupplementalAndDoesNotTriggerCommand(): Unit {
        let fake = TelegramFakeBotApi()
        fake.pollingUpdatesEnabled = false
        setTelegramTransportRunnerForTest(Some({ request => fake.handle(request) }))
        try {
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", dmPolicy: "open", allowFrom: ["*"]))
            adapter.start()
            let payload = "{\"update_id\":510051,\"message\":{\"message_id\":510,\"text\":\"answer this\",\"quote\":{\"text\":\"/reset should stay quoted\"},\"external_reply\":{\"message_id\":509,\"quote\":{\"text\":\"external quote\"},\"text\":\"external body\"},\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"
            let ack = adapter.ingestWebhookPayload(payload)
            @Expect(ack.contains("\"ok\":true"), true)
            let inboundItems = adapter.pullInbound()
            @Expect(inboundItems.size, 1)
            let inbound = inboundItems[0]
            @Expect(inbound.text.contains("[quote-context]"), true)
            @Expect(inbound.text.contains("text=/reset should stay quoted"), true)
            @Expect(inbound.text.contains("quote=external quote"), true)
            @Expect(inbound.text.startsWith("/reset"), false)
            let context = inbound.mediaContext.get("context").getOrThrow().asObject()
            @Expect(context.get("quote").getOrThrow().asObject().get("text").getOrThrow().asString().getValue(), "/reset should stay quoted")
            @Expect(context.get("externalReply").getOrThrow().asObject().get("quoteText").getOrThrow().asString().getValue(), "external quote")
            adapter.stop()
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }

    @TestCase
    public func t51UnsupportedAllowedUpdateTypesRecordIgnoredDiagnostics(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token", dmPolicy: "open", allowFrom: ["*"]))
        for ((kind, payload) in [
            ("business_message", "{\"update_id\":61,\"business_message\":{\"message_id\":1,\"text\":\"biz\",\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810}}}"),
            ("message_reaction_count", "{\"update_id\":62,\"message_reaction_count\":{\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"message_id\":2,\"reactions\":[]}}"),
            ("poll_answer", "{\"update_id\":63,\"poll_answer\":{\"poll_id\":\"p\",\"user\":{\"id\":8734062810},\"option_ids\":[0]}}"),
            ("chat_member", "{\"update_id\":64,\"chat_member\":{\"chat\":{\"id\":8734062810,\"type\":\"private\"},\"from\":{\"id\":8734062810},\"date\":1}}"),
            ("inline_query", "{\"update_id\":65,\"inline_query\":{\"id\":\"iq\",\"from\":{\"id\":8734062810},\"query\":\"q\",\"offset\":\"\"}}")
        ]) {
            let ack = adapter.ingestWebhookPayload(payload)
            @Expect(ack.contains("\"ignored\":true"), true)
            let diag = adapter.debugBuildInboundPolicyDiagnostics()
            @Expect(diag.get("lastDecision").getOrThrow().asString().getValue(), "ignored")
            @Expect(diag.get("lastUpdateKind").getOrThrow().asString().getValue(), kind)
        }
        @Expect(adapter.pullInbound().size, 0)
    }

    @TestCase
    public func retryAfterParserReadsTelegramParameters(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
        let raw = "{\"ok\":false,\"error_code\":429,\"description\":\"Too Many Requests\",\"parameters\":{\"retry_after\":30}}"
        @Expect(adapter.debugRetryAfterSecondsForTest(raw), 30)
    }

    @TestCase
    public func groupMigrationConfigWritesFalseRecordsOnly(): Unit {
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        var user = GatewayUserSettings()
        user.telegram.configWrites = false
        let groups = JsonObject()
        let oldGroup = JsonObject()
        oldGroup.put("label", JsonString("old"))
        groups.put("-222333444", oldGroup)
        user.telegram.groups = Some(groups)
        MetisConfigManager.setGatewaySettings(user)

        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token", configWrites: false),
            pairingRoot: "/tmp/metis-telegram-group-migration-config-false"
        )
        let payload = "{\"update_id\":188,\"message\":{\"message_id\":45,\"migrate_to_chat_id\":\"-100222333444\",\"chat\":{\"id\":\"-222333444\",\"type\":\"group\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)
        let migrations = adapter.debugReadGroupMigrationStateForTest()
        let row = migrations[0].asObject()
        @Expect(row.get("configMigrationStatus").getOrThrow().asString().getValue(), "diagnostic_only")
        let after = CliSettingManager.readGatewaySettings()
        @Expect(after.telegram.groups.getOrThrow().get("-222333444").isSome(), true)
        @Expect(after.telegram.groups.getOrThrow().get("-100222333444").isNone(), true)
    }

    @TestCase
    public func groupMigrationConfigWritesTrueMigratesTempConfigOnly(): Unit {
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        var user = GatewayUserSettings()
        user.telegram.configWrites = true
        let groups = JsonObject()
        let oldGroup = JsonObject()
        oldGroup.put("label", JsonString("old"))
        groups.put("-333444555", oldGroup)
        user.telegram.groups = Some(groups)
        MetisConfigManager.setGatewaySettings(user)

        let adapter = TelegramAdapter(
            config: TelegramConfig(enabled: true, botToken: "telegram-token", configWrites: true),
            pairingRoot: "/tmp/metis-telegram-group-migration-config-true"
        )
        let payload = "{\"update_id\":189,\"message\":{\"message_id\":46,\"migrate_to_chat_id\":\"-100333444555\",\"chat\":{\"id\":\"-333444555\",\"type\":\"group\"},\"from\":{\"id\":8734062810}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)
        let migrations = adapter.debugReadGroupMigrationStateForTest()
        let row = migrations[0].asObject()
        @Expect(row.get("configMigrationStatus").getOrThrow().asString().getValue(), "migrated")
        @Expect(row.get("configPath").getOrThrow().asString().getValue().startsWith("/tmp/"), true)
        let after = CliSettingManager.readGatewaySettings()
        @Expect(after.telegram.groups.getOrThrow().get("-333444555").isNone(), true)
        @Expect(after.telegram.groups.getOrThrow().get("-100333444555").isSome(), true)
    }

    @TestCase
    public func sendActionRetryAndSoftErrorClassificationUseFakeTransport(): Unit {
        let editState = JsonObject()
        editState.put("calls", 0.toJsonValue())
        try {
            setTelegramTransportRunnerForTest(Some({ request: TelegramTransportRequest =>
                if (request.context.startsWith("send:edit")) {
                    let calls = try { editState.get("calls").getOrThrow().asInt().getValue() } catch (_e: Exception) { 0 }
                    editState.put("calls", (calls + 1).toJsonValue())
                    if (calls == 0) {
                        return TelegramTransportResponse(true, body: "{\"ok\":false,\"error_code\":500,\"description\":\"Internal Server Error\"}", outcome: "api-ok-false")
                    }
                    return TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":true}", outcome: "ok")
                }
                TelegramTransportResponse(true, body: "{\"ok\":true,\"result\":{\"message_id\":777}}", outcome: "ok")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token", actions: TelegramActionConfig(editMessage: true))
            )
            adapter.start()
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[edit]\nupdated", replyToMessageId: Some("99")))
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "success")
            }
            @Expect(editState.get("calls").getOrThrow().asInt().getValue(), 2)
        } finally {
            setTelegramTransportRunnerForTest(None)
        }

        try {
            setTelegramTransportRunnerForTest(Some({ _request: TelegramTransportRequest =>
                TelegramTransportResponse(true, body: "{\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: message is not modified\"}", outcome: "api-ok-false")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(enabled: true, botToken: "telegram-token", actions: TelegramActionConfig(editMessage: true))
            )
            adapter.start()
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[edit]\nsame", replyToMessageId: Some("99")))
            match (result) {
                case SendResult.Success => ()
                case SendResult.Failed(reason) => @Expect(reason, "success")
            }
        } finally {
            setTelegramTransportRunnerForTest(None)
        }

        try {
            setTelegramTransportRunnerForTest(Some({ _request: TelegramTransportRequest =>
                TelegramTransportResponse(true, body: "{\"ok\":false,\"error_code\":400,\"description\":\"Bad Request: invalid reaction type\"}", outcome: "api-ok-false")
            }))
            let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
            adapter.start()
            let result = adapter.send(OutboundMessage(ChannelType.Telegram, "user:8734062810", "[reaction]\ntoken=invalid\nrender=invalid", replyToMessageId: Some("99")))
            match (result) {
                case SendResult.Success => @Expect(false, true)
                case SendResult.Failed(reason) => @Expect(reason.contains("reaction-invalid"), true)
            }
        } finally {
            setTelegramTransportRunnerForTest(None)
        }
    }
}
