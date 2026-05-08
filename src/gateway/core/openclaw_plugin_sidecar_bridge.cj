package metis.gateway.core

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings}
import metis.utils.ShellUtils

import magic.jsonable.*

import std.collection.ArrayList
import std.env.getVariable
import std.fs.Path
import std.time.*
import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let OPENCLAW_PLUGIN_COMPAT_KEY = "openclawPluginCompatibility"
private let OPENCLAW_PLUGIN_COMPAT_ALT_KEY = "openclawPluginSidecar"

private var gatewayOpenClawPluginSidecarRunnerOverride: Option<(String, JsonObject) -> JsonObject> =
    None<(String, JsonObject) -> JsonObject>

public func setGatewayOpenClawPluginSidecarRunnerForTest(runner: Option<(String, JsonObject) -> JsonObject>): Unit {
    gatewayOpenClawPluginSidecarRunnerOverride = runner
}

private func gatewayOpenClawPluginSidecarBool(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { fallback }
        case None => fallback
    }
}

private func gatewayOpenClawPluginSidecarString(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                let value = v.asString().getValue().trimAscii()
                if (value.isEmpty()) { fallback } else { value }
            } catch (_e: Exception) {
                fallback
            }
        case None => fallback
    }
}

private func gatewayOpenClawPluginSidecarInt(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.toJsonString())
            } catch (_e: Exception) {
                fallback
            }
        case None => fallback
    }
}

public func gatewayOpenClawPluginSidecarConfig(user: GatewayUserSettings): JsonObject {
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(OPENCLAW_PLUGIN_COMPAT_KEY)) {
                case Some(v) => try { return v.asObject() } catch (_e: Exception) { () }
                case None => ()
            }
            match (extra.get(OPENCLAW_PLUGIN_COMPAT_ALT_KEY)) {
                case Some(v) => try { return v.asObject() } catch (_e: Exception) { () }
                case None => ()
            }
        case None => ()
    }
    JsonObject()
}

public func gatewayOpenClawPluginSidecarEnabled(user: GatewayUserSettings): Bool {
    if (gatewayOpenClawPluginSidecarRunnerOverride.isSome()) {
        return true
    }
    gatewayOpenClawPluginSidecarBool(gatewayOpenClawPluginSidecarConfig(user), "enabled", false)
}

private func gatewayOpenClawPluginSidecarScriptPath(config: JsonObject): String {
    let configured = gatewayOpenClawPluginSidecarString(config, "scriptPath", "")
    if (!configured.isEmpty()) {
        return configured
    }
    let root = match (getVariable("METIS_CJPM_ROOT")) {
        case Some(v) =>
            let trimmed = v.trimAscii()
            if (trimmed.isEmpty()) { CliConfig.cwd.toString() } else { trimmed }
        case None => CliConfig.cwd.toString()
    }
    Path(root).join("scripts").join("openclaw-plugin-sidecar.mjs").toString()
}

private func gatewayOpenClawPluginSidecarDisabled(method: String): JsonObject {
    let out = JsonObject()
    out.put("ok", false.toJsonValue())
    out.put("status", JsonString("disabled"))
    out.put("method", JsonString(method))
    out.put("matched", false.toJsonValue())
    out.put("reason", JsonString("openclaw plugin compatibility sidecar is disabled"))
    return out
}

private func gatewayOpenClawPluginSidecarError(method: String, reason: String): JsonObject {
    let out = JsonObject()
    out.put("ok", false.toJsonValue())
    out.put("status", JsonString("error"))
    out.put("method", JsonString(method))
    out.put("matched", false.toJsonValue())
    out.put("reason", JsonString(reason.trimAscii()))
    return out
}

