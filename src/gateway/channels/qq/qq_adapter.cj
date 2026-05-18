package metis.gateway.channels.qq

import metis.gateway.core.{ChannelAdapter, gatewayLogIdentityHash}
import metis.gateway.logging.{MetisLogEvent, metisCreateSubsystemLogger}
import metis.gateway.model.*
import metis.gateway.model.QQConfig

import magic.jsonable.*
import magic.utils.http.*

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.time.*
import std.sync.Mutex
import stdx.encoding.json.*
import stdx.encoding.url.*
import stdx.net.http.*
import stdx.net.tls.*

/**
 * QQ 适配器。
 *
 * 当前正式路径：
 * - official QQ Bot API
 * - WebSocket gateway
 * - 使用 AppId/AppSecret 换取 access token
 */
public class QQAdapter <: ChannelAdapter {
    private var running = false
    private let queueMutex = Mutex()
    private let inboundQueue = ArrayList<InboundMessage>()
    private let outboundLog = ArrayList<OutboundMessage>()
    private let config: QQConfig
    private let resolvedAccount: QqResolvedAccount
    private var webhookServer: Option<Server> = None
    private var lastSendError: String = ""
    private let recentMessageIds = ArrayList<String>()
    private var officialAccessToken: String = ""
    private var officialTokenExpireAtNano: Int64 = 0
    private var officialSeq: Int64 = 0
    private var officialSessionId: String = ""
    private var officialConnectionSerial: Int64 = 0

    public init(config!: QQConfig = QQConfig(), accountId!: String = "") {
        let requestedAccountId = if (accountId.trimAscii().isEmpty()) { config.accountId } else { accountId.trimAscii() }
        let resolved = gatewayQqResolveAccount(config, requestedAccountId)
        this.config = resolved.config
        this.resolvedAccount = resolved
    }

    public func debugAccountIdForTest(): String {
        this.config.accountId
    }

    public func debugLastSendErrorForTest(): String {
        this.lastSendError
    }

    public func debugParseOfficialSendSuccessForTest(raw: String): Bool {
        this.parseOfficialSendSuccess(raw)
    }

    public func debugParseOfficialSendMessageIdForTest(raw: String): String {
        this.parseOfficialSendMessageId(raw)
    }

    private func channelLogMeta(
        phase: String,
        status: String,
        errorKind!: String = "none",
        error!: String = "",
        extra!: JsonObject = JsonObject()
    ): JsonObject {
        let meta = JsonObject()
        meta.put("channel", JsonString("qq"))
        meta.put("accountId", JsonString(this.config.accountId))
        meta.put("phase", JsonString(phase.trimAscii()))
        meta.put("status", JsonString(status.trimAscii()))
        meta.put("errorKind", JsonString(if (errorKind.trimAscii().isEmpty()) { "none" } else { errorKind.trimAscii() }))
        if (!error.trimAscii().isEmpty()) {
            meta.put("error", JsonString(error.trimAscii()))
        }
        for (key in extra.getFields().keys()) {
            match (extra.get(key)) {
                case Some(value) => meta.put(key, value)
                case None => ()
            }
        }
        meta
    }

    private func logChannel(
        level: String,
        event: String,
        phase: String,
        status: String,
        message: String,
        errorKind!: String = "none",
        error!: String = "",
        extra!: JsonObject = JsonObject()
    ): Unit {
        let meta = this.channelLogMeta(phase, status, errorKind: errorKind, error: error, extra: extra)
        let logger = metisCreateSubsystemLogger("gateway/channel/qq")
        match (level.trimAscii().toAsciiLower()) {
            case "debug" => logger.debug(event, message, meta: meta)
            case "warn" => logger.warn(event, message, meta: meta)
            case "error" => logger.error(event, message, meta: meta)
            case _ => logger.info(event, message, meta: meta)
        }
    }

    private func logError(message: String): Unit {
        this.logChannel(
            "warn",
            MetisLogEvent.channelFailed,
            "runtime",
            "failed",
            message,
            errorKind: this.qqErrorKind(message),
            error: message
        )
    }

    private func qqErrorKind(detail: String): String {
        let lowered = detail.trimAscii().toAsciiLower()
        if (lowered.isEmpty()) { return "unknown" }
        if (lowered.contains("token") || lowered.contains("secret") || lowered.contains("credential") || lowered.contains("authorization")) {
            return "credential"
        }
        if (lowered.contains("not running")) { return "not-running" }
        if (lowered.contains("invalid") || lowered.contains("missing") || lowered.contains("unsupported")) {
            return "validation"
        }
        if (lowered.contains("http") || lowered.contains("response") || lowered.contains("websocket") || lowered.contains("gateway")) {
            return "transport"
        }
        if (lowered.contains("parse") || lowered.contains("json")) { return "parse" }
        if (lowered.contains("heartbeat")) { return "heartbeat" }
        "unknown"
    }

    private func logSendFailure(message: OutboundMessage, detail: String): Unit {
        let extra = JsonObject()
        extra.put("peerHash", JsonString(gatewayLogIdentityHash(message.peerId)))
        extra.put("textLen", message.text.size.toJsonValue())
        extra.put("replyToPresent", message.replyToMessageId.isSome().toJsonValue())
        this.logChannel(
            "warn",
            MetisLogEvent.messageSendFailed,
            "send",
            "failed",
            "QQ send failed",
            errorKind: this.qqErrorKind(detail),
            error: detail,
            extra: extra
        )
    }

    public prop name: String {
        get() { "qq" }
    }

