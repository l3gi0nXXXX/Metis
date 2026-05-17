package metis.gateway.channels.qq

import metis.gateway.core.ChannelAdapter
import metis.gateway.model.*
import metis.gateway.model.QQConfig
import metis.io.PrintUtils

import magic.log.LogUtils
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

    private func logInfo(message: String): Unit {
        PrintUtils.printLine(message)
        LogUtils.info(message)
    }

    private func logError(message: String): Unit {
        PrintUtils.printLine(message)
        LogUtils.error(message)
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
            this.logError("QQ adapter start failed: ${this.lastSendError}")
            return
        }
        if (this.resolvedAccount.missingAccount) {
            this.lastSendError = this.resolvedAccount.missingDiagnostic
            this.logError("QQ adapter start failed: ${this.lastSendError}")
            return
        }
        if (this.config.appId.isEmpty() || this.config.appSecret.isEmpty()) {
            this.lastSendError = "QQ official mode requires appId and appSecret for account ${this.config.accountId}"
            this.logError("QQ adapter start failed: ${this.lastSendError}")
            return
        }
        this.running = true
        this.logInfo("QQ adapter started in official_ws mode")
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
            return SendResult.Failed("qq adapter is not running")
        }
        LogUtils.info("QQ send: peer=${message.peerId}, textLen=${message.text.size}")
        let sentMessageId = this.sendTextToQQWithMessageId(message.peerId, message.text, message.replyToMessageId)
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
        }
        if (!sentMessageId.trimAscii().isEmpty()) {
            LogUtils.info("QQ send: success peer=${message.peerId}")
            return SendResult.Success
        }
        this.logError("QQ send: failed, reason=${this.lastSendError}")
        return SendResult.Failed("failed to send qq message: ${this.lastSendError}")
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        if (!this.running) {
            return ""
        }
        let sentMessageId = this.sendTextToQQWithMessageId(message.peerId, message.text, message.replyToMessageId)
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
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
            let preview = if (payload.size > 200) { payload[..200] + "..." } else { payload }
            PrintUtils.printLine("QQ webhook: received payload len=${payload.size}, preview=${preview}")
            if (!this.validateWebhookHeaders(ctx.request.headers)) {
                PrintUtils.printLine("QQ webhook: header validation failed")
                ctx.responseBuilder.body("{\"ok\":false,\"error\":\"unauthorized\"}")
                return
            }
            let ack = this.ingestWebhookPayload(payload)
            PrintUtils.printLine("QQ webhook: ack=${ack}")
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
            PrintUtils.printLine("QQ ingest: invalid json")
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
            PrintUtils.printLine("QQ ingest: received callback verification op=13, plain_token present=${!plainToken.isEmpty()}, event_ts=${eventTs}")
            PrintUtils.printLine("QQ ingest warning: Ed25519 signature for op=13 is not implemented yet, webhook verification may fail on platform side.")
            return "{\"plain_token\":\"${plainToken}\",\"signature\":\"\"}"
        }

        // 官方 WS 控制事件（例如 READY/RESUMED）不是业务消息，直接忽略并返回 ok。
        if (op == 0) {
            let eventType = this.readStringField(root, "t")
            if (this.isIgnoredOfficialControlEvent(eventType)) {
                PrintUtils.printLine("QQ ingest: ignore control event ${eventType}")
                return "{\"ok\":true,\"ignored\":true,\"event\":\"${eventType}\"}"
            }
        }

        if (let Some(inbound) <- this.mapWebhookToInbound(root)) {
            let dedupKey = this.buildDedupKey(root, inbound)
            LogUtils.info("QQ ingest: mapped messageId=${inbound.messageId}, peer=${inbound.peerId}, sender=${inbound.senderId}, mentioned=${inbound.mentioned}")
            synchronized(this.queueMutex) {
                if (this.isDuplicateMessage(dedupKey)) {
                    LogUtils.info("QQ ingest: dedup hit for key=${dedupKey}")
                    return "{\"ok\":true,\"dedup\":true}"
                }
                this.inboundQueue.add(inbound)
                this.markMessageProcessed(dedupKey)
                LogUtils.info("QQ ingest: queued messageId=${inbound.messageId}, queueSize=${this.inboundQueue.size}")
            }
            return "{\"ok\":true}"
        }
        let eventType = this.readStringField(root, "t")
        if (op == 0 && !eventType.isEmpty()) {
            if (this.isSupportedOfficialInboundEvent(eventType)) {
                this.logError("QQ ingest: supported event payload missing required fields, t=${eventType}")
                return "{\"ok\":false,\"error\":\"invalid_event_payload\",\"event\":\"${eventType}\"}"
            }
            LogUtils.info("QQ ingest: ignored unsupported official event ${eventType}")
            return "{\"ok\":true,\"ignored\":true,\"reason\":\"unsupported_event\",\"event\":\"${eventType}\"}"
        }
        PrintUtils.printLine("QQ ingest: unsupported event, op=${op}, t=${eventType}")
        return "{\"ok\":true,\"ignored\":true,\"reason\":\"unsupported_op\",\"event\":\"${eventType}\"}"
    }

    private func mapWebhookToInbound(root: JsonObject): Option<InboundMessage> {
        return this.mapOfficialWebhookToInbound(root)
    }

    private func mapOnebotWebhookToInbound(root: JsonObject): Option<InboundMessage> {
        let postType = this.readStringField(root, "post_type")
        if (postType != "message") {
            PrintUtils.printLine("QQ map(onebot): skip post_type=${postType}")
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
            PrintUtils.printLine("QQ map(onebot): skip message_type=${messageType}")
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
        PrintUtils.printLine("QQ map(official): eventType=${eventType}")
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
        PrintUtils.printLine("QQ send(onebot): url=${url}, apiPath=${apiPath}")

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
                PrintUtils.printLine("QQ send(onebot): empty http response")
                return false
        }
        let preview = if (responseRaw.size > 300) { responseRaw[..300] + "..." } else { responseRaw }
        PrintUtils.printLine("QQ send(onebot): response=${preview}")
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
        LogUtils.info("QQ send(official): url=${url}, isGroup=${isGroup}, replyTo=${replyTarget}")

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
            this.logError("QQ send(official): ${this.lastSendError}")
            return ""
        } catch (e: Exception) {
            this.lastSendError = "official send exception: ${e.message}"
            this.logError("QQ send(official): ${this.lastSendError}")
            return ""
        }
        let responseRaw = match (responseOpt) {
            case Some(resp) => resp
            case None =>
                this.lastSendError = "empty http response"
                this.logError("QQ send(official): empty http response")
                return ""
        }
        let preview = if (responseRaw.size > 300) { responseRaw[..300] + "..." } else { responseRaw }
        LogUtils.info("QQ send(official): response=${preview}")
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
                this.logError("QQ official_ws: ${this.lastSendError}")
                return ""
        }
        return try {
            let jo = JsonValue.fromStr(responseRaw).asObject()
            let token = this.readStringField(jo, "access_token")
            let expiresIn = this.readIntField(jo, "expires_in")
            if (token.isEmpty()) {
                this.lastSendError = "official token api missing access_token"
                this.logError("QQ official_ws: ${this.lastSendError}")
                return ""
            }
            this.officialAccessToken = token
            let ttl = if (expiresIn > 0) { expiresIn } else { 7200 }
            this.officialTokenExpireAtNano = nowNano + ttl * 1000000000
            this.lastSendError = ""
            LogUtils.info("QQ official_ws: token acquired, ttl=${ttl}s")
            token
        } catch (e: Exception) {
            this.lastSendError = "official token parse failed: ${e.message}"
            this.logError("QQ official_ws: ${this.lastSendError}")
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
            let preview = if (raw.size > 200) { raw[..200] + "..." } else { raw }
            this.lastSendError = "official send parse failed: ${e.message}, raw=${preview}"
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
            let preview = if (raw.size > 200) { raw[..200] + "..." } else { raw }
            this.lastSendError = "official send parse failed: ${e.message}, raw=${preview}"
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
                    this.logInfo("QQ official_ws: connecting gateway...")
                    this.connectOfficialGatewayAndServe()
                } catch (e: Exception) {
                    this.lastSendError = "official ws loop error: ${e.message}"
                    this.logError("QQ official_ws loop error: ${e.message}")
                }
                this.logInfo("QQ official_ws: reconnect in 3s")
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
        this.logInfo("QQ official_ws: using gateway url ${gatewayUrl}")

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
        this.logInfo("QQ official_ws: websocket connected")

        var heartbeatIntervalMs: Int64 = 30000
        var heartbeatStarted = false
        var shouldReconnect = false

        while (this.running) {
            let frame = websocket.read()
            if (frame.frameType == CloseWebFrame) {
                let closePayload = frame.payload.toString()
                this.logInfo("QQ official_ws: received CLOSE frame, payload=${closePayload}")
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
                this.logInfo("QQ official_ws: received HELLO, heartbeat_interval=${heartbeatIntervalMs}ms")
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
                LogUtils.info("QQ official_ws: dispatch event ${eventType}")
                if (eventType == "READY") {
                    let data = match (jo.get("d")) {
                        case Some(v) =>
                            try { v.asObject() } catch (_: Exception) { JsonObject(HashMap<String, JsonValue>()) }
                        case None => JsonObject(HashMap<String, JsonValue>())
                    }
                    let sessionId = this.readStringField(data, "session_id")
                    if (!sessionId.isEmpty()) {
                        this.officialSessionId = sessionId
                        LogUtils.info("QQ official_ws: saved session_id=${sessionId}")
                    }
                }
                let ack = this.ingestWebhookPayload(payload)
                if (ack.contains("\"ok\":false")) {
                    LogUtils.info("QQ official_ws: dispatch ignored ${ack}")
                }
                continue
            }
            if (op == 11) { // Heartbeat ACK
                LogUtils.info("QQ official_ws: heartbeat ack")
                continue
            }
            if (op == 9) { // Invalid Session
                this.logError("QQ official_ws: invalid session (op=9)")
                this.officialSessionId = ""
                this.officialSeq = 0
                shouldReconnect = true
                break
            }
            if (op == 7) { // Reconnect
                this.logInfo("QQ official_ws: server requested reconnect (op=7)")
                shouldReconnect = true
                break
            }
            LogUtils.info("QQ official_ws: received op=${op}")
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
        LogUtils.info("QQ official_ws: sending IDENTIFY, token_source=app_access_token, scheme=${this.config.officialAuthScheme}, intents=${this.config.officialIntents}")
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
        LogUtils.info("QQ official_ws: sending RESUME, session_id=${this.officialSessionId}, seq=${this.officialSeq}")
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
