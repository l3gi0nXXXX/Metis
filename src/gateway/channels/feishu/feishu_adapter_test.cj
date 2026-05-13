package metis.gateway.channels.feishu

import metis.gateway.model.{ChannelPolicyConfig, FeishuConfig}
import std.core.Duration
import std.sync.Mutex
import std.unittest.testmacro.*

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
}