    public func start(): Unit {
        if (this.running || !this.config.enabled) {
            return
        }
        if (!this.isOfficialWsMode()) {
            this.lastSendError = "QQ adapter only supports official_ws mode"
            this.logChannel("error", MetisLogEvent.channelFailed, "start", "failed", "QQ adapter start failed", errorKind: "configuration", error: this.lastSendError)
            return
        }
        if (this.resolvedAccount.missingAccount) {
            this.lastSendError = this.resolvedAccount.missingDiagnostic
            this.logChannel("error", MetisLogEvent.channelFailed, "start", "failed", "QQ adapter start failed", errorKind: "configuration", error: this.lastSendError)
            return
        }
        if (this.resolvedAccount.missingCredential) {
            this.lastSendError = this.resolvedAccount.missingDiagnostic
            this.logChannel("error", MetisLogEvent.channelFailed, "start", "failed", "QQ adapter start failed", errorKind: "credential", error: this.lastSendError)
            return
        }
        if (this.config.appId.isEmpty() || this.config.appSecret.isEmpty()) {
            this.lastSendError = "QQ official mode requires appId and appSecret for account ${this.config.accountId}"
            this.logChannel("error", MetisLogEvent.channelFailed, "start", "failed", "QQ adapter start failed", errorKind: "credential", error: this.lastSendError)
            return
        }
        this.running = true
        let extra = JsonObject()
        extra.put("mode", JsonString("official_ws"))
        this.logChannel("info", MetisLogEvent.channelStarted, "start", "started", "QQ adapter started", extra: extra)
        this.startOfficialGatewayLoop()
    }

    public func stop(): Unit {
        this.running = false
        this.officialConnectionSerial += 1
        if (let Some(server) <- this.webhookServer) {
            try {
                server.close()
            } catch (_e: Exception) {
                ()
            } finally {
                this.webhookServer = None
            }
        }
    }

    public func pullInbound(): Array<InboundMessage> {
        synchronized(this.queueMutex) {
            if (!this.running || this.inboundQueue.isEmpty()) {
                return []
            }
            let result = this.inboundQueue.toArray()
            this.inboundQueue.clear()
            return result
        }
    }

