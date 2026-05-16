package metis.gateway.runtime

import magic.jsonable.*

import metis.core.{gatewayImageGenerationOutputRoot, gatewayImageGenerationResolveConfig, gatewayVideoGenerationOutputRoot, gatewayVideoGenerationResolveConfig}
import metis.core.config.GatewayUserSettings

import std.collection.ArrayList
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

private func gatewayTelegramDiagIntString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => v.toJsonString()
        case None => "0"
    }
}

private func gatewayTelegramDiagObject(obj: JsonObject, key: String): JsonObject {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayTelegramDiagArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayTelegramDiagProviderConfig(config: JsonObject, provider: String): JsonObject {
    if (provider.isEmpty()) {
        return JsonObject()
    }
    let providers = gatewayTelegramDiagObject(config, "providers")
    match (providers.get(provider)) {
        case Some(v) => try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
}

private func gatewayTelegramDiagStringFromPair(primary: JsonObject, secondary: JsonObject, key: String): String {
    let primaryValue = gatewayTelegramDiagString(primary, key, "")
    if (!primaryValue.isEmpty()) {
        return primaryValue
    }
    gatewayTelegramDiagString(secondary, key, "")
}

private func gatewayTelegramDiagBoolFromPair(primary: JsonObject, secondary: JsonObject, key: String, defaultValue: Bool): Bool {
    if (primary.get(key).isSome()) {
        return gatewayTelegramDiagBool(primary, key, defaultValue)
    }
    gatewayTelegramDiagBool(secondary, key, defaultValue)
}

private func gatewayTelegramVideoUnderstandingDiagnostics(user: GatewayUserSettings): JsonObject {
    let shared = user.media.video
    let telegram = user.telegram.video
    let provider = gatewayTelegramDiagStringFromPair(telegram, shared, "provider")
    let providerConfig = if (provider.isEmpty()) {
        JsonObject()
    } else {
        let telegramProvider = gatewayTelegramDiagProviderConfig(telegram, provider)
        if (telegramProvider.size() > 0) {
            telegramProvider
        } else {
            gatewayTelegramDiagProviderConfig(shared, provider)
        }
    }
    let model = gatewayTelegramDiagStringFromPair(
        providerConfig,
        telegram,
        "model"
    )
    let configured = !provider.isEmpty() && (providerConfig.size() > 0 || !model.isEmpty())
    let enabled = gatewayTelegramDiagBoolFromPair(telegram, shared, "enabled", true)
    let out = JsonObject()
    out.put("enabled", enabled.toJsonValue())
    out.put("configured", configured.toJsonValue())
    out.put("status", JsonString(if (!enabled) { "disabled" } else if (configured) { "configured" } else { "not_configured" }))
    out.put("provider", JsonString(provider))
    out.put("providerKind", JsonString(gatewayTelegramDiagString(providerConfig, "kind", "")))
    out.put("model", JsonString(if (model.isEmpty()) { gatewayTelegramDiagString(shared, "model", "") } else { model }))
    return out
}

private func gatewayTelegramVideoGenerationDiagnostics(user: GatewayUserSettings): JsonObject {
    let config = gatewayVideoGenerationResolveConfig(user, channel: "telegram")
    let provider = gatewayTelegramDiagString(config, "provider", "")
    let providerConfig = gatewayTelegramDiagProviderConfig(config, provider)
    let model = gatewayTelegramDiagString(providerConfig, "model", gatewayTelegramDiagString(config, "model", ""))
    let configured = !provider.isEmpty() && providerConfig.size() > 0
    let enabled = gatewayTelegramDiagBool(config, "enabled", true)
    let out = JsonObject()
    out.put("enabled", enabled.toJsonValue())
    out.put("configured", configured.toJsonValue())
    out.put("status", JsonString(if (!enabled) { "disabled" } else if (configured) { "configured" } else { "not_configured" }))
    out.put("provider", JsonString(provider))
    out.put("providerKind", JsonString(gatewayTelegramDiagString(providerConfig, "kind", "")))
    out.put("model", JsonString(model))
    out.put("outputRoot", JsonString(gatewayVideoGenerationOutputRoot(config)))
    return out
}

private func gatewayTelegramImageGenerationDiagnostics(user: GatewayUserSettings): JsonObject {
    let config = gatewayImageGenerationResolveConfig(user, channel: "telegram")
    let provider = gatewayTelegramDiagString(config, "provider", "")
    let providerConfig = gatewayTelegramDiagProviderConfig(config, provider)
    let model = gatewayTelegramDiagString(providerConfig, "model", gatewayTelegramDiagString(config, "model", ""))
    let configured = !provider.isEmpty() && providerConfig.size() > 0
    let enabled = gatewayTelegramDiagBool(config, "enabled", true)
    let out = JsonObject()
    out.put("enabled", enabled.toJsonValue())
    out.put("configured", configured.toJsonValue())
    out.put("status", JsonString(if (!enabled) { "disabled" } else if (configured) { "configured" } else { "not_configured" }))
    out.put("provider", JsonString(provider))
    out.put("providerKind", JsonString(gatewayTelegramDiagString(providerConfig, "kind", "")))
    out.put("model", JsonString(model))
    out.put("outputRoot", JsonString(gatewayImageGenerationOutputRoot(config)))
    out.put("photoActionEnabled", user.telegram.actions.photo.toJsonValue())
    return out
}

private func gatewayTelegramDiagArray(values: Array<String>): JsonArray {
    let out = JsonArray([])
    for (value in values) {
        out.add(JsonString(value))
    }
    out
}

private func gatewayTelegramAddUnique(values: ArrayList<String>, value: String): Unit {
    let normalized = value.trimAscii()
    if (!normalized.isEmpty() && !values.contains(normalized)) {
        values.add(normalized)
    }
}

private func gatewayTelegramDiagBoolStrict(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(v) => try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
}

private func gatewayTelegramDiagPeerKindFromBinding(binding: JsonObject): String {
    let matchObj = gatewayTelegramDiagObject(binding, "match")
    if (gatewayTelegramDiagString(matchObj, "channel", "").trimAscii().toAsciiLower() != "telegram") {
        return ""
    }
    let peer = gatewayTelegramDiagObject(matchObj, "peer")
    gatewayTelegramDiagString(peer, "kind", "").trimAscii().toAsciiLower()
}

private func gatewayTelegramDiagAddBindingPeerKind(peerKinds: ArrayList<String>, binding: JsonObject): Unit {
    let kind = gatewayTelegramDiagPeerKindFromBinding(binding)
    if (!kind.isEmpty()) {
        peerKinds.add(kind)
    }
}

private func gatewayTelegramDiagAddBindingArrayPeerKinds(peerKinds: ArrayList<String>, bindings: JsonArray): Unit {
    for (i in 0..bindings.size()) {
        let binding = try { bindings[i].asObject() } catch (_e: Exception) { JsonObject() }
        gatewayTelegramDiagAddBindingPeerKind(peerKinds, binding)
    }
}

private func gatewayTelegramDiagSelectedAgentIds(broadcast: JsonObject): Array<String> {
    for (key in ["members", "agentIds", "selectedMembers", "selected"]) {
        let arr = gatewayTelegramDiagArray(broadcast, key)
        if (arr.size() == 0) {
            continue
        }
        let out = ArrayList<String>()
        for (i in 0..arr.size()) {
            var agentId = ""
            try {
                agentId = arr[i].asString().getValue().trimAscii()
            } catch (_e: Exception) {
                let obj = try { arr[i].asObject() } catch (_e2: Exception) { JsonObject() }
                agentId = gatewayTelegramDiagString(obj, "agentId", gatewayTelegramDiagString(obj, "id", ""))
            }
            gatewayTelegramAddUnique(out, agentId)
        }
        return out.toArray()
    }
    []
}

private func gatewayTelegramDiagAddTeamArray(teams: ArrayList<JsonObject>, arr: JsonArray): Unit {
    for (i in 0..arr.size()) {
        let team = try { arr[i].asObject() } catch (_e: Exception) { JsonObject() }
        if (team.size() > 0) {
            teams.add(team)
        }
    }
}

private func gatewayTelegramDiagTeams(root: JsonObject): Array<JsonObject> {
    let teams = ArrayList<JsonObject>()
    gatewayTelegramDiagAddTeamArray(teams, gatewayTelegramDiagArray(gatewayTelegramDiagObject(root, "agentTeams"), "list"))
    match (root.get("teams")) {
        case Some(value) =>
            try {
                gatewayTelegramDiagAddTeamArray(teams, value.asArray())
            } catch (_e: Exception) {
                try {
                    gatewayTelegramDiagAddTeamArray(teams, gatewayTelegramDiagArray(value.asObject(), "list"))
                } catch (_e2: Exception) {
                    ()
                }
            }
        case None => ()
    }
    teams.toArray()
}

private func gatewayTelegramDiagRouteBroadcastReadiness(routeRoot: JsonObject): JsonObject {
    let out = JsonObject()
    let peerKinds = ArrayList<String>()
    let selectedAgentIds = ArrayList<String>()
    var broadcastTeamCount: Int64 = 0

    gatewayTelegramDiagAddBindingArrayPeerKinds(peerKinds, gatewayTelegramDiagArray(routeRoot, "bindings"))
    for (team in gatewayTelegramDiagTeams(routeRoot)) {
        gatewayTelegramDiagAddBindingArrayPeerKinds(peerKinds, gatewayTelegramDiagArray(team, "bindings"))
        let broadcast = gatewayTelegramDiagObject(team, "broadcast")
        gatewayTelegramDiagAddBindingArrayPeerKinds(peerKinds, gatewayTelegramDiagArray(broadcast, "bindings"))
        let matchObj = gatewayTelegramDiagObject(broadcast, "match")
        if (matchObj.size() > 0) {
            let synthetic = JsonObject()
            synthetic.put("match", matchObj)
            gatewayTelegramDiagAddBindingPeerKind(peerKinds, synthetic)
        }
        if (gatewayTelegramDiagBoolStrict(broadcast, "enabled")) {
            let selected = gatewayTelegramDiagSelectedAgentIds(broadcast)
            if (selected.size > 0) {
                broadcastTeamCount += 1
                for (agentId in selected) {
                    gatewayTelegramAddUnique(selectedAgentIds, agentId)
                }
            }
        }
    }

    var privateBindingCount: Int64 = 0
    var groupBindingCount: Int64 = 0
    var topicBindingCount: Int64 = 0
    for (kind in peerKinds.toArray()) {
        if (kind == "direct" || kind == "private" || kind == "user") {
            privateBindingCount += 1
        } else if (kind == "group" || kind == "supergroup") {
            groupBindingCount += 1
        } else if (kind == "topic" || kind == "thread") {
            topicBindingCount += 1
        }
    }

    let missing = ArrayList<String>()
    if (privateBindingCount == 0) { missing.add("private-binding") }
    if (groupBindingCount == 0) { missing.add("group-binding") }
    if (topicBindingCount == 0) { missing.add("topic-binding") }
    if (broadcastTeamCount == 0 || selectedAgentIds.size == 0) { missing.add("team-broadcast-selected-members") }

    let rootPresent = routeRoot.size() > 0
    let liveReady = rootPresent && missing.size == 0
    out.put("status", JsonString(if (!rootPresent) { "skipped" } else if (liveReady) { "passed" } else { "failed" }))
    out.put("liveReady", liveReady.toJsonValue())
    out.put("redacted", true.toJsonValue())
    out.put("privateBindingCount", privateBindingCount.toJsonValue())
    out.put("groupBindingCount", groupBindingCount.toJsonValue())
    out.put("topicBindingCount", topicBindingCount.toJsonValue())
    out.put("broadcastTeamCount", broadcastTeamCount.toJsonValue())
    out.put("selectedMemberCount", selectedAgentIds.size.toJsonValue())
    out.put("selectedAgentIds", gatewayTelegramDiagArray(selectedAgentIds.toArray()))
    out.put("missingRequirements", gatewayTelegramDiagArray(missing.toArray()))
    out.put("requiredPeerKinds", gatewayTelegramDiagArray(["private", "group", "topic"]))
    out.put("broadcastEvidenceFields", gatewayTelegramDiagArray([
        "teamId",
        "selectedAgentIds",
        "agents[].agentId",
        "agents[].sessionKey",
        "agents[].deliveryStatus",
        "agents[].deliveryMessageId",
        "answer"
    ]))
    out
}

private func gatewayTelegramDiagMissingRequirementsString(readiness: JsonObject): String {
    match (readiness.get("missingRequirements")) {
        case Some(value) => value.toJsonString()
        case None => "[]"
    }
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

private func gatewayTelegramApiRootRisk(user: GatewayUserSettings): String {
    let root = user.telegram.apiRoot.trimAscii().toAsciiLower()
    if (root.isEmpty() || root == "https://api.telegram.org" || root.startsWith("https://api.telegram.org/")) {
        return ""
    }
    if (!root.startsWith("https://") && !user.telegram.network.dangerouslyAllowPrivateNetwork) {
        return "non_https_custom_api_root"
    }
    if ((root.contains("127.0.0.1") || root.contains("localhost") || root.contains("0.0.0.0") || root.contains("10.") || root.contains("192.168.") || root.contains("172.16.")) &&
        !user.telegram.network.dangerouslyAllowPrivateNetwork) {
        return "private_custom_api_root"
    }
    "custom_api_root"
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

private func gatewayTelegramRuntimeMembershipSummary(runtime: JsonObject): (String, String) {
    let liveProbe = gatewayTelegramDiagObject(runtime, "liveProbe")
    let snapshot = gatewayTelegramDiagObject(liveProbe, "snapshot")
    let membership = gatewayTelegramDiagObject(snapshot, "membership")
    let status = gatewayTelegramDiagString(membership, "status", "")
    if (status.isEmpty()) {
        return ("skipped", "membership probe has not run")
    }
    let probes = match (membership.get("probes")) {
        case Some(v) => try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    if (probes.size() == 0) {
        return (status, gatewayTelegramDiagString(membership, "reason", "no configured group targets"))
    }
    var warnings: Int64 = 0
    var errors: Int64 = 0
    var healthy: Int64 = 0
    for (idx in 0..probes.size()) {
        let probe = try { probes[idx].asObject() } catch (_e: Exception) { JsonObject() }
        if (gatewayTelegramDiagBool(probe, "healthy", false)) {
            healthy += 1
        } else if (gatewayTelegramDiagBool(probe, "warning", false)) {
            warnings += 1
        } else {
            errors += 1
        }
    }
    if (errors > 0) {
        return ("failed", "membership probes healthy=${healthy}, warnings=${warnings}, errors=${errors}")
    }
    if (warnings > 0) {
        return ("warning", "membership probes healthy=${healthy}, warnings=${warnings}, errors=${errors}")
    }
    ("passed", "membership probes healthy=${healthy}, warnings=0, errors=0")
}

private func gatewayTelegramBuildDiagnosticFindings(user: GatewayUserSettings, runtime: JsonObject, routeRoot: JsonObject): JsonArray {
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

    let membership = gatewayTelegramRuntimeMembershipSummary(runtime)
    gatewayTelegramAddFinding(
        findings,
        "telegram-membership-probe",
        if (membership[0] == "failed") { "warning" } else { "info" },
        membership[0],
        "Telegram live membership probe is reported by doctor.",
        membership[1],
        "Run live channel diagnostics with a mocked or trusted Bot API path; verify getChatMember status for configured groups."
    )

    let routeReadiness = gatewayTelegramDiagRouteBroadcastReadiness(routeRoot)
    let routeStatus = gatewayTelegramDiagString(routeReadiness, "status", "skipped")
    gatewayTelegramAddFinding(
        findings,
        "telegram-route-broadcast-live-ready",
        if (routeStatus == "failed") { "warning" } else { "info" },
        routeStatus,
        "Telegram route and team broadcast live-readiness preflight is explicit.",
        "privateBindingCount=${gatewayTelegramDiagIntString(routeReadiness, "privateBindingCount")}, groupBindingCount=${gatewayTelegramDiagIntString(routeReadiness, "groupBindingCount")}, topicBindingCount=${gatewayTelegramDiagIntString(routeReadiness, "topicBindingCount")}, broadcastTeamCount=${gatewayTelegramDiagIntString(routeReadiness, "broadcastTeamCount")}, selectedMemberCount=${gatewayTelegramDiagIntString(routeReadiness, "selectedMemberCount")}, missingRequirements=${gatewayTelegramDiagMissingRequirementsString(routeReadiness)}.",
        "Before live M12-M14, configure one Telegram private binding, one group binding, one topic binding, and one enabled team broadcast with selected members."
    )

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
    gatewayTelegramAddFinding(
        findings,
        "telegram-media-understanding-runtime",
        "info",
        "passed",
        "Telegram media understanding runtime is wired through Gateway mediaContext.",
        "Image/sticker/audio/video/document understanding uses downloaded localPath plus configured/companion runtime output; missing providers return explicit not_configured or metadata_only states.",
        "Configure ASR/vision/video/document providers or companion extraction files when automatic understanding is required."
    )
    let videoUnderstanding = gatewayTelegramVideoUnderstandingDiagnostics(user)
    gatewayTelegramAddFinding(
        findings,
        "telegram-video-understanding-config",
        "info",
        gatewayTelegramDiagString(videoUnderstanding, "status", "not_configured"),
        "Telegram video understanding provider status is explicit.",
        "videoUnderstanding=${gatewayTelegramDiagString(videoUnderstanding, "status", "not_configured")}, enabled=${gatewayTelegramDiagBool(videoUnderstanding, "enabled", true)}, configured=${gatewayTelegramDiagBool(videoUnderstanding, "configured", false)}, provider=${gatewayTelegramDiagString(videoUnderstanding, "provider", "")}, kind=${gatewayTelegramDiagString(videoUnderstanding, "providerKind", "")}, model=${gatewayTelegramDiagString(videoUnderstanding, "model", "")}.",
        "Configure gateway.media.video or gateway.telegram.video when native video understanding should call a provider; companion files still work without provider configuration."
    )
    let videoGeneration = gatewayTelegramVideoGenerationDiagnostics(user)
    gatewayTelegramAddFinding(
        findings,
        "telegram-video-generation-config",
        "info",
        gatewayTelegramDiagString(videoGeneration, "status", "not_configured"),
        "Telegram video generation provider status is explicit.",
        "enabled=${gatewayTelegramDiagBool(videoGeneration, "enabled", true)}, configured=${gatewayTelegramDiagBool(videoGeneration, "configured", false)}, provider=${gatewayTelegramDiagString(videoGeneration, "provider", "")}, model=${gatewayTelegramDiagString(videoGeneration, "model", "")}, outputRoot=${gatewayTelegramDiagString(videoGeneration, "outputRoot", "")}.",
        "Configure gateway.media.videoGeneration or gateway.telegram.videoGeneration before using gateway_video_generate in Telegram turns."
    )
    let imageGeneration = gatewayTelegramImageGenerationDiagnostics(user)
    gatewayTelegramAddFinding(
        findings,
        "telegram-image-generation-config",
        "info",
        gatewayTelegramDiagString(imageGeneration, "status", "not_configured"),
        "Telegram image generation provider status is explicit.",
        "enabled=${gatewayTelegramDiagBool(imageGeneration, "enabled", true)}, configured=${gatewayTelegramDiagBool(imageGeneration, "configured", false)}, provider=${gatewayTelegramDiagString(imageGeneration, "provider", "")}, model=${gatewayTelegramDiagString(imageGeneration, "model", "")}, outputRoot=${gatewayTelegramDiagString(imageGeneration, "outputRoot", "")}, photoActionEnabled=${gatewayTelegramDiagBool(imageGeneration, "photoActionEnabled", false)}.",
        "Configure gateway.media.imageGeneration or gateway.telegram.imageGeneration before using gateway_image_generate in Telegram turns; enable gateway.telegram.actions.photo for automatic photo delivery."
    )
    gatewayTelegramAddFinding(
        findings,
        "telegram-native-command-dispatch",
        "info",
        "passed",
        "Telegram native commands are handled before the ReAct/model path.",
        "/help, /status, /models, /subagents, /sessions, /approvals, /activation, and /pair have deterministic GatewayService/RPC handling.",
        "Keep Telegram menu commands aligned with GatewayService native dispatch."
    )
    gatewayTelegramAddFinding(
        findings,
        "telegram-target-writeback-policy",
        "info",
        "passed",
        "Telegram target writeback remains permission-gated.",
        "Read-only target list/resolve/send tools are available; configuration writeback must stay behind admin/operator scopes and Gateway RPC mutation policy.",
        "Do not allow ordinary Telegram chat turns to mutate metis.json directly."
    )
    gatewayTelegramAddFinding(
        findings,
        "telegram-thread-binding-manager",
        "info",
        if (user.telegram.threadBindings.enabled) { "passed" } else { "skipped" },
        "Telegram thread binding manager state is explicit.",
        "threadBindings.enabled=${user.telegram.threadBindings.enabled}, spawnSubagentSessions=${user.telegram.threadBindings.spawnSubagentSessions}, spawnAcpSessions=${user.telegram.threadBindings.spawnAcpSessions}.",
        "Enable threadBindings only when Telegram forum/topic session binding is required."
    )
    gatewayTelegramAddFinding(
        findings,
        "telegram-chat-action-backoff",
        "info",
        "passed",
        "Telegram chat action failures are bounded by runtime backoff.",
        "sendChatAction 401/403 failures stop repeated chat-action attempts for the current adapter instance.",
        "Inspect adapter lastSendError/runtime state if typing indicators stop after authorization failures."
    )
    if (user.telegram.webhookMaxBodyBytes <= 0) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-webhook-body-limit-missing",
            "warning",
            "failed",
            "Telegram webhook body size limit is disabled.",
            "gateway.telegram.webhookMaxBodyBytes must be positive for bounded webhook intake.",
            "Set webhookMaxBodyBytes to a bounded value such as 1048576."
        )
    }
    if (user.telegram.webhookRateLimitWindowMs <= 0 || user.telegram.webhookRateLimitMaxRequests <= 0) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-webhook-rate-limit-missing",
            "warning",
            "failed",
            "Telegram webhook rate limit is disabled.",
            "gateway.telegram.webhookRateLimitWindowMs and webhookRateLimitMaxRequests must both be positive.",
            "Set webhookRateLimitWindowMs and webhookRateLimitMaxRequests to bounded values."
        )
    }
    if (!user.telegram.webhookUrl.trimAscii().isEmpty() && user.telegram.webhookSecret.trimAscii().isEmpty()) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-webhook-secret-missing",
            "warning",
            "failed",
            "Telegram webhook mode is enabled without a secret token.",
            "gateway.telegram.webhookUrl is configured but webhookSecret is empty.",
            "Set gateway.telegram.webhookSecret and keep it out of chat-visible outputs."
        )
    }
    if (!user.telegram.webhookCertPath.trimAscii().isEmpty()) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-webhook-cert-configured",
            "info",
            "passed",
            "Telegram webhook certificate upload is configured.",
            "gateway.telegram.webhookCertPath is set; setWebhook will use multipart certificate upload.",
            "Keep the certificate path readable by the Gateway process and outside chat-visible outputs."
        )
    }
    if (!user.telegram.configWrites) {
        gatewayTelegramAddFinding(
            findings,
            "telegram-config-writes-disabled",
            "info",
            "passed",
            "Telegram config writes are disabled.",
            "gateway.telegram.configWrites=false prevents Telegram callbacks such as /models selection from mutating metis.json.",
            "Enable configWrites only if Telegram operators are allowed to change Gateway settings."
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
    let apiRootRisk = gatewayTelegramApiRootRisk(user)
    if (apiRootRisk == "non_https_custom_api_root" || apiRootRisk == "private_custom_api_root") {
        gatewayTelegramAddFinding(
            findings,
            "telegram-custom-api-root-risk",
            "warning",
            "failed",
            "Telegram custom apiRoot requires an explicit network trust decision.",
            "apiRoot=${user.telegram.apiRoot.trimAscii()}, risk=${apiRootRisk}.",
            "Use https://api.telegram.org or set gateway.telegram.network.dangerouslyAllowPrivateNetwork only for a trusted local/self-hosted Bot API endpoint."
        )
    } else if (apiRootRisk == "custom_api_root") {
        gatewayTelegramAddFinding(
            findings,
            "telegram-custom-api-root",
            "info",
            "passed",
            "Telegram custom apiRoot is configured.",
            "apiRoot is not the default Telegram Bot API endpoint; file downloads and Bot API calls remain routed through TelegramTransport with token redaction.",
            "Keep custom endpoints trusted and avoid logging raw Bot API URLs."
        )
    }
    let dnsOrder = user.telegram.network.dnsResultOrder.trimAscii().toAsciiLower()
    if (!dnsOrder.isEmpty() && dnsOrder != "ipv4first") {
        gatewayTelegramAddFinding(
            findings,
            "telegram-network-dns-result-order",
            "info",
            "passed",
            "Telegram native transport received a custom DNS result order setting.",
            "gateway.telegram.network.dnsResultOrder=${dnsOrder}; stdx DNS selection is still constrained by the Cangjie native socket resolver.",
            "Use ipv4first when local networks prefer IPv4 proxy paths; keep this setting documented in gateway doctor output."
        )
    }
    gatewayTelegramAddFinding(
        findings,
        "telegram-network-env-proxy",
        "info",
        if (user.telegram.network.envProxyEnabled) { "passed" } else { "skipped" },
        "Telegram env proxy fallback is explicit.",
        "gateway.telegram.network.envProxyEnabled=${user.telegram.network.envProxyEnabled}; explicit gateway.telegram.proxy still has priority when configured.",
        "Enable envProxyEnabled only when this host intentionally routes Telegram Bot API traffic through HTTPS_PROXY/HTTP_PROXY."
    )
    gatewayTelegramAddFinding(
        findings,
        "telegram-group-history-silent-ingest",
        "info",
        if (user.telegram.groupHistoryEnabled) { "passed" } else { "skipped" },
        "Telegram group silent ingest history is explicit.",
        "groupHistoryEnabled=${user.telegram.groupHistoryEnabled}, groupHistoryLimit=${user.telegram.groupHistoryLimit}. Non-mentioned group messages may be recorded as bounded context without triggering an agent turn.",
        "Keep groupHistoryLimit bounded; disable groupHistoryEnabled if silent group context should not be retained."
    )

    if (user.telegram.actions.deleteMessage || user.telegram.actions.pinMessage || user.telegram.actions.unpinMessage || user.telegram.actions.createForumTopic ||
        user.telegram.actions.editForumTopic || user.telegram.media.outboundAllowLocalPath ||
        user.telegram.network.dangerouslyAllowPrivateNetwork) {
        let enabled = JsonArray([])
        if (user.telegram.actions.deleteMessage) { enabled.add(JsonString("deleteMessage")) }
        if (user.telegram.actions.pinMessage) { enabled.add(JsonString("pinMessage")) }
        if (user.telegram.actions.unpinMessage) { enabled.add(JsonString("unpinMessage")) }
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

public func gatewayTelegramDiagnosticsJson(user: GatewayUserSettings, runtime!: JsonObject = JsonObject(), routeRoot!: JsonObject = JsonObject()): JsonObject {
    let findings = gatewayTelegramBuildDiagnosticFindings(user, runtime, routeRoot)
    let routeReadiness = gatewayTelegramDiagRouteBroadcastReadiness(routeRoot)
    let out = JsonObject()
    out.put("summary", gatewayTelegramDiagnosticsSummary(findings))
    out.put("findings", findings)
    out.put("videoUnderstanding", gatewayTelegramVideoUnderstandingDiagnostics(user))
    out.put("videoGeneration", gatewayTelegramVideoGenerationDiagnostics(user))
    out.put("imageGeneration", gatewayTelegramImageGenerationDiagnostics(user))
    out.put("routeBroadcastReadiness", routeReadiness)
    out.put("checkedInputs", gatewayTelegramDiagArray([
        "token",
        "getMe",
        "webhook",
        "webhookGuard",
        "polling",
        "allowFrom",
        "groupAllowFrom",
        "media",
        "mediaUnderstanding",
        "asr",
        "vision",
        "videoUnderstanding",
        "videoGeneration",
        "imageGeneration",
        "documentExtract",
        "nativeCommands",
        "approvalResolver",
        "streamingDraft",
        "membership",
        "threadBindings",
        "groupHistory",
        "routeBindingPreflight",
        "teamBroadcast",
        "targetWriteback",
        "chatActionBackoff",
        "directoryAggregation",
        "modelButtons",
        "configWrites",
        "webhookCertPath",
        "envProxy",
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
