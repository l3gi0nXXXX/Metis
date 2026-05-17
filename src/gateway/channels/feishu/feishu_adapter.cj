package metis.gateway.channels.feishu

import metis.core.parseGatewayEditText
import metis.core.config.CliConfig
import metis.gateway.core.ChannelAdapter
import metis.gateway.model.*
import metis.gateway.model.FeishuConfig
import metis.io.PrintUtils
import metis.utils.ShellUtils
import magic.utils.http.HttpUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.env.getVariable
import std.fs.{Directory, File, Path, canonicalize, exists}
import std.io.*
import std.process.*
import std.time.DateTime
import std.sync.Mutex
import stdx.encoding.url.*
import stdx.encoding.json.*
import stdx.net.http.*
import stdx.net.tls.*

/**
 * Feishu 渠道适配器（P0 基础实现）。
 *
 * 说明：
 * - 当前版本主要用于打通 Gateway 链路，采用“内存队列 + 模拟入站”方式；
 * - 后续你可以将 simulateIncomingText 替换为真实事件来源（WebSocket 或 webhook）；
 * - send() 当前仅记录已发送消息，后续替换为 Feishu API 调用。
 */
public interface FeishuApiClient {
    func isThreadCapableGroup(chatId: String): Bool
    func fetchMessageResource(accountId: String, messageId: String, fileKey: String, resourceType: String): FeishuResourceDownloadResult
    func sendTextMessage(accountId: String, rawPeerId: String, receiveId: String, receiveIdType: String, text: String, replyToMessageId: Option<String>, replyInThread: Bool): FeishuApiSendResult
    func sendInteractiveCard(accountId: String, rawPeerId: String, receiveId: String, receiveIdType: String, card: FeishuInteractiveCard, replyToMessageId: Option<String>, replyInThread: Bool): FeishuApiSendResult
    func patchInteractiveCard(accountId: String, messageId: String, card: FeishuInteractiveCard): FeishuApiSendResult
}

public class FeishuResourceDownloadResult {
    public let ok: Bool
    public let status: String
    public let bytes: Array<Byte>
    public let contentType: String
    public let fileName: String
    public let error: String

    public init(
        ok!: Bool = false,
        status!: String = "not_configured",
        bytes!: Array<Byte> = [],
        contentType!: String = "",
        fileName!: String = "",
        error!: String = ""
    ) {
        this.ok = ok
        this.status = if (status.trimAscii().isEmpty()) { if (ok) { "ok" } else { "error" } } else { status.trimAscii() }
        this.bytes = bytes
        this.contentType = contentType.trimAscii()
        this.fileName = fileName.trimAscii()
        this.error = error.trimAscii()
    }
}

public class FeishuNoopApiClient <: FeishuApiClient {
    public init() {}

    public func isThreadCapableGroup(_chatId: String): Bool {
        false
    }

    public func fetchMessageResource(
        _accountId: String,
        _messageId: String,
        _fileKey: String,
        _resourceType: String
    ): FeishuResourceDownloadResult {
        FeishuResourceDownloadResult(status: "not_configured", error: "feishu api client is not configured")
    }

    public func sendTextMessage(
        _accountId: String,
        _rawPeerId: String,
        _receiveId: String,
        _receiveIdType: String,
        _text: String,
        _replyToMessageId: Option<String>,
        _replyInThread: Bool
    ): FeishuApiSendResult {
        FeishuApiSendResult(status: "not_configured", error: "feishu api client is not configured")
    }

    public func sendInteractiveCard(
        _accountId: String,
        _rawPeerId: String,
        _receiveId: String,
        _receiveIdType: String,
        _card: FeishuInteractiveCard,
        _replyToMessageId: Option<String>,
        _replyInThread: Bool
    ): FeishuApiSendResult {
        FeishuApiSendResult(status: "not_configured", error: "feishu api client is not configured")
    }

    public func patchInteractiveCard(_accountId: String, _messageId: String, _card: FeishuInteractiveCard): FeishuApiSendResult {
        FeishuApiSendResult(status: "not_configured", error: "feishu api client is not configured")
    }
}

public class FeishuFakeApiClient <: FeishuApiClient {
    private let threadCapable = HashMap<String, Bool>()
    private let threadCapabilityCheckCounts = HashMap<String, Int64>()
    private let resources = HashMap<String, FeishuResourceDownloadResult>()
    private let textMessages = ArrayList<String>()
    private let sentCards = ArrayList<FeishuInteractiveCard>()
    private let patchedCards = ArrayList<FeishuInteractiveCard>()
    private var nextCardSendFailureStatus: String = ""
    private var nextCardSendFailureError: String = ""
    private var nextCardPatchFailureStatus: String = ""
    private var nextCardPatchFailureError: String = ""

    public init() {}

    public func setThreadCapable(chatId: String, capable: Bool): Unit {
        this.threadCapable[chatId.trimAscii()] = capable
    }

    public func isThreadCapableGroup(chatId: String): Bool {
        let normalized = chatId.trimAscii()
        this.threadCapabilityCheckCounts[normalized] = (this.threadCapabilityCheckCounts.get(normalized) ?? 0) + 1
        this.threadCapable.get(normalized) ?? false
    }

    public func threadCapabilityChecks(chatId: String): Int64 {
        this.threadCapabilityCheckCounts.get(chatId.trimAscii()) ?? 0
    }

    public func setResource(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String,
        bytes: Array<Byte>,
        contentType!: String = "",
        fileName!: String = ""
    ): Unit {
        this.resources[this.resourceKey(accountId, messageId, fileKey, resourceType)] =
            FeishuResourceDownloadResult(
                ok: true,
                status: "ok",
                bytes: bytes,
                contentType: contentType,
                fileName: fileName
            )
    }

    public func setResourceError(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String,
        status: String,
        error!: String = ""
    ): Unit {
        this.resources[this.resourceKey(accountId, messageId, fileKey, resourceType)] =
            FeishuResourceDownloadResult(status: status, error: error)
    }

    public func fetchMessageResource(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String
    ): FeishuResourceDownloadResult {
        this.resources.get(this.resourceKey(accountId, messageId, fileKey, resourceType)) ??
            FeishuResourceDownloadResult(status: "not_found", error: "fake resource not registered")
    }

    public func sendTextMessage(
        accountId: String,
        rawPeerId: String,
        receiveId: String,
        receiveIdType: String,
        text: String,
        _replyToMessageId: Option<String>,
        _replyInThread: Bool
    ): FeishuApiSendResult {
        this.textMessages.add("${this.normalize(accountId)}|${rawPeerId.trimAscii()}|${receiveId.trimAscii()}|${receiveIdType.trimAscii()}|${text}")
        FeishuApiSendResult(ok: true, status: "ok", messageId: "fake-feishu-text-${this.textMessages.size}")
    }

    public func sendInteractiveCard(
        _accountId: String,
        _rawPeerId: String,
        _receiveId: String,
        _receiveIdType: String,
        card: FeishuInteractiveCard,
        _replyToMessageId: Option<String>,
        _replyInThread: Bool
    ): FeishuApiSendResult {
        this.sentCards.add(card)
        if (!this.nextCardSendFailureStatus.trimAscii().isEmpty()) {
            let status = this.nextCardSendFailureStatus.trimAscii()
            let error = this.nextCardSendFailureError.trimAscii()
            this.nextCardSendFailureStatus = ""
            this.nextCardSendFailureError = ""
            return FeishuApiSendResult(status: status, error: error)
        }
        FeishuApiSendResult(ok: true, status: "ok", messageId: "fake-feishu-card-${this.sentCards.size}")
    }

    public func patchInteractiveCard(_accountId: String, _messageId: String, card: FeishuInteractiveCard): FeishuApiSendResult {
        this.patchedCards.add(card)
        if (!this.nextCardPatchFailureStatus.trimAscii().isEmpty()) {
            let status = this.nextCardPatchFailureStatus.trimAscii()
            let error = this.nextCardPatchFailureError.trimAscii()
            this.nextCardPatchFailureStatus = ""
            this.nextCardPatchFailureError = ""
            return FeishuApiSendResult(status: status, error: error)
        }
        FeishuApiSendResult(ok: true, status: "ok", messageId: _messageId.trimAscii())
    }

    public func cardSendCount(): Int64 {
        this.sentCards.size
    }

    public func textSendCount(): Int64 {
        this.textMessages.size
    }

    public func lastTextMessage(): String {
        if (this.textMessages.isEmpty()) {
            return ""
        }
        this.textMessages[this.textMessages.size - 1]
    }

    public func cardPatchCount(): Int64 {
        this.patchedCards.size
    }

    public func failNextCardSend(status: String, error!: String = ""): Unit {
        this.nextCardSendFailureStatus = if (status.trimAscii().isEmpty()) { "error" } else { status.trimAscii() }
        this.nextCardSendFailureError = error.trimAscii()
    }

    public func failNextCardPatch(status: String, error!: String = ""): Unit {
        this.nextCardPatchFailureStatus = if (status.trimAscii().isEmpty()) { "error" } else { status.trimAscii() }
        this.nextCardPatchFailureError = error.trimAscii()
    }

    public func sentCard(index: Int64): FeishuInteractiveCard {
        this.sentCards.get(index) ?? FeishuInteractiveCard()
    }

    public func patchedCard(index: Int64): FeishuInteractiveCard {
        this.patchedCards.get(index) ?? FeishuInteractiveCard()
    }

    private func resourceKey(accountId: String, messageId: String, fileKey: String, resourceType: String): String {
        "${this.normalize(accountId)}|${messageId.trimAscii()}|${fileKey.trimAscii()}|${resourceType.trimAscii().toAsciiLower()}"
    }

    private func normalize(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) { "default" } else { trimmed }
    }
}

public class FeishuEventReplayLiveSmokeChecklist {
    public static func optInEnvName(): String {
        "METIS_FEISHU_LIVE_EVENT_REPLAY_SMOKE"
    }

    public static func isOptInValueEnabled(value: String): Bool {
        let normalized = value.trimAscii().toAsciiLower()
        normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on"
    }

    public static func toJson(): JsonObject {
        let root = JsonObject()
        root.put("optInRequired", JsonBool(true))
        root.put("optInEnv", JsonString(FeishuEventReplayLiveSmokeChecklist.optInEnvName()))
        root.put("defaultNetwork", JsonString("disabled"))
        root.put("redaction", JsonString("live event fixtures must be redacted before persistence: remove tokens, authorization headers, secrets, tenant credentials, and private user content"))
        root.put("matrix", JsonArray([
            JsonString("message"),
            JsonString("post"),
            JsonString("image"),
            JsonString("file"),
            JsonString("audio"),
            JsonString("video"),
            JsonString("interactive"),
            JsonString("reaction"),
            JsonString("drive"),
            JsonString("bot"),
            JsonString("vc"),
            JsonString("bitable")
        ]))
        root
    }

    public static func skippedExternalResourceReport(): JsonObject {
        let root = FeishuEventReplayLiveSmokeChecklist.toJson()
        root.put("status", JsonString("skipped"))
        root.put("reason", JsonString("external-resource-required"))
        root.put("networkAttempted", JsonBool(false))
        root.put("redacted", JsonBool(true))
        root.put("requiredExternalResources", JsonArray([
            JsonString("test_event_subscription"),
            JsonString("message/post/image/file/audio/video/card/reaction/drive/membership/vc/bitable"),
            JsonString("quote"),
            JsonString("merged_forward"),
            JsonString("resource_fetch_diagnostics"),
            JsonString("redacted_live_event_replay_fixture"),
            JsonString("isolated_test_tenant")
        ]))
        root
    }
}

public class FeishuAdapter <: ChannelAdapter {
    private var running = false
    private let queueMutex = Mutex()
    private let inboundQueue = ArrayList<InboundMessage>()
    private let outboundLog = ArrayList<OutboundMessage>()
    private let baseConfig: FeishuConfig
    private let config: FeishuConfig
    private var webhookServer: Option<Server> = None
    private var tenantAccessToken: String = ""
    private var tokenExpireAtNano: Int64 = 0
    private let tenantAccessTokens = HashMap<String, String>()
    private let tenantAccessTokenExpiries = HashMap<String, Int64>()
    private var lastSendError: String = ""
    private let threadCapabilityCache = HashMap<String, Bool>()
    private let feishuMonitorLock = Mutex()
    private var feishuMonitorProcess: Option<SubProcess> = None
    private var feishuMonitorStdIn: Option<StringWriter<OutputStream>> = None
    private var feishuMonitorStdoutFuture: Option<Future<Unit>> = None
    private var feishuMonitorStderrFuture: Option<Future<Unit>> = None
    private var feishuMonitorWaitFuture: Option<Future<Unit>> = None
    private var feishuMonitorReady: Bool = false
    private var feishuMonitorLastError: String = ""
    private let accountId: String
    private let chatQueue = FeishuChatQueue()
    private let apiClient: FeishuApiClient
    private let eventDedup = HashMap<String, Bool>()

    public init(
        config!: FeishuConfig = FeishuConfig(),
        accountId!: String = "default",
        apiClient!: FeishuApiClient = FeishuNoopApiClient()
    ) {
        let trimmedAccountId = accountId.trimAscii()
        let requestedAccountId = if (trimmedAccountId.isEmpty()) { config.accountId } else { trimmedAccountId }
        let resolved = gatewayFeishuResolveAccount(config, requestedAccountId)
        this.baseConfig = config
        this.config = resolved.config
        this.accountId = resolved.accountId
        this.apiClient = apiClient
        feishuInstallGatewayNativeAuthRunner()
    }

    public prop name: String {
        get() { "feishu" }
    }

    public func debugAccountIdForTest(): String {
        this.accountId
    }

    public func start(): Unit {
        if (this.running) {
            return
        }
        if (!this.config.enabled) {
            PrintUtils.printLine("Feishu adapter: disabled (account=${this.accountId}).")
            return
        }
        this.running = true
        if (this.config.receiveMode == "webhook") {
            this.startWebhookServer()
            return
        }
        if (this.config.appId.isEmpty() || this.config.appSecret.isEmpty()) {
            PrintUtils.printLine("Feishu long_connect: gateway.feishu.appId / gateway.feishu.appSecret is required.")
            return
        }
        if (!this.feishuOfficialSdkMonitorHostEnabled()) {
            PrintUtils.printLine(
                "Feishu long_connect: official SDK monitor host is required. Check scripts/feishu-ws-sidecar.mjs and tools/feishu-official-sdk."
            )
            return
        }
        if (!this.startFeishuOfficialSdkMonitorHost()) {
            PrintUtils.printLine(
                "Feishu inbound unavailable: official SDK monitor host failed to start: ${this.feishuOfficialSdkMonitorError()}"
            )
        }
    }

    /** 便于 demo / 日志打印完整回调地址。 */
    public func webhookListenUrlForLog(): String {
        "http://${this.config.webhookHost}:${this.config.webhookPort}${this.config.webhookPath}"
    }

    public func healthzUrlForLog(): String {
        "http://${this.config.webhookHost}:${this.config.webhookPort}/healthz"
    }

    /** 常驻服务启动后的入口说明（长连接模式无本地 webhook 地址）。 */
    public func printFeishuIngressHints(): Unit {
        if (this.config.receiveMode == "webhook") {
            PrintUtils.printLine("Feishu webhook: ${this.webhookListenUrlForLog()}")
            PrintUtils.printLine("Health: ${this.healthzUrlForLog()}")
        } else {
            PrintUtils.printLine(feishuMonitorHostIngressHintText())
        }
    }

    public func stop(): Unit {
        this.running = false
        this.stopFeishuOfficialSdkMonitorHost()
        if (let Some(server) <- this.webhookServer) {
            try {
                server.close()
            } catch (_e: Exception) {
                // Ignore close failure in stop path.
            } finally {
                this.webhookServer = None
            }
        }
    }

    /**
     * 批量拉取并清空当前待处理入站消息。
     */
    public func pullInbound(): Array<InboundMessage> {
        if (!this.running) {
            return []
        }
        let result = ArrayList<InboundMessage>()
        synchronized(this.queueMutex) {
            if (!this.inboundQueue.isEmpty()) {
                result.add(all: this.inboundQueue.toArray())
                this.inboundQueue.clear()
            }
        }
        result.toArray()
    }

