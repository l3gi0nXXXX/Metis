package metis.gateway.channels.feishu

import metis.core.renderGatewayEditText
import metis.gateway.model.{ChannelPolicyConfig, ChannelType, FeishuConfig, FeishuMediaConfig, OutboundMessage}
import std.core.Duration
import std.fs.{File, Path, exists, remove}
import std.sync.Mutex
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString}

class FeishuQueueProbe {
    private let lock = Mutex()
    private var sameThreadActive = 0
    private var sameThreadOverlap = false
    private var otherThreadObservedParallel = false

    func runSameThreadTask(durationMs: Int64): Unit {
        synchronized(this.lock) {
            this.sameThreadActive += 1
            if (this.sameThreadActive > 1) {
                this.sameThreadOverlap = true
            }
        }
        sleep(Duration.millisecond * durationMs)
        synchronized(this.lock) {
            this.sameThreadActive -= 1
        }
    }

    func runOtherThreadTask(): Unit {
        synchronized(this.lock) {
            if (this.sameThreadActive > 0) {
                this.otherThreadObservedParallel = true
            }
        }
    }

    func sameOverlap(): Bool {
        synchronized(this.lock) {
            this.sameThreadOverlap
        }
    }

    func otherObservedParallel(): Bool {
        synchronized(this.lock) {
            this.otherThreadObservedParallel
        }
    }
}

@Test
public class FeishuAdapterTest {
    private func webhookPayload(
        messageId: String,
        chatId: String,
        senderId: String,
        text: String,
        chatType!: String = "group",
        messageType!: String = "text",
        rootId!: String = "",
        threadId!: String = "",
        headerAccountId!: String = "",
        appId!: String = "",
        mentions!: String = ""
    ): String {
        let headerExtra = if (!headerAccountId.isEmpty()) {
            ",\"account_id\":\"${headerAccountId}\""
        } else if (!appId.isEmpty()) {
            ",\"app_id\":\"${appId}\""
        } else {
            ""
        }
        let mentionField = if (!mentions.isEmpty()) { ",\"mentions\":${mentions}" } else { "" }
        "{" +
            "\"header\":{\"event_type\":\"im.message.receive_v1\"${headerExtra}}," +
            "\"event\":{" +
            "\"sender\":{\"sender_id\":{\"open_id\":\"${senderId}\"}}," +
            "\"message\":{" +
            "\"message_id\":\"${messageId}\"," +
            "\"chat_id\":\"${chatId}\"," +
            "\"chat_type\":\"${chatType}\"," +
            "\"message_type\":\"${messageType}\"," +
            "\"content\":\"${text}\"," +
            "\"root_id\":\"${rootId}\"," +
            "\"thread_id\":\"${threadId}\"" +
            mentionField +
            "}" +
            "}" +
            "}"
    }

    private func cardActionPayload(action: String, accountId!: String = "tenant-a"): String {
        "{" +
            "\"header\":{\"event_type\":\"card.action.trigger\",\"account_id\":\"${accountId}\"}," +
            "\"event\":{" +
            "\"operator\":{\"open_id\":\"ou_operator\"}," +
            "\"context\":{\"open_message_id\":\"om_card\",\"open_chat_id\":\"oc_card\"}," +
            "\"action\":{\"value\":{\"action\":\"${action}\",\"nonce\":\"n-1\"}}" +
            "}" +
            "}"
    }

