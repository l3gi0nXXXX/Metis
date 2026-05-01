package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.GatewayUserSettings

import std.convert.Parsable
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func gatewayTelegramDiagString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayTelegramDiagBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayTelegramDiagObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayTelegramDiagArray(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(JsonString(value))
    }
    out
}

private func gatewayTelegramNormalizeSenderId(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed == "*") {
        return "*"
    }
    if (trimmed.startsWith("telegram:")) {
        return trimmed["telegram:".size..].trimAscii()
    }
    if (trimmed.startsWith("tg:")) {
        return trimmed["tg:".size..].trimAscii()
    }
    if (trimmed.startsWith("user:")) {
        return trimmed["user:".size..].trimAscii()
    }
    trimmed
}

private func gatewayTelegramSenderTokenIsNumeric(raw: String): Bool {
    let normalized = gatewayTelegramNormalizeSenderId(raw)
    if (normalized.isEmpty() || normalized == "*") {
        return true
    }
    try {
        let parsed = Int64.parse(normalized)
        return parsed > 0
    } catch (_e: Exception) {
        return false
    }
}

private func gatewayTelegramContainsWildcard(values: Array<String>): Bool {
    for (value in values) {
        if (gatewayTelegramNormalizeSenderId(value) == "*") {
            return true
        }
    }
    false
}

private func gatewayTelegramInvalidSenderTokens(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        if (!gatewayTelegramSenderTokenIsNumeric(value)) {
            out.add(JsonString(value))
        }
    }
    out
}

private func gatewayTelegramHasTokenConfigured(user: GatewayUserSettings): Bool {
    !user.telegram.botToken.trimAscii().isEmpty() || !user.telegram.tokenFile.trimAscii().isEmpty()
}

private func gatewayTelegramFinding(
    id: String,
    severity: String,
    status: String,
    summary: String,
    detail: String,
    remediation: String
): JsonObject {
    let out = JsonObject()
    out.put("id", JsonString(id))
    out.put("severity", JsonString(severity))
    out.put("status", JsonString(status))
    out.put("summary", JsonString(summary))
    out.put("detail", JsonString(detail))
    out.put("remediation", JsonString(remediation))
    return out
}

private func gatewayTelegramAddFinding(
    findings: JsonArray,
    id: String,
    severity: String,
    status: String,
    summary: String,
    detail: String,
    remediation: String
): Unit {
    findings.add(gatewayTelegramFinding(id, severity, status, summary, detail, remediation))
}

private func gatewayTelegramRuntimeContainsGetMeFailure(runtime: JsonObject): Bool {
    let liveProbe = gatewayTelegramDiagObject(runtime, "liveProbe")
    let liveStatus = gatewayTelegramDiagString(liveProbe, "status", "")
    if (liveStatus == "degraded" || liveStatus == "failed" || liveStatus == "error") {
        return true
    }
    let snapshot = if (liveProbe.get("snapshot").isSome()) {
        gatewayTelegramDiagObject(liveProbe, "snapshot")
    } else {
        gatewayTelegramDiagObject(runtime, "healthSnapshot")
    }
    let getMe = gatewayTelegramDiagObject(snapshot, "getMe")
    if (getMe.size() > 0) {
        return !gatewayTelegramDiagBool(getMe, "ok", false)
    }
    false
}

private func gatewayTelegramRuntimeContainsWebhookConflict(runtime: JsonObject): Bool {
    let snapshot = gatewayTelegramDiagObject(runtime, "healthSnapshot")
    let lifecycle = gatewayTelegramDiagObject(snapshot, "webhookLifecycle")
    let cleanupError = gatewayTelegramDiagString(lifecycle, "cleanupError", "").toAsciiLower()
    let registrationError = gatewayTelegramDiagString(lifecycle, "registrationError", "").toAsciiLower()
    let webhook = gatewayTelegramDiagObject(snapshot, "webhook")
    let webhookUrl = gatewayTelegramDiagString(webhook, "url", "")
    cleanupError.contains("409") ||
        cleanupError.contains("conflict") ||
        registrationError.contains("409") ||
        registrationError.contains("conflict") ||
        (!webhookUrl.isEmpty() && gatewayTelegramDiagString(runtime, "mode", "") == "polling")
}

