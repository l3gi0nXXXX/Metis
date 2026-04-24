package metis.gateway.config

import magic.jsonable.*

import metis.core.config.GatewayUserSettings

import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}

private func gatewaySupportsPutIfAbsent(obj: JsonObject, key: String, value: JsonValue): Unit {
    if (obj.get(key).isNone()) {
        obj.put(key, value)
    }
}

private func gatewayBuiltinChannelSupportsJson(user: GatewayUserSettings, channelId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(channelId)
    let out = JsonObject()
    out.put("provider", JsonString(normalized))
    out.put("deliveryMetadata", JsonBool(true))
    out.put("conversationBinding", JsonBool(true))
    out.put("messageReply", JsonBool(true))
    if (normalized == "feishu") {
        let threadReplyEnabled = user.feishu.replyInThread.trimAscii().toAsciiLower() == "enabled"
        out.put("threadReply", JsonBool(true))
        out.put("quoteReply", JsonBool(true))
        out.put("accountBinding", JsonBool(false))
        out.put("multiAccount", JsonBool(false))
        out.put("webhookIngress", JsonBool(true))
        out.put("streamIngress", JsonBool(true))
        out.put("officialMonitorHost", JsonBool(true))
        out.put("officialGateway", JsonBool(false))
        out.put("mentionRouting", JsonBool(true))
        out.put("activeMode", JsonString(user.feishu.receiveMode))
        out.put("replyInThreadDefault", JsonBool(threadReplyEnabled))
        out.put("transport", JsonString(if (user.feishu.receiveMode == "long_connect") { "official-sdk-monitor-host" } else { "webhook" }))
        return out
    }
    if (normalized == "qq") {
        out.put("threadReply", JsonBool(false))
        out.put("quoteReply", JsonBool(true))
        out.put("accountBinding", JsonBool(false))
        out.put("multiAccount", JsonBool(false))
        out.put("webhookIngress", JsonBool(false))
        out.put("streamIngress", JsonBool(true))
        out.put("officialMonitorHost", JsonBool(false))
        out.put("officialGateway", JsonBool(true))
        out.put("mentionRouting", JsonBool(true))
        out.put("activeMode", JsonString(user.qq.mode))
        out.put("replyInThreadDefault", JsonBool(false))
        out.put("transport", JsonString("official-ws"))
        return out
    }
    if (normalized == "telegram") {
        out.put("threadReply", JsonBool(true))
        out.put("quoteReply", JsonBool(true))
        out.put("accountBinding", JsonBool(false))
        out.put("multiAccount", JsonBool(false))
        out.put("webhookIngress", JsonBool(true))
        out.put("streamIngress", JsonBool(true))
        out.put("pollingIngress", JsonBool(true))
        out.put("officialMonitorHost", JsonBool(false))
        out.put("officialGateway", JsonBool(true))
        out.put("mentionRouting", JsonBool(true))
        out.put("activeMode", JsonString(if (!user.telegram.webhookUrl.trimAscii().isEmpty()) { "webhook" } else { "polling" }))
        out.put("replyInThreadDefault", JsonBool(user.telegram.replyToMode.trimAscii().toAsciiLower() != "off"))
        out.put("transport", JsonString(if (!user.telegram.webhookUrl.trimAscii().isEmpty()) { "webhook" } else { "bot-api" }))
        out.put("nativeCommands", JsonBool(true))
        out.put("customCommands", JsonBool(true))
        out.put("topicBindings", JsonBool(true))
        out.put("topicActions", JsonBool(true))
        out.put("pollActions", JsonBool(true))
        out.put("reactionActions", JsonBool(true))
        out.put("reactionEvents", JsonBool(user.telegram.reactionNotifications.trimAscii().toAsciiLower() != "off"))
        out.put("ackReaction", JsonBool(user.telegram.reactionLevel.trimAscii().toAsciiLower() != "off" && !user.telegram.ackReaction.trimAscii().isEmpty()))
        out.put("mediaSticker", JsonBool(true))
        out.put("mediaPhoto", JsonBool(true))
        out.put("mediaDocument", JsonBool(true))
        out.put("mediaAudio", JsonBool(true))
        out.put("mediaVoice", JsonBool(true))
        out.put("mediaVideo", JsonBool(true))
        out.put("mediaVideoNote", JsonBool(true))
        out.put("allowedUpdatesAuto", JsonBool(true))
        return out
    }
    out.put("threadReply", JsonBool(false))
    out.put("quoteReply", JsonBool(false))
    out.put("accountBinding", JsonBool(false))
    out.put("multiAccount", JsonBool(false))
    out.put("webhookIngress", JsonBool(false))
    out.put("streamIngress", JsonBool(false))
    out.put("officialMonitorHost", JsonBool(false))
    out.put("officialGateway", JsonBool(false))
    out.put("mentionRouting", JsonBool(false))
    out.put("activeMode", JsonString(""))
    out.put("replyInThreadDefault", JsonBool(false))
    out.put("transport", JsonString("builtin"))
    out
}