public func gatewayOpenClawPluginSidecarInvoke(user: GatewayUserSettings, method: String, payload: JsonObject): JsonObject {
    let normalizedMethod = method.trimAscii()
    let config = gatewayOpenClawPluginSidecarConfig(user)
    let configEnabled = gatewayOpenClawPluginSidecarBool(config, "enabled", false)
    if (!configEnabled) {
        match (gatewayOpenClawPluginSidecarRunnerOverride) {
            case Some(runner) => return runner(normalizedMethod, payload)
            case None => ()
        }
    }
    if (!configEnabled) {
        return gatewayOpenClawPluginSidecarDisabled(normalizedMethod)
    }
    let command = gatewayOpenClawPluginSidecarString(config, "nodeCommand", "node")
    let timeoutMs = max(1000, gatewayOpenClawPluginSidecarInt(config, "timeoutMs", 10000))
    let scriptPath = gatewayOpenClawPluginSidecarScriptPath(config)
    let request = JsonObject()
    request.put("method", JsonString(normalizedMethod))
    request.put("payload", payload)
    request.put("config", config)
    let args = [
        command,
        scriptPath,
        normalizedMethod,
        "--config-json",
        config.toJsonString(),
        "--request-json",
        request.toJsonString()
    ]
    let (code, stdout, stderr) = try {
        ShellUtils.execute(args, timeout: Some(Duration.millisecond * timeoutMs), withWrap: false, workDir: CliConfig.cwd)
    } catch (e: Exception) {
        return gatewayOpenClawPluginSidecarError(normalizedMethod, "sidecar launch failed: ${e.message}")
    }
    let raw = stdout.trimAscii()
    if (raw.isEmpty()) {
        return gatewayOpenClawPluginSidecarError(normalizedMethod, "sidecar returned empty response: ${stderr.trimAscii()}")
    }
    let parsed = try {
        JsonValue.fromStr(raw).asObject()
    } catch (e: Exception) {
        return gatewayOpenClawPluginSidecarError(normalizedMethod, "sidecar returned invalid json: ${e.message}")
    }
    parsed.put("method", JsonString(normalizedMethod))
    parsed.put("exitCode", code.toJsonValue())
    if (!stderr.trimAscii().isEmpty()) {
        parsed.put("stderr", JsonString(stderr.trimAscii()))
    }
    parsed
}

public func gatewayOpenClawPluginSidecarStart(user: GatewayUserSettings): JsonObject {
    gatewayOpenClawPluginSidecarInvoke(user, "lifecycle.start", JsonObject())
}

public func gatewayOpenClawPluginSidecarStop(user: GatewayUserSettings): JsonObject {
    gatewayOpenClawPluginSidecarInvoke(user, "lifecycle.stop", JsonObject())
}

public func gatewayOpenClawPluginSidecarHealth(user: GatewayUserSettings): JsonObject {
    gatewayOpenClawPluginSidecarInvoke(user, "lifecycle.health", JsonObject())
}

private func gatewayOpenClawPluginSidecarReadString(obj: JsonObject, key: String): String {
    gatewayOpenClawPluginSidecarString(obj, key, "")
}

private func gatewayOpenClawPluginSidecarCommandsFrom(result: JsonObject): Array<(String, String)> {
    let rows = ArrayList<(String, String)>()
    let commands = match (result.get("commands")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..commands.size()) {
        let row = try { commands[i].asObject() } catch (_e: Exception) { JsonObject() }
        let command = gatewayOpenClawPluginSidecarReadString(row, "command")
            .trimAscii()
            .toAsciiLower()
            .replace("/", "")
        let description = gatewayOpenClawPluginSidecarReadString(row, "description").trimAscii()
        if (!command.isEmpty() && !description.isEmpty()) {
            rows.add((command, description))
        }
    }
    rows.toArray()
}

public func gatewayOpenClawPluginSidecarCommandCatalogForMenu(): Array<(String, String)> {
    let user = CliSettingManager.readGatewaySettings()
    if (!gatewayOpenClawPluginSidecarEnabled(user)) {
        return []
    }
    gatewayOpenClawPluginSidecarCommandsFrom(
        gatewayOpenClawPluginSidecarInvoke(user, "commands.list", JsonObject())
    )
}

public func gatewayOpenClawPluginSidecarCommandCatalog(user: GatewayUserSettings): Array<(String, String)> {
    if (!gatewayOpenClawPluginSidecarEnabled(user)) {
        return []
    }
    gatewayOpenClawPluginSidecarCommandsFrom(
        gatewayOpenClawPluginSidecarInvoke(user, "commands.list", JsonObject())
    )
}

