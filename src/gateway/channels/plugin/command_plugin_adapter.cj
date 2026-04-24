package metis.gateway.channels.plugin

import metis.gateway.core.ChannelAdapter
import metis.gateway.model.{InboundMessage, OutboundMessage, SendResult, ChatType, ChannelType}
import metis.utils.ShellUtils

import magic.log.LogUtils

import std.collection.ArrayList
import std.fs.Path
import std.time.DateTime

import stdx.encoding.json.{JsonObject, JsonValue}

/**
 * 外部命令插件适配器：
 * - 启动:  <command> <script> start ...
 * - 拉取:  <command> <script> pull  ...（stdout 按行输出 JSON 对象）
 * - 发送:  <command> <script> send  ...
 * - 停止:  <command> <script> stop  ...
 */
public class CommandPluginAdapter <: ChannelAdapter {
    public prop name: String {
        get() {
            this.channelId
        }
    }

    private let pluginId: String
    private let channelId: String
    private let pluginRoot: Path
    private let command: String
    private let script: String
    private let configJson: String

    public init(
        pluginId: String,
        channelId: String,
        pluginRoot: Path,
        command: String,
        script: String,
        configJson: String
    ) {
        this.pluginId = pluginId
        this.channelId = channelId
        this.pluginRoot = pluginRoot
        this.command = command
        this.script = script
        this.configJson = configJson
    }

    public func start(): Unit {
        let args = this.baseArgs("start")
        let (ec, _out, err) = ShellUtils.execute(args, withWrap: false, workDir: this.pluginRoot)
        if (ec != 0) {
            LogUtils.error("Gateway plugin '${this.pluginId}' start failed: ${err}")
        }
    }

    public func stop(): Unit {
        let args = this.baseArgs("stop")
        let (_ec, _out, _err) = ShellUtils.execute(args, withWrap: false, workDir: this.pluginRoot)
    }

    public func pullInbound(): Array<InboundMessage> {
        let args = this.baseArgs("pull")
        let (ec, out, err) = ShellUtils.execute(args, withWrap: false, workDir: this.pluginRoot)
        if (ec != 0) {
            LogUtils.error("Gateway plugin '${this.pluginId}' pull failed: ${err}")
            return []
        }
        return this.parseInboundLines(out)
    }

    public func send(message: OutboundMessage): SendResult {
        let argsList = ArrayList<String>()
        argsList.add(all: this.baseArgs("send"))
        argsList.add(all: [
            "--peer-id",
            message.peerId,
            "--text",
            message.text,
            "--reply-to",
            message.replyToMessageId ?? ""
        ])
        let args = argsList.toArray()
        let (ec, _out, err) = ShellUtils.execute(args, withWrap: false, workDir: this.pluginRoot)
        if (ec == 0) {
            return SendResult.Success
        }
        SendResult.Failed(err)
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        match (this.send(message)) {
            case SendResult.Success => ""
            case SendResult.Failed(_reason) => ""
        }
    }

    private func baseArgs(op: String): Array<String> {
        [
            this.command,
            this.script,
            op,
            "--plugin-id",
            this.pluginId,
            "--channel-id",
            this.channelId,
            "--plugin-root",
            this.pluginRoot.toString(),
            "--config-json",
            this.configJson
        ]
    }

    private func parseInboundLines(raw: String): Array<InboundMessage> {
        let out = ArrayList<InboundMessage>()
        for (line in raw.split("\n")) {
            // Windows 上子进程 stdout 常为 CRLF；残留 \r 会导致 JSON 解析失败且此处静默跳过，表现为「inbox 有写入但网关无 inbound」
            let t = line.trimAscii().replace("\r", "").trimAscii()
            if (t.isEmpty()) {
                continue
            }
            try {
                let o = JsonValue.fromStr(t).asObject()
                let messageId = this.readStringField(o, "messageId")
                let peerId = this.readStringField(o, "peerId")
                let senderId = this.readStringField(o, "senderId")
                let text = this.readStringField(o, "text")
                let accountId = this.readStringField(o, "accountId")
                if (peerId.isEmpty() || senderId.isEmpty() || text.isEmpty()) {
                    continue
                }
                let conversationId = this.readStringField(o, "conversationId")
                let threadId = this.readStringField(o, "threadId")
                let replyTargetMessageId = this.readStringField(o, "replyTargetMessageId")
                let replyToMessageId = this.readStringField(o, "replyToMessageId")
                let chatTypeRaw = this.readStringField(o, "chatType").toAsciiLower()
                let chatType = if (chatTypeRaw == "group") { ChatType.Group } else { ChatType.Direct }
                let mentioned = this.readBoolField(o, "mentioned")
                let normalizedMessageId = if (messageId.isEmpty()) { "plugin-${this.pluginId}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}" } else { messageId }
                let effectiveConversationId = if (!conversationId.isEmpty()) { conversationId } else { peerId }
                let effectiveReplyTarget = if (!replyTargetMessageId.isEmpty()) {
                    replyTargetMessageId
                } else if (!replyToMessageId.isEmpty()) {
                    replyToMessageId
                } else {
                    normalizedMessageId
                }
                out.add(
                    InboundMessage(
                        ChannelType.Extension(this.channelId),
                        normalizedMessageId,
                        peerId,
                        senderId,
                        chatType,
                        text,
                        mentioned,
                        DateTime.now(),
                        conversationId: if (effectiveConversationId.isEmpty()) { None<String> } else { Some(effectiveConversationId) },
                        threadId: if (threadId.isEmpty()) { None<String> } else { Some(threadId) },
                        replyTargetMessageId: if (effectiveReplyTarget.isEmpty()) { None<String> } else { Some(effectiveReplyTarget) },
                        replyInThread: this.readBoolField(o, "replyInThread"),
                        raw: Some(t),
                        accountId: accountId
                    )
                )
            } catch (_e: Exception) {
                ()
            }
        }
        out.toArray()
    }

    private func readStringField(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    v.asString().getValue().trimAscii()
                } catch (_e: Exception) {
                    ""
                }
            case None => ""
        }
    }

    private func readBoolField(obj: JsonObject, key: String): Bool {
        match (obj.get(key)) {
            case Some(v) =>
                try {
                    v.asBool().getValue()
                } catch (_e: Exception) {
                    false
                }
            case None => false
        }
    }
}
