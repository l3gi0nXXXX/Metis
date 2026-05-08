package metis.gateway.channels.telegram

import metis.core.{GatewayMediaGroupItem, gatewayMediaTranscribeAudioPathForRuntime, parseGatewayAudioParts, parseGatewayChatAction, parseGatewayDocumentParts, parseGatewayEditButtonsParts, parseGatewayEditMediaParts, parseGatewayEditText, parseGatewayInlineKeyboardParts, parseGatewayMediaGroupItems, parseGatewayPhotoParts, parseGatewayPinAction, parseGatewayReactionRemove, parseGatewayReactionStatus, parseGatewayReactionToken, parseGatewayStickerFileId, parseGatewayTopicCreateText, parseGatewayTopicEditText, parseGatewayVideoNoteFileId, parseGatewayVideoParts, parseGatewayVoiceParts}
import metis.gateway.core.{ChannelAdapter, gatewayOpenClawPluginSidecarApplyCurrentMessageReceivedHook, gatewayOpenClawPluginSidecarCommandCatalogForMenu}
import metis.gateway.model.*
import metis.io.PrintUtils
import metis.core.config.CliConfig

import magic.log.LogUtils
import magic.jsonable.*

import std.collection.{ArrayList, HashMap, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, FileInfo, Path, canonicalize, exists}
import std.sync.Mutex
import std.time.*
import stdx.encoding.json.*
import stdx.net.http.*

private let TELEGRAM_DEFAULT_ACCOUNT_ID = "default"

private class TelegramTokenResolution {
    public let token: String
    public let source: String
    public let tokenFile: String
    public let error: String

    public init(token!: String = "", source!: String = "none", tokenFile!: String = "", error!: String = "") {
        this.token = token
        this.source = source
        this.tokenFile = tokenFile
        this.error = error
    }
}

private class TelegramInboundMediaInfo {
    public let kind: String
    public let fileId: String
    public let fileUniqueId: String
    public let mimeType: String
    public let fileSize: Int64
    public let fileName: String
    public let mediaGroupId: String
    public let caption: String
    public let stickerEmoji: String
    public let stickerSetName: String
    public let stickerIsAnimated: Bool
    public let stickerIsVideo: Bool

    public init(
        kind: String,
        fileId: String,
        fileUniqueId!: String = "",
        mimeType!: String = "",
        fileSize!: Int64 = 0,
        fileName!: String = "",
        mediaGroupId!: String = "",
        caption!: String = "",
        stickerEmoji!: String = "",
        stickerSetName!: String = "",
        stickerIsAnimated!: Bool = false,
        stickerIsVideo!: Bool = false
    ) {
        this.kind = kind
        this.fileId = fileId
        this.fileUniqueId = fileUniqueId
        this.mimeType = mimeType
        this.fileSize = fileSize
        this.fileName = fileName
        this.mediaGroupId = mediaGroupId
        this.caption = caption
        this.stickerEmoji = stickerEmoji
        this.stickerSetName = stickerSetName
        this.stickerIsAnimated = stickerIsAnimated
        this.stickerIsVideo = stickerIsVideo
    }
}

private class TelegramPendingMediaGroup {
    public let key: String
    public var firstSeenAtMs: Int64
    public var lastSeenAtMs: Int64
    public let messages: ArrayList<InboundMessage>

    public init(key: String, firstSeenAtMs: Int64) {
        this.key = key
        this.firstSeenAtMs = firstSeenAtMs
        this.lastSeenAtMs = firstSeenAtMs
        this.messages = ArrayList<InboundMessage>()
    }
}

private var telegramAsrRunnerOverride: Option<(String, String) -> String> = None<(String, String) -> String>

public func setTelegramAsrRunnerForTest(runner: Option<(String, String) -> String>): Unit {
    telegramAsrRunnerOverride = runner
}

private class TelegramWebhookBodyReadResult {
    public let ok: Bool
    public let payload: String
    public let error: String

    public init(ok: Bool, payload!: String = "", error!: String = "") {
        this.ok = ok
        this.payload = payload
        this.error = error
    }
}

private func normalizeTelegramAccountIdForState(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty() || trimmed == "telegram:default") {
        return TELEGRAM_DEFAULT_ACCOUNT_ID
    }
    if (trimmed.startsWith("telegram:")) {
        return trimmed["telegram:".size..].trimAscii().toAsciiLower()
    }
    trimmed.toAsciiLower()
}

private func safeTelegramStateSegment(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return TELEGRAM_DEFAULT_ACCOUNT_ID
    }
    let out = StringBuilder()
    for (r in trimmed.runes()) {
        if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'.' || r == r'_' || r == r'-') {
            out.append(r)
        } else {
            out.append(r'_')
        }
    }
    let normalized = out.toString().trimAscii()
    if (normalized.isEmpty()) { TELEGRAM_DEFAULT_ACCOUNT_ID } else { normalized }
}