private func gatewayTelegramRuntimeContainsPolling409(runtime: JsonObject): Bool {
    let snapshot = gatewayTelegramDiagObject(runtime, "healthSnapshot")
    let polling = gatewayTelegramDiagObject(snapshot, "polling")
    let outcome = gatewayTelegramDiagString(polling, "lastOutcome", "").toAsciiLower()
    let error = gatewayTelegramDiagString(polling, "lastError", "").toAsciiLower()
    outcome.contains("409") || outcome.contains("conflict") || error.contains("409") || error.contains("conflict")
}

private func gatewayTelegramBuildDiagnosticFindings(user: GatewayUserSettings, runtime: JsonObject): JsonArray {
    let findings = JsonArray([])
    if (!user.telegram.enabled) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-disabled",
            "info",
            "skipped",
            "Telegram channel is disabled.",
            "Telegram diagnostics are skipped until gateway.telegram.enabled is true.",
            "Enable Telegram before using this channel."
        )
        return findings
    }

    if (!gatewayTelegramHasTokenConfigured(user)) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-token-missing",
            "critical",
            "failed",
            "Telegram bot token is not configured.",
            "gateway.telegram.botToken and gateway.telegram.tokenFile are both empty.",
            "Configure tokenFile or botToken; prefer tokenFile for local secret hygiene."
        )
    }

    if (gatewayTelegramRuntimeContainsGetMeFailure(runtime)) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-getme-failed",
            "warning",
            "failed",
            "Telegram getMe probe is not healthy.",
            "The runtime health snapshot reports a failed or degraded getMe result.",
            "Verify token validity, proxy, DNS, TLS, and Telegram Bot API reachability."
        )
    }

    if (gatewayTelegramRuntimeContainsWebhookConflict(runtime)) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-webhook-conflict",
            "warning",
            "failed",
            "Telegram webhook state conflicts with current runtime mode.",
            "Polling mode must clear existing Telegram webhook state before getUpdates can work reliably.",
            "Run gateway restart after fixing webhook mode or clear webhook with deleteWebhook through the native transport."
        )
    }

    if (gatewayTelegramRuntimeContainsPolling409(runtime)) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-polling-409",
            "warning",
            "failed",
            "Telegram polling reported a 409 conflict.",
            "Another getUpdates consumer or stale webhook state can cause Telegram polling conflicts.",
            "Stop competing consumers and let the polling supervisor back off and recover."
        )
    }

    let invalidDm = gatewayTelegramInvalidSenderTokens(user.telegram.allowFrom)
    if (invalidDm.size() > 0) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-allowfrom-nonnumeric",
            "warning",
            "failed",
            "Telegram DM allowFrom contains non-numeric sender ids.",
            invalidDm.toJsonString(),
            "Use numeric Telegram user ids, or supported prefixes telegram:/tg:/user: before a numeric id."
        )
    }

    let invalidGroup = gatewayTelegramInvalidSenderTokens(user.telegram.groupAllowFrom)
    if (invalidGroup.size() > 0) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-groupallowfrom-nonnumeric",
            "warning",
            "failed",
            "Telegram groupAllowFrom contains non-numeric sender ids.",
            invalidGroup.toJsonString(),
            "Use numeric Telegram user ids, or supported prefixes telegram:/tg:/user: before a numeric id."
        )
    }

    if (gatewayTelegramContainsWildcard(user.telegram.groupAllowFrom)) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-groupallowfrom-wildcard",
            "warning",
            "failed",
            "Telegram groupAllowFrom contains a wildcard.",
            "A wildcard allows every group sender through the gateway.",
            "Replace wildcard with explicit Telegram sender ids unless the group is intentionally public."
        )
    }

    let groupPolicy = user.telegram.groupPolicy.trimAscii().toAsciiLower()
    if (groupPolicy != "disabled" && groupPolicy != "open" &&
        user.telegram.groupAllowFrom.isEmpty() && user.telegram.allowFrom.isEmpty()) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-group-no-sender-allowlist",
            "warning",
            "failed",
            "Telegram group mode is enabled without a sender allowlist.",
            "groupPolicy=${user.telegram.groupPolicy}, groupAllowFrom and allowFrom are both empty.",
            "Configure gateway.telegram.groupAllowFrom or gateway.telegram.allowFrom for group ingress."
        )
    }

    gatewayTelegramAddFinding(
        findings,
        "telegram-curl-runtime-residual",
        "info",
        "passed",
        "Telegram runtime transport is native HTTP.",
        "No curl --config runtime mode is exposed by the Telegram transport diagnostics.",
        "Keep transport changes inside TelegramTransport and do not reintroduce curl process execution."
    )

    if (user.telegram.media.downloadEnabled && user.telegram.media.allowedMimes.isEmpty()) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-media-allowed-mimes-missing",
            "warning",
            "failed",
            "Telegram media download is enabled without an allowed MIME policy.",
            "gateway.telegram.media.allowedMimes is empty while downloads are enabled.",
            "Set allowedMimes to the smallest required MIME set, for example image/* or application/pdf."
        )
    }
    if (!user.telegram.actions.photo) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-vision-action-disabled",
            "info",
            "skipped",
            "Telegram photo sending is disabled.",
            "Inbound image media still gets a media-context block, but outbound photo actions are disabled.",
            "Enable gateway.telegram.actions.photo only when outbound photo delivery is required."
        )
    }
    if (!user.telegram.actions.voice && !user.telegram.actions.audio) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-asr-audio-actions-disabled",
            "info",
            "skipped",
            "Telegram audio/voice sending is disabled.",
            "Inbound voice/audio media still gets a transcription-eligible media-context block when received.",
            "Enable voice/audio actions only when outbound audio delivery is required."
        )
    }
    if (!user.telegram.actions.inlineKeyboard || !user.telegram.actions.callbackQuery) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-approval-resolver-ui-disabled",
            "warning",
            "failed",
            "Telegram approval resolver buttons are not fully enabled.",
            "approval resolver requires inlineKeyboard=true and callbackQuery=true.",
            "Enable gateway.telegram.actions.inlineKeyboard and gateway.telegram.actions.callbackQuery to resolve approval buttons from Telegram."
        )
    }
    if (!user.telegram.actions.editMessage || user.telegram.streaming.trimAscii().toAsciiLower() == "off") {
        gatewayTelegramAddFinding(
            findings,
            "telegram-streaming-draft-disabled",
            "info",
            "skipped",
            "Telegram streaming draft delivery is not fully enabled.",
            "editMessage=false or streaming=off makes long responses fall back to regular sendMessage delivery.",
            "Enable editMessage and keep streaming enabled when Telegram draft preview is desired."
        )
    }
    if (user.telegram.media.mediaMaxBytes <= 0) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-media-size-limit-missing",
            "warning",
            "failed",
            "Telegram media size limit is disabled.",
            "gateway.telegram.media.mediaMaxBytes must be positive for bounded media downloads.",
            "Set mediaMaxBytes to a bounded value."
        )
    }
    if (user.telegram.media.outboundAllowLocalPath && user.telegram.media.outboundLocalRoots.isEmpty()) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-media-local-roots-missing",
            "warning",
            "failed",
            "Telegram outbound local path upload is enabled without roots.",
            "gateway.telegram.media.outboundLocalRoots is empty.",
            "Configure explicit local roots or disable outboundAllowLocalPath."
        )
    }

    if (user.telegram.actions.deleteMessage || user.telegram.actions.createForumTopic ||
        user.telegram.actions.editForumTopic || user.telegram.media.outboundAllowLocalPath ||
        user.telegram.network.dangerouslyAllowPrivateNetwork) {
        let enabled = JsonArray([])
        if (user.telegram.actions.deleteMessage) { enabled.add(JsonString("deleteMessage")) }
        if (user.telegram.actions.createForumTopic) { enabled.add(JsonString("createForumTopic")) }
        if (user.telegram.actions.editForumTopic) { enabled.add(JsonString("editForumTopic")) }
        if (user.telegram.media.outboundAllowLocalPath) { enabled.add(JsonString("outboundAllowLocalPath")) }
        if (user.telegram.network.dangerouslyAllowPrivateNetwork) { enabled.add(JsonString("dangerouslyAllowPrivateNetwork")) }
        gatewayTelegramAddFinding(
            findings,
            "telegram-high-risk-actions-enabled",
            "warning",
            "failed",
            "Telegram high-risk actions are enabled.",
            enabled.toJsonString(),
            "Keep destructive or local-file/network expansion actions disabled unless they are explicitly needed."
        )
    }
    findings
}

