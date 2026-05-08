package metis.gateway.openclaw_channel_http

import metis.gateway.core.ChannelAdapter
import metis.gateway.model.{ChatType, ChannelType, InboundMessage, OutboundMessage, SendResult}

import magic.jsonable.*
import std.collection.ArrayList
import std.convert.Parsable
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonFloat, JsonInt, JsonObject, JsonString, JsonValue}

public const OPENCLAW_CHANNEL_HTTP_SCHEMA: String = "openclaw.channel_http.v1"
public const OPENCLAW_CHANNEL_START_METHOD: String = "openclaw.channel.start"
public const OPENCLAW_CHANNEL_STOP_METHOD: String = "openclaw.channel.stop"
public const OPENCLAW_CHANNEL_PULL_INBOUND_METHOD: String = "openclaw.channel.pullInbound"
public const OPENCLAW_CHANNEL_SEND_METHOD: String = "openclaw.channel.send"
public const OPENCLAW_CHANNEL_HEALTH_METHOD: String = "openclaw.channel.health"
public const OPENCLAW_HTTP_DISPATCH_METHOD: String = "openclaw.http.dispatch"

public interface OpenClawBridgeRunner {
    func invoke(method: String, payload: JsonObject): JsonObject
}

public class OpenClawBridgeCallResult {
    public let ok: Bool
    public let status: String
    public let reason: String
    public let diagnostic: JsonObject
    public let raw: JsonObject

    public init(ok: Bool, status: String, reason: String, diagnostic: JsonObject, raw: JsonObject) {
        this.ok = ok
        this.status = status
        this.reason = reason
        this.diagnostic = diagnostic
        this.raw = raw
    }
}

public class OpenClawChannelSendResult {
    public let ok: Bool
    public let status: String
    public let messageId: String
    public let reason: String
    public let diagnostic: JsonObject
    public let raw: JsonObject

    public init(
        ok: Bool,
        status: String,
        messageId: String,
        reason: String,
        diagnostic: JsonObject,
        raw: JsonObject
    ) {
        this.ok = ok
        this.status = status
        this.messageId = messageId
        this.reason = reason
        this.diagnostic = diagnostic
        this.raw = raw
    }
}

public class OpenClawHttpDispatchResult {
    public let ok: Bool
    public let status: String
    public let statusCode: Int64
    public let headers: JsonObject
    public let body: String
    public let diagnostic: JsonObject
    public let diagnosticKind: String
    public let diagnosticMessage: String
    public let raw: JsonObject

    public init(
        ok: Bool,
        status: String,
        statusCode: Int64,
        headers: JsonObject,
        body: String,
        diagnostic: JsonObject,
        diagnosticKind: String,
        diagnosticMessage: String,
        raw: JsonObject
    ) {
        this.ok = ok
        this.status = status
        this.statusCode = statusCode
        this.headers = headers
        this.body = body
        this.diagnostic = diagnostic
        this.diagnosticKind = diagnosticKind
        this.diagnosticMessage = diagnosticMessage
        this.raw = raw
    }
}

private func ocString(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                v.asString().getValue()
            } catch (_e1: Exception) {
                match (v) {
                    case i: JsonInt => i.getValue().toString()
                    case f: JsonFloat => f.getValue().toString()
                    case b: JsonBool => if (b.getValue()) { "true" } else { "false" }
                    case _ => fallback
                }
            }
        case None => fallback
    }
}

private func ocBool(obj: JsonObject, key: String, fallback!: Bool = false): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                v.asBool().getValue()
            } catch (_e1: Exception) {
                let text = ocString(obj, key).trimAscii().toAsciiLower()
                if (text == "true" || text == "1" || text == "yes") {
                    true
                } else if (text == "false" || text == "0" || text == "no") {
                    false
                } else {
                    fallback
                }
            }
        case None => fallback
    }
}

