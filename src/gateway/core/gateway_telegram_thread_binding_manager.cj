package metis.gateway.core

import metis.core.config.{CliConfig, GatewayUserSettings}
import metis.gateway.model.{InboundMessage, channelToString}

import magic.jsonable.*
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private var gatewayTelegramThreadBindingRootOverride: Option<Path> = None<Path>

public func setGatewayTelegramThreadBindingRootForTest(root: Option<Path>): Unit {
    gatewayTelegramThreadBindingRootOverride = root
}

private func gatewayTelegramThreadBindingRoot(): Path {
    match (gatewayTelegramThreadBindingRootOverride) {
        case Some(root) => root
        case None => CliConfig.dotDir.join("gateway-telegram")
    }
}

private func gatewayTelegramThreadBindingPath(): Path {
    gatewayTelegramThreadBindingRoot().join("thread-bindings.json")
}

private func gatewayTelegramThreadBindingNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}

private func gatewayTelegramThreadBindingString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayTelegramThreadBindingInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayTelegramThreadBindingLoad(): JsonArray {
    let path = gatewayTelegramThreadBindingPath()
    if (!exists(path)) {
        return JsonArray([])
    }
    try {
        JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asArray()
    } catch (_e: Exception) {
        JsonArray([])
    }
}

private func gatewayTelegramThreadBindingSave(rows: JsonArray): Unit {
    let root = gatewayTelegramThreadBindingRoot()
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    File.writeTo(gatewayTelegramThreadBindingPath(), rows.toJsonString().toArray())
}

private func gatewayTelegramThreadBindingKey(channel: String, accountId: String, conversationId: String): String {
    "${channel.trimAscii().toAsciiLower()}|${accountId.trimAscii()}|${conversationId.trimAscii()}"
}

private func gatewayTelegramThreadBindingRecordKey(row: JsonObject): String {
    gatewayTelegramThreadBindingKey(
        gatewayTelegramThreadBindingString(row, "channel"),
        gatewayTelegramThreadBindingString(row, "accountId"),
        gatewayTelegramThreadBindingString(row, "conversationId")
    )
}

private func gatewayTelegramThreadBindingExpired(row: JsonObject, nowMs: Int64): Bool {
    let expiresAtMs = gatewayTelegramThreadBindingInt(row, "expiresAtMs")
    expiresAtMs > 0 && expiresAtMs <= nowMs
}

public func gatewayTelegramThreadBindingExpire(nowMs!: Int64 = gatewayTelegramThreadBindingNowMs()): JsonObject {
    let rows = gatewayTelegramThreadBindingLoad()
    let kept = JsonArray([])
    var expired: Int64 = 0
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (gatewayTelegramThreadBindingExpired(row, nowMs)) {
            expired += 1
        } else {
            kept.add(row)
        }
    }
    gatewayTelegramThreadBindingSave(kept)
    let out = JsonObject()
    out.put("ok", JsonBool(true))
    out.put("expired", expired.toJsonValue())
    out.put("remaining", kept.size().toJsonValue())
    return out
}

public func gatewayTelegramThreadBindingBind(
    channel: String,
    accountId: String,
    conversationId: String,
    sessionKey: String,
    parentConversationId!: String = "",
    threadId!: String = "",
    ownerId!: String = "",
    ttlMs!: Int64 = 0,
    nowMs!: Int64 = gatewayTelegramThreadBindingNowMs()
): JsonObject {
    let normalizedChannel = channel.trimAscii().toAsciiLower()
    let normalizedAccount = accountId.trimAscii()
    let normalizedConversation = conversationId.trimAscii()
    let normalizedSession = sessionKey.trimAscii().toAsciiLower()
    let result = JsonObject()
    if (normalizedChannel.isEmpty() || normalizedAccount.isEmpty() || normalizedConversation.isEmpty() || normalizedSession.isEmpty()) {
        result.put("ok", JsonBool(false))
        result.put("status", JsonString("error"))
        result.put("error", JsonString("channel, accountId, conversationId, and sessionKey are required"))
        return result
    }
    let rows = gatewayTelegramThreadBindingLoad()
    let next = JsonArray([])
    let bindingKey = gatewayTelegramThreadBindingKey(normalizedChannel, normalizedAccount, normalizedConversation)
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (!gatewayTelegramThreadBindingExpired(row, nowMs) &&
            gatewayTelegramThreadBindingRecordKey(row) != bindingKey) {
            next.add(row)
        }
    }
    let record = JsonObject()
    record.put("channel", JsonString(normalizedChannel))
    record.put("accountId", JsonString(normalizedAccount))
    record.put("conversationId", JsonString(normalizedConversation))
    record.put("parentConversationId", JsonString(parentConversationId.trimAscii()))
    record.put("threadId", JsonString(threadId.trimAscii()))
    record.put("sessionKey", JsonString(normalizedSession))
    record.put("ownerId", JsonString(ownerId.trimAscii()))
    record.put("createdAtMs", nowMs.toJsonValue())
    record.put("updatedAtMs", nowMs.toJsonValue())
    if (ttlMs > 0) {
        record.put("expiresAtMs", (nowMs + ttlMs).toJsonValue())
    } else {
        record.put("expiresAtMs", 0.toJsonValue())
    }
    next.add(record)
    gatewayTelegramThreadBindingSave(next)
    result.put("ok", JsonBool(true))
    result.put("status", JsonString("bound"))
    result.put("binding", record)
    return result
}