public func gatewayPluginSupportsJson(user: GatewayUserSettings, pluginId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(pluginId)
    let base = JsonObject()
    base.put("provider", JsonString(normalized))
    base.put("deliveryMetadata", JsonBool(true))
    base.put("conversationBinding", JsonBool(true))
    base.put("messageReply", JsonBool(true))
    base.put("threadReply", JsonBool(true))
    base.put("quoteReply", JsonBool(true))
    base.put("accountBinding", JsonBool(true))
    base.put("multiAccount", JsonBool(true))
    base.put("webhookIngress", JsonBool(false))
    base.put("streamIngress", JsonBool(false))
    base.put("officialMonitorHost", JsonBool(false))
    base.put("officialGateway", JsonBool(false))
    base.put("mentionRouting", JsonBool(true))
    let runtimeKind = match (getGatewayPluginCatalogEntry(normalized)) {
        case Some(entry) => entry.runtimeKind
        case None => "unknown"
    }
    let compatibilityMode = match (getGatewayPluginCatalogEntry(normalized)) {
        case Some(entry) => entry.compatibilityMode
        case None => ""
    }
    base.put("runtimeKind", JsonString(runtimeKind))
    base.put("compatibilityMode", JsonString(compatibilityMode))
    base.put(
        "transport",
        JsonString(
            if (compatibilityMode == "legacy-plugin-host") {
                "legacy-plugin-host"
            } else if (runtimeKind == "command-adapter") {
                "command-adapter"
            } else {
                "plugin-adapter"
            }
        )
    )
    base
}

public func gatewayChannelSupportsJson(user: GatewayUserSettings, channelId: String): JsonObject {
    let normalized = normalizeGatewayChannelId(channelId)
    match (getGatewayChannelCatalogEntry(normalized)) {
        case Some(entry) =>
            if (entry.builtin) {
                return gatewayBuiltinChannelSupportsJson(user, normalized)
            }
            if (!entry.pluginId.isEmpty()) {
                let supports = gatewayPluginSupportsJson(user, entry.pluginId)
                gatewaySupportsPutIfAbsent(supports, "channelId", JsonString(normalized))
                gatewaySupportsPutIfAbsent(supports, "provider", JsonString(entry.pluginId))
                return supports
            }
        case None => ()
    }
    let out = JsonObject()
    out.put("provider", JsonString(normalized))
    out.put("channelId", JsonString(normalized))
    out.put("deliveryMetadata", JsonBool(true))
    out.put("conversationBinding", JsonBool(true))
    out.put("messageReply", JsonBool(true))
    out.put("threadReply", JsonBool(false))
    out.put("quoteReply", JsonBool(false))
    out.put("accountBinding", JsonBool(false))
    out.put("multiAccount", JsonBool(false))
    out.put("webhookIngress", JsonBool(false))
    out.put("streamIngress", JsonBool(false))
    out.put("officialMonitorHost", JsonBool(false))
    out.put("officialGateway", JsonBool(false))
    out.put("mentionRouting", JsonBool(false))
    out.put("transport", JsonString("unknown"))
    out
}

public func gatewayChannelSupportsReplyInThread(supports: JsonObject): Bool {
    match (supports.get("threadReply")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

public func gatewayChannelSupportsMessageReply(supports: JsonObject): Bool {
    match (supports.get("messageReply")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

public func gatewayApplyChannelDeliveryPolicy(user: GatewayUserSettings, channelId: String, delivery: JsonObject): JsonObject {
    let supports = gatewayChannelSupportsJson(user, channelId)
    let out = delivery
    out.put("supports", supports)
    let requestedReplyInThread = match (delivery.get("replyInThread")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let requestedReplyToMessageId = match (delivery.get("replyToMessageId")) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
    let threadReplySupported = gatewayChannelSupportsReplyInThread(supports)
    let messageReplySupported = gatewayChannelSupportsMessageReply(supports)
    let effectiveReplyInThread = requestedReplyInThread && threadReplySupported
    let effectiveReplyToMessageId = if (requestedReplyToMessageId.isEmpty()) {
        ""
    } else if (messageReplySupported) {
        requestedReplyToMessageId
    } else {
        ""
    }
    let degraded = (!requestedReplyToMessageId.isEmpty() && !messageReplySupported) || (requestedReplyInThread && !threadReplySupported)
    let reason = if (!requestedReplyToMessageId.isEmpty() && !messageReplySupported) {
        "message-reply-unsupported"
    } else if (requestedReplyInThread && !threadReplySupported) {
        "thread-reply-unsupported"
    } else {
        "ok"
    }
    out.put("requestedReplyToMessageId", JsonString(requestedReplyToMessageId))
    out.put("requestedReplyInThread", requestedReplyInThread.toJsonValue())
    out.put("effectiveReplyToMessageId", JsonString(effectiveReplyToMessageId))
    out.put("effectiveReplyInThread", effectiveReplyInThread.toJsonValue())
    out.put("degraded", degraded.toJsonValue())
    out.put("policyState", JsonString(if (degraded) { "degraded" } else { "supported" }))
    out.put("policyReason", JsonString(reason))
    out
}