private func ocInt(obj: JsonObject, key: String, fallback!: Int64 = 0): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            match (v) {
                case i: JsonInt => i.getValue()
                case f: JsonFloat => Int64(f.getValue())
                case _ => try { Int64.parse(ocString(obj, key).trimAscii()) } catch (_e: Exception) { fallback }
            }
        case None => fallback
    }
}

private func ocObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func ocArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func ocPutOptionalString(obj: JsonObject, key: String, value: String): Unit {
    let trimmed = value.trimAscii()
    if (!trimmed.isEmpty()) {
        obj.put(key, JsonString(trimmed))
    }
}

private func ocBasePayload(kind: String): JsonObject {
    let out = JsonObject()
    out.put("schema", JsonString(OPENCLAW_CHANNEL_HTTP_SCHEMA))
    out.put("bridge", JsonString("metis"))
    out.put("kind", JsonString(kind))
    return out
}

private func ocChannelBasePayload(kind: String, channelId: String, accountId: String): JsonObject {
    let out = ocBasePayload(kind)
    out.put("channelId", JsonString(channelId.trimAscii()))
    out.put("accountId", JsonString(accountId.trimAscii()))
    return out
}

public func openClawChannelLifecyclePayload(channelId: String, accountId: String, operation: String): JsonObject {
    let out = ocChannelBasePayload("channel.${operation.trimAscii()}", channelId, accountId)
    out.put("operation", JsonString(operation.trimAscii()))
    return out
}

public func openClawChannelPullInboundPayload(
    channelId: String,
    accountId: String,
    limit!: Int64 = 50,
    cursor!: String = ""
): JsonObject {
    let out = ocChannelBasePayload("channel.pullInbound", channelId, accountId)
    out.put("limit", limit.toJsonValue())
    ocPutOptionalString(out, "cursor", cursor)
    return out
}

public func openClawChannelSendPayload(
    channelId: String,
    accountId: String,
    peerId: String,
    text: String,
    replyToMessageId!: String = "",
    mediaRefs!: JsonArray = JsonArray([]),
    threadId!: String = "",
    chatType!: String = "direct",
    rawMetadata!: JsonObject = JsonObject()
): JsonObject {
    let out = ocChannelBasePayload("channel.send", channelId, accountId)
    out.put("peerId", JsonString(peerId.trimAscii()))
    out.put("text", JsonString(text))
    out.put("replyToMessageId", JsonString(replyToMessageId.trimAscii()))
    out.put("mediaRefs", mediaRefs)
    out.put("chatType", JsonString(chatType.trimAscii().toAsciiLower()))
    out.put("rawMetadata", rawMetadata)
    ocPutOptionalString(out, "threadId", threadId)
    return out
}

public func openClawHttpDispatchPayload(
    method: String,
    path: String,
    query!: JsonObject = JsonObject(),
    headers!: JsonObject = JsonObject(),
    body!: JsonValue = JsonString(""),
    timeoutMs!: Int64 = 0
): JsonObject {
    let out = ocBasePayload("http.dispatch")
    out.put("method", JsonString(method.trimAscii()))
    out.put("path", JsonString(path.trimAscii()))
    out.put("query", query)
    out.put("headers", headers)
    out.put("body", body)
    out.put("timeoutMs", timeoutMs.toJsonValue())
    return out
}

public func openClawParseCallResult(raw: JsonObject): OpenClawBridgeCallResult {
    let diagnostic = ocObject(raw, "diagnostic")
    OpenClawBridgeCallResult(
        ocBool(raw, "ok"),
        ocString(raw, "status"),
        ocString(raw, "reason"),
        diagnostic,
        raw
    )
}

public func openClawParseChannelSendResult(raw: JsonObject): OpenClawChannelSendResult {
    OpenClawChannelSendResult(
        ocBool(raw, "ok"),
        ocString(raw, "status"),
        ocString(raw, "messageId"),
        ocString(raw, "reason"),
        ocObject(raw, "diagnostic"),
        raw
    )
}

