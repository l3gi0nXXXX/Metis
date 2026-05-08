package metis.gateway.core

import metis.core.config.CliConfig
import metis.core.config.GatewayUserSettings

import magic.jsonable.*

import std.fs.{File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func telegramApprovalLineValue(text: String, key: String): String {
    let prefix = "${key}="
    for (line in text.split("\n")) {
        let trimmed = line.trimAscii()
        if (trimmed.startsWith(prefix)) {
            return trimmed[prefix.size..].trimAscii()
        }
    }
    ""
}

private func telegramApprovalJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func telegramApprovalSenderAllowed(user: GatewayUserSettings, senderId: String): Bool {
    let normalized = senderId.trimAscii()
    if (normalized.isEmpty()) {
        return false
    }
    let approvalMode = user.telegram.execApprovals.enabled.trimAscii().toAsciiLower()
    if (approvalMode == "false" || approvalMode == "off" || approvalMode == "disabled") {
        return false
    }
    if (!user.telegram.execApprovals.approvers.isEmpty()) {
        for (value in user.telegram.execApprovals.approvers) {
            let v = value.trimAscii()
            if (v == "*" || v == normalized || v == "telegram:${normalized}" || v == "tg:${normalized}" || v == "user:${normalized}") {
                return true
            }
        }
        return false
    }
    for (value in user.telegram.allowFrom) {
        let v = value.trimAscii()
        if (v == "*" || v == normalized || v == "telegram:${normalized}" || v == "tg:${normalized}" || v == "user:${normalized}") {
            return true
        }
    }
    for (value in user.telegram.groupAllowFrom) {
        let v = value.trimAscii()
        if (v == "*" || v == normalized || v == "telegram:${normalized}" || v == "tg:${normalized}" || v == "user:${normalized}") {
            return true
        }
    }
    false
}

private func telegramApprovalTerminalStatus(status: String): Bool {
    let normalized = status.trimAscii().toAsciiLower()
    normalized == "approved" || normalized == "denied" || normalized == "resolved" || normalized == "expired"
}

private func telegramApprovalApplyDecision(row: JsonObject, approvalId: String, decision: String, senderId: String): String {
    let current = telegramApprovalJsonString(row, "status")
    if (telegramApprovalTerminalStatus(current)) {
        return "already_resolved"
    }
    let normalizedDecision = decision.trimAscii().toAsciiLower()
    let status = if (normalizedDecision.startsWith("allow")) { "approved" } else if (normalizedDecision == "deny" || normalizedDecision == "denied") { "denied" } else { "resolved" }
    row.put("id", JsonString(approvalId))
    row.put("approvalId", JsonString(approvalId))
    row.put("decision", JsonString(normalizedDecision))
    row.put("status", JsonString(status))
    row.put("resolvedBy", JsonString(senderId.trimAscii()))
    row.put("resolvedAtMs", DateTime.now().toUnixTimeStamp().toMilliseconds().toJsonValue())
    "resolved"
}

private func telegramApprovalObjectMatches(row: JsonObject, approvalId: String): Bool {
    telegramApprovalJsonString(row, "id") == approvalId ||
        telegramApprovalJsonString(row, "approvalId") == approvalId ||
        telegramApprovalJsonString(row, "requestId") == approvalId
}

private func telegramApprovalResolveInArray(arr: JsonArray, approvalId: String, decision: String, senderId: String): (String, JsonArray) {
    let next = JsonArray([])
    var resolvedStatus = ""
    for (idx in 0..arr.size()) {
        let row = try { arr[idx].asObject() } catch (_: Exception) { JsonObject() }
        if (resolvedStatus.isEmpty() && telegramApprovalObjectMatches(row, approvalId)) {
            resolvedStatus = telegramApprovalApplyDecision(row, approvalId, decision, senderId)
        }
        next.add(row)
    }
    (resolvedStatus, next)
}

private func telegramApprovalResolveInRoot(root: JsonObject, approvalId: String, decision: String, senderId: String): String {
    if (telegramApprovalObjectMatches(root, approvalId)) {
        return telegramApprovalApplyDecision(root, approvalId, decision, senderId)
    }
    for (key in ["approvals", "pending", "items", "requests"]) {
        match (root.get(key)) {
            case Some(v) =>
                let arr = try { v.asArray() } catch (_: Exception) { JsonArray([]) }
                let (status, next) = telegramApprovalResolveInArray(arr, approvalId, decision, senderId)
                if (!status.isEmpty()) {
                    root.put(key, next)
                    return status
                }
            case None => ()
        }
    }
    match (root.get(approvalId)) {
        case Some(v) =>
            let obj = try { v.asObject() } catch (_: Exception) { JsonObject() }
            if (obj.size() > 0) {
                let status = telegramApprovalApplyDecision(obj, approvalId, decision, senderId)
                root.put(approvalId, obj)
                return status
            }
        case None => ()
    }
    ""
}

public func gatewayResolveTelegramApprovalCallback(
    text: String,
    user: GatewayUserSettings,
    approvalsPath!: Path = CliConfig.dotDir.join("exec-approvals.json")
): JsonObject {
    let out = JsonObject()
    out.put("kind", JsonString("telegram-approval-resolver"))
    if (!text.trimAscii().startsWith("[telegram-approval]")) {
        out.put("ok", false.toJsonValue())
        out.put("status", JsonString("ignored"))
        out.put("error", JsonString("not_telegram_approval"))
        return out
    }
    let approvalId = telegramApprovalLineValue(text, "approvalId")
    let decision = telegramApprovalLineValue(text, "decision")
    let senderId = telegramApprovalLineValue(text, "by")
    out.put("approvalId", JsonString(approvalId))
    out.put("decision", JsonString(decision))
    out.put("senderId", JsonString(senderId))
    out.put("path", JsonString(approvalsPath.toString()))
    if (approvalId.isEmpty() || decision.isEmpty() || senderId.isEmpty()) {
        out.put("ok", false.toJsonValue())
        out.put("status", JsonString("error"))
        out.put("error", JsonString("invalid_approval_callback"))
        return out
    }
    if (!telegramApprovalSenderAllowed(user, senderId)) {
        out.put("ok", false.toJsonValue())
        out.put("status", JsonString("rejected"))
        out.put("error", JsonString("sender_not_authorized"))
        return out
    }
    if (!exists(approvalsPath)) {
        out.put("ok", false.toJsonValue())
        out.put("status", JsonString("error"))
        out.put("error", JsonString("approval_not_found"))
        return out
    }
    let raw = String.fromUtf8(File.readFrom(approvalsPath))
    let root = try { JsonValue.fromStr(raw).asObject() } catch (_: Exception) { JsonObject() }
    if (root.size() == 0) {
        out.put("ok", false.toJsonValue())
        out.put("status", JsonString("error"))
        out.put("error", JsonString("approval_store_invalid"))
        return out
    }
    let status = telegramApprovalResolveInRoot(root, approvalId, decision, senderId)
    if (status.isEmpty()) {
        out.put("ok", false.toJsonValue())
        out.put("status", JsonString("error"))
        out.put("error", JsonString("approval_not_found"))
        return out
    }
    File.writeTo(approvalsPath, root.toJsonString().toArray())
    out.put("ok", (status == "resolved").toJsonValue())
    out.put("status", JsonString(status))
    if (status != "resolved") {
        out.put("error", JsonString(status))
    }
    out
}

public func gatewayTelegramApprovalResolverReply(result: JsonObject): String {
    let ok = match (result.get("ok")) {
        case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
    let approvalId = telegramApprovalJsonString(result, "approvalId")
    let decision = telegramApprovalJsonString(result, "decision")
    let status = telegramApprovalJsonString(result, "status")
    let error = telegramApprovalJsonString(result, "error")
    if (ok) {
        return "Approval resolved: ${approvalId} -> ${decision}"
    }
    if (!error.isEmpty()) {
        return "Approval not resolved: ${approvalId} (${error})"
    }
    "Approval not resolved: ${approvalId} (${status})"
}