public func gatewayTelegramThreadBindingList(nowMs!: Int64 = gatewayTelegramThreadBindingNowMs()): JsonArray {
    let rows = gatewayTelegramThreadBindingLoad()
    let out = JsonArray([])
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (!gatewayTelegramThreadBindingExpired(row, nowMs)) {
            out.add(row)
        }
    }
    return out
}

public func gatewayTelegramThreadBindingResolve(
    channel: String,
    accountId: String,
    conversationId: String,
    parentConversationId!: String = "",
    nowMs!: Int64 = gatewayTelegramThreadBindingNowMs()
): JsonObject {
    let normalizedChannel = channel.trimAscii().toAsciiLower()
    let normalizedAccount = accountId.trimAscii()
    let normalizedConversation = conversationId.trimAscii()
    let normalizedParent = parentConversationId.trimAscii()
    let rows = gatewayTelegramThreadBindingList(nowMs: nowMs)
    var parentMatch = JsonObject()
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        let rowChannel = gatewayTelegramThreadBindingString(row, "channel")
        let rowAccount = gatewayTelegramThreadBindingString(row, "accountId")
        let rowConversation = gatewayTelegramThreadBindingString(row, "conversationId")
        if (rowChannel != normalizedChannel) {
            continue
        }
        if (!(rowAccount == normalizedAccount || rowAccount == "*")) {
            continue
        }
        if (rowConversation == normalizedConversation) {
            return row
        }
        if (!normalizedParent.isEmpty() && rowConversation == normalizedParent && parentMatch.size() == 0) {
            parentMatch = row
        }
    }
    parentMatch
}

public func gatewayTelegramThreadBindingTouch(
    channel: String,
    accountId: String,
    conversationId: String,
    nowMs!: Int64 = gatewayTelegramThreadBindingNowMs()
): JsonObject {
    let rows = gatewayTelegramThreadBindingLoad()
    let key = gatewayTelegramThreadBindingKey(channel, accountId, conversationId)
    let out = JsonArray([])
    var touched = JsonObject()
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (!gatewayTelegramThreadBindingExpired(row, nowMs) && gatewayTelegramThreadBindingRecordKey(row) == key) {
            row.put("updatedAtMs", nowMs.toJsonValue())
            touched = row
        }
        if (!gatewayTelegramThreadBindingExpired(row, nowMs)) {
            out.add(row)
        }
    }
    gatewayTelegramThreadBindingSave(out)
    let result = JsonObject()
    result.put("ok", JsonBool(touched.size() > 0))
    result.put("status", JsonString(if (touched.size() > 0) { "touched" } else { "not_found" }))
    if (touched.size() > 0) {
        result.put("binding", touched)
    }
    return result
}

public func gatewayTelegramThreadBindingUnbind(
    channel: String,
    accountId: String,
    conversationId: String,
    nowMs!: Int64 = gatewayTelegramThreadBindingNowMs()
): JsonObject {
    let rows = gatewayTelegramThreadBindingLoad()
    let key = gatewayTelegramThreadBindingKey(channel, accountId, conversationId)
    let out = JsonArray([])
    var removed: Int64 = 0
    for (i in 0..rows.size()) {
        let row = try { rows[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (gatewayTelegramThreadBindingExpired(row, nowMs)) {
            continue
        }
        if (gatewayTelegramThreadBindingRecordKey(row) == key) {
            removed += 1
            continue
        }
        out.add(row)
    }
    gatewayTelegramThreadBindingSave(out)
    let result = JsonObject()
    result.put("ok", JsonBool(removed > 0))
    result.put("status", JsonString(if (removed > 0) { "unbound" } else { "not_found" }))
    result.put("removed", removed.toJsonValue())
    return result
}

private func gatewayTelegramParentConversationId(peerId: String, conversationId: String): String {
    let peer = peerId.trimAscii()
    match (peer.indexOf(":topic:")) {
        case Some(idx) => return peer[..idx]
        case None => ()
    }
    let conversation = conversationId.trimAscii()
    match (conversation.indexOf(":topic:")) {
        case Some(idx) => conversation[..idx]
        case None => ""
    }
}

public func gatewayTelegramConversationIdForMessage(message: InboundMessage): String {
    let conversationId = message.conversationId ?? ""
    if (!conversationId.trimAscii().isEmpty()) {
        return conversationId.trimAscii()
    }
    message.peerId.trimAscii()
}

public func gatewayTelegramThreadBindingSessionHintForMessage(
    user: GatewayUserSettings,
    message: InboundMessage,
    accountId: String
): String {
    if (!user.telegram.threadBindings.enabled || channelToString(message.channel) != "telegram") {
        return ""
    }
    let conversationId = gatewayTelegramConversationIdForMessage(message)
    if (conversationId.isEmpty()) {
        return ""
    }
    let parentConversationId = gatewayTelegramParentConversationId(message.peerId, conversationId)
    let binding = gatewayTelegramThreadBindingResolve(
        "telegram",
        accountId,
        conversationId,
        parentConversationId: parentConversationId
    )
    let sessionKey = gatewayTelegramThreadBindingString(binding, "sessionKey")
    if (!sessionKey.isEmpty()) {
        let _ = gatewayTelegramThreadBindingTouch("telegram", gatewayTelegramThreadBindingString(binding, "accountId"), gatewayTelegramThreadBindingString(binding, "conversationId"))
    }
    sessionKey
}