private func openClawMediaContext(channelId: String, message: JsonObject): JsonObject {
    let out = JsonObject()
    out.put("schema", JsonString(OPENCLAW_CHANNEL_HTTP_SCHEMA))
    out.put("channelId", JsonString(channelId.trimAscii()))
    out.put("accountId", JsonString(ocString(message, "accountId").trimAscii()))
    out.put("messageId", JsonString(ocString(message, "messageId").trimAscii()))
    out.put("peerId", JsonString(ocString(message, "peerId").trimAscii()))
    out.put("threadId", JsonString(ocString(message, "threadId").trimAscii()))
    out.put("chatType", JsonString(ocString(message, "chatType", fallback: "direct").trimAscii().toAsciiLower()))
    out.put("mediaRefs", ocArray(message, "mediaRefs"))
    out.put("rawMetadata", ocObject(message, "rawMetadata"))
    return out
}

private func openClawChatType(raw: String): ChatType {
    let normalized = raw.trimAscii().toAsciiLower()
    if (normalized == "group" || normalized == "supergroup" || normalized == "channel") {
        return ChatType.Group
    }
    ChatType.Direct
}

private func openClawInboundFromJson(channelId: String, message: JsonObject, index: Int64): Option<InboundMessage> {
    let peerId = ocString(message, "peerId").trimAscii()
    let senderId = ocString(message, "senderId").trimAscii()
    if (peerId.isEmpty() || senderId.isEmpty()) {
        return None<InboundMessage>
    }
    let messageId = ocString(message, "messageId").trimAscii()
    let normalizedMessageId = if (messageId.isEmpty()) { "openclaw-${channelId}-${index}" } else { messageId }
    let replyTarget = if (!ocString(message, "replyTargetMessageId").trimAscii().isEmpty()) {
        ocString(message, "replyTargetMessageId").trimAscii()
    } else {
        ocString(message, "replyToMessageId").trimAscii()
    }
    let threadId = ocString(message, "threadId").trimAscii()
    let conversationId = ocString(message, "conversationId").trimAscii()
    let rawMetadata = ocObject(message, "rawMetadata")
    Some<InboundMessage>(
        InboundMessage(
            ChannelType.Extension(channelId.trimAscii()),
            normalizedMessageId,
            peerId,
            senderId,
            openClawChatType(ocString(message, "chatType", fallback: "direct")),
            ocString(message, "text"),
            ocBool(message, "mentioned"),
            DateTime.now(),
            conversationId: if (conversationId.isEmpty()) { None<String> } else { Some(conversationId) },
            threadId: if (threadId.isEmpty()) { None<String> } else { Some(threadId) },
            replyTargetMessageId: if (replyTarget.isEmpty()) { None<String> } else { Some(replyTarget) },
            replyInThread: ocBool(message, "replyInThread"),
            raw: if (rawMetadata.toJsonString() == "{}") { None<String> } else { Some(rawMetadata.toJsonString()) },
            accountId: ocString(message, "accountId"),
            mediaContext: openClawMediaContext(channelId, message)
        )
    )
}

public func openClawParseChannelInbound(channelId: String, raw: JsonObject): Array<InboundMessage> {
    if (!ocBool(raw, "ok")) {
        return []
    }
    let out = ArrayList<InboundMessage>()
    let messages = ocArray(raw, "messages")
    for (i in 0..messages.size()) {
        let message = try { messages[i].asObject() } catch (_e: Exception) { JsonObject() }
        match (openClawInboundFromJson(channelId, message, i)) {
            case Some(inbound) => out.add(inbound)
            case None => ()
        }
    }
    out.toArray()
}

private func openClawHttpBody(raw: JsonObject): String {
    match (raw.get("body")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { v.toJsonString() }
        case None => ""
    }
}