private func gatewayTelegramDiagnosticsSummary(findings: JsonArray): JsonObject {
    var critical = 0
    var warning = 0
    var info = 0
    var failed = 0
    for (idx in 0..findings.size()) {
        let findingValue = findings[idx]
        let finding = try { findingValue.asObject() } catch (_e: Exception) { JsonObject() }
        let severity = gatewayTelegramDiagString(finding, "severity", "info")
        let status = gatewayTelegramDiagString(finding, "status", "")
        if (severity == "critical") {
            critical++
        } else if (severity == "warning") {
            warning++
        } else {
            info++
        }
        if (status == "failed") {
            failed++
        }
    }
    let out = JsonObject()
    out.put("kind", JsonString("telegram-diagnostics"))
    out.put("findingCount", findings.size().toJsonValue())
    out.put("criticalCount", critical.toJsonValue())
    out.put("warningCount", warning.toJsonValue())
    out.put("infoCount", info.toJsonValue())
    out.put("failedCount", failed.toJsonValue())
    out.put("healthy", (failed == 0).toJsonValue())
    out.put("transport", JsonString("native-http"))
    out.put("curlConfigRuntimeResidual", false.toJsonValue())
    return out
}

public func gatewayTelegramDiagnosticsJson(user: GatewayUserSettings, runtime!: JsonObject = JsonObject()): JsonObject {
    let findings = gatewayTelegramBuildDiagnosticFindings(user, runtime)
    let out = JsonObject()
    out.put("summary", gatewayTelegramDiagnosticsSummary(findings))
    out.put("findings", findings)
    out.put("checkedInputs", gatewayTelegramDiagArray([
        "token",
        "getMe",
        "webhook",
        "polling",
        "allowFrom",
        "groupAllowFrom",
        "media",
        "mediaUnderstanding",
        "approvalResolver",
        "streamingDraft",
        "directoryAggregation",
        "modelButtons",
        "actions",
        "transport"
    ]))
    return out
}

public func gatewayTelegramDiagnosticsActionsJson(diagnostics: JsonObject): JsonArray {
    let actions = JsonArray([])
    let findings = match (diagnostics.get("findings")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    for (idx in 0..findings.size()) {
        let findingValue = findings[idx]
        let finding = try { findingValue.asObject() } catch (_e: Exception) { JsonObject() }
        let status = gatewayTelegramDiagString(finding, "status", "")
        let severity = gatewayTelegramDiagString(finding, "severity", "info")
        if (status != "failed" || severity == "info") {
            continue
        }
        let action = JsonObject()
        action.put("action", JsonString("telegram-diagnostic-followup"))
        action.put("method", JsonString("channels.audit"))
        let params = JsonObject()
        params.put("channelId", JsonString("telegram"))
        action.put("params", params)
        action.put("findingId", finding.get("id") ?? JsonString(""))
        action.put("severity", JsonString(severity))
        action.put("summary", finding.get("summary") ?? JsonString(""))
        action.put("remediation", finding.get("remediation") ?? JsonString(""))
        action.put("policyState", JsonString("telegram-diagnostic-required"))
        actions.add(action)
    }
    return actions
}
