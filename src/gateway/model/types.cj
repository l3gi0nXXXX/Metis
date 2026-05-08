package metis.gateway.model

import std.time.DateTime
import stdx.encoding.json.JsonObject

/**
 * 网关层统一的渠道类型。
 * P0 只实现 Feishu，QQ 预留在枚举中，便于后续扩展。
 */
public enum ChannelType {
    | Feishu
    | QQ
    | Telegram
    /**
     * 通过 `GatewayChannelPlugin` 接入的扩展渠道（如钉钉、微信等），`id` 与适配器 `name`、路由策略 key 一致。
     */
    | Extension(String)
}

/**
 * 会话维度：私聊 or 群聊。
 * 用于路由策略和会话 key 生成。
 */
public enum ChatType {
    | Direct
    | Group
}

/**
 * 统一的入站消息模型。
 * 渠道 SDK/HTTP/WebSocket 收到消息后，先转为该结构，核心路由逻辑不感知平台差异。
 */
public class InboundMessage {
    public let channel: ChannelType
    public let accountId: String
    public let messageId: String
    public let peerId: String
    public let senderId: String
    public let chatType: ChatType
    public let text: String
    public let mentioned: Bool
    public let timestamp: DateTime
    public let conversationId: Option<String>
    public let threadId: Option<String>
    public let replyTargetMessageId: Option<String>
    public let replyInThread: Bool
    public let raw: Option<String>
    public let mediaContext: JsonObject

    public init(
        channel: ChannelType,
        messageId: String,
        peerId: String,
        senderId: String,
        chatType: ChatType,
        text: String,
        mentioned: Bool,
        timestamp: DateTime,
        conversationId!: Option<String> = None,
        threadId!: Option<String> = None,
        replyTargetMessageId!: Option<String> = None,
        replyInThread!: Bool = false,
        raw!: Option<String> = None,
        accountId!: String = "",
        mediaContext!: JsonObject = JsonObject()
    ) {
        this.channel = channel
        this.accountId = accountId.trimAscii()
        this.messageId = messageId
        this.peerId = peerId
        this.senderId = senderId
        this.chatType = chatType
        this.text = text
        this.mentioned = mentioned
        this.timestamp = timestamp
        this.conversationId = conversationId
        this.threadId = threadId
        this.replyTargetMessageId = replyTargetMessageId
        this.replyInThread = replyInThread
        this.raw = raw
        this.mediaContext = mediaContext
    }
}

/**
 * 统一的出站消息模型。
 * 网关将 Agent 文本回复封装为该结构，再由具体渠道适配器发送出去。
 */
public class OutboundMessage {
    public let channel: ChannelType
    public let accountId: String
    public let peerId: String
    public let replyToMessageId: Option<String>
    public let quoteText: String
    public let replyInThread: Bool
    public let text: String

    public init(
        channel: ChannelType,
        peerId: String,
        text: String,
        replyToMessageId!: Option<String> = None,
        quoteText!: String = "",
        replyInThread!: Bool = false,
        accountId!: String = ""
    ) {
        this.channel = channel
        this.accountId = accountId.trimAscii()
        this.peerId = peerId
        this.replyToMessageId = replyToMessageId
        this.quoteText = quoteText.trimAscii()
        this.replyInThread = replyInThread
        this.text = text
    }
}

/**
 * 发送结果，P0 仅区分成功与失败。
 */
public enum SendResult {
    | Success
    | Failed(String)
}

/**
 * 路由决策。
 * accepted = true 时，conversationKey 一定有值。
 */
public class RouteDecision {
    public let accepted: Bool
    public let reason: String
    public let conversationKey: Option<String>

    public init(accepted: Bool, reason: String, conversationKey!: Option<String> = None) {
        this.accepted = accepted
        this.reason = reason
        this.conversationKey = conversationKey
    }
}

/**
 * 辅助函数：渠道枚举转字符串。
 * 统一 key 生成和日志输出。
 */
public func channelToString(channel: ChannelType): String {
    return match (channel) {
        case ChannelType.Feishu => "feishu"
        case ChannelType.QQ => "qq"
        case ChannelType.Telegram => "telegram"
        case ChannelType.Extension(id) => id
    }
}

/** 与 `ChannelAdapter.name` 对齐，用于定时任务投递等到指定适配器 */
public func channelTypeFromAdapterName(name: String): ChannelType {
    let n = name.trimAscii().toAsciiLower()
    if (n == "feishu") {
        return ChannelType.Feishu
    }
    if (n == "qq") {
        return ChannelType.QQ
    }
    if (n == "telegram") {
        return ChannelType.Telegram
    }
    ChannelType.Extension(n)
}

/**
 * 辅助函数：会话类型枚举转字符串。
 */
public func chatTypeToString(chatType: ChatType): String {
    return match (chatType) {
        case ChatType.Direct => "direct"
        case ChatType.Group => "group"
    }
}