private func telegramAccountStateDirFor(rootDir: Path, accountId: String): Path {
    let root = rootDir.join("gateway-telegram")
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    let dir = root.join("accounts").join(safeTelegramStateSegment(normalizeTelegramAccountIdForState(accountId)))
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

/**
 * Telegram 原生 Bot API 适配器。
 *
 * T2 目标是先替掉 generic builtin stub，建立 Telegram 原生 runtime 骨架：
 * - 独立 start/stop/pull/send 生命周期
 * - webhook / polling 模式提示
 * - 真实 `sendMessage` Bot API 出站
 * - 为后续 inbound / topics / reactions / media 留出原生扩展点
 */
public class TelegramAdapter <: ChannelAdapter {
    private let config: TelegramConfig
    private let pairingStore: TelegramPairingStore
    private let stateRoot: Path
    private let registerNativeCommandsOnStart: Bool
    private let queueMutex = Mutex()
    private let offsetMutex = Mutex()
    private let inboundQueue = ArrayList<InboundMessage>()
    private let outboundLog = ArrayList<OutboundMessage>()
    private let pendingUpdateIds = HashSet<String>()
    private let completedUpdateIds = HashSet<String>()
    private let completedUpdateIdOrder = ArrayList<String>()
    private let consumedApprovalCallbacks = HashSet<String>()
    private let pendingMediaGroups = HashMap<String, TelegramPendingMediaGroup>()
    private let groupHistoryByPeer = HashMap<String, ArrayList<JsonObject>>()
    private let webhookGuardMutex = Mutex()
    private let webhookRateWindowStartedAtBySource = HashMap<String, Int64>()
    private let webhookRateCountBySource = HashMap<String, Int64>()
    private var pollingRunner: Option<TelegramPollingRunner> = None<TelegramPollingRunner>
    private var telegramTransportRebuildCount: Int64 = 0
    private var running = false
    private var webhookServer: Option<Server> = None
    private var lastSendError: String = ""
    private var botUsernameLookupAttempted: Bool = false
    private var cachedBotUsername: String = ""
    private var nativeCommandsLastSyncStatus: String = "not-attempted"
    private var nativeCommandsLastSyncError: String = ""
    private var nativeCommandsLastSyncAtMs: Int64 = 0
    private var nativeCommandsLastSyncCommandCount: Int64 = 0
    private var nativeCommandsLastSyncHash: String = ""
    private var nativeCommandsLastSyncSkipped: Bool = false
    private var nativeCommandsLastSyncRetryCount: Int64 = 0
    private var nativeCommandsLastSyncTrimmedCount: Int64 = 0
    private var chatActionBackoffUntilMs: Int64 = 0
    private var chatActionBackoffReason: String = ""
    private var webhookRegistrationStatus: String = "not-attempted"
    private var webhookRegistrationError: String = ""
    private var webhookRegistrationAtMs: Int64 = 0
    private var webhookCleanupStatus: String = "not-attempted"
    private var webhookCleanupError: String = ""
    private var webhookCleanupAtMs: Int64 = 0
    private var pollingWebhookCleared: Bool = false
    private var lastInboundDecision: String = "none"
    private var lastInboundReason: String = ""
    private var lastInboundUpdateKind: String = ""
    private var lastInboundUpdateIdForPolicy: String = ""
    private var lastInboundPeerId: String = ""
    private var lastInboundSenderId: String = ""
    private var lastInboundMessageIdForPolicy: String = ""
    private var lastConfirmedPollingOffset: String = ""
    private var lastRetryAfterSeconds: Int64 = 0

    public init(
        config!: TelegramConfig = TelegramConfig(),
        pairingRoot!: String = "",
        registerNativeCommandsOnStart!: Bool = false
    ) {
        let resolvedStateRoot = if (pairingRoot.trimAscii().isEmpty()) { CliConfig.dotDir } else { Path(pairingRoot.trimAscii()) }
        this.config = config
        this.registerNativeCommandsOnStart = registerNativeCommandsOnStart
        this.stateRoot = resolvedStateRoot
        this.pairingStore = telegramPairingAccountStore(
            rootDir: resolvedStateRoot,
            accountId: config.accountId
        )
        this.pollingRunner = Some(TelegramPollingRunner(
            { => this.fetchTelegramUpdates() },
            { raw: String => this.ingestPollingResponse(raw) },
            { => this.running && !this.usesWebhookMode() },
            rebuildTransport: { => this.markTelegramTransportDirtyForPollingWatchdog() }
        ))
    }

    public prop name: String {
        get() { "telegram" }
    }

    public func start(): Unit {
        if (this.running || !this.config.enabled) {
            return
        }
        if (this.effectiveBotToken().isEmpty()) {
            this.lastSendError = "Telegram adapter requires botToken or tokenFile"
            LogUtils.error("Telegram adapter start failed: ${this.lastSendError}")
            return
        }
        this.running = true
        this.markPollingIdle()
        if (this.usesWebhookMode()) {
            this.registerWebhookWithTelegram()
            this.startWebhookServer()
            this.startNativeCommandSyncIfNeeded()
            PrintUtils.printLine("Telegram adapter started in webhook mode")
            return
        }
        this.ensurePollingWebhookCleared("polling-start")
        this.startPollingLoop()
        this.startNativeCommandSyncIfNeeded()
        PrintUtils.printLine("Telegram adapter started in polling mode")
    }

    public func stop(): Unit {
        let shouldConfirmOffset = this.running && !this.usesWebhookMode()
        this.running = false
        if (shouldConfirmOffset) {
            this.confirmPollingOffsetOnStop()
        }
        this.markPollingStopped()
        if (let Some(server) <- this.webhookServer) {
            try {
                server.close()
            } catch (_e: Exception) {
                ()
            } finally {
                this.webhookServer = None
            }
        }
        this.pollingRunnerOrThrow().stop()
    }

    public func pullInbound(): Array<InboundMessage> {
        synchronized(this.queueMutex) {
            if (!this.running) {
                return []
            }
            let drained = this.inboundQueue.toArray()
            this.inboundQueue.clear()
            let out = this.mergeTelegramTextBurstInboundMessages(
                this.collectTelegramMediaGroupsForPull(drained)
            )
            out
        }
    }

    private func mergeTelegramTextBurstInboundMessages(messages: Array<InboundMessage>): Array<InboundMessage> {
        let out = ArrayList<InboundMessage>()
        for (msg in messages) {
            if (!this.telegramInboundCanTextBurstMerge(msg)) {
                out.add(msg)
                continue
            }
            if (out.size > 0 && this.telegramInboundShouldTextBurstMerge(out[out.size - 1], msg)) {
                out[out.size - 1] = this.mergeTelegramTextBurstMessage(out[out.size - 1], msg)
            } else {
                out.add(msg)
            }
        }
        out.toArray()
    }

    private func telegramMediaContextAllowsTextBurstMerge(mediaContext: JsonObject): Bool {
        if (mediaContext.size() == 0) {
            return true
        }
        match (mediaContext.get("records")) {
            case Some(_) => return false
            case None => ()
        }
        match (mediaContext.get("context")) {
            case Some(_) => return false
            case None => ()
        }
        true
    }

    private func telegramInboundCanTextBurstMerge(msg: InboundMessage): Bool {
        let text = msg.text.trimAscii()
        if (text.isEmpty() || text.startsWith("/") || text.startsWith("[")) {
            return false
        }
        if (text.contains("\n[")) {
            return false
        }
        this.telegramMediaContextAllowsTextBurstMerge(msg.mediaContext)
    }

    private func telegramInboundShouldTextBurstMerge(first: InboundMessage, next: InboundMessage): Bool {
        if (!this.telegramInboundCanTextBurstMerge(first) || !this.telegramInboundCanTextBurstMerge(next)) {
            return false
        }
        if (this.telegramInboundBurstKey(first) != this.telegramInboundBurstKey(next)) {
            return false
        }
        if (first.text.size + next.text.size > 12000) {
            return false
        }
        if (first.text.split("\n").size + next.text.split("\n").size > 12) {
            return false
        }
        try {
            let firstId = Int64.parse(first.messageId.trimAscii())
            let nextId = Int64.parse(next.messageId.trimAscii())
            if (nextId <= firstId || nextId - firstId > 1) {
                return false
            }
        } catch (_e: Exception) {
            ()
        }
        true
    }

    private func telegramInboundBurstKey(msg: InboundMessage): String {
        let thread = match (msg.threadId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        "${msg.peerId}|${msg.senderId}|${thread}"
    }

    private func mergeTelegramTextBurstMediaContext(first: JsonObject, next: JsonObject, messageId: String): JsonObject {
        if (first.size() == 0 && next.size() == 0) {
            return first
        }
        let merged = JsonObject()
        for (key in ["channel", "accountId", "peerId", "mediaStatePath"]) {
            let nextValue = this.readStringField(next, key)
            let value = if (!nextValue.isEmpty()) { nextValue } else { this.readStringField(first, key) }
            if (!value.isEmpty()) {
                merged.put(key, JsonString(value))
            }
        }
        merged.put("messageId", JsonString(messageId))
        merged
    }

    private func mergeTelegramTextBurstMessage(first: InboundMessage, next: InboundMessage): InboundMessage {
        let mergedContext = this.mergeTelegramTextBurstMediaContext(first.mediaContext, next.mediaContext, next.messageId)
        InboundMessage(
            first.channel,
            next.messageId,
            first.peerId,
            first.senderId,
            first.chatType,
            first.text + "\n" + next.text,
            first.mentioned || next.mentioned,
            next.timestamp,
            conversationId: first.conversationId,
            threadId: first.threadId,
            replyTargetMessageId: first.replyTargetMessageId,
            replyInThread: first.replyInThread,
            raw: first.raw,
            accountId: first.accountId,
            mediaContext: mergedContext
        )
    }

    private func collectTelegramMediaGroupsForPull(messages: Array<InboundMessage>): Array<InboundMessage> {
        let out = ArrayList<InboundMessage>()
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        this.flushTelegramPendingMediaGroups(out, nowMs, force: false)
        for (msg in messages) {
            let groupId = this.inboundPrimaryMediaGroupId(msg)
            if (groupId.isEmpty()) {
                this.flushTelegramPendingMediaGroups(out, nowMs, force: true)
                out.add(msg)
                continue
            }
            let key = this.telegramInboundBurstKey(msg) + "|album:" + groupId
            if (this.pendingMediaGroups.get(key).isNone() && this.pendingMediaGroups.size > 0) {
                this.flushTelegramPendingMediaGroups(out, nowMs, force: true)
            }
            let pending = match (this.pendingMediaGroups.get(key)) {
                case Some(existing) => existing
                case None =>
                    let created = TelegramPendingMediaGroup(key, nowMs)
                    this.pendingMediaGroups[key] = created
                    created
            }
            pending.messages.add(msg)
            pending.lastSeenAtMs = nowMs
        }
        this.flushTelegramPendingMediaGroups(out, nowMs, force: false)
        out.toArray()
    }

    private func flushTelegramPendingMediaGroups(out: ArrayList<InboundMessage>, nowMs: Int64, force!: Bool): Unit {
        let flushKeys = ArrayList<String>()
        for ((key, pending) in this.pendingMediaGroups) {
            if (force || pending.messages.size > 1 || nowMs - pending.firstSeenAtMs >= 700) {
                out.add(this.mergeTelegramMediaGroupPending(pending))
                flushKeys.add(key)
            }
        }
        for (key in flushKeys) {
            this.pendingMediaGroups.remove(key)
        }
    }

    private func mergeTelegramMediaGroupPending(pending: TelegramPendingMediaGroup): InboundMessage {
        var merged = pending.messages[0]
        var idx: Int64 = 1
        while (idx < pending.messages.size) {
            merged = this.mergeTelegramMediaGroupMessage(merged, pending.messages[idx])
            idx += 1
        }
        merged
    }

    private func mergeTelegramMediaGroupInboundMessages(messages: Array<InboundMessage>): Array<InboundMessage> {
        let out = ArrayList<InboundMessage>()
        let groupPositions = HashMap<String, Int64>()
        for (msg in messages) {
            let groupId = this.inboundPrimaryMediaGroupId(msg)
            if (groupId.isEmpty()) {
                out.add(msg)
                continue
            }
            match (groupPositions.get(groupId)) {
                case Some(pos) =>
                    out[pos] = this.mergeTelegramMediaGroupMessage(out[pos], msg)
                case None =>
                    groupPositions[groupId] = out.size
                    out.add(msg)
            }
        }
        out.toArray()
    }

    private func inboundPrimaryMediaGroupId(message: InboundMessage): String {
        match (message.mediaContext.get("records")) {
            case Some(v) =>
                try {
                    let records = v.asArray()
                    if (records.size() == 0) {
                        return ""
                    }
                    this.readStringField(records[0].asObject(), "mediaGroupId").trimAscii()
                } catch (_e: Exception) {
                    ""
                }
            case None => ""
        }
    }

    private func mediaContextRecords(context: JsonObject): JsonArray {
        match (context.get("records")) {
            case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
    }

    private func mergeTelegramMediaGroupContext(first: JsonObject, next: JsonObject, messageId: String): JsonObject {
        let merged = JsonObject()
        for (key in ["channel", "accountId", "peerId"]) {
            let value = this.readStringField(first, key)
            if (!value.isEmpty()) {
                merged.put(key, JsonString(value))
            }
        }
        merged.put("messageId", JsonString(messageId))
        let records = JsonArray([])
        for (item in this.mediaContextRecords(first).getItems()) {
            records.add(item)
        }
        for (item in this.mediaContextRecords(next).getItems()) {
            records.add(item)
        }
        merged.put("records", records)
        merged
    }

    private func mergeTelegramMediaGroupMessage(first: InboundMessage, next: InboundMessage): InboundMessage {
        let mergedContext = this.mergeTelegramMediaGroupContext(first.mediaContext, next.mediaContext, next.messageId)
        let text = if (first.text.trimAscii().isEmpty()) { next.text } else { first.text }
        InboundMessage(
            first.channel,
            next.messageId,
            first.peerId,
            first.senderId,
            first.chatType,
            text,
            first.mentioned || next.mentioned,
            next.timestamp,
            conversationId: first.conversationId,
            threadId: first.threadId,
            replyTargetMessageId: first.replyTargetMessageId,
            replyInThread: first.replyInThread,
            raw: first.raw,
            accountId: first.accountId,
            mediaContext: mergedContext
        )
    }

    public func send(message: OutboundMessage): SendResult {
        let sentMessageId = this.sendWithMessageId(message)
        if (!sentMessageId.trimAscii().isEmpty() || this.lastSendError.trimAscii().isEmpty()) {
            return SendResult.Success
        }
        SendResult.Failed("failed to send telegram message: ${this.lastSendError}")
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        this.sendWithMessageIdImpl(message, requireRunning: true)
    }

    public func sendDirectWithMessageIdForGatewayRpc(message: OutboundMessage): String {
        this.sendWithMessageIdImpl(message, requireRunning: false)
    }

    private func sendWithMessageIdImpl(message: OutboundMessage, requireRunning!: Bool): String {
        if (requireRunning && !this.running) {
            this.lastSendError = "telegram adapter is not running"
            return ""
        }
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
        }
        if (!this.config.actions.sendMessage) {
            this.lastSendError = "telegram sendMessage action is disabled"
            return ""
        }
        var lastMessageId = ""
        for (payload in this.buildSendPayloads(message)) {
            if (this.payloadIsPoll(payload) && !this.config.actions.poll) {
                this.lastSendError = "telegram poll action is disabled"
                return ""
            }
            if (payload.get("validation_error").isSome()) {
                this.lastSendError = this.payloadValidationError(payload)
                return ""
            }
            if (this.payloadIsDelete(payload) && !this.config.actions.deleteMessage) {
                this.lastSendError = "telegram deleteMessage action is disabled"
                return ""
            }
            if (this.payloadIsClearButtons(payload) && !this.config.actions.editMessage) {
                this.lastSendError = "telegram clear-buttons action requires editMessage action"
                return ""
            }
            if (this.payloadIsEditButtons(payload) && !this.config.actions.editMessage) {
                this.lastSendError = "telegram editButtons action requires editMessage action"
                return ""
            }
            if (this.payloadIsEdit(payload) && !this.config.actions.editMessage) {
                this.lastSendError = "telegram editMessage action is disabled"
                return ""
            }
            if (this.payloadIsEditMedia(payload) && !this.config.actions.editMessage) {
                this.lastSendError = "telegram editMessage action is disabled"
                return ""
            }
            if (this.payloadIsPin(payload) && !this.config.actions.pinMessage) {
                this.lastSendError = "telegram pinMessage action is disabled"
                return ""
            }
            if (this.payloadIsUnpin(payload) && !this.config.actions.unpinMessage) {
                this.lastSendError = "telegram unpinMessage action is disabled"
                return ""
            }
            if (this.payloadIsReaction(payload) && !this.config.actions.reactions) {
                this.lastSendError = "telegram reaction action is disabled"
                return ""
            }
            if (this.payloadIsInlineKeyboardInvalid(payload)) {
                this.lastSendError = this.payloadValidationError(payload)
                return ""
            }
            if ((this.payloadIsDraft(payload) || this.payloadIsApproval(payload)) && payload.get("validation_error").isSome()) {
                this.lastSendError = this.payloadValidationError(payload)
                return ""
            }
            if (this.payloadIsMediaInvalid(payload)) {
                this.lastSendError = this.payloadValidationError(payload)
                return ""
            }
            if (this.payloadIsInlineKeyboard(payload) && !this.config.actions.inlineKeyboard) {
                this.lastSendError = "telegram inlineKeyboard action is disabled"
                return ""
            }
            if ((this.payloadIsInlineKeyboard(payload) || this.payloadIsApproval(payload) || this.payloadIsEditButtons(payload)) &&
                !this.inlineButtonsAllowedForPeer(message.peerId)) {
                this.lastSendError = "telegram inline button scope blocks peer"
                return ""
            }
            if (this.payloadIsDraft(payload) && !this.config.actions.editMessage) {
                this.lastSendError = "telegram draft preview requires editMessage action"
                return ""
            }
            if (this.payloadIsApproval(payload) && !this.config.actions.inlineKeyboard) {
                this.lastSendError = "telegram approval buttons require inlineKeyboard action"
                return ""
            }
            if (this.payloadIsSticker(payload) && !this.config.actions.sticker) {
                this.lastSendError = "telegram sticker action is disabled"
                return ""
            }
            if (this.payloadIsPhoto(payload) && !this.config.actions.photo) {
                this.lastSendError = "telegram photo action is disabled"
                return ""
            }
            if (this.payloadIsAnimation(payload) && !this.config.actions.photo) {
                this.lastSendError = "telegram animation action requires photo action"
                return ""
            }
            if (this.payloadIsDocument(payload) && !this.config.actions.document) {
                this.lastSendError = "telegram document action is disabled"
                return ""
            }
            if (this.payloadIsAudio(payload) && !this.config.actions.audio) {
                this.lastSendError = "telegram audio action is disabled"
                return ""
            }
            if (this.payloadIsVoice(payload) && !this.config.actions.voice) {
                this.lastSendError = "telegram voice action is disabled"
                return ""
            }
            if (this.payloadIsVideo(payload) && !this.config.actions.video) {
                this.lastSendError = "telegram video action is disabled"
                return ""
            }
            if (this.payloadIsVideoNote(payload) && !this.config.actions.videoNote) {
                this.lastSendError = "telegram video-note action is disabled"
                return ""
            }
            if (this.payloadIsTopicCreate(payload) && !this.config.actions.createForumTopic) {
                this.lastSendError = "telegram topic-create action is disabled"
                return ""
            }
            if (this.payloadIsTopicEdit(payload) && !this.config.actions.editForumTopic) {
                this.lastSendError = "telegram topic-edit action is disabled"
                return ""
            }
            if (this.payloadIsChatAction(payload) && this.chatActionBackoffActive()) {
                this.lastSendError = "telegram chat-action backoff active: ${this.chatActionBackoffReason}"
                return ""
            }
            let sentMessageId = this.sendPayloadToTelegram(payload)
            if (this.payloadIsChatAction(payload) && sentMessageId.isEmpty()) {
                this.recordChatActionBackoffIfNeeded()
            }
            if (sentMessageId.isEmpty()) {
                return ""
            }
            lastMessageId = sentMessageId
        }
        if (!lastMessageId.trimAscii().isEmpty()) {
            this.recordSentTelegramMessage(message, lastMessageId)
            this.maybeRemoveAckAfterReply(message)
        }
        lastMessageId
    }

    public func simulateIncomingText(
        messageId: String,
        peerId: String,
        senderId: String,
        text: String,
        chatType!: ChatType = ChatType.Direct,
        mentioned!: Bool = true,
        threadId!: Option<String> = None
    ): Unit {
        let msg = InboundMessage(
            ChannelType.Telegram,
            messageId,
            peerId,
            senderId,
            chatType,
            text,
            mentioned,
            DateTime.now(),
            threadId: threadId,
            replyInThread: threadId != None,
            raw: Some(text),
            accountId: this.effectiveAccountId()
        )
        synchronized(this.queueMutex) {
            this.inboundQueue.add(msg)
        }
    }

    public func getOutboundLog(): Array<OutboundMessage> {
        synchronized(this.queueMutex) {
            this.outboundLog.toArray()
        }
    }

    public func debugPendingPairingCode(senderId: String): String {
        this.pairingStore.pendingCodeForSender(senderId)
    }

    public func debugApprovePairingCode(code: String): Bool {
        this.pairingStore.approve(code)
    }

    public func debugBuildSendPayloads(message: OutboundMessage): JsonArray {
        let out = JsonArray([])
        for (payload in this.buildSendPayloads(message)) {
            out.add(JsonObject(payload))
        }
        out
    }

    public func debugBuildNativeCommandsPayload(): JsonObject {
        this.buildNativeCommandsPayload()
    }

    public func debugBuildAllowedUpdates(): JsonArray {
        this.buildAllowedUpdates()
    }

    public func debugBuildWebhookRegistrationPayload(): JsonObject {
        this.buildWebhookRegistrationPayload()
    }

    public func debugBuildWebhookDeletePayload(): JsonObject {
        this.buildWebhookDeletePayload(dropPendingUpdates: false)
    }

    public func debugBuildWebhookDeletePayloadWithDropPendingForTest(dropPending: Bool): JsonObject {
        this.buildWebhookDeletePayload(dropPendingUpdates: dropPending)
    }

    public func debugRegisterWebhookForTest(): Bool {
        this.registerWebhookWithTelegram()
    }

    public func debugEnsurePollingWebhookClearedForTest(reason!: String = "test"): Bool {
        this.ensurePollingWebhookCleared(reason)
    }

    public func debugBuildWebhookLifecycleDiagnostics(): JsonObject {
        this.buildWebhookLifecycleDiagnostics()
    }

    public func debugBuildInboundPolicyDiagnostics(): JsonObject {
        this.buildInboundPolicyDiagnostics()
    }

    public func debugValidateWebhookSecretForTest(secretHeader: String): Bool {
        this.validateWebhookSecretHeader(secretHeader)
    }

    public func debugResolveWebhookSourceForTest(xForwardedFor: String, xRealIp: String, remoteHint: String): String {
        this.resolveWebhookSource(xForwardedFor, xRealIp, remoteHint)
    }

    public func debugWebhookRateLimitAllowsForTest(source: String, nowMs: Int64): Bool {
        this.webhookRateLimitAllows(source, nowMs: nowMs)
    }

    public func debugBuildWebhookGuardForTest(method: String, path: String, bodyBytes: Int64, source: String, nowMs: Int64): JsonObject {
        this.buildWebhookGuardResult(method, path, bodyBytes, source, nowMs: nowMs)
    }

    public func debugBuildHealthSnapshot(
        getMeRaw!: String = "{\"ok\":true,\"result\":{\"id\":1,\"is_bot\":true,\"username\":\"bot\"}}",
        webhookInfoRaw!: String = "{\"ok\":true,\"result\":{\"url\":\"\",\"pending_update_count\":0}}"
    ): JsonObject {
        this.buildTelegramHealthSnapshot(getMeRaw, webhookInfoRaw)
    }

    public func debugBuildPollingDiagnosticSnapshot(): JsonObject {
        this.buildPollingDiagnosticSnapshot()
    }

    public func debugCurrentPollBackoffMsForTest(): Int64 {
        this.currentPollBackoffMs()
    }

    public func debugSetPollingWatchdogForTest(stallMs: Int64, intervalMs: Int64): Unit {
        this.pollingRunnerOrThrow().debugSetWatchdogForTest(stallMs, intervalMs)
    }

    public func debugTelegramTransportRebuildCountForTest(): Int64 {
        this.telegramTransportRebuildCount
    }

    public func debugLastSendErrorForTest(): String {
        this.lastSendError
    }

    public func debugChatActionBackoffUntilMsForTest(): Int64 {
        this.chatActionBackoffUntilMs
    }

    public func debugTryTelegramGetChatForTest(chatId: String): JsonObject {
        this.tryTelegramGetChat(chatId)
    }

    public func debugTrustedLocalTelegramFilePathForTest(filePath: String): String {
        this.trustedLocalTelegramFilePath(filePath)
    }

    public func debugReadGroupMigrationStateForTest(): JsonArray {
        let path = this.groupMigrationStatePath()
        if (!exists(path)) {
            return JsonArray([])
        }
        try { JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray() } catch (_e: Exception) { JsonArray([]) }
    }

    public func debugBuildLiveProbe(): JsonObject {
        let out = JsonObject()
        out.put("supported", true.toJsonValue())
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            out.put("executed", false.toJsonValue())
            out.put("status", JsonString("missing-token"))
            return out
        }
        let apiRoot = this.normalizeApiRoot()
        let getMeRaw = this.tryTelegramGet("${apiRoot}/bot${token}/getMe")
        let webhookInfoRaw = this.tryTelegramGet("${apiRoot}/bot${token}/getWebhookInfo")
        let snapshot = this.buildTelegramHealthSnapshot(getMeRaw, webhookInfoRaw)
        let getMe = snapshot.get("getMe").getOrThrow().asObject()
        let webhookInfo = snapshot.get("webhookInfo").getOrThrow().asObject()
        let getMeOk = this.readJsonBoolField(getMe, "ok", false)
        let webhookInfoOk = this.readJsonBoolField(webhookInfo, "ok", false)
        out.put("executed", true.toJsonValue())
        out.put("status", JsonString(if (getMeOk && webhookInfoOk) { "ok" } else { "degraded" }))
        out.put("healthy", (getMeOk && webhookInfoOk).toJsonValue())
        out.put("snapshot", snapshot)
        out
    }

    public func debugRedactTelegramUrlForTest(url: String): String {
        this.telegramTransport().redactUrl(url)
    }

    public func debugTelegramRenderHtmlForTest(text: String): String {
        this.telegramRenderHtml(text)
    }

    public func debugIngestPollingResponse(raw: String): Int64 {
        this.ingestPollingResponse(raw)
    }

    public func debugFetchTelegramUpdatesRaw(): String {
        this.fetchTelegramUpdates()
    }

    public func debugRunPollingIterationForTest(): Int64 {
        this.runPollingIteration()
    }

    public func debugConfirmPollingOffsetOnStopForTest(): Bool {
        this.confirmPollingOffsetOnStop()
    }

    public func debugLastConfirmedPollingOffsetForTest(): String {
        this.lastConfirmedPollingOffset
    }

    public func debugRetryAfterSecondsForTest(raw: String): Int64 {
        this.telegramRetryAfterSeconds(raw)
    }

    public func debugSupportedUpdateTypesForTest(): JsonArray {
        this.buildTelegramUpdateTypeCapabilityMatrix()
    }

    public func debugSyncNativeCommandsForTest(): Bool {
        this.syncNativeCommands()
    }

    public func debugLastInboundUpdateId(): String {
        this.readLastInboundUpdateId()
    }

    public func debugOffsetDiagnosticsForTest(): JsonObject {
        this.buildOffsetDiagnostics()
    }

    public func debugReadMediaState(): JsonObject {
        this.readMediaState()
    }

    public func debugReadSentMessageStateForTest(): JsonObject {
        this.readSentMessageState()
    }

    public func debugPersistInboundMediaForTest(
        kind: String,
        fileId: String,
        caption!: String = "",
        fileUniqueId!: String = "",
        mimeType!: String = "",
        fileSize!: Int64 = 0,
        fileName!: String = "",
        mediaGroupId!: String = "",
        peerId!: String = "",
        messageId!: String = "",
        getFileRaw!: String = "",
        downloadRaw!: String = ""
    ): JsonObject {
        this.persistInboundMedia(
            TelegramInboundMediaInfo(
                kind,
                fileId,
                fileUniqueId: fileUniqueId,
                mimeType: mimeType,
                fileSize: fileSize,
                fileName: fileName,
                mediaGroupId: mediaGroupId,
                caption: caption
            ),
            peerId: peerId,
            messageId: messageId,
            getFileRaw: getFileRaw,
            downloadRaw: downloadRaw
        )
        this.readMediaState()
    }

    public func ingestWebhookPayload(payload: String): String {
        this.ingestTelegramUpdatePayload(payload, dedupeByOffset: false)
    }

    public func ingestWebhookPayloadWithSecret(payload: String, secretHeader: String): String {
        if (!this.validateWebhookSecretHeader(secretHeader)) {
            return "{\"ok\":false,\"error\":\"webhook_secret_mismatch\"}"
        }
        this.ingestWebhookPayload(payload)
    }

    private func validateWebhookSecretHeader(secretHeader: String): Bool {
        let expected = this.config.webhookSecret.trimAscii()
        if (expected.isEmpty()) {
            return true
        }
        this.constantTimeStringEquals(secretHeader.trimAscii(), expected)
    }

    private func constantTimeStringEquals(left: String, right: String): Bool {
        let leftBytes = left.toArray()
        let rightBytes = right.toArray()
        let maxSize = if (leftBytes.size > rightBytes.size) { leftBytes.size } else { rightBytes.size }
        var mismatch = leftBytes.size != rightBytes.size
        var i: Int64 = 0
        while (i < Int64(maxSize)) {
            let a = if (i < Int64(leftBytes.size)) { Int64(leftBytes[i]) } else { 0 }
            let b = if (i < Int64(rightBytes.size)) { Int64(rightBytes[i]) } else { 0 }
            if (a != b) {
                mismatch = true
            }
            i += 1
        }
        !mismatch
    }

    private func ingestTelegramUpdatePayload(payload: String, dedupeByOffset!: Bool = false): String {
        let root = try {
            JsonValue.fromStr(payload).asObject()
        } catch (_e: Exception) {
            return "{\"ok\":false,\"error\":\"invalid_json\"}"
        }
        let updateId = this.readIntStringField(root, "update_id")
        if (!this.beginUpdateProcessing(updateId, dedupeByOffset: dedupeByOffset)) {
            this.recordInboundDecision(updateId, this.primaryUpdateKind(root), "ignored", "duplicate_update")
            return "{\"ok\":true,\"ignored\":true,\"duplicate\":true}"
        }
        try {
            if (let Some(inbound) <- this.mapWebhookToInbound(root, payload)) {
                this.applyTelegramMessageReceivedHook(inbound, accepted: true, reason: "", raw: payload)
                synchronized(this.queueMutex) {
                    this.inboundQueue.add(inbound)
                }
                this.maybeAckInboundReaction(inbound)
                this.recordInboundDecision(
                    updateId,
                    this.primaryUpdateKind(root),
                    "accepted",
                    "",
                    peerId: inbound.peerId,
                    senderId: inbound.senderId,
                    messageId: inbound.messageId
                )
                this.completeUpdateProcessing(updateId)
                return "{\"ok\":true}"
            }
            this.applyIgnoredTelegramMessageReceivedHook(root, payload)
            this.completeUpdateProcessing(updateId)
            "{\"ok\":true,\"ignored\":true}"
        } catch (e: Exception) {
            this.finishUpdateProcessingWithoutWatermark(updateId)
            "{\"ok\":false,\"error\":\"update_processing_failed\",\"message\":\"${e.message}\"}"
        }
    }

    private func usesWebhookMode(): Bool {
        !this.config.webhookUrl.trimAscii().isEmpty()
    }

    private func buildAllowedUpdates(): JsonArray {
        let updates = JsonArray([])
        let seen = HashSet<String>()
        for (kind in ["message", "edited_message", "channel_post", "edited_channel_post"]) {
            updates.add(JsonString(kind))
            seen.add(kind)
        }
        let notifications = this.config.reactionNotifications.trimAscii().toAsciiLower()
        if (!(notifications == "off" || notifications == "false" || notifications == "disabled")) {
            if (!seen.contains("message_reaction")) {
                updates.add(JsonString("message_reaction"))
                seen.add("message_reaction")
            }
        }
        if (this.config.actions.callbackQuery || this.config.actions.inlineKeyboard) {
            if (!seen.contains("callback_query")) {
                updates.add(JsonString("callback_query"))
                seen.add("callback_query")
            }
        }
        for (raw in this.config.network.allowedUpdatesExtra) {
            let kind = raw.trimAscii()
            if (!kind.isEmpty() && !seen.contains(kind)) {
                updates.add(JsonString(kind))
                seen.add(kind)
            }
        }
        updates
    }

    private func buildWebhookRegistrationPayload(): JsonObject {
        let out = JsonObject()
        out.put("url", JsonString(this.config.webhookUrl.trimAscii()))
        if (!this.config.webhookSecret.trimAscii().isEmpty()) {
            out.put("secret_token", JsonString(this.config.webhookSecret.trimAscii()))
        }
        out.put("allowed_updates", this.buildAllowedUpdates())
        if (!this.config.webhookCertPath.trimAscii().isEmpty()) {
            out.put("certificatePath", JsonString(this.config.webhookCertPath.trimAscii()))
        }
        out
    }

    private func buildWebhookDeletePayload(dropPendingUpdates!: Bool = false): JsonObject {
        let out = JsonObject()
        out.put("drop_pending_updates", dropPendingUpdates.toJsonValue())
        out
    }

    private func effectiveBotToken(): String {
        this.resolveTelegramToken().token
    }

    private func effectiveAccountId(): String {
        this.normalizeTelegramAccountId(this.config.accountId)
    }

    private func normalizeTelegramAccountId(raw: String): String {
        normalizeTelegramAccountIdForState(raw)
    }

    private func resolveTelegramToken(): TelegramTokenResolution {
        let accountId = this.effectiveAccountId()
        let accountCfg = this.resolveTelegramAccountConfig(accountId)
        if (accountId != TELEGRAM_DEFAULT_ACCOUNT_ID && accountCfg.isNone() && this.config.accounts.isSome()) {
            return TelegramTokenResolution(source: "none", error: "unknown accountId: ${accountId}")
        }
        match (accountCfg) {
            case Some(account) =>
                let accountTokenFile = this.readStringField(account, "tokenFile").trimAscii()
                if (!accountTokenFile.isEmpty()) {
                    return this.readTelegramTokenFile(accountTokenFile, source: "tokenFile")
                }
                let accountToken = this.readStringField(account, "botToken").trimAscii()
                if (!accountToken.isEmpty()) {
                    return TelegramTokenResolution(token: accountToken, source: "config")
                }
            case None => ()
        }
        let tokenFile = this.config.tokenFile.trimAscii()
        if (!tokenFile.isEmpty()) {
            return this.readTelegramTokenFile(tokenFile, source: "tokenFile")
        }
        let inline = this.config.botToken.trimAscii()
        if (!inline.isEmpty()) {
            return TelegramTokenResolution(token: inline, source: "config")
        }
        TelegramTokenResolution(source: "none")
    }

    private func resolveTelegramAccountConfig(accountId: String): Option<JsonObject> {
        match (this.config.accounts) {
            case Some(accounts) =>
                match (accounts.get(accountId)) {
                    case Some(v) => try { Some(v.asObject()) } catch (_: Exception) { None }
                    case None =>
                        if (accountId == TELEGRAM_DEFAULT_ACCOUNT_ID) {
                            match (accounts.get("telegram:default")) {
                                case Some(v) => try { Some(v.asObject()) } catch (_: Exception) { None }
                                case None => None
                            }
                        } else {
                            None
                        }
                }
            case None => None
        }
    }

    private func readTelegramTokenFile(pathText: String, source!: String): TelegramTokenResolution {
        let path = Path(pathText.trimAscii())
        if (!exists(path)) {
            return TelegramTokenResolution(source: "none", tokenFile: pathText.trimAscii(), error: "tokenFile not found")
        }
        try {
            let token = String.fromUtf8(File.readFrom(path)).trimAscii()
            if (token.isEmpty()) {
                return TelegramTokenResolution(source: "none", tokenFile: pathText.trimAscii(), error: "tokenFile is empty")
            }
            TelegramTokenResolution(token: token, source: source, tokenFile: pathText.trimAscii())
        } catch (e: Exception) {
            TelegramTokenResolution(source: "none", tokenFile: pathText.trimAscii(), error: "tokenFile unreadable: ${e.message}")
        }
    }

    private func buildTelegramAccountDiagnostics(): JsonObject {
        let resolved = this.resolveTelegramToken()
        let out = JsonObject()
        out.put("accountId", JsonString(this.effectiveAccountId()))
        out.put("tokenSource", JsonString(resolved.source))
        out.put("tokenConfigured", (!resolved.token.trimAscii().isEmpty()).toJsonValue())
        out.put("tokenRedacted", JsonString(this.redactTelegramToken(resolved.token)))
        out.put("tokenFile", JsonString(resolved.tokenFile))
        out.put("tokenError", JsonString(resolved.error))
        out.put("botId", JsonString(this.extractBotIdFromToken(resolved.token)))
        out
    }

    private func redactTelegramToken(token: String): String {
        let trimmed = token.trimAscii()
        if (trimmed.isEmpty()) {
            return ""
        }
        let botId = this.extractBotIdFromToken(trimmed)
        if (!botId.isEmpty()) {
            return "${botId}:<redacted>"
        }
        "<redacted>"
    }

    private func effectiveBotId(): String {
        this.extractBotIdFromToken(this.effectiveBotToken())
    }

    private func extractBotIdFromToken(token: String): String {
        let trimmed = token.trimAscii()
        match (trimmed.indexOf(":")) {
            case Some(idx) =>
                if (idx <= 0) {
                    return ""
                }
                let botId = trimmed[..idx]
                for (r in botId.runes()) {
                    if (r < r'0' || r > r'9') {
                        return ""
                    }
                }
                botId
            case None => ""
        }
    }

    public func debugTelegramAccountDiagnosticsForTest(): JsonObject {
        this.buildTelegramAccountDiagnostics()
    }

    private func startWebhookServer(): Unit {
        let server = ServerBuilder()
            .addr(this.config.webhookHost)
            .port(this.config.webhookPort)
            .build()
        server.distributor.register(this.config.webhookPath, { ctx =>
            let source = this.resolveWebhookSource(
                ctx.request.headers.getFirst("X-Forwarded-For") ?? ctx.request.headers.getFirst("x-forwarded-for") ?? "",
                ctx.request.headers.getFirst("X-Real-IP") ?? ctx.request.headers.getFirst("x-real-ip") ?? "",
                ""
            )
            let guard = this.buildWebhookGuardResult(ctx.request.method, this.config.webhookPath, 0, source)
            if (!this.readJsonBoolField(guard, "ok", false)) {
                let httpStatus = this.readJsonIntField(guard, "httpStatus", 400)
                if (httpStatus == 405) {
                    ctx.responseBuilder.status(405)
                } else if (httpStatus == 404) {
                    ctx.responseBuilder.status(404)
                } else if (httpStatus == 429) {
                    ctx.responseBuilder.status(429)
                } else if (httpStatus == 413) {
                    ctx.responseBuilder.status(413)
                } else {
                    ctx.responseBuilder.status(400)
                }
                ctx.responseBuilder.body(guard.toJsonString())
                return
            }
            let secret = ctx.request.headers.getFirst("X-Telegram-Bot-Api-Secret-Token") ??
                ctx.request.headers.getFirst("x-telegram-bot-api-secret-token") ??
                ""
            if (!this.validateWebhookSecretHeader(secret)) {
                ctx.responseBuilder.status(403)
                ctx.responseBuilder.body("{\"ok\":false,\"error\":\"webhook_secret_mismatch\"}")
                return
            }
            let body = this.readRequestBodyLimited(ctx)
            if (!body.ok) {
                ctx.responseBuilder.status(if (body.error == "payload-too-large") { 413 } else { 408 })
                let err = JsonObject()
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("error", JsonString(body.error))
                ctx.responseBuilder.body(err.toJsonString())
                return
            }
            let payload = body.payload
            let ack = this.ingestWebhookPayload(payload)
            ctx.responseBuilder.body(ack)
        })
        server.distributor.register("/healthz", { ctx =>
            ctx.responseBuilder.body("ok")
        })
        this.webhookServer = Some(server)
        spawn {
            try {
                server.serve()
            } catch (_e: Exception) {
                ()
            }
        }
    }

    private func startPollingLoop(): Unit {
        this.pollingRunnerOrThrow().start()
    }

    private func registerWebhookWithTelegram(): Bool {
        let token = this.effectiveBotToken()
        this.webhookRegistrationAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        if (token.isEmpty()) {
            this.webhookRegistrationStatus = "error"
            this.webhookRegistrationError = "bot token is empty"
            return false
        }
        let responseOpt = this.sendWebhookRegistrationRequest(token)
        let raw = match (responseOpt) {
            case Some(v) => v
            case None =>
                this.webhookRegistrationStatus = "error"
                this.webhookRegistrationError = this.lastSendError
                LogUtils.info("Telegram setWebhook failed: ${this.webhookRegistrationError}")
                return false
        }
        if (this.parseTelegramBoolSuccess(raw, missingDetail: "telegram setWebhook returned ok=false")) {
            this.webhookRegistrationStatus = "ok"
            this.webhookRegistrationError = ""
            return true
        }
        this.webhookRegistrationStatus = "error"
        this.webhookRegistrationError = this.lastSendError
        LogUtils.info("Telegram setWebhook failed: ${this.webhookRegistrationError}")
        false
    }

    private func sendWebhookRegistrationRequest(token: String): Option<String> {
        let url = this.normalizeApiRoot() + "/bot${token}/setWebhook"
        let certPath = this.config.webhookCertPath.trimAscii()
        if (certPath.isEmpty()) {
            return this.telegramJsonPost(url, this.buildWebhookRegistrationPayload(), context: "setWebhook")
        }
        let path = Path(certPath)
        if (!exists(path)) {
            this.setLastSendError("telegram webhook certificate path does not exist")
            return None<String>
        }
        let isRegular = try { FileInfo(path).isRegular() } catch (_e: Exception) { false }
        if (!isRegular) {
            this.setLastSendError("telegram webhook certificate path is not a regular file")
            return None<String>
        }
        let fields = HashMap<String, String>()
        fields["url"] = this.config.webhookUrl.trimAscii()
        if (!this.config.webhookSecret.trimAscii().isEmpty()) {
            fields["secret_token"] = this.config.webhookSecret.trimAscii()
        }
        fields["allowed_updates"] = this.buildAllowedUpdates().toJsonString()
        this.telegramMultipartFilesPost(
            url,
            fields,
            [TelegramMultipartFile("certificate", filePath: certPath)],
            context: "setWebhook"
        )
    }

    private func ensurePollingWebhookCleared(reason: String): Bool {
        if (this.pollingWebhookCleared) {
            return true
        }
        let token = this.effectiveBotToken()
        this.webhookCleanupAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        if (token.isEmpty()) {
            this.webhookCleanupStatus = "error"
            this.webhookCleanupError = "bot token is empty"
            return false
        }
        let responseOpt = this.telegramJsonPost(
            this.normalizeApiRoot() + "/bot${token}/deleteWebhook",
            this.buildWebhookDeletePayload(dropPendingUpdates: false),
            context: "deleteWebhook:${reason}"
        )
        let raw = match (responseOpt) {
            case Some(v) => v
            case None =>
                this.webhookCleanupStatus = "error"
                this.webhookCleanupError = this.lastSendError
                LogUtils.info("Telegram deleteWebhook failed: ${this.webhookCleanupError}")
                return false
        }
        if (this.parseTelegramBoolSuccess(raw, missingDetail: "telegram deleteWebhook returned ok=false")) {
            this.webhookCleanupStatus = "ok"
            this.webhookCleanupError = ""
            this.pollingWebhookCleared = true
            return true
        }
        this.webhookCleanupStatus = "error"
        this.webhookCleanupError = this.lastSendError
        LogUtils.info("Telegram deleteWebhook failed: ${this.webhookCleanupError}")
        false
    }

    private func startNativeCommandSyncIfNeeded(): Unit {
        if (!this.registerNativeCommandsOnStart) {
            return
        }
        spawn {
            this.syncNativeCommands()
        }
    }

    private func runPollingLoop(): Unit {
        this.pollingRunnerOrThrow().start()
    }

    private func runPollingIteration(): Int64 {
        this.pollingRunnerOrThrow().runIteration()
    }

    private func pollingRunnerOrThrow(): TelegramPollingRunner {
        match (this.pollingRunner) {
            case Some(runner) => runner
            case None => throw Exception("telegram polling runner is not initialized")
        }
    }

    private func markTelegramTransportDirtyForPollingWatchdog(): Unit {
        this.telegramTransportRebuildCount += 1
        LogUtils.info("Telegram polling watchdog marked transport dirty; future requests will use a fresh native transport")
    }

    private func markPollingIdle(): Unit {
        this.pollingRunnerOrThrow().markIdle()
    }

    private func markPollingStopped(): Unit {
        this.pollingRunnerOrThrow().stop()
    }

    private func markPollSuccess(outcome!: String = "success"): Unit {
        this.pollingRunnerOrThrow().recordSuccess(outcome: outcome)
    }

    private func recordPollError(error: String, outcome!: String = "error"): Unit {
        this.pollingRunnerOrThrow().recordError(error, outcome: outcome)
    }

    private func pollErrorRecordedForCurrentIteration(): Bool {
        this.pollingRunnerOrThrow().errorRecordedForCurrentIteration()
    }

    private func currentPollBackoffMs(): Int64 {
        this.pollingRunnerOrThrow().currentBackoffMs()
    }

    private func buildPollingDiagnosticSnapshot(): JsonObject {
        this.pollingRunnerOrThrow().diagnostics()
    }

    private func readRequestBodyLimited(ctx: HttpContext): TelegramWebhookBodyReadResult {
        try {
            let output = ArrayList<Byte>()
            let buffer = Array<Byte>(8192, repeat: 0)
            let limit = this.effectiveWebhookMaxBodyBytes()
            let startedAt = DateTime.now().toUnixTimeStamp().toMilliseconds()
            let timeoutMs = this.effectiveWebhookBodyTimeoutMs()
            while (true) {
                if (timeoutMs > 0 && DateTime.now().toUnixTimeStamp().toMilliseconds() - startedAt > timeoutMs) {
                    return TelegramWebhookBodyReadResult(false, error: "timeout")
                }
                let n = ctx.request.body.read(buffer)
                if (n <= 0) {
                    break
                }
                if (limit > 0 && Int64(output.size) + Int64(n) > limit) {
                    return TelegramWebhookBodyReadResult(false, error: "payload-too-large")
                }
                output.add(all: buffer[..n])
            }
            TelegramWebhookBodyReadResult(true, payload: String.fromUtf8(output.toArray()))
        } catch (_e: Exception) {
            TelegramWebhookBodyReadResult(false, error: "read-failed")
        }
    }

    private func effectiveWebhookMaxBodyBytes(): Int64 {
        if (this.config.webhookMaxBodyBytes <= 0) { 1024 * 1024 } else { this.config.webhookMaxBodyBytes }
    }

    private func effectiveWebhookBodyTimeoutMs(): Int64 {
        if (this.config.webhookBodyTimeoutMs < 0) { 0 } else { this.config.webhookBodyTimeoutMs }
    }

    private func effectiveWebhookRateLimitWindowMs(): Int64 {
        if (this.config.webhookRateLimitWindowMs <= 0) { 60000 } else { this.config.webhookRateLimitWindowMs }
    }

    private func effectiveWebhookRateLimitMaxRequests(): Int64 {
        if (this.config.webhookRateLimitMaxRequests <= 0) { 120 } else { this.config.webhookRateLimitMaxRequests }
    }

    private func splitFirstCsvValue(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) {
            return ""
        }
        let parts = trimmed.split(",")
        if (parts.isEmpty()) {
            return trimmed
        }
        parts[0].trimAscii()
    }

    private func trustedProxyContains(candidate: String): Bool {
        let value = candidate.trimAscii()
        if (value.isEmpty()) {
            return false
        }
        for (proxy in this.config.trustedProxies) {
            if (proxy.trimAscii() == value) {
                return true
            }
        }
        false
    }

    private func resolveWebhookSource(xForwardedFor: String, xRealIp: String, remoteHint: String): String {
        let forwarded = this.splitFirstCsvValue(xForwardedFor)
        let real = xRealIp.trimAscii()
        let remote = remoteHint.trimAscii()
        if (!forwarded.isEmpty() && (remote.isEmpty() || this.trustedProxyContains(remote) || this.config.trustedProxies.isEmpty())) {
            return forwarded
        }
        if (!real.isEmpty() && (this.config.allowRealIpFallback || remote.isEmpty() || this.trustedProxyContains(remote))) {
            return real
        }
        if (!remote.isEmpty()) {
            return remote
        }
        "unknown"
    }

    private func webhookRateLimitAllows(source: String, nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()): Bool {
        let key = if (source.trimAscii().isEmpty()) { "unknown" } else { source.trimAscii() }
        let windowMs = this.effectiveWebhookRateLimitWindowMs()
        let maxRequests = this.effectiveWebhookRateLimitMaxRequests()
        synchronized(this.webhookGuardMutex) {
            let startedAt = this.webhookRateWindowStartedAtBySource.get(key) ?? 0
            let count = this.webhookRateCountBySource.get(key) ?? 0
            if (startedAt <= 0 || nowMs - startedAt >= windowMs) {
                this.webhookRateWindowStartedAtBySource[key] = nowMs
                this.webhookRateCountBySource[key] = 1
                return true
            }
            if (count >= maxRequests) {
                return false
            }
            this.webhookRateCountBySource[key] = count + 1
            true
        }
    }

    private func buildWebhookGuardResult(
        method: String,
        path: String,
        bodyBytes: Int64,
        source: String,
        nowMs!: Int64 = DateTime.now().toUnixTimeStamp().toMilliseconds()
    ): JsonObject {
        let out = JsonObject()
        let normalizedMethod = method.trimAscii().toAsciiUpper()
        if (normalizedMethod != "POST") {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("error"))
            out.put("error", JsonString("method-not-allowed"))
            out.put("httpStatus", 405.toJsonValue())
            return out
        }
        if (!path.trimAscii().isEmpty() && path.trimAscii() != this.config.webhookPath.trimAscii()) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("error"))
            out.put("error", JsonString("path-not-found"))
            out.put("httpStatus", 404.toJsonValue())
            return out
        }
        if (bodyBytes > 0 && bodyBytes > this.effectiveWebhookMaxBodyBytes()) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("error"))
            out.put("error", JsonString("payload-too-large"))
            out.put("httpStatus", 413.toJsonValue())
            return out
        }
        if (!this.webhookRateLimitAllows(source, nowMs: nowMs)) {
            out.put("ok", JsonBool(false))
            out.put("status", JsonString("error"))
            out.put("error", JsonString("rate-limited"))
            out.put("httpStatus", 429.toJsonValue())
            return out
        }
        out.put("ok", JsonBool(true))
        out.put("status", JsonString("ok"))
        out.put("source", JsonString(if (source.trimAscii().isEmpty()) { "unknown" } else { source.trimAscii() }))
        out.put("httpStatus", 200.toJsonValue())
        out
    }

    private func mapWebhookToInbound(root: JsonObject, raw: String): Option<InboundMessage> {
        match (this.mapReactionWebhookToInbound(root, raw)) {
            case Some(inbound) => return Some(inbound)
            case None => ()
        }
        if (root.get("callback_query").isSome()) {
            return this.mapCallbackQueryWebhookToInbound(root, raw)
        }
        let message = this.pickPrimaryUpdateObject(root)
        if (message.isNone()) {
            this.recordInboundDecision(this.readIntStringField(root, "update_id"), this.primaryUpdateKind(root), "ignored", "unsupported_update_kind")
            return None
        }
        let msg = message.getOrThrow()
        let messageId = this.readIntStringField(msg, "message_id")
        if (this.recordTelegramGroupMigrationIfNeeded(root, msg, messageId)) {
            this.recordInboundDecision(
                this.readIntStringField(root, "update_id"),
                this.primaryUpdateKind(root),
                "ignored",
                "group_migration_recorded",
                messageId: messageId
            )
            return None
        }
        let mediaInfo = this.readTelegramMediaInfo(msg)
        var text = this.normalizeInboundTelegramCommandText(this.readInboundTelegramText(msg, mediaInfo: mediaInfo))
        if (messageId.isEmpty() || text.isEmpty()) {
            this.recordInboundDecision(
                this.readIntStringField(root, "update_id"),
                this.primaryUpdateKind(root),
                "ignored",
                "unsupported_or_empty_message",
                messageId: messageId
            )
            return None
        }
        let chat = this.readObjectField(msg, "chat")
        let from = this.readObjectField(msg, "from")
        let threadIdRaw = this.readIntStringField(msg, "message_thread_id")
        let peerId = this.telegramPeerId(chat, threadId: threadIdRaw)
        let senderId = this.readIntStringField(from, "id")
        let chatType = if (this.readStringField(chat, "type") == "private") { ChatType.Direct } else { ChatType.Group }
        let mediaContext = JsonObject()
        mediaContext.put("channel", JsonString("telegram"))
        mediaContext.put("accountId", JsonString(this.effectiveAccountId()))
        mediaContext.put("peerId", JsonString(peerId))
        mediaContext.put("messageId", JsonString(messageId))
        mediaContext.put("mediaStatePath", JsonString(this.mediaStatePath().toString()))
        let contextRecords = JsonArray([])
        let persistedMediaStates = ArrayList<JsonObject>()
        match (mediaInfo) {
            case Some(info) =>
                let mediaState = this.persistInboundMedia(info, peerId: peerId, messageId: messageId, relation: "current")
                let record = this.readObjectField(mediaState, "lastMedia")
                contextRecords.add(record)
                persistedMediaStates.add(mediaState)
                text = this.appendTelegramMediaContextBlock(text, info, mediaState, peerId, messageId)
            case None => ()
        }
        let replyTarget: Option<String> = match (this.readObjectFieldOpt(msg, "reply_to_message")) {
            case Some(reply) =>
                let replyId = this.readIntStringField(reply, "message_id")
                match (this.readTelegramMediaInfo(reply)) {
                    case Some(replyInfo) =>
                        let replyMediaState = this.persistInboundMedia(
                            replyInfo,
                            peerId: peerId,
                            messageId: replyId,
                            relation: "replyTarget",
                            replyToMessageId: replyId
                        )
                        contextRecords.add(this.readObjectField(replyMediaState, "lastMedia"))
                        persistedMediaStates.add(replyMediaState)
                    case None => ()
                }
                if (replyId.isEmpty()) { None<String> } else { Some(replyId) }
            case None => None<String>
        }
        match (this.readObjectFieldOpt(msg, "external_reply")) {
            case Some(externalReply) =>
                let externalId = this.readIntStringField(externalReply, "message_id")
                match (this.readTelegramMediaInfo(externalReply)) {
                    case Some(externalInfo) =>
                        let externalMediaState = this.persistInboundMedia(
                            externalInfo,
                            peerId: peerId,
                            messageId: if (externalId.isEmpty()) { messageId } else { externalId },
                            relation: "externalReply",
                            replyToMessageId: externalId
                        )
                        contextRecords.add(this.readObjectField(externalMediaState, "lastMedia"))
                        persistedMediaStates.add(externalMediaState)
                    case None => ()
                }
            case None => ()
        }
        if (contextRecords.size() > 0) {
            mediaContext.put("channel", JsonString("telegram"))
            mediaContext.put("accountId", JsonString(this.effectiveAccountId()))
            mediaContext.put("peerId", JsonString(peerId))
            mediaContext.put("messageId", JsonString(messageId))
            mediaContext.put("records", contextRecords)
        }
        let structuredContext = this.telegramStructuredSupplementalContext(msg)
        if (structuredContext.size() > 0) {
            mediaContext.put("channel", JsonString("telegram"))
            mediaContext.put("accountId", JsonString(this.effectiveAccountId()))
            mediaContext.put("peerId", JsonString(peerId))
            mediaContext.put("messageId", JsonString(messageId))
            mediaContext.put("context", structuredContext)
        }
        if (this.readStringField(chat, "type") == "supergroup" && this.readBoolFieldOpt(chat, "is_forum").isNone()) {
            let chatInfo = this.tryTelegramGetChat(this.readIntStringField(chat, "id"))
            if (this.readJsonBoolField(chatInfo, "ok", false)) {
                mediaContext.put("channel", JsonString("telegram"))
                mediaContext.put("accountId", JsonString(this.effectiveAccountId()))
                mediaContext.put("peerId", JsonString(peerId))
                mediaContext.put("messageId", JsonString(messageId))
                let context = match (mediaContext.get("context")) {
                    case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
                    case None => JsonObject()
                }
                let forum = JsonObject()
                forum.put("source", JsonString("getChat"))
                forum.put("chatId", chatInfo.get("chatId") ?? JsonString(""))
                forum.put("isForum", chatInfo.get("isForum") ?? false.toJsonValue())
                context.put("forum", forum)
                mediaContext.put("context", context)
            }
        }
        this.attachTelegramRouteConfigContext(mediaContext, peerId, senderId, chatType)
        let mentioned = this.detectMentionInMessage(msg, text)
        match (chatType) {
            case ChatType.Group =>
                if (mentioned) {
                    this.attachTelegramGroupHistoryContext(mediaContext, peerId, messageId)
                }
            case ChatType.Direct => ()
        }
        let inbound = InboundMessage(
            ChannelType.Telegram,
            messageId,
            peerId,
            senderId,
            chatType,
            text,
            mentioned,
            DateTime.now(),
            conversationId: Some(peerId),
            threadId: if (threadIdRaw.isEmpty()) { None } else { Some(threadIdRaw) },
            replyTargetMessageId: replyTarget,
            replyInThread: !threadIdRaw.isEmpty(),
            raw: Some(raw),
            accountId: this.effectiveAccountId(),
            mediaContext: mediaContext
        )
        let rejectReason = this.inboundRejectReason(inbound)
        if (!rejectReason.isEmpty()) {
            this.maybeRecordTelegramGroupHistory(inbound, rejectReason)
            this.recordInboundDecision(
                this.readIntStringField(root, "update_id"),
                this.primaryUpdateKind(root),
                "ignored",
                rejectReason,
                peerId: inbound.peerId,
                senderId: inbound.senderId,
                messageId: inbound.messageId
            )
            return None
        }
        for (mediaState in persistedMediaStates) {
            this.maybeWarnInboundMediaDownloadFailure(peerId, messageId, mediaState)
        }
        Some(inbound)
    }

    private func fetchTelegramUpdates(): String {
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            return ""
        }
        this.ensurePollingWebhookCleared("before-getUpdates")
        let payload = JsonObject()
        let lastInbound = this.readLastInboundUpdateId()
        if (!lastInbound.isEmpty()) {
            try {
                payload.put("offset", (Int64.parse(lastInbound) + 1).toJsonValue())
            } catch (_: Exception) {
                ()
            }
        }
        let timeoutSeconds = if (this.config.timeoutSeconds > 0) { this.config.timeoutSeconds } else { 30 }
        payload.put("timeout", timeoutSeconds.toJsonValue())
        payload.put("allowed_updates", this.buildAllowedUpdates())
        match (this.telegramJsonPost(
            this.normalizeApiRoot() + "/bot${token}/getUpdates",
            payload,
            context: "getUpdates"
        )) {
            case Some(raw) =>
                if (raw.trimAscii().isEmpty()) {
                    this.recordPollError("getUpdates returned empty response", outcome: "empty-response")
                    LogUtils.info("Telegram getUpdates failed: getUpdates returned empty response")
                }
                raw
            case None =>
                if (!this.pollErrorRecordedForCurrentIteration()) {
                    this.recordPollError("getUpdates returned no response", outcome: "no-response")
                    LogUtils.info("Telegram getUpdates failed: getUpdates returned no response")
                }
                ""
        }
    }

    private func ingestPollingResponse(raw: String): Int64 {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) {
            return 0
        }
        return try {
            let root = JsonValue.fromStr(trimmed).asObject()
            if (!this.readJsonBoolField(root, "ok", false)) {
                let desc = this.readStringField(root, "description").trimAscii()
                let detail = if (desc.isEmpty()) {
                    "getUpdates returned ok=false"
                } else {
                    "getUpdates returned ok=false: ${desc}"
                }
                let outcome = if (this.isTelegramConflictError(root, desc)) { "conflict" } else { "api-error" }
                this.recordPollError(detail, outcome: outcome)
                let retryAfter = this.telegramRetryAfterSeconds(trimmed)
                if (retryAfter > 0) {
                    this.lastRetryAfterSeconds = retryAfter
                    this.recordPollError("${detail}; retry_after=${retryAfter}", outcome: "rate-limit")
                }
                if (outcome == "conflict") {
                    this.pollingWebhookCleared = false
                    this.ensurePollingWebhookCleared("conflict-recovery")
                }
                LogUtils.info("Telegram getUpdates failed: ${detail}")
                return 0
            }
            match (root.get("result")) {
                case Some(v) =>
                    try {
                        let arr = v.asArray()
                        var accepted: Int64 = 0
                        for (item in arr.getItems()) {
                            try {
                                let update = item.asObject()
                                let ack = this.ingestTelegramUpdatePayload(update.toJsonString(), dedupeByOffset: true)
                                if (ack.contains("\"ok\":true") && !ack.contains("\"ignored\":true")) {
                                    accepted += 1
                                }
                            } catch (_: Exception) {
                                ()
                            }
                        }
                        if (accepted > 0) {
                            LogUtils.info("Telegram getUpdates accepted ${accepted} inbound update(s)")
                        }
                        this.markPollSuccess(outcome: if (accepted > 0) { "success" } else { "empty-result" })
                        accepted
                    } catch (_: Exception) {
                        this.recordPollError("getUpdates result parse failed", outcome: "parse-error")
                        0
                    }
                case None =>
                    this.recordPollError("getUpdates missing result", outcome: "parse-error")
                    0
            }
        } catch (e: Exception) {
            let detail = "getUpdates parse failed: ${e.message}"
            this.recordPollError(detail, outcome: "parse-error")
            LogUtils.info("Telegram getUpdates failed: ${detail}")
            0
        }
    }

    private func confirmPollingOffsetOnStop(): Bool {
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            return false
        }
        let lastInbound = this.readLastInboundUpdateId()
        if (lastInbound.isEmpty()) {
            return false
        }
        let nextOffset = try { Int64.parse(lastInbound) + 1 } catch (_: Exception) { return false }
        let payload = JsonObject()
        payload.put("offset", nextOffset.toJsonValue())
        payload.put("limit", 1.toJsonValue())
        let responseOpt = this.telegramJsonPost(
            this.normalizeApiRoot() + "/bot${token}/getUpdates",
            payload,
            context: "getUpdates:stop-confirm"
        )
        match (responseOpt) {
            case Some(raw) =>
                if (this.parseTelegramBoolSuccess(raw, missingDetail: "telegram stop offset confirmation returned ok=false")) {
                    this.lastConfirmedPollingOffset = "${nextOffset}"
                    return true
                }
                false
            case None => false
        }
    }

    private func telegramRetryAfterSeconds(raw: String): Int64 {
        try {
            let root = JsonValue.fromStr(raw).asObject()
            let params = this.readObjectField(root, "parameters")
            match (params.get("retry_after")) {
                case Some(v) =>
                    try { return v.asInt().getValue() } catch (_e: Exception) {
                        try { return Int64.parse(v.asString().getValue().trimAscii()) } catch (_e2: Exception) { return 0 }
                    }
                case None => return 0
            }
        } catch (_e: Exception) {
            return 0
        }
    }

    private func readInboundTelegramText(
        msg: JsonObject,
        mediaInfo!: Option<TelegramInboundMediaInfo> = None<TelegramInboundMediaInfo>
    ): String {
        let text = this.readStringField(msg, "text").trimAscii()
        if (!text.isEmpty()) {
            return this.appendTelegramSupplementalContext(this.telegramTextWithEntities(msg, text, "entities"), msg)
        }
        match (mediaInfo) {
            case Some(info) =>
                let lines = ArrayList<String>()
                lines.add("[${info.kind}]")
                lines.add("fileId=${info.fileId}")
                if (!info.fileUniqueId.isEmpty()) {
                    lines.add("fileUniqueId=${info.fileUniqueId}")
                }
                if (!info.mimeType.isEmpty()) {
                    lines.add("mimeType=${info.mimeType}")
                }
                if (info.fileSize > 0) {
                    lines.add("fileSize=${info.fileSize}")
                }
                if (!info.fileName.isEmpty()) {
                    lines.add("fileName=${info.fileName}")
                }
                if (!info.mediaGroupId.isEmpty()) {
                    lines.add("mediaGroupId=${info.mediaGroupId}")
                    lines.add("albumPolicy=${this.effectiveMediaAlbumPolicy()}")
                }
                if (!info.caption.isEmpty() && info.kind != "sticker" && info.kind != "video-note") {
                    lines.add("caption=${info.caption}")
                    let captionEntities = this.telegramEntityContextBlock(info.caption, msg, "caption_entities")
                    if (!captionEntities.isEmpty()) {
                        lines.add(captionEntities)
                    }
                }
                if (info.kind == "sticker") {
                    if (!info.stickerEmoji.isEmpty()) {
                        lines.add("stickerEmoji=${info.stickerEmoji}")
                    }
                    if (!info.stickerSetName.isEmpty()) {
                        lines.add("stickerSetName=${info.stickerSetName}")
                    }
                    lines.add("stickerAnimated=${info.stickerIsAnimated}")
                    lines.add("stickerVideo=${info.stickerIsVideo}")
                }
                return this.appendTelegramSupplementalContext(String.join(lines.toArray(), delimiter: "\n"), msg)
            case None =>
                let supplemental = this.telegramSupplementalContextText(msg)
                if (!supplemental.isEmpty()) {
                    return supplemental
                }
                ""
        }
    }

    private func telegramTextWithEntities(msg: JsonObject, text: String, entityField: String): String {
        let entities = this.telegramEntityContextBlock(text, msg, entityField)
        if (entities.isEmpty()) {
            return text
        }
        text + "\n" + entities
    }

    private func telegramEntityContextBlock(text: String, msg: JsonObject, entityField: String): String {
        let lines = ArrayList<String>()
        match (msg.get(entityField)) {
            case Some(rawEntities) =>
                try {
                    let arr = rawEntities.asArray()
                    for (item in arr.getItems()) {
                        try {
                            let entity = item.asObject()
                            let entityType = this.readStringField(entity, "type").trimAscii()
                            let offset = this.readJsonIntField(entity, "offset", -1)
                            let length = this.readJsonIntField(entity, "length", 0)
                            let segment = this.telegramEntitySlice(text, offset, length)
                            if (entityType == "text_link") {
                                let url = this.readStringField(entity, "url").trimAscii()
                                if (!url.isEmpty()) {
                                    if (lines.isEmpty()) {
                                        lines.add("[entities]")
                                    }
                                    lines.add("textLink=${segment}|url=${url}")
                                }
                            } else if (entityType == "url" || entityType == "mention" || entityType == "text_mention") {
                                if (lines.isEmpty()) {
                                    lines.add("[entities]")
                                }
                                lines.add("${entityType}=${segment}")
                            }
                        } catch (_e: Exception) {
                            ()
                        }
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func telegramEntitySlice(text: String, offset: Int64, length: Int64): String {
        if (offset < 0 || length <= 0 || offset >= text.size) {
            return ""
        }
        let end = if (offset + length > text.size) { text.size } else { offset + length }
        try { text[offset..end] } catch (_e: Exception) { "" }
    }

    private func appendTelegramSupplementalContext(baseText: String, msg: JsonObject): String {
        let supplemental = this.telegramSupplementalContextText(msg)
        if (supplemental.isEmpty()) {
            return baseText
        }
        baseText + "\n" + supplemental
    }

    private func telegramSupplementalContextText(msg: JsonObject): String {
        let lines = ArrayList<String>()
        let messageQuote = this.telegramQuoteText(msg)
        if (!messageQuote.isEmpty()) {
            lines.add("[quote-context]")
            lines.add("kind=quote")
            lines.add("text=${messageQuote}")
        }
        match (this.readObjectFieldOpt(msg, "reply_to_message")) {
            case Some(reply) =>
                let replyText = this.readStringField(reply, "text").trimAscii()
                let replyCaption = this.readStringField(reply, "caption").trimAscii()
                let replyBody = if (!replyText.isEmpty()) { replyText } else { replyCaption }
                if (!replyBody.isEmpty()) {
                    lines.add("[reply-context]")
                    lines.add("messageId=${this.readIntStringField(reply, "message_id")}")
                    lines.add("body=${replyBody}")
                }
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "external_reply")) {
            case Some(externalReply) =>
                let extText = this.readStringField(externalReply, "text").trimAscii()
                let extCaption = this.readStringField(externalReply, "caption").trimAscii()
                let extBody = if (!extText.isEmpty()) { extText } else { extCaption }
                let extQuote = this.telegramQuoteText(externalReply)
                lines.add("[external-reply-context]")
                lines.add("messageId=${this.readIntStringField(externalReply, "message_id")}")
                if (!extQuote.isEmpty()) {
                    lines.add("quote=${extQuote}")
                }
                if (!extBody.isEmpty()) {
                    lines.add("body=${extBody}")
                }
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "forward_origin")) {
            case Some(origin) =>
                lines.add("[forward-context]")
                lines.add("type=${this.readStringField(origin, "type")}")
                let senderName = this.readStringField(origin, "sender_user_name")
                if (!senderName.isEmpty()) {
                    lines.add("sender=${senderName}")
                }
                let chat = this.readObjectField(origin, "chat")
                let title = this.readStringField(chat, "title")
                if (!title.isEmpty()) {
                    lines.add("chatTitle=${title}")
                }
                let senderChat = this.readObjectField(origin, "sender_chat")
                let senderChatTitle = this.readStringField(senderChat, "title").trimAscii()
                if (!senderChatTitle.isEmpty()) {
                    lines.add("senderChatTitle=${senderChatTitle}")
                }
                let originMessageId = this.readIntStringField(origin, "message_id")
                if (!originMessageId.isEmpty()) {
                    lines.add("originMessageId=${originMessageId}")
                }
                let authorSignature = this.readStringField(origin, "author_signature").trimAscii()
                if (!authorSignature.isEmpty()) {
                    lines.add("authorSignature=${authorSignature}")
                }
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "location")) {
            case Some(location) =>
                lines.add("[location]")
                lines.add("latitude=${this.readFloatStringField(location, "latitude")}")
                lines.add("longitude=${this.readFloatStringField(location, "longitude")}")
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "venue")) {
            case Some(venue) =>
                lines.add("[venue]")
                lines.add("title=${this.readStringField(venue, "title")}")
                lines.add("address=${this.readStringField(venue, "address")}")
                let location = this.readObjectField(venue, "location")
                lines.add("latitude=${this.readFloatStringField(location, "latitude")}")
                lines.add("longitude=${this.readFloatStringField(location, "longitude")}")
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "contact")) {
            case Some(contact) =>
                lines.add("[contact]")
                lines.add("firstName=${this.readStringField(contact, "first_name")}")
                lines.add("lastName=${this.readStringField(contact, "last_name")}")
                lines.add("phoneNumber=${this.readStringField(contact, "phone_number")}")
            case None => ()
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func telegramQuoteText(msg: JsonObject): String {
        match (this.readObjectFieldOpt(msg, "quote")) {
            case Some(quoteObj) => this.readStringField(quoteObj, "text").trimAscii()
            case None => ""
        }
    }

    private func telegramStructuredSupplementalContext(msg: JsonObject): JsonObject {
        let out = JsonObject()
        let messageQuote = this.telegramQuoteText(msg)
        if (!messageQuote.isEmpty()) {
            let obj = JsonObject()
            obj.put("kind", JsonString("quote"))
            obj.put("text", JsonString(messageQuote))
            out.put("quote", obj)
        }
        match (this.readObjectFieldOpt(msg, "reply_to_message")) {
            case Some(reply) =>
                let obj = JsonObject()
                obj.put("messageId", JsonString(this.readIntStringField(reply, "message_id")))
                obj.put("text", JsonString(this.readStringField(reply, "text").trimAscii()))
                obj.put("caption", JsonString(this.readStringField(reply, "caption").trimAscii()))
                let from = this.readObjectField(reply, "from")
                obj.put("senderId", JsonString(this.readIntStringField(from, "id")))
                obj.put("senderUsername", JsonString(this.readStringField(from, "username").trimAscii()))
                out.put("replyTo", obj)
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "external_reply")) {
            case Some(externalReply) =>
                let obj = JsonObject()
                obj.put("messageId", JsonString(this.readIntStringField(externalReply, "message_id")))
                obj.put("text", JsonString(this.readStringField(externalReply, "text").trimAscii()))
                obj.put("caption", JsonString(this.readStringField(externalReply, "caption").trimAscii()))
                obj.put("quoteText", JsonString(this.telegramQuoteText(externalReply)))
                let from = this.readObjectField(externalReply, "from")
                obj.put("senderId", JsonString(this.readIntStringField(from, "id")))
                obj.put("senderUsername", JsonString(this.readStringField(from, "username").trimAscii()))
                out.put("externalReply", obj)
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "forward_origin")) {
            case Some(origin) =>
                let obj = JsonObject()
                obj.put("type", JsonString(this.readStringField(origin, "type").trimAscii()))
                obj.put("senderUserName", JsonString(this.readStringField(origin, "sender_user_name").trimAscii()))
                obj.put("date", JsonString(this.readIntStringField(origin, "date")))
                obj.put("messageId", JsonString(this.readIntStringField(origin, "message_id")))
                obj.put("authorSignature", JsonString(this.readStringField(origin, "author_signature").trimAscii()))
                let senderUser = this.readObjectField(origin, "sender_user")
                if (senderUser.size() > 0) {
                    obj.put("senderId", JsonString(this.readIntStringField(senderUser, "id")))
                    obj.put("senderUsername", JsonString(this.readStringField(senderUser, "username").trimAscii()))
                }
                let chat = this.readObjectField(origin, "chat")
                if (chat.size() > 0) {
                    obj.put("chatId", JsonString(this.readIntStringField(chat, "id")))
                    obj.put("chatTitle", JsonString(this.readStringField(chat, "title").trimAscii()))
                    obj.put("chatType", JsonString(this.readStringField(chat, "type").trimAscii()))
                }
                let senderChat = this.readObjectField(origin, "sender_chat")
                if (senderChat.size() > 0) {
                    obj.put("senderChatId", JsonString(this.readIntStringField(senderChat, "id")))
                    obj.put("senderChatTitle", JsonString(this.readStringField(senderChat, "title").trimAscii()))
                    obj.put("senderChatType", JsonString(this.readStringField(senderChat, "type").trimAscii()))
                    obj.put("senderChatUsername", JsonString(this.readStringField(senderChat, "username").trimAscii()))
                }
                out.put("forwarded", obj)
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "location")) {
            case Some(location) =>
                let obj = JsonObject()
                obj.put("latitude", JsonString(this.readFloatStringField(location, "latitude")))
                obj.put("longitude", JsonString(this.readFloatStringField(location, "longitude")))
                out.put("location", obj)
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "venue")) {
            case Some(venue) =>
                let obj = JsonObject()
                obj.put("title", JsonString(this.readStringField(venue, "title").trimAscii()))
                obj.put("address", JsonString(this.readStringField(venue, "address").trimAscii()))
                let location = this.readObjectField(venue, "location")
                obj.put("latitude", JsonString(this.readFloatStringField(location, "latitude")))
                obj.put("longitude", JsonString(this.readFloatStringField(location, "longitude")))
                out.put("venue", obj)
            case None => ()
        }
        match (this.readObjectFieldOpt(msg, "contact")) {
            case Some(contact) =>
                let obj = JsonObject()
                obj.put("firstName", JsonString(this.readStringField(contact, "first_name").trimAscii()))
                obj.put("lastName", JsonString(this.readStringField(contact, "last_name").trimAscii()))
                obj.put("phoneNumber", JsonString(this.readStringField(contact, "phone_number").trimAscii()))
                obj.put("userId", JsonString(this.readIntStringField(contact, "user_id")))
                out.put("contact", obj)
            case None => ()
        }
        out
    }

    private func appendTelegramMediaContextBlock(
        baseText: String,
        info: TelegramInboundMediaInfo,
        mediaState: JsonObject,
        peerId: String,
        messageId: String
    ): String {
        let lastMedia = this.readObjectField(mediaState, "lastMedia")
        let localPath = this.readStringField(lastMedia, "downloadPath").trimAscii()
        let skippedReason = this.readStringField(lastMedia, "skippedReason").trimAscii()
        let downloaded = this.readBoolFieldOpt(lastMedia, "downloaded") == Some(true)
        let effectiveMime = this.readStringField(lastMedia, "mimeType").trimAscii()
        let effectiveSize = this.readJsonIntField(lastMedia, "fileSize", info.fileSize)
        let safetyStatus = if (downloaded) {
            "downloaded"
        } else if (!skippedReason.isEmpty()) {
            "skipped:${skippedReason}"
        } else {
            "metadata-only"
        }
        let eligibility = if (info.kind == "photo" || (info.kind == "sticker" && !info.stickerIsAnimated && !info.stickerIsVideo)) {
            "vision"
        } else if (info.kind == "voice" || info.kind == "audio") {
            "transcription"
        } else if (info.kind == "document") {
            "file-context"
        } else {
            "metadata-only"
        }
        let lines = ArrayList<String>()
        lines.add(baseText)
        lines.add("[media-context]")
        lines.add("channel=telegram")
        lines.add("accountId=${this.effectiveAccountId()}")
        lines.add("peerId=${peerId}")
        lines.add("messageId=${messageId}")
        lines.add("mediaKind=${info.kind}")
        lines.add("fileId=${info.fileId}")
        if (!localPath.isEmpty()) {
            lines.add("localPath=${localPath}")
        }
        let filePath = this.readStringField(lastMedia, "filePath").trimAscii()
        if (!filePath.isEmpty()) {
            lines.add("telegramFilePath=${filePath}")
        }
        if (!effectiveMime.isEmpty()) {
            lines.add("mimeType=${effectiveMime}")
        }
        if (effectiveSize > 0) {
            lines.add("fileSize=${effectiveSize}")
        }
        if (!info.fileName.trimAscii().isEmpty()) {
            lines.add("fileName=${info.fileName.trimAscii()}")
        }
        if (!info.caption.trimAscii().isEmpty()) {
            lines.add("caption=${info.caption.trimAscii()}")
        }
        if (info.kind == "sticker") {
            if (!info.stickerEmoji.trimAscii().isEmpty()) {
                lines.add("stickerEmoji=${info.stickerEmoji.trimAscii()}")
            }
            if (!info.stickerSetName.trimAscii().isEmpty()) {
                lines.add("stickerSetName=${info.stickerSetName.trimAscii()}")
            }
            lines.add("stickerAnimated=${info.stickerIsAnimated}")
            lines.add("stickerVideo=${info.stickerIsVideo}")
        }
        let transcript = this.readStringField(lastMedia, "transcript").trimAscii()
        if (!transcript.isEmpty()) {
            lines.add("transcript=${transcript}")
        }
        lines.add("safetyStatus=${safetyStatus}")
        lines.add("eligibleFor=${eligibility}")
        lines.add("modelHandling=${this.telegramMediaModelHandling(eligibility, downloaded)}")
        String.join(lines.toArray(), delimiter: "\n")
    }

    private func telegramMediaModelHandling(eligibility: String, downloaded: Bool): String {
        if (eligibility == "vision") {
            if (downloaded) { "vision-input-ready" } else { "vision-metadata-only" }
        } else if (eligibility == "transcription") {
            if (downloaded) { "asr-input-ready" } else { "asr-metadata-only" }
        } else if (eligibility == "file-context") {
            if (downloaded) { "file-context-ready" } else { "file-metadata-only" }
        } else {
            "metadata-only"
        }
    }

    private func readTelegramMediaInfo(msg: JsonObject): Option<TelegramInboundMediaInfo> {
        let caption = this.readStringField(msg, "caption").trimAscii()
        let mediaGroupId = this.readStringField(msg, "media_group_id").trimAscii()
        match (this.readPhotoMediaInfo(msg, caption, mediaGroupId)) {
            case Some(info) => return Some(info)
            case None => ()
        }
        for ((field, kind) in [
            ("document", "document"),
            ("audio", "audio"),
            ("voice", "voice"),
            ("video", "video"),
            ("video_note", "video-note"),
            ("sticker", "sticker")
        ]) {
            match (this.readObjectFieldOpt(msg, field)) {
                case Some(obj) =>
                    let fileId = this.readStringField(obj, "file_id").trimAscii()
                    if (!fileId.isEmpty()) {
                        return Some(this.telegramMediaInfoFromObject(kind, obj, caption: caption, mediaGroupId: mediaGroupId))
                    }
                case None => ()
            }
        }
        None
    }

    private func telegramMediaInfoFromObject(
        kind: String,
        obj: JsonObject,
        caption!: String,
        mediaGroupId!: String
    ): TelegramInboundMediaInfo {
        TelegramInboundMediaInfo(
            kind,
            this.readStringField(obj, "file_id").trimAscii(),
            fileUniqueId: this.readStringField(obj, "file_unique_id").trimAscii(),
            mimeType: this.readStringField(obj, "mime_type").trimAscii().toAsciiLower(),
            fileSize: this.readJsonIntField(obj, "file_size", 0),
            fileName: this.readStringField(obj, "file_name").trimAscii(),
            mediaGroupId: mediaGroupId,
            caption: caption,
            stickerEmoji: this.readStringField(obj, "emoji").trimAscii(),
            stickerSetName: this.readStringField(obj, "set_name").trimAscii(),
            stickerIsAnimated: this.readJsonBoolField(obj, "is_animated", false),
            stickerIsVideo: this.readJsonBoolField(obj, "is_video", false)
        )
    }

    private func readPhotoMediaInfo(msg: JsonObject, caption: String, mediaGroupId: String): Option<TelegramInboundMediaInfo> {
        match (msg.get("photo")) {
            case Some(v) =>
                try {
                    let arr = v.asArray()
                    if (arr.size() <= 0) {
                        return None
                    }
                    var selected: Option<JsonObject> = None
                    var selectedSize: Int64 = -1
                    var i = arr.size() - 1
                    while (i >= 0) {
                        try {
                            let obj = arr[i].asObject()
                            let fileId = this.readStringField(obj, "file_id").trimAscii()
                            if (!fileId.isEmpty()) {
                                let size = this.readJsonIntField(obj, "file_size", 0)
                                if (selected.isNone() || size > selectedSize) {
                                    selected = Some(obj)
                                    selectedSize = size
                                }
                            }
                        } catch (_: Exception) {
                            ()
                        }
                        i -= 1
                    }
                    match (selected) {
                        case Some(obj) =>
                            Some(this.telegramMediaInfoFromObject("photo", obj, caption: caption, mediaGroupId: mediaGroupId))
                        case None => None
                    }
                } catch (_: Exception) {
                    None
                }
            case None => None
        }
    }

    private func mapReactionWebhookToInbound(root: JsonObject, raw: String): Option<InboundMessage> {
        let notifications = this.config.reactionNotifications.trimAscii().toAsciiLower()
        if (notifications == "off" || notifications == "false" || notifications == "disabled") {
            return None
        }
        let reaction = match (this.readObjectFieldOpt(root, "message_reaction")) {
            case Some(v) => v
            case None => return None
        }
        let chat = this.readObjectField(reaction, "chat")
        let messageId = this.readIntStringField(reaction, "message_id")
        let chatId = this.readIntStringField(chat, "id")
        if (messageId.isEmpty() || chatId.isEmpty()) {
            return None
        }
        let sender = this.readObjectField(reaction, "user")
        let senderId = this.readIntStringField(sender, "id")
        if (senderId.isEmpty()) {
            return None
        }
        let chatType = if (this.readStringField(chat, "type") == "private") { ChatType.Direct } else { ChatType.Group }
        let peerId = match (chatType) {
            case ChatType.Group =>
                if (this.readBoolFieldOpt(chat, "is_forum") == Some(true)) {
                    this.telegramPeerId(chat, threadId: "1")
                } else {
                    this.telegramPeerId(chat)
                }
            case ChatType.Direct => this.telegramPeerId(chat)
        }
        let token = this.readReactionEmoji(reaction)
        let text = if (token.isEmpty()) {
            "[telegram-reaction]\nmessageId=${messageId}\nby=${senderId}"
        } else {
            "[telegram-reaction]\nmessageId=${messageId}\nemoji=${token}\nby=${senderId}"
        }
        let inbound = InboundMessage(
            ChannelType.Telegram,
            "reaction:${chatId}:${messageId}:${senderId}",
            peerId,
            senderId,
            chatType,
            text,
            false,
            DateTime.now(),
            conversationId: Some(peerId),
            threadId: this.reactionInboundThreadId(peerId),
            replyTargetMessageId: Some(messageId),
            replyInThread: peerId.contains(":topic:"),
            raw: Some(raw),
            accountId: this.effectiveAccountId()
        )
        let rejectReason = this.inboundRejectReason(inbound)
        if (!rejectReason.isEmpty()) {
            this.recordInboundDecision(
                this.readIntStringField(root, "update_id"),
                "message_reaction",
                "ignored",
                rejectReason,
                peerId: inbound.peerId,
                senderId: inbound.senderId,
                messageId: inbound.messageId
            )
            return None
        }
        Some(inbound)
    }

    private func mapCallbackQueryWebhookToInbound(root: JsonObject, raw: String): Option<InboundMessage> {
        let callback = match (this.readObjectFieldOpt(root, "callback_query")) {
            case Some(v) => v
            case None => return None
        }
        if (!this.config.actions.callbackQuery) {
            this.recordInboundDecision(this.readIntStringField(root, "update_id"), "callback_query", "ignored", "callback_query_disabled")
            return None
        }
        let callbackId = this.readStringField(callback, "id").trimAscii()
        let data = this.readStringField(callback, "data").trimAscii()
        let sender = this.readObjectField(callback, "from")
        let senderId = this.readIntStringField(sender, "id")
        let msg = this.readObjectField(callback, "message")
        let messageId = this.readIntStringField(msg, "message_id")
        let chat = this.readObjectField(msg, "chat")
        let chatId = this.readIntStringField(chat, "id")
        if (callbackId.isEmpty() || senderId.isEmpty() || messageId.isEmpty() || chatId.isEmpty()) {
            this.recordInboundDecision(this.readIntStringField(root, "update_id"), "callback_query", "ignored", "unsupported_or_empty_callback_query")
            return None
        }
        this.answerTelegramCallbackQuery(callbackId, "")
        let approvalValidation = this.validateApprovalCallbackData(callbackId, data)
        if (!approvalValidation.isEmpty()) {
            this.recordInboundDecision(this.readIntStringField(root, "update_id"), "callback_query", "ignored", approvalValidation)
            return None
        }
        let threadIdRaw = this.readIntStringField(msg, "message_thread_id")
        let peerId = this.telegramPeerId(chat, threadId: threadIdRaw)
        let chatType = if (this.readStringField(chat, "type") == "private") { ChatType.Direct } else { ChatType.Group }
        let text = if (data.startsWith("approval:")) {
            this.renderApprovalCallbackInboundText(callbackId, messageId, data, senderId)
        } else if (data.isEmpty()) {
            "[telegram-callback]\nid=${callbackId}\nmessageId=${messageId}\nactionType=unknown\nby=${senderId}"
        } else {
            "[telegram-callback]\nid=${callbackId}\nmessageId=${messageId}\nactionType=${this.classifyTelegramCallbackAction(data)}\ndata=${data}\nby=${senderId}"
        }
        let inbound = InboundMessage(
            ChannelType.Telegram,
            "callback:${callbackId}",
            peerId,
            senderId,
            chatType,
            text,
            true,
            DateTime.now(),
            conversationId: Some(peerId),
            threadId: if (threadIdRaw.isEmpty()) { None } else { Some(threadIdRaw) },
            replyTargetMessageId: Some(messageId),
            replyInThread: !threadIdRaw.isEmpty(),
            raw: Some(raw),
            accountId: this.effectiveAccountId()
        )
        let rejectReason = this.inboundRejectReason(inbound)
        if (!rejectReason.isEmpty()) {
            this.recordInboundDecision(
                this.readIntStringField(root, "update_id"),
                "callback_query",
                "ignored",
                rejectReason,
                peerId: inbound.peerId,
                senderId: inbound.senderId,
                messageId: inbound.messageId
            )
            return None
        }
        if (data.startsWith("approval:")) {
            this.clearTelegramCallbackButtons(chatId, messageId)
        }
        Some(inbound)
    }

    private func classifyTelegramCallbackAction(data: String): String {
        let normalized = data.trimAscii()
        if (normalized.startsWith("approval:")) { return "approval" }
        if (normalized.startsWith("models:")) { return "model-ui" }
        if (normalized.startsWith("commands:")) { return "command-ui" }
        if (normalized.startsWith("sessions:")) { return "session-ui" }
        if (normalized.startsWith("subagents:")) { return "subagent-ui" }
        if (normalized.startsWith("plugin-approval:")) { return "plugin-approval" }
        if (normalized.startsWith("plugin:")) { return "plugin-not-applicable" }
        "unknown"
    }

    private func answerTelegramCallbackQuery(callbackId: String, text: String): Unit {
        let token = this.effectiveBotToken()
        if (token.isEmpty() || callbackId.trimAscii().isEmpty()) {
            return
        }
        let body = JsonObject()
        body.put("callback_query_id", JsonString(callbackId.trimAscii()))
        if (!text.trimAscii().isEmpty()) {
            body.put("text", JsonString(text.trimAscii()))
        }
        let previous = this.lastSendError
        match (this.telegramJsonPost(this.normalizeApiRoot() + "/bot${token}/answerCallbackQuery", body, context: "answerCallbackQuery")) {
            case Some(raw) =>
                if (!this.parseTelegramBoolSuccess(raw, missingDetail: "telegram answerCallbackQuery returned ok=false")) {
                    this.lastSendError = previous
                }
            case None => this.lastSendError = previous
        }
    }

    private func clearTelegramCallbackButtons(chatId: String, messageId: String): Unit {
        let token = this.effectiveBotToken()
        if (token.isEmpty() || chatId.trimAscii().isEmpty() || messageId.trimAscii().isEmpty()) {
            return
        }
        let body = JsonObject()
        body.put("chat_id", JsonString(chatId.trimAscii()))
        try { body.put("message_id", Int64.parse(messageId.trimAscii()).toJsonValue()) } catch (_: Exception) { body.put("message_id", JsonString(messageId.trimAscii())) }
        let markup = JsonObject()
        markup.put("inline_keyboard", JsonArray([]))
        body.put("reply_markup", markup)
        let previous = this.lastSendError
        match (this.telegramJsonPost(this.normalizeApiRoot() + "/bot${token}/editMessageReplyMarkup", body, context: "editMessageReplyMarkup:clear")) {
            case Some(raw) =>
                let ok = this.parseTelegramBoolSuccess(raw, missingDetail: "telegram editMessageReplyMarkup returned ok=false")
                if (!ok) {
                    let lower = this.lastSendError.toAsciiLower()
                    if (lower.contains("message is not modified")) {
                        this.lastSendError = previous
                    }
                }
            case None => this.lastSendError = previous
        }
    }

    private func validateApprovalCallbackData(callbackId: String, data: String): String {
        if (!data.startsWith("approval:")) {
            return ""
        }
        let parts = data.split(":")
        if (parts.size < 4) {
            return "approval_callback_invalid"
        }
        let expiresAtMs = try { Int64.parse(parts[3].trimAscii()) } catch (_: Exception) { 0 }
        if (expiresAtMs <= 0 || DateTime.now().toUnixTimeStamp().toMilliseconds() > expiresAtMs) {
            return "approval_callback_expired"
        }
        synchronized(this.queueMutex) {
            if (this.consumedApprovalCallbacks.contains(callbackId)) {
                return "approval_callback_replayed"
            }
            this.consumedApprovalCallbacks.add(callbackId)
        }
        ""
    }

    private func renderApprovalCallbackInboundText(callbackId: String, messageId: String, data: String, senderId: String): String {
        let parts = data.split(":")
        let approvalId = if (parts.size > 1) { parts[1].trimAscii() } else { "" }
        let decision = if (parts.size > 2) { parts[2].trimAscii() } else { "" }
        "[telegram-approval]\nid=${callbackId}\nmessageId=${messageId}\napprovalId=${approvalId}\ndecision=${decision}\nby=${senderId}"
    }

    private func sendPayloadToTelegram(payload: HashMap<String, JsonValue>): String {
        let kind = match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() } catch (_e: Exception) { "text" }
            case None => "text"
        }
        let chatId = match (payload.get("chat_id")) {
            case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
            case None => ""
        }
        let peerId = match (payload.get("peer")) {
            case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { chatId }
            case None => chatId
        }
        if (peerId.trimAscii().isEmpty()) {
            this.lastSendError = "peerId is empty"
            return ""
        }
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            this.lastSendError = "bot token is empty"
            return ""
        }
        let method = this.telegramApiMethodForPayloadKind(kind)
        let url = this.normalizeApiRoot() + "/bot${token}/${method}"
        if (kind == "draft") {
            return this.sendDraftPayloadToTelegram(payload)
        }
        if (kind == "media-group" || kind == "edit-media") {
            return this.sendComplexMediaPayloadToTelegram(url, kind, payload)
        }
        let responseOpt = match (this.localMediaUploadForPayload(kind, payload)) {
            case Some(upload) => this.telegramMultipartPost(url, payload, upload[0], upload[1], context: "send:${kind}:multipart")
            case None => this.telegramJsonPost(url, this.telegramApiBodyForPayload(payload, plainFallback: false), context: "send:${kind}")
        }
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                if (this.lastSendError.trimAscii().isEmpty()) {
                    this.setLastSendError("empty http response")
                }
                return ""
        }
        if (let Some(messageId) <- this.parseTelegramPayloadSuccess(kind, responseRaw)) {
            this.sendTelegramPayloadFollowUpText(payload)
            return messageId
        }
        if (kind == "voice") {
            let fallbackId = this.trySendVoiceForbiddenFallback(payload)
            if (!fallbackId.isEmpty()) {
                return fallbackId
            }
        }
        if (this.shouldRetryWithoutTelegramThread(payload)) {
            let threadlessPayload = this.telegramPayloadWithoutThread(payload)
            let retryResponseOpt = match (this.localMediaUploadForPayload(kind, threadlessPayload)) {
                case Some(upload) => this.telegramMultipartPost(url, threadlessPayload, upload[0], upload[1], context: "send:${kind}:threadless:multipart")
                case None => this.telegramJsonPost(url, this.telegramApiBodyForPayload(threadlessPayload, plainFallback: false), context: "send:${kind}:threadless")
            }
            match (retryResponseOpt) {
                case Some(retryRaw) =>
                    if (let Some(messageId) <- this.parseTelegramPayloadSuccess(kind, retryRaw)) {
                        this.sendTelegramPayloadFollowUpText(threadlessPayload)
                        return messageId
                    }
                    if (kind == "voice") {
                        let fallbackId = this.trySendVoiceForbiddenFallback(threadlessPayload)
                        if (!fallbackId.isEmpty()) {
                            return fallbackId
                        }
                    }
                case None =>
                    if (this.lastSendError.trimAscii().isEmpty()) {
                        this.setLastSendError("empty http response")
                    }
            }
        }
        if (kind == "poll" || kind == "delete" || kind == "clear-buttons" || kind == "edit-buttons" || kind == "pin" || kind == "unpin" || kind == "topic-create" || kind == "reaction" || kind == "sticker") {
            return ""
        }
        if (!this.shouldRetryWithoutParseMode()) {
            return ""
        }
        let plainPayload = HashMap<String, JsonValue>()
        for ((key, value) in payload) {
            if (key == "parse_mode") {
                continue
            }
            plainPayload[key] = value
        }
        let plainResponseOpt = match (this.localMediaUploadForPayload(kind, plainPayload)) {
            case Some(upload) => this.telegramMultipartPost(url, plainPayload, upload[0], upload[1], context: "send:${kind}:plain:multipart")
            case None => this.telegramJsonPost(url, this.telegramApiBodyForPayload(plainPayload, plainFallback: true), context: "send:${kind}:plain")
        }
        let plainResponseRaw = match (plainResponseOpt) {
            case Some(resp) => resp
            case None =>
                if (this.lastSendError.trimAscii().isEmpty()) {
                    this.setLastSendError("empty http response")
                }
                return ""
        }
        let plainMessageId = this.parseTelegramPayloadSuccess(kind, plainResponseRaw) ?? ""
        if (!plainMessageId.isEmpty()) {
            this.sendTelegramPayloadFollowUpText(plainPayload)
        }
        plainMessageId
    }

    private func trySendVoiceForbiddenFallback(payload: HashMap<String, JsonValue>): String {
        let err = this.lastSendError.trimAscii().toAsciiLower()
        if (!err.contains("voice_messages_forbidden") && !err.contains("voice messages forbidden")) {
            return ""
        }
        let plainCaption = match (payload.get("plain_caption")) {
            case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
            case None => ""
        }
        let fallbackText = if (!plainCaption.isEmpty()) {
            plainCaption
        } else {
            "Telegram refused this voice message. The original audio is available as a voice attachment in Gateway media context."
        }
        let fallback = HashMap<String, JsonValue>()
        fallback["kind"] = JsonString("text")
        fallback["peer"] = payload.get("peer") ?? JsonString("")
        fallback["chat_id"] = payload.get("chat_id") ?? JsonString("")
        fallback["text"] = JsonString(this.telegramRenderHtml(fallbackText))
        fallback["plain_text"] = JsonString(fallbackText)
        fallback["parse_mode"] = JsonString("HTML")
        fallback["disable_web_page_preview"] = true.toJsonValue()
        match (payload.get("message_thread_id")) {
            case Some(v) => fallback["message_thread_id"] = v
            case None => ()
        }
        this.copyTelegramReplyTarget(fallback, payload)
        let previousError = this.lastSendError
        let sent = this.sendPayloadToTelegram(fallback)
        if (!sent.isEmpty()) {
            this.lastSendError = previousError
        }
        sent
    }

    private func sendComplexMediaPayloadToTelegram(url: String, kind: String, payload: HashMap<String, JsonValue>): String {
        let responseOpt = match (this.telegramMultipartFilesForPayload(kind, payload)) {
            case Some(files) => this.telegramMultipartFilesPost(url, this.telegramComplexMultipartFieldsForPayload(kind, payload, files), files, context: "send:${kind}:multipart")
            case None => this.telegramJsonPost(url, this.telegramApiBodyForPayload(payload, plainFallback: false), context: "send:${kind}")
        }
        let raw = match (responseOpt) {
            case Some(v) => v
            case None =>
                this.setLastSendError("empty http response")
                return ""
        }
        if (kind == "media-group") {
            return if (this.parseTelegramMediaGroupSuccess(raw)) { "media-group" } else { "" }
        }
        this.parseTelegramPayloadSuccess(kind, raw) ?? ""
    }

    private func sendTelegramPayloadFollowUpText(payload: HashMap<String, JsonValue>): Unit {
        let text = match (payload.get("follow_up_text")) {
            case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
            case None => ""
        }
        if (text.isEmpty()) {
            return
        }
        let body = JsonObject()
        body.put("chat_id", payload.get("chat_id") ?? JsonString(""))
        body.put("text", JsonString(this.telegramRenderHtml(text)))
        body.put("plain_text", JsonString(text))
        body.put("parse_mode", JsonString("HTML"))
        body.put("disable_web_page_preview", (!this.config.linkPreview).toJsonValue())
        match (payload.get("message_thread_id")) {
            case Some(v) => body.put("message_thread_id", v)
            case None => ()
        }
        match (payload.get("reply_parameters")) {
            case Some(v) => body.put("reply_parameters", v)
            case None =>
                match (payload.get("reply_to_message_id")) {
                    case Some(v) => body.put("reply_to_message_id", v)
                    case None => ()
                }
        }
        let url = this.normalizeApiRoot() + "/bot${this.effectiveBotToken()}/sendMessage"
        let previousError = this.lastSendError
        match (this.telegramJsonPost(url, body, context: "send:follow-up")) {
            case Some(raw) =>
                if (this.parseTelegramPayloadSuccess("text", raw).isNone()) {
                    this.lastSendError = previousError
                }
            case None => this.lastSendError = previousError
        }
    }

    private func shouldRetryWithoutTelegramThread(payload: HashMap<String, JsonValue>): Bool {
        if (!payload.contains("message_thread_id")) {
            return false
        }
        let err = this.lastSendError.trimAscii().toAsciiLower()
        err.contains("message thread not found") ||
            err.contains("message thread_id not found") ||
            err.contains("thread not found") ||
            err.contains("topic not found")
    }

    private func telegramPayloadWithoutThread(payload: HashMap<String, JsonValue>): HashMap<String, JsonValue> {
        let out = HashMap<String, JsonValue>()
        for ((key, value) in payload) {
            if (key == "message_thread_id") {
                continue
            }
            out[key] = value
        }
        out
    }

    private func sendDraftPayloadToTelegram(payload: HashMap<String, JsonValue>): String {
        let draftPayload = HashMap<String, JsonValue>()
        for ((key, value) in payload) {
            if (key == "final_text" || key == "plain_final_text") {
                continue
            }
            draftPayload[key] = value
        }
        draftPayload["kind"] = JsonString("text")
        let draftUrl = this.normalizeApiRoot() + "/bot${this.effectiveBotToken()}/sendMessageDraft"
        var responseOpt = this.telegramJsonPost(draftUrl, this.telegramApiBodyForPayload(draftPayload, plainFallback: false), context: "send:draft:native")
        if (responseOpt.isNone()) {
            let low = this.lastSendError.toAsciiLower()
            if (low.contains("not found") || low.contains("method") || low.contains("404")) {
                let fallbackUrl = this.normalizeApiRoot() + "/bot${this.effectiveBotToken()}/sendMessage"
                responseOpt = this.telegramJsonPost(fallbackUrl, this.telegramApiBodyForPayload(draftPayload, plainFallback: false), context: "send:draft")
            }
        }
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.setLastSendError("empty http response")
                return ""
        }
        let messageId = match (this.parseTelegramSendSuccess(responseRaw)) {
            case Some(id) => id
            case None =>
                if (!this.telegramDraftMethodLooksUnsupported(responseRaw)) {
                    return ""
                }
                let fallbackUrl = this.normalizeApiRoot() + "/bot${this.effectiveBotToken()}/sendMessage"
                let fallbackRaw = match (this.telegramJsonPost(fallbackUrl, this.telegramApiBodyForPayload(draftPayload, plainFallback: false), context: "send:draft")) {
                    case Some(resp) => resp
                    case None => return ""
                }
                match (this.parseTelegramSendSuccess(fallbackRaw)) {
                    case Some(id2) => id2
                    case None => return ""
                }
        }
        let editPayload = HashMap<String, JsonValue>()
        editPayload["kind"] = JsonString("edit")
        editPayload["peer"] = payload.get("peer") ?? JsonString("")
        editPayload["chat_id"] = payload.get("chat_id") ?? JsonString("")
        editPayload["message_id"] = JsonString(messageId)
        editPayload["text"] = payload.get("final_text") ?? payload.get("text") ?? JsonString("")
        editPayload["plain_text"] = payload.get("plain_final_text") ?? payload.get("plain_text") ?? JsonString("")
        editPayload["parse_mode"] = JsonString("HTML")
        editPayload["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
        let editUrl = this.normalizeApiRoot() + "/bot${this.effectiveBotToken()}/editMessageText"
        let editResponseOpt = this.telegramJsonPost(editUrl, this.telegramApiBodyForPayload(editPayload, plainFallback: false), context: "send:draft:final")
        match (editResponseOpt) {
            case Some(raw) =>
                if (this.parseTelegramPayloadSuccess("edit", raw).isSome()) {
                    return messageId
                }
                ""
            case None =>
                this.setLastSendError("empty http response")
                ""
        }
    }

    private func telegramDraftMethodLooksUnsupported(raw: String): Bool {
        let low = raw.trimAscii().toAsciiLower()
        low.contains("method not found") ||
            low.contains("not found") ||
            low.contains("can't find method") ||
            low.contains("\"error_code\":404") ||
            low.contains("\"error_code\": 404")
    }

    private func telegramApiBodyForPayload(payload: HashMap<String, JsonValue>, plainFallback!: Bool): JsonObject {
        let out = JsonObject()
        for ((key, value) in payload) {
            if (key == "kind" || key == "peer" || key == "plain_text" || key == "plain_caption" || key == "follow_up_text") {
                continue
            }
            if (plainFallback && key == "text") {
                match (payload.get("plain_text")) {
                    case Some(plain) =>
                        out.put("text", plain)
                        continue
                    case None => ()
                }
            }
            if (plainFallback && key == "caption") {
                match (payload.get("plain_caption")) {
                    case Some(plain) =>
                        out.put("caption", plain)
                        continue
                    case None => ()
                }
            }
            out.put(key, value)
        }
        out
    }

    private func localMediaUploadForPayload(kind: String, payload: HashMap<String, JsonValue>): Option<Array<String>> {
        let mediaField = this.telegramMediaFieldForPayloadKind(kind)
        if (mediaField.isEmpty()) {
            return None
        }
        let ref = match (payload.get(mediaField)) {
            case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
            case None => ""
        }
        if (ref.isEmpty() || !this.looksLikeLocalMediaPath(ref)) {
            return None
        }
        Some([mediaField, this.normalizeOutboundLocalMediaPath(ref)])
    }

    private func telegramMultipartFilesForPayload(kind: String, payload: HashMap<String, JsonValue>): Option<Array<TelegramMultipartFile>> {
        let files = ArrayList<TelegramMultipartFile>()
        if (kind == "media-group") {
            match (payload.get("media")) {
                case Some(v) =>
                    try {
                        var idx: Int64 = 0
                        for (item in v.asArray().getItems()) {
                            let obj = item.asObject()
                            let ref = this.readStringField(obj, "media").trimAscii()
                            if (this.looksLikeLocalMediaPath(ref)) {
                                files.add(TelegramMultipartFile("file${idx}", filePath: this.normalizeOutboundLocalMediaPath(ref)))
                            }
                            idx += 1
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                case None => ()
            }
        } else if (kind == "edit-media") {
            match (payload.get("media")) {
                case Some(v) =>
                    try {
                        let obj = v.asObject()
                        let ref = this.readStringField(obj, "media").trimAscii()
                        if (this.looksLikeLocalMediaPath(ref)) {
                            files.add(TelegramMultipartFile("file0", filePath: this.normalizeOutboundLocalMediaPath(ref)))
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                case None => ()
            }
        }
        if (files.isEmpty()) {
            return None
        }
        Some(files.toArray())
    }

    private func telegramComplexMultipartFieldsForPayload(kind: String, payload: HashMap<String, JsonValue>, files: Array<TelegramMultipartFile>): HashMap<String, String> {
        let out = HashMap<String, String>()
        for ((key, value) in payload) {
            if (key == "kind" || key == "peer" || key == "plain_text" || key == "plain_caption" || key == "follow_up_text") {
                continue
            }
            if (key == "media") {
                out[key] = this.telegramMediaPayloadWithAttachReferences(kind, value, files)
            } else {
                out[key] = this.telegramMultipartFieldValue(value)
            }
        }
        out
    }

    private func telegramMediaPayloadWithAttachReferences(kind: String, value: JsonValue, files: Array<TelegramMultipartFile>): String {
        if (kind == "media-group") {
            let arr = JsonArray([])
            try {
                var idx: Int64 = 0
                for (item in value.asArray().getItems()) {
                    let obj = item.asObject()
                    let copy = this.copyTelegramInputMediaObject(obj, if (this.looksLikeLocalMediaPath(this.readStringField(obj, "media"))) { "attach://file${idx}" } else { "" })
                    arr.add(copy)
                    idx += 1
                }
                return arr.toJsonString()
            } catch (_e: Exception) {
                return value.toJsonString()
            }
        }
        if (kind == "edit-media") {
            try {
                let obj = value.asObject()
                let copy = this.copyTelegramInputMediaObject(obj, if (this.looksLikeLocalMediaPath(this.readStringField(obj, "media"))) { "attach://file0" } else { "" })
                return copy.toJsonString()
            } catch (_e: Exception) {
                return value.toJsonString()
            }
        }
        value.toJsonString()
    }

    private func copyTelegramInputMediaObject(obj: JsonObject, attachMedia: String): JsonObject {
        let out = JsonObject()
        for (key in ["type", "media", "caption", "parse_mode", "has_spoiler", "thumbnail", "duration", "width", "height", "supports_streaming", "performer", "title", "disable_content_type_detection"]) {
            match (obj.get(key)) {
                case Some(v) =>
                    if (key == "media" && !attachMedia.trimAscii().isEmpty()) {
                        out.put("media", JsonString(attachMedia.trimAscii()))
                    } else {
                        out.put(key, v)
                    }
                case None => ()
            }
        }
        out
    }

    private func telegramMediaFieldForPayloadKind(kind: String): String {
        if (kind == "photo") { return "photo" }
        if (kind == "document") { return "document" }
        if (kind == "audio") { return "audio" }
        if (kind == "voice") { return "voice" }
        if (kind == "video") { return "video" }
        if (kind == "video-note") { return "video_note" }
        if (kind == "sticker") { return "sticker" }
        if (kind == "animation") { return "animation" }
        ""
    }

    private func telegramMultipartFieldsForPayload(payload: HashMap<String, JsonValue>, fileField: String): HashMap<String, String> {
        let out = HashMap<String, String>()
        for ((key, value) in payload) {
            if (key == "kind" || key == "peer" || key == "plain_text" || key == "plain_caption" || key == "follow_up_text" || key == fileField) {
                continue
            }
            out[key] = this.telegramMultipartFieldValue(value)
        }
        out
    }

    private func telegramMultipartFieldValue(value: JsonValue): String {
        try {
            return value.asString().getValue()
        } catch (_e1: Exception) {
            try {
                return if (value.asBool().getValue()) { "true" } else { "false" }
            } catch (_e2: Exception) {
                value.toJsonString()
            }
        }
    }

    private func parseTelegramPayloadSuccess(kind: String, raw: String): Option<String> {
        if (kind == "delete" || kind == "clear-buttons" || kind == "edit-buttons" || kind == "pin" || kind == "unpin" || kind == "reaction" || kind == "edit" || kind == "edit-media" || kind == "chat-action") {
            return if (this.parseTelegramBoolSuccess(raw, missingDetail: "telegram api returned ok=false")) { Some("") } else { None<String> }
        }
        if (kind == "topic-create") {
            return if (this.parseTelegramTopicCreateSuccess(raw)) { Some("") } else { None<String> }
        }
        if (kind == "topic-edit") {
            return if (this.parseTelegramBoolSuccess(raw, missingDetail: "telegram api returned ok=false")) { Some("") } else { None<String> }
        }
        return this.parseTelegramSendSuccess(raw)
    }

    private func parseTelegramMediaGroupSuccess(raw: String): Bool {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let ok = match (jo.get("ok")) {
                case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
                case None => false
            }
            if (!ok) {
                let desc = this.readStringField(jo, "description")
                this.setLastSendError(if (desc.isEmpty()) { "telegram media group returned ok=false" } else { desc })
                return false
            }
            this.lastSendError = ""
            true
        } catch (e: Exception) {
            this.setLastSendError("telegram media group parse failed: ${e.message}")
            false
        }
    }

    private func parseTelegramSendSuccess(raw: String): Option<String> {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let ok = match (jo.get("ok")) {
                case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
                case None => false
            }
            if (!ok) {
                let desc = this.readStringField(jo, "description")
                this.setLastSendError(if (desc.isEmpty()) { "telegram api returned ok=false" } else { desc })
                return None<String>
            }
            let result = this.readObjectField(jo, "result")
            let messageId = this.readIntStringField(result, "message_id")
            if (messageId.isEmpty()) {
                this.setLastSendError("telegram api missing result.message_id")
                return None<String>
            }
            this.lastSendError = ""
            Some(messageId)
        } catch (e: Exception) {
            this.setLastSendError("telegram send parse failed: ${e.message}")
            None<String>
        }
    }

    private func parseTelegramBoolSuccess(raw: String, missingDetail!: String): Bool {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let ok = match (jo.get("ok")) {
                case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
                case None => false
            }
            if (!ok) {
                let desc = this.readStringField(jo, "description")
                this.setLastSendError(if (desc.isEmpty()) { missingDetail } else { desc })
                return false
            }
            this.lastSendError = ""
            true
        } catch (e: Exception) {
            this.setLastSendError("telegram bool parse failed: ${e.message}")
            false
        }
    }

    private func chatActionBackoffActive(): Bool {
        let until = this.chatActionBackoffUntilMs
        until > 0 && DateTime.now().toUnixTimeStamp().toMilliseconds() < until
    }

    private func recordChatActionBackoffIfNeeded(): Unit {
        let reason = this.lastSendError.trimAscii()
        let low = reason.toAsciiLower()
        if (low.contains("401") || low.contains("403") || low.contains("unauthorized") || low.contains("forbidden")) {
            this.chatActionBackoffReason = if (reason.isEmpty()) { "telegram chat-action authorization failure" } else { reason }
            this.chatActionBackoffUntilMs = DateTime.now().toUnixTimeStamp().toMilliseconds() + 60000
        }
    }

    private func parseTelegramTopicCreateSuccess(raw: String): Bool {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let ok = match (jo.get("ok")) {
                case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
                case None => false
            }
            if (!ok) {
                let desc = this.readStringField(jo, "description")
                this.setLastSendError(if (desc.isEmpty()) { "telegram api returned ok=false" } else { desc })
                return false
            }
            let result = this.readObjectField(jo, "result")
            let threadId = this.readIntStringField(result, "message_thread_id")
            if (threadId.isEmpty()) {
                this.setLastSendError("telegram api missing result.message_thread_id")
                return false
            }
            this.lastSendError = ""
            true
        } catch (e: Exception) {
            this.setLastSendError("telegram topic parse failed: ${e.message}")
            false
        }
    }

    private func parseTelegramProbeResult(raw: String): JsonObject {
        let out = JsonObject()
        out.put("ok", false.toJsonValue())
        if (raw.trimAscii().isEmpty()) {
            out.put("error", JsonString("empty"))
            return out
        }
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let ok = match (jo.get("ok")) {
                case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
                case None => false
            }
            out.put("ok", ok.toJsonValue())
            if (!ok) {
                out.put("error", JsonString(this.readStringField(jo, "description")))
            }
            out.put("result", jo.get("result") ?? JsonObject())
            out
        } catch (e: Exception) {
            out.put("error", JsonString("parse:${e.message}"))
            out
        }
    }

    private func tryTelegramGet(url: String): String {
        match (this.telegramGet(url, accept: "application/json", context: "get")) {
            case Some(raw) => raw
            case None => "{\"ok\":false,\"description\":\"empty http response\"}"
        }
    }

    private func buildTelegramHealthSnapshot(getMeRaw: String, webhookInfoRaw: String): JsonObject {
        let out = JsonObject()
        let getMe = this.parseTelegramProbeResult(getMeRaw)
        let webhookInfo = this.parseTelegramProbeResult(webhookInfoRaw)
        let lastInboundUpdateId = this.readLastInboundUpdateId()
        let summary = JsonObject()
        let account = this.buildTelegramAccountDiagnostics()
        summary.put("mode", JsonString(if (this.usesWebhookMode()) { "webhook" } else { "polling" }))
        summary.put("accountId", account.get("accountId") ?? JsonString(this.effectiveAccountId()))
        summary.put("tokenSource", account.get("tokenSource") ?? JsonString("none"))
        summary.put("tokenConfigured", account.get("tokenConfigured") ?? false.toJsonValue())
        summary.put("allowedUpdates", this.buildAllowedUpdates())
        summary.put("webhookConfigured", this.usesWebhookMode().toJsonValue())
        summary.put("offsetPersistenceEnabled", true.toJsonValue())
        summary.put("lastInboundUpdateId", JsonString(lastInboundUpdateId))
        let media = this.readMediaState()
        summary.put("mediaPersistenceEnabled", true.toJsonValue())
        summary.put("mediaDownloadEnabled", true.toJsonValue())
        summary.put("lastPersistedMediaId", JsonString(this.readStringField(media, "lastPersistedMediaId")))
        let polling = this.buildPollingDiagnosticSnapshot()
        summary.put("pollingState", polling.get("state") ?? JsonString("idle"))
        summary.put("pollingConsecutiveFailures", polling.get("consecutiveFailures") ?? 0.toJsonValue())
        summary.put("pollingLastOutcome", polling.get("lastOutcome") ?? JsonString("idle"))
        summary.put("pollingLastConfirmedOffset", JsonString(this.lastConfirmedPollingOffset))
        summary.put("pollingLastRetryAfterSeconds", this.lastRetryAfterSeconds.toJsonValue())
        let inboundPolicy = this.buildInboundPolicyDiagnostics()
        summary.put("lastInboundDecision", inboundPolicy.get("lastDecision") ?? JsonString("none"))
        summary.put("lastInboundReason", inboundPolicy.get("lastReason") ?? JsonString(""))
        summary.put("healthy", (this.readJsonBoolField(getMe, "ok", false) && this.readJsonBoolField(webhookInfo, "ok", false)).toJsonValue())
        let bot = JsonObject()
        match (getMe.get("result")) {
            case Some(v) =>
                try {
                    let result = v.asObject()
                    bot.put("id", JsonString(this.readIntStringField(result, "id")))
                    bot.put("username", JsonString(this.readStringField(result, "username")))
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        let webhook = JsonObject()
        match (webhookInfo.get("result")) {
            case Some(v) =>
                try {
                    let result = v.asObject()
                    webhook.put("url", JsonString(this.readStringField(result, "url")))
                    webhook.put("pendingUpdateCount", JsonString(this.readIntStringField(result, "pending_update_count")))
                    webhook.put("lastErrorMessage", JsonString(this.readStringField(result, "last_error_message")))
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        out.put("summary", summary)
        out.put("bot", bot)
        out.put("webhook", webhook)
        let offset = JsonObject()
        offset.put("lastInboundUpdateId", JsonString(lastInboundUpdateId))
        offset.put("statePath", JsonString(this.offsetStatePath().toString()))
        offset.put("persistenceEnabled", true.toJsonValue())
        offset.put("accountId", JsonString(this.effectiveAccountId()))
        offset.put("botId", JsonString(this.effectiveBotId()))
        let offsetDiagnostics = this.buildOffsetDiagnostics()
        offset.put("pendingUpdateCount", offsetDiagnostics.get("pendingUpdateCount") ?? 0.toJsonValue())
        offset.put("dedupeCacheSize", offsetDiagnostics.get("dedupeCacheSize") ?? 0.toJsonValue())
        offset.put("lastConfirmedOffset", JsonString(this.lastConfirmedPollingOffset))
        out.put("offset", offset)
        out.put("account", account)
        out.put("media", media)
        out.put("polling", polling)
        out.put("inboundPolicy", inboundPolicy)
        out.put("webhookLifecycle", this.buildWebhookLifecycleDiagnostics())
        out.put("nativeCommands", this.buildNativeCommandDiagnostics())
        out.put("telegramUpdateTypes", this.buildTelegramUpdateTypeCapabilityMatrix())
        out.put("getMe", getMe)
        out.put("webhookInfo", webhookInfo)
        out
    }

    private func buildWebhookLifecycleDiagnostics(): JsonObject {
        let out = JsonObject()
        out.put("mode", JsonString(if (this.usesWebhookMode()) { "webhook" } else { "polling" }))
        out.put("registrationStatus", JsonString(this.webhookRegistrationStatus))
        out.put("registrationError", JsonString(this.webhookRegistrationError))
        out.put("registrationAtMs", this.webhookRegistrationAtMs.toJsonValue())
        out.put("cleanupStatus", JsonString(this.webhookCleanupStatus))
        out.put("cleanupError", JsonString(this.webhookCleanupError))
        out.put("cleanupAtMs", this.webhookCleanupAtMs.toJsonValue())
        out.put("pollingWebhookCleared", this.pollingWebhookCleared.toJsonValue())
        out.put("secretConfigured", (!this.config.webhookSecret.trimAscii().isEmpty()).toJsonValue())
        out.put("certificateConfigured", (!this.config.webhookCertPath.trimAscii().isEmpty()).toJsonValue())
        out.put("webhookAndPollingMutuallyExclusive", true.toJsonValue())
        out
    }

    private func buildInboundPolicyDiagnostics(): JsonObject {
        let out = JsonObject()
        out.put("lastDecision", JsonString(this.lastInboundDecision))
        out.put("lastReason", JsonString(this.lastInboundReason))
        out.put("lastUpdateKind", JsonString(this.lastInboundUpdateKind))
        out.put("lastUpdateId", JsonString(this.lastInboundUpdateIdForPolicy))
        out.put("lastPeerId", JsonString(this.lastInboundPeerId))
        out.put("lastSenderId", JsonString(this.lastInboundSenderId))
        out.put("lastMessageId", JsonString(this.lastInboundMessageIdForPolicy))
        out
    }

    private func telegramUpdateTypeCapability(kind: String, status: String, handler: String, reason: String): JsonObject {
        let out = JsonObject()
        out.put("kind", JsonString(kind))
        out.put("status", JsonString(status))
        out.put("handler", JsonString(handler))
        out.put("reason", JsonString(reason))
        out
    }

    private func buildTelegramUpdateTypeCapabilityMatrix(): JsonArray {
        let out = JsonArray([])
        out.add(this.telegramUpdateTypeCapability("message", "supported", "message", "standard Telegram message ingress"))
        out.add(this.telegramUpdateTypeCapability("edited_message", "supported", "message", "edited message maps to standard ingress"))
        out.add(this.telegramUpdateTypeCapability("channel_post", "supported", "message", "channel post maps to channel-style ingress"))
        out.add(this.telegramUpdateTypeCapability("edited_channel_post", "supported", "message", "edited channel post maps to channel-style ingress"))
        out.add(this.telegramUpdateTypeCapability("message_reaction", "config-supported", "reaction", "enabled when reactionNotifications is not off"))
        out.add(this.telegramUpdateTypeCapability("message_reaction_count", "ignored", "unsupported-diagnostic", "aggregate reaction counts do not represent a user chat turn"))
        out.add(this.telegramUpdateTypeCapability("callback_query", "config-supported", "callback", "enabled when actions.callbackQuery or inlineKeyboard is true"))
        for (kind in ["business_connection", "business_message", "edited_business_message", "deleted_business_messages", "inline_query", "chosen_inline_result", "shipping_query", "pre_checkout_query", "purchased_paid_media", "poll", "poll_answer", "my_chat_member", "chat_member", "managed_bot", "chat_join_request", "chat_boost", "removed_chat_boost"]) {
            out.add(this.telegramUpdateTypeCapability(kind, "not-applicable", "unsupported-diagnostic", "not part of the current Metis code-agent chat surface"))
        }
        out
    }

    private func telegramStateDir(): Path {
        let dir = this.stateRoot.join("gateway-telegram")
        if (!exists(dir)) {
            try {
                Directory.create(dir, recursive: true)
            } catch (_e: Exception) {
                if (!exists(dir)) {
                    throw _e
                }
            }
        }
        dir
    }

    private func telegramAccountStateDir(): Path {
        let dir = this.telegramStateDir().join("accounts").join(this.safeStateSegment(this.effectiveAccountId()))
        if (!exists(dir)) {
            try {
                Directory.create(dir, recursive: true)
            } catch (_e: Exception) {
                if (!exists(dir)) {
                    throw _e
                }
            }
        }
        dir
    }

    private func offsetStatePath(): Path {
        this.telegramAccountStateDir().join("offset-state.json")
    }

    private func buildOffsetDiagnostics(): JsonObject {
        synchronized(this.offsetMutex) {
            let out = JsonObject()
            out.put("lastInboundUpdateId", JsonString(this.readLastInboundUpdateId()))
            out.put("pendingUpdateCount", this.pendingUpdateIds.size.toJsonValue())
            out.put("dedupeCacheSize", this.completedUpdateIds.size.toJsonValue())
            out.put("statePath", JsonString(this.offsetStatePath().toString()))
            out.put("accountId", JsonString(this.effectiveAccountId()))
            out.put("botId", JsonString(this.effectiveBotId()))
            out
        }
    }

    private func mediaStatePath(): Path {
        this.telegramAccountStateDir().join("media-state.json")
    }

    private func sentMessageStatePath(): Path {
        this.telegramAccountStateDir().join("sent-message-state.json")
    }

    private func groupMigrationStatePath(): Path {
        this.telegramAccountStateDir().join("group-migrations.json")
    }

    private func recordTelegramGroupMigrationIfNeeded(root: JsonObject, msg: JsonObject, messageId: String): Bool {
        let toChatId = this.readIntStringField(msg, "migrate_to_chat_id").trimAscii()
        let fromChatId = this.readIntStringField(msg, "migrate_from_chat_id").trimAscii()
        if (toChatId.isEmpty() && fromChatId.isEmpty()) {
            return false
        }
        let chat = this.readObjectField(msg, "chat")
        let chatId = this.readIntStringField(chat, "id").trimAscii()
        let oldChatId = if (!fromChatId.isEmpty()) { fromChatId } else { chatId }
        let newChatId = if (!toChatId.isEmpty()) { toChatId } else { chatId }
        let row = JsonObject()
        row.put("updateId", JsonString(this.readIntStringField(root, "update_id")))
        row.put("messageId", JsonString(messageId.trimAscii()))
        row.put("oldChatId", JsonString(oldChatId))
        row.put("newChatId", JsonString(newChatId))
        row.put("oldPeerId", JsonString(if (oldChatId.isEmpty()) { "" } else { "group:${oldChatId}" }))
        row.put("newPeerId", JsonString(if (newChatId.isEmpty()) { "" } else { "group:${newChatId}" }))
        row.put("accountId", JsonString(this.effectiveAccountId()))
        row.put("recordedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        let path = this.groupMigrationStatePath()
        let migrations = if (exists(path)) {
            try { JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray() } catch (_e: Exception) { JsonArray([]) }
        } else {
            JsonArray([])
        }
        for (item in migrations.getItems()) {
            let existing = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            if (this.readStringField(existing, "oldChatId") == oldChatId && this.readStringField(existing, "newChatId") == newChatId) {
                return true
            }
        }
        migrations.add(row)
        if (!exists(path.parent)) {
            Directory.create(path.parent, recursive: true)
        }
        File.writeTo(path, (migrations.toJsonString() + "\n").toArray())
        true
    }

    private func mediaDownloadDir(): Path {
        let dir = this.telegramAccountStateDir().join("media")
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        dir
    }

    private func readLastInboundUpdateId(): String {
        let path = this.offsetStatePath()
        if (!exists(path)) {
            return ""
        }
        return try {
            let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
            if (this.offsetStateBelongsToCurrentBot(root)) {
                let latest = this.readStringField(root, "lastUpdateId").trimAscii()
                if (!latest.isEmpty()) {
                    return latest
                }
                return this.readStringField(root, "lastInboundUpdateId").trimAscii()
            }
            ""
        } catch (_: Exception) {
            ""
        }
    }

    private func beginUpdateProcessing(updateId: String, dedupeByOffset!: Bool = false): Bool {
        let normalized = updateId.trimAscii()
        if (normalized.isEmpty()) {
            return true
        }
        synchronized(this.offsetMutex) {
            if (this.pendingUpdateIds.contains(normalized)) {
                return false
            }
            if (dedupeByOffset) {
                if (this.completedUpdateIds.contains(normalized)) {
                    return false
                }
                let watermark = this.readLastInboundUpdateId()
                if (this.updateIdLessThanOrEqual(normalized, watermark)) {
                    this.rememberCompletedUpdateId(normalized)
                    return false
                }
            }
            this.pendingUpdateIds.add(normalized)
            true
        }
    }

    private func completeUpdateProcessing(updateId: String): Unit {
        let normalized = updateId.trimAscii()
        if (normalized.isEmpty()) {
            return
        }
        synchronized(this.offsetMutex) {
            this.pendingUpdateIds.remove(normalized)
            this.rememberCompletedUpdateId(normalized)
            this.persistLastInboundUpdateId(normalized)
        }
    }

    private func finishUpdateProcessingWithoutWatermark(updateId: String): Unit {
        let normalized = updateId.trimAscii()
        if (normalized.isEmpty()) {
            return
        }
        synchronized(this.offsetMutex) {
            this.pendingUpdateIds.remove(normalized)
        }
    }

    private func rememberCompletedUpdateId(updateId: String): Unit {
        if (updateId.isEmpty() || this.completedUpdateIds.contains(updateId)) {
            return
        }
        this.completedUpdateIds.add(updateId)
        this.completedUpdateIdOrder.add(updateId)
        while (this.completedUpdateIdOrder.size > 256) {
            let evicted = this.completedUpdateIdOrder[0]
            this.completedUpdateIdOrder.remove(at: 0)
            this.completedUpdateIds.remove(evicted)
        }
    }

    private func updateIdLessThanOrEqual(updateId: String, watermark: String): Bool {
        let left = updateId.trimAscii()
        let right = watermark.trimAscii()
        if (left.isEmpty() || right.isEmpty()) {
            return false
        }
        try {
            return Int64.parse(left) <= Int64.parse(right)
        } catch (_: Exception) {
            false
        }
    }

    private func persistLastInboundUpdateId(updateId: String): Unit {
        let normalized = updateId.trimAscii()
        if (normalized.isEmpty()) {
            return
        }
        let root = JsonObject()
        root.put("version", 2.toJsonValue())
        root.put("accountId", JsonString(this.effectiveAccountId()))
        root.put("botId", JsonString(this.effectiveBotId()))
        root.put("lastUpdateId", JsonString(normalized))
        root.put("lastInboundUpdateId", JsonString(normalized))
        root.put("updatedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        File.writeTo(this.offsetStatePath(), root.toJsonString().toArray())
    }

    private func offsetStateBelongsToCurrentBot(root: JsonObject): Bool {
        let expectedAccountId = this.effectiveAccountId()
        let storedAccountId = this.readStringField(root, "accountId").trimAscii()
        if (!storedAccountId.isEmpty() && storedAccountId != expectedAccountId) {
            return false
        }
        let expectedBotId = this.effectiveBotId()
        if (expectedBotId.isEmpty()) {
            return true
        }
        let storedBotId = this.readStringField(root, "botId").trimAscii()
        if (storedBotId.isEmpty()) {
            return false
        }
        storedBotId == expectedBotId
    }

    private func safeStateSegment(raw: String): String {
        safeTelegramStateSegment(raw)
    }

    private func readMediaState(): JsonObject {
        let path = this.mediaStatePath()
        if (!exists(path)) {
            let empty = JsonObject()
            empty.put("statePath", JsonString(path.toString()))
            empty.put("persistenceEnabled", true.toJsonValue())
            empty.put("downloadEnabled", this.config.media.downloadEnabled.toJsonValue())
            empty.put("mediaMaxBytes", this.effectiveMediaMaxBytes().toJsonValue())
            empty.put("allowedMimes", this.mediaAllowedMimesJson())
            empty.put("albumPolicy", JsonString(this.effectiveMediaAlbumPolicy()))
            empty.put("warnOnDownloadFailure", this.config.media.warnOnDownloadFailure.toJsonValue())
            empty.put("accountId", JsonString(this.effectiveAccountId()))
            empty.put("lastPersistedMediaId", JsonString(""))
            empty.put("lastMedia", JsonObject())
            return empty
        }
        return try {
            let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
            root.put("statePath", JsonString(path.toString()))
            root.put("persistenceEnabled", true.toJsonValue())
            root.put("downloadEnabled", this.config.media.downloadEnabled.toJsonValue())
            root.put("mediaMaxBytes", this.effectiveMediaMaxBytes().toJsonValue())
            root.put("allowedMimes", this.mediaAllowedMimesJson())
            root.put("albumPolicy", JsonString(this.effectiveMediaAlbumPolicy()))
            root.put("warnOnDownloadFailure", this.config.media.warnOnDownloadFailure.toJsonValue())
            root.put("accountId", JsonString(this.effectiveAccountId()))
            root
        } catch (_: Exception) {
            let empty = JsonObject()
            empty.put("statePath", JsonString(path.toString()))
            empty.put("persistenceEnabled", true.toJsonValue())
            empty.put("downloadEnabled", this.config.media.downloadEnabled.toJsonValue())
            empty.put("mediaMaxBytes", this.effectiveMediaMaxBytes().toJsonValue())
            empty.put("allowedMimes", this.mediaAllowedMimesJson())
            empty.put("albumPolicy", JsonString(this.effectiveMediaAlbumPolicy()))
            empty.put("warnOnDownloadFailure", this.config.media.warnOnDownloadFailure.toJsonValue())
            empty.put("accountId", JsonString(this.effectiveAccountId()))
            empty.put("lastPersistedMediaId", JsonString(""))
            empty.put("lastMedia", JsonObject())
            empty
        }
    }

    private func persistInboundMedia(
        info: TelegramInboundMediaInfo,
        peerId!: String = "",
        messageId!: String = "",
        relation!: String = "",
        replyToMessageId!: String = "",
        getFileRaw!: String = "",
        downloadRaw!: String = ""
    ): JsonObject {
        let normalizedKind = info.kind.trimAscii().toAsciiLower()
        let normalizedFileId = info.fileId.trimAscii()
        if (normalizedKind.isEmpty() || normalizedFileId.isEmpty()) {
            return JsonObject()
        }
        var filePath = ""
        var downloadPath = ""
        var downloaded = false
        var skippedReason = ""
        var effectiveMime = info.mimeType.trimAscii().toAsciiLower()
        var effectiveSize = info.fileSize
        if (!this.config.media.downloadEnabled) {
            skippedReason = "download_disabled"
        } else if (!this.mediaMimeAllowed(effectiveMime)) {
            skippedReason = "mime_not_allowed"
        } else if (this.mediaSizeExceedsLimit(effectiveSize)) {
            skippedReason = "size_limit_exceeded"
        }
        if (skippedReason.isEmpty()) {
            let resolvedGetFileRaw = if (!getFileRaw.trimAscii().isEmpty()) {
                getFileRaw
            } else {
                this.tryTelegramGetFile(normalizedFileId)
            }
            if (!resolvedGetFileRaw.trimAscii().isEmpty()) {
                filePath = this.parseTelegramFilePath(resolvedGetFileRaw)
                let getFileSize = this.parseTelegramFileSize(resolvedGetFileRaw)
                if (getFileSize > 0) {
                    effectiveSize = getFileSize
                }
            }
            if (this.mediaSizeExceedsLimit(effectiveSize)) {
                skippedReason = "size_limit_exceeded"
            } else if (!filePath.isEmpty() && !this.isSafeTelegramFilePath(filePath) && this.trustedLocalTelegramFilePath(filePath).isEmpty()) {
                skippedReason = "unsafe_file_path"
            } else if (!filePath.isEmpty()) {
                let resolvedDownloadRaw = if (!downloadRaw.trimAscii().isEmpty()) {
                    downloadRaw.toArray()
                } else {
                    this.tryTelegramDownloadFile(filePath)
                }
                if (!resolvedDownloadRaw.isEmpty()) {
                    if (this.mediaSizeExceedsLimit(Int64(resolvedDownloadRaw.size))) {
                        skippedReason = "download_size_limit_exceeded"
                    } else {
                        downloadPath = this.persistDownloadedMediaBytes(
                            info,
                            normalizedFileId,
                            filePath,
                            resolvedDownloadRaw,
                            messageId: messageId
                        )
                        downloaded = !downloadPath.isEmpty()
                    }
                }
            }
        }
        let accountId = this.effectiveAccountId()
        let createdAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let mediaId = this.telegramMediaRecordId(
            accountId,
            peerId,
            messageId,
            normalizedKind,
            normalizedFileId
        )
        let eligibleFor = this.telegramMediaEligibility(info)
        let relativePath = this.relativeTelegramMediaPath(downloadPath)

        let lastMedia = JsonObject()
        lastMedia.put("mediaId", JsonString(mediaId))
        lastMedia.put("channel", JsonString("telegram"))
        lastMedia.put("accountId", JsonString(accountId))
        lastMedia.put("peerId", JsonString(peerId.trimAscii()))
        lastMedia.put("messageId", JsonString(messageId.trimAscii()))
        lastMedia.put("relation", JsonString(if (relation.trimAscii().isEmpty()) { "current" } else { relation.trimAscii() }))
        lastMedia.put("replyToMessageId", JsonString(replyToMessageId.trimAscii()))
        lastMedia.put("mediaKind", JsonString(normalizedKind))
        lastMedia.put("kind", JsonString(normalizedKind))
        lastMedia.put("fileId", JsonString(normalizedFileId))
        lastMedia.put("fileUniqueId", JsonString(info.fileUniqueId))
        lastMedia.put("telegramFilePath", JsonString(filePath))
        lastMedia.put("originalFileName", JsonString(info.fileName))
        lastMedia.put("mimeType", JsonString(effectiveMime))
        lastMedia.put("fileSize", effectiveSize.toJsonValue())
        lastMedia.put("fileName", JsonString(info.fileName))
        lastMedia.put("mediaGroupId", JsonString(info.mediaGroupId))
        lastMedia.put("albumPolicy", JsonString(this.effectiveMediaAlbumPolicy()))
        lastMedia.put("caption", JsonString(info.caption.trimAscii()))
        lastMedia.put("stickerEmoji", JsonString(info.stickerEmoji.trimAscii()))
        lastMedia.put("stickerSetName", JsonString(info.stickerSetName.trimAscii()))
        lastMedia.put("stickerAnimated", info.stickerIsAnimated.toJsonValue())
        lastMedia.put("stickerVideo", info.stickerIsVideo.toJsonValue())
        lastMedia.put("filePath", JsonString(filePath))
        lastMedia.put("localPath", JsonString(downloadPath))
        lastMedia.put("relativePath", JsonString(relativePath))
        lastMedia.put("downloaded", downloaded.toJsonValue())
        lastMedia.put("downloadPath", JsonString(downloadPath))
        lastMedia.put("skippedReason", JsonString(skippedReason))
        lastMedia.put("eligibleFor", JsonString(eligibleFor))
        let transcript = this.tryTranscribeTelegramMedia(normalizedKind, downloadPath, effectiveMime)
        if (!transcript.isEmpty()) {
            lastMedia.put("transcript", JsonString(transcript))
            lastMedia.put("asrStatus", JsonString("transcribed"))
        } else if (normalizedKind == "voice" || normalizedKind == "audio") {
            lastMedia.put("asrStatus", JsonString(if (downloaded) { "ready" } else { "metadata-only" }))
        }
        lastMedia.put("createdAtMs", createdAtMs.toJsonValue())
        lastMedia.put("persistedAtMs", createdAtMs.toJsonValue())
        let root = this.readMediaState()
        let records = this.readMediaRecords(root)
        records.add(lastMedia)
        root.put("accountId", JsonString(accountId))
        root.put("downloadEnabled", this.config.media.downloadEnabled.toJsonValue())
        root.put("mediaMaxBytes", this.effectiveMediaMaxBytes().toJsonValue())
        root.put("allowedMimes", this.mediaAllowedMimesJson())
        root.put("albumPolicy", JsonString(this.effectiveMediaAlbumPolicy()))
        root.put("warnOnDownloadFailure", this.config.media.warnOnDownloadFailure.toJsonValue())
        root.put("lastPersistedMediaId", JsonString(normalizedFileId))
        root.put("lastMediaRecordId", JsonString(mediaId))
        root.put("lastMedia", lastMedia)
        root.put("records", records)
        File.writeTo(this.mediaStatePath(), root.toJsonString().toArray())
        root
    }

    private func readMediaRecords(root: JsonObject): JsonArray {
        match (root.get("records")) {
            case Some(v) =>
                try {
                    v.asArray()
                } catch (_: Exception) {
                    JsonArray([])
                }
            case None => JsonArray([])
        }
    }

    private func readSentMessageState(): JsonObject {
        let path = this.sentMessageStatePath()
        if (!exists(path)) {
            let empty = JsonObject()
            empty.put("statePath", JsonString(path.toString()))
            empty.put("persistenceEnabled", true.toJsonValue())
            empty.put("accountId", JsonString(this.effectiveAccountId()))
            empty.put("lastMessage", JsonObject())
            empty.put("records", JsonArray([]))
            return empty
        }
        return try {
            let root = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
            root.put("statePath", JsonString(path.toString()))
            root.put("persistenceEnabled", true.toJsonValue())
            root.put("accountId", JsonString(this.effectiveAccountId()))
            root
        } catch (_e: Exception) {
            let empty = JsonObject()
            empty.put("statePath", JsonString(path.toString()))
            empty.put("persistenceEnabled", true.toJsonValue())
            empty.put("accountId", JsonString(this.effectiveAccountId()))
            empty.put("lastMessage", JsonObject())
            empty.put("records", JsonArray([]))
            empty
        }
    }

    private func readSentMessageRecords(root: JsonObject): JsonArray {
        match (root.get("records")) {
            case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
    }

    private func recordSentTelegramMessage(message: OutboundMessage, telegramMessageId: String): Unit {
        let id = telegramMessageId.trimAscii()
        if (id.isEmpty()) {
            return
        }
        try {
            let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
            let root = this.readSentMessageState()
            let record = JsonObject()
            record.put("channel", JsonString("telegram"))
            record.put("accountId", JsonString(this.effectiveAccountId()))
            record.put("peerId", JsonString(message.peerId.trimAscii()))
            record.put("messageId", JsonString(id))
            record.put("textPreview", JsonString(this.truncateForTelegramState(message.text.trimAscii(), 240)))
            record.put("createdAtMs", nowMs.toJsonValue())
            match (message.replyToMessageId) {
                case Some(target) => record.put("replyToMessageId", JsonString(target.trimAscii()))
                case None => record.put("replyToMessageId", JsonString(""))
            }
            record.put("replyInThread", message.replyInThread.toJsonValue())
            let records = this.readSentMessageRecords(root)
            records.add(record)
            root.put("lastMessage", record)
            root.put("records", this.capJsonArrayTail(records, 100))
            File.writeTo(this.sentMessageStatePath(), root.toJsonString().toArray())
        } catch (_e: Exception) {
            ()
        }
    }

    private func truncateForTelegramState(text: String, maxChars: Int64): String {
        if (maxChars <= 0 || text.size <= maxChars) {
            return text
        }
        text[..maxChars]
    }

    private func capJsonArrayTail(items: JsonArray, maxItems: Int64): JsonArray {
        if (maxItems <= 0 || items.size() <= maxItems) {
            return items
        }
        let out = JsonArray([])
        var idx = items.size() - maxItems
        while (idx < items.size()) {
            out.add(items[idx])
            idx += 1
        }
        out
    }

    private func telegramMediaRecordId(accountId: String, peerId: String, messageId: String, kind: String, fileId: String): String {
        let account = if (accountId.trimAscii().isEmpty()) { TELEGRAM_DEFAULT_ACCOUNT_ID } else { accountId.trimAscii() }
        let peer = if (peerId.trimAscii().isEmpty()) { "unknown-peer" } else { peerId.trimAscii() }
        let message = if (messageId.trimAscii().isEmpty()) { "unknown-message" } else { messageId.trimAscii() }
        "tg_${this.safeStateSegment(account)}_${this.safeStateSegment(peer)}_${this.safeStateSegment(message)}_${this.safeStateSegment(kind)}_${this.safeStateSegment(fileId)}"
    }

    private func telegramMediaEligibility(info: TelegramInboundMediaInfo): String {
        let kind = info.kind.trimAscii().toAsciiLower()
        if (kind == "photo" || (kind == "sticker" && !info.stickerIsAnimated && !info.stickerIsVideo)) {
            return "vision"
        }
        if (kind == "voice" || kind == "audio") {
            return "transcription"
        }
        if (kind == "document") {
            return "file-context"
        }
        "metadata-only"
    }

    private func tryTranscribeTelegramMedia(kind: String, downloadPath: String, mimeType: String): String {
        let normalizedKind = kind.trimAscii().toAsciiLower()
        if (normalizedKind != "voice" && normalizedKind != "audio") {
            return ""
        }
        let path = downloadPath.trimAscii()
        if (path.isEmpty()) {
            return ""
        }
        match (telegramAsrRunnerOverride) {
            case Some(runner) =>
                try { runner(path, mimeType.trimAscii().toAsciiLower()).trimAscii() } catch (_e: Exception) { "" }
            case None => gatewayMediaTranscribeAudioPathForRuntime(path, mimeType)
        }
    }

    private func maybeWarnInboundMediaDownloadFailure(peerId: String, messageId: String, mediaState: JsonObject): Unit {
        if (!this.config.media.warnOnDownloadFailure) {
            return
        }
        let lastMedia = this.readObjectField(mediaState, "lastMedia")
        let downloaded = this.readBoolFieldOpt(lastMedia, "downloaded") == Some(true)
        let reason = this.readStringField(lastMedia, "skippedReason").trimAscii()
        if (downloaded || reason.isEmpty()) {
            return
        }
        let kind = this.readStringField(lastMedia, "mediaKind").trimAscii()
        let text = "Telegram ${kind} media was received but was not downloaded locally. reason=${reason}; messageId=${messageId}"
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("text")
        body["peer"] = JsonString(peerId.trimAscii())
        body["chat_id"] = JsonString(this.normalizePeerId(peerId.trimAscii()))
        body["text"] = JsonString(this.telegramRenderHtml(text))
        body["plain_text"] = JsonString(text)
        body["parse_mode"] = JsonString("HTML")
        body["disable_web_page_preview"] = true.toJsonValue()
        let previousError = this.lastSendError
        let _ = this.sendPayloadToTelegram(body)
        this.lastSendError = previousError
    }

    private func relativeTelegramMediaPath(path: String): String {
        let normalized = path.trimAscii()
        if (normalized.isEmpty()) {
            return ""
        }
        let mediaRoot = this.mediaDownloadDir().toString()
        if (normalized == mediaRoot) {
            return ""
        }
        let prefix = mediaRoot + "/"
        if (normalized.startsWith(prefix)) {
            return normalized[prefix.size..]
        }
        ""
    }

    private func tryTelegramGetFile(fileId: String): String {
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            return ""
        }
        let apiRoot = this.normalizeApiRoot()
        let attempts = if (this.config.network.getFileRetryCount <= 0) { 1 } else { this.config.network.getFileRetryCount }
        var last = ""
        for (_i in 0..attempts) {
            last = this.tryTelegramGet("${apiRoot}/bot${token}/getFile?file_id=${fileId}")
            let parsed = this.parseTelegramProbeResult(last)
            if (this.readJsonBoolField(parsed, "ok", false)) {
                return last
            }
            let err = this.readStringField(parsed, "error").toAsciiLower()
            if (err.contains("file is too big") || err.contains("too big") || err.contains("forbidden") || err.contains("unauthorized")) {
                return last
            }
        }
        last
    }

    private func tryTelegramGetChat(chatId: String): JsonObject {
        let out = JsonObject()
        out.put("ok", false.toJsonValue())
        let token = this.effectiveBotToken()
        let normalizedChatId = chatId.trimAscii()
        if (token.isEmpty() || normalizedChatId.isEmpty()) {
            out.put("error", JsonString("missing-token-or-chat-id"))
            return out
        }
        let raw = this.tryTelegramGet("${this.normalizeApiRoot()}/bot${token}/getChat?chat_id=${normalizedChatId}")
        let parsed = this.parseTelegramProbeResult(raw)
        if (!this.readJsonBoolField(parsed, "ok", false)) {
            out.put("error", JsonString(this.readStringField(parsed, "error")))
            return out
        }
        let result = this.readObjectField(parsed, "result")
        out.put("ok", true.toJsonValue())
        out.put("chatId", JsonString(this.readIntStringField(result, "id")))
        out.put("type", JsonString(this.readStringField(result, "type")))
        out.put("username", JsonString(this.readStringField(result, "username")))
        out.put("title", JsonString(this.readStringField(result, "title")))
        out.put("isForum", (this.readBoolFieldOpt(result, "is_forum") == Some(true)).toJsonValue())
        let reactions = JsonArray([])
        match (result.get("available_reactions")) {
            case Some(v) =>
                try {
                    let arr = v.asArray()
                    for (item in arr.getItems()) {
                        try {
                            let obj = item.asObject()
                            let emoji = this.readStringField(obj, "emoji").trimAscii()
                            if (!emoji.isEmpty()) {
                                reactions.add(JsonString(emoji))
                            }
                        } catch (_e: Exception) {
                            try {
                                let emoji = item.asString().getValue().trimAscii()
                                if (!emoji.isEmpty()) {
                                    reactions.add(JsonString(emoji))
                                }
                            } catch (_e2: Exception) {
                                ()
                            }
                        }
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        out.put("availableReactions", reactions)
        out
    }

    private func parseTelegramFilePath(raw: String): String {
        let parsed = this.parseTelegramProbeResult(raw)
        if (!this.readJsonBoolField(parsed, "ok", false)) {
            return ""
        }
        match (parsed.get("result")) {
            case Some(v) =>
                try {
                    let result = v.asObject()
                    this.readStringField(result, "file_path").trimAscii()
                } catch (_: Exception) {
                    ""
                }
            case None => ""
        }
    }

    private func parseTelegramFileSize(raw: String): Int64 {
        let parsed = this.parseTelegramProbeResult(raw)
        if (!this.readJsonBoolField(parsed, "ok", false)) {
            return 0
        }
        match (parsed.get("result")) {
            case Some(v) =>
                try {
                    let result = v.asObject()
                    this.readJsonIntField(result, "file_size", 0)
                } catch (_: Exception) {
                    0
                }
            case None => 0
        }
    }

    private func tryTelegramDownloadFile(filePath: String): Array<Byte> {
        let normalized = filePath.trimAscii()
        let token = this.effectiveBotToken()
        if (normalized.isEmpty() || token.isEmpty()) {
            return []
        }
        let localPath = this.trustedLocalTelegramFilePath(normalized)
        if (!localPath.isEmpty()) {
            try {
                return File.readFrom(Path(localPath))
            } catch (_e: Exception) {
                return []
            }
        }
        let url = this.normalizeApiRoot() + "/file/bot${token}/${normalized}"
        match (this.telegramGetBytes(url, accept: "*/*", context: "downloadFile")) {
            case Some(raw) => raw
            case None => []
        }
    }

    private func persistDownloadedMediaBytes(
        info: TelegramInboundMediaInfo,
        fileId: String,
        telegramFilePath: String,
        raw: Array<Byte>,
        messageId!: String = ""
    ): String {
        if (raw.isEmpty()) {
            return ""
        }
        let dayDir = this.mediaDownloadDir().join(DateTime.now().format("yyyy-MM-dd"))
        if (!exists(dayDir)) {
            Directory.create(dayDir, recursive: true)
        }
        let messageSegment = this.safeStateSegment(if (messageId.trimAscii().isEmpty()) { "unknown-message" } else { messageId.trimAscii() })
        let messageDir = dayDir.join(messageSegment)
        if (!exists(messageDir)) {
            Directory.create(messageDir, recursive: true)
        }
        let fileName = this.uniqueTelegramMediaFileName(
            messageDir,
            info,
            fileId,
            telegramFilePath
        )
        let path = messageDir.join(fileName)
        File.writeTo(path, raw)
        path.toString()
    }

    private func uniqueTelegramMediaFileName(dir: Path, info: TelegramInboundMediaInfo, fileId: String, telegramFilePath: String): String {
        let preferred = this.preferredTelegramMediaFileName(info, fileId, telegramFilePath)
        if (!exists(dir.join(preferred))) {
            return preferred
        }
        let ext = this.fileExtensionFromName(preferred)
        let stem = if (ext.isEmpty()) { preferred } else { preferred[..preferred.size - ext.size - 1] }
        var i: Int64 = 2
        while (i < 10000) {
            let candidate = if (ext.isEmpty()) { "${stem}-${i}" } else { "${stem}-${i}.${ext}" }
            if (!exists(dir.join(candidate))) {
                return candidate
            }
            i += 1
        }
        if (ext.isEmpty()) { "${stem}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}" } else { "${stem}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}.${ext}" }
    }

    private func preferredTelegramMediaFileName(info: TelegramInboundMediaInfo, fileId: String, telegramFilePath: String): String {
        var candidate = this.safeTelegramMediaFileName(info.fileName)
        if (candidate.isEmpty()) {
            candidate = this.safeTelegramMediaFileName(this.fileNameFromTelegramFilePath(telegramFilePath))
        }
        let ext = this.telegramMediaExtension(info, telegramFilePath)
        if (candidate.isEmpty()) {
            let safeId = this.safeStateSegment(fileId)
            return if (ext.isEmpty()) { safeId } else { "${safeId}.${ext}" }
        }
        if (!ext.isEmpty() && this.fileExtensionFromName(candidate).isEmpty()) {
            return "${candidate}.${ext}"
        }
        candidate
    }

    private func safeTelegramMediaFileName(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) {
            return ""
        }
        let name = this.fileNameFromTelegramFilePath(trimmed)
        let out = StringBuilder()
        for (r in name.runes()) {
            if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'.' || r == r'_' || r == r'-') {
                out.append(r)
            } else {
                out.append(r'_')
            }
        }
        let normalized = out.toString().trimAscii()
        if (normalized.isEmpty() || normalized == "." || normalized == "..") {
            return ""
        }
        normalized
    }

    private func fileNameFromTelegramFilePath(pathText: String): String {
        let normalized = pathText.trimAscii().replace("\\", "/")
        if (normalized.isEmpty()) {
            return ""
        }
        match (normalized.lastIndexOf("/")) {
            case Some(idx) =>
                let name = normalized[idx + 1..].trimAscii()
                if (name == "." || name == "..") { "" } else { name }
            case None =>
                if (normalized == "." || normalized == "..") { "" } else { normalized }
        }
    }

    private func telegramMediaExtension(info: TelegramInboundMediaInfo, telegramFilePath: String): String {
        let fromName = this.fileExtensionFromName(info.fileName)
        if (!fromName.isEmpty()) {
            return fromName
        }
        let fromPath = this.fileExtensionFromName(telegramFilePath)
        if (!fromPath.isEmpty()) {
            return fromPath
        }
        this.fileExtensionFromMime(info.mimeType)
    }

    private func fileExtensionFromName(name: String): String {
        let fileName = this.fileNameFromTelegramFilePath(name)
        match (fileName.lastIndexOf(".")) {
            case Some(idx) =>
                if (idx <= 0 || idx + 1 >= fileName.size) {
                    return ""
                }
                fileName[idx + 1..].trimAscii().toAsciiLower()
            case None => ""
        }
    }

    private func fileExtensionFromMime(mime: String): String {
        let normalized = mime.trimAscii().toAsciiLower()
        if (normalized == "image/jpeg" || normalized == "image/jpg") { return "jpg" }
        if (normalized == "image/png") { return "png" }
        if (normalized == "image/gif") { return "gif" }
        if (normalized == "image/webp") { return "webp" }
        if (normalized == "application/pdf") { return "pdf" }
        if (normalized == "text/plain") { return "txt" }
        if (normalized == "application/json") { return "json" }
        if (normalized == "audio/ogg") { return "ogg" }
        if (normalized == "audio/mpeg") { return "mp3" }
        if (normalized == "audio/mp4") { return "m4a" }
        if (normalized == "video/mp4") { return "mp4" }
        ""
    }

    private func mediaAllowedMimesJson(): JsonArray {
        let out = JsonArray([])
        for (mime in this.config.media.allowedMimes) {
            let normalized = mime.trimAscii().toAsciiLower()
            if (!normalized.isEmpty()) {
                out.add(JsonString(normalized))
            }
        }
        out
    }

    private func mediaMimeAllowed(mime: String): Bool {
        let normalized = mime.trimAscii().toAsciiLower()
        if (this.config.media.allowedMimes.isEmpty() || normalized.isEmpty()) {
            return true
        }
        for (allowed in this.config.media.allowedMimes) {
            let one = allowed.trimAscii().toAsciiLower()
            if (one == "*" || one == normalized) {
                return true
            }
            if (one.endsWith("/*")) {
                let prefix = one[..one.size - 1]
                if (normalized.startsWith(prefix)) {
                    return true
                }
            }
        }
        false
    }

    private func effectiveMediaMaxBytes(): Int64 {
        if (this.config.media.mediaMaxBytes > 0) {
            return this.config.media.mediaMaxBytes
        }
        20 * 1024 * 1024
    }

    private func mediaSizeExceedsLimit(size: Int64): Bool {
        size > 0 && size > this.effectiveMediaMaxBytes()
    }

    private func effectiveMediaAlbumPolicy(): String {
        let normalized = this.config.media.albumPolicy.trimAscii().toAsciiLower()
        if (normalized == "single-largest" || normalized == "first" || normalized == "metadata-only") {
            return normalized
        }
        "single-largest"
    }

    private func isSafeTelegramFilePath(filePath: String): Bool {
        let normalized = filePath.trimAscii()
        if (normalized.isEmpty() ||
            normalized.startsWith("/") ||
            normalized.startsWith("\\") ||
            normalized.contains("://") ||
            normalized.contains("\\")) {
            return false
        }
        for (part in normalized.split("/")) {
            let seg = part.trimAscii()
            if (seg.isEmpty() || seg == "." || seg == "..") {
                return false
            }
        }
        true
    }

    private func trustedLocalTelegramFilePath(filePath: String): String {
        let normalized = filePath.trimAscii()
        if (normalized.isEmpty() || !normalized.startsWith("/")) {
            return ""
        }
        if (this.config.media.trustedLocalFileRoots.isEmpty()) {
            return ""
        }
        let candidate = try { canonicalize(Path(normalized)).toString() } catch (_e: Exception) { return "" }
        for (root in this.config.media.trustedLocalFileRoots) {
            let rootText = root.trimAscii()
            if (rootText.isEmpty()) {
                continue
            }
            let rootPath = try { canonicalize(Path(rootText)).toString() } catch (_e: Exception) { continue }
            if (candidate == rootPath || candidate.startsWith(rootPath + "/")) {
                return candidate
            }
        }
        ""
    }

    private func readJsonIntField(obj: JsonObject, key: String, defaultValue: Int64): Int64 {
        match (obj.get(key)) {
            case Some(v) =>
                try { Int64(v.asInt().getValue()) } catch (_e1: Exception) {
                    try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_e2: Exception) { defaultValue }
                }
            case None => defaultValue
        }
    }

    private func readJsonBoolField(obj: JsonObject, key: String, defaultValue: Bool): Bool {
        match (obj.get(key)) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
            case None => defaultValue
        }
    }

    private func readJsonArrayField(obj: JsonObject, key: String): JsonArray {
        match (obj.get(key)) {
            case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
    }

    private func isTelegramConflictError(root: JsonObject, desc: String): Bool {
        let lower = desc.toAsciiLower()
        if (lower.contains("conflict") || lower.contains("409")) {
            return true
        }
        match (root.get("error_code")) {
            case Some(v) =>
                try { return v.asInt().getValue() == 409 } catch (_: Exception) { () }
            case None => ()
        }
        false
    }

    private func shouldRetryWithoutParseMode(): Bool {
        let reason = this.lastSendError.toAsciiLower()
        reason.contains("parse entities") || reason.contains("can't parse")
    }

    private func syncNativeCommands(): Bool {
        this.nativeCommandsLastSyncAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let rows = this.resolvedTelegramCommandMenuForTelegramApi()
        this.nativeCommandsLastSyncCommandCount = rows.size
        this.nativeCommandsLastSyncSkipped = false
        this.nativeCommandsLastSyncRetryCount = 0
        this.nativeCommandsLastSyncTrimmedCount = 0
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            this.setNativeCommandsSyncError("bot token is empty")
            return false
        }
        var payload = this.buildNativeCommandsPayloadForRows(rows)
        let payloadHash = payload.toJsonString()
        if (
            !payloadHash.isEmpty() &&
            payloadHash == this.nativeCommandsLastSyncHash &&
            (this.nativeCommandsLastSyncStatus == "ok" || this.nativeCommandsLastSyncStatus == "skipped")
        ) {
            this.nativeCommandsLastSyncStatus = "skipped"
            this.nativeCommandsLastSyncError = ""
            this.nativeCommandsLastSyncSkipped = true
            return true
        }
        let deleteResponse = this.telegramJsonPost(
            this.normalizeApiRoot() + "/bot${token}/deleteMyCommands",
            JsonObject(),
            context: "deleteMyCommands"
        )
        match (deleteResponse) {
            case Some(raw) =>
                if (!this.parseTelegramBoolSuccess(raw, missingDetail: "telegram deleteMyCommands returned ok=false")) {
                    this.setNativeCommandsSyncError(this.lastSendError)
                    LogUtils.info("Telegram deleteMyCommands failed: ${this.lastSendError}")
                    return false
                }
            case None =>
                this.setNativeCommandsSyncError("empty http response")
                LogUtils.info("Telegram deleteMyCommands failed: ${this.lastSendError}")
                return false
        }
        let responseOpt = this.telegramJsonPost(
            this.normalizeApiRoot() + "/bot${token}/setMyCommands",
            payload,
            context: "setMyCommands"
        )
        var responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.setNativeCommandsSyncError("empty http response")
                LogUtils.info("Telegram setMyCommands failed: ${this.lastSendError}")
                return false
        }
        var ok = this.parseTelegramBoolSuccess(responseRaw, missingDetail: "telegram setMyCommands returned ok=false")
        if (!ok && this.shouldRetryNativeCommandMenuWithTrim()) {
            this.nativeCommandsLastSyncRetryCount += 1
            let trimmedRows = this.trimTelegramCommandRowsForRetry(rows)
            this.nativeCommandsLastSyncTrimmedCount = rows.size - trimmedRows.size
            this.nativeCommandsLastSyncCommandCount = trimmedRows.size
            payload = this.buildNativeCommandsPayloadForRows(trimmedRows)
            match (this.telegramJsonPost(
                this.normalizeApiRoot() + "/bot${token}/setMyCommands",
                payload,
                context: "setMyCommands:retry"
            )) {
                case Some(retryRaw) =>
                    responseRaw = retryRaw
                    ok = this.parseTelegramBoolSuccess(responseRaw, missingDetail: "telegram setMyCommands retry returned ok=false")
                case None =>
                    this.setNativeCommandsSyncError("empty http response")
                    LogUtils.info("Telegram setMyCommands retry failed: ${this.lastSendError}")
                    return false
            }
        }
        if (!ok) {
            this.setNativeCommandsSyncError(this.lastSendError)
            LogUtils.info("Telegram setMyCommands failed: ${this.lastSendError}")
        } else {
            this.nativeCommandsLastSyncStatus = "ok"
            this.nativeCommandsLastSyncError = ""
            this.nativeCommandsLastSyncHash = payloadHash
        }
        ok
    }

    private func shouldRetryNativeCommandMenuWithTrim(): Bool {
        let reason = this.lastSendError.toAsciiLower()
        reason.contains("bot_commands_too_much") ||
            reason.contains("commands_too_much") ||
            reason.contains("commands too much") ||
            reason.contains("too many commands")
    }

    private func trimTelegramCommandRowsForRetry(rows: Array<(String, String)>): Array<(String, String)> {
        let out = ArrayList<(String, String)>()
        let limit = if (rows.size > 80) { 80 } else { rows.size }
        var i: Int64 = 0
        while (i < limit) {
            out.add(rows[i])
            i += 1
        }
        out.toArray()
    }

    private func setNativeCommandsSyncError(message: String): Unit {
        this.setLastSendError(message)
        this.nativeCommandsLastSyncStatus = "error"
        this.nativeCommandsLastSyncError = this.lastSendError
    }

    private func buildNativeCommandDiagnostics(): JsonObject {
        let out = JsonObject()
        let nativeMode = this.config.commandsNative.trimAscii().toAsciiLower()
        let builtinsEnabled = nativeMode != "off" && nativeMode != "false" && nativeMode != "disabled"
        out.put("mode", JsonString(if (nativeMode.isEmpty()) { "auto" } else { nativeMode }))
        out.put("builtinsEnabled", builtinsEnabled.toJsonValue())
        out.put("customCommandCount", this.config.customCommands.size.toJsonValue())
        out.put("resolvedCommandCount", this.resolvedTelegramCommandMenu().size.toJsonValue())
        out.put("apiCommandCount", this.resolvedTelegramCommandMenuForTelegramApi().size.toJsonValue())
        out.put("apiCommandLimit", 100.toJsonValue())
        out.put("lastSyncStatus", JsonString(this.nativeCommandsLastSyncStatus))
        out.put("lastSyncError", JsonString(this.nativeCommandsLastSyncError))
        out.put("lastSyncAtMs", this.nativeCommandsLastSyncAtMs.toJsonValue())
        out.put("lastSyncCommandCount", this.nativeCommandsLastSyncCommandCount.toJsonValue())
        out.put("lastSyncSkipped", this.nativeCommandsLastSyncSkipped.toJsonValue())
        out.put("lastSyncRetryCount", this.nativeCommandsLastSyncRetryCount.toJsonValue())
        out.put("lastSyncTrimmedCount", this.nativeCommandsLastSyncTrimmedCount.toJsonValue())
        out
    }

    private func buildNativeCommandsPayload(): JsonObject {
        this.buildNativeCommandsPayloadForRows(this.resolvedTelegramCommandMenuForTelegramApi())
    }

    private func buildNativeCommandsPayloadForRows(rows: Array<(String, String)>): JsonObject {
        let commands = JsonArray([])
        for ((command, description) in rows) {
            let item = JsonObject()
            item.put("command", JsonString(command))
            item.put("description", JsonString(this.telegramCommandDescription(description)))
            commands.add(item)
        }
        let obj = JsonObject()
        obj.put("commands", commands)
        obj
    }

    private func resolvedTelegramCommandMenu(): Array<(String, String)> {
        let rows = ArrayList<(String, String)>()
        let seen = HashMap<String, Bool>()
        let nativeMode = this.config.commandsNative.trimAscii().toAsciiLower()
        if (nativeMode != "off" && nativeMode != "false" && nativeMode != "disabled") {
            for ((command, description) in [
                ("help", "Show help"),
                ("status", "Show status"),
                ("commands", "Show commands"),
                ("tools", "Show tools"),
                ("whoami", "Show Telegram identity"),
                ("models", "Switch model"),
                ("model", "Show current model"),
                ("subagents", "Manage subagents"),
                ("sessions", "Manage sessions"),
                ("session", "Show current session"),
                ("focus", "Bind this conversation to a session"),
                ("unfocus", "Remove this conversation binding"),
                ("agents", "Show bound sessions"),
                ("new", "Start new session"),
                ("reset", "Reset session"),
                ("compact", "Compact session"),
                ("think", "Set reasoning"),
                ("reasoning", "Set reasoning"),
                ("fast", "Fast mode"),
                ("verbose", "Verbose mode"),
                ("approvals", "Review approvals"),
                ("activation", "Set activation mode"),
                ("pair", "Manage pairing")
            ]) {
                rows.add((command, description))
                seen[command] = true
            }
        }
        for ((command, description) in gatewayOpenClawPluginSidecarCommandCatalogForMenu()) {
            let normalizedCommand = this.normalizeTelegramCommandName(command)
            let normalizedDescription = description.trimAscii()
            if (normalizedCommand.isEmpty() || normalizedDescription.isEmpty()) {
                continue
            }
            if (seen.contains(normalizedCommand)) {
                continue
            }
            rows.add((normalizedCommand, normalizedDescription))
            seen[normalizedCommand] = true
        }
        for (custom in this.config.customCommands) {
            let normalizedCommand = this.normalizeTelegramCommandName(custom.command)
            let normalizedDescription = custom.description.trimAscii()
            if (normalizedCommand.isEmpty() || normalizedDescription.isEmpty()) {
                continue
            }
            if (seen.contains(normalizedCommand)) {
                continue
            }
            rows.add((normalizedCommand, normalizedDescription))
            seen[normalizedCommand] = true
        }
        rows.toArray()
    }

    private func resolvedTelegramCommandMenuForTelegramApi(): Array<(String, String)> {
        let rows = ArrayList<(String, String)>()
        for (row in this.resolvedTelegramCommandMenu()) {
            if (rows.size >= 100) {
                break
            }
            rows.add(row)
        }
        rows.toArray()
    }

    private func telegramCommandDescription(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) {
            return "Command"
        }
        if (trimmed.size <= 256) {
            return trimmed
        }
        trimmed[..256]
    }

    private func normalizeTelegramCommandName(raw: String): String {
        var normalized = raw.trimAscii().toAsciiLower()
        while (normalized.startsWith("/")) {
            normalized = normalized[1..]
        }
        if (normalized.isEmpty() || normalized.size > 32) {
            return ""
        }
        for (r in normalized.toRuneArray()) {
            let ok = (r >= r'a' && r <= r'z') ||
                (r >= r'0' && r <= r'9') ||
                r == r'_'
            if (!ok) {
                return ""
            }
        }
        normalized
    }

    private func normalizeInboundTelegramCommandText(raw: String): String {
        let trimmed = raw.trimAscii()
        if (!trimmed.startsWith("/")) {
            return trimmed
        }
        let parts = trimmed.split(" ", 2)
        let token = parts[0]
        let tail = if (parts.size > 1) { parts[1].trimAscii() } else { "" }
        let normalizedToken = match (token.indexOf("@")) {
            case Some(idx) =>
                if (idx > 1) { token[..idx] } else { token }
            case None => token
        }
        if (tail.isEmpty()) {
            return normalizedToken
        }
        "${normalizedToken} ${tail}"
    }

    private func buildSendPayloads(message: OutboundMessage): Array<HashMap<String, JsonValue>> {
        match (this.detectPollPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectDeletePayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectClearButtonsPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectEditButtonsPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectEditPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectPinPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectReactionPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectChatActionPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectInlineKeyboardPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectDraftPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectApprovalPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectMediaGroupPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectEditMediaPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectStickerPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectPhotoPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectDocumentPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectAudioPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectVoicePayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectVideoPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectVideoNotePayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectTopicCreatePayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectTopicEditPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        let chunks = this.chunkTelegramText(message.text)
        let out = ArrayList<HashMap<String, JsonValue>>()
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        for (i in 0..chunks.size) {
            let body = HashMap<String, JsonValue>()
            body["kind"] = JsonString("text")
            body["peer"] = JsonString(normalizedPeer)
            body["chat_id"] = JsonString(chatId)
            body["text"] = JsonString(this.telegramRenderHtml(chunks[i]))
            body["plain_text"] = JsonString(chunks[i])
            body["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
            body["parse_mode"] = JsonString("HTML")
            this.applyTelegramSilentOption(body)
            if (!threadId.isEmpty() && replyInThread) {
                body["message_thread_id"] = JsonString(threadId)
            }
            if (this.shouldAttachReplyTargetToChunk(i)) {
                this.applyTelegramReplyTarget(body, message)
            }
            out.add(body)
        }
        out.toArray()
    }

    private func buildPollPayload(
        message: OutboundMessage,
        question: String,
        options: Array<String>,
        durationSeconds!: Int64 = 0,
        allowMultiselect!: Bool = false,
        isAnonymous!: Option<Bool> = None<Bool>
    ): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("poll")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["question"] = JsonString(question)
        this.applyTelegramSilentOption(body)
        let optionsJson = JsonArray([])
        for (one in options) {
            optionsJson.add(JsonString(one))
        }
        body["options"] = optionsJson
        if (durationSeconds > 0) {
            body["open_period"] = durationSeconds.toJsonValue()
        }
        if (allowMultiselect) {
            body["allows_multiple_answers"] = true.toJsonValue()
        }
        match (isAnonymous) {
            case Some(v) => body["is_anonymous"] = v.toJsonValue()
            case None => ()
        }
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        body
    }

    private func buildMediaGroupPayload(message: OutboundMessage, items: Array<GatewayMediaGroupItem>): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("media-group")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        let media = JsonArray([])
        for (item in items) {
            let one = JsonObject()
            let kind = this.normalizeMediaGroupType(item.kind, item.fileId)
            one.put("type", JsonString(kind))
            one.put("media", JsonString(item.fileId))
            if (!item.caption.isEmpty()) {
                let escaped = this.telegramRenderHtml(item.caption)
                one.put("caption", JsonString(escaped))
                one.put("parse_mode", JsonString("HTML"))
            }
            media.add(one)
        }
        body["media"] = media
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func buildEditMediaPayload(message: OutboundMessage, targetMessageId: String, kind: String, fileId: String, caption: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("edit-media")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["message_id"] = JsonString(targetMessageId)
        let media = JsonObject()
        media.put("type", JsonString(this.normalizeMediaGroupType(kind, fileId)))
        media.put("media", JsonString(fileId))
        if (!caption.trimAscii().isEmpty()) {
            media.put("caption", JsonString(this.telegramRenderHtml(caption.trimAscii())))
            media.put("parse_mode", JsonString("HTML"))
        }
        body["media"] = media
        body
    }

    private func normalizeMediaGroupType(kind: String, fileId: String): String {
        let normalized = kind.trimAscii().toAsciiLower()
        if (normalized == "photo" || normalized == "video" || normalized == "audio" || normalized == "document" || normalized == "animation") {
            if (normalized == "animation") {
                return "video"
            }
            return normalized
        }
        if (this.telegramRefLooksLikeGif(fileId)) {
            return "video"
        }
        "photo"
    }

    private func buildDeletePayload(message: OutboundMessage, targetMessageId: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("delete")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        body
    }

    private func buildClearButtonsPayload(message: OutboundMessage, targetMessageId: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("clear-buttons")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        let markup = JsonObject()
        markup.put("inline_keyboard", JsonArray([]))
        body["reply_markup"] = markup
        body
    }

    private func buildEditButtonsPayload(message: OutboundMessage, targetMessageId: String, specs: Array<String>): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("edit-buttons")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        let markup = this.telegramInlineKeyboardMarkupFromSpecs(specs)
        if (this.readJsonArrayField(markup, "inline_keyboard").size() <= 0) {
            body["validation_error"] = JsonString("telegram editButtons requires at least one valid button")
            return body
        }
        body["reply_markup"] = markup
        body
    }

    private func buildPinPayload(message: OutboundMessage, targetMessageId: String, unpin!: Bool = false): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString(if (unpin) { "unpin" } else { "pin" })
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        if (!unpin) {
            body["disable_notification"] = true.toJsonValue()
        }
        body
    }

    private func buildEditPayload(message: OutboundMessage, targetMessageId: String, content: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("edit")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        body["text"] = JsonString(this.telegramRenderHtml(content))
        body["plain_text"] = JsonString(content)
        body["parse_mode"] = JsonString("HTML")
        body["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
        body
    }

    private func buildTopicCreatePayload(message: OutboundMessage, title: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("topic-create")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["name"] = JsonString(title)
        body
    }

    private func buildTopicEditPayload(message: OutboundMessage, targetThreadId: String, title: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("topic-edit")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_thread_id"] = JsonString(targetThreadId)
        body["name"] = JsonString(title)
        body
    }

    private func buildReactionPayload(message: OutboundMessage, targetMessageId: String, token: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let effectiveToken = this.telegramReactionFallbackToken(this.normalizePeerId(normalizedPeer), token)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("reaction")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        let reactions = JsonArray([])
        if (!parseGatewayReactionRemove(message.text)) {
            let reaction = JsonObject()
            reaction.put("type", JsonString("emoji"))
            reaction.put("emoji", JsonString(effectiveToken))
            reactions.add(reaction)
        }
        body["reaction"] = reactions
        body
    }

    private func telegramReactionFallbackToken(chatId: String, requested: String): String {
        let token = requested.trimAscii()
        if (token.isEmpty()) {
            return token
        }
        let chatInfo = this.tryTelegramGetChat(chatId)
        if (!this.readJsonBoolField(chatInfo, "ok", false)) {
            return token
        }
        match (chatInfo.get("availableReactions")) {
            case Some(v) =>
                try {
                    let arr = v.asArray()
                    if (arr.size() == 0) {
                        return token
                    }
                    var first = ""
                    for (item in arr.getItems()) {
                        let emoji = try { item.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
                        if (first.isEmpty() && !emoji.isEmpty()) {
                            first = emoji
                        }
                        if (emoji == token) {
                            return token
                        }
                    }
                    if (!first.isEmpty()) {
                        return first
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        token
    }

    private func buildChatActionPayload(message: OutboundMessage, action: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("chat-action")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["action"] = JsonString(this.normalizeTelegramChatAction(action))
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        body
    }

    private func buildInlineKeyboardPayload(message: OutboundMessage, text: String, specs: Array<String>): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("inline-keyboard")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["text"] = JsonString(this.telegramRenderHtml(text))
        body["plain_text"] = JsonString(text)
        body["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
        body["parse_mode"] = JsonString("HTML")
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        let markup = this.telegramInlineKeyboardMarkupFromSpecs(specs)
        let rows = this.readJsonArrayField(markup, "inline_keyboard")
        if (rows.size() <= 0) {
            body["validation_error"] = JsonString("telegram inlineKeyboard requires at least one valid button")
            return body
        }
        body["reply_markup"] = markup
        body
    }

    private func telegramInlineKeyboardMarkupFromSpecs(specs: Array<String>): JsonObject {
        let rows = JsonArray([])
        var current = JsonArray([])
        for (spec0 in specs) {
            let spec = spec0.trimAscii()
            if (spec.isEmpty()) {
                continue
            }
            if (spec == "row" || spec == "---") {
                if (current.size() > 0) {
                    rows.add(current)
                    current = JsonArray([])
                }
                continue
            }
            match (this.inlineKeyboardButtonFromSpec(spec)) {
                case Some(button) => current.add(button)
                case None => ()
            }
        }
        if (current.size() > 0) {
            rows.add(current)
        }
        let markup = JsonObject()
        markup.put("inline_keyboard", rows)
        markup
    }

    private func buildDraftPayload(message: OutboundMessage, preview: String, finalText: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("draft")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["text"] = JsonString(this.telegramRenderHtml(preview))
        body["plain_text"] = JsonString(preview)
        body["final_text"] = JsonString(this.telegramRenderHtml(finalText))
        body["plain_final_text"] = JsonString(finalText)
        body["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
        body["parse_mode"] = JsonString("HTML")
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func buildApprovalPayload(
        message: OutboundMessage,
        approvalId: String,
        text: String,
        allowLabel: String,
        denyLabel: String,
        allowDecision: String,
        denyDecision: String,
        expiresAtMs: Int64
    ): HashMap<String, JsonValue> {
        let payload = this.buildInlineKeyboardPayload(message, text, [
            "${allowLabel}|callback:${this.approvalCallbackData(approvalId, allowDecision, expiresAtMs)}",
            "${denyLabel}|callback:${this.approvalCallbackData(approvalId, denyDecision, expiresAtMs)}"
        ])
        payload["kind"] = JsonString("approval")
        payload["approval_id"] = JsonString(approvalId)
        payload["expires_at_ms"] = expiresAtMs.toJsonValue()
        payload
    }

    private func approvalCallbackData(approvalId: String, decision: String, expiresAtMs: Int64): String {
        "approval:${this.approvalTokenPart(approvalId)}:${this.approvalTokenPart(decision)}:${expiresAtMs}"
    }

    private func approvalTokenPart(raw: String): String {
        let cleaned = raw.trimAscii()
            .replace(":", "_")
            .replace("|", "_")
            .replace("\n", "_")
            .replace("\r", "_")
            .replace(" ", "_")
        if (cleaned.isEmpty()) { "id" } else { cleaned }
    }

    private func buildStickerPayload(message: OutboundMessage, fileId: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("sticker")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["sticker"] = JsonString(fileId)
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func telegramApplyMediaCaption(body: HashMap<String, JsonValue>, caption: String): Unit {
        let plain = caption.trimAscii()
        if (plain.isEmpty()) {
            return
        }
        let escaped = this.telegramRenderHtml(plain)
        if (escaped.size <= 1024) {
            body["caption"] = JsonString(escaped)
            body["plain_caption"] = JsonString(plain)
            body["parse_mode"] = JsonString("HTML")
        } else {
            body["follow_up_text"] = JsonString(plain)
        }
    }

    private func telegramRefLooksLikeGif(ref: String): Bool {
        let normalized = ref.trimAscii().toAsciiLower()
        normalized.endsWith(".gif") || normalized.contains(".gif?")
    }

    private func telegramRefLooksVoiceCompatible(ref: String): Bool {
        let normalized = ref.trimAscii().toAsciiLower()
        if (normalized.startsWith("http://") || normalized.startsWith("https://")) {
            return true
        }
        normalized.endsWith(".ogg") || normalized.endsWith(".oga") || normalized.endsWith(".opus")
    }

    private func buildPhotoPayload(message: OutboundMessage, fileId: String, caption: String): HashMap<String, JsonValue> {
        if (this.telegramPhotoShouldFallbackToDocument(fileId)) {
            return this.buildDocumentPayload(message, fileId, caption)
        }
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        let asAnimation = this.telegramRefLooksLikeGif(fileId)
        body["kind"] = JsonString(if (asAnimation) { "animation" } else { "photo" })
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body[if (asAnimation) { "animation" } else { "photo" }] = JsonString(fileId)
        this.telegramApplyMediaCaption(body, caption)
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func byteToInt64(v: Byte): Int64 {
        Int64(v)
    }

    private func be16(bytes: Array<Byte>, idx: Int64): Int64 {
        if (idx + 1 >= Int64(bytes.size)) { return 0 }
        this.byteToInt64(bytes[idx]) * 256 + this.byteToInt64(bytes[idx + 1])
    }

    private func be32(bytes: Array<Byte>, idx: Int64): Int64 {
        if (idx + 3 >= Int64(bytes.size)) { return 0 }
        this.byteToInt64(bytes[idx]) * 16777216 +
            this.byteToInt64(bytes[idx + 1]) * 65536 +
            this.byteToInt64(bytes[idx + 2]) * 256 +
            this.byteToInt64(bytes[idx + 3])
    }

    private func telegramLocalImageDimensions(pathText: String): (Int64, Int64) {
        let path = Path(pathText)
        if (pathText.trimAscii().isEmpty() || !exists(path)) {
            return (0, 0)
        }
        let bytes = try { File.readFrom(path) } catch (_e: Exception) { return (0, 0) }
        if (bytes.size >= 24 &&
            bytes[0] == 137u8 && bytes[1] == 80u8 && bytes[2] == 78u8 && bytes[3] == 71u8 &&
            bytes[12] == 73u8 && bytes[13] == 72u8 && bytes[14] == 68u8 && bytes[15] == 82u8) {
            return (this.be32(bytes, 16), this.be32(bytes, 20))
        }
        if (bytes.size >= 4 && bytes[0] == 255u8 && bytes[1] == 216u8) {
            var idx: Int64 = 2
            while (idx + 9 < Int64(bytes.size)) {
                if (bytes[idx] != 255u8) {
                    idx += 1
                    continue
                }
                let marker = bytes[idx + 1]
                let segmentLength = this.be16(bytes, idx + 2)
                if (segmentLength <= 0) {
                    return (0, 0)
                }
                if ((marker >= 192u8 && marker <= 195u8) || (marker >= 197u8 && marker <= 199u8) ||
                    (marker >= 201u8 && marker <= 203u8) || (marker >= 205u8 && marker <= 207u8)) {
                    return (this.be16(bytes, idx + 7), this.be16(bytes, idx + 5))
                }
                idx += 2 + segmentLength
            }
        }
        (0, 0)
    }

    private func telegramPhotoShouldFallbackToDocument(fileId: String): Bool {
        if (!this.looksLikeLocalMediaPath(fileId)) {
            return false
        }
        let localPath = this.normalizeOutboundLocalMediaPath(fileId)
        let (width, height) = this.telegramLocalImageDimensions(localPath)
        if (width <= 0 || height <= 0) {
            return false
        }
        if (width + height > 10000) {
            return true
        }
        let longer = if (width > height) { width } else { height }
        let shorter = if (width > height) { height } else { width }
        shorter > 0 && longer > shorter * 20
    }

    private func buildDocumentPayload(message: OutboundMessage, fileId: String, caption: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("document")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["document"] = JsonString(fileId)
        this.telegramApplyMediaCaption(body, caption)
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func buildAudioPayload(message: OutboundMessage, fileId: String, caption: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("audio")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["audio"] = JsonString(fileId)
        this.telegramApplyMediaCaption(body, caption)
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func buildVoicePayload(message: OutboundMessage, fileId: String, caption: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        let asAudio = this.looksLikeLocalMediaPath(fileId) && !this.telegramRefLooksVoiceCompatible(fileId)
        body["kind"] = JsonString(if (asAudio) { "audio" } else { "voice" })
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body[if (asAudio) { "audio" } else { "voice" }] = JsonString(fileId)
        this.telegramApplyMediaCaption(body, caption)
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func buildVideoPayload(message: OutboundMessage, fileId: String, caption: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("video")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["video"] = JsonString(fileId)
        this.telegramApplyMediaCaption(body, caption)
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func buildVideoNotePayload(message: OutboundMessage, fileId: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("video-note")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["video_note"] = JsonString(fileId)
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        this.applyTelegramReplyTarget(body, message)
        body
    }

    private func chunkTelegramText(text: String): Array<String> {
        let trimmed = text.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
        if (trimmed.isEmpty()) {
            return []
        }
        let chunkMode = this.config.chunkMode.trimAscii().toAsciiLower()
        if (chunkMode == "newline") {
            return this.chunkTelegramTextByNewline(trimmed)
        }
        this.chunkTelegramTextByLength(trimmed)
    }

    private func chunkTelegramTextByLength(text: String): Array<String> {
        var limit = this.config.textChunkLimit
        if (limit <= 0) {
            limit = 4000
        }
        if (Int64(text.size) <= limit) {
            return [text]
        }
        let chunks = ArrayList<String>()
        var cursor = 0
        while (cursor < text.size) {
            let end = if (cursor + limit > text.size) { text.size } else { cursor + limit }
            chunks.add(text[cursor..end])
            cursor = end
        }
        chunks.toArray()
    }

    private func chunkTelegramTextByNewline(text: String): Array<String> {
        let parts = text.split("\n\n")
        if (parts.size <= 1) {
            return this.chunkTelegramTextByLength(text)
        }
        var limit = this.config.textChunkLimit
        if (limit <= 0) {
            limit = 4000
        }
        let chunks = ArrayList<String>()
        var current = ""
        for (part0 in parts) {
            let part = part0.trimAscii()
            if (part.isEmpty()) {
                continue
            }
            if (Int64(part.size) > limit) {
                if (!current.isEmpty()) {
                    chunks.add(current)
                    current = ""
                }
                for (piece in this.chunkTelegramTextByLength(part)) {
                    chunks.add(piece)
                }
                continue
            }
            let candidate = if (current.isEmpty()) { part } else { current + "\n\n" + part }
            if (Int64(candidate.size) <= limit) {
                current = candidate
            } else {
                if (!current.isEmpty()) {
                    chunks.add(current)
                }
                current = part
            }
        }
        if (!current.isEmpty()) {
            chunks.add(current)
        }
        if (chunks.isEmpty()) {
            return this.chunkTelegramTextByLength(text)
        }
        chunks.toArray()
    }

    private func effectiveReplyToMessageId(replyToMessageId: Option<String>): Option<String> {
        replyToMessageId
    }

    private func applyTelegramReplyTarget(body: HashMap<String, JsonValue>, message: OutboundMessage): Unit {
        match (this.effectiveReplyToMessageId(message.replyToMessageId)) {
            case Some(replyId0) =>
                let replyId = replyId0.trimAscii()
                if (replyId.isEmpty()) {
                    return
                }
                let quoteText = message.quoteText.trimAscii()
                if (quoteText.isEmpty()) {
                    body["reply_to_message_id"] = JsonString(replyId)
                    return
                }
                let params = JsonObject()
                params.put("message_id", JsonString(replyId))
                params.put("quote", JsonString(quoteText))
                body["reply_parameters"] = params
            case None => ()
        }
    }

    private func copyTelegramReplyTarget(dst: HashMap<String, JsonValue>, src: HashMap<String, JsonValue>): Unit {
        match (src.get("reply_parameters")) {
            case Some(v) => dst["reply_parameters"] = v
            case None =>
                match (src.get("reply_to_message_id")) {
                    case Some(v) => dst["reply_to_message_id"] = v
                    case None => ()
                }
        }
    }

    private func applyTelegramSilentOption(body: HashMap<String, JsonValue>): Unit {
        if (this.config.silent) {
            body["disable_notification"] = true.toJsonValue()
        }
    }

    private func effectiveReplyInThread(replyInThread: Bool): Bool {
        let mode = this.config.replyToMode.trimAscii().toAsciiLower()
        if (mode == "off" || mode == "disabled") {
            return false
        }
        if (mode == "all" || mode == "thread") {
            return true
        }
        replyInThread
    }

    private func shouldAttachReplyTargetToChunk(chunkIndex: Int64): Bool {
        let mode = this.config.replyToMode.trimAscii().toAsciiLower()
        if (mode == "all") {
            return true
        }
        if (mode == "off" || mode == "disabled" || mode == "first" || mode == "thread") {
            return chunkIndex == 0
        }
        chunkIndex == 0
    }

    private func payloadIsPoll(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "poll" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsDelete(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "delete" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsClearButtons(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "clear-buttons" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsEditButtons(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "edit-buttons" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsEdit(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "edit" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsPin(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "pin" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsUnpin(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "unpin" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsReaction(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "reaction" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsChatAction(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "chat-action" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsInlineKeyboard(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "inline-keyboard" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsDraft(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "draft" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsApproval(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "approval" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsMediaGroup(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "media-group" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsEditMedia(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "edit-media" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsInlineKeyboardInvalid(payload: HashMap<String, JsonValue>): Bool {
        this.payloadIsInlineKeyboard(payload) && payload.get("validation_error").isSome()
    }

    private func payloadIsMediaInvalid(payload: HashMap<String, JsonValue>): Bool {
        this.payloadIsAnyMedia(payload) && payload.get("validation_error").isSome()
    }

    private func payloadValidationError(payload: HashMap<String, JsonValue>): String {
        match (payload.get("validation_error")) {
            case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "telegram payload validation failed" }
            case None => "telegram payload validation failed"
        }
    }

    private func payloadIsSticker(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "sticker" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsPhoto(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "photo" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsAnimation(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "animation" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsDocument(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "document" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsAudio(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "audio" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsVoice(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "voice" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsVideo(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "video" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsVideoNote(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "video-note" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsAnyMedia(payload: HashMap<String, JsonValue>): Bool {
            this.payloadIsSticker(payload) ||
            this.payloadIsPhoto(payload) ||
            this.payloadIsAnimation(payload) ||
            this.payloadIsDocument(payload) ||
            this.payloadIsAudio(payload) ||
            this.payloadIsVoice(payload) ||
            this.payloadIsVideo(payload) ||
            this.payloadIsVideoNote(payload) ||
            this.payloadIsMediaGroup(payload) ||
            this.payloadIsEditMedia(payload)
    }

    private func payloadIsTopicCreate(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "topic-create" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsTopicEdit(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "topic-edit" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func telegramApiMethodForPayloadKind(kind: String): String {
        if (kind == "poll") {
            return "sendPoll"
        }
        if (kind == "delete") {
            return "deleteMessage"
        }
        if (kind == "clear-buttons") {
            return "editMessageReplyMarkup"
        }
        if (kind == "edit-buttons") {
            return "editMessageReplyMarkup"
        }
        if (kind == "edit") {
            return "editMessageText"
        }
        if (kind == "edit-media") {
            return "editMessageMedia"
        }
        if (kind == "media-group") {
            return "sendMediaGroup"
        }
        if (kind == "pin") {
            return "pinChatMessage"
        }
        if (kind == "unpin") {
            return "unpinChatMessage"
        }
        if (kind == "reaction") {
            return "setMessageReaction"
        }
        if (kind == "chat-action") {
            return "sendChatAction"
        }
        if (kind == "draft") {
            return "sendMessage"
        }
        if (kind == "approval") {
            return "sendMessage"
        }
        if (kind == "sticker") {
            return "sendSticker"
        }
        if (kind == "photo") {
            return "sendPhoto"
        }
        if (kind == "animation") {
            return "sendAnimation"
        }
        if (kind == "document") {
            return "sendDocument"
        }
        if (kind == "audio") {
            return "sendAudio"
        }
        if (kind == "voice") {
            return "sendVoice"
        }
        if (kind == "video") {
            return "sendVideo"
        }
        if (kind == "video-note") {
            return "sendVideoNote"
        }
        if (kind == "topic-create") {
            return "createForumTopic"
        }
        if (kind == "topic-edit") {
            return "editForumTopic"
        }
        "sendMessage"
    }

    private func detectPollPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let normalized = message.text.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
        if (!normalized.startsWith("[poll]")) {
            return None
        }
        let lines = normalized.split("\n")
        if (lines.size < 2) {
            return None
        }
        let title = lines[1].trimAscii()
        let options = ArrayList<String>()
        var durationSeconds: Int64 = 0
        var durationHoursSeen = false
        var allowMultiselect = false
        var isAnonymous: Option<Bool> = None<Bool>
        if (lines.size > 2) {
            var i = 2
            while (i < lines.size) {
                let raw = lines[i].trimAscii()
                if (!raw.isEmpty()) {
                    if (raw.startsWith("durationSeconds=")) {
                        durationSeconds = try { Int64.parse(raw["durationSeconds=".size..].trimAscii()) } catch (_e: Exception) { -1 }
                    } else if (raw.startsWith("durationHours=")) {
                        durationHoursSeen = true
                    } else if (raw.startsWith("allowMultiselect=")) {
                        allowMultiselect = this.parseTelegramBool(raw["allowMultiselect=".size..].trimAscii())
                    } else if (raw.startsWith("isAnonymous=")) {
                        isAnonymous = Some(this.parseTelegramBool(raw["isAnonymous=".size..].trimAscii()))
                    } else if (raw.startsWith("pollAnonymous=")) {
                        isAnonymous = Some(this.parseTelegramBool(raw["pollAnonymous=".size..].trimAscii()))
                    } else if (raw.startsWith("pollPublic=")) {
                        isAnonymous = Some(!this.parseTelegramBool(raw["pollPublic=".size..].trimAscii()))
                    } else {
                        let parsed = this.parsePollOptionLine(raw)
                        if (!parsed.isEmpty()) {
                            options.add(parsed)
                        }
                    }
                }
                i += 1
            }
        }
        if (title.isEmpty() || options.isEmpty()) {
            return None
        }
        if (title.size > 300) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("poll")
            invalid["validation_error"] = JsonString("telegram poll question supports at most 300 characters")
            return Some(invalid)
        }
        for (option in options) {
            if (option.size > 100) {
                let invalid = HashMap<String, JsonValue>()
                invalid["kind"] = JsonString("poll")
                invalid["validation_error"] = JsonString("telegram poll option supports at most 100 characters")
                return Some(invalid)
            }
        }
        if (options.size > 10) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("poll")
            invalid["validation_error"] = JsonString("telegram poll supports at most 10 options")
            return Some(invalid)
        }
        if (durationHoursSeen) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("poll")
            invalid["validation_error"] = JsonString("telegram poll durationHours is not supported; use durationSeconds (5..600)")
            return Some(invalid)
        }
        if (durationSeconds < 0 || (durationSeconds > 0 && (durationSeconds < 5 || durationSeconds > 600))) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("poll")
            invalid["validation_error"] = JsonString("telegram poll durationSeconds must be between 5 and 600")
            return Some(invalid)
        }
        Some(this.buildPollPayload(message, title, options.toArray(), durationSeconds: durationSeconds, allowMultiselect: allowMultiselect, isAnonymous: isAnonymous))
    }

    private func detectDeletePayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let normalized = message.text.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
        if (normalized != "[delete]") {
            return None
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let trimmed = target.trimAscii()
                if (trimmed.isEmpty()) { None } else { Some(this.buildDeletePayload(message, trimmed)) }
            case None => None
        }
    }

    private func detectClearButtonsPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let normalized = message.text.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
        if (normalized != "[clear-buttons]") {
            return None
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let trimmed = target.trimAscii()
                if (trimmed.isEmpty()) { None } else { Some(this.buildClearButtonsPayload(message, trimmed)) }
            case None => None
        }
    }

    private func detectEditButtonsPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let specs = parseGatewayEditButtonsParts(message.text)
        if (specs.isEmpty()) {
            return None
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let trimmed = target.trimAscii()
                if (trimmed.isEmpty()) { None } else { Some(this.buildEditButtonsPayload(message, trimmed, specs)) }
            case None => None
        }
    }

    private func detectEditPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let content = parseGatewayEditText(message.text)
        if (content.isEmpty()) {
            return None
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let trimmed = target.trimAscii()
                if (trimmed.isEmpty()) { None } else { Some(this.buildEditPayload(message, trimmed, content)) }
            case None => None
        }
    }

    private func detectPinPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let action = parseGatewayPinAction(message.text)
        if (action.isEmpty()) {
            return None
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let trimmed = target.trimAscii()
                if (trimmed.isEmpty()) {
                    None
                } else {
                    Some(this.buildPinPayload(message, trimmed, unpin: action == "unpin"))
                }
            case None => None
        }
    }

    private func detectTopicCreatePayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let title = parseGatewayTopicCreateText(message.text)
        if (title.isEmpty()) {
            return None
        }
        Some(this.buildTopicCreatePayload(message, title))
    }

    private func detectTopicEditPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let title = parseGatewayTopicEditText(message.text)
        if (title.isEmpty()) {
            return None
        }
        match (message.replyToMessageId) {
            case Some(targetThreadId) =>
                let trimmed = targetThreadId.trimAscii()
                if (trimmed.isEmpty()) { None } else { Some(this.buildTopicEditPayload(message, trimmed, title)) }
            case None => None
        }
    }

    private func detectReactionPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        var token = parseGatewayReactionToken(message.text)
        let status = parseGatewayReactionStatus(message.text)
        if (token.isEmpty() && !status.isEmpty()) {
            token = this.telegramStatusReactionToken(status)
        }
        let remove = parseGatewayReactionRemove(message.text)
        if (token.isEmpty() && !remove) {
            return None
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let trimmed = target.trimAscii()
                if (trimmed.isEmpty()) { None } else { Some(this.buildReactionPayload(message, trimmed, token)) }
            case None => None
        }
    }

    private func telegramStatusReactionToken(status: String): String {
        match (status.trimAscii().toAsciiLower()) {
            case "queued" => "👀"
            case "thinking" => "🤔"
            case "tool" => "🔥"
            case "coding" => "👨‍💻"
            case "web" => "⚡"
            case "done" => "👍"
            case "error" => "😱"
            case "stallsoft" | "stall_soft" | "stall-soft" => "🥱"
            case "stallhard" | "stall_hard" | "stall-hard" => "😨"
            case "compacting" => "✍"
            case _ => ""
        }
    }

    private func detectChatActionPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let action = parseGatewayChatAction(message.text)
        if (action.isEmpty()) {
            return None
        }
        Some(this.buildChatActionPayload(message, action))
    }

    private func normalizeTelegramChatAction(action: String): String {
        let normalized = action.trimAscii().toAsciiLower().replace("-", "_").replace(" ", "_")
        if (normalized == "typing" || normalized == "upload_photo" || normalized == "record_video" ||
            normalized == "upload_video" || normalized == "record_voice" || normalized == "upload_voice" ||
            normalized == "upload_document" || normalized == "choose_sticker" || normalized == "find_location" ||
            normalized == "record_video_note" || normalized == "upload_video_note") {
            return normalized
        }
        "typing"
    }

    private func detectInlineKeyboardPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let parsed = parseGatewayInlineKeyboardParts(message.text)
        let text = parsed[0].trimAscii()
        if (text.isEmpty() && parsed[1].isEmpty()) {
            return None
        }
        if (text.isEmpty()) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("inline-keyboard")
            invalid["validation_error"] = JsonString("telegram inlineKeyboard requires non-empty text")
            return Some(invalid)
        }
        if (!this.inlineKeyboardSpecsAreValid(parsed[1])) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("inline-keyboard")
            invalid["validation_error"] = JsonString("telegram inlineKeyboard requires at least one valid button")
            return Some(invalid)
        }
        Some(this.buildInlineKeyboardPayload(message, text, parsed[1]))
    }

    private func detectDraftPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let normalized = message.text.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
        if (!normalized.startsWith("[draft]")) {
            return None
        }
        var preview = "Processing..."
        var finalText = ""
        for (line0 in normalized.split("\n")) {
            let line = line0.trimAscii()
            if (line.startsWith("preview=")) {
                preview = line["preview=".size..].trimAscii()
            } else if (line.startsWith("final=")) {
                finalText = line["final=".size..].trimAscii()
            }
        }
        if (finalText.isEmpty()) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("draft")
            invalid["validation_error"] = JsonString("telegram draft requires final text")
            return Some(invalid)
        }
        Some(this.buildDraftPayload(message, preview, finalText))
    }

    private func detectApprovalPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let normalized = message.text.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
        if (!normalized.startsWith("[approval]")) {
            return None
        }
        var approvalId = ""
        var text = "Approval required"
        var allowLabel = "Approve"
        var denyLabel = "Deny"
        var allowDecision = "allow-once"
        var denyDecision = "deny"
        var expiresAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds() + 600000
        for (line0 in normalized.split("\n")) {
            let line = line0.trimAscii()
            if (line.startsWith("id=")) {
                approvalId = line["id=".size..].trimAscii()
            } else if (line.startsWith("text=")) {
                text = line["text=".size..].trimAscii()
            } else if (line.startsWith("allowLabel=")) {
                allowLabel = line["allowLabel=".size..].trimAscii()
            } else if (line.startsWith("denyLabel=")) {
                denyLabel = line["denyLabel=".size..].trimAscii()
            } else if (line.startsWith("allow=")) {
                allowDecision = line["allow=".size..].trimAscii()
            } else if (line.startsWith("deny=")) {
                denyDecision = line["deny=".size..].trimAscii()
            } else if (line.startsWith("expiresAtMs=")) {
                try {
                    expiresAtMs = Int64.parse(line["expiresAtMs=".size..].trimAscii())
                } catch (_: Exception) {
                    ()
                }
            }
        }
        if (approvalId.isEmpty()) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("approval")
            invalid["validation_error"] = JsonString("telegram approval requires id")
            return Some(invalid)
        }
        Some(this.buildApprovalPayload(message, approvalId, text, allowLabel, denyLabel, allowDecision, denyDecision, expiresAtMs))
    }

    private func detectMediaGroupPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let items = parseGatewayMediaGroupItems(message.text)
        if (items.isEmpty()) {
            return None
        }
        if (items.size < 2 || items.size > 10) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("media-group")
            invalid["validation_error"] = JsonString("telegram media group requires 2 to 10 items")
            return Some(invalid)
        }
        for (item in items) {
            let kind = this.normalizeMediaGroupType(item.kind, item.fileId)
            let invalid = this.validateOutboundMediaReference(kind, item.fileId)
            if (!invalid.isEmpty()) {
                return Some(this.invalidMediaPayload("media-group", invalid))
            }
        }
        Some(this.buildMediaGroupPayload(message, items))
    }

    private func detectEditMediaPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let parsed = parseGatewayEditMediaParts(message.text)
        let kind = parsed[0]
        let fileId = parsed[1]
        let caption = parsed[2]
        if (kind.isEmpty() && fileId.isEmpty()) {
            return None
        }
        if (fileId.isEmpty()) {
            let invalid = HashMap<String, JsonValue>()
            invalid["kind"] = JsonString("edit-media")
            invalid["validation_error"] = JsonString("telegram edit-media requires fileId")
            return Some(invalid)
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let targetMessageId = target.trimAscii()
                if (targetMessageId.isEmpty()) {
                    return None
                }
                let normalizedKind = this.normalizeMediaGroupType(kind, fileId)
                let invalid = this.validateOutboundMediaReference(normalizedKind, fileId)
                if (!invalid.isEmpty()) {
                    return Some(this.invalidMediaPayload("edit-media", invalid))
                }
                Some(this.buildEditMediaPayload(message, targetMessageId, normalizedKind, fileId, caption))
            case None => None
        }
    }

    private func detectStickerPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let fileId = parseGatewayStickerFileId(message.text)
        if (fileId.isEmpty()) {
            return None
        }
        let invalid = this.validateOutboundMediaReference("sticker", fileId)
        if (!invalid.isEmpty()) {
            return Some(this.invalidMediaPayload("sticker", invalid))
        }
        Some(this.buildStickerPayload(message, fileId))
    }

    private func detectPhotoPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let parsed = parseGatewayPhotoParts(message.text)
        if (parsed[0].isEmpty()) {
            return None
        }
        let invalid = this.validateOutboundMediaReference("photo", parsed[0])
        if (!invalid.isEmpty()) {
            return Some(this.invalidMediaPayload("photo", invalid))
        }
        Some(this.buildPhotoPayload(message, parsed[0], parsed[1]))
    }

    private func detectDocumentPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let parsed = parseGatewayDocumentParts(message.text)
        if (parsed[0].isEmpty()) {
            return None
        }
        let invalid = this.validateOutboundMediaReference("document", parsed[0])
        if (!invalid.isEmpty()) {
            return Some(this.invalidMediaPayload("document", invalid))
        }
        Some(this.buildDocumentPayload(message, parsed[0], parsed[1]))
    }

    private func detectAudioPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let parsed = parseGatewayAudioParts(message.text)
        if (parsed[0].isEmpty()) {
            return None
        }
        let invalid = this.validateOutboundMediaReference("audio", parsed[0])
        if (!invalid.isEmpty()) {
            return Some(this.invalidMediaPayload("audio", invalid))
        }
        Some(this.buildAudioPayload(message, parsed[0], parsed[1]))
    }

    private func detectVoicePayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let parsed = parseGatewayVoiceParts(message.text)
        if (parsed[0].isEmpty()) {
            return None
        }
        let invalid = this.validateOutboundMediaReference("voice", parsed[0])
        if (!invalid.isEmpty()) {
            return Some(this.invalidMediaPayload("voice", invalid))
        }
        Some(this.buildVoicePayload(message, parsed[0], parsed[1]))
    }

    private func detectVideoPayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let parsed = parseGatewayVideoParts(message.text)
        if (parsed[0].isEmpty()) {
            return None
        }
        let invalid = this.validateOutboundMediaReference("video", parsed[0])
        if (!invalid.isEmpty()) {
            return Some(this.invalidMediaPayload("video", invalid))
        }
        Some(this.buildVideoPayload(message, parsed[0], parsed[1]))
    }

    private func detectVideoNotePayload(message: OutboundMessage): Option<HashMap<String, JsonValue>> {
        let fileId = parseGatewayVideoNoteFileId(message.text)
        if (fileId.isEmpty()) {
            return None
        }
        let invalid = this.validateOutboundMediaReference("video-note", fileId)
        if (!invalid.isEmpty()) {
            return Some(this.invalidMediaPayload("video-note", invalid))
        }
        Some(this.buildVideoNotePayload(message, fileId))
    }

    private func invalidMediaPayload(kind: String, reason: String): HashMap<String, JsonValue> {
        let invalid = HashMap<String, JsonValue>()
        invalid["kind"] = JsonString(kind)
        invalid["validation_error"] = JsonString(reason)
        invalid
    }

    private func validateOutboundMediaReference(kind: String, ref: String): String {
        let normalized = ref.trimAscii()
        if (normalized.isEmpty()) {
            return "telegram ${kind} media reference is empty"
        }
        let lowered = normalized.toAsciiLower()
        if (lowered.startsWith("http://") || lowered.startsWith("https://")) {
            if (!this.config.media.outboundAllowUrl) {
                return "telegram outbound media URL is disabled"
            }
            if (kind == "video-note" && (lowered.startsWith("http://") || lowered.startsWith("https://"))) {
                return "telegram video-note does not support outbound URL media"
            }
            return ""
        }
        if (this.looksLikeLocalMediaPath(normalized)) {
            if (!this.config.media.outboundAllowLocalPath) {
                return "telegram outbound local media path is disabled"
            }
            if (!this.localMediaPathWithinAllowedRoots(normalized)) {
                return "telegram outbound local media path is outside configured roots"
            }
            return ""
        }
        if (normalized.contains("://")) {
            return "telegram outbound media URL scheme is not allowed"
        }
        ""
    }

    private func looksLikeLocalMediaPath(ref: String): Bool {
        let lowered = ref.toAsciiLower()
        lowered.startsWith("file://") ||
            ref.startsWith("/") ||
            ref.startsWith("./") ||
            ref.startsWith("../") ||
            ref.startsWith("~")
    }

    private func localMediaPathWithinAllowedRoots(ref: String): Bool {
        if (this.config.media.outboundLocalRoots.isEmpty()) {
            return false
        }
        let rawPath = if (ref.toAsciiLower().startsWith("file://")) { ref[7..] } else { ref }
        let candidate = try { canonicalize(Path(rawPath)).toString() } catch (_e: Exception) { return false }
        for (root in this.config.media.outboundLocalRoots) {
            let normalizedRoot = root.trimAscii()
            if (normalizedRoot.isEmpty()) {
                continue
            }
            let rootPath = try { canonicalize(Path(normalizedRoot)).toString() } catch (_e: Exception) { continue }
            if (candidate == rootPath || candidate.startsWith(rootPath + "/")) {
                return true
            }
        }
        false
    }

    private func normalizeOutboundLocalMediaPath(ref: String): String {
        let trimmed = ref.trimAscii()
        if (trimmed.toAsciiLower().startsWith("file://")) {
            return trimmed[7..]
        }
        trimmed
    }

    private func parsePollOptionLine(raw: String): String {
        match (raw.indexOf(". ")) {
            case Some(idx) => raw[idx + 2..].trimAscii()
            case None => raw
        }
    }

    private func parseTelegramBool(raw: String): Bool {
        let normalized = raw.trimAscii().toAsciiLower()
        normalized == "true" || normalized == "1" || normalized == "yes" || normalized == "on"
    }

    private func inlineKeyboardButtonFromSpec(spec: String): Option<JsonObject> {
        let normalized = spec.trimAscii()
        match (normalized.indexOf("|")) {
            case Some(idx) =>
                let label = normalized[..idx].trimAscii()
                let action = normalized[idx + 1..].trimAscii()
                if (label.isEmpty() || action.isEmpty()) {
                    return None
                }
                let button = JsonObject()
                button.put("text", JsonString(label))
                if (action.startsWith("callback:")) {
                    if (action.size <= "callback:".size) {
                        return None
                    }
                    let data = action["callback:".size..].trimAscii()
                    if (data.isEmpty() || data.size > 64) {
                        return None
                    }
                    button.put("callback_data", JsonString(data))
                    return Some(button)
                }
                if (action.startsWith("url:")) {
                    if (!(action.startsWith("url:https://") || action.startsWith("url:http://"))) {
                        return None
                    }
                    let url = action["url:".size..].trimAscii()
                    if (url.isEmpty()) {
                        return None
                    }
                    button.put("url", JsonString(url))
                    return Some(button)
                }
                None
            case None => None
        }
    }

    private func inlineKeyboardSpecsAreValid(specs: Array<String>): Bool {
        for (spec0 in specs) {
            let spec = spec0.trimAscii()
            if (spec.isEmpty() || spec == "row" || spec == "---") {
                continue
            }
            if (this.inlineKeyboardButtonFromSpec(spec).isSome()) {
                return true
            }
        }
        false
    }

    private func inlineButtonsAllowedForPeer(peerId: String): Bool {
        let scope = this.config.inlineButtons.scope.trimAscii().toAsciiLower()
        let peer = peerId.trimAscii()
        if (scope == "off" || scope == "disabled" || scope == "false") {
            return false
        }
        if (scope == "all" || scope.isEmpty()) {
            return true
        }
        if (scope == "dm" || scope == "direct") {
            return peer.startsWith("user:")
        }
        if (scope == "group" || scope == "groups") {
            return peer.startsWith("group:")
        }
        if (scope == "allowlist") {
            if (this.config.inlineButtons.allowlist.isEmpty()) {
                return true
            }
            for (raw in this.config.inlineButtons.allowlist) {
                let item = raw.trimAscii()
                if (item == "*" || item == peer) {
                    return true
                }
                if (item.startsWith("tg:") && item["tg:".size..].trimAscii() == peer) {
                    return true
                }
                if (item.startsWith("telegram:") && item["telegram:".size..].trimAscii() == peer) {
                    return true
                }
            }
            return false
        }
        true
    }

    private func reactionInboundThreadId(peerId: String): Option<String> {
        match (peerId.indexOf(":topic:")) {
            case Some(idx) => Some(peerId[idx + ":topic:".size..].trimAscii())
            case None => None
        }
    }

    private func readReactionEmoji(reaction: JsonObject): String {
        match (reaction.get("new_reaction")) {
            case Some(v) =>
                try {
                    for (item in v.asArray().getItems()) {
                        try {
                            let obj = item.asObject()
                            if (this.readStringField(obj, "type") == "emoji") {
                                let emoji = this.readStringField(obj, "emoji").trimAscii()
                                if (!emoji.isEmpty()) {
                                    return emoji
                                }
                            }
                        } catch (_e: Exception) {
                            ()
                        }
                    }
                    ""
                } catch (_e: Exception) {
                    ""
                }
            case None => ""
        }
    }

    private func maybeAckInboundReaction(message: InboundMessage): Unit {
        if (message.text.startsWith("[telegram-reaction]")) {
            return
        }
        let level = this.config.reactionLevel.trimAscii().toAsciiLower()
        if (level == "off" || level == "false" || level == "disabled") {
            return
        }
        if (!this.config.actions.reactions) {
            return
        }
        let token = this.config.ackReaction.trimAscii()
        if (token.isEmpty()) {
            return
        }
        let target = message.messageId.trimAscii()
        if (target.isEmpty()) {
            return
        }
        let payload = this.buildReactionPayload(
            OutboundMessage(
                ChannelType.Telegram,
                message.peerId,
                "",
                replyToMessageId: Some(target),
                replyInThread: message.replyInThread,
                accountId: message.accountId
            ),
            target,
            token
        )
        let _ = this.sendPayloadToTelegram(payload)
    }

    private func maybeRemoveAckAfterReply(message: OutboundMessage): Unit {
        if (!this.config.removeAckAfterReply || !this.config.actions.reactions) {
            return
        }
        match (message.replyToMessageId) {
            case Some(target0) =>
                let target = target0.trimAscii()
                if (target.isEmpty()) {
                    return
                }
                let payload = this.buildReactionPayload(
                    OutboundMessage(
                        ChannelType.Telegram,
                        message.peerId,
                        "[reaction]\nremove=true\nrender=remove",
                        replyToMessageId: Some(target),
                        replyInThread: message.replyInThread,
                        accountId: message.accountId
                    ),
                    target,
                    ""
                )
                let _ = this.sendPayloadToTelegram(payload)
            case None => ()
        }
    }

    private func telegramEscapeHtml(text: String): String {
        text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    }

    private func telegramEscapeHtmlAttr(text: String): String {
        this.telegramEscapeHtml(text).replace("\"", "&quot;")
    }

    private func startsWithAt(text: String, idx: Int64, token: String): Bool {
        if (idx < 0 || idx + token.size > text.size) {
            return false
        }
        var i: Int64 = 0
        while (i < token.size) {
            if (text[idx + i] != token[i]) {
                return false
            }
            i += 1
        }
        true
    }

    private func appendEscapedHtmlSegment(sb: StringBuilder, segment: String): Unit {
        sb.append(this.telegramEscapeHtml(segment))
    }

    private func appendEscapedHtmlPlainSegment(sb: StringBuilder, segment: String): Unit {
        var cursor: Int64 = 0
        while (cursor < segment.size) {
            let b = segment[cursor]
            if (b == UInt8(32) || b == UInt8(9) || b == UInt8(10)) {
                sb.append(segment[cursor..cursor + 1])
                cursor += 1
                continue
            }
            var end = cursor
            while (end < segment.size) {
                let eb = segment[end]
                if (eb == UInt8(32) || eb == UInt8(9) || eb == UInt8(10)) {
                    break
                }
                end += 1
            }
            let token = segment[cursor..end]
            if (this.telegramPlainTokenLooksFileRef(token)) {
                sb.append("<code>")
                sb.append(this.telegramEscapeHtml(token))
                sb.append("</code>")
            } else {
                sb.append(this.telegramEscapeHtml(token))
            }
            cursor = end
        }
    }

    private func telegramPlainTokenLooksFileRef(token: String): Bool {
        let t = token.trimAscii()
        if (t.isEmpty() || t.startsWith("http://") || t.startsWith("https://")) {
            return false
        }
        let lower = t.toAsciiLower()
        let hasPathPrefix = t.startsWith("/") || t.startsWith("./") || t.startsWith("../") || t.startsWith("~/")
        let hasKnownExtension = lower.endsWith(".cj") || lower.contains(".cj:") ||
            lower.endsWith(".ts") || lower.contains(".ts:") ||
            lower.endsWith(".js") || lower.contains(".js:") ||
            lower.endsWith(".mjs") || lower.contains(".mjs:") ||
            lower.endsWith(".json") || lower.contains(".json:") ||
            lower.endsWith(".md") || lower.contains(".md:") ||
            lower.endsWith(".txt") || lower.contains(".txt:") ||
            lower.endsWith(".py") || lower.contains(".py:") ||
            lower.endsWith(".sh") || lower.contains(".sh:")
        hasPathPrefix && (hasKnownExtension || t.contains(":"))
    }

    private func telegramLineLooksMarkdownTable(line: String): Bool {
        let t = line.trimAscii()
        t.startsWith("|") && t.endsWith("|") && t.contains("|")
    }

    private func telegramLineLooksMarkdownTableSeparator(line: String): Bool {
        let t = line.trimAscii()
        if (!t.startsWith("|") || !t.endsWith("|")) {
            return false
        }
        var hasDash = false
        for (b in t.toArray()) {
            if (b == UInt8(45)) {
                hasDash = true
            } else if (b == UInt8(124) || b == UInt8(58) || b == UInt8(32)) {
                ()
            } else {
                return false
            }
        }
        hasDash
    }

    private func telegramRenderHtml(text: String): String {
        try {
            this.telegramRenderHtmlUnsafe(text)
        } catch (e: Exception) {
            LogUtils.info("Telegram HTML render failed; using escaped plain text: ${e.message}")
            this.telegramEscapeHtml(text.replace("\r\n", "\n").replace("\r", "\n"))
        }
    }

    private func telegramRenderHtmlUnsafe(text: String): String {
        let raw = text.replace("\r\n", "\n").replace("\r", "\n")
        if (raw.isEmpty()) {
            return ""
        }
        let sb = StringBuilder()
        var cursor: Int64 = 0
        while (cursor < raw.size) {
            if (cursor == 0 || raw[cursor - 1] == UInt8(10)) {
                let lineEnd = match (raw.indexOf("\n", cursor)) {
                    case Some(idx) => idx
                    case None => raw.size
                }
                let nextStart = if (lineEnd < raw.size) { lineEnd + 1 } else { raw.size }
                if (nextStart < raw.size) {
                    let nextEnd = match (raw.indexOf("\n", nextStart)) {
                        case Some(idx) => idx
                        case None => raw.size
                    }
                    if (this.telegramLineLooksMarkdownTable(raw[cursor..lineEnd]) &&
                        this.telegramLineLooksMarkdownTableSeparator(raw[nextStart..nextEnd])) {
                        var tableEnd = nextEnd
                        var scan = if (nextEnd < raw.size) { nextEnd + 1 } else { raw.size }
                        while (scan < raw.size) {
                            let rowEnd = match (raw.indexOf("\n", scan)) {
                                case Some(idx) => idx
                                case None => raw.size
                            }
                            if (!this.telegramLineLooksMarkdownTable(raw[scan..rowEnd])) {
                                break
                            }
                            tableEnd = rowEnd
                            scan = if (rowEnd < raw.size) { rowEnd + 1 } else { raw.size }
                        }
                        sb.append("<pre>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor..tableEnd])
                        sb.append("</pre>")
                        if (tableEnd < raw.size) {
                            sb.append("\n")
                            cursor = tableEnd + 1
                        } else {
                            cursor = tableEnd
                        }
                        continue
                    }
                }
            }
            if (raw[cursor] == UInt8(10) && cursor + 1 < raw.size && this.startsWithAt(raw, cursor + 1, "> ")) {
                sb.append("\n")
                cursor += 1
                continue
            }
            if ((cursor == 0 || raw[cursor - 1] == UInt8(10)) && this.startsWithAt(raw, cursor, "> ")) {
                let lineEnd = match (raw.indexOf("\n", cursor)) {
                    case Some(idx) => idx
                    case None => raw.size
                }
                sb.append("<blockquote>")
                this.appendEscapedHtmlSegment(sb, raw[cursor + 2..lineEnd])
                sb.append("</blockquote>")
                if (lineEnd < raw.size) {
                    sb.append("\n")
                    cursor = lineEnd + 1
                } else {
                    cursor = lineEnd
                }
                continue
            }
            if (this.startsWithAt(raw, cursor, "```")) {
                match (raw.indexOf("```", cursor + 3)) {
                    case Some(endIdx) =>
                        sb.append("<pre>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor + 3..endIdx])
                        sb.append("</pre>")
                        cursor = endIdx + 3
                        continue
                    case None => ()
                }
            }
            if (this.startsWithAt(raw, cursor, "||")) {
                match (raw.indexOf("||", cursor + 2)) {
                    case Some(endIdx) =>
                        sb.append("<tg-spoiler>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor + 2..endIdx])
                        sb.append("</tg-spoiler>")
                        cursor = endIdx + 2
                        continue
                    case None => ()
                }
            }
            if (this.startsWithAt(raw, cursor, "**")) {
                match (raw.indexOf("**", cursor + 2)) {
                    case Some(endIdx) =>
                        sb.append("<b>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor + 2..endIdx])
                        sb.append("</b>")
                        cursor = endIdx + 2
                        continue
                    case None => ()
                }
            }
            if (this.startsWithAt(raw, cursor, "*") && !this.startsWithAt(raw, cursor, "**")) {
                match (raw.indexOf("*", cursor + 1)) {
                    case Some(endIdx) =>
                        sb.append("<i>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor + 1..endIdx])
                        sb.append("</i>")
                        cursor = endIdx + 1
                        continue
                    case None => ()
                }
            }
            if (this.startsWithAt(raw, cursor, "__")) {
                match (raw.indexOf("__", cursor + 2)) {
                    case Some(endIdx) =>
                        sb.append("<u>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor + 2..endIdx])
                        sb.append("</u>")
                        cursor = endIdx + 2
                        continue
                    case None => ()
                }
            }
            if (this.startsWithAt(raw, cursor, "~~")) {
                match (raw.indexOf("~~", cursor + 2)) {
                    case Some(endIdx) =>
                        sb.append("<s>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor + 2..endIdx])
                        sb.append("</s>")
                        cursor = endIdx + 2
                        continue
                    case None => ()
                }
            }
            if (this.startsWithAt(raw, cursor, "`")) {
                match (raw.indexOf("`", cursor + 1)) {
                    case Some(endIdx) =>
                        sb.append("<code>")
                        this.appendEscapedHtmlSegment(sb, raw[cursor + 1..endIdx])
                        sb.append("</code>")
                        cursor = endIdx + 1
                        continue
                    case None => ()
                }
            }
            if (this.startsWithAt(raw, cursor, "[")) {
                match (raw.indexOf("](", cursor + 1)) {
                    case Some(midIdx) =>
                        match (raw.indexOf(")", midIdx + 2)) {
                            case Some(endIdx) =>
                                let label = raw[cursor + 1..midIdx]
                                let url = raw[midIdx + 2..endIdx].trimAscii()
                                if (url.startsWith("https://") || url.startsWith("http://")) {
                                    sb.append("<a href=\"${this.telegramEscapeHtmlAttr(url)}\">")
                                    this.appendEscapedHtmlSegment(sb, label)
                                    sb.append("</a>")
                                    cursor = endIdx + 1
                                    continue
                                }
                            case None => ()
                        }
                    case None => ()
                }
            }
            let next = this.nextTelegramMarkdownMarker(raw, this.nextTelegramMarkdownSearchStart(raw, cursor))
            this.appendEscapedHtmlPlainSegment(sb, raw[cursor..next])
            cursor = next
        }
        sb.toString()
    }

    private func nextTelegramMarkdownSearchStart(text: String, cursor: Int64): Int64 {
        if (cursor < 0 || cursor >= text.size) {
            return text.size
        }
        if (text[cursor] < UInt8(128)) {
            return cursor + 1
        }
        cursor
    }

    private func nextTelegramMarkdownMarker(text: String, start: Int64): Int64 {
        var next = text.size
        for (token in ["\n> ", "```", "||", "**", "__", "~~", "`", "*", "["]) {
            match (text.indexOf(token, start)) {
                case Some(idx) =>
                    if (idx < next) {
                        next = idx
                    }
                case None => ()
            }
        }
        next
    }

    private func pickPrimaryUpdateObject(root: JsonObject): Option<JsonObject> {
        for (key in ["message", "edited_message", "channel_post", "edited_channel_post"]) {
            match (this.readObjectFieldOpt(root, key)) {
                case Some(v) => return Some(v)
                case None => ()
            }
        }
        None
    }

    private func primaryUpdateKind(root: JsonObject): String {
        for (key in [
            "message", "edited_message", "channel_post", "edited_channel_post", "message_reaction",
            "callback_query", "business_connection", "business_message", "edited_business_message",
            "deleted_business_messages", "message_reaction_count", "inline_query", "chosen_inline_result",
            "shipping_query", "pre_checkout_query", "purchased_paid_media", "poll", "poll_answer",
            "my_chat_member", "chat_member", "managed_bot", "chat_join_request", "chat_boost",
            "removed_chat_boost"
        ]) {
            if (root.get(key).isSome()) {
                return key
            }
        }
        "unknown"
    }

    private func recordInboundDecision(
        updateId: String,
        updateKind: String,
        decision: String,
        reason: String,
        peerId!: String = "",
        senderId!: String = "",
        messageId!: String = ""
    ): Unit {
        this.lastInboundDecision = decision.trimAscii()
        this.lastInboundReason = reason.trimAscii()
        this.lastInboundUpdateKind = updateKind.trimAscii()
        this.lastInboundUpdateIdForPolicy = updateId.trimAscii()
        this.lastInboundPeerId = peerId.trimAscii()
        this.lastInboundSenderId = senderId.trimAscii()
        this.lastInboundMessageIdForPolicy = messageId.trimAscii()
    }

    private func applyTelegramMessageReceivedHook(
        inbound: InboundMessage,
        accepted!: Bool,
        reason!: String,
        raw!: String
    ): Unit {
        let _ = gatewayOpenClawPluginSidecarApplyCurrentMessageReceivedHook(
            "telegram",
            this.effectiveAccountId(),
            inbound.peerId,
            inbound.senderId,
            inbound.messageId,
            inbound.text,
            accepted,
            reason,
            raw
        )
    }

    private func applyIgnoredTelegramMessageReceivedHook(root: JsonObject, raw: String): Unit {
        let msg = match (this.pickPrimaryUpdateObject(root)) {
            case Some(v) => v
            case None => return
        }
        let messageId = this.readIntStringField(msg, "message_id")
        if (messageId.trimAscii().isEmpty()) {
            return
        }
        let mediaInfo = this.readTelegramMediaInfo(msg)
        let text = this.normalizeInboundTelegramCommandText(this.readInboundTelegramText(msg, mediaInfo: mediaInfo))
        let chat = this.readObjectField(msg, "chat")
        let from = this.readObjectField(msg, "from")
        let threadIdRaw = this.readIntStringField(msg, "message_thread_id")
        let peerId = this.telegramPeerId(chat, threadId: threadIdRaw)
        let senderId = this.readIntStringField(from, "id")
        let reason = if (this.lastInboundReason.trimAscii().isEmpty()) { "ignored" } else { this.lastInboundReason.trimAscii() }
        let _ = gatewayOpenClawPluginSidecarApplyCurrentMessageReceivedHook(
            "telegram",
            this.effectiveAccountId(),
            peerId,
            senderId,
            messageId,
            text,
            false,
            reason,
            raw
        )
    }

    private func detectMentionInMessage(msg: JsonObject, text: String): Bool {
        let normalized = text.trimAscii()
        if (normalized.isEmpty()) {
            return false
        }
        if (normalized.startsWith("/")) {
            return true
        }
        let chat = this.readObjectField(msg, "chat")
        let strictBotTarget = this.readStringField(chat, "type") != "private"
        if (this.telegramMessageHasMentionEntity(msg, normalized, "entities", strictBotTarget: strictBotTarget)) {
            return true
        }
        if (this.telegramMessageHasMentionEntity(msg, normalized, "caption_entities", strictBotTarget: strictBotTarget)) {
            return true
        }
        false
    }

    private func telegramMessageHasMentionEntity(msg: JsonObject, text: String, entityField: String, strictBotTarget!: Bool): Bool {
        match (msg.get(entityField)) {
            case Some(rawEntities) =>
                try {
                    let arr = rawEntities.asArray()
                    for (item in arr.getItems()) {
                        try {
                            let entity = item.asObject()
                            let entityType = this.readStringField(entity, "type").trimAscii()
                            if (entityType == "text_mention") {
                                if (!strictBotTarget) {
                                    return true
                                }
                                let botId = this.effectiveBotId()
                                let user = this.readObjectField(entity, "user")
                                let userId = this.readIntStringField(user, "id")
                                if (botId.isEmpty() || userId.isEmpty() || userId == botId) {
                                    return true
                                }
                            }
                            if (entityType == "mention") {
                                let segment = this.telegramEntitySlice(
                                    text,
                                    this.readJsonIntField(entity, "offset", -1),
                                    this.readJsonIntField(entity, "length", 0)
                                ).trimAscii()
                                if (segment.startsWith("@")) {
                                    if (!strictBotTarget) {
                                        return true
                                    }
                                    let botUsername = this.effectiveBotUsername().trimAscii().toAsciiLower()
                                    let mentionedUsername = segment[1..].trimAscii().toAsciiLower()
                                    if (botUsername.isEmpty() || mentionedUsername == botUsername) {
                                        return true
                                    }
                                }
                            }
                        } catch (_e: Exception) {
                            ()
                        }
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        false
    }

    private func effectiveBotUsername(): String {
        if (this.botUsernameLookupAttempted) {
            return this.cachedBotUsername
        }
        this.botUsernameLookupAttempted = true
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            return ""
        }
        let raw = this.tryTelegramGet("${this.normalizeApiRoot()}/bot${token}/getMe")
        let parsed = this.parseTelegramProbeResult(raw)
        if (!this.readJsonBoolField(parsed, "ok", false)) {
            return ""
        }
        let result = this.readObjectField(parsed, "result")
        this.cachedBotUsername = this.readStringField(result, "username").trimAscii()
        this.cachedBotUsername
    }

    private func acceptsInbound(message: InboundMessage): Bool {
        this.inboundRejectReason(message).isEmpty()
    }

    private func inboundRejectReason(message: InboundMessage): String {
        match (message.chatType) {
            case ChatType.Direct => return this.directInboundRejectReason(message)
            case ChatType.Group => return this.groupInboundRejectReason(message)
        }
    }

    private func maybeRecordTelegramGroupHistory(message: InboundMessage, rejectReason: String): Unit {
        if (!this.config.groupHistoryEnabled || rejectReason != "group_mention_required") {
            return
        }
        match (message.chatType) {
            case ChatType.Group => ()
            case ChatType.Direct => return
        }
        let peer = message.peerId.trimAscii()
        if (peer.isEmpty()) {
            return
        }
        let entry = JsonObject()
        entry.put("messageId", JsonString(message.messageId.trimAscii()))
        entry.put("senderId", JsonString(message.senderId.trimAscii()))
        entry.put("text", JsonString(message.text.trimAscii()))
        entry.put("reason", JsonString(rejectReason))
        entry.put("recordedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        synchronized(this.queueMutex) {
            let history = match (this.groupHistoryByPeer.get(peer)) {
                case Some(existing) => existing
                case None =>
                    let created = ArrayList<JsonObject>()
                    this.groupHistoryByPeer[peer] = created
                    created
            }
            history.add(entry)
            let limit = if (this.config.groupHistoryLimit <= 0) { 20 } else { this.config.groupHistoryLimit }
            while (history.size > limit) {
                history.remove(at: 0)
            }
        }
    }

    private func attachTelegramGroupHistoryContext(mediaContext: JsonObject, peerId: String, messageId: String): Unit {
        if (!this.config.groupHistoryEnabled) {
            return
        }
        let peer = peerId.trimAscii()
        if (peer.isEmpty()) {
            return
        }
        let records = JsonArray([])
        synchronized(this.queueMutex) {
            match (this.groupHistoryByPeer.get(peer)) {
                case Some(history) =>
                    for (item in history.toArray()) {
                        records.add(item)
                    }
                    history.clear()
                case None => ()
            }
        }
        if (records.size() == 0) {
            return
        }
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let groupHistory = JsonObject()
        groupHistory.put("source", JsonString("telegram-silent-ingest"))
        groupHistory.put("peerId", JsonString(peer))
        groupHistory.put("triggerMessageId", JsonString(messageId.trimAscii()))
        groupHistory.put("records", records)
        context.put("groupHistory", groupHistory)
        mediaContext.put("channel", JsonString("telegram"))
        mediaContext.put("accountId", JsonString(this.effectiveAccountId()))
        mediaContext.put("peerId", JsonString(peer))
        mediaContext.put("messageId", JsonString(messageId.trimAscii()))
        mediaContext.put("context", context)
    }

    private func directInboundRejectReason(message: InboundMessage): String {
        let policy = this.config.dmPolicy.trimAscii().toAsciiLower()
        if (policy == "disabled") {
            return "dm_disabled"
        }
        if (policy == "open") {
            if (this.allowlistContainsWildcard(this.config.allowFrom)) {
                return ""
            }
            return "dm_open_requires_wildcard"
        }
        if (policy == "allowlist") {
            if (this.senderAllowed(this.config.allowFrom, message.senderId)) {
                return ""
            }
            return "dm_sender_not_allowed"
        }
        if (policy == "pairing") {
            if (this.pairingStore.isApproved(message.senderId)) {
                return ""
            }
            let existingCode = this.pairingStore.pendingCodeForSender(message.senderId)
            let code = this.pairingStore.ensurePending(message.senderId)
            if (existingCode.isEmpty() && !code.isEmpty()) {
                this.sendPairingPrompt(message.senderId, code)
            }
            return "dm_pairing_required"
        }
        ""
    }

    private func sendPairingPrompt(senderId: String, code: String): Unit {
        let normalizedSender = senderId.trimAscii()
        let normalizedCode = code.trimAscii()
        if (normalizedSender.isEmpty() || normalizedCode.isEmpty()) {
            return
        }
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("text")
        body["peer"] = JsonString("user:${normalizedSender}")
        body["chat_id"] = JsonString(normalizedSender)
        body["text"] = JsonString(this.telegramEscapeHtml(
            "Pairing required. Approve this Telegram DM with: metis pairing approve telegram ${normalizedCode}"
        ))
        body["parse_mode"] = JsonString("HTML")
        body["disable_web_page_preview"] = true.toJsonValue()
        let sentMessageId = this.sendPayloadToTelegram(body)
        if (sentMessageId.isEmpty() && !this.lastSendError.trimAscii().isEmpty()) {
            LogUtils.info("Telegram pairing prompt failed sender=${normalizedSender}: ${this.lastSendError}")
        }
    }

    private func groupInboundRejectReason(message: InboundMessage): String {
        if (!this.groupIsAllowed(message.peerId)) {
            return "group_not_allowed"
        }
        let entry = this.resolveGroupEntry(message.peerId)
        let topicEntry = this.resolveTopicEntry(message.peerId, entry)
        let requireMention = this.groupRequiresMention(entry, topicEntry)
        if (requireMention && !message.mentioned) {
            return "group_mention_required"
        }
        let senderPolicy = this.effectiveGroupSenderPolicy(entry, topicEntry)
        if (senderPolicy == "disabled") {
            return "group_sender_policy_disabled"
        }
        if (senderPolicy == "open") {
            return ""
        }
        let allowFrom = this.effectiveGroupAllowFrom(entry, topicEntry)
        if (this.senderAllowed(allowFrom, message.senderId)) {
            return ""
        }
        "group_sender_not_allowed"
    }

    private func groupIsAllowed(peerId: String): Bool {
        let normalizedGroupId = this.normalizeGroupId(peerId)
        match (this.config.groups) {
            case Some(groups) =>
                match (groups.get(normalizedGroupId)) {
                    case Some(_) => return true
                    case None => return groups.get("*").isSome()
                }
            case None =>
                return this.config.groupPolicy.trimAscii().toAsciiLower() == "open"
        }
    }

    private func groupRequiresMention(entry: Option<JsonObject>, topicEntry: Option<JsonObject>): Bool {
        match (topicEntry) {
            case Some(topicCfg) =>
                match (this.readBoolFieldOpt(topicCfg, "requireMention")) {
                    case Some(v) => return v
                    case None => ()
                }
            case None => ()
        }
        match (entry) {
            case Some(groupCfg) =>
                match (this.readBoolFieldOpt(groupCfg, "requireMention")) {
                    case Some(v) => return v
                    case None => ()
                }
            case None => ()
        }
        this.config.policy.requireMentionInGroup
    }

    private func effectiveGroupSenderPolicy(entry: Option<JsonObject>, topicEntry: Option<JsonObject>): String {
        match (topicEntry) {
            case Some(topicCfg) =>
                let override = this.readStringField(topicCfg, "groupPolicy").trimAscii().toAsciiLower()
                if (!override.isEmpty()) {
                    return override
                }
            case None => ()
        }
        match (entry) {
            case Some(groupCfg) =>
                let override = this.readStringField(groupCfg, "groupPolicy").trimAscii().toAsciiLower()
                if (!override.isEmpty()) {
                    return override
                }
            case None => ()
        }
        this.config.groupPolicy.trimAscii().toAsciiLower()
    }

    private func effectiveGroupAllowFrom(entry: Option<JsonObject>, topicEntry: Option<JsonObject>): Array<String> {
        match (topicEntry) {
            case Some(topicCfg) =>
                let topicAllow = this.readStringArrayField(topicCfg, "allowFrom")
                if (!topicAllow.isEmpty()) {
                    return topicAllow
                }
            case None => ()
        }
        match (entry) {
            case Some(groupCfg) =>
                let groupAllow = this.readStringArrayField(groupCfg, "allowFrom")
                if (!groupAllow.isEmpty()) {
                    return groupAllow
                }
            case None => ()
        }
        if (!this.config.groupAllowFrom.isEmpty()) {
            return this.config.groupAllowFrom
        }
        this.config.allowFrom
    }

    private func senderAllowed(allowFrom: Array<String>, senderId: String): Bool {
        if (allowFrom.isEmpty()) {
            return false
        }
        let normalizedSenderId = this.normalizeTelegramUserId(senderId)
        for (raw in allowFrom) {
            let normalized = this.normalizeTelegramUserId(raw)
            if (normalized == "*" || normalized == normalizedSenderId) {
                return true
            }
        }
        false
    }

    private func allowlistContainsWildcard(allowFrom: Array<String>): Bool {
        for (raw in allowFrom) {
            if (this.normalizeTelegramUserId(raw) == "*") {
                return true
            }
        }
        false
    }

    private func normalizeTelegramUserId(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed == "*") {
            return "*"
        }
        if (trimmed.startsWith("telegram:")) {
            return trimmed["telegram:".size..].trimAscii()
        }
        if (trimmed.startsWith("tg:")) {
            return trimmed["tg:".size..].trimAscii()
        }
        if (trimmed.startsWith("user:")) {
            return trimmed["user:".size..].trimAscii()
        }
        trimmed
    }

    private func normalizeGroupId(peerId: String): String {
        if (peerId.startsWith("group:")) {
            let pure = peerId["group:".size..]
            match (pure.indexOf(":topic:")) {
                case Some(topicIdx) => return pure[..topicIdx]
                case None => return pure
            }
        }
        peerId.trimAscii()
    }

    private func resolveGroupEntry(peerId: String): Option<JsonObject> {
        let normalizedGroupId = this.normalizeGroupId(peerId)
        match (this.config.groups) {
            case Some(groups) =>
                match (this.readObjectFieldOpt(groups, normalizedGroupId)) {
                    case Some(v) => return Some(v)
                    case None => return this.readObjectFieldOpt(groups, "*")
                }
            case None => return None
        }
    }

    private func resolveTopicEntry(peerId: String, groupEntry: Option<JsonObject>): Option<JsonObject> {
        let threadId = this.extractThreadId(peerId)
        if (threadId.isEmpty()) {
            return None
        }
        match (groupEntry) {
            case Some(groupCfg) =>
                match (this.readObjectFieldOpt(groupCfg, "topics")) {
                    case Some(topics) =>
                        match (this.readObjectFieldOpt(topics, threadId)) {
                            case Some(v) => return Some(v)
                            case None => return this.readObjectFieldOpt(topics, "*")
                        }
                    case None => return None
                }
            case None => return None
        }
    }

    private func resolveDirectRouteEntry(peerId: String, senderId: String): Option<JsonObject> {
        match (this.config.dms) {
            case Some(dms) =>
                for (key in [senderId.trimAscii(), peerId.trimAscii(), "*"]) {
                    if (key.isEmpty()) {
                        continue
                    }
                    match (this.readObjectFieldOpt(dms, key)) {
                        case Some(v) => return Some(v)
                        case None => ()
                    }
                }
            case None => ()
        }
        this.config.direct
    }

    private func copyTelegramRouteConfigFields(target: JsonObject, entry: JsonObject): Unit {
        let agentId = this.readStringField(entry, "agentId").trimAscii()
        if (!agentId.isEmpty()) {
            target.put("agentId", JsonString(agentId))
        }
        let systemPrompt = this.readStringField(entry, "systemPrompt").trimAscii()
        if (!systemPrompt.isEmpty()) {
            target.put("systemPrompt", JsonString(systemPrompt))
        }
        let skills = this.readStringArrayField(entry, "skills")
        if (!skills.isEmpty()) {
            target.put("skills", skills.toJsonValue())
        }
        match (this.readBoolFieldOpt(entry, "disableAudioPreflight")) {
            case Some(v) => target.put("disableAudioPreflight", v.toJsonValue())
            case None => ()
        }
    }

    private func telegramRouteConfigFor(peerId: String, senderId: String, chatType: ChatType): JsonObject {
        let out = JsonObject()
        match (chatType) {
            case ChatType.Direct =>
                match (this.resolveDirectRouteEntry(peerId, senderId)) {
                    case Some(entry) => this.copyTelegramRouteConfigFields(out, entry)
                    case None => ()
                }
            case ChatType.Group =>
                let groupEntry = this.resolveGroupEntry(peerId)
                match (groupEntry) {
                    case Some(entry) => this.copyTelegramRouteConfigFields(out, entry)
                    case None => ()
                }
                match (this.resolveTopicEntry(peerId, groupEntry)) {
                    case Some(entry) => this.copyTelegramRouteConfigFields(out, entry)
                    case None => ()
                }
        }
        out
    }

    private func attachTelegramRouteConfigContext(mediaContext: JsonObject, peerId: String, senderId: String, chatType: ChatType): Unit {
        let route = this.telegramRouteConfigFor(peerId, senderId, chatType)
        if (route.size() == 0) {
            return
        }
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        context.put("telegramRoute", route)
        mediaContext.put("channel", JsonString("telegram"))
        mediaContext.put("accountId", JsonString(this.effectiveAccountId()))
        mediaContext.put("peerId", JsonString(peerId.trimAscii()))
        mediaContext.put("context", context)
    }

    private func telegramPeerId(chat: JsonObject, threadId!: String = ""): String {
        let chatId = this.readIntStringField(chat, "id")
        let chatType = this.readStringField(chat, "type")
        if (chatType == "private") {
            return "user:${chatId}"
        }
        let normalizedThreadId = threadId.trimAscii()
        if (!normalizedThreadId.isEmpty()) {
            return "group:${chatId}:topic:${normalizedThreadId}"
        }
        "group:${chatId}"
    }

    private func normalizePeerId(peerId: String): String {
        if (peerId.startsWith("user:")) {
            return peerId["user:".size..]
        }
        if (peerId.startsWith("group:")) {
            let pure = peerId["group:".size..]
            match (pure.indexOf(":topic:")) {
                case Some(topicIdx) => return this.resolveMigratedTelegramChatId(pure[..topicIdx])
                case None => ()
            }
            return this.resolveMigratedTelegramChatId(pure)
        }
        peerId
    }

    private func resolveMigratedTelegramChatId(chatId: String): String {
        let normalized = chatId.trimAscii()
        if (normalized.isEmpty()) {
            return normalized
        }
        let path = this.groupMigrationStatePath()
        if (!exists(path)) {
            return normalized
        }
        let migrations = try { JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray() } catch (_e: Exception) { JsonArray([]) }
        var latest = normalized
        for (item in migrations.getItems()) {
            let row = try { item.asObject() } catch (_e: Exception) { JsonObject() }
            let oldChatId = this.readStringField(row, "oldChatId").trimAscii()
            let newChatId = this.readStringField(row, "newChatId").trimAscii()
            if (oldChatId == latest && !newChatId.isEmpty() && newChatId != latest) {
                latest = newChatId
            }
        }
        latest
    }

    private func extractThreadId(peerId: String): String {
        match (peerId.indexOf(":topic:")) {
            case Some(idx) => return peerId[idx + ":topic:".size..]
            case None => return ""
        }
    }

    private func normalizeApiRoot(): String {
        let raw = this.config.apiRoot.trimAscii()
        if (raw.isEmpty()) {
            return "https://api.telegram.org"
        }
        if (raw.endsWith("/")) {
            return raw[..raw.size - 1]
        }
        raw
    }

    private func isPollingContext(context: String): Bool {
        let normalized = context.trimAscii()
        normalized == "getUpdates" || normalized.startsWith("deleteWebhook:")
    }

    private func recordTelegramRequestError(context: String, detail: String, outcome!: String = "request-error"): Unit {
        let message = this.redactTelegramSensitive("${context} ${detail}".trimAscii())
        if (this.isPollingContext(context)) {
            this.recordPollError(message, outcome: outcome)
        } else {
            this.setLastSendError(message)
        }
    }

    private func telegramTransport(): TelegramTransport {
        TelegramTransport(
            proxy: this.config.proxy,
            envProxyEnabled: this.config.network.envProxyEnabled,
            timeoutSeconds: if (this.config.timeoutSeconds > 0) { this.config.timeoutSeconds } else { 30 },
            insecureSkipTlsVerify: this.config.network.insecureSkipTlsVerify,
            dangerouslyAllowPrivateNetwork: this.config.network.dangerouslyAllowPrivateNetwork,
            autoSelectFamily: this.config.network.autoSelectFamily,
            dnsResultOrder: this.config.network.dnsResultOrder
        )
    }

    private func telegramGet(url: String, accept!: String, context!: String): Option<String> {
        this.handleTelegramTransportResponse(this.telegramTransport().get(url, accept: accept, context: context), context)
    }

    private func telegramGetBytes(url: String, accept!: String, context!: String): Option<Array<Byte>> {
        this.handleTelegramTransportBytesResponse(this.telegramTransport().get(url, accept: accept, context: context), context)
    }

    private func telegramJsonPost(url: String, body: JsonObject, context!: String): Option<String> {
        this.handleTelegramTransportResponse(this.telegramTransport().postJson(url, body, context: context), context)
    }

    private func telegramMultipartPost(
        url: String,
        payload: HashMap<String, JsonValue>,
        fileField: String,
        filePath: String,
        context!: String
    ): Option<String> {
        this.handleTelegramTransportResponse(
            this.telegramTransport().postMultipartFile(
                url,
                this.telegramMultipartFieldsForPayload(payload, fileField),
                fileField,
                filePath,
                context: context
            ),
            context
        )
    }

    private func telegramMultipartFilesPost(
        url: String,
        fields: HashMap<String, String>,
        files: Array<TelegramMultipartFile>,
        context!: String
    ): Option<String> {
        this.handleTelegramTransportResponse(
            this.telegramTransport().postMultipartFiles(url, fields, files, context: context),
            context
        )
    }

    private func handleTelegramTransportResponse(response: TelegramTransportResponse, context: String): Option<String> {
        if (response.ok) {
            return Some(response.body)
        }
        let outcome = if (response.outcome.trimAscii().isEmpty()) { "request-error" } else { response.outcome.trimAscii() }
        let detail = this.redactTelegramSensitive(if (response.error.trimAscii().isEmpty()) { "transport failed" } else { response.error.trimAscii() })
        if (context.startsWith("send:") || context == "setWebhook" || context.startsWith("deleteWebhook:") ||
            context == "setMyCommands" || context == "answerCallbackQuery" || context.startsWith("editMessageReplyMarkup:")) {
            this.setLastSendError(detail)
        }
        this.recordTelegramRequestError(context, "transport failed: ${detail}", outcome: outcome)
        LogUtils.info("Telegram ${context} failed: ${context} transport failed: ${detail}")
        None
    }

    private func handleTelegramTransportBytesResponse(response: TelegramTransportResponse, context: String): Option<Array<Byte>> {
        if (response.ok) {
            if (!response.bodyBytes.isEmpty()) {
                return Some(response.bodyBytes)
            }
            if (!response.body.isEmpty()) {
                return Some(response.body.toArray())
            }
            return Some([])
        }
        let outcome = if (response.outcome.trimAscii().isEmpty()) { "request-error" } else { response.outcome.trimAscii() }
        let detail = this.redactTelegramSensitive(if (response.error.trimAscii().isEmpty()) { "transport failed" } else { response.error.trimAscii() })
        this.recordTelegramRequestError(context, "transport failed: ${detail}", outcome: outcome)
        LogUtils.info("Telegram ${context} failed: ${context} transport failed: ${detail}")
        None
    }

    private func setLastSendError(message: String): Unit {
        this.lastSendError = this.redactTelegramSensitive(message)
    }

    private func redactTelegramSensitive(message: String): String {
        var out = TelegramTransport().redactUrl(message)
        let token = this.effectiveBotToken().trimAscii()
        if (!token.isEmpty()) {
            out = out.replace(token, "<redacted>")
        }
        let proxy = this.config.proxy.trimAscii()
        if (!proxy.isEmpty()) {
            out = out.replace(proxy, this.redactTelegramProxy(proxy))
        }
        out
    }

    private func redactTelegramProxy(proxy: String): String {
        match (proxy.indexOf("://")) {
            case Some(schemeIdx) =>
                let prefixEnd = schemeIdx + 3
                let rest = proxy[prefixEnd..]
                match (rest.indexOf("@")) {
                    case Some(atIdx) => proxy[..prefixEnd] + "<redacted>@" + rest[atIdx + 1..]
                    case None => proxy
                }
            case None => proxy
        }
    }

    private func readStringField(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_e: Exception) { "" }
            case None => ""
        }
    }

    private func readBoolFieldOpt(obj: JsonObject, key: String): Option<Bool> {
        match (obj.get(key)) {
            case Some(v) =>
                try { Some(v.asBool().getValue()) } catch (_e: Exception) { None }
            case None => None
        }
    }

    private func readStringArrayField(obj: JsonObject, key: String): Array<String> {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    let arr = ArrayList<String>()
                    for (item in v.asArray().getItems()) {
                        try {
                            arr.add(item.asString().getValue())
                        } catch (_e: Exception) {
                            ()
                        }
                    }
                    arr.toArray()
                } catch (_e: Exception) {
                    []
                }
            case None => []
        }
    }

    private func readIntStringField(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) => match (v) {
                case s: JsonString => s.getValue().trimAscii()
                case n: JsonInt => n.getValue().toString()
                case n: JsonFloat => Int64(n.getValue()).toString()
                case _ => ""
            }
            case None => ""
        }
    }

    private func readFloatStringField(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) => match (v) {
                case s: JsonString => s.getValue().trimAscii()
                case n: JsonInt => n.getValue().toString()
                case n: JsonFloat => n.getValue().toString()
                case _ => ""
            }
            case None => ""
        }
    }

    private func readObjectField(obj: JsonObject, key: String): JsonObject {
        match (this.readObjectFieldOpt(obj, key)) {
            case Some(v) => v
            case None => JsonObject()
        }
    }

    private func readObjectFieldOpt(obj: JsonObject, key: String): Option<JsonObject> {
        match (obj.get(key)) {
            case Some(v) =>
                try { Some(v.asObject()) } catch (_e: Exception) { None }
            case None => None
        }
    }
}
