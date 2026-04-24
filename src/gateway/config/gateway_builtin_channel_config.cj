package metis.gateway.config

import magic.jsonable.*

import metis.core.config.GatewayUserSettings

import std.collection.HashMap
import stdx.encoding.json.{JsonObject, JsonValue}

public func gatewayBuiltinExtraConfig(user: GatewayUserSettings, channelId: String): JsonObject {
    let normalized = channelId.trimAscii().toAsciiLower()
    if (normalized == "telegram") {
        let obj = JsonObject()
        obj.put("enabled", user.telegram.enabled.toJsonValue())
        obj.put("botToken", user.telegram.botToken.toJsonValue())
        obj.put("tokenFile", user.telegram.tokenFile.toJsonValue())
        obj.put("dmPolicy", user.telegram.dmPolicy.toJsonValue())
        obj.put("groupPolicy", user.telegram.groupPolicy.toJsonValue())
        obj.put("commandsNative", user.telegram.commandsNative.toJsonValue())
        obj.put("replyToMode", user.telegram.replyToMode.toJsonValue())
        obj.put("streaming", user.telegram.streaming.toJsonValue())
        obj.put("textChunkLimit", user.telegram.textChunkLimit.toJsonValue())
        obj.put("linkPreview", user.telegram.linkPreview.toJsonValue())
        obj.put("webhookUrl", user.telegram.webhookUrl.toJsonValue())
        obj.put("webhookSecret", user.telegram.webhookSecret.toJsonValue())
        obj.put("webhookPath", user.telegram.webhookPath.toJsonValue())
        obj.put("webhookHost", user.telegram.webhookHost.toJsonValue())
        obj.put("webhookPort", user.telegram.webhookPort.toJsonValue())
        obj.put("apiRoot", user.telegram.apiRoot.toJsonValue())
        obj.put("reactionNotifications", user.telegram.reactionNotifications.toJsonValue())
        obj.put("reactionLevel", user.telegram.reactionLevel.toJsonValue())
        obj.put("ackReaction", user.telegram.ackReaction.toJsonValue())
        return obj
    }
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(normalized)) {
                case Some(v) =>
                    try { v.asObject() } catch (_e: Exception) { JsonObject(HashMap<String, JsonValue>()) }
                case None => JsonObject(HashMap<String, JsonValue>())
            }
        case None => JsonObject(HashMap<String, JsonValue>())
    }
}

public func gatewayBuiltinExtraBool(cfg: JsonObject, key: String, defaultValue: Bool): Bool {
    match (cfg.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

public func gatewayBuiltinExtraString(cfg: JsonObject, key: String): String {
    match (cfg.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

public func gatewayBuiltinExtraConfigured(cfg: JsonObject): Bool {
    if (gatewayBuiltinExtraBool(cfg, "configured", false)) {
        return true
    }
    for (key in ["token", "botToken", "appToken", "webhookUrl", "signingSecret", "channel", "guildId"]) {
        if (!gatewayBuiltinExtraString(cfg, key).isEmpty()) {
            return true
        }
    }
    false
}

public func gatewayBuiltinExtraChannelConfigPresent(user: GatewayUserSettings, channelId: String): Bool {
    let normalized = channelId.trimAscii().toAsciiLower()
    if (normalized == "telegram") {
        return !user.telegram.botToken.trimAscii().isEmpty() ||
            !user.telegram.tokenFile.trimAscii().isEmpty() ||
            !user.telegram.webhookUrl.trimAscii().isEmpty()
    }
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(normalized)) {
                case Some(v) => v.toJsonString().trimAscii() != "{}"
                case None => false
            }
        case None => false
    }
}

public func gatewayBuiltinExtraChannelEnabled(user: GatewayUserSettings, channelId: String): Bool {
    let normalized = channelId.trimAscii().toAsciiLower()
    if (normalized == "telegram") {
        return user.telegram.enabled
    }
    match (user.channelsExtra) {
        case Some(extra) =>
            match (extra.get(normalized)) {
                case Some(v) =>
                    try {
                        let obj = v.asObject()
                        match (obj.get("enabled")) {
                            case Some(flag) =>
                                try { flag.asBool().getValue() } catch (_e: Exception) { true }
                            case None => true
                        }
                    } catch (_e: Exception) {
                        false
                    }
                case None => false
            }
        case None => false
    }
}
