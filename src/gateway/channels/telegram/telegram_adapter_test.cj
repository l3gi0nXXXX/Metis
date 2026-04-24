package metis.gateway.channels.telegram

import metis.gateway.model.*

import magic.jsonable.*
import std.collection.ArrayList
import std.fs.Path
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.*

@Test
public class TelegramAdapterTest {
    public init() {
        setTelegramCurlRunnerForTest(None)
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
        @Expect(commands.size(), 4)
        let first = commands[0].asObject()
        let second = commands[1].asObject()
        @Expect(first.get("command").getOrThrow().asString().getValue(), "help")
        @Expect(first.get("description").getOrThrow().asString().getValue(), "Show help")
        @Expect(second.get("command").getOrThrow().asString().getValue(), "status")
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
        @Expect(commands.size(), 5)
        let last = commands[4].asObject()
        @Expect(last.get("command").getOrThrow().asString().getValue(), "generate")
        @Expect(last.get("description").getOrThrow().asString().getValue(), "Create image")
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
        @Expect(lastMedia.get("downloadPath").getOrThrow().asString().getValue().contains(".download"), true)
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

    /*
    @TestCase
    public func webhookPhotoMessagesMapToStructuredInboundMediaText(): Unit {
        let groups = JsonObject()
        let groupRule = JsonObject()
        groupRule.put("requireMention", false.toJsonValue())
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
        @Expect(inbound[0].text, "[photo]\nfileId=large\ncaption=hello photo")
        @Expect(inbound[0].threadId.getOrThrow(), "42")
    }
    */

    @TestCase
    public func webhookStickerMessagesMapToStructuredInboundMediaText(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
        )
        adapter.start()
        let payload = "{\"update_id\":1,\"message\":{\"message_id\":101,\"sticker\":{\"file_id\":\"sticker-file-id\"},\"chat\":{\"id\":745123456,\"type\":\"private\"},\"from\":{\"id\":745123456}}}"
        let ack = adapter.ingestWebhookPayload(payload)
        @Expect(ack.contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "user:745123456")
        @Expect(inbound[0].text, "[sticker]\nfileId=sticker-file-id")
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
    public func pollingResponseQueuesInboundTelegramMessages(): Unit {
        let adapter = TelegramAdapter(
            config: TelegramConfig(
                enabled: true,
                botToken: "telegram-token",
                dmPolicy: "open",
                allowFrom: ["*"]
            )
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
    public func proxyConfiguredPollingUsesCurlProxyForGetUpdates(): Unit {
        let seen = ArrayList<String>()
        try {
            setTelegramCurlRunnerForTest(Some({ args: Array<String> =>
                for (arg in args) {
                    seen.add(arg)
                }
                (0, "{\"ok\":true,\"result\":[]}", "")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            let raw = adapter.debugFetchTelegramUpdatesRaw()
            @Expect(raw.contains("\"ok\":true"), true)
            @Expect(seen[0], "curl")
            @Expect(seen.contains("--proxy"), true)
            @Expect(seen.contains("http://127.0.0.1:7897"), true)
            @Expect(seen[seen.size - 1].contains("/getUpdates"), true)
        } finally {
            setTelegramCurlRunnerForTest(None)
        }
    }

    @TestCase
    public func proxyConfiguredNativeCommandsUseCurlProxy(): Unit {
        let seen = ArrayList<String>()
        try {
            setTelegramCurlRunnerForTest(Some({ args: Array<String> =>
                for (arg in args) {
                    seen.add(arg)
                }
                (0, "{\"ok\":true,\"result\":true}", "")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token",
                    proxy: "http://127.0.0.1:7897"
                )
            )
            @Expect(adapter.debugSyncNativeCommandsForTest(), true)
            @Expect(seen[0], "curl")
            @Expect(seen.contains("--proxy"), true)
            @Expect(seen.contains("http://127.0.0.1:7897"), true)
            @Expect(seen[seen.size - 1].contains("/setMyCommands"), true)
        } finally {
            setTelegramCurlRunnerForTest(None)
        }
    }

    /*
    @TestCase
    public func sendWithMessageIdReturnsTelegramMessageIdForStreaming(): Unit {
        try {
            setTelegramCurlRunnerForTest(Some({ _args: Array<String> =>
                (0, "{\"ok\":true,\"result\":{\"message_id\":321,\"text\":\"hello\"}}", "")
            }))
            let adapter = TelegramAdapter(
                config: TelegramConfig(
                    enabled: true,
                    botToken: "telegram-token"
                )
            )
            adapter.start()
            let messageId = adapter.sendWithMessageId(
                OutboundMessage(ChannelType.Telegram, "user:8734062810", "hello")
            )
            @Expect(messageId, "321")
        } finally {
            setTelegramCurlRunnerForTest(None)
        }
    }
    */

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

    /*
    @TestCase
    public func sendPayloadsRenderNativeTelegramStickerPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
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
    */

    /*
    @TestCase
    public func sendPayloadsRenderNativeTelegramPhotoPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
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
    */

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

    /*
    @TestCase
    public func sendPayloadsRenderNativeTelegramVideoPayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
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
    */

    /*
    @TestCase
    public func sendPayloadsRenderNativeTelegramVideoNotePayload(): Unit {
        let adapter = TelegramAdapter(config: TelegramConfig(enabled: true, botToken: "telegram-token"))
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
    */

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
        @Expect(inbound[0].text.contains("[telegram-reaction]"), true)
        @Expect(inbound[0].text.contains("emoji=👍"), true)
    }
}
