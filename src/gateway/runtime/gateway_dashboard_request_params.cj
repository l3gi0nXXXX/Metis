package metis.gateway.runtime

import metis.gateway.session.{GatewayIngressSource, gatewayBuildChatHistoryRpcParams, gatewayBuildChatSendRpcParams, gatewayBuildSessionsDeleteRpcParams}

import std.convert.Parsable
import stdx.encoding.json.{JsonObject, JsonString, JsonValue}

private func gatewayDashboardParamString(params: JsonObject, key: String): String {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayDashboardParamBool(params: JsonObject, key: String): Bool {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) {
                let raw = try { v.asString().getValue().trimAscii().toAsciiLower() } catch (_inner: Exception) { "" }
                raw == "true" || raw == "1" || raw == "yes" || raw == "on"
            }
        case None => false
    }
}

private func gatewayDashboardParamInt(params: JsonObject, key: String, defaultValue: Int64): Int64 {
    match (params.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.toJsonString().trimAscii().replace("\"", ""))
            } catch (_e: Exception) {
                let raw = try { v.asString().getValue().trimAscii() } catch (_inner: Exception) { "" }
                if (raw.isEmpty()) {
                    defaultValue
                } else {
                    try { Int64.parse(raw) } catch (_inner: Exception) { defaultValue }
                }
            }
        case None => defaultValue
    }
}

public func gatewayDashboardRequestParams(
    method: String,
    params: JsonObject,
    source!: GatewayIngressSource = GatewayIngressSource.ControlUi
): JsonObject {
    let normalized = method.trimAscii().toAsciiLower()
    if (normalized == "dashboard.chat.history") {
        let sessionKey = gatewayDashboardParamString(params, "sessionKey")
        let session = if (!sessionKey.isEmpty()) { sessionKey } else { gatewayDashboardParamString(params, "session") }
        return gatewayBuildChatHistoryRpcParams(session: session)
    }
    if (normalized == "dashboard.chat.send") {
        let sessionKey = gatewayDashboardParamString(params, "sessionKey")
        let session = if (!sessionKey.isEmpty()) { sessionKey } else { gatewayDashboardParamString(params, "session") }
        let message = gatewayDashboardParamString(params, "message")
        let text = if (!message.trimAscii().isEmpty()) { message } else { gatewayDashboardParamString(params, "text") }
        return gatewayBuildChatSendRpcParams(
            source,
            session: session,
            text: text,
            deliver: gatewayDashboardParamBool(params, "deliver"),
            thinking: gatewayDashboardParamString(params, "thinking"),
            conversationId: gatewayDashboardParamString(params, "conversationId"),
            threadId: gatewayDashboardParamString(params, "threadId"),
            sourceMessageId: gatewayDashboardParamString(params, "sourceMessageId"),
            replyChannel: gatewayDashboardParamString(params, "replyChannel"),
            replyTo: gatewayDashboardParamString(params, "replyTo"),
            replyAccount: gatewayDashboardParamString(params, "replyAccount"),
            replyToMessageId: gatewayDashboardParamString(params, "replyToMessageId"),
            replyInThread: gatewayDashboardParamBool(params, "replyInThread"),
            idempotencyKey: gatewayDashboardParamString(params, "idempotencyKey")
        )
    }
    if (normalized == "dashboard.skills.set" || normalized == "skills.update") {
        let skillKey = gatewayDashboardParamString(params, "skillKey")
        let name = if (!skillKey.isEmpty()) { skillKey } else { gatewayDashboardParamString(params, "name") }
        let apiKey = gatewayDashboardParamString(params, "apiKey")
        let enabled = gatewayDashboardParamBool(params, "enabled")
        return gatewayDashboardBuildSkillSetRequestParams(name, enabled, apiKey: apiKey)
    }
    if (normalized == "dashboard.model.switch") {
        return gatewayDashboardBuildModelSwitchParams(gatewayDashboardParamString(params, "model"))
    }
    if (normalized == "dashboard.sessions.delete") {
        return gatewayBuildSessionsDeleteRpcParams(keys: gatewayDashboardParamString(params, "keys"))
    }
    if (normalized == "channels.status") {
        return gatewayDashboardBuildChannelsStatusParams(
            gatewayDashboardParamBool(params, "probe"),
            gatewayDashboardParamInt(params, "timeoutMs", 8000)
        )
    }
    if (normalized == "channels.runtime") {
        let out = JsonObject()
        let channelId = gatewayDashboardParamString(params, "channelId")
        let id = gatewayDashboardParamString(params, "id")
        let channel = gatewayDashboardParamString(params, "channel")
        if (!channelId.isEmpty()) {
            out.put("channelId", JsonString(channelId))
        } else if (!id.isEmpty()) {
            out.put("channelId", JsonString(id))
        } else if (!channel.isEmpty()) {
            out.put("channelId", JsonString(channel))
        }
        return out
    }
    if (normalized == "channels.health") {
        return JsonObject()
    }
    if (normalized == "channels.audit") {
        let out = JsonObject()
        let channelId = gatewayDashboardParamString(params, "channelId")
        let id = gatewayDashboardParamString(params, "id")
        let channel = gatewayDashboardParamString(params, "channel")
        if (!channelId.isEmpty()) {
            out.put("channelId", JsonString(channelId))
        } else if (!id.isEmpty()) {
            out.put("channelId", JsonString(id))
        } else if (!channel.isEmpty()) {
            out.put("channelId", JsonString(channel))
        }
        return out
    }
    if (normalized == "dashboard.cron") {
        return gatewayDashboardBuildCronPostParams(
            action: gatewayDashboardParamString(params, "action"),
            name: gatewayDashboardParamString(params, "name"),
            every: gatewayDashboardParamString(params, "every"),
            session: gatewayDashboardParamString(params, "session"),
            message: gatewayDashboardParamString(params, "message"),
            deliveryChannel: gatewayDashboardParamString(params, "delivery_channel"),
            deliveryTo: gatewayDashboardParamString(params, "delivery_to"),
            deliveryAnnounce: gatewayDashboardParamString(params, "delivery_announce"),
            systemEvent: gatewayDashboardParamString(params, "system_event"),
            wakeMode: gatewayDashboardParamString(params, "wake_mode"),
            at: gatewayDashboardParamString(params, "at"),
            cronExpr: gatewayDashboardParamString(params, "cron_expr"),
            timeZone: gatewayDashboardParamString(params, "time_zone"),
            id: gatewayDashboardParamString(params, "id"),
            enabled: gatewayDashboardParamString(params, "enabled"),
            scheduleKind: gatewayDashboardParamString(params, "schedule_kind")
        )
    }
    if (normalized == "config.get") {
        let path = gatewayDashboardParamString(params, "path")
        return gatewayDashboardBuildConfigGetParams(if (path.isEmpty()) { "gateway" } else { path })
    }
    if (normalized == "config.patch" || normalized == "config.apply") {
        return gatewayDashboardBuildConfigPatchParams(
            gatewayDashboardParamString(params, "path"),
            gatewayDashboardParamString(params, "raw")
        )
    }
    if (normalized == "config.schema.lookup") {
        return gatewayDashboardBuildConfigSchemaLookupParams(gatewayDashboardParamString(params, "path"))
    }
    params
}
