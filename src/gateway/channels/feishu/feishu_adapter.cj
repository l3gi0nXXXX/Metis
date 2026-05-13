package metis.gateway.channels.feishu

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
import std.fs.{Path, canonicalize, exists}
import std.io.*
import std.process.*
import std.time.DateTime
import std.sync.Mutex
import stdx.encoding.json.*
import stdx.net.http.*

/**
 * Feishu 渠道适配器（P0 基础实现）。
 *
 * 说明：
 * - 当前版本主要用于打通 Gateway 链路，采用“内存队列 + 模拟入站”方式；
 * - 后续你可以将 simulateIncomingText 替换为真实事件来源（WebSocket 或 webhook）；
 * - send() 当前仅记录已发送消息，后续替换为 Feishu API 调用。
 */
public class FeishuAdapter <: ChannelAdapter {
    private var running = false
    private let queueMutex = Mutex()
    private let inboundQueue = ArrayList<InboundMessage>()
    private let outboundLog = ArrayList<OutboundMessage>()
    private let config: FeishuConfig
    private var webhookServer: Option<Server> = None
    private var tenantAccessToken: String = ""
    private var tokenExpireAtNano: Int64 = 0
    private var lastSendError: String = ""
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

    public init(config!: FeishuConfig = FeishuConfig(), accountId!: String = "default") {
        this.config = config
        let trimmedAccountId = accountId.trimAscii()
        this.accountId = if (trimmedAccountId.isEmpty()) { "default" } else { trimmedAccountId }
    }

    public prop name: String {
        get() { "feishu" }
    }

    public func start(): Unit {
        if (this.running) {
            return
        }
        this.running = true
        if (!this.config.enabled) {
            PrintUtils.printLine("Feishu adapter: disabled (gateway.feishu.enabled=false).")
            return
        }
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
        let sentMessageId = this.sendTextToFeishuWithMessageId(
            message.peerId,
            message.text,
            replyToMessageId: message.replyToMessageId,
            replyInThread: message.replyInThread
        )
        synchronized(this.queueMutex) {
            // 无论是否成功都记录，便于排障。
            this.outboundLog.add(message)
        }
        if (!sentMessageId.trimAscii().isEmpty()) {
            return SendResult.Success
        }
        return SendResult.Failed("failed to send message via feishu api: ${this.lastSendError}")
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        if (!this.running) {
            return ""
        }
        let sentMessageId = this.sendTextToFeishuWithMessageId(
            message.peerId,
            message.text,
            replyToMessageId: message.replyToMessageId,
            replyInThread: message.replyInThread
        )
        synchronized(this.queueMutex) {
            this.outboundLog.add(message)
        }
        sentMessageId
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
        if (!headerEventType.isEmpty() && headerEventType != "im.message.receive_v1") {
            PrintUtils.printLine("Feishu ingest: ignore event_type=${headerEventType}")
            return "{\"ok\":true,\"ignored\":true}"
        }

        if (let Some(inbound) <- this.mapWebhookToInbound(root)) {
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
        return "{\"ok\":true,\"ignored\":true}"
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
        let mediaContext = JsonObject()
        let accountId = this.effectiveAccountId()
        this.attachFeishuImRouteContext(mediaContext, accountId, peerId, chatType, senderId, messageId, "", "")
        this.attachFeishuGateContext(mediaContext, chatType, mentioned)
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
            this.messageMentionsBotOpenId(messageObj) ||
            (this.config.botOpenId.isEmpty() && (text.contains("@") || text.contains("<at ")))
        let mediaContext = JsonObject()
        this.attachFeishuImRouteContext(mediaContext, accountId, chatId, chatType, senderId, messageId, rootId, threadId)
        this.attachFeishuGateContext(mediaContext, chatType, mentioned)
        this.attachFeishuAttachmentContext(mediaContext, accountId, chatId, messageId, messageType, contentJsonString)

        return InboundMessage(
            ChannelType.Feishu,
            messageId,
            chatId,
            senderId,
            chatType,
            text,
            mentioned,
            DateTime.now(),
            conversationId: this.resolveConversationId(chatId, chatType, senderId, messageId, rootId, threadId),
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
                } else {
                    route.put("peerKind", JsonString("group"))
                    route.put("peerId", JsonString(chatId.trimAscii()))
                }
        }
        route.put("senderId", JsonString(senderId.trimAscii()))
        route.put("messageId", JsonString(messageId.trimAscii()))
        context.put("imRoute", route)
        mediaContext.put("channel", JsonString("feishu"))
        mediaContext.put("accountId", JsonString(normalizedAccountId))
        mediaContext.put("context", context)
    }

