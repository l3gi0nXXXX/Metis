package metis.gateway.channels.telegram

import metis.core.{parseGatewayAudioParts, parseGatewayDocumentParts, parseGatewayEditText, parseGatewayInlineKeyboardParts, parseGatewayPhotoParts, parseGatewayReactionToken, parseGatewayStickerFileId, parseGatewayTopicCreateText, parseGatewayTopicEditText, parseGatewayVideoNoteFileId, parseGatewayVideoParts, parseGatewayVoiceParts}
import metis.gateway.core.ChannelAdapter
import metis.gateway.model.*
import metis.io.PrintUtils
import metis.core.config.CliConfig

import magic.log.LogUtils
import magic.jsonable.*

import std.collection.{ArrayList, HashMap, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, Path, canonicalize, exists}
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

    public init(
        kind: String,
        fileId: String,
        fileUniqueId!: String = "",
        mimeType!: String = "",
        fileSize!: Int64 = 0,
        fileName!: String = "",
        mediaGroupId!: String = "",
        caption!: String = ""
    ) {
        this.kind = kind
        this.fileId = fileId
        this.fileUniqueId = fileUniqueId
        this.mimeType = mimeType
        this.fileSize = fileSize
        this.fileName = fileName
        this.mediaGroupId = mediaGroupId
        this.caption = caption
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
    private var pollingRunner: Option<TelegramPollingRunner> = None<TelegramPollingRunner>
    private var telegramTransportRebuildCount: Int64 = 0
    private var running = false
    private var webhookServer: Option<Server> = None
    private var lastSendError: String = ""
    private var nativeCommandsLastSyncStatus: String = "not-attempted"
    private var nativeCommandsLastSyncError: String = ""
    private var nativeCommandsLastSyncAtMs: Int64 = 0
    private var nativeCommandsLastSyncCommandCount: Int64 = 0
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
        this.running = false
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
            if (!this.running || this.inboundQueue.isEmpty()) {
                return []
            }
            let out = this.inboundQueue.toArray()
            this.inboundQueue.clear()
            out
        }
    }

    public func send(message: OutboundMessage): SendResult {
        let sentMessageId = this.sendWithMessageId(message)
        if (!sentMessageId.trimAscii().isEmpty() || this.lastSendError.trimAscii().isEmpty()) {
            return SendResult.Success
        }
        SendResult.Failed("failed to send telegram message: ${this.lastSendError}")
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        if (!this.running) {
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
            if (this.payloadIsDelete(payload) && !this.config.actions.deleteMessage) {
                this.lastSendError = "telegram deleteMessage action is disabled"
                return ""
            }
            if (this.payloadIsEdit(payload) && !this.config.actions.editMessage) {
                this.lastSendError = "telegram editMessage action is disabled"
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
            let sentMessageId = this.sendPayloadToTelegram(payload)
            if (sentMessageId.isEmpty()) {
                return ""
            }
            lastMessageId = sentMessageId
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

    public func debugIngestPollingResponse(raw: String): Int64 {
        this.ingestPollingResponse(raw)
    }

    public func debugFetchTelegramUpdatesRaw(): String {
        this.fetchTelegramUpdates()
    }

    public func debugRunPollingIterationForTest(): Int64 {
        this.runPollingIteration()
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

    public func debugPersistInboundMediaForTest(
        kind: String,
        fileId: String,
        caption!: String = "",
        fileUniqueId!: String = "",
        mimeType!: String = "",
        fileSize!: Int64 = 0,
        fileName!: String = "",
        mediaGroupId!: String = "",
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
        secretHeader.trimAscii() == expected
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
        for (kind in ["message", "edited_message", "channel_post", "edited_channel_post"]) {
            updates.add(JsonString(kind))
        }
        let notifications = this.config.reactionNotifications.trimAscii().toAsciiLower()
        if (!(notifications == "off" || notifications == "false" || notifications == "disabled")) {
            updates.add(JsonString("message_reaction"))
        }
        if (this.config.actions.callbackQuery || this.config.actions.inlineKeyboard) {
            updates.add(JsonString("callback_query"))
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
            let secret = ctx.request.headers.getFirst("X-Telegram-Bot-Api-Secret-Token") ??
                ctx.request.headers.getFirst("x-telegram-bot-api-secret-token") ??
                ""
            if (!this.validateWebhookSecretHeader(secret)) {
                ctx.responseBuilder.status(403)
                ctx.responseBuilder.body("{\"ok\":false,\"error\":\"webhook_secret_mismatch\"}")
                return
            }
            let payload = this.readRequestBody(ctx)
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
        let responseOpt = this.telegramJsonPost(
            this.normalizeApiRoot() + "/bot${token}/setWebhook",
            this.buildWebhookRegistrationPayload(),
            context: "setWebhook"
        )
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

    private func readRequestBody(ctx: HttpContext): String {
        try {
            let output = ArrayList<Byte>()
            let buffer = Array<Byte>(8192, repeat: 0)
            while (true) {
                let n = ctx.request.body.read(buffer)
                if (n <= 0) {
                    break
                }
                output.add(all: buffer[..n])
            }
            String.fromUtf8(output.toArray())
        } catch (_e: Exception) {
            ""
        }
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
        let text = this.normalizeInboundTelegramCommandText(this.readInboundTelegramText(msg))
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
        let replyTarget: Option<String> = match (this.readObjectFieldOpt(msg, "reply_to_message")) {
            case Some(reply) =>
                let replyId = this.readIntStringField(reply, "message_id")
                if (replyId.isEmpty()) { None<String> } else { Some(replyId) }
            case None => None<String>
        }
        let mentioned = this.detectMention(text)
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
            accountId: this.effectiveAccountId()
        )
        match (this.readTelegramMediaInfo(msg)) {
            case Some(info) =>
                this.persistInboundMedia(info)
            case None => ()
        }
        let rejectReason = this.inboundRejectReason(inbound)
        if (!rejectReason.isEmpty()) {
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

    private func readInboundTelegramText(msg: JsonObject): String {
        let text = this.readStringField(msg, "text").trimAscii()
        if (!text.isEmpty()) {
            return text
        }
        match (this.readTelegramMediaInfo(msg)) {
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
                }
                return String.join(lines.toArray(), delimiter: "\n")
            case None => ""
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
            caption: caption
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
            "[telegram-callback]\nid=${callbackId}\nmessageId=${messageId}\nby=${senderId}"
        } else {
            "[telegram-callback]\nid=${callbackId}\nmessageId=${messageId}\ndata=${data}\nby=${senderId}"
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
        Some(inbound)
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
            return this.sendDraftPayloadToTelegram(url, payload)
        }
        let responseOpt = match (this.localMediaUploadForPayload(kind, payload)) {
            case Some(upload) => this.telegramMultipartPost(url, payload, upload[0], upload[1], context: "send:${kind}:multipart")
            case None => this.telegramJsonPost(url, this.telegramApiBodyForPayload(payload, plainFallback: false), context: "send:${kind}")
        }
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.setLastSendError("empty http response")
                return ""
        }
        if (let Some(messageId) <- this.parseTelegramPayloadSuccess(kind, responseRaw)) {
            return messageId
        }
        if (kind == "poll" || kind == "delete" || kind == "topic-create" || kind == "reaction" || kind == "sticker") {
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
                this.setLastSendError("empty http response")
                return ""
        }
        this.parseTelegramPayloadSuccess(kind, plainResponseRaw) ?? ""
    }

    private func sendDraftPayloadToTelegram(url: String, payload: HashMap<String, JsonValue>): String {
        let draftPayload = HashMap<String, JsonValue>()
        for ((key, value) in payload) {
            if (key == "final_text" || key == "plain_final_text") {
                continue
            }
            draftPayload[key] = value
        }
        draftPayload["kind"] = JsonString("text")
        let responseOpt = this.telegramJsonPost(url, this.telegramApiBodyForPayload(draftPayload, plainFallback: false), context: "send:draft")
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.setLastSendError("empty http response")
                return ""
        }
        let messageId = match (this.parseTelegramSendSuccess(responseRaw)) {
            case Some(id) => id
            case None => return ""
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

    private func telegramApiBodyForPayload(payload: HashMap<String, JsonValue>, plainFallback!: Bool): JsonObject {
        let out = JsonObject()
        for ((key, value) in payload) {
            if (key == "kind" || key == "peer" || key == "plain_text" || key == "plain_caption") {
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

    private func telegramMediaFieldForPayloadKind(kind: String): String {
        if (kind == "photo") { return "photo" }
        if (kind == "document") { return "document" }
        if (kind == "audio") { return "audio" }
        if (kind == "voice") { return "voice" }
        if (kind == "video") { return "video" }
        if (kind == "video-note") { return "video_note" }
        if (kind == "sticker") { return "sticker" }
        ""
    }

    private func telegramMultipartFieldsForPayload(payload: HashMap<String, JsonValue>, fileField: String): HashMap<String, String> {
        let out = HashMap<String, String>()
        for ((key, value) in payload) {
            if (key == "kind" || key == "peer" || key == "plain_text" || key == "plain_caption" || key == fileField) {
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
        if (kind == "delete" || kind == "reaction" || kind == "edit") {
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
        out.put("offset", offset)
        out.put("account", account)
        out.put("media", media)
        out.put("polling", polling)
        out.put("inboundPolicy", inboundPolicy)
        out.put("webhookLifecycle", this.buildWebhookLifecycleDiagnostics())
        out.put("nativeCommands", this.buildNativeCommandDiagnostics())
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
            empty.put("accountId", JsonString(this.effectiveAccountId()))
            empty.put("lastPersistedMediaId", JsonString(""))
            empty.put("lastMedia", JsonObject())
            empty
        }
    }

    private func persistInboundMedia(
        info: TelegramInboundMediaInfo,
        getFileRaw!: String = "",
        downloadRaw!: String = ""
    ): Unit {
        let normalizedKind = info.kind.trimAscii().toAsciiLower()
        let normalizedFileId = info.fileId.trimAscii()
        if (normalizedKind.isEmpty() || normalizedFileId.isEmpty()) {
            return
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
            } else if (!filePath.isEmpty() && !this.isSafeTelegramFilePath(filePath)) {
                skippedReason = "unsafe_file_path"
            } else if (!filePath.isEmpty()) {
                let resolvedDownloadRaw = if (!downloadRaw.trimAscii().isEmpty()) {
                    downloadRaw
                } else {
                    this.tryTelegramDownloadFile(filePath)
                }
                if (!resolvedDownloadRaw.isEmpty()) {
                    if (this.mediaSizeExceedsLimit(Int64(resolvedDownloadRaw.toArray().size))) {
                        skippedReason = "download_size_limit_exceeded"
                    } else {
                        downloadPath = this.persistDownloadedMediaBytes(normalizedFileId, resolvedDownloadRaw)
                        downloaded = !downloadPath.isEmpty()
                    }
                }
            }
        }
        let lastMedia = JsonObject()
        lastMedia.put("kind", JsonString(normalizedKind))
        lastMedia.put("fileId", JsonString(normalizedFileId))
        lastMedia.put("fileUniqueId", JsonString(info.fileUniqueId))
        lastMedia.put("mimeType", JsonString(effectiveMime))
        lastMedia.put("fileSize", effectiveSize.toJsonValue())
        lastMedia.put("fileName", JsonString(info.fileName))
        lastMedia.put("mediaGroupId", JsonString(info.mediaGroupId))
        lastMedia.put("albumPolicy", JsonString(this.effectiveMediaAlbumPolicy()))
        lastMedia.put("caption", JsonString(info.caption.trimAscii()))
        lastMedia.put("filePath", JsonString(filePath))
        lastMedia.put("downloaded", downloaded.toJsonValue())
        lastMedia.put("downloadPath", JsonString(downloadPath))
        lastMedia.put("skippedReason", JsonString(skippedReason))
        lastMedia.put("persistedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
        let root = JsonObject()
        root.put("accountId", JsonString(this.effectiveAccountId()))
        root.put("downloadEnabled", this.config.media.downloadEnabled.toJsonValue())
        root.put("mediaMaxBytes", this.effectiveMediaMaxBytes().toJsonValue())
        root.put("allowedMimes", this.mediaAllowedMimesJson())
        root.put("albumPolicy", JsonString(this.effectiveMediaAlbumPolicy()))
        root.put("lastPersistedMediaId", JsonString(normalizedFileId))
        root.put("lastMedia", lastMedia)
        File.writeTo(this.mediaStatePath(), root.toJsonString().toArray())
    }

    private func tryTelegramGetFile(fileId: String): String {
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            return ""
        }
        let apiRoot = this.normalizeApiRoot()
        this.tryTelegramGet("${apiRoot}/bot${token}/getFile?file_id=${fileId}")
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

    private func tryTelegramDownloadFile(filePath: String): String {
        let normalized = filePath.trimAscii()
        let token = this.effectiveBotToken()
        if (normalized.isEmpty() || token.isEmpty()) {
            return ""
        }
        let url = this.normalizeApiRoot() + "/file/bot${token}/${normalized}"
        match (this.telegramGet(url, accept: "*/*", context: "downloadFile")) {
            case Some(raw) => raw
            case None => ""
        }
    }

    private func persistDownloadedMediaBytes(fileId: String, raw: String): String {
        if (raw.isEmpty()) {
            return ""
        }
        let safeId = fileId.trimAscii().replace("/", "_").replace(":", "_").replace("\\", "_")
        let path = this.mediaDownloadDir().join("${safeId}.download")
        File.writeTo(path, raw.toArray())
        path.toString()
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
        this.nativeCommandsLastSyncCommandCount = this.resolvedTelegramCommandMenu().size
        let token = this.effectiveBotToken()
        if (token.isEmpty()) {
            this.setNativeCommandsSyncError("bot token is empty")
            return false
        }
        let responseOpt = this.telegramJsonPost(
            this.normalizeApiRoot() + "/bot${token}/setMyCommands",
            this.buildNativeCommandsPayload(),
            context: "setMyCommands"
        )
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.setNativeCommandsSyncError("empty http response")
                LogUtils.info("Telegram setMyCommands failed: ${this.lastSendError}")
                return false
        }
        let ok = this.parseTelegramBoolSuccess(responseRaw, missingDetail: "telegram setMyCommands returned ok=false")
        if (!ok) {
            this.setNativeCommandsSyncError(this.lastSendError)
            LogUtils.info("Telegram setMyCommands failed: ${this.lastSendError}")
        } else {
            this.nativeCommandsLastSyncStatus = "ok"
            this.nativeCommandsLastSyncError = ""
        }
        ok
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
        out.put("lastSyncStatus", JsonString(this.nativeCommandsLastSyncStatus))
        out.put("lastSyncError", JsonString(this.nativeCommandsLastSyncError))
        out.put("lastSyncAtMs", this.nativeCommandsLastSyncAtMs.toJsonValue())
        out.put("lastSyncCommandCount", this.nativeCommandsLastSyncCommandCount.toJsonValue())
        out
    }

    private func buildNativeCommandsPayload(): JsonObject {
        let commands = JsonArray([])
        for ((command, description) in this.resolvedTelegramCommandMenu()) {
            let item = JsonObject()
            item.put("command", JsonString(command))
            item.put("description", JsonString(description))
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
                ("activation", "Set activation mode"),
                ("pair", "Manage pairing")
            ]) {
                rows.add((command, description))
                seen[command] = true
            }
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
        match (this.detectPollPayload(message.text)) {
            case Some(spec) => return [this.buildPollPayload(message, spec[0], spec[1])]
            case None => ()
        }
        match (this.detectDeletePayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectEditPayload(message)) {
            case Some(payload) => return [payload]
            case None => ()
        }
        match (this.detectReactionPayload(message)) {
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
        let replyToMessageId = this.effectiveReplyToMessageId(message.replyToMessageId)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        for (i in 0..chunks.size) {
            let body = HashMap<String, JsonValue>()
            body["kind"] = JsonString("text")
            body["peer"] = JsonString(normalizedPeer)
            body["chat_id"] = JsonString(chatId)
            body["text"] = JsonString(this.telegramEscapeHtml(chunks[i]))
            body["plain_text"] = JsonString(chunks[i])
            body["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
            body["parse_mode"] = JsonString("HTML")
            this.applyTelegramSilentOption(body)
            if (!threadId.isEmpty() && replyInThread) {
                body["message_thread_id"] = JsonString(threadId)
            }
            if (this.shouldAttachReplyTargetToChunk(i)) {
                if (let Some(replyId) <- replyToMessageId) {
                    if (!replyId.trimAscii().isEmpty()) {
                        body["reply_to_message_id"] = JsonString(replyId.trimAscii())
                    }
                }
            }
            out.add(body)
        }
        out.toArray()
    }

    private func buildPollPayload(message: OutboundMessage, question: String, options: Array<String>): HashMap<String, JsonValue> {
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
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        body
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

    private func buildEditPayload(message: OutboundMessage, targetMessageId: String, content: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("edit")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        body["text"] = JsonString(this.telegramEscapeHtml(content))
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
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("reaction")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(this.normalizePeerId(normalizedPeer))
        body["message_id"] = JsonString(targetMessageId)
        let reaction = JsonObject()
        reaction.put("type", JsonString("emoji"))
        reaction.put("emoji", JsonString(token))
        let reactions = JsonArray([])
        reactions.add(reaction)
        body["reaction"] = reactions
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
        body["text"] = JsonString(this.telegramEscapeHtml(text))
        body["plain_text"] = JsonString(text)
        body["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
        body["parse_mode"] = JsonString("HTML")
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
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
        if (rows.size() <= 0) {
            body["validation_error"] = JsonString("telegram inlineKeyboard requires at least one valid button")
            return body
        }
        let markup = JsonObject()
        markup.put("inline_keyboard", rows)
        body["reply_markup"] = markup
        body
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
        body["text"] = JsonString(this.telegramEscapeHtml(preview))
        body["plain_text"] = JsonString(preview)
        body["final_text"] = JsonString(this.telegramEscapeHtml(finalText))
        body["plain_final_text"] = JsonString(finalText)
        body["disable_web_page_preview"] = (!this.config.linkPreview).toJsonValue()
        body["parse_mode"] = JsonString("HTML")
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
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
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
        body
    }

    private func buildPhotoPayload(message: OutboundMessage, fileId: String, caption: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("photo")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["photo"] = JsonString(fileId)
        if (!caption.trimAscii().isEmpty()) {
            body["caption"] = JsonString(this.telegramEscapeHtml(caption))
            body["plain_caption"] = JsonString(caption)
            body["parse_mode"] = JsonString("HTML")
        }
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
        body
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
        if (!caption.trimAscii().isEmpty()) {
            body["caption"] = JsonString(this.telegramEscapeHtml(caption))
            body["plain_caption"] = JsonString(caption)
            body["parse_mode"] = JsonString("HTML")
        }
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
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
        if (!caption.trimAscii().isEmpty()) {
            body["caption"] = JsonString(this.telegramEscapeHtml(caption))
            body["plain_caption"] = JsonString(caption)
            body["parse_mode"] = JsonString("HTML")
        }
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
        body
    }

    private func buildVoicePayload(message: OutboundMessage, fileId: String, caption: String): HashMap<String, JsonValue> {
        let normalizedPeer = message.peerId.trimAscii()
        let chatId = this.normalizePeerId(normalizedPeer)
        let threadId = this.extractThreadId(normalizedPeer)
        let replyInThread = this.effectiveReplyInThread(message.replyInThread)
        let body = HashMap<String, JsonValue>()
        body["kind"] = JsonString("voice")
        body["peer"] = JsonString(normalizedPeer)
        body["chat_id"] = JsonString(chatId)
        body["voice"] = JsonString(fileId)
        if (!caption.trimAscii().isEmpty()) {
            body["caption"] = JsonString(this.telegramEscapeHtml(caption))
            body["plain_caption"] = JsonString(caption)
            body["parse_mode"] = JsonString("HTML")
        }
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
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
        if (!caption.trimAscii().isEmpty()) {
            body["caption"] = JsonString(this.telegramEscapeHtml(caption))
            body["plain_caption"] = JsonString(caption)
            body["parse_mode"] = JsonString("HTML")
        }
        this.applyTelegramSilentOption(body)
        if (!threadId.isEmpty() && replyInThread) {
            body["message_thread_id"] = JsonString(threadId)
        }
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
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
        if (let Some(replyId) <- this.effectiveReplyToMessageId(message.replyToMessageId)) {
            if (!replyId.trimAscii().isEmpty()) {
                body["reply_to_message_id"] = JsonString(replyId.trimAscii())
            }
        }
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

    private func payloadIsEdit(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "edit" } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func payloadIsReaction(payload: HashMap<String, JsonValue>): Bool {
        match (payload.get("kind")) {
            case Some(v) => try { v.asString().getValue().trimAscii().toAsciiLower() == "reaction" } catch (_e: Exception) { false }
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
            this.payloadIsDocument(payload) ||
            this.payloadIsAudio(payload) ||
            this.payloadIsVoice(payload) ||
            this.payloadIsVideo(payload) ||
            this.payloadIsVideoNote(payload)
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
        if (kind == "edit") {
            return "editMessageText"
        }
        if (kind == "reaction") {
            return "setMessageReaction"
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

    private func detectPollPayload(text: String): Option<(String, Array<String>)> {
        let normalized = text.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
        if (!normalized.startsWith("[poll]")) {
            return None
        }
        let lines = normalized.split("\n")
        if (lines.size < 2) {
            return None
        }
        let title = lines[1].trimAscii()
        let options = ArrayList<String>()
        if (lines.size > 2) {
            var i = 2
            while (i < lines.size) {
                let raw = lines[i].trimAscii()
                if (!raw.isEmpty()) {
                    let parsed = this.parsePollOptionLine(raw)
                    if (!parsed.isEmpty()) {
                        options.add(parsed)
                    }
                }
                i += 1
            }
        }
        if (title.isEmpty() || options.isEmpty()) {
            return None
        }
        Some((title, options.toArray()))
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
        let token = parseGatewayReactionToken(message.text)
        if (token.isEmpty()) {
            return None
        }
        match (message.replyToMessageId) {
            case Some(target) =>
                let trimmed = target.trimAscii()
                if (trimmed.isEmpty()) { None } else { Some(this.buildReactionPayload(message, trimmed, token)) }
            case None => None
        }
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

    private func telegramEscapeHtml(text: String): String {
        text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
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
        for (key in ["message", "edited_message", "channel_post", "edited_channel_post", "message_reaction", "callback_query"]) {
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

    private func detectMention(text: String): Bool {
        let normalized = text.trimAscii()
        if (normalized.isEmpty()) {
            return false
        }
        if (normalized.contains("@")) {
            return true
        }
        if (normalized.startsWith("/")) {
            return true
        }
        false
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
                case Some(topicIdx) => return pure[..topicIdx]
                case None => ()
            }
            return pure
        }
        peerId
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
            timeoutSeconds: if (this.config.timeoutSeconds > 0) { this.config.timeoutSeconds } else { 30 }
        )
    }

    private func telegramGet(url: String, accept!: String, context!: String): Option<String> {
        this.handleTelegramTransportResponse(this.telegramTransport().get(url, accept: accept, context: context), context)
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

    private func handleTelegramTransportResponse(response: TelegramTransportResponse, context: String): Option<String> {
        if (response.ok) {
            return Some(response.body)
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