    @TestCase
    public func accountResolverMergesDefaultAndAccountOverridesWithRedaction(): Unit {
        let accounts = JsonObject()
        let tenant = JsonObject()
        tenant.put("enabled", JsonBool(false))
        tenant.put("appId", JsonString("tenant-app"))
        tenant.put("receiveMode", JsonString("webhook"))
        tenant.put("groupPolicy", JsonString("open"))
        tenant.put("requireMention", JsonBool(false))
        let accountGroups = JsonObject()
        accountGroups.put("oc_account", JsonObject())
        tenant.put("groups", accountGroups)
        accounts.put("tenant-a", tenant)

        let baseGroups = JsonObject()
        baseGroups.put("oc_base", JsonObject())
        let config = FeishuConfig(
            enabled: true,
            defaultAccount: "tenant-a",
            appId: "base-app",
            appSecret: "base-secret-never-visible",
            accounts: Some(accounts),
            receiveMode: "long_connect",
            groups: Some(baseGroups),
            groupPolicy: "allowlist",
            requireMention: true
        )

        let resolved = gatewayFeishuResolveAccount(config, "tenant-a")
        @Expect(resolved.accountId, "tenant-a")
        @Expect(resolved.explicitAccount, true)
        @Expect(resolved.config.enabled, false)
        @Expect(resolved.config.appId, "tenant-app")
        @Expect(resolved.config.appSecret, "base-secret-never-visible")
        @Expect(resolved.config.receiveMode, "webhook")
        @Expect(resolved.config.groupPolicy, "open")
        @Expect(resolved.config.requireMention, false)
        @Expect(resolved.config.groups.getOrThrow().getFields().contains("oc_account"), true)

        let descriptions = gatewayFeishuDescribeAccounts(config)
        let raw = descriptions.toJsonString()
        @Expect(raw.contains("tenant-a"), true)
        @Expect(raw.contains("base-secret-never-visible"), false)
        @Expect(raw.contains("tenant-app"), false)
        let firstDescription = descriptions.get("accounts").getOrThrow().asArray().getItems()[0].asObject()
        @Expect(firstDescription.get("credentialSource").getOrThrow().asString().getValue(), "account")
    }

    @TestCase
    public func accountResolverDeepMergesSupportedNestedGroupOverrides(): Unit {
        let baseTeam = JsonObject()
        baseTeam.put("requireMention", JsonBool(true))
        let baseTools = JsonObject()
        baseTools.put("deny", JsonArray([JsonString("feishu_drive_file")]))
        baseTeam.put("tools", baseTools)
        let baseWildcard = JsonObject()
        baseWildcard.put("allowBots", JsonBool(false))
        let baseGroups = JsonObject()
        baseGroups.put("oc_team", baseTeam)
        baseGroups.put("*", baseWildcard)

        let accountTeam = JsonObject()
        accountTeam.put("systemPrompt", JsonString("tenant-a group prompt"))
        let accountTools = JsonObject()
        accountTools.put("allow", JsonArray([JsonString("feishu_fetch_doc")]))
        accountTeam.put("tools", accountTools)
        let accountOnly = JsonObject()
        accountOnly.put("requireMention", JsonBool(false))
        let accountGroups = JsonObject()
        accountGroups.put("oc_team", accountTeam)
        accountGroups.put("oc_account_only", accountOnly)
        let tenant = JsonObject()
        tenant.put("groups", accountGroups)
        let accounts = JsonObject()
        accounts.put("tenant-a", tenant)

        let config = FeishuConfig(
            enabled: true,
            defaultAccount: "tenant-a",
            accounts: Some(accounts),
            groups: Some(baseGroups)
        )

        let resolvedGroups = gatewayFeishuResolveAccount(config, "tenant-a").config.groups.getOrThrow()
        @Expect(resolvedGroups.getFields().contains("oc_team"), true)
        @Expect(resolvedGroups.getFields().contains("oc_account_only"), true)
        @Expect(resolvedGroups.getFields().contains("*"), true)
        let mergedTeam = resolvedGroups.get("oc_team").getOrThrow().asObject()
        @Expect(mergedTeam.get("requireMention").getOrThrow().asBool().getValue(), true)
        @Expect(mergedTeam.get("systemPrompt").getOrThrow().asString().getValue(), "tenant-a group prompt")
        let mergedTools = mergedTeam.get("tools").getOrThrow().asObject()
        @Expect(mergedTools.get("allow").getOrThrow().asArray().size(), 1)
        @Expect(mergedTools.get("deny").getOrThrow().asArray().size(), 1)
    }

