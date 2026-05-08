package metis.gateway.core

import metis.core.config.GatewayUserSettings

import std.collection.HashMap
import std.convert.Parsable
import stdx.encoding.json.{JsonObject, JsonValue}

public func gatewayTelegramErrorPolicyMode(user: GatewayUserSettings): String {
    if (user.telegram.errorPolicy.silentErrorReplies) {
        return "silent"
    }
    let normalized = user.telegram.errorPolicy.policy.trimAscii().toAsciiLower()
    if (normalized == "always" || normalized == "once" || normalized == "silent") {
        return normalized
    }
    "always"
}

private func gatewayTelegramErrorPolicyString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func gatewayTelegramErrorPolicyBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayTelegramErrorPolicyInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(v) => try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 0 }
        case None => 0
    }
}

private func gatewayTelegramErrorPolicyObject(obj: JsonObject): JsonObject {
    match (obj.get("errorPolicy")) {
        case Some(v) =>
            try {
                return v.asObject()
            } catch (_e: Exception) {
                let out = JsonObject()
                try { out.put("policy", v) } catch (_e2: Exception) { () }
                return out
            }
        case None => JsonObject()
    }
}

private func gatewayTelegramRouteConfigByKey(objOpt: Option<JsonObject>, keys: Array<String>): JsonObject {
    match (objOpt) {
        case Some(obj) =>
            for (key in keys) {
                match (obj.get(key)) {
                    case Some(v) => try { return v.asObject() } catch (_e: Exception) { () }
                    case None => ()
                }
            }
        case None => ()
    }
    JsonObject()
}

private func gatewayTelegramGroupIdFromPeer(peerId: String): String {
    let normalized = peerId.trimAscii()
    if (!normalized.startsWith("group:")) {
        return ""
    }
    let rest = normalized["group:".size..]
    match (rest.indexOf(":topic:")) {
        case Some(idx) => rest[..idx]
        case None => rest
    }
}