public func gatewayOpenClawPluginSidecarApplyMessageSendingHook(
    user: GatewayUserSettings,
    channelName: String,
    accountId: String,
    peerId: String,
    text: String,
    replyToMessageId: String,
    replyInThread: Bool
): JsonObject {
    if (!gatewayOpenClawPluginSidecarEnabled(user) || channelName.trimAscii().toAsciiLower() != "telegram") {
        let out = JsonObject()
        out.put("ok", true.toJsonValue())
        out.put("status", JsonString("skipped"))
        out.put("cancelled", false.toJsonValue())
        out.put("text", JsonString(text))
        return out
    }
    let payload = JsonObject()
    payload.put("channel", JsonString(channelName.trimAscii().toAsciiLower()))
    payload.put("accountId", JsonString(accountId.trimAscii()))
    payload.put("peerId", JsonString(peerId.trimAscii()))
    payload.put("to", JsonString(peerId.trimAscii()))
    payload.put("conversationId", JsonString(peerId.trimAscii()))
    payload.put("threadId", JsonString(gatewayOpenClawTelegramThreadIdFromPeer(peerId)))
    payload.put("text", JsonString(text))
    payload.put("content", JsonString(text))
    payload.put("caption", JsonString(""))
    payload.put("mediaKinds", JsonArray([]))
    payload.put("replyToMessageId", JsonString(replyToMessageId.trimAscii()))
    payload.put("replyInThread", replyInThread.toJsonValue())
    let reply = JsonObject()
    reply.put("messageId", JsonString(replyToMessageId.trimAscii()))
    reply.put("inThread", replyInThread.toJsonValue())
    payload.put("reply", reply)
    payload.put("quote", JsonObject())
    let metadata = JsonObject()
    metadata.put("channel", JsonString(channelName.trimAscii().toAsciiLower()))
    metadata.put("accountId", JsonString(accountId.trimAscii()))
    metadata.put("peerId", JsonString(peerId.trimAscii()))
    metadata.put("conversationId", JsonString(peerId.trimAscii()))
    metadata.put("threadId", JsonString(gatewayOpenClawTelegramThreadIdFromPeer(peerId)))
    metadata.put("reply", reply)
    payload.put("metadata", metadata)
    gatewayOpenClawPluginSidecarInvoke(user, "hook.message_sending", payload)
}

public func gatewayOpenClawPluginSidecarApplyMessageSentHook(
    user: GatewayUserSettings,
    channelName: String,
    accountId: String,
    peerId: String,
    text: String,
    sentMessageId: String,
    delivered: Bool,
    reason: String,
    durationMs!: Int64 = 0
): JsonObject {
    if (!gatewayOpenClawPluginSidecarEnabled(user) || channelName.trimAscii().toAsciiLower() != "telegram") {
        let out = JsonObject()
        out.put("ok", true.toJsonValue())
        out.put("status", JsonString("skipped"))
        return out
    }
    let payload = JsonObject()
    payload.put("channel", JsonString(channelName.trimAscii().toAsciiLower()))
    payload.put("accountId", JsonString(accountId.trimAscii()))
    payload.put("peerId", JsonString(peerId.trimAscii()))
    payload.put("to", JsonString(peerId.trimAscii()))
    payload.put("conversationId", JsonString(peerId.trimAscii()))
    payload.put("threadId", JsonString(gatewayOpenClawTelegramThreadIdFromPeer(peerId)))
    payload.put("text", JsonString(text))
    payload.put("content", JsonString(text))
    payload.put("sentMessageId", JsonString(sentMessageId.trimAscii()))
    let ids = JsonArray([])
    if (!sentMessageId.trimAscii().isEmpty()) {
        ids.add(JsonString(sentMessageId.trimAscii()))
    }
    payload.put("messageIds", ids)
    payload.put("mediaKinds", JsonArray([]))
    payload.put("delivered", delivered.toJsonValue())
    payload.put("success", delivered.toJsonValue())
    payload.put("reason", JsonString(reason.trimAscii()))
    payload.put("error", JsonString(reason.trimAscii()))
    payload.put("durationMs", durationMs.toJsonValue())
    let metadata = JsonObject()
    metadata.put("channel", JsonString(channelName.trimAscii().toAsciiLower()))
    metadata.put("accountId", JsonString(accountId.trimAscii()))
    metadata.put("peerId", JsonString(peerId.trimAscii()))
    metadata.put("conversationId", JsonString(peerId.trimAscii()))
    metadata.put("threadId", JsonString(gatewayOpenClawTelegramThreadIdFromPeer(peerId)))
    metadata.put("messageIds", ids)
    payload.put("metadata", metadata)
    gatewayOpenClawPluginSidecarInvoke(user, "hook.message_sent", payload)
}