public func openClawParseHttpDispatchResult(raw: JsonObject): OpenClawHttpDispatchResult {
    let diagnostic = ocObject(raw, "diagnostic")
    let statusCode = if (raw.get("statusCode").isSome()) {
        ocInt(raw, "statusCode")
    } else {
        ocInt(raw, "status")
    }
    OpenClawHttpDispatchResult(
        ocBool(raw, "ok"),
        ocString(raw, "status"),
        statusCode,
        ocObject(raw, "headers"),
        openClawHttpBody(raw),
        diagnostic,
        ocString(diagnostic, "kind"),
        ocString(diagnostic, "message"),
        raw
    )
}

public class OpenClawChannelAdapterBridge <: ChannelAdapter {
    public prop name: String {
        get() {
            this.channelId
        }
    }

    private let channelId: String
    private let accountId: String
    private let runner: OpenClawBridgeRunner

    public init(channelId: String, accountId: String, runner: OpenClawBridgeRunner) {
        this.channelId = channelId.trimAscii()
        this.accountId = accountId.trimAscii()
        this.runner = runner
    }

    public func startResult(): OpenClawBridgeCallResult {
        openClawParseCallResult(
            this.runner.invoke(
                OPENCLAW_CHANNEL_START_METHOD,
                openClawChannelLifecyclePayload(this.channelId, this.accountId, "start")
            )
        )
    }

    public func start(): Unit {
        let _ = this.startResult()
    }

    public func stopResult(): OpenClawBridgeCallResult {
        openClawParseCallResult(
            this.runner.invoke(
                OPENCLAW_CHANNEL_STOP_METHOD,
                openClawChannelLifecyclePayload(this.channelId, this.accountId, "stop")
            )
        )
    }

    public func stop(): Unit {
        let _ = this.stopResult()
    }

    public func health(): OpenClawBridgeCallResult {
        openClawParseCallResult(
            this.runner.invoke(
                OPENCLAW_CHANNEL_HEALTH_METHOD,
                openClawChannelLifecyclePayload(this.channelId, this.accountId, "health")
            )
        )
    }

    public func pullInbound(): Array<InboundMessage> {
        openClawParseChannelInbound(
            this.channelId,
            this.runner.invoke(
                OPENCLAW_CHANNEL_PULL_INBOUND_METHOD,
                openClawChannelPullInboundPayload(this.channelId, this.accountId)
            )
        )
    }

    public func send(message: OutboundMessage): SendResult {
        let result = this.sendResult(message)
        if (result.ok) {
            return SendResult.Success
        }
        let reason = if (result.reason.trimAscii().isEmpty()) { result.status } else { result.reason }
        SendResult.Failed(reason)
    }

    public func sendResult(message: OutboundMessage): OpenClawChannelSendResult {
        let replyTo = match (message.replyToMessageId) {
            case Some(v) => v
            case None => ""
        }
        let account = if (!message.accountId.trimAscii().isEmpty()) { message.accountId } else { this.accountId }
        openClawParseChannelSendResult(
            this.runner.invoke(
                OPENCLAW_CHANNEL_SEND_METHOD,
                openClawChannelSendPayload(
                    this.channelId,
                    account,
                    message.peerId,
                    message.text,
                    replyToMessageId: replyTo,
                    chatType: "direct"
                )
            )
        )
    }

    public func sendWithMessageId(message: OutboundMessage): String {
        let result = this.sendResult(message)
        if (result.ok) {
            return result.messageId
        }
        ""
    }
}

public class OpenClawHttpRouteBridge {
    private let runner: OpenClawBridgeRunner

    public init(runner: OpenClawBridgeRunner) {
        this.runner = runner
    }

    public func dispatch(
        method: String,
        path: String,
        query!: JsonObject = JsonObject(),
        headers!: JsonObject = JsonObject(),
        body!: JsonValue = JsonString(""),
        timeoutMs!: Int64 = 0
    ): OpenClawHttpDispatchResult {
        openClawParseHttpDispatchResult(
            this.runner.invoke(
                OPENCLAW_HTTP_DISPATCH_METHOD,
                openClawHttpDispatchPayload(
                    method,
                    path,
                    query: query,
                    headers: headers,
                    body: body,
                    timeoutMs: timeoutMs
                )
            )
        )
    }
}