    @TestCase
    public func disabledAccountOverrideDoesNotRunAdapterTransport(): Unit {
        let accounts = JsonObject()
        let disabled = JsonObject()
        disabled.put("enabled", JsonBool(false))
        accounts.put("tenant-off", disabled)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, accounts: Some(accounts)),
            accountId: "tenant-off"
        )
        adapter.start()
        adapter.simulateIncomingText("om_disabled", "oc_group", "ou_1", "hello")
        @Expect(adapter.pullInbound().size, 0)
    }

    @TestCase
    public func adapterUsesAccountScopedGroupPolicyForInboundGate(): Unit {
        let accounts = JsonObject()
        let tenant = JsonObject()
        tenant.put("groupPolicy", JsonString("open"))
        tenant.put("requireMention", JsonBool(false))
        tenant.put("botOpenId", JsonString("bot-open"))
        accounts.put("tenant-a", tenant)
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                accounts: Some(accounts),
                groupPolicy: "allowlist",
                requireMention: true
            ),
            accountId: "tenant-a"
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_account_gate",
                "oc_not_in_base_allowlist",
                "ou_1",
                "{\\\"text\\\":\\\"plain group message\\\"}"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        let gate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(gate.get("triggerAgent").getOrThrow().asBool().getValue(), true)
        @Expect(gate.get("reason").getOrThrow().asString().getValue(), "accepted")
    }

    @TestCase
    public func fakeClientRecordsInteractiveCardSendAndPatch(): Unit {
        let client = FeishuFakeApiClient()
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), apiClient: client)
        adapter.start()
        let card = FeishuInteractiveCard(
            title: "Metis Feishu auth",
            text: "Open the verification URL and enter the user code.",
            actionId: "feishu.auth.start"
        )

        let messageId = adapter.sendInteractiveCardToFeishu("oc_card", card)
        @Expect(messageId, "fake-feishu-card-1")
        @Expect(client.cardSendCount(), 1)
        @Expect(client.sentCard(0).fallbackText().contains("Metis Feishu auth"), true)

        let patched = adapter.patchInteractiveCardInFeishu(messageId, FeishuInteractiveCard(title: "Done", text: "Authorized"))
        @Expect(patched, true)
        @Expect(client.cardPatchCount(), 1)
        @Expect(client.patchedCard(0).fallbackText().contains("Authorized"), true)
    }

    @TestCase
    public func streamingSendWithMessageIdCreatesAndPatchesOneInteractiveCard(): Unit {
        let client = FeishuFakeApiClient()
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true, streaming: "partial"), apiClient: client)
        adapter.start()

        let messageId = adapter.sendWithMessageId(OutboundMessage(
            ChannelType.Feishu,
            "oc_stream",
            "first chunk",
            replyToMessageId: Some("om_source"),
            replyInThread: true,
            accountId: "tenant-a"
        ))
        @Expect(messageId, "fake-feishu-card-1")
        @Expect(client.cardSendCount(), 1)
        @Expect(client.sentCard(0).fallbackText().contains("first chunk"), true)

        let patchedId = adapter.sendWithMessageId(OutboundMessage(
            ChannelType.Feishu,
            "oc_stream",
            renderGatewayEditText("first chunk\nsecond chunk"),
            replyToMessageId: Some(messageId),
            accountId: "tenant-a"
        ))
        @Expect(patchedId, messageId)
        @Expect(client.cardPatchCount(), 1)
        @Expect(client.patchedCard(0).fallbackText().contains("second chunk"), true)
    }

    @TestCase
    public func toolUseDisplayIsIncludedOnlyWhenEnabled(): Unit {
        let hidden = FeishuReplyCardDraft(title: "Metis", showToolUse: false)
        hidden.appendText("answer")
        hidden.appendToolUse("feishu_im_user_fetch_resource", "{\"message_id\":\"om_1\"}")
        @Expect(hidden.toCard().fallbackText().contains("feishu_im_user_fetch_resource"), false)

        let visible = FeishuReplyCardDraft(title: "Metis", showToolUse: true)
        visible.appendText("answer")
        visible.appendToolUse("feishu_im_user_fetch_resource", "{\"message_id\":\"om_1\"}")
        let card = visible.toCard()
        @Expect(card.fallbackText().contains("answer"), true)
        @Expect(card.fallbackText().contains("Tool use"), true)
        @Expect(card.fallbackText().contains("feishu_im_user_fetch_resource"), true)
    }

    @TestCase
    public func cardActionTriggerBecomesSafeSystemEvent(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "tenant-a")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(this.cardActionPayload("feishu.auth.confirm")).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].systemEvent, true)
        @Expect(inbound[0].systemEventKind, "feishu.card_action")
        @Expect(inbound[0].accountId, "tenant-a")
        @Expect(inbound[0].peerId, "oc_card")
        @Expect(inbound[0].text.contains("[feishu-card-action]"), true)
        let action = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuCardAction").getOrThrow().asObject()
        @Expect(action.get("action").getOrThrow().asString().getValue(), "feishu.auth.confirm")
        @Expect(action.get("operatorId").getOrThrow().asString().getValue(), "ou_operator")
    }

    @TestCase
    public func webhookThreadPayloadProjectsUnifiedImRouteContext(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true))
        adapter.start()
        let payload =
            "{" +
            "\"header\":{\"event_type\":\"im.message.receive_v1\"}," +
            "\"event\":{" +
            "\"sender\":{\"sender_id\":{\"open_id\":\"ou_123\"}}," +
            "\"message\":{" +
            "\"message_id\":\"om_1\"," +
            "\"chat_id\":\"oc_a\"," +
            "\"chat_type\":\"group\"," +
            "\"message_type\":\"text\"," +
            "\"content\":\"{\\\"text\\\":\\\"hello\\\"}\"," +
            "\"root_id\":\"\"," +
            "\"thread_id\":\"thread_x\"" +
            "}" +
            "}" +
            "}"

        @Expect(adapter.ingestWebhookPayload(payload).contains("\"ok\":true"), true)
        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].peerId, "oc_a")
        @Expect(inbound[0].threadId.getOrThrow(), "thread_x")
        let imRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(imRoute.get("channel").getOrThrow().asString().getValue(), "feishu")
        @Expect(imRoute.get("accountId").getOrThrow().asString().getValue(), "default")
        @Expect(imRoute.get("peerKind").getOrThrow().asString().getValue(), "thread")
        @Expect(imRoute.get("peerId").getOrThrow().asString().getValue(), "thread_x")
        @Expect(imRoute.get("parentPeerKind").getOrThrow().asString().getValue(), "group")
        @Expect(imRoute.get("parentPeerId").getOrThrow().asString().getValue(), "oc_a")
        @Expect(imRoute.get("senderId").getOrThrow().asString().getValue(), "ou_123")
        @Expect(imRoute.get("messageId").getOrThrow().asString().getValue(), "om_1")
    }

    @TestCase
    public func webhookRouteContextUsesConfiguredAndInboundAccountIds(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_work", "oc_a", "ou_1", "{\\\"text\\\":\\\"hello\\\"}")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_inbound",
                "oc_a",
                "ou_2",
                "{\\\"text\\\":\\\"hello\\\"}",
                headerAccountId: "tenant-b"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].accountId, "work")
        @Expect(inbound[1].accountId, "tenant-b")
        let workRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        let tenantRoute = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(workRoute.get("accountId").getOrThrow().asString().getValue(), "work")
        @Expect(workRoute.get("defaultAccountId").getOrThrow().asString().getValue(), "work")
        @Expect(tenantRoute.get("accountId").getOrThrow().asString().getValue(), "tenant-b")
        @Expect(inbound[0].mediaContext.get("accountId").getOrThrow().asString().getValue(), "work")
    }

    @TestCase
    public func groupThreadKeepsThreadPeerAndReplyInThread(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true))
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread", "oc_group", "ou_1", "{\\\"text\\\":\\\"hello\\\"}", threadId: "omt_topic")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].threadId.getOrThrow(), "omt_topic")
        @Expect(inbound[0].replyInThread, true)
        let imRoute = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(imRoute.get("peerKind").getOrThrow().asString().getValue(), "thread")
        @Expect(imRoute.get("parentPeerKind").getOrThrow().asString().getValue(), "group")
        @Expect(imRoute.get("parentPeerId").getOrThrow().asString().getValue(), "oc_group")
    }

    @TestCase
    public func accountChatThreadQueueSerializesOnlySameThread(): Unit {
        let queue = FeishuChatQueue()
        let probe = FeishuQueueProbe()

        let first = spawn {
            queue.runExclusive("work", "oc_group", "omt_1", { =>
                probe.runSameThreadTask(80)
            })
        }
        sleep(Duration.millisecond * 10)
        let second = spawn {
            queue.runExclusive("work", "oc_group", "omt_1", { =>
                probe.runSameThreadTask(20)
            })
        }
        let third = spawn {
            queue.runExclusive("work", "oc_group", "omt_2", { =>
                probe.runOtherThreadTask()
            })
        }
        first.get()
        second.get()
        third.get()

        @Expect(probe.sameOverlap(), false)
        @Expect(probe.otherObservedParallel(), true)
        @Expect(buildFeishuQueueKey("work", "oc_group", "omt_1"), "work:oc_group:thread:omt_1")
    }

    @TestCase
    public func groupRequireMentionGateKeepsDiagnosticWithoutTrigger(): Unit {
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                botOpenId: "bot-open",
                groupPolicy: "open",
                policy: ChannelPolicyConfig(requireMentionInGroup: true)
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_gate", "oc_group", "ou_1", "{\\\"text\\\":\\\"plain group message\\\"}")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].mentioned, false)
        let gate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(gate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(gate.get("reason").getOrThrow().asString().getValue(), "group_mention_required")
    }

    @TestCase
    public func imageFileMediaAndAudioCreateAttachmentContextWithoutDownload(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true), accountId: "work")
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_image",
                "oc_group",
                "ou_1",
                "{\\\"image_key\\\":\\\"img_v2_1\\\",\\\"file_name\\\":\\\"diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                messageType: "image"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_file",
                "oc_group",
                "ou_1",
                "{\\\"file_key\\\":\\\"file_v2_1\\\",\\\"file_name\\\":\\\"report.pdf\\\",\\\"mime_type\\\":\\\"application/pdf\\\",\\\"size\\\":64}",
                messageType: "file"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_media",
                "oc_group",
                "ou_1",
                "{\\\"file_key\\\":\\\"media_v2_1\\\",\\\"file_name\\\":\\\"clip.mp4\\\",\\\"mime_type\\\":\\\"video/mp4\\\"}",
                messageType: "media"
            )
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_audio",
                "oc_group",
                "ou_1",
                "{\\\"file_key\\\":\\\"audio_v2_1\\\",\\\"file_name\\\":\\\"voice.ogg\\\",\\\"mime_type\\\":\\\"audio/ogg\\\"}",
                messageType: "audio"
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 4)
        let imageRecords = inbound[0].mediaContext.get("records").getOrThrow().asArray()
        let image = imageRecords[0].asObject()
        @Expect(image.get("channel").getOrThrow().asString().getValue(), "feishu")
        @Expect(image.get("accountId").getOrThrow().asString().getValue(), "work")
        @Expect(image.get("mediaKind").getOrThrow().asString().getValue(), "image")
        @Expect(image.get("fileId").getOrThrow().asString().getValue(), "img_v2_1")
        @Expect(image.get("originalFileName").getOrThrow().asString().getValue(), "diagram.png")
        @Expect(image.get("mimeType").getOrThrow().asString().getValue(), "image/png")
        @Expect(image.get("downloaded").getOrThrow().asBool().getValue(), false)
        @Expect(image.get("skippedReason").getOrThrow().asString().getValue(), "metadata_only")

        let file = inbound[1].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        let media = inbound[2].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        let audio = inbound[3].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
        @Expect(file.get("mediaKind").getOrThrow().asString().getValue(), "file")
        @Expect(file.get("fileSize").getOrThrow().asInt().getValue(), 64)
        @Expect(media.get("mediaKind").getOrThrow().asString().getValue(), "media")
        @Expect(audio.get("mediaKind").getOrThrow().asString().getValue(), "audio")
    }

    @TestCase
    public func imageResourceDownloadPersistsToConfiguredSafeTempPath(): Unit {
        let root = "/tmp/metis-feishu-media-download-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let client = FeishuFakeApiClient()
        client.setResource(
            "work",
            "om_image_dl",
            "img_v2_dl",
            "image",
            "fake-image".toArray(),
            contentType: "image/png",
            fileName: "diagram.png"
        )
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                media: FeishuMediaConfig(downloadEnabled: true, allowedMimes: ["image/*"], downloadRoot: root)
            ),
            accountId: "work",
            apiClient: client
        )
        adapter.start()
        try {
            @Expect(adapter.ingestWebhookPayload(
                this.webhookPayload(
                    "om_image_dl",
                    "oc_group",
                    "ou_1",
                    "{\\\"image_key\\\":\\\"img_v2_dl\\\",\\\"file_name\\\":\\\"diagram.png\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                    messageType: "image"
                )
            ).contains("\"ok\":true"), true)

            let inbound = adapter.pullInbound()
            @Expect(inbound.size, 1)
            let record = inbound[0].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            @Expect(record.get("downloaded").getOrThrow().asBool().getValue(), true)
            @Expect(record.get("skippedReason").getOrThrow().asString().getValue(), "")
            let localPath = record.get("localPath").getOrThrow().asString().getValue()
            @Expect(localPath.startsWith(root), true)
            @Expect(localPath.contains(".."), false)
            @Expect(exists(Path(localPath)), true)
            @Expect(String.fromUtf8(File.readFrom(Path(localPath))), "fake-image")
        } finally {
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func resourceDownloadReportsPermissionAndRateLimitFailures(): Unit {
        let root = "/tmp/metis-feishu-media-errors-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        let client = FeishuFakeApiClient()
        client.setResourceError("default", "om_forbidden", "img_forbidden", "image", "forbidden")
        client.setResourceError("default", "om_rate", "file_rate", "file", "rate_limited")
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                media: FeishuMediaConfig(downloadEnabled: true, downloadRoot: root)
            ),
            apiClient: client
        )
        adapter.start()
        try {
            @Expect(adapter.ingestWebhookPayload(
                this.webhookPayload(
                    "om_forbidden",
                    "oc_group",
                    "ou_1",
                    "{\\\"image_key\\\":\\\"img_forbidden\\\",\\\"mime_type\\\":\\\"image/png\\\"}",
                    messageType: "image"
                )
            ).contains("\"ok\":true"), true)
            @Expect(adapter.ingestWebhookPayload(
                this.webhookPayload(
                    "om_rate",
                    "oc_group",
                    "ou_1",
                    "{\\\"file_key\\\":\\\"file_rate\\\",\\\"file_name\\\":\\\"rate.pdf\\\",\\\"mime_type\\\":\\\"application/pdf\\\"}",
                    messageType: "file"
                )
            ).contains("\"ok\":true"), true)

            let inbound = adapter.pullInbound()
            @Expect(inbound.size, 2)
            let forbidden = inbound[0].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            let rate = inbound[1].mediaContext.get("records").getOrThrow().asArray()[0].asObject()
            @Expect(forbidden.get("downloaded").getOrThrow().asBool().getValue(), false)
            @Expect(forbidden.get("skippedReason").getOrThrow().asString().getValue(), "forbidden")
            @Expect(rate.get("downloaded").getOrThrow().asBool().getValue(), false)
            @Expect(rate.get("skippedReason").getOrThrow().asString().getValue(), "rate_limited")
        } finally {
            try { remove(Path(root), recursive: true) } catch (_e: Exception) { () }
        }
    }

    @TestCase
    public func groupConfigProjectsToolPolicyAndSenderGate(): Unit {
        let groups = JsonObject()
        let group = JsonObject()
        group.put("allowFrom", JsonArray([JsonString("ou_allowed")]))
        let tools = JsonObject()
        tools.put("allow", JsonArray([JsonString("feishu_im_user_fetch_resource")]))
        group.put("tools", tools)
        groups.put("oc_team", group)
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                groupPolicy: "allowlist",
                groups: Some(groups)
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_allowed", "oc_team", "ou_allowed", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_denied", "oc_team", "ou_other", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        let route = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        let groupPolicy = route.get("groupPolicy").getOrThrow().asObject()
        let routeTools = groupPolicy.get("tools").getOrThrow().asObject()
        @Expect(routeTools.get("allow").getOrThrow().asArray()[0].asString().getValue(), "feishu_im_user_fetch_resource")
        let deniedGate = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(deniedGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(deniedGate.get("reason").getOrThrow().asString().getValue(), "sender_not_allowed")
    }

    @TestCase
    public func groupPolicyAllowlistAndBotSenderGateAreStructured(): Unit {
        let adapter = FeishuAdapter(
            config: FeishuConfig(
                enabled: true,
                groupPolicy: "allowlist",
                groupAllowFrom: ["oc_allowed"],
                allowBots: false
            )
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_blocked_group", "oc_blocked", "ou_1", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_bot", "oc_allowed", "ou_bot", "{\\\"text\\\":\\\"@bot hello\\\"}")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        let blockedGate = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(blockedGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(blockedGate.get("reason").getOrThrow().asString().getValue(), "group_not_allowed")
        let botGate = inbound[1].mediaContext.get("context").getOrThrow().asObject()
            .get("feishuGate").getOrThrow().asObject()
        @Expect(botGate.get("triggerAgent").getOrThrow().asBool().getValue(), false)
        @Expect(botGate.get("reason").getOrThrow().asString().getValue(), "bot_sender_not_allowed")
    }

    @TestCase
    public func nativeMentionEntitiesBecomeAliasCandidates(): Unit {
        let adapter = FeishuAdapter(config: FeishuConfig(enabled: true, botOpenId: "bot-open"))
        adapter.start()
        let mentions =
            "[" +
            "{\"id\":{\"open_id\":\"ou_writer\",\"user_id\":\"writer-user\"},\"name\":\"Writer\",\"key\":\"@_user_1\"}," +
            "{\"id\":{\"open_id\":\"bot-open\"},\"name\":\"Metis\",\"key\":\"@_user_bot\"}" +
            "]"
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload(
                "om_mentions",
                "oc_group",
                "ou_1",
                "{\\\"text\\\":\\\"please review\\\"}",
                mentions: mentions
            )
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 1)
        @Expect(inbound[0].mentioned, true)
        let aliasCandidates = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("aliasCandidates").getOrThrow().asArray()
        @Expect(aliasCandidates.size(), 1)
        let candidate = aliasCandidates[0].asObject()
        @Expect(candidate.get("platform").getOrThrow().asString().getValue(), "feishu")
        @Expect(candidate.get("openId").getOrThrow().asString().getValue(), "ou_writer")
        @Expect(candidate.get("name").getOrThrow().asString().getValue(), "Writer")
    }

    @TestCase
    public func threadSessionRequiresFakeThreadCapableGroup(): Unit {
        let client = FeishuFakeApiClient()
        client.setThreadCapable("oc_threads", true)
        client.setThreadCapable("oc_plain", false)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, threadSession: true),
            apiClient: client
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_ok", "oc_threads", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_1")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_no", "oc_plain", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_2")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].conversationId.getOrThrow(), "oc_threads:topic:omt_1")
        @Expect(inbound[1].conversationId.getOrThrow(), "oc_plain")
        let route = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(route.get("threadSessionKey").getOrThrow().asString().getValue(), "oc_threads:topic:omt_1")
    }

    @TestCase
    public func threadSessionCachesThreadCapabilityAndReportsSkippedReason(): Unit {
        let client = FeishuFakeApiClient()
        client.setThreadCapable("oc_plain", false)
        let adapter = FeishuAdapter(
            config: FeishuConfig(enabled: true, threadSession: true),
            apiClient: client
        )
        adapter.start()
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_no_1", "oc_plain", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_1")
        ).contains("\"ok\":true"), true)
        @Expect(adapter.ingestWebhookPayload(
            this.webhookPayload("om_thread_no_2", "oc_plain", "ou_1", "{\\\"text\\\":\\\"topic\\\"}", threadId: "omt_2")
        ).contains("\"ok\":true"), true)

        let inbound = adapter.pullInbound()
        @Expect(inbound.size, 2)
        @Expect(inbound[0].conversationId.getOrThrow(), "oc_plain")
        @Expect(client.threadCapabilityChecks("oc_plain"), 1)
        let route = inbound[0].mediaContext.get("context").getOrThrow().asObject()
            .get("imRoute").getOrThrow().asObject()
        @Expect(route.get("threadSessionKey").isNone(), true)
        let diagnostic = route.get("threadSessionDiagnostic").getOrThrow().asObject()
        @Expect(diagnostic.get("status").getOrThrow().asString().getValue(), "skipped")
        @Expect(diagnostic.get("reason").getOrThrow().asString().getValue(), "thread_not_capable")
    }

}