private func gatewayTelegramRouteErrorPolicy(user: GatewayUserSettings, peerId: String, threadId: String): JsonObject {
    let peer = peerId.trimAscii()
    if (peer.startsWith("group:")) {
        let groupId = gatewayTelegramGroupIdFromPeer(peer)
        let groupConfig = gatewayTelegramRouteConfigByKey(user.telegram.groups, [groupId, "group:${groupId}", peer])
        let topics = match (groupConfig.get("topics")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let topicKey = if (!threadId.trimAscii().isEmpty()) {
            threadId.trimAscii()
        } else {
            match (peer.indexOf(":topic:")) {
                case Some(idx) => peer[idx + ":topic:".size..].trimAscii()
                case None => ""
            }
        }
        if (!topicKey.isEmpty()) {
            let topicConfig = gatewayTelegramRouteConfigByKey(Some(topics), [topicKey, "topic:${topicKey}", peer])
            let topicPolicy = gatewayTelegramErrorPolicyObject(topicConfig)
            if (topicPolicy.size() > 0) {
                return topicPolicy
            }
        }
        return gatewayTelegramErrorPolicyObject(groupConfig)
    }
    let directId = if (peer.startsWith("user:")) { peer["user:".size..].trimAscii() } else { peer }
    let directConfig = gatewayTelegramRouteConfigByKey(user.telegram.direct, [peer, directId, "user:${directId}"])
    let directPolicy = gatewayTelegramErrorPolicyObject(directConfig)
    if (directPolicy.size() > 0) {
        return directPolicy
    }
    let dmConfig = gatewayTelegramRouteConfigByKey(user.telegram.dms, [peer, directId, "user:${directId}"])
    gatewayTelegramErrorPolicyObject(dmConfig)
}

public func gatewayTelegramErrorPolicyModeForTarget(user: GatewayUserSettings, peerId: String, threadId: String): String {
    let route = gatewayTelegramRouteErrorPolicy(user, peerId, threadId)
    if (gatewayTelegramErrorPolicyBool(route, "silentErrorReplies")) {
        return "silent"
    }
    let routePolicy = gatewayTelegramErrorPolicyString(route, "policy").toAsciiLower()
    if (routePolicy == "always" || routePolicy == "once" || routePolicy == "silent") {
        return routePolicy
    }
    gatewayTelegramErrorPolicyMode(user)
}

public func gatewayTelegramErrorCooldownMs(user: GatewayUserSettings): Int64 {
    let raw = user.telegram.errorPolicy.cooldownMs
    if (raw <= 0) { 60000 } else { raw }
}

public func gatewayTelegramErrorCooldownMsForTarget(user: GatewayUserSettings, peerId: String, threadId: String): Int64 {
    let route = gatewayTelegramRouteErrorPolicy(user, peerId, threadId)
    let raw = gatewayTelegramErrorPolicyInt(route, "cooldownMs")
    if (raw > 0) { raw } else { gatewayTelegramErrorCooldownMs(user) }
}

public class GatewayTelegramErrorPolicyState {
    private let lastErrorReplyAtMsByKey = HashMap<String, Int64>()

    public init() {}

    public func shouldReply(
        user: GatewayUserSettings,
        peerId: String,
        threadId: String,
        errorKey: String,
        nowMs: Int64
    ): Bool {
        let policy = gatewayTelegramErrorPolicyModeForTarget(user, peerId, threadId)
        if (policy == "silent") {
            return false
        }
        if (policy == "always") {
            return true
        }
        let key = "${peerId.trimAscii()}|${threadId.trimAscii()}|${errorKey.trimAscii()}"
        let cooldownMs = gatewayTelegramErrorCooldownMsForTarget(user, peerId, threadId)
        match (this.lastErrorReplyAtMsByKey.get(key)) {
            case Some(lastAt) =>
                if (nowMs - lastAt < cooldownMs) {
                    return false
                }
            case None => ()
        }
        this.lastErrorReplyAtMsByKey[key] = nowMs
        true
    }
}

public class GatewayTelegramSendErrorDecision {
    public let classification: String
    public let retryable: Bool
    public let softSuccess: Bool
    public let retryAfterSeconds: Int64
    public let diagnostic: String

    public init(
        classification!: String = "unknown",
        retryable!: Bool = false,
        softSuccess!: Bool = false,
        retryAfterSeconds!: Int64 = 0,
        diagnostic!: String = ""
    ) {
        this.classification = classification
        this.retryable = retryable
        this.softSuccess = softSuccess
        this.retryAfterSeconds = retryAfterSeconds
        this.diagnostic = diagnostic
    }
}

private func gatewayTelegramSendRetryAfterSeconds(raw: String): Int64 {
    try {
        let root = JsonValue.fromStr(raw).asObject()
        let params = match (root.get("parameters")) {
            case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        match (params.get("retry_after")) {
            case Some(v) =>
                try { return v.asInt().getValue() } catch (_e1: Exception) {
                    try { return Int64.parse(v.asString().getValue().trimAscii()) } catch (_e2: Exception) { return 0 }
                }
            case None => 0
        }
    } catch (_e: Exception) {
        0
    }
}

private func gatewayTelegramSendErrorCode(raw: String): Int64 {
    try {
        let root = JsonValue.fromStr(raw).asObject()
        match (root.get("error_code")) {
            case Some(v) =>
                try { v.asInt().getValue() } catch (_e1: Exception) {
                    try { Int64.parse(v.asString().getValue().trimAscii()) } catch (_e2: Exception) { 0 }
                }
            case None => 0
        }
    } catch (_e: Exception) {
        0
    }
}

private func gatewayTelegramSendDescription(raw: String): String {
    try {
        let root = JsonValue.fromStr(raw).asObject()
        match (root.get("description")) {
            case Some(v) => try { v.asString().getValue().trimAscii() } catch (_e: Exception) { raw.trimAscii() }
            case None => raw.trimAscii()
        }
    } catch (_e: Exception) {
        raw.trimAscii()
    }
}

private func gatewayTelegramSendDiagnostic(
    classification: String,
    retryable: Bool,
    softSuccess: Bool,
    retryAfterSeconds: Int64,
    description: String
): String {
    var out = "telegram send error class=${classification} retryable=${retryable} softSuccess=${softSuccess}"
    if (retryAfterSeconds > 0) {
        out += " retry_after=${retryAfterSeconds}"
    }
    if (!description.trimAscii().isEmpty()) {
        out += " detail=${description.trimAscii()}"
    }
    out
}

public func gatewayTelegramClassifySendError(
    kind: String,
    raw: String,
    transportOutcome!: String = "",
    statusCode!: Int64 = 0
): GatewayTelegramSendErrorDecision {
    let normalizedKind = kind.trimAscii().toAsciiLower()
    let outcome = transportOutcome.trimAscii().toAsciiLower()
    let description = gatewayTelegramSendDescription(raw)
    let low = description.toAsciiLower()
    let code = if (statusCode > 0) { statusCode } else { gatewayTelegramSendErrorCode(raw) }
    let retryAfter = gatewayTelegramSendRetryAfterSeconds(raw)

    var classification = "api-error"
    var retryable = false
    var softSuccess = false

    if (retryAfter > 0 || code == 429 || outcome == "rate-limit") {
        classification = "rate-limit"
        retryable = true
    } else if (code >= 500 || outcome == "retryable-status" || outcome == "timeout") {
        classification = "server-error"
        retryable = true
    } else if ((normalizedKind == "edit" || normalizedKind == "draft") && low.contains("message is not modified")) {
        classification = "message-not-modified"
        softSuccess = true
    } else if (normalizedKind == "reaction" && (low.contains("reaction") && (low.contains("invalid") || low.contains("not allowed") || low.contains("can't be set")))) {
        classification = "reaction-invalid"
    } else if (code == 401 || code == 403 || low.contains("unauthorized") || low.contains("forbidden") ||
        low.contains("bot was blocked") || low.contains("not enough rights") || low.contains("chat not found")) {
        classification = "permission"
    } else if (code >= 400 && code < 500) {
        classification = "client-error"
    } else if (outcome == "blocked-url") {
        classification = "blocked-url"
    } else if (!outcome.isEmpty() && outcome != "ok" && outcome != "api-ok-false") {
        classification = "transport-error"
    }

    GatewayTelegramSendErrorDecision(
        classification: classification,
        retryable: retryable,
        softSuccess: softSuccess,
        retryAfterSeconds: retryAfter,
        diagnostic: gatewayTelegramSendDiagnostic(classification, retryable, softSuccess, retryAfter, description)
    )
}