public func gatewayOpenClawPluginSidecarApplyMessageReceivedHook(
    user: GatewayUserSettings,
    channelName: String,
    accountId: String,
    peerId: String,
    senderId: String,
    messageId: String,
    text: String,
    accepted: Bool,
    reason: String,
    raw: String,
    conversationId!: String = "",
    threadId!: String = "",
    replyToMessageId!: String = "",
    replyInThread!: Bool = false,
    mediaContext!: JsonObject = JsonObject()
): JsonObject {
    if (!gatewayOpenClawPluginSidecarEnabled(user) || channelName.trimAscii().toAsciiLower() != "telegram") {
        let out = JsonObject()
        out.put("ok", true.toJsonValue())
        out.put("status", JsonString("skipped"))
        return out
    }
    let payload = JsonObject()
    payload.put("channel", JsonString(channelName.trimAscii().toAsciiLower()))
    payload.put("accountId", JsonString(accountId.trimAscii()))
    payload.put("peerId", JsonString(peerId.trimAscii()))
    payload.put("from", JsonString(senderId.trimAscii()))
    payload.put("conversationId", JsonString(if (conversationId.trimAscii().isEmpty()) { peerId.trimAscii() } else { conversationId.trimAscii() }))
    payload.put("threadId", JsonString(if (threadId.trimAscii().isEmpty()) { gatewayOpenClawTelegramThreadIdFromPeer(peerId) } else { threadId.trimAscii() }))
    payload.put("senderId", JsonString(senderId.trimAscii()))
    payload.put("messageId", JsonString(messageId.trimAscii()))
    payload.put("text", JsonString(text))
    payload.put("content", JsonString(text))
    payload.put("mediaContext", mediaContext)
    payload.put("mediaSummary", gatewayOpenClawPluginSidecarMediaSummary(mediaContext))
    let reply = JsonObject()
    reply.put("messageId", JsonString(replyToMessageId.trimAscii()))
    reply.put("inThread", replyInThread.toJsonValue())
    payload.put("reply", reply)
    payload.put("quote", JsonObject())
    payload.put("forward", JsonObject())
    payload.put("accepted", accepted.toJsonValue())
    payload.put("reason", JsonString(reason.trimAscii()))
    payload.put("raw", JsonString(raw))
    let metadata = JsonObject()
    metadata.put("channel", JsonString(channelName.trimAscii().toAsciiLower()))
    metadata.put("accountId", JsonString(accountId.trimAscii()))
    metadata.put("peerId", JsonString(peerId.trimAscii()))
    metadata.put("conversationId", JsonString(if (conversationId.trimAscii().isEmpty()) { peerId.trimAscii() } else { conversationId.trimAscii() }))
    metadata.put("threadId", JsonString(if (threadId.trimAscii().isEmpty()) { gatewayOpenClawTelegramThreadIdFromPeer(peerId) } else { threadId.trimAscii() }))
    metadata.put("messageId", JsonString(messageId.trimAscii()))
    metadata.put("senderId", JsonString(senderId.trimAscii()))
    metadata.put("mediaSummary", gatewayOpenClawPluginSidecarMediaSummary(mediaContext))
    payload.put("metadata", metadata)
    gatewayOpenClawPluginSidecarInvoke(user, "hook.message_received", payload)
}

public func gatewayOpenClawPluginSidecarApplyCurrentMessageReceivedHook(
    channelName: String,
    accountId: String,
    peerId: String,
    senderId: String,
    messageId: String,
    text: String,
    accepted: Bool,
    reason: String,
    raw: String,
    conversationId!: String = "",
    threadId!: String = "",
    replyToMessageId!: String = "",
    replyInThread!: Bool = false,
    mediaContext!: JsonObject = JsonObject()
): JsonObject {
    gatewayOpenClawPluginSidecarApplyMessageReceivedHook(
        CliSettingManager.readGatewaySettings(),
        channelName,
        accountId,
        peerId,
        senderId,
        messageId,
        text,
        accepted,
        reason,
        raw,
        conversationId: conversationId,
        threadId: threadId,
        replyToMessageId: replyToMessageId,
        replyInThread: replyInThread,
        mediaContext: mediaContext
    )
}

private func gatewayOpenClawTelegramThreadIdFromPeer(peerId: String): String {
    let peer = peerId.trimAscii()
    match (peer.indexOf(":topic:")) {
        case Some(idx) => peer[(idx + ":topic:".size)..].trimAscii()
        case None => ""
    }
}

private func gatewayOpenClawPluginSidecarMediaSummary(mediaContext: JsonObject): JsonObject {
    let out = JsonObject()
    let kinds = JsonArray([])
    let records = match (mediaContext.get("records")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (i in 0..records.size()) {
        let row = try { records[i].asObject() } catch (_e: Exception) { JsonObject() }
        let kind = gatewayOpenClawPluginSidecarString(row, "mediaKind", gatewayOpenClawPluginSidecarString(row, "kind", "")).trimAscii()
        if (!kind.isEmpty()) {
            kinds.add(JsonString(kind))
        }
    }
    let context = match (mediaContext.get("context")) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    match (context.get("mediaKind")) {
        case Some(v) =>
            try {
                let kind = v.asString().getValue().trimAscii()
                if (!kind.isEmpty()) {
                    kinds.add(JsonString(kind))
                }
            } catch (_e: Exception) {
                ()
            }
        case None => ()
    }
    out.put("count", kinds.size().toJsonValue())
    out.put("kinds", kinds)
    return out
}
