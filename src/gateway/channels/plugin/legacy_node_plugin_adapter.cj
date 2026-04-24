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
 * Legacy channel plugin compatibility host skeleton.
 *
 * This adapter does not yet execute the full legacy TypeScript plugin ABI, but
 * it establishes the manifest/runtime contract needed for a Node-based host:
 *
 * - start: `command entry start ...`
 * - pull:  `command entry pull  ...`
 * - send:  `command entry send  ...`
 * - stop:  `command entry stop  ...`
 *
 * The important difference from `CommandPluginAdapter` is semantic: this adapter
 * is explicitly reserved for legacy-style plugin manifests so later work can
 * swap the command invocation for a real compatibility host without changing the
 * gateway-side registry and manager contracts again.
 */
public class LegacyNodePluginAdapter <: ChannelAdapter {
    public prop name: String {
        get() {
            this.channelId
        }
    }

    private let pluginId: String
    private let channelId: String
    private let pluginRoot: Path
    private let command: String
    private let entry: String
    private let manifestPath: String
    private let configJson: String

    public init(
        pluginId: String,
        channelId: String,
        pluginRoot: Path,
        command: String,
        entry: String,
        manifestPath: String,
        configJson: String
    ) {
        this.pluginId = pluginId
        this.channelId = channelId
        this.pluginRoot = pluginRoot
        this.command = command
        this.entry = entry
        this.manifestPath = manifestPath
        this.configJson = configJson
    }

    public func start(): Unit {
        let args = this.baseArgs("start")
        let (ec, _out, err) = ShellUtils.execute(args, withWrap: false, workDir: this.pluginRoot)
        if (ec != 0) {
            LogUtils.error("Legacy plugin host '${this.pluginId}' start failed: ${err}")
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
            LogUtils.error("Legacy plugin host '${this.pluginId}' pull failed: ${err}")
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
            this.entry,
            op,
            "--plugin-id",
            this.pluginId,
            "--channel-id",
            this.channelId,
            "--plugin-root",
            this.pluginRoot.toString(),
            "--manifest-path",
            this.manifestPath,
            "--compat-mode",
            "legacy-node-plugin",
            "--config-json",
            this.configJson
        ]
    }

    private func parseInboundLines(raw: String): Array<InboundMessage> {
        let out = ArrayList<InboundMessage>()
        for (line in raw.split("\n")) {
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