    public func send(message: OutboundMessage): SendResult {
        if (!this.running) {
            this.logSendFailure(message, "qq adapter is not running")
            return SendResult.Failed("qq adapter is not running")
        }
        let sendMeta = JsonObject()
        sendMeta.put("peerHash", JsonString(gatewayLogIdentityHash(message.peerId)))
        sendMeta.put("textLen", message.text.size.toJsonValue())
        this.logChannel("debug", MetisLogEvent.channelSend, "send", "started", "QQ send started", extra: sendMeta)
        let sentMessageId = this.sendTextToQQWithMessageId(message.peerId, message.text, message.replyToMessageId)
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
        }
        if (!sentMessageId.trimAscii().isEmpty()) {
            this.logChannel("info", MetisLogEvent.messageSent, "send", "sent", "QQ send succeeded", extra: sendMeta)
            return SendResult.Success
        }
        this.logSendFailure(message, this.lastSendError)
        return SendResult.Failed("failed to send qq message: ${this.lastSendError}")
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        if (!this.running) {
            this.logSendFailure(message, "qq adapter is not running")
            return ""
        }
        let sentMessageId = this.sendTextToQQWithMessageId(message.peerId, message.text, message.replyToMessageId)
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
        }
        if (sentMessageId.trimAscii().isEmpty() && !this.lastSendError.trimAscii().isEmpty()) {
            this.logSendFailure(message, this.lastSendError)
        }
        sentMessageId
    }

    /**
     * 手工注入测试消息（用于本地联调）。
     */
    public func simulateIncomingText(
        messageId: String,
        peerId: String,
        senderId: String,
        text: String,
        chatType!: ChatType = ChatType.Direct,
        mentioned!: Bool = true
    ): Unit {
        let msg = InboundMessage(
            ChannelType.QQ,
            messageId,
            peerId,
            senderId,
            chatType,
            text,
            mentioned,
            DateTime.now(),
            raw: None
        )
        synchronized(this.queueMutex) {
            this.inboundQueue.add(msg)
        }
    }

    public func getOutboundLog(): Array<OutboundMessage> {
        synchronized(this.queueMutex) {
            return this.outboundLog.toArray()
        }
    }

    private func startWebhookServer(): Unit {
        let server = ServerBuilder()
            .addr(this.config.webhookHost)
            .port(this.config.webhookPort)
            .build()

        server.distributor.register(this.config.webhookPath, { ctx =>
            let payload = this.readRequestBody(ctx)
            let receiveMeta = JsonObject()
            receiveMeta.put("payloadBytes", payload.size.toJsonValue())
            this.logChannel("debug", MetisLogEvent.messageInbound, "webhook", "received", "QQ webhook received payload", extra: receiveMeta)
            if (!this.validateWebhookHeaders(ctx.request.headers)) {
                this.logChannel(
                    "warn",
                    MetisLogEvent.messageInbound,
                    "webhook",
                    "failed",
                    "QQ webhook header validation failed",
                    errorKind: "credential",
                    error: "invalid authorization header"
                )
                ctx.responseBuilder.body("{\"ok\":false,\"error\":\"unauthorized\"}")
                return
            }
            let ack = this.ingestWebhookPayload(payload)
            let ackMeta = JsonObject()
            ackMeta.put("ackBytes", ack.size.toJsonValue())
            ackMeta.put("ackOk", ack.contains("\"ok\":true").toJsonValue())
            this.logChannel("debug", MetisLogEvent.messageInbound, "webhook", "ack", "QQ webhook ack generated", extra: ackMeta)
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

    private func validateWebhookHeaders(headers: HttpHeaders): Bool {
        if (!this.config.requireAuthorizationHeader) {
            return true
        }
        if (this.config.accessToken.isEmpty()) {
            return false
        }
        let auth = headers.getFirst("Authorization") ??
            headers.getFirst("authorization") ??
            ""
        if (auth.isEmpty()) {
            return false
        }
        return auth == "Bearer ${this.config.accessToken}" || auth == this.config.accessToken
    }

    /**
     * 解析 OneBot 风格 webhook payload，并将消息事件入队。
     */
    public func ingestWebhookPayload(payload: String): String {
        let root = try {
            JsonValue.fromStr(payload).asObject()
        } catch (_e: Exception) {
            let extra = JsonObject()
            extra.put("payloadBytes", payload.size.toJsonValue())
            this.logChannel("warn", MetisLogEvent.messageInbound, "ingest", "failed", "QQ ingest invalid JSON", errorKind: "parse", error: "invalid_json", extra: extra)
            return "{\"ok\":false,\"error\":\"invalid_json\"}"
        }

        // QQ 平台回调地址验证（op=13）
        // 说明：严格实现需要按官方文档对 plain_token + event_ts 使用 Ed25519 生成 signature。
        // 当前先返回可观测提示，避免被当成普通事件处理。
        let op = this.readIntField(root, "op")
        if (op == 13) {
            let d = match (root.get("d")) {
                case Some(v) => v.asObject()
                case None => JsonObject(HashMap<String, JsonValue>())
            }
            let plainToken = this.readStringField(d, "plain_token")
            let eventTs = this.readStringField(d, "event_ts")
            let extra = JsonObject()
            extra.put("plainTokenPresent", (!plainToken.isEmpty()).toJsonValue())
            extra.put("eventTsPresent", (!eventTs.trimAscii().isEmpty()).toJsonValue())
            this.logChannel(
                "warn",
                MetisLogEvent.messageInbound,
                "webhook",
                "verification",
                "QQ callback verification received without Ed25519 signature support",
                errorKind: "not-implemented",
                extra: extra
            )
            return "{\"plain_token\":\"${plainToken}\",\"signature\":\"\"}"
        }

        // 官方 WS 控制事件（例如 READY/RESUMED）不是业务消息，直接忽略并返回 ok。
        if (op == 0) {
            let eventType = this.readStringField(root, "t")
            if (this.isIgnoredOfficialControlEvent(eventType)) {
                let extra = JsonObject()
                extra.put("eventType", JsonString(eventType))
                this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "ignored", "QQ ingest ignored control event", extra: extra)
                return "{\"ok\":true,\"ignored\":true,\"event\":\"${eventType}\"}"
            }
        }

        if (let Some(inbound) <- this.mapWebhookToInbound(root)) {
            let dedupKey = this.buildDedupKey(root, inbound)
            let mappedMeta = JsonObject()
            mappedMeta.put("messageId", JsonString(inbound.messageId))
            mappedMeta.put("peerHash", JsonString(gatewayLogIdentityHash(inbound.peerId)))
            mappedMeta.put("senderHash", JsonString(gatewayLogIdentityHash(inbound.senderId)))
            mappedMeta.put("mentioned", inbound.mentioned.toJsonValue())
            mappedMeta.put("textLen", inbound.text.size.toJsonValue())
            this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "mapped", "QQ ingest mapped inbound message", extra: mappedMeta)
            synchronized(this.queueMutex) {
                if (this.isDuplicateMessage(dedupKey)) {
                    let dedupMeta = JsonObject()
                    dedupMeta.put("dedupHash", JsonString(gatewayLogIdentityHash(dedupKey)))
                    this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "dedup", "QQ ingest duplicate message skipped", extra: dedupMeta)
                    return "{\"ok\":true,\"dedup\":true}"
                }
                this.inboundQueue.add(inbound)
                this.markMessageProcessed(dedupKey)
                let queuedMeta = JsonObject()
                queuedMeta.put("messageId", JsonString(inbound.messageId))
                queuedMeta.put("queueSize", this.inboundQueue.size.toJsonValue())
                this.logChannel("info", MetisLogEvent.messageInbound, "ingest", "queued", "QQ ingest queued message", extra: queuedMeta)
            }
            return "{\"ok\":true}"
        }
        let eventType = this.readStringField(root, "t")
        if (op == 0 && !eventType.isEmpty()) {
            if (this.isSupportedOfficialInboundEvent(eventType)) {
                let extra = JsonObject()
                extra.put("eventType", JsonString(eventType))
                this.logChannel("warn", MetisLogEvent.messageInbound, "ingest", "failed", "QQ supported event payload missing required fields", errorKind: "validation", extra: extra)
                return "{\"ok\":false,\"error\":\"invalid_event_payload\",\"event\":\"${eventType}\"}"
            }
            let extra = JsonObject()
            extra.put("eventType", JsonString(eventType))
            this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "ignored", "QQ ingest ignored unsupported official event", extra: extra)
            return "{\"ok\":true,\"ignored\":true,\"reason\":\"unsupported_event\",\"event\":\"${eventType}\"}"
        }
        let extra = JsonObject()
        extra.put("op", op.toJsonValue())
        extra.put("eventType", JsonString(eventType))
        this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "ignored", "QQ ingest ignored unsupported op", extra: extra)
        return "{\"ok\":true,\"ignored\":true,\"reason\":\"unsupported_op\",\"event\":\"${eventType}\"}"
    }

    private func mapWebhookToInbound(root: JsonObject): Option<InboundMessage> {
        return this.mapOfficialWebhookToInbound(root)
    }

    private func mapOnebotWebhookToInbound(root: JsonObject): Option<InboundMessage> {
        let postType = this.readStringField(root, "post_type")
        if (postType != "message") {
            let extra = JsonObject()
            extra.put("postType", JsonString(postType))
            this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "ignored", "QQ onebot post type ignored", extra: extra)
            return None
        }
        let messageType = this.readStringField(root, "message_type")
        let messageId = this.readStringField(root, "message_id")
        let senderId = this.readStringField(root, "user_id")
        let text = this.readStringField(root, "raw_message")

        let chatType: ChatType
        let peerId: String
        let mentioned: Bool
        if (messageType == "private") {
            chatType = ChatType.Direct
            peerId = "user:${senderId}"
            mentioned = true
        } else if (messageType == "group") {
            chatType = ChatType.Group
            let groupId = this.readStringField(root, "group_id")
            peerId = "group:${groupId}"
            mentioned = this.detectMention(text)
        } else {
            let extra = JsonObject()
            extra.put("messageType", JsonString(messageType))
            this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "ignored", "QQ onebot message type ignored", extra: extra)
            return None
        }
        return InboundMessage(
            ChannelType.QQ,
            messageId,
            peerId,
            senderId,
            chatType,
            text,
            mentioned,
            DateTime.now(),
            conversationId: Some(peerId),
            replyTargetMessageId: if (messageId.trimAscii().isEmpty()) { None<String> } else { Some(messageId.trimAscii()) },
            raw: Some(root.toJsonString())
        )
    }

    /**
     * 官方机器人事件解析（沿用 AppId/AppSecret 模式）：
     * - GROUP_AT_MESSAGE_CREATE
     * - C2C_MESSAGE_CREATE
     *
     * 说明：不同网关/代理对字段可能有差异，这里做了兼容读法。
     */
    private func mapOfficialWebhookToInbound(root: JsonObject): Option<InboundMessage> {
        let eventType = this.readStringField(root, "t")
        let eventMeta = JsonObject()
        eventMeta.put("eventType", JsonString(eventType))
        this.logChannel("debug", MetisLogEvent.messageInbound, "ingest", "mapping", "QQ official event mapping", extra: eventMeta)
        if (this.isIgnoredOfficialControlEvent(eventType)) {
            // 连接建立/恢复事件，不是业务消息，静默忽略。
            return None
        }
        let data = match (root.get("d")) {
            case Some(v) => v.asObject()
            case None => return None
        }

        let messageId = this.readStringField(data, "id")
        let text = this.readStringField(data, "content")

        let senderId = this.resolveOfficialSenderId(data)

        if (eventType == "GROUP_AT_MESSAGE_CREATE" || eventType == "GROUP_MESSAGE_CREATE") {
            let groupOpenid = this.readStringField(data, "group_openid")
            if (groupOpenid.isEmpty()) {
                return None
            }
            let mentioned = if (eventType == "GROUP_AT_MESSAGE_CREATE") {
                true
            } else {
                this.officialMessageMentionsBot(data)
            }
            let normalizedText = this.normalizeOfficialMessageText(text)
            return InboundMessage(
                ChannelType.QQ,
                messageId,
                "group:${groupOpenid}",
                senderId,
                ChatType.Group,
                normalizedText,
                mentioned,
                DateTime.now(),
                conversationId: Some("group:${groupOpenid}"),
                replyTargetMessageId: if (messageId.trimAscii().isEmpty()) { None<String> } else { Some(messageId.trimAscii()) },
                raw: Some(root.toJsonString())
            )
        }

        if (eventType == "C2C_MESSAGE_CREATE") {
            let peerOpenid = this.readStringField(data, "user_openid")
            let realPeer = if (peerOpenid.isEmpty()) { senderId } else { peerOpenid }
            if (realPeer.isEmpty()) {
                return None
            }
            let normalizedText = this.normalizeOfficialMessageText(text)
            return InboundMessage(
                ChannelType.QQ,
                messageId,
                "user:${realPeer}",
                senderId,
                ChatType.Direct,
                normalizedText,
                true,
                DateTime.now(),
                conversationId: Some("user:${realPeer}"),
                replyTargetMessageId: if (messageId.trimAscii().isEmpty()) { None<String> } else { Some(messageId.trimAscii()) },
                raw: Some(root.toJsonString())
            )
        }
        return None
    }

    private func isIgnoredOfficialControlEvent(eventType: String): Bool {
        eventType == "READY" || eventType == "RESUMED"
    }

    private func isSupportedOfficialInboundEvent(eventType: String): Bool {
        eventType == "GROUP_AT_MESSAGE_CREATE" ||
        eventType == "GROUP_MESSAGE_CREATE" ||
        eventType == "C2C_MESSAGE_CREATE"
    }

    private func resolveOfficialSenderId(data: JsonObject): String {
        let userOpenid = this.readStringField(data, "user_openid")
        if (!userOpenid.isEmpty()) {
            return userOpenid
        }
        let authorId = this.readStringField(data, "author_id")
        if (!authorId.isEmpty()) {
            return authorId
        }
        return match (data.get("author")) {
            case Some(v) => this.readStringField(v.asObject(), "id")
            case None => ""
        }
    }

    private func officialMessageMentionsBot(data: JsonObject): Bool {
        return match (data.get("mentions")) {
            case Some(mv) =>
                if (this.jsonMentionsContainBotIdentity(mv)) {
                    true
                } else {
                    this.textContainsBotMention(this.readStringField(data, "content"))
                }
            case None => this.textContainsBotMention(this.readStringField(data, "content"))
        }
    }

    private func jsonMentionsContainBotIdentity(mv: JsonValue): Bool {
        let mentionsArr = mv as JsonArray
        if (let Some(arr) <- mentionsArr) {
            for (i in 0..arr.size()) {
                let itemObj = arr[i] as JsonObject
                if (let Some(o) <- itemObj) {
                    if (this.officialMentionMatchesIdentity(this.readStringField(o, "id"))) {
                        return true
                    }
                    if (this.officialMentionMatchesIdentity(this.readStringField(o, "user_openid"))) {
                        return true
                    }
                    if (this.officialMentionMatchesIdentity(this.readStringField(o, "member_openid"))) {
                        return true
                    }
                    if (let Some(botObjValue) <- o.get("bot")) {
                        let botObj = botObjValue as JsonObject
                        if (let Some(bo) <- botObj) {
                            if (this.officialMentionMatchesIdentity(this.readStringField(bo, "id"))) {
                                return true
                            }
                            if (this.officialMentionMatchesIdentity(this.readStringField(bo, "user_openid"))) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        false
    }

    private func officialMentionMatchesIdentity(candidate: String): Bool {
        let normalized = candidate.trimAscii()
        if (normalized.isEmpty()) {
            return false
        }
        return normalized == this.config.botQQ || normalized == this.config.appId
    }

    private func textContainsBotMention(text: String): Bool {
        let trimmed = text.trimAscii()
        if (trimmed.isEmpty()) {
            return false
        }
        if (!this.config.botQQ.isEmpty()) {
            if (trimmed.contains("<@!${this.config.botQQ}>") || trimmed.contains("<@${this.config.botQQ}>") || trimmed.contains("@${this.config.botQQ}")) {
                return true
            }
        }
        if (!this.config.appId.isEmpty()) {
            if (trimmed.contains("<@!${this.config.appId}>") || trimmed.contains("<@${this.config.appId}>") || trimmed.contains("@${this.config.appId}")) {
                return true
            }
        }
        false
    }

    private func normalizeOfficialMessageText(text: String): String {
        var normalized = text
        if (!this.config.botQQ.isEmpty()) {
            normalized = normalized.replace("<@!${this.config.botQQ}>", "")
            normalized = normalized.replace("<@${this.config.botQQ}>", "")
            normalized = normalized.replace("@${this.config.botQQ}", "")
        }
        if (!this.config.appId.isEmpty()) {
            normalized = normalized.replace("<@!${this.config.appId}>", "")
            normalized = normalized.replace("<@${this.config.appId}>", "")
            normalized = normalized.replace("@${this.config.appId}", "")
        }
        normalized.trimAscii()
    }

    private func detectMention(text: String): Bool {
        // 安全策略：未配置 botQQ 时，群聊默认不触发，避免误触发。
        if (this.config.botQQ.isEmpty()) {
            return false
        }
        return text.contains("[CQ:at,qq=${this.config.botQQ}]")
    }

    private func buildDedupKey(root: JsonObject, inbound: InboundMessage): String {
        let eventType = this.readStringField(root, "t")
        if (eventType.isEmpty()) {
            return inbound.messageId
        }
        return "${eventType}:${inbound.peerId}:${inbound.messageId}"
    }

    private func sendTextToQQ(peerId: String, text: String, replyToMessageId: Option<String>): Bool {
        !this.sendTextToQQWithMessageId(peerId, text, replyToMessageId).trimAscii().isEmpty()
    }

    private func sendTextToQQWithMessageId(peerId: String, text: String, replyToMessageId: Option<String>): String {
        this.sendTextToQQOfficialWithMessageId(peerId, text, replyToMessageId)
    }

    private func sendTextToQQOnebot(peerId: String, text: String): Bool {
        if (peerId.trimAscii().isEmpty() || text.trimAscii().isEmpty()) {
            this.lastSendError = "peerId/text is empty"
            return false
        }
        let (isGroup, pureId) = this.parsePeerId(peerId)
        let apiPath = this.resolveSendApiPath(isGroup)
        let url = this.config.onebotApiBaseUrl + apiPath
        let requestMeta = JsonObject()
        requestMeta.put("apiPath", JsonString(apiPath))
        requestMeta.put("isGroup", isGroup.toJsonValue())
        requestMeta.put("peerHash", JsonString(gatewayLogIdentityHash(peerId)))
        requestMeta.put("textLen", text.size.toJsonValue())
        this.logChannel("debug", MetisLogEvent.channelSend, "send", "request", "QQ onebot send request", extra: requestMeta)

        let header = HashMap<String, String>()
        header["Content-Type"] = "application/json; charset=utf-8"
        if (!this.config.accessToken.isEmpty()) {
            header["Authorization"] = "Bearer ${this.config.accessToken}"
        }

        let body = HashMap<String, JsonValue>()
        if (apiPath == "/send_msg") {
            body["message_type"] = JsonString(if (isGroup) { "group" } else { "private" })
            if (isGroup) {
                body["group_id"] = JsonString(pureId)
            } else {
                body["user_id"] = JsonString(pureId)
            }
        } else {
            if (isGroup) {
                body["group_id"] = JsonString(pureId)
            } else {
                body["user_id"] = JsonString(pureId)
            }
        }
        body["message"] = JsonString(text)
        body["auto_escape"] = false.toJsonValue()

        let responseOpt = HttpUtils.post(url, header, JsonObject(body))
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.lastSendError = "empty http response"
                this.logChannel("warn", MetisLogEvent.messageSendFailed, "send", "failed", "QQ onebot send returned empty response", errorKind: "transport", error: this.lastSendError, extra: requestMeta)
                return false
        }
        let responseMeta = JsonObject()
        responseMeta.put("responseBytes", responseRaw.size.toJsonValue())
        responseMeta.put("apiPath", JsonString(apiPath))
        this.logChannel("debug", MetisLogEvent.channelSend, "send", "response", "QQ onebot send response received", extra: responseMeta)
        return this.parseOnebotApiSuccess(responseRaw)
    }

    private func sendTextToQQOfficial(peerId: String, text: String, replyToMessageId: Option<String>): Bool {
        !this.sendTextToQQOfficialWithMessageId(peerId, text, replyToMessageId).trimAscii().isEmpty()
    }

    private func sendTextToQQOfficialWithMessageId(peerId: String, text: String, replyToMessageId: Option<String>): String {
        if (peerId.trimAscii().isEmpty() || text.trimAscii().isEmpty()) {
            this.lastSendError = "peerId/text is empty"
            return ""
        }
        let token = this.getOfficialAccessToken()
        if (token.isEmpty()) {
            return ""
        }
        let (isGroup, pureId) = this.parsePeerId(peerId)
        let urlTemplate = if (isGroup) {
            this.config.officialSendGroupUrlTemplate
        } else {
            this.config.officialSendPrivateUrlTemplate
        }
        let url = urlTemplate.replace("{peer_id}", pureId)
        let replyTarget = match (replyToMessageId) {
            case Some(v) => v
            case None => ""
        }
        let requestMeta = JsonObject()
        requestMeta.put("isGroup", isGroup.toJsonValue())
        requestMeta.put("peerHash", JsonString(gatewayLogIdentityHash(peerId)))
        requestMeta.put("textLen", text.size.toJsonValue())
        requestMeta.put("replyToPresent", (!replyTarget.trimAscii().isEmpty()).toJsonValue())
        this.logChannel("debug", MetisLogEvent.channelSend, "send", "request", "QQ official send request", extra: requestMeta)

        let header = HashMap<String, String>()
        header["Content-Type"] = "application/json; charset=utf-8"
        header["Authorization"] = "${this.config.officialAuthScheme} ${token}"
        if (!this.config.appId.isEmpty()) {
            header["X-Union-Appid"] = this.config.appId
        }

        let body = HashMap<String, JsonValue>()
        body["content"] = JsonString(text)
        // Provider-internal behavior:
        // QQ official send only supports message-level reply via msg_id.
        // Thread-style degradation is handled earlier by the unified delivery policy.
        if (let Some(msgId) <- replyToMessageId) {
            if (!msgId.isEmpty()) {
                body["msg_id"] = JsonString(msgId)
            }
        }
        let responseOpt = try {
            HttpUtils.post(url, header, JsonObject(body))
        } catch (e: HttpException) {
            this.lastSendError = "official send http error: ${e.message}"
            this.logChannel("warn", MetisLogEvent.messageSendFailed, "send", "failed", "QQ official send HTTP error", errorKind: "transport", error: this.lastSendError, extra: requestMeta)
            return ""
        } catch (e: Exception) {
            this.lastSendError = "official send exception: ${e.message}"
            this.logChannel("warn", MetisLogEvent.messageSendFailed, "send", "failed", "QQ official send exception", errorKind: this.qqErrorKind(this.lastSendError), error: this.lastSendError, extra: requestMeta)
            return ""
        }
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.lastSendError = "empty http response"
                this.logChannel("warn", MetisLogEvent.messageSendFailed, "send", "failed", "QQ official send returned empty response", errorKind: "transport", error: this.lastSendError, extra: requestMeta)
                return ""
        }
        let responseMeta = JsonObject()
        responseMeta.put("responseBytes", responseRaw.size.toJsonValue())
        responseMeta.put("isGroup", isGroup.toJsonValue())
        this.logChannel("debug", MetisLogEvent.channelSend, "send", "response", "QQ official send response received", extra: responseMeta)
        this.parseOfficialSendMessageId(responseRaw)
    }

    private func parseOnebotApiSuccess(raw: String): Bool {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let status = this.readStringField(jo, "status")
            let retcode = this.readIntField(jo, "retcode")
            if (status == "ok" && retcode == 0) {
                this.lastSendError = ""
                true
            } else {
                let msg = this.readStringField(jo, "msg")
                this.lastSendError = "status=${status}, retcode=${retcode}, msg=${msg}"
                false
            }
        } catch (e: Exception) {
            this.lastSendError = "parse onebot response failed: ${e.message}"
            false
        }
    }

    private func parsePeerId(peerId: String): (Bool, String) {
        if (peerId.startsWith("group:")) {
            return (true, peerId["group:".size..])
        }
        if (peerId.startsWith("user:")) {
            return (false, peerId["user:".size..])
        }
        // 兼容早期格式：无前缀时默认按私聊处理。
        return (false, peerId)
    }

    private func isOfficialWsMode(): Bool {
        return this.config.mode.toAsciiLower() == "official_ws"
    }

    private func getOfficialAccessToken(): String {
        let nowNano = DateTime.now().toUnixTimeStamp().toNanoseconds()
        if (!this.officialAccessToken.isEmpty() && nowNano < this.officialTokenExpireAtNano - 60 * 1000000000) {
            return this.officialAccessToken
        }

        let header = HashMap<String, String>()
        header["Content-Type"] = "application/json; charset=utf-8"
        let body = HashMap<String, JsonValue>()
        body["appId"] = JsonString(this.config.appId)
        body["clientSecret"] = JsonString(this.config.appSecret)

        let responseOpt = HttpUtils.post(this.config.officialTokenUrl, header, JsonObject(body))
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.lastSendError = "official token api no response"
                this.logChannel("warn", MetisLogEvent.channelFailed, "official_ws", "failed", "QQ official token API returned no response", errorKind: "transport", error: this.lastSendError)
                return ""
        }
        return try {
            let jo = JsonValue.fromStr(responseRaw).asObject()
            let token = this.readStringField(jo, "access_token")
            let expiresIn = this.readIntField(jo, "expires_in")
            if (token.isEmpty()) {
                this.lastSendError = "official token api missing access_token"
                this.logChannel("warn", MetisLogEvent.channelFailed, "official_ws", "failed", "QQ official token API missing access_token", errorKind: "credential", error: this.lastSendError)
                return ""
            }
            this.officialAccessToken = token
            let ttl = if (expiresIn > 0) { expiresIn } else { 7200 }
            this.officialTokenExpireAtNano = nowNano + ttl * 1000000000
            this.lastSendError = ""
            let extra = JsonObject()
            extra.put("ttlSeconds", ttl.toJsonValue())
            this.logChannel("info", MetisLogEvent.channelStarted, "official_ws", "token_acquired", "QQ official token acquired", extra: extra)
            token
        } catch (e: Exception) {
            this.lastSendError = "official token parse failed: ${e.message}"
            this.logChannel("warn", MetisLogEvent.channelFailed, "official_ws", "failed", "QQ official token parse failed", errorKind: "parse", error: this.lastSendError)
            ""
        }
    }

    private func parseOfficialSendSuccess(raw: String): Bool {
        // 官方接口返回体常见为 {"id":"..."} 或标准错误结构；这里做宽松成功判定。
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let id = this.readStringField(jo, "id")
            if (!id.isEmpty()) {
                this.lastSendError = ""
                true
            } else {
                let code = this.readIntField(jo, "code")
                let msg = this.readStringField(jo, "message")
                let detail = this.readStringField(jo, "msg")
                this.lastSendError = "official send failed: code=${code}, message=${msg}, msg=${detail}"
                false
            }
        } catch (e: Exception) {
            this.lastSendError = "official send parse failed: ${e.message}, bodyLen=${raw.size}, bodyHash=${gatewayLogIdentityHash(raw)}"
            false
        }
    }

    private func parseOfficialSendMessageId(raw: String): String {
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let id = this.readStringField(jo, "id").trimAscii()
            if (!id.isEmpty()) {
                this.lastSendError = ""
                return id
            }
            let code = this.readIntField(jo, "code")
            let msg = this.readStringField(jo, "message")
            let detail = this.readStringField(jo, "msg")
            this.lastSendError = "official send failed: code=${code}, message=${msg}, msg=${detail}"
            ""
        } catch (e: Exception) {
            this.lastSendError = "official send parse failed: ${e.message}, bodyLen=${raw.size}, bodyHash=${gatewayLogIdentityHash(raw)}"
            ""
        }
    }

    private func resolveSendApiPath(isGroup: Bool): String {
        if (this.config.sendApiMode == "unified") {
            return "/send_msg"
        }
        return if (isGroup) { "/send_group_msg" } else { "/send_private_msg" }
    }

    private func isDuplicateMessage(messageId: String): Bool {
        if (messageId.isEmpty()) {
            return false
        }
        return this.recentMessageIds.contains(messageId)
    }

    private func markMessageProcessed(messageId: String): Unit {
        if (messageId.isEmpty()) {
            return
        }
        this.recentMessageIds.add(messageId)
        if (this.recentMessageIds.size > this.config.dedupWindowSize) {
            let all = this.recentMessageIds.toArray()
            let start = all.size - this.config.dedupWindowSize
            this.recentMessageIds.clear()
            this.recentMessageIds.add(all: all[start..])
        }
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

    private func readIntField(obj: JsonObject, key: String): Int64 {
        return match (obj.get(key)) {
            case Some(v) => match (v) {
                case i: JsonInt => i.getValue()
                case f: JsonFloat => Int64(f.getValue())
                case s: JsonString => try { Int64.parse(s.getValue()) } catch (_e: Exception) { 0 }
                case _ => 0
            }
            case None => 0
        }
    }

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
     * 官方网关 WS 循环（P2 基础版）：
     * - 自动重连
     * - 处理 Dispatch(0) 事件并入队
     * - 处理 Hello(10) 并定期发送 Heartbeat(1)
     */
    private func startOfficialGatewayLoop(): Unit {
        spawn {
            while (this.running) {
                try {
                    this.logChannel("debug", MetisLogEvent.channelPull, "official_ws", "connecting", "QQ official websocket connecting")
                    this.connectOfficialGatewayAndServe()
                } catch (e: Exception) {
                    this.lastSendError = "official ws loop error: ${e.message}"
                    this.logChannel("warn", MetisLogEvent.channelFailed, "official_ws", "failed", "QQ official websocket loop error", errorKind: this.qqErrorKind(e.message), error: e.message)
                }
                this.logChannel("debug", MetisLogEvent.channelPull, "official_ws", "reconnect_scheduled", "QQ official websocket reconnect scheduled")
                sleep(Duration.second * 3)
            }
        }
    }

    private func connectOfficialGatewayAndServe(): Unit {
        this.officialConnectionSerial += 1
        let connectionSerial = this.officialConnectionSerial
        let gatewayUrl = this.resolveOfficialGatewayWebsocketUrl()
        if (gatewayUrl.isEmpty()) {
            throw Exception("official gateway url is empty")
        }
        let gatewayMeta = JsonObject()
        gatewayMeta.put("urlConfigured", true.toJsonValue())
        this.logChannel("debug", MetisLogEvent.channelPull, "official_ws", "gateway_url_resolved", "QQ official websocket gateway URL resolved", extra: gatewayMeta)

        // wss 连接必须显式配置 TLS，否则会报
        // "TLS must be configured when HTTPS requests are sent."
        var tlsConfig = TlsClientConfig()
        tlsConfig.verifyMode = TrustAll
        tlsConfig.alpnProtocolsList = ["http/1.1"]
        let client = ClientBuilder().tlsConfig(tlsConfig).build()
        let u = URL.parse(gatewayUrl)
        let websocket: WebSocket
        let _respHeaders: HttpHeaders
        (websocket, _respHeaders) = WebSocket.upgradeFromClient(client, u)
        client.close()
        this.logChannel("info", MetisLogEvent.channelStarted, "official_ws", "connected", "QQ official websocket connected")

        var heartbeatIntervalMs: Int64 = 30000
        var heartbeatStarted = false
        var shouldReconnect = false

        while (this.running) {
            let frame = websocket.read()
            if (frame.frameType == CloseWebFrame) {
                let closePayload = frame.payload.toString()
                let extra = JsonObject()
                extra.put("payloadBytes", closePayload.size.toJsonValue())
                this.logChannel("info", MetisLogEvent.channelStopped, "official_ws", "closed", "QQ official websocket close frame received", extra: extra)
                shouldReconnect = true
                break
            }
            if (frame.frameType != TextWebFrame) {
                continue
            }
            let payload = String.fromUtf8(frame.payload)
            let jo = try {
                JsonValue.fromStr(payload).asObject()
            } catch (_e: Exception) {
                continue
            }
            let op = this.readIntField(jo, "op")
            if (let Some(sVal) <- jo.get("s")) {
                this.officialSeq = match (sVal) {
                    case i: JsonInt => i.getValue()
                    case f: JsonFloat => Int64(f.getValue())
                    case _ => this.officialSeq
                }
            }

            if (op == 10) { // Hello
                let d = match (jo.get("d")) {
                    case Some(v) => v.asObject()
                    case None => JsonObject(HashMap<String, JsonValue>())
                }
                let interval = this.readIntField(d, "heartbeat_interval")
                if (interval > 0) {
                    heartbeatIntervalMs = interval
                }
                let extra = JsonObject()
                extra.put("heartbeatIntervalMs", heartbeatIntervalMs.toJsonValue())
                this.logChannel("info", MetisLogEvent.channelPull, "heartbeat", "hello", "QQ official websocket hello received", extra: extra)
                this.sendOfficialIdentifyOrResume(websocket)
                if (!heartbeatStarted) {
                    heartbeatStarted = true
                    this.startHeartbeat(websocket, heartbeatIntervalMs, connectionSerial)
                }
                continue
            }
            if (op == 0) { // Dispatch
                // 直接复用官方事件解析路径（t+d）。
                let eventType = this.readStringField(jo, "t")
                let dispatchMeta = JsonObject()
                dispatchMeta.put("eventType", JsonString(eventType))
                this.logChannel("debug", MetisLogEvent.messageInbound, "official_ws", "dispatch", "QQ official websocket dispatch event", extra: dispatchMeta)
                if (eventType == "READY") {
                    let data = match (jo.get("d")) {
                        case Some(v) =>
                            try { v.asObject() } catch (_: Exception) { JsonObject(HashMap<String, JsonValue>()) }
                        case None => JsonObject(HashMap<String, JsonValue>())
                    }
                    let sessionId = this.readStringField(data, "session_id")
                    if (!sessionId.isEmpty()) {
                        this.officialSessionId = sessionId
                        let sessionMeta = JsonObject()
                        sessionMeta.put("sessionHash", JsonString(gatewayLogIdentityHash(sessionId)))
                        this.logChannel("debug", MetisLogEvent.channelPull, "official_ws", "session_saved", "QQ official websocket session saved", extra: sessionMeta)
                    }
                }
                let ack = this.ingestWebhookPayload(payload)
                if (ack.contains("\"ok\":false")) {
                    let ackMeta = JsonObject()
                    ackMeta.put("ackBytes", ack.size.toJsonValue())
                    this.logChannel("debug", MetisLogEvent.messageInbound, "official_ws", "dispatch_ignored", "QQ official websocket dispatch ignored", extra: ackMeta)
                }
                continue
            }
            if (op == 11) { // Heartbeat ACK
                this.logChannel("debug", MetisLogEvent.channelPull, "heartbeat", "ack", "QQ official websocket heartbeat ack")
                continue
            }
            if (op == 9) { // Invalid Session
                this.logChannel("warn", MetisLogEvent.channelFailed, "official_ws", "failed", "QQ official websocket invalid session", errorKind: "session", error: "op=9")
                this.officialSessionId = ""
                this.officialSeq = 0
                shouldReconnect = true
                break
            }
            if (op == 7) { // Reconnect
                this.logChannel("info", MetisLogEvent.channelPull, "official_ws", "reconnect_requested", "QQ official websocket server requested reconnect")
                shouldReconnect = true
                break
            }
            let opMeta = JsonObject()
            opMeta.put("op", op.toJsonValue())
            this.logChannel("debug", MetisLogEvent.channelPull, "official_ws", "received", "QQ official websocket op received", extra: opMeta)
        }
        try {
            websocket.closeConn()
        } catch (_e: Exception) {
            ()
        }
        if (shouldReconnect) {
            throw Exception("qq official websocket reconnect requested")
        }
    }

    private func resolveOfficialGatewayWebsocketUrl(): String {
        if (this.config.officialWebsocketUrl.startsWith("ws://") || this.config.officialWebsocketUrl.startsWith("wss://")) {
            return this.config.officialWebsocketUrl
        }
        let header = HashMap<String, String>()
        let token = this.getOfficialAccessToken()
        if (token.isEmpty()) {
            return ""
        }
        header["Authorization"] = "${this.config.officialAuthScheme} ${token}"
        if (!this.config.appId.isEmpty()) {
            header["X-Union-Appid"] = this.config.appId
        }

        // 官方 /gateway 使用 GET 返回 { url: "wss://..." }。
        let rawOpt = HttpUtils.get(this.config.officialGatewayUrl, header, None)
        let raw = match (rawOpt) {
            case Some(v) => v
            case None =>
                let fallback = "wss://api.sgroup.qq.com/websocket/"
                this.lastSendError = "official gateway api no response, fallback to ${fallback}"
                this.logError("QQ official_ws: ${this.lastSendError}")
                return fallback
        }
        return try {
            let jo = JsonValue.fromStr(raw).asObject()
            let wsUrl = this.readStringField(jo, "url")
            if (wsUrl.isEmpty()) {
                let fallback = "wss://api.sgroup.qq.com/websocket/"
                this.lastSendError = "gateway response missing url, fallback to ${fallback}"
                this.logError("QQ official_ws: ${this.lastSendError}")
                return fallback
            }
            wsUrl
        } catch (e: Exception) {
            let fallback = "wss://api.sgroup.qq.com/websocket/"
            this.lastSendError = "official gateway parse failed: ${e.message}, fallback to ${fallback}"
            this.logError("QQ official_ws: ${this.lastSendError}")
            fallback
        }
    }

    private func sendOfficialIdentify(websocket: WebSocket): Unit {
        let accessToken = this.getOfficialAccessToken()
        if (accessToken.isEmpty()) {
            this.logError("QQ official_ws: IDENTIFY skipped, token is empty")
            return
        }
        let root = HashMap<String, JsonValue>()
        root["op"] = JsonInt(2)

        let d = HashMap<String, JsonValue>()
        // Access Token 鉴权格式：<scheme> <access_token>
        // 默认 scheme 为 QQBot（可通过 QQ_OFFICIAL_AUTH_SCHEME 覆盖）。
        d["token"] = JsonString("${this.config.officialAuthScheme} ${accessToken}")
        d["intents"] = JsonInt(this.config.officialIntents)
        d["shard"] = JsonArray(ArrayList<JsonValue>([JsonInt(0), JsonInt(1)]))

        let props = HashMap<String, JsonValue>()
        props["$os"] = JsonString("windows")
        props["$sdk"] = JsonString("magic-cli")
        props["$device"] = JsonString("magic-cli")
        d["properties"] = JsonObject(props)

        root["d"] = JsonObject(d)
        let payload = JsonObject(root).toJsonString()
        let identifyMeta = JsonObject()
        identifyMeta.put("scheme", JsonString(this.config.officialAuthScheme))
        identifyMeta.put("intents", JsonInt(this.config.officialIntents))
        this.logChannel(
            "debug",
            MetisLogEvent.channelSend,
            "official_ws",
            "identify",
            "QQ official websocket sending IDENTIFY",
            extra: identifyMeta
        )
        websocket.write(TextWebFrame, payload.toArray())
    }

    private func sendOfficialResume(websocket: WebSocket): Unit {
        let accessToken = this.getOfficialAccessToken()
        if (accessToken.isEmpty()) {
            this.logError("QQ official_ws: RESUME skipped, token is empty")
            return
        }
        if (this.officialSessionId.isEmpty()) {
            this.sendOfficialIdentify(websocket)
            return
        }
        let root = HashMap<String, JsonValue>()
        root["op"] = JsonInt(6)

        let d = HashMap<String, JsonValue>()
        d["token"] = JsonString("${this.config.officialAuthScheme} ${accessToken}")
        d["session_id"] = JsonString(this.officialSessionId)
        d["seq"] = JsonInt(this.officialSeq)
        root["d"] = JsonObject(d)

        let payload = JsonObject(root).toJsonString()
        let resumeMeta = JsonObject()
        resumeMeta.put("sessionHash", JsonString(gatewayLogIdentityHash(this.officialSessionId)))
        resumeMeta.put("seq", JsonInt(this.officialSeq))
        this.logChannel(
            "debug",
            MetisLogEvent.channelSend,
            "official_ws",
            "resume",
            "QQ official websocket sending RESUME",
            extra: resumeMeta
        )
        websocket.write(TextWebFrame, payload.toArray())
    }

    private func sendOfficialIdentifyOrResume(websocket: WebSocket): Unit {
        if (!this.officialSessionId.isEmpty() && this.officialSeq > 0) {
            this.sendOfficialResume(websocket)
            return
        }
        this.sendOfficialIdentify(websocket)
    }

    private func startHeartbeat(websocket: WebSocket, intervalMs: Int64, connectionSerial: Int64): Unit {
        spawn {
            while (this.running && this.officialConnectionSerial == connectionSerial) {
                let hb = HashMap<String, JsonValue>()
                hb["op"] = JsonInt(1)
                hb["d"] = JsonInt(this.officialSeq)
                let payload = JsonObject(hb).toJsonString()
                try {
                    websocket.write(TextWebFrame, payload.toArray())
                } catch (_e: Exception) {
                    this.logError("QQ official_ws: heartbeat failed, stop heartbeat loop")
                    break
                }
                sleep(Duration.millisecond * intervalMs)
            }
        }
    }
}