    private func attachFeishuGateContext(mediaContext: JsonObject, chatType: ChatType, mentioned: Bool): Unit {
        let context = match (mediaContext.get("context")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let gate = JsonObject()
        let groupMentionRequired = match (chatType) {
            case ChatType.Direct => false
            case ChatType.Group => this.config.policy.requireMentionInGroup && !mentioned
        }
        gate.put("triggerAgent", JsonBool(!groupMentionRequired))
        gate.put("mentioned", JsonBool(mentioned))
        gate.put("requireMentionInGroup", JsonBool(this.config.policy.requireMentionInGroup))
        gate.put("reason", JsonString(if (groupMentionRequired) { "group_mention_required" } else { "accepted" }))
        context.put("feishuGate", gate)
        mediaContext.put("context", context)
    }

    private func attachFeishuAttachmentContext(
        mediaContext: JsonObject,
        accountId: String,
        chatId: String,
        messageId: String,
        messageType: String,
        contentJsonString: String
    ): Unit {
        let normalizedType = messageType.trimAscii().toAsciiLower()
        if (!(normalizedType == "image" || normalizedType == "file" || normalizedType == "media" || normalizedType == "audio")) {
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
        record.put("originalFileName", JsonString(this.feishuAttachmentFileName(content)))
        record.put("fileName", JsonString(this.feishuAttachmentFileName(content)))
        record.put("mimeType", JsonString(this.feishuAttachmentMimeType(normalizedType, content)))
        record.put("fileSize", JsonInt(this.feishuAttachmentFileSize(content)))
        record.put("downloaded", JsonBool(false))
        record.put("skippedReason", JsonString("metadata_only"))
        record.put("eligibleFor", JsonString(this.feishuAttachmentEligibility(normalizedType)))
        record.put("localPath", JsonString(""))
        record.put("downloadPath", JsonString(""))
        record.put("createdAtMs", JsonInt(DateTime.now().toUnixTimeStamp().toMilliseconds()))
        let records = JsonArray([])
        records.add(record)
        mediaContext.put("records", records)
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
        if (kind == "media") { return "video/*" }
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
        if (kind == "media") { return "video" }
        "document"
    }

    private func readHeaderEventType(root: JsonObject): String {
        match (root.get("header")) {
            case Some(hv) => this.readStringField(hv.asObject(), "event_type")
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
    private func messageMentionsBotOpenId(messageObj: JsonObject): Bool {
        if (this.config.botOpenId.isEmpty()) {
            return false
        }
        return match (messageObj.get("mentions")) {
            case Some(mv) => this.jsonMentionsContainOpenId(mv)
            case None => false
        }
    }

    /** 解析 message.mentions 数组，是否与当前配置的机器人 open_id 匹配。 */
    private func jsonMentionsContainOpenId(mv: JsonValue): Bool {
        let mentionsArr = mv as JsonArray
        if (let Some(arr) <- mentionsArr) {
            for (i in 0..arr.size()) {
                let item = arr[i]
                let mo = item as JsonObject
                if (let Some(o) <- mo) {
                    let id = this.readStringField(o, "id")
                    if (id == this.config.botOpenId) {
                        return true
                    }
                    if (let Some(idObjValue) <- o.get("id")) {
                        let idObj = idObjValue as JsonObject
                        if (let Some(io) <- idObj) {
                            let openId = this.readStringField(io, "open_id")
                            let userId = this.readStringField(io, "user_id")
                            if (openId == this.config.botOpenId || userId == this.config.botOpenId) {
                                return true
                            }
                        }
                    }
                    if (let Some(idObjValue) <- o.get("user_id")) {
                        let idObj = idObjValue as JsonString
                        if (let Some(uid) <- idObj) {
                            if (uid.getValue() == this.config.botOpenId) {
                                return true
                            }
                        }
                    }
                    let key = this.readStringField(o, "key")
                    if (!key.isEmpty() && key.contains(this.config.botOpenId)) {
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
                } else if (this.config.replyInThread == "enabled" && !normalizedMessageId.isEmpty()) {
                    normalizedMessageId
                } else {
                    ""
                }
                let scope = this.config.groupSessionScope.trimAscii().toAsciiLower()
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
                if (!topicId.isEmpty() && this.config.groupSessionScope.trimAscii().toAsciiLower() == "group_topic") {
                    return Some(this.buildTopicConversationId(normalizedChatId, topicId))
                }
                if (normalizedChatId.isEmpty()) { None } else { Some(normalizedChatId) }
        }
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
                        if (let Some(inbound) <- this.mapWebhookToInbound(v.asObject())) {
                            synchronized(this.queueMutex) {
                                this.inboundQueue.add(inbound)
                            }
                        }
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
        let result = this.sendTextToFeishuDetailed(
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
        let result = this.sendTextToFeishuDetailed(
            chatId,
            text,
            replyToMessageId: replyToMessageId,
            replyInThread: replyInThread
        )
        result[1]
    }

    private func sendTextToFeishuDetailed(
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
        let token = this.getTenantAccessToken()
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
                this.sendCreateMessageRequest(chatId, receiveId, contentJson, header)
            } else {
                this.sendReplyMessageRequest(normalizedReplyId, contentJson, header, replyInThread: replyInThread)
            }
        } else {
            this.sendCreateMessageRequest(chatId, receiveId, contentJson, header)
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
        let fallbackResponseOpt = this.sendCreateMessageRequest(chatId, receiveId, contentJson, header)
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
        rawPeerId: String,
        receiveId: String,
        contentJson: String,
        header: HashMap<String, String>
    ): Option<String> {
        let base = this.normalizeFeishuDomain()
        let receiveIdType = this.resolveReceiveIdType(rawPeerId)
        let url = "${base}/open-apis/im/v1/messages?receive_id_type=${receiveIdType}"
        let body = HashMap<String, JsonValue>()
        body["receive_id"] = JsonString(receiveId)
        body["msg_type"] = JsonString("text")
        body["content"] = JsonString(contentJson)
        HttpUtils.post(url, header, JsonObject(body))
    }

    private func sendReplyMessageRequest(
        replyToMessageId: String,
        contentJson: String,
        header: HashMap<String, String>,
        replyInThread!: Bool = false
    ): Option<String> {
        let base = this.normalizeFeishuDomain()
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
        let nowNano = DateTime.now().toUnixTimeStamp().toNanoseconds()
        if (!this.tenantAccessToken.isEmpty() && nowNano < this.tokenExpireAtNano - 60 * 1000000000) {
            return this.tenantAccessToken
        }
        if (this.config.appId.isEmpty() || this.config.appSecret.isEmpty()) {
            return ""
        }

        let base = this.normalizeFeishuDomain()
        let url = "${base}/open-apis/auth/v3/tenant_access_token/internal"
        let header = HashMap<String, String>([
            ("Content-Type", "application/json; charset=utf-8")
        ])
        let body = HashMap<String, JsonValue>()
        body["app_id"] = JsonString(this.config.appId)
        body["app_secret"] = JsonString(this.config.appSecret)

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
                this.tenantAccessToken = token
                let ttlSeconds = if (expire > 0) { expire } else { 7200 }
                this.tokenExpireAtNano = nowNano + ttlSeconds * 1000000000
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
        var d = this.config.domain.trimAscii()
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