    /**
     * 发送消息到飞书（P0：仅落到本地日志）。
     */
    public func send(message: OutboundMessage): SendResult {
        if (!this.running) {
            return SendResult.Failed("feishu adapter is not running")
        }
        let sentMessageId = this.sendWithMessageId(message)
        if (!sentMessageId.trimAscii().isEmpty()) {
            return SendResult.Success
        }
        return SendResult.Failed("failed to send message via feishu api: ${this.lastSendError}")
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        if (!this.running) {
            return ""
        }
        let accountId = this.outboundAccountId(message)
        let sentMessageId = if (this.feishuShouldPatchInteractiveCard(message)) {
            this.patchInteractiveCardForOutbound(accountId, message)
        } else if (this.feishuShouldUseInteractiveCardForOutbound(accountId, message)) {
            this.sendInteractiveCardForOutbound(accountId, message)
        } else {
            this.sendTextToFeishuWithMessageIdForAccount(
                accountId,
                message.peerId,
                message.text,
                replyToMessageId: message.replyToMessageId,
                replyInThread: message.replyInThread
            )
        }
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
        }
        sentMessageId
    }

    private func feishuShouldPatchInteractiveCard(message: OutboundMessage): Bool {
        if (message.replyToMessageId.isNone()) {
            return false
        }
        !parseGatewayEditText(message.text).isEmpty()
    }

    private func feishuShouldUseInteractiveCardForOutbound(accountId: String, message: OutboundMessage): Bool {
        if (message.text.trimAscii().isEmpty()) {
            return false
        }
        if (this.feishuShouldPatchInteractiveCard(message)) {
            return false
        }
        let mode = this.feishuConfigForAccount(accountId).streaming.trimAscii().toAsciiLower()
        mode != "off" && mode != "text"
    }

    private func patchInteractiveCardForOutbound(accountId: String, message: OutboundMessage): String {
        let targetMessageId = message.replyToMessageId.getOrThrow().trimAscii()
        if (targetMessageId.isEmpty()) {
            return ""
        }
        let text = parseGatewayEditText(message.text)
        let result = this.apiClient.patchInteractiveCard(accountId, targetMessageId, FeishuInteractiveCard(title: "Metis", text: text))
        if (result.ok) {
            this.lastSendError = ""
            return if (!result.messageId.isEmpty()) { result.messageId } else { targetMessageId }
        }
        if (result.status != "not_configured") {
            this.lastSendError = if (result.error.isEmpty()) { result.status } else { result.error }
        }
        ""
    }

    private func sendInteractiveCardForOutbound(accountId: String, message: OutboundMessage): String {
        let receiveId = this.normalizeSendTarget(message.peerId)
        if (receiveId.isEmpty()) {
            this.lastSendError = "peerId is empty"
            return ""
        }
        let card = FeishuInteractiveCard(title: "Metis", text: message.text)
        let result = this.apiClient.sendInteractiveCard(
            accountId,
            message.peerId,
            receiveId,
            this.resolveReceiveIdType(message.peerId),
            card,
            message.replyToMessageId,
            message.replyInThread
        )
        if (result.ok && !result.messageId.isEmpty()) {
            this.lastSendError = ""
            return result.messageId
        }
        if (result.status != "not_configured") {
            this.lastSendError = if (result.error.isEmpty()) { result.status } else { result.error }
        }
        this.sendTextToFeishuWithMessageIdForAccount(
            accountId,
            message.peerId,
            card.fallbackText(),
            replyToMessageId: message.replyToMessageId,
            replyInThread: message.replyInThread
        )
    }

    public func sendInteractiveCardToFeishu(
        chatId: String,
        card: FeishuInteractiveCard,
        replyToMessageId!: Option<String> = None,
        replyInThread!: Bool = false
    ): String {
        if (!this.running) {
            return ""
        }
        let accountId = this.effectiveAccountId()
        let receiveId = this.normalizeSendTarget(chatId)
        if (receiveId.isEmpty()) {
            this.lastSendError = "chatId is empty"
            return ""
        }
        let result = this.apiClient.sendInteractiveCard(
            accountId,
            chatId,
            receiveId,
            this.resolveReceiveIdType(chatId),
            card,
            replyToMessageId,
            replyInThread
        )
        if (result.ok && !result.messageId.isEmpty()) {
            this.lastSendError = ""
            return result.messageId
        }
        if (result.status != "not_configured") {
            this.lastSendError = if (result.error.isEmpty()) { result.status } else { result.error }
        }
        this.sendTextToFeishuWithMessageIdForAccount(accountId, chatId, card.fallbackText(), replyToMessageId: replyToMessageId, replyInThread: replyInThread)
    }

    public func patchInteractiveCardInFeishu(messageId: String, card: FeishuInteractiveCard): Bool {
        if (!this.running) {
            return false
        }
        let result = this.apiClient.patchInteractiveCard(this.effectiveAccountId(), messageId, card)
        if (result.ok) {
            this.lastSendError = ""
            return true
        }
        if (result.status != "not_configured") {
            this.lastSendError = if (result.error.isEmpty()) { result.status } else { result.error }
        }
        false
    }

    /**
     * P1 入口：处理飞书 webhook 原始 JSON。
     *
     * 返回值：
     * - URL 校验请求：返回包含 challenge 的 JSON 字符串；
     * - 普通事件请求：返回 {"ok":true}；
     * - 非法请求：返回 {"ok":false,...}。
     *
     * 说明：
     * - 该方法只负责“解析并入队”，由上层 gateway.processOnce() 继续处理。
     * - 当前未做签名校验，后续可扩展 token/signature 校验逻辑。
     */
    public func ingestWebhookPayload(payload: String): String {
        let root = try {
            JsonValue.fromStr(payload).asObject()
        } catch (e: Exception) {
            PrintUtils.printLine("Feishu ingest: invalid json")
            return "{\"ok\":false,\"error\":\"invalid_json\"}"
        }

        // 飞书 URL 校验事件
        if (let Some(typeVal) <- root.get("type")) {
            if (typeVal.asString().getValue() == "url_verification") {
                let challenge = match (root.get("challenge")) {
                    case Some(v) => v.asString().getValue()
                    case None => ""
                }
                return "{\"challenge\":\"${challenge}\"}"
            }
        }

        return this.feishuDispatchEventRoot(root)
    }

    /**
     * 处理飞书事件 JSON（Webhook 与长连接共用）：入队 im.message.receive_v1 文本消息。
     */
    private func feishuDispatchEventRoot(root: JsonObject): String {
        let headerEventType = this.readHeaderEventType(root)
        match (this.validateFeishuEventOwnership(root)) {
            case Some(reason) => return this.feishuIgnoredResponse(reason, eventType: headerEventType)
            case None => ()
        }
        if (this.feishuEventIsStale(root)) {
            return this.feishuIgnoredResponse("stale_event", eventType: headerEventType)
        }
        if (headerEventType == "card.action.trigger") {
            if (let Some(inbound) <- this.mapCardActionToInbound(root)) {
                if (!this.tryRecordFeishuEvent(inbound.accountId, inbound.messageId)) {
                    return this.feishuIgnoredResponse("duplicate_event", eventType: headerEventType)
                }
                synchronized(this.queueMutex) {
                    this.inboundQueue.add(inbound)
                }
                return "{\"ok\":true}"
            }
            return this.feishuIgnoredResponse("malformed_event", eventType: headerEventType)
        }
        if (headerEventType == "im.message.reaction.created_v1" || headerEventType == "im.message.reaction.deleted_v1") {
            if (let Some(inbound) <- this.mapReactionEventToInbound(root)) {
                if (!this.tryRecordFeishuEvent(inbound.accountId, inbound.messageId)) {
                    return this.feishuIgnoredResponse("duplicate_event", eventType: headerEventType)
                }
                this.chatQueue.runExclusive(inbound.accountId, inbound.peerId, inbound.threadId ?? "", { =>
                    synchronized(this.queueMutex) {
                        this.inboundQueue.add(inbound)
                    }
                })
                return "{\"ok\":true}"
            }
            return this.feishuIgnoredResponse("malformed_event", eventType: headerEventType)
        }
        if (headerEventType == "drive.file.comment.created_v1" ||
            headerEventType == "drive.file.comment.updated_v1" ||
            headerEventType == "drive.file.comment.deleted_v1") {
            if (let Some(inbound) <- this.mapDriveCommentEventToInbound(root)) {
                if (!this.tryRecordFeishuEvent(inbound.accountId, inbound.messageId)) {
                    return this.feishuIgnoredResponse("duplicate_event", eventType: headerEventType)
                }
                synchronized(this.queueMutex) {
                    this.inboundQueue.add(inbound)
                }
                return "{\"ok\":true}"
            }
            return this.feishuIgnoredResponse("malformed_event", eventType: headerEventType)
        }
        if (headerEventType == "im.chat.member.bot.added_v1" || headerEventType == "im.chat.member.bot.deleted_v1") {
            if (let Some(inbound) <- this.mapBotMembershipEventToInbound(root)) {
                if (!this.tryRecordFeishuEvent(inbound.accountId, inbound.messageId)) {
                    return this.feishuIgnoredResponse("duplicate_event", eventType: headerEventType)
                }
                synchronized(this.queueMutex) {
                    this.inboundQueue.add(inbound)
                }
                return "{\"ok\":true}"
            }
            return this.feishuIgnoredResponse("malformed_event", eventType: headerEventType)
        }
        if (headerEventType == "vc.meeting.invited_v1" || headerEventType == "vc.meeting.meeting_invited_v1") {
            if (let Some(inbound) <- this.mapVcInvitedEventToInbound(root)) {
                if (!this.tryRecordFeishuEvent(inbound.accountId, inbound.messageId)) {
                    return this.feishuIgnoredResponse("duplicate_event", eventType: headerEventType)
                }
                synchronized(this.queueMutex) {
                    this.inboundQueue.add(inbound)
                }
                return "{\"ok\":true}"
            }
            return this.feishuIgnoredResponse("malformed_event", eventType: headerEventType)
        }
        if (headerEventType == "bitable.field.changed_v1" || headerEventType == "bitable.field.updated_v1") {
            if (let Some(inbound) <- this.mapBitableFieldChangedEventToInbound(root)) {
                if (!this.tryRecordFeishuEvent(inbound.accountId, inbound.messageId)) {
                    return this.feishuIgnoredResponse("duplicate_event", eventType: headerEventType)
                }
                synchronized(this.queueMutex) {
                    this.inboundQueue.add(inbound)
                }
                return "{\"ok\":true}"
            }
            return this.feishuIgnoredResponse("malformed_event", eventType: headerEventType)
        }
        if (!headerEventType.isEmpty() && headerEventType != "im.message.receive_v1") {
            PrintUtils.printLine("Feishu ingest: ignore event_type=${headerEventType}")
            return this.feishuIgnoredResponse("unsupported_event", eventType: headerEventType)
        }

        if (let Some(inbound) <- this.mapWebhookToInbound(root)) {
            if (!this.tryRecordFeishuEvent(inbound.accountId, inbound.messageId)) {
                return this.feishuIgnoredResponse("duplicate_event", eventType: headerEventType)
            }
            PrintUtils.printLine(
                "Feishu ingest: mapped messageId=${inbound.messageId}, chat=${inbound.peerId}, sender=${inbound.senderId}, mentioned=${inbound.mentioned}"
            )
            this.chatQueue.runExclusive(inbound.accountId, inbound.peerId, inbound.threadId ?? "", { =>
                synchronized(this.queueMutex) {
                    this.inboundQueue.add(inbound)
                }
            })
            return "{\"ok\":true}"
        }
        PrintUtils.printLine("Feishu ingest: no text message mapped (non-text or missing fields), event_type=${headerEventType}")
        let diagnostic = this.feishuMessageIgnoredDiagnostic(root, headerEventType)
        return this.feishuIgnoredResponse(diagnostic[0], eventType: headerEventType, messageType: diagnostic[1])
    }

    private func feishuIgnoredResponse(reason: String, eventType!: String = "", messageType!: String = ""): String {
        let root = JsonObject()
        root.put("ok", JsonBool(true))
        root.put("ignored", JsonBool(true))
        root.put("reason", JsonString(if (reason.trimAscii().isEmpty()) { "ignored" } else { reason.trimAscii() }))
        if (!eventType.trimAscii().isEmpty()) {
            root.put("eventType", JsonString(eventType.trimAscii()))
        }
        if (!messageType.trimAscii().isEmpty()) {
            root.put("messageType", JsonString(messageType.trimAscii()))
        }
        root.toJsonString()
    }

    private func feishuMessageIgnoredDiagnostic(root: JsonObject, eventType: String): (String, String) {
        if (!eventType.trimAscii().isEmpty() && eventType != "im.message.receive_v1") {
            return ("unsupported_event", "")
        }
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { return ("malformed_event", "") }
            case None => return ("malformed_event", "")
        }
        let messageObj = match (event.get("message")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { return ("malformed_event", "") }
            case None => return ("malformed_event", "")
        }
        match (event.get("sender")) {
            case Some(v) =>
                let sender = try { v.asObject() } catch (_e: Exception) { return ("malformed_event", "") }
                match (sender.get("sender_id")) {
                    case Some(idv) =>
                        let senderIdObj = try { idv.asObject() } catch (_e: Exception) { return ("malformed_event", "") }
                        if (this.extractSenderId(senderIdObj).trimAscii().isEmpty()) {
                            return ("malformed_event", "")
                        }
                    case None => return ("malformed_event", "")
                }
            case None => return ("malformed_event", "")
        }
        let messageType = this.readStringField(messageObj, "message_type").trimAscii().toAsciiLower()
        if (!this.feishuMessageTypeSupported(messageType)) {
            return ("unsupported_message_type", messageType)
        }
        ("malformed_event", messageType)
    }

    private func feishuMessageTypeSupported(messageType: String): Bool {
        let normalized = messageType.trimAscii().toAsciiLower()
        normalized == "text" ||
            normalized == "post" ||
            normalized == "image" ||
            normalized == "file" ||
            normalized == "audio" ||
            normalized == "video" ||
            normalized == "media" ||
            normalized == "interactive" ||
            normalized == "merge_forward" ||
            normalized == "sticker" ||
            normalized == "share_chat" ||
            normalized == "share_user"
    }

    private func validateFeishuEventOwnership(root: JsonObject): Option<String> {
        let accountId = this.resolveFeishuAccountIdWithoutApp(root)
        let cfg = this.feishuConfigForAccount(accountId)
        let expectedAppId = cfg.appId.trimAscii()
        if (expectedAppId.isEmpty()) {
            return None<String>
        }
        let eventAppId = this.readFeishuEventAppId(root)
        if (eventAppId.isEmpty()) {
            return None<String>
        }
        if (eventAppId != expectedAppId) {
            PrintUtils.printLine("Feishu ingest: wrong app for account=${accountId}, event app_id mismatch")
            return Some("wrong_app")
        }
        None<String>
    }

    private func readFeishuEventAppId(root: JsonObject): String {
        let header = match (root.get("header")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["app_id", "appId"]) {
            let value = this.readStringField(header, key).trimAscii()
            if (!value.isEmpty()) {
                return value
            }
        }
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["app_id", "appId"]) {
            let value = this.readStringField(event, key).trimAscii()
            if (!value.isEmpty()) {
                return value
            }
        }
        ""
    }

    private func resolveFeishuAccountIdWithoutApp(root: JsonObject): String {
        let header = match (root.get("header")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["account_id", "accountId", "tenant_key", "tenantKey"]) {
            let value = this.readStringField(header, key).trimAscii()
            if (!value.isEmpty()) {
                return this.normalizeAccountId(value)
            }
        }
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["account_id", "accountId", "tenant_key", "tenantKey"]) {
            let value = this.readStringField(event, key).trimAscii()
            if (!value.isEmpty()) {
                return this.normalizeAccountId(value)
            }
        }
        this.effectiveAccountId()
    }

    private func feishuEventIsStale(root: JsonObject): Bool {
        let timestamp = this.readFeishuEventTimestampMs(root)
        if (timestamp <= 0) {
            return false
        }
        let now = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let skewMs = this.config.requestMaxSkewSeconds * 1000
        timestamp + skewMs < now
    }

    private func readFeishuEventTimestampMs(root: JsonObject): Int64 {
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["action_time", "event_time", "invite_time", "create_time"]) {
            let parsed = this.parseFeishuTimestampMs(this.readStringField(event, key))
            if (parsed > 0) {
                return parsed
            }
        }
        let message = match (event.get("message")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["create_time", "update_time"]) {
            let parsed = this.parseFeishuTimestampMs(this.readStringField(message, key))
            if (parsed > 0) {
                return parsed
            }
        }
        0
    }

    private func parseFeishuTimestampMs(raw: String): Int64 {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) {
            return 0
        }
        try {
            let parsed = Int64.parse(trimmed)
            if (parsed > 0 && parsed < 10_000_000_000) {
                return parsed * 1000
            }
            parsed
        } catch (_e: Exception) {
            0
        }
    }

    private func tryRecordFeishuEvent(accountId: String, eventKey: String): Bool {
        let normalizedKey = eventKey.trimAscii()
        if (normalizedKey.isEmpty()) {
            return true
        }
        let key = "${this.normalizeAccountId(accountId)}:${normalizedKey}"
        var recorded = false
        synchronized(this.queueMutex) {
            if (this.eventDedup.get(key) ?? false) {
                recorded = false
            } else {
                this.eventDedup[key] = true
                recorded = true
            }
        }
        recorded
    }

    private func mapCardActionToInbound(root: JsonObject): Option<InboundMessage> {
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let context = match (event.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let actionObj = match (event.get("action")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let valueObj = match (actionObj.get("value")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let operatorObj = match (event.get("operator")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let action = this.firstNonEmpty([
            this.readStringField(valueObj, "action"),
            this.readStringField(valueObj, "actionId"),
            this.readStringField(valueObj, "key"),
            this.readStringField(actionObj, "tag")
        ])
        if (action.isEmpty()) {
            return None<InboundMessage>
        }
        let accountId = this.resolveFeishuAccountId(root)
        let messageId = this.firstNonEmpty([
            this.readStringField(context, "open_message_id"),
            this.readStringField(context, "message_id"),
            this.readStringField(context, "messageId")
        ])
        let peerId = this.firstNonEmpty([
            this.readStringField(context, "open_chat_id"),
            this.readStringField(context, "chat_id"),
            this.readStringField(context, "chatId")
        ])
        let operatorId = this.firstNonEmpty([
            this.readStringField(operatorObj, "open_id"),
            this.readStringField(operatorObj, "openId"),
            this.readStringField(operatorObj, "user_id"),
            this.readStringField(operatorObj, "userId")
        ])
        let effectivePeerId = if (peerId.isEmpty()) { operatorId } else { peerId }
        if (effectivePeerId.isEmpty()) {
            return None<InboundMessage>
        }
        let threadId = this.firstNonEmpty([
            this.readStringField(context, "open_thread_id"),
            this.readStringField(context, "thread_id"),
            this.readStringField(context, "threadId")
        ])
        let mediaContext = JsonObject()
        mediaContext.put("channel", JsonString("feishu"))
        mediaContext.put("accountId", JsonString(accountId))
        mediaContext.put("peerId", JsonString(effectivePeerId))
        mediaContext.put("messageId", JsonString(messageId))
        let contextObj = JsonObject()
        let actionContext = JsonObject()
        actionContext.put("action", JsonString(action))
        actionContext.put("operatorId", JsonString(operatorId))
        actionContext.put("messageId", JsonString(messageId))
        actionContext.put("peerId", JsonString(effectivePeerId))
        actionContext.put("threadId", JsonString(threadId))
        actionContext.put("status", JsonString("accepted"))
        contextObj.put("feishuCardAction", actionContext)
        mediaContext.put("context", contextObj)
        let inboundId = "card:${if (messageId.isEmpty()) { "unknown-message" } else { messageId }}:${if (operatorId.isEmpty()) { "unknown-operator" } else { operatorId }}:${action}"
        let chatType = if (effectivePeerId.startsWith("oc_")) { ChatType.Group } else { ChatType.Direct }
        Some(InboundMessage(
            ChannelType.Feishu,
            inboundId,
            effectivePeerId,
            operatorId,
            chatType,
            "[feishu-card-action]\naction=${action}\nmessageId=${messageId}\nby=${operatorId}",
            true,
            DateTime.now(),
            conversationId: Some(effectivePeerId),
            threadId: if (threadId.isEmpty()) { None<String> } else { Some(threadId) },
            replyTargetMessageId: if (messageId.isEmpty()) { None<String> } else { Some(messageId) },
            raw: Some(root.toJsonString()),
            accountId: accountId,
            mediaContext: mediaContext,
            systemEvent: true,
            systemEventKind: "feishu.card_action"
        ))
    }

    private func mapReactionEventToInbound(root: JsonObject): Option<InboundMessage> {
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { return None<InboundMessage> }
            case None => return None<InboundMessage>
        }
        let reactionTypeObj = match (event.get("reaction_type")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let userIdObj = match (event.get("user_id")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let accountId = this.resolveFeishuAccountId(root)
        let messageId = this.readStringField(event, "message_id")
        let chatId = this.readStringField(event, "chat_id")
        let threadId = this.readStringField(event, "thread_id")
        let chatTypeRaw = this.readStringField(event, "chat_type")
        let operatorId = this.firstNonEmpty([
            this.readStringField(userIdObj, "open_id"),
            this.readStringField(userIdObj, "user_id"),
            this.readStringField(userIdObj, "union_id")
        ])
        let emojiType = this.firstNonEmpty([
            this.readStringField(reactionTypeObj, "emoji_type"),
            this.readStringField(reactionTypeObj, "emojiType"),
            this.readStringField(event, "reaction_type")
        ])
        if (messageId.trimAscii().isEmpty() || chatId.trimAscii().isEmpty() || operatorId.trimAscii().isEmpty()) {
            return None<InboundMessage>
        }
        let chatType = if (chatTypeRaw == "p2p") { ChatType.Direct } else { ChatType.Group }
        let cfg = this.feishuConfigForAccount(accountId)
        let mediaContext = JsonObject()
        this.attachFeishuImRouteContext(mediaContext, cfg, accountId, chatId, chatType, operatorId, messageId, "", threadId)
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let reaction = JsonObject()
        let eventType = this.readHeaderEventType(root)
        reaction.put("messageId", JsonString(messageId.trimAscii()))
        reaction.put("operatorId", JsonString(operatorId.trimAscii()))
        reaction.put("emojiType", JsonString(emojiType.trimAscii()))
        reaction.put("chatId", JsonString(chatId.trimAscii()))
        reaction.put("threadId", JsonString(threadId.trimAscii()))
        reaction.put("eventType", JsonString(eventType))
        reaction.put("status", JsonString("accepted"))
        reaction.put("operatorEvidence", this.feishuOperatorEvidence(
            operatorId,
            if (eventType == "im.message.reaction.deleted_v1") { "reaction_deleted" } else { "reaction_created" },
            eventType: eventType,
            messageId: messageId,
            chatId: chatId,
            accountId: accountId
        ))
        reaction.put("resourceFetch", this.feishuNoResourceFetchDiagnostic("not_required", reason: "reaction events do not carry downloadable message resources"))
        context.put("feishuReaction", reaction)
        mediaContext.put("context", context)
        let inboundId = "reaction:${messageId.trimAscii()}:${operatorId.trimAscii()}:${emojiType.trimAscii()}"
        Some(InboundMessage(
            ChannelType.Feishu,
            inboundId,
            chatId.trimAscii(),
            operatorId.trimAscii(),
            chatType,
            "[feishu-reaction]\nmessageId=${messageId.trimAscii()}\nreaction=${emojiType.trimAscii()}\nby=${operatorId.trimAscii()}",
            true,
            DateTime.now(),
            conversationId: this.resolveConversationId(cfg, chatId, chatType, operatorId, messageId, "", threadId),
            threadId: if (threadId.trimAscii().isEmpty()) { None<String> } else { Some(threadId.trimAscii()) },
            replyTargetMessageId: Some(messageId.trimAscii()),
            raw: Some(root.toJsonString()),
            accountId: accountId,
            mediaContext: mediaContext,
            systemEvent: true,
            systemEventKind: "feishu.reaction"
        ))
    }

    private func mapDriveCommentEventToInbound(root: JsonObject): Option<InboundMessage> {
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { return None<InboundMessage> }
            case None => return None<InboundMessage>
        }
        let userIdObj = match (event.get("user_id")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let accountId = this.resolveFeishuAccountId(root)
        let commentId = this.readStringField(event, "comment_id")
        let replyId = this.readStringField(event, "reply_id")
        let fileToken = this.firstNonEmpty([
            this.readStringField(event, "file_token"),
            this.readStringField(event, "token")
        ])
        let fileType = this.readStringField(event, "file_type")
        let operatorId = this.firstNonEmpty([
            this.readStringField(userIdObj, "open_id"),
            this.readStringField(userIdObj, "user_id"),
            this.readStringField(userIdObj, "union_id")
        ])
        if (commentId.trimAscii().isEmpty() || fileToken.trimAscii().isEmpty()) {
            return None<InboundMessage>
        }
        let peerId = "drive:${fileToken.trimAscii()}"
        let mediaContext = JsonObject()
        mediaContext.put("channel", JsonString("feishu"))
        mediaContext.put("accountId", JsonString(accountId))
        mediaContext.put("peerId", JsonString(peerId))
        mediaContext.put("messageId", JsonString(commentId.trimAscii()))
        let context = JsonObject()
        let comment = JsonObject()
        comment.put("commentId", JsonString(commentId.trimAscii()))
        comment.put("replyId", JsonString(replyId.trimAscii()))
        comment.put("fileToken", JsonString(fileToken.trimAscii()))
        comment.put("fileType", JsonString(fileType.trimAscii()))
        comment.put("operatorId", JsonString(operatorId.trimAscii()))
        comment.put("mentioned", JsonBool(this.readBoolField(event, "is_mention", false)))
        comment.put("content", JsonString(this.readStringField(event, "content")))
        comment.put("eventType", JsonString(this.readHeaderEventType(root)))
        context.put("feishuDriveComment", comment)
        mediaContext.put("context", context)
        let inboundId = if (replyId.trimAscii().isEmpty()) {
            "comment:${commentId.trimAscii()}"
        } else {
            "comment:${commentId.trimAscii()}:reply:${replyId.trimAscii()}"
        }
        Some(InboundMessage(
            ChannelType.Feishu,
            inboundId,
            peerId,
            operatorId.trimAscii(),
            ChatType.Direct,
            "[feishu-drive-comment]\nfileToken=${fileToken.trimAscii()}\ncommentId=${commentId.trimAscii()}\nreplyId=${replyId.trimAscii()}\ncontent=${this.readStringField(event, "content")}",
            this.readBoolField(event, "is_mention", false),
            DateTime.now(),
            conversationId: Some(peerId),
            raw: Some(root.toJsonString()),
            accountId: accountId,
            mediaContext: mediaContext,
            systemEvent: true,
            systemEventKind: "feishu.drive_comment"
        ))
    }

    private func mapBotMembershipEventToInbound(root: JsonObject): Option<InboundMessage> {
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { return None<InboundMessage> }
            case None => return None<InboundMessage>
        }
        let eventType = this.readHeaderEventType(root)
        let accountId = this.resolveFeishuAccountId(root)
        let chatId = this.firstNonEmpty([
            this.readStringField(event, "chat_id"),
            this.readStringField(event, "open_chat_id")
        ])
        if (chatId.trimAscii().isEmpty()) {
            return None<InboundMessage>
        }
        let operatorObj = match (event.get("operator_id")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let operatorId = this.firstNonEmpty([
            this.readStringField(operatorObj, "open_id"),
            this.readStringField(operatorObj, "user_id"),
            this.readStringField(operatorObj, "union_id"),
            this.readStringField(event, "operator_id")
        ])
        let action = if (eventType.contains("deleted") || eventType.contains("removed")) { "deleted" } else { "added" }
        let mediaContext = JsonObject()
        mediaContext.put("channel", JsonString("feishu"))
        mediaContext.put("accountId", JsonString(accountId))
        mediaContext.put("peerId", JsonString(chatId.trimAscii()))
        mediaContext.put("messageId", JsonString("bot:${action}:${chatId.trimAscii()}"))
        let context = JsonObject()
        let membership = JsonObject()
        membership.put("chatId", JsonString(chatId.trimAscii()))
        membership.put("operatorId", JsonString(operatorId.trimAscii()))
        membership.put("action", JsonString(action))
        membership.put("eventType", JsonString(eventType))
        membership.put("status", JsonString("accepted"))
        context.put("feishuBotMembership", membership)
        mediaContext.put("context", context)
        let inboundId = "bot-membership:${eventType}:${chatId.trimAscii()}:${operatorId.trimAscii()}"
        Some(InboundMessage(
            ChannelType.Feishu,
            inboundId,
            chatId.trimAscii(),
            operatorId.trimAscii(),
            ChatType.Group,
            "[feishu-bot-membership]\naction=${action}\nchatId=${chatId.trimAscii()}\nby=${operatorId.trimAscii()}",
            true,
            DateTime.now(),
            conversationId: Some(chatId.trimAscii()),
            raw: Some(root.toJsonString()),
            accountId: accountId,
            mediaContext: mediaContext,
            systemEvent: true,
            systemEventKind: "feishu.bot_membership"
        ))
    }

    private func mapVcInvitedEventToInbound(root: JsonObject): Option<InboundMessage> {
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { return None<InboundMessage> }
            case None => return None<InboundMessage>
        }
        let meetingObj = match (event.get("meeting")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let accountId = this.resolveFeishuAccountId(root)
        let eventId = this.readStringField(event, "event_id")
        let meetingNo = this.firstNonEmpty([
            this.readStringField(meetingObj, "meeting_no"),
            this.readStringField(event, "meeting_no")
        ])
        if (meetingNo.trimAscii().isEmpty() && eventId.trimAscii().isEmpty()) {
            return None<InboundMessage>
        }
        let operatorObj = match (event.get("operator_id")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let operatorId = this.firstNonEmpty([
            this.readStringField(operatorObj, "open_id"),
            this.readStringField(operatorObj, "user_id"),
            this.readStringField(operatorObj, "union_id"),
            this.readStringField(event, "operator_id")
        ])
        let peerId = if (meetingNo.trimAscii().isEmpty()) { "vc:${eventId.trimAscii()}" } else { "vc:${meetingNo.trimAscii()}" }
        let mediaContext = JsonObject()
        mediaContext.put("channel", JsonString("feishu"))
        mediaContext.put("accountId", JsonString(accountId))
        mediaContext.put("peerId", JsonString(peerId))
        mediaContext.put("messageId", JsonString(if (eventId.trimAscii().isEmpty()) { peerId } else { eventId.trimAscii() }))
        let context = JsonObject()
        let vc = JsonObject()
        vc.put("eventId", JsonString(eventId.trimAscii()))
        vc.put("meetingNo", JsonString(meetingNo.trimAscii()))
        vc.put("operatorId", JsonString(operatorId.trimAscii()))
        vc.put("eventType", JsonString(this.readHeaderEventType(root)))
        vc.put("status", JsonString("accepted"))
        context.put("feishuVcInvited", vc)
        mediaContext.put("context", context)
        let inboundId = if (eventId.trimAscii().isEmpty()) { "vc-invited:${meetingNo.trimAscii()}" } else { "vc-invited:${eventId.trimAscii()}" }
        Some(InboundMessage(
            ChannelType.Feishu,
            inboundId,
            peerId,
            operatorId.trimAscii(),
            ChatType.Direct,
            "[feishu-vc-invited]\nmeetingNo=${meetingNo.trimAscii()}\neventId=${eventId.trimAscii()}\nby=${operatorId.trimAscii()}",
            true,
            DateTime.now(),
            conversationId: Some(peerId),
            raw: Some(root.toJsonString()),
            accountId: accountId,
            mediaContext: mediaContext,
            systemEvent: true,
            systemEventKind: "feishu.vc_invited"
        ))
    }

    private func mapBitableFieldChangedEventToInbound(root: JsonObject): Option<InboundMessage> {
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { return None<InboundMessage> }
            case None => return None<InboundMessage>
        }
        let accountId = this.resolveFeishuAccountId(root)
        let appToken = this.firstNonEmpty([
            this.readStringField(event, "app_token"),
            this.readStringField(event, "appToken")
        ])
        let tableId = this.firstNonEmpty([
            this.readStringField(event, "table_id"),
            this.readStringField(event, "tableId")
        ])
        let fieldId = this.firstNonEmpty([
            this.readStringField(event, "field_id"),
            this.readStringField(event, "fieldId")
        ])
        if (appToken.trimAscii().isEmpty() || tableId.trimAscii().isEmpty() || fieldId.trimAscii().isEmpty()) {
            return None<InboundMessage>
        }
        let operatorObj = match (event.get("operator_id")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let operatorId = this.firstNonEmpty([
            this.readStringField(operatorObj, "open_id"),
            this.readStringField(operatorObj, "user_id"),
            this.readStringField(operatorObj, "union_id"),
            this.readStringField(event, "operator_id")
        ])
        let peerId = "bitable:${appToken.trimAscii()}:${tableId.trimAscii()}"
        let mediaContext = JsonObject()
        mediaContext.put("channel", JsonString("feishu"))
        mediaContext.put("accountId", JsonString(accountId))
        mediaContext.put("peerId", JsonString(peerId))
        mediaContext.put("messageId", JsonString("bitable:${appToken.trimAscii()}:${tableId.trimAscii()}:${fieldId.trimAscii()}"))
        let context = JsonObject()
        let bitable = JsonObject()
        bitable.put("appToken", JsonString(appToken.trimAscii()))
        bitable.put("tableId", JsonString(tableId.trimAscii()))
        bitable.put("fieldId", JsonString(fieldId.trimAscii()))
        bitable.put("operatorId", JsonString(operatorId.trimAscii()))
        bitable.put("eventType", JsonString(this.readHeaderEventType(root)))
        bitable.put("status", JsonString("accepted"))
        context.put("feishuBitableFieldChanged", bitable)
        mediaContext.put("context", context)
        let inboundId = "bitable-field:${appToken.trimAscii()}:${tableId.trimAscii()}:${fieldId.trimAscii()}:${operatorId.trimAscii()}"
        Some(InboundMessage(
            ChannelType.Feishu,
            inboundId,
            peerId,
            operatorId.trimAscii(),
            ChatType.Direct,
            "[feishu-bitable-field-changed]\nappToken=${appToken.trimAscii()}\ntableId=${tableId.trimAscii()}\nfieldId=${fieldId.trimAscii()}\nby=${operatorId.trimAscii()}",
            true,
            DateTime.now(),
            conversationId: Some(peerId),
            raw: Some(root.toJsonString()),
            accountId: accountId,
            mediaContext: mediaContext,
            systemEvent: true,
            systemEventKind: "feishu.bitable_field_changed"
        ))
    }

    private func firstNonEmpty(values: Array<String>): String {
        for (value in values) {
            let trimmed = value.trimAscii()
            if (!trimmed.isEmpty()) {
                return trimmed
            }
        }
        ""
    }

    /**
     * P0 测试入口：模拟飞书收到文本消息。
     * 在没有真实网关事件接入之前，可用该方法验证整条链路。
     */
    public func simulateIncomingText(
        messageId: String,
        peerId: String,
        senderId: String,
        text: String,
        chatType!: ChatType = ChatType.Direct,
        mentioned!: Bool = true
    ): Unit {
        if (!this.running) {
            return
        }
        let mediaContext = JsonObject()
        let accountId = this.effectiveAccountId()
        let cfg = this.feishuConfigForAccount(accountId)
        this.attachFeishuImRouteContext(mediaContext, cfg, accountId, peerId, chatType, senderId, messageId, "", "")
        this.attachFeishuGateContext(mediaContext, cfg, chatType, mentioned, peerId, senderId)
        let msg = InboundMessage(
            ChannelType.Feishu,
            messageId,
            peerId,
            senderId,
            chatType,
            text,
            mentioned,
            DateTime.now(),
            raw: None,
            accountId: accountId,
            mediaContext: mediaContext
        )
        synchronized(this.queueMutex) {
            this.inboundQueue.add(msg)
        }
    }

    /**
     * 调试接口：获取已发送消息。
     */
    public func getOutboundLog(): Array<OutboundMessage> {
        synchronized(this.queueMutex) {
            return this.outboundLog.toArray()
        }
    }

    private func outboundAccountId(message: OutboundMessage): String {
        if (!message.accountId.trimAscii().isEmpty()) {
            return gatewayFeishuNormalizeAccountId(message.accountId)
        }
        this.effectiveAccountId()
    }

    private func feishuConfigForAccount(accountId: String): FeishuConfig {
        let normalized = gatewayFeishuNormalizeAccountId(accountId)
        if (normalized == this.accountId) {
            return this.config
        }
        gatewayFeishuResolveAccount(this.baseConfig, normalized).config
    }

    /**
     * 启动内置 HTTP webhook 服务（P1.5）。
     *
     * 路由：
     * - `${webhookPath}`: 飞书回调入口
     * - `/healthz`: 健康检查
     */
    private func startWebhookServer(): Unit {
        let server = ServerBuilder()
            .addr(this.config.webhookHost)
            .port(this.config.webhookPort)
            .build()

        server.distributor.register(this.config.webhookPath, { ctx =>
            let payload = this.readRequestBody(ctx)
            // URL 校验请求往往不带业务签名头，不能按普通事件校验。
            if (!this.isUrlVerificationPayload(payload) && !this.validateWebhookPayload(ctx.request.headers, payload)) {
                ctx.responseBuilder.body("{\"ok\":false,\"error\":\"invalid_signature_or_timestamp\"}")
                return
            }
            let responseText = this.ingestWebhookPayload(payload)
            ctx.responseBuilder.body(responseText)
        })
        server.distributor.register("/healthz", { ctx =>
            ctx.responseBuilder.body("ok")
        })

        this.webhookServer = Some(server)
        spawn {
            try {
                PrintUtils.printLine("Feishu webhook gateway started at ${this.webhookListenUrlForLog()}")
                PrintUtils.printLine("Health endpoint: ${this.healthzUrlForLog()}")
                server.serve()
            } catch (_e: Exception) {
                // P1.5 最小版：服务异常退出暂不抛出到主流程。
            }
        }
    }

    /**
     * 将飞书 webhook 事件映射为统一入站消息。
     * 当前仅处理文本事件：
     * event.message.receive_v1
     */
    private func mapWebhookToInbound(root: JsonObject): Option<InboundMessage> {
        let event = match (root.get("event")) {
            case Some(v) => v.asObject()
            case None => return None
        }

        let messageObj = match (event.get("message")) {
            case Some(v) => v.asObject()
            case None => return None
        }
        let senderObj = match (event.get("sender")) {
            case Some(v) => v.asObject()
            case None => return None
        }

        let messageType = this.readStringField(messageObj, "message_type")
        let contentJsonString = this.readStringField(messageObj, "content")
        let text = this.extractInboundText(messageType, contentJsonString)
        if (text.trimAscii().isEmpty()) {
            return None
        }

        let messageId = this.readStringField(messageObj, "message_id")
        let chatId = this.readStringField(messageObj, "chat_id")
        let chatTypeRaw = this.readStringField(messageObj, "chat_type")
        let rootId = this.readStringField(messageObj, "root_id")
        let threadId = this.readStringField(messageObj, "thread_id")
        let accountId = this.resolveFeishuAccountId(root)
        let accountConfig = this.feishuConfigForAccount(accountId)

        let senderIdObj = match (senderObj.get("sender_id")) {
            case Some(v) => v.asObject()
            case None => return None
        }
        let senderId = this.extractSenderId(senderIdObj)
        if (senderId.trimAscii().isEmpty()) {
            return None
        }

        let chatType = if (chatTypeRaw == "p2p") {
            ChatType.Direct
        } else {
            ChatType.Group
        }
        let isDirect = match (chatType) {
            case ChatType.Direct => true
            case ChatType.Group => false
        }
        // 群聊：优先用 mentions 判断是否 @ 机器人；未配置 FEISHU_BOT_OPEN_ID 时退回文本里是否含 @。
        let mentioned = isDirect ||
            this.messageMentionsBotOpenId(messageObj, accountConfig) ||
            (accountConfig.botOpenId.isEmpty() && (text.contains("@") || text.contains("<at ")))
        let mediaContext = JsonObject()
        this.attachFeishuImRouteContext(mediaContext, accountConfig, accountId, chatId, chatType, senderId, messageId, rootId, threadId)
        this.attachFeishuGateContext(mediaContext, accountConfig, chatType, mentioned, chatId, senderId)
        this.attachFeishuQuoteContext(mediaContext, accountId, chatId, senderId, messageId, rootId, threadId, chatType)
        this.attachFeishuAliasCandidates(mediaContext, accountConfig, messageObj)
        this.attachFeishuAttachmentContext(mediaContext, accountConfig, accountId, chatId, senderId, messageId, messageType, contentJsonString)
        this.attachFeishuRichMessageContext(mediaContext, accountId, chatId, senderId, messageId, messageType, contentJsonString)
        this.attachFeishuResourceBoundaryContext(mediaContext, accountConfig, accountId, messageId, messageType)

        return InboundMessage(
            ChannelType.Feishu,
            messageId,
            chatId,
            senderId,
            chatType,
            text,
            mentioned,
            DateTime.now(),
            conversationId: this.resolveConversationId(accountConfig, chatId, chatType, senderId, messageId, rootId, threadId),
            threadId: if (threadId.trimAscii().isEmpty()) { None<String> } else { Some(threadId.trimAscii()) },
            replyTargetMessageId: this.resolveReplyTargetMessageId(messageId, rootId, threadId),
            replyInThread: this.shouldReplyInThread(chatType, rootId, threadId),
            raw: Some(root.toJsonString()),
            accountId: accountId,
            mediaContext: mediaContext
        )
    }

    private func attachFeishuImRouteContext(
        mediaContext: JsonObject,
        cfg: FeishuConfig,
        accountId: String,
        chatId: String,
        chatType: ChatType,
        senderId: String,
        messageId: String,
        rootId: String,
        threadId: String
    ): Unit {
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let route = JsonObject()
        let normalizedAccountId = this.normalizeAccountId(accountId)
        route.put("channel", JsonString("feishu"))
        route.put("accountId", JsonString(normalizedAccountId))
        route.put("defaultAccountId", JsonString(this.effectiveAccountId()))
        match (chatType) {
            case ChatType.Direct =>
                route.put("peerKind", JsonString("direct"))
                route.put("peerId", JsonString(if (!senderId.trimAscii().isEmpty()) { senderId.trimAscii() } else { chatId.trimAscii() }))
            case ChatType.Group =>
                let topicId = if (!threadId.trimAscii().isEmpty()) {
                    threadId.trimAscii()
                } else {
                    rootId.trimAscii()
                }
                if (!topicId.isEmpty()) {
                    route.put("peerKind", JsonString("thread"))
                    route.put("peerId", JsonString(topicId))
                    route.put("parentPeerKind", JsonString("group"))
                    route.put("parentPeerId", JsonString(chatId.trimAscii()))
                    route.put("threadId", JsonString(topicId))
                    let threadSessionStatus = this.feishuThreadSessionStatus(cfg, chatId, topicId)
                    if (threadSessionStatus[0]) {
                        route.put("threadSessionKey", JsonString(this.buildTopicConversationId(chatId.trimAscii(), topicId)))
                    } else if (cfg.threadSession) {
                        let diagnostic = JsonObject()
                        diagnostic.put("status", JsonString("skipped"))
                        diagnostic.put("reason", JsonString(threadSessionStatus[1]))
                        route.put("threadSessionDiagnostic", diagnostic)
                    }
                } else {
                    route.put("peerKind", JsonString("group"))
                    route.put("peerId", JsonString(chatId.trimAscii()))
                }
        }
        route.put("senderId", JsonString(senderId.trimAscii()))
        route.put("messageId", JsonString(messageId.trimAscii()))
        match (chatType) {
            case ChatType.Group =>
                let groupPolicy = this.feishuGroupPolicyContext(cfg, chatId)
                if (groupPolicy.size() > 0) {
                    route.put("groupPolicy", groupPolicy)
                }
            case ChatType.Direct => ()
        }
        context.put("imRoute", route)
        mediaContext.put("channel", JsonString("feishu"))
        mediaContext.put("accountId", JsonString(normalizedAccountId))
        let envelopePeerId = match (chatType) {
            case ChatType.Direct => if (!chatId.trimAscii().isEmpty()) { chatId.trimAscii() } else { senderId.trimAscii() }
            case ChatType.Group => chatId.trimAscii()
        }
        mediaContext.put("peerId", JsonString(envelopePeerId))
        mediaContext.put("context", context)
    }

    private func attachFeishuGateContext(
        mediaContext: JsonObject,
        cfg: FeishuConfig,
        chatType: ChatType,
        mentioned: Bool,
        chatId: String,
        senderId: String
    ): Unit {
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let gate = JsonObject()
        var accepted = true
        var reason = "accepted"
        match (chatType) {
            case ChatType.Direct =>
                let dmPolicy = cfg.dmPolicy.trimAscii().toAsciiLower()
                if (dmPolicy == "disabled") {
                    accepted = false
                    reason = "dm_disabled"
                } else if (dmPolicy == "open") {
                    ()
                } else if (this.feishuSenderAllowedByList(cfg.allowFrom, senderId)) {
                    ()
                } else if (dmPolicy == "allowlist") {
                    accepted = false
                    reason = "dm_sender_not_allowed"
                } else {
                    accepted = false
                    reason = "dm_pairing_required"
                }
            case ChatType.Group =>
                let groupConfig = this.feishuGroupConfig(cfg, chatId)
                let groupEnabled = this.feishuGroupBool(groupConfig, "enabled", true)
                let groupAllowBots = this.feishuGroupBool(groupConfig, "allowBots", cfg.allowBots)
                let groupRequireMention = this.feishuGroupBool(groupConfig, "requireMention", cfg.policy.requireMentionInGroup)
                let groupAllowFrom = this.feishuGroupStringArray(groupConfig, "allowFrom")
                if (!groupEnabled) {
                    accepted = false
                    reason = "group_disabled"
                } else if (!this.feishuGroupAllowed(cfg, chatId)) {
                    accepted = false
                    reason = "group_not_allowed"
                } else if (!this.feishuSenderAllowedByGroup(groupAllowFrom, senderId)) {
                    accepted = false
                    reason = "sender_not_allowed"
                } else if (!groupAllowBots && this.feishuSenderLooksBot(senderId)) {
                    accepted = false
                    reason = "bot_sender_not_allowed"
                } else if (groupRequireMention && !mentioned) {
                    accepted = false
                    reason = "group_mention_required"
                }
        }
        gate.put("triggerAgent", JsonBool(accepted))
        gate.put("mentioned", JsonBool(mentioned))
        gate.put("requireMentionInGroup", JsonBool(this.feishuGroupBool(this.feishuGroupConfig(cfg, chatId), "requireMention", cfg.policy.requireMentionInGroup)))
        gate.put("dmPolicy", JsonString(cfg.dmPolicy))
        gate.put("allowFrom", this.feishuStringArrayJson(cfg.allowFrom))
        gate.put("groupPolicy", JsonString(cfg.groupPolicy))
        gate.put("groupAllowFrom", this.feishuStringArrayJson(cfg.groupAllowFrom))
        gate.put("allowBots", JsonBool(cfg.allowBots))
        gate.put("reason", JsonString(reason))
        context.put("feishuGate", gate)
        mediaContext.put("context", context)
    }

    private func feishuGroupAllowed(cfg: FeishuConfig, chatId: String): Bool {
        let policy = cfg.groupPolicy.trimAscii().toAsciiLower()
        if (policy == "open") {
            return true
        }
        if (policy == "disabled") {
            return false
        }
        let normalized = chatId.trimAscii()
        for (id in cfg.groupAllowFrom) {
            let candidate = id.trimAscii()
            if (candidate == "*" || candidate == normalized) {
                return true
            }
        }
        match (cfg.groups) {
            case Some(groups) =>
                groups.getFields().contains(normalized) || groups.getFields().contains("*")
            case None => false
        }
    }

    private func feishuGroupConfig(cfg: FeishuConfig, chatId: String): JsonObject {
        let normalized = chatId.trimAscii()
        match (cfg.groups) {
            case Some(groups) =>
                match (groups.get(normalized)) {
                    case Some(v) =>
                        try { return v.asObject() } catch (_e: Exception) { () }
                    case None => ()
                }
                match (groups.get("*")) {
                    case Some(v) =>
                        try { return v.asObject() } catch (_e: Exception) { () }
                    case None => ()
                }
                JsonObject()
            case None => JsonObject()
        }
    }

    private func feishuGroupPolicyContext(feishuConfig: FeishuConfig, chatId: String): JsonObject {
        let cfg = this.feishuGroupConfig(feishuConfig, chatId)
        let out = JsonObject()
        out.put("groupId", JsonString(chatId.trimAscii()))
        out.put("policy", JsonString(feishuConfig.groupPolicy.trimAscii().toAsciiLower()))
        out.put("requireMention", JsonBool(this.feishuGroupBool(cfg, "requireMention", feishuConfig.policy.requireMentionInGroup)))
        out.put("allowBots", JsonBool(this.feishuGroupBool(cfg, "allowBots", feishuConfig.allowBots)))
        for (key in ["tools", "skills", "systemPrompt", "runtimePolicy", "policy"]) {
            match (cfg.get(key)) {
                case Some(v) => out.put(key, v)
                case None => ()
            }
        }
        out
    }

    private func feishuGroupBool(cfg: JsonObject, key: String, fallback: Bool): Bool {
        match (cfg.get(key)) {
            case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { fallback }
            case None => fallback
        }
    }

    private func feishuGroupStringArray(cfg: JsonObject, key: String): Array<String> {
        let out = ArrayList<String>()
        match (cfg.get(key)) {
            case Some(v) =>
                try {
                    let arr = v.asArray()
                    for (i in 0..arr.size()) {
                        try {
                            let value = arr[i].asString().getValue().trimAscii()
                            if (!value.isEmpty()) {
                                out.add(value)
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
        out.toArray()
    }

    private func feishuSenderAllowedByGroup(allowFrom: Array<String>, senderId: String): Bool {
        if (allowFrom.isEmpty()) {
            return true
        }
        this.feishuSenderAllowedByList(allowFrom, senderId)
    }

    private func feishuSenderAllowedByList(allowFrom: Array<String>, senderId: String): Bool {
        let normalized = senderId.trimAscii()
        for (candidateRaw in allowFrom) {
            let candidate = candidateRaw.trimAscii()
            if (candidate == "*" || candidate == normalized) {
                return true
            }
        }
        false
    }

    private func feishuStringArrayJson(values: Array<String>): JsonArray {
        let out = JsonArray([])
        for (value in values) {
            out.add(JsonString(value))
        }
        out
    }

    private func feishuSenderLooksBot(senderId: String): Bool {
        senderId.trimAscii().toAsciiLower().contains("bot")
    }

    private func attachFeishuAliasCandidates(mediaContext: JsonObject, cfg: FeishuConfig, messageObj: JsonObject): Unit {
        let mentions = match (messageObj.get("mentions")) {
            case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        if (mentions.size() == 0) {
            return
        }
        let candidates = JsonArray([])
        for (i in 0..mentions.size()) {
            let mention = try { mentions[i].asObject() } catch (_e: Exception) { JsonObject() }
            let idObj = match (mention.get("id")) {
                case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
                case None => JsonObject()
            }
            let openId = this.readStringField(idObj, "open_id")
            let userId = this.readStringField(idObj, "user_id")
            let unionId = this.readStringField(idObj, "union_id")
            if (openId.isEmpty() && userId.isEmpty() && unionId.isEmpty()) {
                continue
            }
            if (!cfg.botOpenId.isEmpty() &&
                (openId == cfg.botOpenId || userId == cfg.botOpenId || unionId == cfg.botOpenId)) {
                continue
            }
            let row = JsonObject()
            row.put("platform", JsonString("feishu"))
            row.put("openId", JsonString(openId))
            row.put("userId", JsonString(userId))
            row.put("unionId", JsonString(unionId))
            row.put("name", JsonString(this.readStringField(mention, "name")))
            row.put("key", JsonString(this.readStringField(mention, "key")))
            candidates.add(row)
        }
        if (candidates.size() == 0) {
            return
        }
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        context.put("aliasCandidates", candidates)
        mediaContext.put("context", context)
    }

    private func attachFeishuAttachmentContext(
        mediaContext: JsonObject,
        cfg: FeishuConfig,
        accountId: String,
        chatId: String,
        senderId: String,
        messageId: String,
        messageType: String,
        contentJsonString: String
    ): Unit {
        let normalizedType = messageType.trimAscii().toAsciiLower()
        if (!(normalizedType == "image" || normalizedType == "file" || normalizedType == "media" || normalizedType == "audio" || normalizedType == "video")) {
            return
        }
        let content = try {
            JsonValue.fromStr(contentJsonString).asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let fileId = this.feishuAttachmentFileId(normalizedType, content)
        if (fileId.isEmpty()) {
            return
        }
        let originalFileName = this.feishuAttachmentFileName(content)
        let originalMimeType = this.feishuAttachmentMimeType(normalizedType, content)
        let declaredSize = this.feishuAttachmentFileSize(content)
        let resourceType = this.feishuResourceTypeForApi(normalizedType)
        let record = JsonObject()
        record.put("mediaId", JsonString("${this.normalizeAccountId(accountId)}:${chatId.trimAscii()}:${messageId.trimAscii()}:${normalizedType}:${fileId}"))
        record.put("channel", JsonString("feishu"))
        record.put("accountId", JsonString(this.normalizeAccountId(accountId)))
        record.put("peerId", JsonString(chatId.trimAscii()))
        record.put("messageId", JsonString(messageId.trimAscii()))
        record.put("relation", JsonString("current"))
        record.put("mediaKind", JsonString(normalizedType))
        record.put("kind", JsonString(normalizedType))
        record.put("fileId", JsonString(fileId))
        record.put("fileKey", JsonString(fileId))
        record.put("resourceType", JsonString(resourceType))
        record.put("originalFileName", JsonString(originalFileName))
        record.put("fileName", JsonString(originalFileName))
        record.put("mimeType", JsonString(originalMimeType))
        record.put("fileSize", JsonInt(declaredSize))
        record.put("eligibleFor", JsonString(this.feishuAttachmentEligibility(normalizedType)))
        record.put("createdAtMs", JsonInt(DateTime.now().toUnixTimeStamp().toMilliseconds()))
        var downloaded = false
        var skippedReason = "metadata_only"
        var localPath = ""
        var effectiveMimeType = originalMimeType
        var effectiveFileName = originalFileName
        var effectiveFileSize = declaredSize
        var resourceNetworkAttempted = false
        if (cfg.media.downloadEnabled) {
            if (!this.feishuMediaMimeAllowed(cfg, originalMimeType)) {
                skippedReason = "mime_not_allowed"
            } else if (declaredSize > 0 && this.feishuMediaSizeExceedsLimit(cfg, declaredSize)) {
                skippedReason = "size_limit_exceeded"
            } else {
                resourceNetworkAttempted = true
                let result = this.fetchFeishuMessageResource(
                    this.normalizeAccountId(accountId),
                    messageId,
                    fileId,
                    resourceType
                )
                if (result.ok) {
                    effectiveMimeType = if (!result.contentType.isEmpty()) { result.contentType } else { originalMimeType }
                    effectiveFileName = if (!result.fileName.isEmpty()) { result.fileName } else { originalFileName }
                    effectiveFileSize = Int64(result.bytes.size)
                    if (this.feishuMediaSizeExceedsLimit(cfg, effectiveFileSize)) {
                        skippedReason = "download_size_limit_exceeded"
                    } else if (!this.feishuMediaMimeAllowed(cfg, effectiveMimeType)) {
                        skippedReason = "mime_not_allowed"
                    } else {
                        let persisted = this.feishuPersistDownloadedResourceBytes(
                            cfg,
                            result.bytes,
                            accountId: accountId,
                            chatId: chatId,
                            messageId: messageId,
                            fileKey: fileId,
                            mediaKind: normalizedType,
                            fileName: effectiveFileName,
                            mimeType: effectiveMimeType
                        )
                        if (!persisted.trimAscii().isEmpty()) {
                            downloaded = true
                            skippedReason = ""
                            localPath = persisted
                        } else {
                            skippedReason = "download_failed"
                        }
                    }
                } else {
                    skippedReason = this.feishuDownloadSkippedReason(result.status)
                }
            }
        }
        record.put("fileName", JsonString(effectiveFileName))
        record.put("mimeType", JsonString(effectiveMimeType))
        record.put("fileSize", JsonInt(effectiveFileSize))
        record.put("downloaded", JsonBool(downloaded))
        record.put("skippedReason", JsonString(skippedReason))
        record.put("localPath", JsonString(localPath))
        record.put("downloadPath", JsonString(localPath))
        let finalStatus = if (downloaded) { "downloaded" } else { skippedReason }
        record.put("currentTurnContext", this.feishuCurrentTurnResourceContext(
            accountId,
            chatId,
            senderId,
            messageId,
            normalizedType,
            fileId,
            resourceType,
            finalStatus,
            resourceNetworkAttempted,
            this.feishuAttachmentEligibility(normalizedType)
        ))
        record.put("resourceFetch", this.feishuResourceFetchDiagnostic(
            accountId,
            messageId,
            fileId,
            resourceType,
            normalizedType,
            finalStatus,
            resourceNetworkAttempted,
            this.feishuAttachmentEligibility(normalizedType)
        ))
        let records = JsonArray([])
        records.add(record)
        mediaContext.put("records", records)
    }

    private func attachFeishuQuoteContext(
        mediaContext: JsonObject,
        accountId: String,
        chatId: String,
        senderId: String,
        messageId: String,
        rootId: String,
        threadId: String,
        chatType: ChatType
    ): Unit {
        let cleanRoot = rootId.trimAscii()
        let cleanThread = threadId.trimAscii()
        if (cleanRoot.isEmpty() && cleanThread.isEmpty()) {
            return
        }
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let quoteContext = JsonObject()
        quoteContext.put("messageId", JsonString(messageId.trimAscii()))
        quoteContext.put("rootId", JsonString(cleanRoot))
        quoteContext.put("threadId", JsonString(cleanThread))
        quoteContext.put("status", JsonString("metadata_only"))
        quoteContext.put("reason", JsonString("quoted Feishu message content requires historical resource/message authorization"))
        quoteContext.put("replyInThread", JsonBool(this.shouldReplyInThread(chatType, cleanRoot, cleanThread)))
        match (this.resolveReplyTargetMessageId(messageId, cleanRoot, cleanThread)) {
            case Some(target) => quoteContext.put("replyTargetMessageId", JsonString(target))
            case None => quoteContext.put("replyTargetMessageId", JsonString(""))
        }
        quoteContext.put("operatorEvidence", this.feishuOperatorEvidence(
            senderId,
            "quote_reply",
            eventType: "im.message.receive_v1",
            messageId: messageId,
            chatId: chatId,
            accountId: accountId
        ))
        quoteContext.put("historicalFetch", this.feishuHistoricalResourceFetchDiagnostic(
            "auth_required",
            reason: "quote expansion requires Feishu historical message/resource scopes"
        ))
        quoteContext.put("resourceFetch", this.feishuNoResourceFetchDiagnostic(
            "auth_required",
            reason: "quote expansion requires Feishu historical message/resource scopes"
        ))
        context.put("feishuQuote", quoteContext)
        mediaContext.put("context", context)
    }

    private func attachFeishuRichMessageContext(
        mediaContext: JsonObject,
        accountId: String,
        chatId: String,
        senderId: String,
        messageId: String,
        messageType: String,
        contentJsonString: String
    ): Unit {
        let normalizedType = messageType.trimAscii().toAsciiLower()
        if (normalizedType != "merge_forward") {
            return
        }
        let content = try {
            JsonValue.fromStr(contentJsonString).asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let forward = JsonObject()
        forward.put("title", JsonString(this.readStringField(content, "title").trimAscii()))
        forward.put("status", JsonString("metadata_only"))
        forward.put("declaredMessageCount", JsonInt(this.readIntField(content, "message_count")))
        forward.put("operatorEvidence", this.feishuOperatorEvidence(
            senderId,
            "merge_forward",
            eventType: "im.message.receive_v1",
            messageId: messageId,
            chatId: chatId,
            accountId: accountId
        ))
        forward.put("historicalFetch", this.feishuHistoricalResourceFetchDiagnostic(
            "auth_required",
            reason: "merge_forward expansion requires Feishu historical message scopes"
        ))
        let fetch = JsonObject()
        fetch.put("status", JsonString("external_resource_required"))
        fetch.put("networkAttempted", JsonBool(false))
        fetch.put("tool", JsonString("feishu_im_message.list_forward_messages"))
        fetch.put("reason", JsonString("merge_forward expansion requires a live Feishu message history/resource API fixture"))
        fetch.put("redacted", JsonBool(true))
        fetch.put("requiredScopes", JsonArray([
            JsonString("im:message")
        ]))
        forward.put("resourceFetch", fetch)
        context.put("feishuMergeForward", forward)
        mediaContext.put("context", context)
    }

    private func feishuResourceFetchDiagnostic(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String,
        mediaKind: String,
        status: String,
        networkAttempted: Bool,
        eligibleFor: String
    ): JsonObject {
        let out = JsonObject()
        let cleanStatus = if (status.trimAscii().isEmpty()) { "metadata_only" } else { status.trimAscii() }
        out.put("status", JsonString(cleanStatus))
        out.put("errorClass", JsonString(this.feishuClassifyResourceFetchStatus(cleanStatus)))
        out.put("networkAttempted", JsonBool(networkAttempted))
        out.put("tool", JsonString("feishu_im_user_fetch_resource"))
        out.put("accountId", JsonString(this.normalizeAccountId(accountId)))
        out.put("messageId", JsonString(messageId.trimAscii()))
        out.put("fileKey", JsonString(fileKey.trimAscii()))
        out.put("resourceType", JsonString(resourceType.trimAscii()))
        out.put("mediaKind", JsonString(mediaKind.trimAscii()))
        out.put("eligibleFor", JsonString(eligibleFor.trimAscii()))
        out.put("requiredScopes", JsonArray([
            JsonString("im:message.resource:read")
        ]))
        out.put("redacted", JsonBool(true))
        out
    }

    private func feishuCurrentTurnResourceContext(
        accountId: String,
        chatId: String,
        senderId: String,
        messageId: String,
        messageType: String,
        fileKey: String,
        resourceType: String,
        status: String,
        networkAttempted: Bool,
        eligibleFor: String
    ): JsonObject {
        let cleanStatus = if (status.trimAscii().isEmpty()) { "metadata_only" } else { status.trimAscii() }
        let out = JsonObject()
        out.put("relation", JsonString("current"))
        out.put("source", JsonString("im.message.receive_v1"))
        out.put("accountId", JsonString(this.normalizeAccountId(accountId)))
        out.put("peerId", JsonString(chatId.trimAscii()))
        out.put("operatorId", JsonString(senderId.trimAscii()))
        out.put("messageId", JsonString(messageId.trimAscii()))
        out.put("messageType", JsonString(messageType.trimAscii().toAsciiLower()))
        out.put("fileKey", JsonString(fileKey.trimAscii()))
        out.put("resourceType", JsonString(resourceType.trimAscii()))
        out.put("eligibleFor", JsonString(eligibleFor.trimAscii()))
        out.put("status", JsonString(cleanStatus))
        out.put("errorClass", JsonString(this.feishuClassifyResourceFetchStatus(cleanStatus)))
        out.put("networkAttempted", JsonBool(networkAttempted))
        out.put("redacted", JsonBool(true))
        out
    }

    private func feishuHistoricalResourceFetchDiagnostic(status: String, reason!: String = ""): JsonObject {
        let cleanStatus = if (status.trimAscii().isEmpty()) { "auth_required" } else { status.trimAscii().toAsciiLower() }
        let out = JsonObject()
        out.put("relation", JsonString("historical"))
        out.put("status", JsonString(cleanStatus))
        out.put("errorClass", JsonString(this.feishuClassifyResourceFetchStatus(cleanStatus)))
        out.put("networkAttempted", JsonBool(false))
        out.put("tool", JsonString("feishu_im_user_fetch_resource"))
        out.put("reason", JsonString(reason.trimAscii()))
        out.put("requiredScopes", JsonArray([
            JsonString("im:message"),
            JsonString("im:message.resource:read")
        ]))
        out.put("errorClasses", this.feishuHistoricalResourceErrorClasses())
        out.put("redacted", JsonBool(true))
        out
    }

    private func feishuHistoricalResourceErrorClasses(): JsonArray {
        JsonArray([
            JsonString("auth_required"),
            JsonString("scope_missing"),
            JsonString("api_error")
        ])
    }

    private func feishuClassifyResourceFetchStatus(status: String): String {
        let clean = status.trimAscii().toAsciiLower()
        if (clean.isEmpty() || clean == "metadata_only" || clean == "external_resource_required" || clean == "not_required") {
            return "not_attempted"
        }
        if (clean == "downloaded" || clean == "ok") {
            return "ok"
        }
        if (
            clean == "auth_required" ||
            clean == "missing_credential" ||
            clean == "missing_credentials" ||
            clean == "missing_user_auth" ||
            clean == "not_configured" ||
            clean == "forbidden" ||
            clean == "unauthorized" ||
            clean == "401" ||
            clean == "403"
        ) {
            return "auth_required"
        }
        if (clean == "scope_missing" || clean == "user_scope_missing" || clean == "app_scope_missing") {
            return "scope_missing"
        }
        if (
            clean == "api_error" ||
            clean == "network_error" ||
            clean == "parse_error" ||
            clean == "download_failed" ||
            clean == "not_found" ||
            clean == "rate_limited" ||
            clean == "429" ||
            clean.startsWith("http_")
        ) {
            return "api_error"
        }
        clean
    }

    private func feishuOperatorEvidence(
        operatorId: String,
        operation: String,
        eventType!: String = "",
        messageId!: String = "",
        chatId!: String = "",
        accountId!: String = "",
        idType!: String = "open_id"
    ): JsonObject {
        let out = JsonObject()
        out.put("operatorId", JsonString(operatorId.trimAscii()))
        out.put("operatorIdType", JsonString(idType.trimAscii()))
        out.put("operation", JsonString(operation.trimAscii()))
        out.put("eventType", JsonString(eventType.trimAscii()))
        out.put("accountId", JsonString(this.normalizeAccountId(accountId)))
        out.put("chatId", JsonString(chatId.trimAscii()))
        out.put("messageId", JsonString(messageId.trimAscii()))
        out.put("source", JsonString("feishu_event"))
        out.put("redacted", JsonBool(true))
        out
    }

    private func feishuNoResourceFetchDiagnostic(status: String, reason!: String = ""): JsonObject {
        let out = JsonObject()
        out.put("status", JsonString(if (status.trimAscii().isEmpty()) { "not_required" } else { status.trimAscii() }))
        out.put("errorClass", JsonString(this.feishuClassifyResourceFetchStatus(status)))
        out.put("networkAttempted", JsonBool(false))
        out.put("reason", JsonString(reason.trimAscii()))
        out.put("redacted", JsonBool(true))
        out
    }

    private func attachFeishuResourceBoundaryContext(
        mediaContext: JsonObject,
        cfg: FeishuConfig,
        accountId: String,
        messageId: String,
        messageType: String
    ): Unit {
        let normalizedType = messageType.trimAscii().toAsciiLower()
        if (!(normalizedType == "image" || normalizedType == "file" || normalizedType == "media" || normalizedType == "audio" || normalizedType == "video")) {
            return
        }
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let boundary = JsonObject()
        let current = JsonObject()
        current.put("relation", JsonString("current"))
        current.put("source", JsonString("channel_media_context"))
        current.put("messageId", JsonString(messageId.trimAscii()))
        current.put("status", JsonString(if (this.feishuMediaContextHasRecords(mediaContext)) { "staged_metadata" } else { "not_present" }))
        current.put("downloadEnabled", JsonBool(cfg.media.downloadEnabled))
        boundary.put("currentTurn", current)

        let historical = JsonObject()
        historical.put("relation", JsonString("historical"))
        historical.put("source", JsonString("oapi"))
        historical.put("tool", JsonString("feishu_im_user_fetch_resource"))
        historical.put("accountId", JsonString(this.normalizeAccountId(accountId)))
        historical.put("status", JsonString("auth_required"))
        historical.put("errorClass", JsonString("auth_required"))
        historical.put("errorClasses", this.feishuHistoricalResourceErrorClasses())
        historical.put("networkAttempted", JsonBool(false))
        historical.put("requiredScopes", JsonArray([
            JsonString("im:message"),
            JsonString("im:message.resource:read")
        ]))
        historical.put("reason", JsonString("historical Feishu resources require user authorization and message resource scopes"))
        historical.put("redacted", JsonBool(true))
        boundary.put("historicalResource", historical)

        let botImage = JsonObject()
        botImage.put("identity", JsonString("bot"))
        botImage.put("source", JsonString("oapi"))
        botImage.put("tool", JsonString("feishu_im_bot_image"))
        botImage.put("status", JsonString("not_configured"))
        botImage.put("errorClass", JsonString("auth_required"))
        botImage.put("reason", JsonString("bot image fetch must be configured through the Feishu OAPI boundary"))
        botImage.put("redacted", JsonBool(true))
        boundary.put("botImage", botImage)

        let docMedia = JsonObject()
        docMedia.put("source", JsonString("oapi"))
        docMedia.put("tool", JsonString("feishu_doc_media"))
        docMedia.put("status", JsonString("auth_required"))
        docMedia.put("errorClass", JsonString("auth_required"))
        docMedia.put("reason", JsonString("document media requires Feishu document authorization and scope checks"))
        docMedia.put("redacted", JsonBool(true))
        boundary.put("docMedia", docMedia)

        context.put("feishuResourceBoundary", boundary)
        mediaContext.put("context", context)
    }

    private func feishuMediaContextHasRecords(mediaContext: JsonObject): Bool {
        match (mediaContext.get("records")) {
            case Some(v) =>
                try { v.asArray().size() > 0 } catch (_e: Exception) { false }
            case None => false
        }
    }

    private func feishuResourceTypeForApi(kind: String): String {
        if (kind.trimAscii().toAsciiLower() == "image") { "image" } else { "file" }
    }

    private func fetchFeishuMessageResource(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String
    ): FeishuResourceDownloadResult {
        let injected = this.apiClient.fetchMessageResource(accountId, messageId, fileKey, resourceType)
        if (injected.ok || injected.status != "not_configured") {
            return injected
        }
        this.fetchFeishuMessageResourceViaHttp(accountId, messageId, fileKey, resourceType)
    }

    private func fetchFeishuMessageResourceViaHttp(
        accountId: String,
        messageId: String,
        fileKey: String,
        resourceType: String
    ): FeishuResourceDownloadResult {
        let cfg = this.feishuConfigForAccount(accountId)
        let token = this.getTenantAccessTokenForConfig(accountId, cfg)
        if (token.trimAscii().isEmpty()) {
            return FeishuResourceDownloadResult(status: "not_configured", error: "tenant_access_token is empty")
        }
        let base = this.normalizeFeishuDomain(cfg)
        let url = "${base}/open-apis/im/v1/messages/${messageId.trimAscii()}/resources/${fileKey.trimAscii()}?type=${resourceType.trimAscii()}"
        let builder = ClientBuilder()
        builder.readTimeout(Duration.second * 30)
        if (url.startsWith("https")) {
            var tlsConfig = TlsClientConfig()
            tlsConfig.domain = URL.parse(url).hostName
            tlsConfig.alpnProtocolsList = ["http/1.1"]
            builder.tlsConfig(tlsConfig)
        }
        let client = builder.build()
        try {
            let reqBuilder = HttpRequestBuilder().url(url).get()
            reqBuilder.header("Authorization", "Bearer ${token}")
            reqBuilder.header("Accept", "*/*")
            let response = client.send(reqBuilder.build())
            let status = Int64(response.status)
            let bytes = this.feishuReadAllBytes(response)
            let contentType = response.headers.getFirst("content-type") ?? response.headers.getFirst("Content-Type") ?? ""
            let fileName = this.feishuFileNameFromContentDisposition(
                response.headers.getFirst("content-disposition") ?? response.headers.getFirst("Content-Disposition") ?? ""
            )
            if (status >= 200 && status < 300) {
                return FeishuResourceDownloadResult(ok: true, status: "ok", bytes: bytes, contentType: contentType, fileName: fileName)
            }
            return FeishuResourceDownloadResult(status: this.feishuHttpStatusLabel(status), error: "feishu resource download failed: status=${status}")
        } catch (e: Exception) {
            return FeishuResourceDownloadResult(status: "network_error", error: e.message)
        } finally {
            client.close()
        }
    }

    private func feishuReadAllBytes(response: HttpResponse): Array<Byte> {
        let out = ArrayList<Byte>()
        let buffer = Array<Byte>(8192, repeat: 0)
        while (true) {
            let n = response.body.read(buffer)
            if (n <= 0) {
                break
            }
            out.add(all: buffer[..n])
        }
        out.toArray()
    }

    private func feishuHttpStatusLabel(status: Int64): String {
        if (status == 401 || status == 403) { return "forbidden" }
        if (status == 404) { return "not_found" }
        if (status == 429) { return "rate_limited" }
        "http_${status}"
    }

    private func feishuDownloadSkippedReason(status: String): String {
        let normalized = status.trimAscii().toAsciiLower()
        if (normalized == "403" || normalized == "401" || normalized == "forbidden" || normalized == "unauthorized") {
            return "forbidden"
        }
        if (normalized == "404" || normalized == "not_found") {
            return "not_found"
        }
        if (normalized == "429" || normalized == "rate_limited" || normalized == "too_many_requests") {
            return "rate_limited"
        }
        if (normalized.isEmpty()) {
            return "download_failed"
        }
        normalized
    }

    private func feishuMediaMimeAllowed(cfg: FeishuConfig, mimeType: String): Bool {
        let mime = mimeType.trimAscii().toAsciiLower()
        if (cfg.media.allowedMimes.isEmpty()) {
            return true
        }
        for (raw in cfg.media.allowedMimes) {
            let allowed = raw.trimAscii().toAsciiLower()
            if (allowed == "*" || allowed == mime) {
                return true
            }
            if (allowed.endsWith("/*")) {
                let prefix = allowed[0..allowed.size - 1]
                if (mime.startsWith(prefix)) {
                    return true
                }
            }
        }
        false
    }

    private func feishuMediaSizeExceedsLimit(cfg: FeishuConfig, sizeBytes: Int64): Bool {
        let limit = cfg.media.mediaMaxBytes
        limit > 0 && sizeBytes > limit
    }

    private func feishuPersistDownloadedResourceBytes(
        cfg: FeishuConfig,
        bytes: Array<Byte>,
        accountId!: String,
        chatId!: String,
        messageId!: String,
        fileKey!: String,
        mediaKind!: String,
        fileName!: String,
        mimeType!: String
    ): String {
        let root = Path(if (cfg.media.downloadRoot.trimAscii().isEmpty()) {
            "/tmp/metis-feishu-media"
        } else {
            cfg.media.downloadRoot.trimAscii()
        })
        let dir = root
            .join(this.feishuSafeMediaSegment(this.normalizeAccountId(accountId)))
            .join(this.feishuSafeMediaSegment(chatId))
            .join(this.feishuSafeMediaSegment(messageId))
        let safeName = this.feishuSafeMediaFileName(fileKey, mediaKind: mediaKind, fileName: fileName, mimeType: mimeType)
        try {
            if (!exists(dir)) {
                Directory.create(dir, recursive: true)
            }
            let target = dir.join(safeName)
            File.writeTo(target, bytes)
            target.toString()
        } catch (_e: Exception) {
            ""
        }
    }

    private func feishuSafeMediaSegment(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) {
            return "default"
        }
        let out = StringBuilder()
        for (r in trimmed.runes()) {
            if ((r >= r'a' && r <= r'z') || (r >= r'A' && r <= r'Z') || (r >= r'0' && r <= r'9') || r == r'.' || r == r'_' || r == r'-') {
                out.append(r)
            } else {
                out.append(r'_')
            }
        }
        var value = out.toString().trimAscii()
        while (value.contains("..")) {
            value = value.replace("..", "_")
        }
        while (value.startsWith(".")) {
            value = value[1..]
        }
        if (value.isEmpty()) { "default" } else { value }
    }

    private func feishuSafeMediaFileName(fileKey: String, mediaKind!: String, fileName!: String, mimeType!: String): String {
        let candidate = if (!fileName.trimAscii().isEmpty()) {
            fileName.trimAscii()
        } else if (!fileKey.trimAscii().isEmpty()) {
            fileKey.trimAscii()
        } else {
            mediaKind.trimAscii()
        }
        var safe = this.feishuSafeMediaSegment(candidate)
        if (this.feishuFileExtensionFromName(safe).isEmpty()) {
            safe += this.feishuFileExtensionFromMime(mimeType)
        }
        safe
    }

    private func feishuFileExtensionFromName(name: String): String {
        let trimmed = name.trimAscii()
        var dot: Int64 = -1
        for (i in 0..trimmed.size) {
            if (trimmed[i] == UInt8(46)) {
                dot = i
            }
        }
        if (dot >= 0 && dot < trimmed.size - 1) {
            return trimmed[dot..]
        }
        ""
    }

    private func feishuFileExtensionFromMime(mimeType: String): String {
        let mime = mimeType.trimAscii().toAsciiLower()
        if (mime == "image/jpeg" || mime == "image/jpg") { return ".jpg" }
        if (mime == "image/png") { return ".png" }
        if (mime == "image/gif") { return ".gif" }
        if (mime == "image/webp") { return ".webp" }
        if (mime == "audio/ogg") { return ".ogg" }
        if (mime == "audio/mpeg") { return ".mp3" }
        if (mime == "audio/mp4") { return ".m4a" }
        if (mime == "video/mp4") { return ".mp4" }
        if (mime == "application/pdf") { return ".pdf" }
        if (mime == "application/json") { return ".json" }
        if (mime.startsWith("text/")) { return ".txt" }
        ""
    }

    private func feishuFileNameFromContentDisposition(raw: String): String {
        let marker = "filename="
        let value = raw.trimAscii()
        let lowered = value.toAsciiLower()
        let pos = match (lowered.indexOf(marker)) {
            case Some(v) => v
            case None => return ""
        }
        var out = value[pos + marker.size..].trimAscii()
        if (out.startsWith("\"") && out.endsWith("\"") && out.size >= 2) {
            out = out[1..out.size - 1]
        }
        out
    }

    private func resolveFeishuAccountId(root: JsonObject): String {
        let header = match (root.get("header")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["account_id", "accountId", "tenant_key", "tenantKey", "app_id", "appId"]) {
            let value = this.readStringField(header, key).trimAscii()
            if (!value.isEmpty()) {
                return this.normalizeAccountId(value)
            }
        }
        let event = match (root.get("event")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        for (key in ["account_id", "accountId", "tenant_key", "tenantKey", "app_id", "appId"]) {
            let value = this.readStringField(event, key).trimAscii()
            if (!value.isEmpty()) {
                return this.normalizeAccountId(value)
            }
        }
        this.effectiveAccountId()
    }

    private func effectiveAccountId(): String {
        this.accountId
    }

    private func normalizeAccountId(raw: String): String {
        let trimmed = raw.trimAscii()
        if (trimmed.isEmpty()) { "default" } else { trimmed }
    }

    private func feishuAttachmentFileId(kind: String, content: JsonObject): String {
        if (kind == "image") {
            let imageKey = this.readStringField(content, "image_key").trimAscii()
            if (!imageKey.isEmpty()) { return imageKey }
        }
        for (key in ["file_key", "fileKey", "media_key", "mediaKey", "audio_key", "audioKey"]) {
            let value = this.readStringField(content, key).trimAscii()
            if (!value.isEmpty()) { return value }
        }
        ""
    }

    private func feishuAttachmentFileName(content: JsonObject): String {
        for (key in ["file_name", "fileName", "name"]) {
            let value = this.readStringField(content, key).trimAscii()
            if (!value.isEmpty()) { return value }
        }
        ""
    }

    private func feishuAttachmentMimeType(kind: String, content: JsonObject): String {
        for (key in ["mime_type", "mimeType"]) {
            let value = this.readStringField(content, key).trimAscii().toAsciiLower()
            if (!value.isEmpty()) { return value }
        }
        if (kind == "image") { return "image/*" }
        if (kind == "audio") { return "audio/*" }
        if (kind == "media" || kind == "video") { return "video/*" }
        ""
    }

    private func feishuAttachmentFileSize(content: JsonObject): Int64 {
        for (key in ["size", "file_size", "fileSize"]) {
            let value = this.readStringField(content, key).trimAscii()
            if (!value.isEmpty()) {
                return try { Int64.parse(value) } catch (_e: Exception) { 0 }
            }
        }
        0
    }

    private func feishuAttachmentEligibility(kind: String): String {
        if (kind == "image") { return "image" }
        if (kind == "audio") { return "audio" }
        if (kind == "media" || kind == "video") { return "video" }
        "document"
    }

    private func readHeaderEventType(root: JsonObject): String {
        match (root.get("header")) {
            case Some(hv) => try { this.readStringField(hv.asObject(), "event_type") } catch (_e: Exception) { "" }
            case None => ""
        }
    }

    private func isUrlVerificationPayload(payload: String): Bool {
        return try {
            let jo = JsonValue.fromStr(payload).asObject()
            match (jo.get("type")) {
                case Some(tv) => tv.asString().getValue() == "url_verification"
                case None => false
            }
        } catch (_e: Exception) {
            false
        }
    }

    /**
     * 飞书 message.mentions 中与机器人 open_id 匹配则视为被 @。
     */
    private func messageMentionsBotOpenId(messageObj: JsonObject, cfg: FeishuConfig): Bool {
        if (cfg.botOpenId.isEmpty()) {
            return false
        }
        return match (messageObj.get("mentions")) {
            case Some(mv) => this.jsonMentionsContainOpenId(mv, cfg)
            case None => false
        }
    }

    /** 解析 message.mentions 数组，是否与当前配置的机器人 open_id 匹配。 */
    private func jsonMentionsContainOpenId(mv: JsonValue, cfg: FeishuConfig): Bool {
        let mentionsArr = mv as JsonArray
        if (let Some(arr) <- mentionsArr) {
            for (i in 0..arr.size()) {
                let item = arr[i]
                let mo = item as JsonObject
                if (let Some(o) <- mo) {
                    let id = this.readStringField(o, "id")
                    if (id == cfg.botOpenId) {
                        return true
                    }
                    if (let Some(idObjValue) <- o.get("id")) {
                        let idObj = idObjValue as JsonObject
                        if (let Some(io) <- idObj) {
                            let openId = this.readStringField(io, "open_id")
                            let userId = this.readStringField(io, "user_id")
                            if (openId == cfg.botOpenId || userId == cfg.botOpenId) {
                                return true
                            }
                        }
                    }
                    if (let Some(idObjValue) <- o.get("user_id")) {
                        let idObj = idObjValue as JsonString
                        if (let Some(uid) <- idObj) {
                            if (uid.getValue() == cfg.botOpenId) {
                                return true
                            }
                        }
                    }
                    let key = this.readStringField(o, "key")
                    if (!key.isEmpty() && key.contains(cfg.botOpenId)) {
                        return true
                    }
                }
            }
        }
        false
    }

    private func extractSenderId(senderIdObj: JsonObject): String {
        let openId = this.readStringField(senderIdObj, "open_id")
        if (!openId.isEmpty()) {
            return openId
        }
        let userId = this.readStringField(senderIdObj, "user_id")
        if (!userId.isEmpty()) {
            return userId
        }
        this.readStringField(senderIdObj, "union_id")
    }

    private func readStringField(obj: JsonObject, key: String): String {
        return match (obj.get(key)) {
            case Some(v) => match (v) {
                case s: JsonString => s.getValue()
                case i: JsonInt => i.getValue().toString()
                case f: JsonFloat => f.getValue().toString()
                case _ => ""
            }
            case None => ""
        }
    }

    private func readBoolField(obj: JsonObject, key: String, fallback: Bool): Bool {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    return v.asBool().getValue()
                } catch (_e: Exception) {
                    let raw = this.readStringField(obj, key).trimAscii().toAsciiLower()
                    if (raw == "true" || raw == "1" || raw == "yes") {
                        return true
                    }
                    if (raw == "false" || raw == "0" || raw == "no") {
                        return false
                    }
                    return fallback
                }
            case None => fallback
        }
    }

    /**
     * 飞书文本 content 通常是 JSON 字符串，例如 {"text":"hello"}。
     */
    private func extractTextFromContent(contentJsonString: String): String {
        if (contentJsonString.isEmpty()) {
            return ""
        }
        return try {
            let contentObj = JsonValue.fromStr(contentJsonString).asObject()
            this.readStringField(contentObj, "text")
        } catch (e: Exception) {
            contentJsonString
        }
    }

    private func extractInboundText(messageType: String, contentJsonString: String): String {
        let normalized = messageType.trimAscii().toAsciiLower()
        if (normalized == "text") {
            return this.extractTextFromContent(contentJsonString)
        }
        if (normalized == "post") {
            return this.extractPostText(contentJsonString)
        }
        if (normalized == "interactive") {
            return this.extractInteractiveCardText(contentJsonString)
        }
        if (normalized == "image") {
            return "[image]"
        }
        if (normalized == "file") {
            return "[file]"
        }
        if (normalized == "media") {
            return "[media]"
        }
        if (normalized == "audio") {
            return "[audio]"
        }
        if (normalized == "video") {
            return "[video]"
        }
        if (normalized == "merge_forward") {
            return this.extractMergeForwardText(contentJsonString)
        }
        if (normalized == "sticker") {
            return "[sticker]"
        }
        if (normalized == "share_chat") {
            return "[shared chat]"
        }
        if (normalized == "share_user") {
            return "[shared user card]"
        }
        ""
    }

    private func extractMergeForwardText(contentJsonString: String): String {
        let title = try {
            let root = JsonValue.fromStr(contentJsonString).asObject()
            this.readStringField(root, "title").trimAscii()
        } catch (_e: Exception) {
            ""
        }
        if (title.isEmpty()) {
            "[merge forward]"
        } else {
            "[merge forward]\n${title}"
        }
    }

    private func extractPostText(contentJsonString: String): String {
        if (contentJsonString.isEmpty()) {
            return ""
        }
        return try {
            let root = JsonValue.fromStr(contentJsonString).asObject()
            let zh = match (root.get("zh_cn")) {
                case Some(v) => v.asObject()
                case None => return ""
            }
            let content = match (zh.get("content")) {
                case Some(v) => v.asArray()
                case None => return ""
            }
            var pieces = ArrayList<String>()
            for (i in 0..content.size()) {
                let rowVal = content[i]
                let row = rowVal as JsonArray
                if (let Some(items) <- row) {
                    for (j in 0..items.size()) {
                        let cellVal = items[j]
                        let cell = cellVal as JsonObject
                        if (let Some(obj) <- cell) {
                            let text = this.readStringField(obj, "text")
                            if (!text.trimAscii().isEmpty()) {
                                pieces.add(text)
                            }
                        }
                    }
                }
            }
            String.join(pieces.toArray(), delimiter: "\n")
        } catch (_e: Exception) {
            ""
        }
    }

    private func extractInteractiveCardText(contentJsonString: String): String {
        if (contentJsonString.isEmpty()) {
            return ""
        }
        return try {
            let root = JsonValue.fromStr(contentJsonString).asObject()
            var pieces = ArrayList<String>()
            this.collectInteractiveCardText(root, pieces)
            let merged = String.join(pieces.toArray(), delimiter: "\n")
            if (merged.trimAscii().isEmpty()) {
                "[interactive card]"
            } else {
                merged
            }
        } catch (_e: Exception) {
            "[interactive card]"
        }
    }

    private func collectInteractiveCardText(obj: JsonObject, pieces: ArrayList<String>): Unit {
        if (let Some(bodyValue) <- obj.get("body")) {
            let bodyObj = bodyValue as JsonObject
            if (let Some(body) <- bodyObj) {
                this.collectInteractiveCardText(body, pieces)
            }
        }
        if (let Some(elementsValue) <- obj.get("elements")) {
            let elementsArr = elementsValue as JsonArray
            if (let Some(elements) <- elementsArr) {
                for (i in 0..elements.size()) {
                    let itemVal = elements[i]
                    let itemObj = itemVal as JsonObject
                    if (let Some(item) <- itemObj) {
                        let content = this.readStringField(item, "content")
                        if (!content.trimAscii().isEmpty()) {
                            pieces.add(content)
                        }
                        if (let Some(textValue) <- item.get("text")) {
                            let textObj = textValue as JsonObject
                            if (let Some(textNode) <- textObj) {
                                let textContent = this.readStringField(textNode, "content")
                                if (!textContent.trimAscii().isEmpty()) {
                                    pieces.add(textContent)
                                }
                            }
                        }
                        this.collectInteractiveCardText(item, pieces)
                    }
                }
            }
        }
    }

    private func normalizeSendTarget(peerId: String): String {
        let trimmed = peerId.trimAscii()
        if (trimmed.isEmpty()) {
            return ""
        }
        var withoutProvider = trimmed
        let lowered = trimmed.toAsciiLower()
        if (lowered.startsWith("feishu:")) {
            withoutProvider = trimmed[7..trimmed.size]
        } else if (lowered.startsWith("lark:")) {
            withoutProvider = trimmed[5..trimmed.size]
        }
        let candidate = withoutProvider.trimAscii()
        let loweredTarget = candidate.toAsciiLower()
        for (prefix in ["chat:", "group:", "channel:", "user:", "dm:", "open_id:"]) {
            if (loweredTarget.startsWith(prefix)) {
                return candidate[prefix.size..candidate.size].trimAscii()
            }
        }
        candidate
    }

    private func buildTopicConversationId(chatId: String, topicId: String): String {
        if (chatId.trimAscii().isEmpty() || topicId.trimAscii().isEmpty()) {
            return chatId
        }
        "${chatId}:topic:${topicId}"
    }

    private func resolveConversationId(
        cfg: FeishuConfig,
        chatId: String,
        chatType: ChatType,
        senderId: String,
        messageId: String,
        rootId: String,
        threadId: String
    ): Option<String> {
        match (chatType) {
            case ChatType.Direct =>
                let directId = if (chatId.trimAscii().isEmpty()) { senderId.trimAscii() } else { chatId.trimAscii() }
                if (directId.isEmpty()) { None } else { Some(directId) }
            case ChatType.Group =>
                let normalizedChatId = chatId.trimAscii()
                let normalizedSenderId = senderId.trimAscii()
                let normalizedMessageId = messageId.trimAscii()
                let topicId = if (!rootId.trimAscii().isEmpty()) {
                    rootId.trimAscii()
                } else if (!threadId.trimAscii().isEmpty()) {
                    threadId.trimAscii()
                } else if (cfg.replyInThread == "enabled" && !normalizedMessageId.isEmpty()) {
                    normalizedMessageId
                } else {
                    ""
                }
                if (this.feishuThreadSessionEnabled(cfg, normalizedChatId, topicId)) {
                    return Some(this.buildTopicConversationId(normalizedChatId, topicId))
                }
                let scope = cfg.groupSessionScope.trimAscii().toAsciiLower()
                if (scope == "group_sender") {
                    if (normalizedChatId.isEmpty() || normalizedSenderId.isEmpty()) {
                        return if (normalizedChatId.isEmpty()) { None } else { Some(normalizedChatId) }
                    }
                    return Some("${normalizedChatId}:sender:${normalizedSenderId}")
                }
                if (scope == "group_topic") {
                    if (!topicId.isEmpty()) {
                        return Some(this.buildTopicConversationId(normalizedChatId, topicId))
                    }
                    return if (normalizedChatId.isEmpty()) { None } else { Some(normalizedChatId) }
                }
                if (scope == "group_topic_sender") {
                    if (!topicId.isEmpty() && !normalizedSenderId.isEmpty()) {
                        return Some("${normalizedChatId}:topic:${topicId}:sender:${normalizedSenderId}")
                    }
                    if (!normalizedSenderId.isEmpty()) {
                        return Some("${normalizedChatId}:sender:${normalizedSenderId}")
                    }
                    return if (normalizedChatId.isEmpty()) { None } else { Some(normalizedChatId) }
                }
                if (!topicId.isEmpty() && cfg.groupSessionScope.trimAscii().toAsciiLower() == "group_topic") {
                    return Some(this.buildTopicConversationId(normalizedChatId, topicId))
                }
                if (normalizedChatId.isEmpty()) { None } else { Some(normalizedChatId) }
        }
    }

    private func feishuThreadCapabilityCacheKey(accountId: String, chatId: String): String {
        "${this.normalizeAccountId(accountId)}:${chatId.trimAscii()}"
    }

    private func feishuThreadCapableGroup(accountId: String, chatId: String): Bool {
        let key = this.feishuThreadCapabilityCacheKey(accountId, chatId)
        match (this.threadCapabilityCache.get(key)) {
            case Some(cached) => return cached
            case None => ()
        }
        let capable = this.apiClient.isThreadCapableGroup(chatId.trimAscii())
        this.threadCapabilityCache[key] = capable
        capable
    }

    private func feishuThreadSessionStatus(cfg: FeishuConfig, chatId: String, topicId: String): (Bool, String) {
        if (!cfg.threadSession) {
            return (false, "thread_session_disabled")
        }
        if (chatId.trimAscii().isEmpty()) {
            return (false, "missing_chat_id")
        }
        if (topicId.trimAscii().isEmpty()) {
            return (false, "missing_thread_id")
        }
        if (!this.feishuThreadCapableGroup(cfg.accountId, chatId)) {
            return (false, "thread_not_capable")
        }
        (true, "enabled")
    }

    private func feishuThreadSessionEnabled(cfg: FeishuConfig, chatId: String, topicId: String): Bool {
        this.feishuThreadSessionStatus(cfg, chatId, topicId)[0]
    }

    private func resolveReplyTargetMessageId(messageId: String, rootId: String, threadId: String): Option<String> {
        let normalizedRoot = rootId.trimAscii()
        if (!normalizedRoot.isEmpty()) {
            return Some(normalizedRoot)
        }
        if (!threadId.trimAscii().isEmpty() && !messageId.trimAscii().isEmpty()) {
            return Some(messageId.trimAscii())
        }
        let normalizedMessageId = messageId.trimAscii()
        if (normalizedMessageId.isEmpty()) { None } else { Some(normalizedMessageId) }
    }

    private func shouldReplyInThread(chatType: ChatType, rootId: String, threadId: String): Bool {
        match (chatType) {
            case ChatType.Direct => false
            case ChatType.Group =>
                this.config.replyInThread == "enabled" ||
                    !rootId.trimAscii().isEmpty() ||
                    !threadId.trimAscii().isEmpty()
        }
    }

    private func feishuProjectRootForMonitorHost(): Path {
        try {
            if (exists(CliConfig.cwd.join("cjpm.toml"))) {
                return canonicalize(CliConfig.cwd)
            }
        } catch (_e: Exception) {
            ()
        }
        match (getVariable("METIS_CJPM_ROOT")) {
            case Some(v) =>
                let trimmed = v.trimAscii()
                if (!trimmed.isEmpty()) {
                    try {
                        let candidate = Path(trimmed)
                        if (exists(candidate.join("cjpm.toml"))) {
                            return canonicalize(candidate)
                        }
                    } catch (_e: Exception) {
                        ()
                    }
                }
            case None => ()
        }
        try {
            var cur = canonicalize(Path("."))
            var guard = 0
            while (guard < 96) {
                if (exists(cur.join("cjpm.toml"))) {
                    return cur
                }
                let par = cur.parent
                if (par == cur) {
                    break
                }
                cur = par
                guard += 1
            }
        } catch (_e: Exception) {
            ()
        }
        try {
            canonicalize(CliConfig.cwd)
        } catch (_e: Exception) {
            CliConfig.cwd
        }
    }

    private func feishuOfficialSdkMonitorHostScript(): Path {
        this.feishuProjectRootForMonitorHost().join("scripts").join("feishu-ws-sidecar.mjs")
    }

    private func feishuOfficialSdkDepsRoot(): Path {
        this.feishuProjectRootForMonitorHost().join("tools").join("feishu-official-sdk")
    }

    private func feishuOfficialSdkAvailable(): Bool {
        let scriptPath = this.feishuOfficialSdkMonitorHostScript()
        let depsRoot = this.feishuOfficialSdkDepsRoot()
        let depsPackage = depsRoot.join("package.json")
        let sdkPackage = depsRoot.join("node_modules").join("@larksuiteoapi").join("node-sdk").join("package.json")
        exists(scriptPath) && exists(depsPackage) && exists(sdkPackage)
    }

    private func feishuOfficialSdkMonitorHostEnabled(): Bool {
        if (this.config.receiveMode != "long_connect") {
            return false
        }
        this.feishuOfficialSdkAvailable()
    }

    private func feishuOfficialSdkMonitorError(): String {
        synchronized(this.feishuMonitorLock) {
            this.feishuMonitorLastError
        }
    }

    private func handleFeishuOfficialSdkMonitorHostLine(line: String): Unit {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty()) {
            return
        }
        try {
            let root = JsonValue.fromStr(trimmed).asObject()
            let kind = this.readStringField(root, "type")
            if (kind == "ready") {
                synchronized(this.feishuMonitorLock) {
                    this.feishuMonitorReady = true
                    this.feishuMonitorLastError = ""
                }
                PrintUtils.printLine("Feishu official SDK monitor host active")
                return
            }
            if (kind == "event") {
                match (root.get("payload")) {
                    case Some(v) =>
                        let _ = this.feishuDispatchEventRoot(v.asObject())
                    case None => ()
                }
                return
            }
            if (kind == "error") {
                let message = this.readStringField(root, "message")
                synchronized(this.feishuMonitorLock) {
                    this.feishuMonitorLastError = message
                }
                PrintUtils.printLine("Feishu official SDK monitor host error: ${message}")
                return
            }
            if (kind == "closed") {
                let reason = this.readStringField(root, "reason")
                synchronized(this.feishuMonitorLock) {
                    this.feishuMonitorReady = false
                    this.feishuMonitorLastError = reason
                }
                PrintUtils.printLine("Feishu official SDK monitor host closed: ${reason}")
                return
            }
        } catch (e: Exception) {
            PrintUtils.printLine("Feishu official SDK monitor host emitted invalid line: ${e.message}")
        }
    }

    private func startFeishuOfficialSdkMonitorHost(): Bool {
        if (!this.feishuOfficialSdkAvailable()) {
            PrintUtils.printLine(
                "Feishu official SDK monitor host unavailable script=${this.feishuOfficialSdkMonitorHostScript().toString()} deps=${this.feishuOfficialSdkDepsRoot().toString()}"
            )
            return false
        }
        this.cleanupStaleFeishuOfficialSdkMonitorHosts()
        try {
            let alreadyRunning = synchronized(this.feishuMonitorLock) {
                match (this.feishuMonitorProcess) {
                    case Some(_) => true
                    case None =>
                        this.feishuMonitorReady = false
                        this.feishuMonitorLastError = ""
                        let process = launch(
                            "node",
                            [
                                this.feishuOfficialSdkMonitorHostScript().toString(),
                                "--sdk-root",
                                this.feishuOfficialSdkDepsRoot().toString(),
                                "--app-id",
                                this.config.appId,
                                "--app-secret",
                                this.config.appSecret,
                                "--domain",
                                this.config.domain,
                                "--verification-token",
                                this.config.verificationToken,
                                "--encrypt-key",
                                this.config.encryptKey
                            ],
                            stdIn: ProcessRedirect.Pipe,
                            stdOut: ProcessRedirect.Pipe,
                            stdErr: ProcessRedirect.Pipe,
                            workingDirectory: Some(this.feishuProjectRootForMonitorHost())
                        )
                        this.feishuMonitorProcess = Some(process)
                        this.feishuMonitorStdIn = Some(StringWriter(process.stdInPipe))
                        this.feishuMonitorStdoutFuture = Some(spawn {
                            let reader = StringReader(process.stdOutPipe)
                            while (true) {
                                match (reader.readln()) {
                                    case Some(line) => this.handleFeishuOfficialSdkMonitorHostLine(line)
                                    case None => break
                                }
                            }
                        })
                        this.feishuMonitorStderrFuture = Some(spawn {
                            let reader = StringReader(process.stdErrPipe)
                            while (true) {
                                match (reader.readln()) {
                                    case Some(line) =>
                                        let text = line.trimAscii()
                                        if (!text.isEmpty()) {
                                            PrintUtils.printLine("Feishu official SDK monitor host stderr: ${text}")
                                        }
                                    case None => break
                                }
                            }
                        })
                        this.feishuMonitorWaitFuture = Some(spawn {
                            let exitCode = process.wait()
                            synchronized(this.feishuMonitorLock) {
                                this.feishuMonitorProcess = None
                                this.feishuMonitorStdIn = None
                                this.feishuMonitorReady = false
                                if (exitCode != 0 && this.feishuMonitorLastError.isEmpty()) {
                                    this.feishuMonitorLastError = "monitor-host-exit-${exitCode}"
                                }
                            }
                        })
                        false
                }
            }
            if (alreadyRunning) {
                return true
            }
        } catch (e: Exception) {
            synchronized(this.feishuMonitorLock) {
                this.feishuMonitorLastError = e.message
            }
            return false
        }
        for (_i in 0..40) {
            synchronized(this.feishuMonitorLock) {
                if (this.feishuMonitorReady) {
                    return true
                }
                match (this.feishuMonitorProcess) {
                    case Some(_) => ()
                    case None => return false
                }
            }
            sleep(Duration.millisecond * 50)
        }
        synchronized(this.feishuMonitorLock) {
            if (this.feishuMonitorLastError.isEmpty()) {
                this.feishuMonitorLastError = "monitor-host-timeout"
            }
        }
        this.stopFeishuOfficialSdkMonitorHost()
        false
    }

    private func stopFeishuOfficialSdkMonitorHost(): Unit {
        var processOpt = None<SubProcess>
        var writerOpt = None<StringWriter<OutputStream>>
        synchronized(this.feishuMonitorLock) {
            processOpt = this.feishuMonitorProcess
            writerOpt = this.feishuMonitorStdIn
        }
        match (writerOpt) {
            case Some(writer) =>
                try {
                    writer.write(feishuMonitorHostStopFrame())
                    writer.flush()
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
        match (processOpt) {
            case Some(process) =>
                let gracefulStopped = feishuWaitForMonitorHostExit(process, feishuMonitorHostGraceStopWaitMs())
                if (!gracefulStopped) {
                    try {
                        process.terminate(force: true)
                    } catch (_e: Exception) {
                        ()
                    }
                    let _ = feishuWaitForMonitorHostExit(process, feishuMonitorHostForcedStopWaitMs())
                }
            case None => ()
        }
        synchronized(this.feishuMonitorLock) {
            this.feishuMonitorProcess = None
            this.feishuMonitorStdIn = None
            this.feishuMonitorStdoutFuture = None
            this.feishuMonitorStderrFuture = None
            this.feishuMonitorWaitFuture = None
            this.feishuMonitorReady = false
        }
    }

    private func cleanupStaleFeishuOfficialSdkMonitorHosts(): Unit {
        let stalePids = feishuFindStaleMonitorHostPids(
            this.feishuOfficialSdkMonitorHostScript().toString(),
            this.config.appId
        )
        if (stalePids.isEmpty()) {
            return
        }
        let killed = feishuKillMonitorHostPids(stalePids)
        if (killed.size > 0) {
            let killedText = String.join(killed.map({ pid => pid.toString() }), delimiter: ",")
            PrintUtils.printLine("Feishu official SDK monitor host cleanup: killed stale sidecars ${killedText}")
        }
    }

    private func resolveReceiveIdType(peerId: String): String {
        let trimmed = peerId.trimAscii()
        let lowered = trimmed.toAsciiLower()
        if (lowered.startsWith("feishu:")) {
            return this.resolveReceiveIdType(trimmed[7..trimmed.size].trimAscii())
        }
        if (lowered.startsWith("lark:")) {
            return this.resolveReceiveIdType(trimmed[5..trimmed.size].trimAscii())
        }
        if (lowered.startsWith("chat:") || lowered.startsWith("group:") || lowered.startsWith("channel:")) {
            return "chat_id"
        }
        if (lowered.startsWith("open_id:")) {
            return "open_id"
        }
        if (lowered.startsWith("user:") || lowered.startsWith("dm:")) {
            let plain = this.normalizeSendTarget(trimmed)
            if (plain.startsWith("ou_")) {
                return "open_id"
            }
            return "user_id"
        }
        if (trimmed.startsWith("oc_")) {
            return "chat_id"
        }
        if (trimmed.startsWith("ou_")) {
            return "open_id"
        }
        "user_id"
    }

    /**
     * 调用飞书发送文本消息 API。
     * P1.5 约定 receive_id 使用 chat_id（由 inbound.peerId 透传）。
     */
    private func sendTextToFeishu(
        chatId: String,
        text: String,
        replyToMessageId!: Option<String> = None,
        replyInThread!: Bool = false
    ): Bool {
        let result = this.sendTextToFeishuDetailedForAccount(
            this.effectiveAccountId(),
            chatId,
            text,
            replyToMessageId: replyToMessageId,
            replyInThread: replyInThread
        )
        result[0]
    }

    private func sendTextToFeishuWithMessageId(
        chatId: String,
        text: String,
        replyToMessageId!: Option<String> = None,
        replyInThread!: Bool = false
    ): String {
        this.sendTextToFeishuWithMessageIdForAccount(
            this.effectiveAccountId(),
            chatId,
            text,
            replyToMessageId: replyToMessageId,
            replyInThread: replyInThread
        )
    }

    private func sendTextToFeishuWithMessageIdForAccount(
        accountId: String,
        chatId: String,
        text: String,
        replyToMessageId!: Option<String> = None,
        replyInThread!: Bool = false
    ): String {
        let result = this.sendTextToFeishuDetailedForAccount(
            accountId,
            chatId,
            text,
            replyToMessageId: replyToMessageId,
            replyInThread: replyInThread
        )
        result[1]
    }

    private func sendTextToFeishuDetailedForAccount(
        accountId: String,
        chatId: String,
        text: String,
        replyToMessageId!: Option<String> = None,
        replyInThread!: Bool = false
    ): (Bool, String) {
        let receiveId = this.normalizeSendTarget(chatId)
        if (receiveId.isEmpty() || text.trimAscii().isEmpty()) {
            this.lastSendError = "chatId/text is empty"
            return (false, "")
        }
        let cfg = this.feishuConfigForAccount(accountId)
        let receiveIdType = this.resolveReceiveIdType(chatId)
        let injected = this.apiClient.sendTextMessage(
            gatewayFeishuNormalizeAccountId(accountId),
            chatId,
            receiveId,
            receiveIdType,
            text,
            replyToMessageId,
            replyInThread
        )
        if (injected.ok && !injected.messageId.isEmpty()) {
            this.lastSendError = ""
            return (true, injected.messageId)
        }
        if (injected.status != "not_configured") {
            this.lastSendError = if (injected.error.isEmpty()) { injected.status } else { injected.error }
            return (false, "")
        }
        let token = this.getTenantAccessTokenForConfig(accountId, cfg)
        if (token.isEmpty()) {
            this.lastSendError = "tenant_access_token is empty"
            return (false, "")
        }

        let header = HashMap<String, String>([
            ("Content-Type", "application/json; charset=utf-8"),
            ("Authorization", "Bearer ${token}")
        ])

        let contentMap = HashMap<String, JsonValue>()
        contentMap["text"] = JsonString(text)

        let contentJson = JsonObject(contentMap).toJsonString()
        let responseOpt = if (let Some(replyId) <- replyToMessageId) {
            let normalizedReplyId = replyId.trimAscii()
            if (normalizedReplyId.isEmpty()) {
                this.sendCreateMessageRequest(cfg, chatId, receiveId, contentJson, header)
            } else {
                this.sendReplyMessageRequest(cfg, normalizedReplyId, contentJson, header, replyInThread: replyInThread)
            }
        } else {
            this.sendCreateMessageRequest(cfg, chatId, receiveId, contentJson, header)
        }
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.lastSendError = "empty http response"
                return (false, "")
        }
        let sentMessageId = this.parseFeishuApiMessageId(responseRaw)
        if (!sentMessageId.isEmpty()) {
            this.lastSendError = ""
            return (true, sentMessageId)
        }
        // Provider-internal fallback only:
        // core/runtime policy already decides whether reply/thread is allowed.
        // This branch only handles Feishu-specific reply target invalidation,
        // then degrades to a plain create-message call against the same chat.
        if (replyInThread) {
            return (false, "")
        }
        if (!this.shouldFallbackFromReplyFailure(responseRaw, replyToMessageId)) {
            return (false, "")
        }
        let fallbackResponseOpt = this.sendCreateMessageRequest(cfg, chatId, receiveId, contentJson, header)
        let fallbackResponseRaw = match (fallbackResponseOpt) {
            case Some(resp) => resp
            case None =>
                this.lastSendError = "empty http response"
                return (false, "")
        }
        let fallbackMessageId = this.parseFeishuApiMessageId(fallbackResponseRaw)
        if (!fallbackMessageId.isEmpty()) {
            this.lastSendError = ""
            return (true, fallbackMessageId)
        }
        (false, "")
    }

    private func sendCreateMessageRequest(
        cfg: FeishuConfig,
        rawPeerId: String,
        receiveId: String,
        contentJson: String,
        header: HashMap<String, String>
    ): Option<String> {
        let base = this.normalizeFeishuDomain(cfg)
        let receiveIdType = this.resolveReceiveIdType(rawPeerId)
        let url = "${base}/open-apis/im/v1/messages?receive_id_type=${receiveIdType}"
        let body = HashMap<String, JsonValue>()
        body["receive_id"] = JsonString(receiveId)
        body["msg_type"] = JsonString("text")
        body["content"] = JsonString(contentJson)
        HttpUtils.post(url, header, JsonObject(body))
    }

    private func sendReplyMessageRequest(
        cfg: FeishuConfig,
        replyToMessageId: String,
        contentJson: String,
        header: HashMap<String, String>,
        replyInThread!: Bool = false
    ): Option<String> {
        let base = this.normalizeFeishuDomain(cfg)
        let url = "${base}/open-apis/im/v1/messages/${replyToMessageId}/reply"
        let body = HashMap<String, JsonValue>()
        body["content"] = JsonString(contentJson)
        body["msg_type"] = JsonString("text")
        if (replyInThread) {
            body["reply_in_thread"] = JsonBool(true)
        }
        HttpUtils.post(url, header, JsonObject(body))
    }

    private func shouldFallbackFromReplyFailure(raw: String, replyToMessageId: Option<String>): Bool {
        if (replyToMessageId == None) {
            return false
        }
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let code = this.readIntField(jo, "code")
            let msg = this.readStringField(jo, "msg").toAsciiLower()
            code == 230011 || code == 231003 || msg.contains("withdrawn") || msg.contains("not found")
        } catch (_e: Exception) {
            false
        }
    }

    /**
     * 获取并缓存 tenant_access_token（应用凭证模式）。
     * 缓存策略：在过期前 60 秒刷新。
     */
    private func getTenantAccessToken(): String {
        this.getTenantAccessTokenForConfig(this.effectiveAccountId(), this.config)
    }

    private func getTenantAccessTokenForConfig(accountId: String, cfg: FeishuConfig): String {
        let normalizedAccountId = gatewayFeishuNormalizeAccountId(accountId)
        let nowNano = DateTime.now().toUnixTimeStamp().toNanoseconds()
        let cachedToken = this.tenantAccessTokens.get(normalizedAccountId) ?? ""
        let cachedExpireAt = this.tenantAccessTokenExpiries.get(normalizedAccountId) ?? 0
        if (!cachedToken.isEmpty() && nowNano < cachedExpireAt - 60 * 1000000000) {
            return cachedToken
        }
        if (cfg.appId.isEmpty() || cfg.appSecret.isEmpty()) {
            return ""
        }

        let base = this.normalizeFeishuDomain(cfg)
        let url = "${base}/open-apis/auth/v3/tenant_access_token/internal"
        let header = HashMap<String, String>([
            ("Content-Type", "application/json; charset=utf-8")
        ])
        let body = HashMap<String, JsonValue>()
        body["app_id"] = JsonString(cfg.appId)
        body["app_secret"] = JsonString(cfg.appSecret)

        let responseOpt = HttpUtils.post(url, header, JsonObject(body))
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.lastSendError = "tenant token api no response"
                return ""
        }

        return try {
            let jo = JsonValue.fromStr(responseRaw).asObject()
            let token = this.readStringField(jo, "tenant_access_token")
            let expire = this.readIntField(jo, "expire")
            if (!token.isEmpty()) {
                let ttlSeconds = if (expire > 0) { expire } else { 7200 }
                this.tenantAccessTokens[normalizedAccountId] = token
                this.tenantAccessTokenExpiries[normalizedAccountId] = nowNano + ttlSeconds * 1000000000
                this.lastSendError = ""
            } else {
                this.lastSendError = "tenant token api missing tenant_access_token"
            }
            token
        } catch (e: Exception) {
            this.lastSendError = "tenant token parse failed: ${e.message}"
            ""
        }
    }

    private func readIntField(obj: JsonObject, key: String): Int64 {
        return match (obj.get(key)) {
            case Some(v) => match (v) {
                case n: JsonInt => n.getValue()
                case n: JsonFloat => Int64(n.getValue())
                case _ => 0
            }
            case None => 0
        }
    }

    /**
     * 从 HttpContext 中读取请求 body 文本。
     * 这里依赖 std 库 `readString`，方便直接读取 UTF-8 字符串。
     */
    private func readRequestBody(ctx: HttpContext): String {
        return try {
            let output = ArrayList<Byte>()
            let buffer = Array<Byte>(4096, repeat: 0)
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

    /**
     * 签名/时效校验（P1.5）。
     *
     * 已实现：
     * - 时间戳头存在并在允许窗口内；
     * - 可选要求签名头存在；
     * - 可选要求 payload.token 与配置 token 一致。
     */
    private func validateWebhookPayload(headers: HttpHeaders, payload: String): Bool {
        let timestamp = headers.getFirst("X-Lark-Request-Timestamp") ??
            headers.getFirst("x-lark-request-timestamp") ??
            ""
        if (timestamp.isEmpty()) {
            return false
        }
        let ts = try {
            Int64.parse(timestamp)
        } catch (_e: Exception) {
            return false
        }

        let nowSec = DateTime.now().toUnixTimeStamp().toSeconds()
        let diff = if (nowSec >= ts) { nowSec - ts } else { ts - nowSec }
        if (diff > this.config.requestMaxSkewSeconds) {
            return false
        }

        if (this.config.requireSignatureHeaders) {
            let signature = headers.getFirst("X-Lark-Signature") ??
                headers.getFirst("x-lark-signature") ??
                ""
            if (signature.isEmpty()) {
                return false
            }
        }

        if (this.config.verificationToken.isEmpty()) {
            return true
        }
        return this.verifyTokenFromPayload(payload)
    }

    private func verifyTokenFromPayload(payload: String): Bool {
        if (payload.isEmpty()) {
            return false
        }
        return try {
            let jo = JsonValue.fromStr(payload).asObject()
            let token = this.readStringField(jo, "token")
            token == this.config.verificationToken
        } catch (_e: Exception) {
            false
        }
    }

    private func normalizeFeishuDomain(): String {
        this.normalizeFeishuDomain(this.config)
    }

    private func normalizeFeishuDomain(cfg: FeishuConfig): String {
        var d = cfg.domain.trimAscii()
        if (d.toAsciiLower() == "feishu") {
            d = "https://open.feishu.cn"
        } else if (d.toAsciiLower() == "lark") {
            d = "https://open.larksuite.com"
        }
        while (d.size > 0 && d.endsWith("/")) {
            d = d[0..d.size - 1]
        }
        d
    }

    /**
     * 解析飞书 API 返回，要求 code == 0 才算成功。
     */
    private func parseFeishuApiSuccess(raw: String): Bool {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let code = this.readIntField(jo, "code")
            if (code == 0) {
                this.lastSendError = ""
                true
            } else {
                let msg = this.readStringField(jo, "msg")
                this.lastSendError = "code=${code}, msg=${msg}"
                false
            }
        } catch (e: Exception) {
            this.lastSendError = "send api parse failed: ${e.message}"
            false
        }
    }

    private func parseFeishuApiMessageId(raw: String): String {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let code = this.readIntField(jo, "code")
            if (code != 0) {
                let msg = this.readStringField(jo, "msg")
                this.lastSendError = "code=${code}, msg=${msg}"
                return ""
            }
            match (jo.get("data")) {
                case Some(dataVal) =>
                    let data = dataVal.asObject()
                    let direct = this.readStringField(data, "message_id").trimAscii()
                    if (!direct.isEmpty()) {
                        return direct
                    }
                    this.readStringField(data, "id").trimAscii()
                case None => ""
            }
        } catch (e: Exception) {
            this.lastSendError = "send api parse failed: ${e.message}"
            ""
        }
    }
}

public func feishuMonitorHostIngressHintText(): String {
    "Feishu long_connect: using official SDK monitor host. Ensure app subscribes im.message.receive_v1 and console uses 长连接."
}

public func feishuMonitorHostStopFrame(): String {
    "{\"type\":\"stop\"}\n"
}

public func feishuMonitorHostGraceStopWaitMs(): Int64 {
    400
}

public func feishuMonitorHostForcedStopWaitMs(): Int64 {
    600
}

public func feishuMonitorHostShellSingleQuote(raw: String): String {
    "'" + raw.replace("'", "'\"'\"'") + "'"
}

public func feishuMonitorHostPsLookupCommand(scriptPath: String, appId: String): String {
    let quotedScript = feishuMonitorHostShellSingleQuote(scriptPath)
    let quotedAppId = feishuMonitorHostShellSingleQuote("--app-id ${appId}")
    "ps -axo pid=,ppid=,command= | grep -F -- ${quotedScript} | grep -F -- ${quotedAppId} | grep -v grep"
}

public func feishuParseMonitorHostPids(raw: String): Array<Int64> {
    let pids = ArrayList<Int64>()
    for (line in raw.split("\n")) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        let pieces = trimmed.split(" ")
        for (piece in pieces) {
            let token = piece.trimAscii()
            if (token.isEmpty()) {
                continue
            }
            try {
                let pid = Int64.parse(token)
                if (pid > 0 && !pids.contains(pid)) {
                    pids.add(pid)
                }
            } catch (_e: Exception) {
                ()
            }
            break
        }
    }
    pids.toArray()
}

private func feishuFindStaleMonitorHostPids(scriptPath: String, appId: String): Array<Int64> {
    if (scriptPath.trimAscii().isEmpty() || appId.trimAscii().isEmpty()) {
        return []
    }
    let (exitCode, stdOut, _) = ShellUtils.execute(
        ["sh", "-c", feishuMonitorHostPsLookupCommand(scriptPath, appId)],
        withWrap: false
    )
    if (exitCode != 0) {
        return []
    }
    feishuParseMonitorHostPids(stdOut)
}

private func feishuKillMonitorHostPids(pids: Array<Int64>): Array<Int64> {
    if (pids.isEmpty()) {
        return []
    }
    let valid = ArrayList<String>()
    let killed = ArrayList<Int64>()
    for (pid in pids) {
        if (pid > 0) {
            valid.add(pid.toString())
            killed.add(pid)
        }
    }
    if (valid.isEmpty()) {
        return []
    }
    let command = ["sh", "-c", "kill -9 ${String.join(valid.toArray(), delimiter: " ")} 2>/dev/null"]
    let (exitCode, _, _) = ShellUtils.execute(command, withWrap: false)
    if (exitCode != 0) {
        return []
    }
    killed.toArray()
}

private func feishuWaitForMonitorHostExit(process: SubProcess, timeoutMs: Int64): Bool {
    if (timeoutMs <= 0) {
        return false
    }
    try {
        let _ = process.wait(timeout: Duration.millisecond * timeoutMs)
        true
    } catch (_e: Exception) {
        false
    }
}
