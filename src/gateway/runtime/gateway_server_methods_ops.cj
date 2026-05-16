package metis.gateway.runtime

import magic.jsonable.*

import metis.core.config.{CliConfig, GatewayUserSettings, MetisConfigManager, MetisPaths}
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.core.gatewayAgentTeamDoctorScan
import metis.gateway.model.GatewayConfig
import metis.core.model.CliModelManager

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Directory, File, exists}
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func gatewayOpsStringParam(request: GatewayRpcRequest, keys: Array<String>, defaultValue: String): String {
    for (key in keys) {
        match (request.params.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        return value
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    defaultValue
}

private func gatewayOpsJsonString(obj: JsonObject, key: String, defaultValue: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue().trimAscii() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayOpsJsonBool(obj: JsonObject, key: String, defaultValue: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayOpsJsonInt(obj: JsonObject, key: String, defaultValue: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { defaultValue }
        case None => defaultValue
    }
}

private func gatewayTransportContext(request: GatewayRpcRequest, user: GatewayUserSettings): (String, String) {
    let requestPreferred = request.transport.trimAscii().toAsciiLower()
    let requestGatewayUrl = request.gatewayUrl.trimAscii()
    if ((requestPreferred == "remote" || requestPreferred == "http" || requestPreferred == "https") &&
        !requestGatewayUrl.isEmpty()) {
        return ("remote", requestGatewayUrl)
    }
    let preferred = gatewayPreferredTransportFromSettings(user)
    let gatewayUrl = gatewayPreferredGatewayUrlFromSettings(user)
    (preferred, gatewayUrl)
}

private func gatewayJsonArraySize(value: JsonValue): Int64 {
    try {
        Int64(value.asArray().size())
    } catch (_e: Exception) {
        0
    }
}

private func gatewayOpsServerRuntime(): JsonObject {
    gatewayServerRuntimeSnapshot()
}

private func gatewayOpsServerRuntimeArray(runtime: JsonObject, key: String): JsonArray {
    match (runtime.get(key)) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func gatewayOpsConfig(user: GatewayUserSettings): GatewayConfig {
    buildGatewayConfigFromUserSettings(user)
}

private func gatewayOpsPlatform(cfg: GatewayConfig): JsonObject {
    gatewayPlatformSnapshot(cfg)
}

private func gatewayOpsHttp(cfg: GatewayConfig): JsonObject {
    GatewayHttpSurface.snapshot(cfg)
}

private func gatewayOpsControlUi(cfg: GatewayConfig): JsonObject {
    gatewayControlUiRuntimeStatusJson(cfg)
}

private func gatewayProbeChecksJson(user: GatewayUserSettings): JsonArray {
    let checks = JsonArray([])
    let rpc = gatewayServerRuntimeSnapshot()
    let transport = gatewayTransportRuntimeSnapshot(user)
    let cfg = gatewayOpsConfig(user)
    let http = gatewayOpsHttp(cfg)
    let controlUi = gatewayOpsControlUi(cfg)

    let master = JsonObject()
    master.put("name", JsonString("gateway.master"))
    master.put("ok", user.enabled.toJsonValue())
    master.put("detail", JsonString(if (user.enabled) { "enabled" } else { "disabled" }))
    checks.add(master)

    let channels = JsonObject()
    channels.put("name", JsonString("gateway.channels"))
    channels.put("ok", gatewayHasAnyEnabledChannel(user).toJsonValue())
    channels.put("detail", JsonString(if (gatewayHasAnyEnabledChannel(user)) { "at least one enabled channel" } else { "no enabled channels" }))
    checks.add(channels)

    let rpcCheck = JsonObject()
    rpcCheck.put("name", JsonString("gateway.rpc"))
    rpcCheck.put("ok", (rpc.get("serverStarted") ?? false.toJsonValue()))
    rpcCheck.put("detail", JsonString("protocol/runtime available"))
    checks.add(rpcCheck)

    let transportCheck = JsonObject()
    transportCheck.put("name", JsonString("gateway.transport"))
    transportCheck.put("ok", true.toJsonValue())
    transportCheck.put("detail", JsonString("preferred=" + gatewayPreferredTransportFromSettings(user)))
    transportCheck.put("runtime", transport)
    checks.add(transportCheck)

    let httpCheck = JsonObject()
    httpCheck.put("name", JsonString("gateway.http"))
    httpCheck.put("ok", (http.get("started") ?? false.toJsonValue()))
    httpCheck.put("detail", JsonString("http surface"))
    checks.add(httpCheck)

    let controlUiCheck = JsonObject()
    let controlUiEnabled = match (controlUi.get("controlUi")) {
        case Some(v) =>
            try {
                let obj = v.asObject()
                match (obj.get("enabled")) {
                    case Some(flag) =>
                        try { flag.asBool().getValue() } catch (_inner: Exception) { false }
                    case None => false
                }
            } catch (_e: Exception) {
                false
            }
        case None => false
    }
    controlUiCheck.put("name", JsonString("gateway.control_ui"))
    controlUiCheck.put("ok", controlUiEnabled.toJsonValue())
    controlUiCheck.put("detail", JsonString("control-ui runtime"))
    checks.add(controlUiCheck)
    checks
}

private func gatewayProbeIssuesJson(user: GatewayUserSettings, checks: JsonArray): JsonArray {
    let issues = JsonArray([])
    let cfg = gatewayOpsConfig(user)
    if (!user.enabled) {
        let issue = JsonObject()
        issue.put("code", JsonString("gateway-disabled"))
        issue.put("severity", JsonString("warning"))
        issue.put("message", JsonString("Gateway master switch is disabled."))
        issues.add(issue)
    }
    if (!gatewayHasAnyEnabledChannel(user)) {
        let issue = JsonObject()
        issue.put("code", JsonString("no-enabled-channel"))
        issue.put("severity", JsonString("error"))
        issue.put("message", JsonString("No enabled gateway channels are configured."))
        issues.add(issue)
    }
    if (user.remote.enabled && user.remote.url.trimAscii().isEmpty()) {
        let issue = JsonObject()
        issue.put("code", JsonString("remote-url-missing"))
        issue.put("severity", JsonString("error"))
        issue.put("message", JsonString("Gateway remote mode is enabled but remote.url is empty."))
        issues.add(issue)
    }
    if (cfg.controlUi.allowInsecureAuth) {
        let issue = JsonObject()
        issue.put("code", JsonString("control-ui-insecure-auth"))
        issue.put("severity", JsonString("warning"))
        issue.put("message", JsonString("Control UI allows insecure auth."))
        issues.add(issue)
    }
    if (cfg.controlUi.dangerouslyDisableDeviceAuth) {
        let issue = JsonObject()
        issue.put("code", JsonString("device-auth-disabled"))
        issue.put("severity", JsonString("warning"))
        issue.put("message", JsonString("Control UI device auth is disabled."))
        issues.add(issue)
    }
    let controlUiRootState = gatewayControlUiRootStateJson(cfg)
    let assetMode = match (gatewayControlUiSnapshotJson(cfg).get("assetMode")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "inline-fallback" }
        case None => "inline-fallback"
    }
    let rootKind = match (controlUiRootState.get("kind")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    let rootMessage = match (controlUiRootState.get("message")) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
    if (assetMode == "inline-fallback") {
        let issue = JsonObject()
        issue.put("code", JsonString("control-ui-inline-fallback"))
        issue.put("severity", JsonString("warning"))
        issue.put("message", JsonString("Control UI is running in legacy inline fallback mode. Restore bundled static assets or configure gateway.controlUi.root with a built static UI directory for the formal production path."))
        issues.add(issue)
    } else if (rootKind != "resolved" && rootKind != "bundled") {
        let issue = JsonObject()
        issue.put("code", JsonString("control-ui-root-invalid"))
        issue.put("severity", JsonString("error"))
        issue.put("message", JsonString(if (rootMessage.trimAscii().isEmpty()) { "Configured Control UI root is not serving static assets." } else { rootMessage }))
        issues.add(issue)
    }
    for (i in 0..checks.size()) {
        let item = checks[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let ok = match (obj.get("ok")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_inner: Exception) { true }
            case None => true
        }
        if (!ok) {
            let issue = JsonObject()
            let checkName = match (obj.get("name")) {
                case Some(v) =>
                    try { v.asString().getValue() } catch (_inner: Exception) { "check" }
                case None => "check"
            }
            let detail = obj.get("detail") ?? JsonString("")
            issue.put("code", JsonString(checkName + "-failed"))
            issue.put("severity", JsonString("warning"))
            issue.put("check", JsonString(checkName))
            issue.put("message", detail)
            issues.add(issue)
        }
    }
    issues
}

private func gatewayProbeSummaryJson(checks: JsonArray, issues: JsonArray): JsonObject {
    let summary = JsonObject()
    summary.put("checkCount", checks.size().toJsonValue())
    summary.put("issueCount", issues.size().toJsonValue())
    summary.put("ok", (issues.size() == 0).toJsonValue())
    summary
}

private func gatewayProbeActionsJson(user: GatewayUserSettings, issues: JsonArray): JsonArray {
    let actions = JsonArray([])
    for (i in 0..issues.size()) {
        let item = issues[i]
        let issue = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let code = gatewayOpsJsonString(issue, "code", "")
        let action = JsonObject()
        action.put("issueCode", JsonString(code))
        action.put("severity", issue.get("severity") ?? JsonString("warning"))
        action.put("policyState", JsonString("inspection"))
        let constraints = JsonArray([])
        let issuePresent = JsonObject()
        issuePresent.put("name", JsonString("issue-present"))
        issuePresent.put("satisfied", true.toJsonValue())
        issuePresent.put("detail", JsonString("issue is currently present"))
        constraints.add(issuePresent)
        action.put("constraints", constraints)
        match (code) {
            case "gateway-disabled" =>
                action.put("action", JsonString("enable-master"))
                action.put("method", JsonString("master_on"))
                action.put("policyState", JsonString("master-disabled"))
            case "no-enabled-channel" =>
                action.put("action", JsonString("configure-channel"))
                action.put("method", JsonString("channels.bindings"))
                let params = JsonObject()
                params.put("channelId", JsonString("feishu"))
                action.put("params", params)
                action.put("policyState", JsonString("channel-required"))
            case "remote-url-missing" =>
                action.put("action", JsonString("set-remote-url"))
                action.put("method", JsonString("config.get"))
                action.put("policyState", JsonString("remote-misconfigured"))
            case "control-ui-insecure-auth" =>
                action.put("action", JsonString("tighten-control-ui-auth"))
                action.put("method", JsonString("control_ui.origin_policy"))
                action.put("policyState", JsonString("auth-relaxed"))
            case "device-auth-disabled" =>
                action.put("action", JsonString("re-enable-device-auth"))
                action.put("method", JsonString("devices.policy"))
                action.put("policyState", JsonString("device-auth-relaxed"))
            case _ =>
                action.put("action", JsonString("inspect"))
                action.put("method", JsonString("probe"))
                action.put("policyState", JsonString("inspect"))
        }
        actions.add(action)
    }
    if (actions.size() == 0) {
        let action = JsonObject()
        action.put("action", JsonString("healthy"))
        action.put("method", JsonString("doctor"))
        action.put("ready", (user.enabled && gatewayHasAnyEnabledChannel(user)).toJsonValue())
        action.put("policyState", JsonString("healthy"))
        action.put("constraints", JsonArray([]))
        actions.add(action)
    }
    actions
}

private func gatewayDoctorActionsJson(user: GatewayUserSettings, checks: JsonArray, issues: JsonArray, routeRoot!: JsonObject = JsonObject()): JsonArray {
    let actions = gatewayProbeActionsJson(user, issues)
    let telegramActions = gatewayTelegramDiagnosticsActionsJson(gatewayTelegramDiagnosticsJson(user, routeRoot: routeRoot))
    for (idx in 0..telegramActions.size()) {
        actions.add(telegramActions[idx])
    }
    let cfg = gatewayOpsConfig(user)
    let audits = [
        gatewayNodeSchedulingAuditSummary(cfg),
        gatewayDeviceApprovalAuditSummary(cfg),
        gatewayPushOrchestrationAuditSummary(cfg)
    ]
    for (audit in audits) {
        let actionsNeeded = match (audit.get("actionsNeeded")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        if (!actionsNeeded) {
            continue
        }
        let action = JsonObject()
        action.put("action", JsonString("audit-followup"))
        action.put("auditState", audit.get("auditState") ?? JsonString(""))
        action.put("audit", audit)
        action.put("policyState", audit.get("auditState") ?? JsonString("audit"))
        let constraints = JsonArray([])
        let auditNeeded = JsonObject()
        auditNeeded.put("name", JsonString("audit-actions-needed"))
        auditNeeded.put("satisfied", false.toJsonValue())
        auditNeeded.put("detail", JsonString("audit indicates follow-up work is required"))
        constraints.add(auditNeeded)
        action.put("constraints", constraints)
        let params = JsonObject()
        let auditKind = gatewayOpsJsonString(audit, "auditKind", "")
        if (auditKind == "node-scheduling") {
            action.put("method", JsonString("nodes.policy.audit"))
        } else if (auditKind == "device-approval") {
            action.put("method", JsonString("devices.policy.audit"))
        } else if (auditKind == "push-orchestration") {
            action.put("method", JsonString("push.orchestration.audit"))
        } else {
            action.put("method", JsonString("doctor"))
        }
        action.put("params", params)
        actions.add(action)
    }
    let summary = gatewayProbeSummaryJson(checks, issues)
    if (gatewayOpsJsonString(summary, "ok", "") == "") {
        ()
    }
    return actions
}

private func gatewayActionEnvelope(actions: JsonArray, policyState: String, remediationState: String): JsonObject {
    let constraints = JsonArray([])
    let hasActions = JsonObject()
    hasActions.put("name", JsonString("remediation-actions"))
    hasActions.put("satisfied", (actions.size() > 0).toJsonValue())
    hasActions.put("detail", JsonString("actions=${actions.size()}"))
    constraints.add(hasActions)
    let issueCodes = JsonArray([])
    for (i in 0..actions.size()) {
        let action = try {
            actions[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        match (action.get("issueCode")) {
            case Some(v) => issueCodes.add(v)
            case None => ()
        }
    }
    let result = JsonObject()
    result.put("policyState", JsonString(policyState))
    result.put("remediationState", JsonString(remediationState))
    result.put("actionsNeeded", actions.size().toJsonValue())
    result.put("blockingCount", actions.size().toJsonValue())
    result.put("issueCodes", issueCodes)
    result.put("constraints", constraints)
    result.put("actions", actions)
    result
}

private func gatewayRecentLogFiles(limit: Int64): JsonArray {
    let rows = ArrayList<String>()
    if (exists(CliConfig.logsDir)) {
        for (entry in Directory.readFrom(CliConfig.logsDir)) {
            if (!entry.isDirectory()) {
                rows.add(entry.name)
            }
        }
    }
    let out = JsonArray([])
    let names = rows.toArray()
    if (names.isEmpty()) {
        return out
    }
    var count: Int64 = 0
    for (idx in names.size - 1..=-1:-1) {
        if (count >= limit) {
            break
        }
        out.add(JsonString(names[idx]))
        count += 1
    }
    out
}

private func gatewayModelsStatusJson(): JsonObject {
    let result = JsonObject()
    result.put("primary", JsonString(CliConfig.model))
    match (CliConfig.fastModel) {
        case Some(v) => result.put("fast", JsonString(v))
        case None => result.put("fast", JsonString(""))
    }
    result.put("fallbacks", CliConfig.fallbackModels.toJsonValue())
    let candidates = JsonArray([])
    for (model in CliModelManager.getAllModels()) {
        candidates.add(JsonString(model.fullName))
    }
    result.put("candidateOrder", candidates)
    result
}

private func gatewayOpsRawConfigReadOnly(): JsonObject {
    match (MetisConfigManager.rawConfig()) {
        case Some(root) =>
            try {
                return JsonValue.fromStr(root.toJsonString()).asObject()
            } catch (_: Exception) {
                return JsonObject()
            }
        case None => JsonObject()
    }
}

private func gatewayOpsAgentTeamDiagnosticsJson(routeRoot!: JsonObject = JsonObject()): JsonObject {
    let root = if (routeRoot.size() > 0) { routeRoot } else { gatewayOpsRawConfigReadOnly() }
    gatewayAgentTeamDoctorScan(root, homeRoot: MetisPaths.homeRootReadOnly(),
        defaultWorkspace: MetisPaths.workspaceRootReadOnly())
}

private func gatewayModelGetJson(modelId: String): JsonObject {
    let result = JsonObject()
    let normalized = modelId.trimAscii()
    result.put("id", JsonString(normalized))
    result.put("current", (normalized == CliConfig.model).toJsonValue())
    result.put("owner", JsonString(if (normalized.contains(":")) { normalized.split(":")[0] } else { "metis" }))
    result.put("fallback", CliConfig.fallbackModels.contains(normalized).toJsonValue())
    result
}

private func gatewayLogsStatusJson(): JsonObject {
    let result = JsonObject()
    result.put("logsDir", JsonString(CliConfig.logsDir.toString()))
    result.put("currentLogFile", JsonString(CliConfig.logFile.toString()))
    result.put("recentFiles", gatewayRecentLogFiles(10))
    result
}

private func gatewayLogGetJson(fileName: String): JsonObject {
    let result = gatewayLogsStatusJson()
    let normalized = fileName.trimAscii()
    let path = CliConfig.logsDir.join(normalized)
    result.put("requestedFile", JsonString(normalized))
    result.put("requestedPath", JsonString(path.toString()))
    result.put("exists", exists(path).toJsonValue())
    if (exists(path)) {
        let lines = JsonArray([])
        let all = String.fromUtf8(File.readFrom(path)).split("\n")
        if (all.size > 0) {
            var count: Int64 = 0
            for (idx in all.size - 1..=0:-1) {
                if (count >= 40) {
                    break
                }
                let line = all[idx].trimAscii()
                if (line.isEmpty()) {
                    continue
                }
                lines.add(JsonString(line))
                count += 1
            }
        }
        result.put("tail", lines)
    }
    result
}

private func gatewayCurrentLogFileName(): String {
    let full = CliConfig.logFile.toString()
    let parts = full.split("/")
    if (parts.isEmpty()) {
        return full
    }
    parts[parts.size - 1]
}

private func gatewayLogTailJson(maxLines: Int64): JsonObject {
    let result = gatewayLogsStatusJson()
    let lines = JsonArray([])
    if (exists(CliConfig.logFile)) {
        let all = String.fromUtf8(File.readFrom(CliConfig.logFile)).split("\n")
        let total = all.size
        let limit = if (maxLines <= 0) { 80 } else { maxLines }
        var count: Int64 = 0
        for (idx in total - 1..=-1:-1) {
            if (count >= limit) {
                break
            }
            let line = all[idx].trimAscii()
            if (line.isEmpty()) {
                continue
            }
            lines.add(JsonString(line))
            count += 1
        }
    }
    result.put("tail", lines)
    result
}

private func gatewayUsageStatusJson(cfgUser: GatewayUserSettings): JsonObject {
    let cfg = gatewayOpsConfig(cfgUser)
    let platform = gatewayOpsPlatform(cfg)
    let usage = match (platform.get("usage")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    usage.put("masterEnabled", cfgUser.enabled.toJsonValue())
    usage.put("rpcRequestCount", gatewayOpsServerRuntime().get("requestCount") ?? 0.toJsonValue())
    usage
}

private func gatewaySecretsSummaryJson(cfgUser: GatewayUserSettings): JsonObject {
    let cfg = gatewayOpsConfig(cfgUser)
    let platform = gatewayOpsPlatform(cfg)
    let secrets = match (platform.get("secrets")) {
        case Some(v) =>
            try { v.asObject() } catch (_e: Exception) { JsonObject() }
        case None => JsonObject()
    }
    let transport = JsonObject()
    transport.put("preferred", JsonString(gatewayPreferredTransportFromSettings(cfgUser)))
    transport.put("remoteEnabled", cfgUser.remote.enabled.toJsonValue())
    secrets.put("transport", transport)
    secrets
}

private func gatewayDoctorStatusJson(user: GatewayUserSettings): JsonObject {
    let routeRoot = gatewayOpsRawConfigReadOnly()
    let cfg = gatewayOpsConfig(user)
    let rpc = gatewayOpsServerRuntime()
    let doctor = JsonObject()
    doctor.put("ready", (user.enabled && gatewayHasAnyEnabledChannel(user)).toJsonValue())
    doctor.put("masterEnabled", user.enabled.toJsonValue())
    doctor.put("hasEnabledChannel", gatewayHasAnyEnabledChannel(user).toJsonValue())
    doctor.put("runtime", gatewayRuntimeSnapshot())
    doctor.put("rpc", rpc)
    doctor.put("transport", rpc.get("transport") ?? JsonObject())
    doctor.put("http", gatewayOpsHttp(cfg))
    doctor.put("platform", gatewayOpsPlatform(cfg))
    doctor.put("openclawCompatHost", gatewayOpenClawCompatHostSnapshot(user))
    doctor.put("controlUi", buildGatewayExternalSurfaceJson(user).get("controlUi") ?? JsonObject())
    let checks = gatewayProbeChecksJson(user)
    let issues = gatewayProbeIssuesJson(user, checks)
    doctor.put("checks", checks)
    doctor.put("issues", issues)
    doctor.put("telegramDiagnostics", gatewayTelegramDiagnosticsJson(user, routeRoot: routeRoot))
    doctor.put("agentTeamDiagnostics", gatewayOpsAgentTeamDiagnosticsJson(routeRoot: routeRoot))
    doctor.put("summary", gatewayProbeSummaryJson(checks, issues))
    doctor.put("actions", gatewayDoctorActionsJson(user, checks, issues, routeRoot: routeRoot))
    return doctor
}

private func gatewayProbeJson(user: GatewayUserSettings): JsonObject {
    let cfg = gatewayOpsConfig(user)
    let rpc = gatewayOpsServerRuntime()
    let result = JsonObject()
    result.put("reachable", true.toJsonValue())
    result.put("transport", gatewayTransportRuntimeSnapshot(user))
    result.put("rpc", rpc)
    result.put("http", gatewayOpsHttp(cfg))
    result.put("controlUi", buildGatewayExternalSurfaceJson(user).get("controlUi") ?? JsonObject())
    result.put("ready", (user.enabled && gatewayHasAnyEnabledChannel(user)).toJsonValue())
    let checks = gatewayProbeChecksJson(user)
    let issues = gatewayProbeIssuesJson(user, checks)
    result.put("checks", checks)
    result.put("issues", issues)
    result.put("summary", gatewayProbeSummaryJson(checks, issues))
    result.put("actions", gatewayProbeActionsJson(user, issues))
    result
}

private func gatewayOpsActionContextJson(user: GatewayUserSettings, includeRuntime!: Bool = false): JsonObject {
    let cfg = gatewayOpsConfig(user)
    let rpc = gatewayOpsServerRuntime()
    let out = JsonObject()
    if (includeRuntime) {
        out.put("runtime", gatewayRuntimeSnapshot())
    }
    out.put("transport", rpc.get("transport") ?? JsonObject())
    out.put("http", gatewayOpsHttp(cfg))
    out.put("platform", gatewayPlatformRuntimeSummary(cfg))
    out.put("openclawCompatHost", gatewayOpenClawCompatHostSnapshot(user))
    out.put("controlUi", buildGatewayExternalSurfaceJson(user).get("controlUi") ?? JsonObject())
    out
}

private func gatewaySelectById(rows: JsonArray, id: String): JsonObject {
    let normalized = id.trimAscii()
    if (normalized.isEmpty()) {
        return JsonObject()
    }
    for (i in 0..rows.size()) {
        let item = rows[i]
        let obj = try {
            item.asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let rowId = match (obj.get("id")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_inner: Exception) { "" }
            case None => ""
        }
        if (rowId == normalized) {
            return obj
        }
    }
    JsonObject()
}

private func gatewayHealthFlag(row: JsonObject, statusKeys: Array<String>, runningKeys: Array<String>): JsonObject {
    let result = JsonObject()
    var status = ""
    var running = false
    for (key in statusKeys) {
        match (row.get(key)) {
            case Some(v) =>
                try {
                    let value = v.asString().getValue().trimAscii()
                    if (!value.isEmpty()) {
                        status = value
                        break
                    }
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    for (key in runningKeys) {
        match (row.get(key)) {
            case Some(v) =>
                try {
                    running = v.asBool().getValue()
                    break
                } catch (_e: Exception) {
                    ()
                }
            case None => ()
        }
    }
    let healthy = running || status == "active" || status == "online" || status == "delivered"
    result.put("healthy", healthy.toJsonValue())
    result.put("status", JsonString(status))
    result.put("running", running.toJsonValue())
    result
}

private func gatewayTransportReconnectAuditJson(transport: JsonObject, remote: JsonObject): JsonObject {
    let audit = JsonObject()
    let phase = gatewayOpsJsonString(remote, "phase", "idle")
    let connected = match (remote.get("connected")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { false }
        case None => false
    }
    let eligible = match (remote.get("eligibleForReconnect")) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) { true }
        case None => true
    }
    let failureCount = gatewayOpsJsonInt(remote, "consecutiveFailureCount", 0)
    let transitionCount = gatewayOpsJsonInt(remote, "transitionCount", 0)
    let cooldownRemaining = gatewayOpsJsonInt(remote, "cooldownRemainingMs", 0)
    let actions = JsonArray([])
    if (!connected && eligible) {
        let row = JsonObject()
        row.put("action", JsonString("reconnect-now"))
        row.put("method", JsonString("transport.reconnect"))
        row.put("policyState", JsonString("eligible"))
        row.put("params", JsonObject())
        actions.add(row)
    }
    if (cooldownRemaining > 0) {
        let row = JsonObject()
        row.put("action", JsonString("inspect-reconnect-window"))
        row.put("method", JsonString("transport.reconnect.window"))
        row.put("policyState", JsonString("cooldown"))
        row.put("params", JsonObject())
        actions.add(row)
    }
    let constraints = JsonArray([])
    let endpointPresent = JsonObject()
    endpointPresent.put("name", JsonString("transport-endpoint"))
    endpointPresent.put("satisfied", (!gatewayOpsJsonString(transport, "gatewayUrl", "").isEmpty()).toJsonValue())
    endpointPresent.put("detail", JsonString("transport endpoint is resolved"))
    constraints.add(endpointPresent)
    let reconnectable = JsonObject()
    reconnectable.put("name", JsonString("eligible-for-reconnect"))
    reconnectable.put("satisfied", eligible.toJsonValue())
    reconnectable.put("detail", JsonString(if (eligible) { "transport can reconnect now" } else { "transport is in reconnect cooldown" }))
    constraints.add(reconnectable)
    audit.put("phase", JsonString(phase))
    audit.put("connected", connected.toJsonValue())
    audit.put("eligibleForReconnect", eligible.toJsonValue())
    audit.put("consecutiveFailureCount", failureCount.toJsonValue())
    audit.put("transitionCount", transitionCount.toJsonValue())
    audit.put("cooldownRemainingMs", cooldownRemaining.toJsonValue())
    audit.put("actionsNeeded", (!connected || cooldownRemaining > 0 || failureCount > 0).toJsonValue())
    audit.put("auditState", JsonString(if (connected && phase == "stable") { "stable" } else if (cooldownRemaining > 0) { "cooldown" } else if (failureCount > 0) { "recovering" } else { phase }))
    audit.put("constraints", constraints)
    audit.put("actions", actions)
    audit
}

private func gatewayTransportStreamAuditJson(runtime: JsonObject): JsonObject {
    let audit = JsonObject()
    let streams = match (runtime.get("eventStreams")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    let subscriptions = match (runtime.get("eventSubscriptions")) {
        case Some(v) =>
            try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
    var activeStreams: Int64 = 0
    var detachedStreams: Int64 = 0
    var waitingStreams: Int64 = 0
    var waiterCount: Int64 = 0
    for (i in 0..streams.size()) {
        let row = try {
            streams[i].asObject()
        } catch (_e: Exception) {
            JsonObject()
        }
        let phase = gatewayOpsJsonString(row, "phase", "idle")
        if (gatewayOpsJsonBool(row, "active", false)) {
            activeStreams += 1
        }
        if (phase == "detached") {
            detachedStreams += 1
        }
        if (phase == "waiting" || phase == "streaming") {
            waitingStreams += 1
        }
        waiterCount += gatewayOpsJsonInt(row, "waiterCount", 0)
    }
    let actions = JsonArray([])
    if (detachedStreams > 0) {
        let row = JsonObject()
        row.put("action", JsonString("resume-stream"))
        row.put("method", JsonString("connect.stream.resume"))
        row.put("policyState", JsonString("detached"))
        row.put("params", JsonObject())
        actions.add(row)
    }
    if (activeStreams == 0 && subscriptions.size() > 0) {
        let row = JsonObject()
        row.put("action", JsonString("open-stream"))
        row.put("method", JsonString("connect.stream.open"))
        row.put("policyState", JsonString("idle"))
        row.put("params", JsonObject())
        actions.add(row)
    }
    let constraints = JsonArray([])
    let subscriptionPresence = JsonObject()
    subscriptionPresence.put("name", JsonString("subscription-present"))
    subscriptionPresence.put("satisfied", (subscriptions.size() > 0).toJsonValue())
    subscriptionPresence.put("detail", JsonString(if (subscriptions.size() > 0) { "client subscriptions exist" } else { "no active subscriptions registered" }))
    constraints.add(subscriptionPresence)
    let pushCapability = JsonObject()
    pushCapability.put("name", JsonString("server-push-capable"))
    pushCapability.put("satisfied", true.toJsonValue())
    pushCapability.put("detail", JsonString("stream runtime can be woken by server-side push"))
    constraints.add(pushCapability)
    audit.put("streamCount", streams.size().toJsonValue())
    audit.put("subscriptionCount", subscriptions.size().toJsonValue())
    audit.put("activeStreams", activeStreams.toJsonValue())
    audit.put("detachedStreams", detachedStreams.toJsonValue())
    audit.put("waitingStreams", waitingStreams.toJsonValue())
    audit.put("waiterCount", waiterCount.toJsonValue())
    audit.put("actionsNeeded", (detachedStreams > 0 || (activeStreams == 0 && subscriptions.size() > 0)).toJsonValue())
    audit.put("auditState", JsonString(if (detachedStreams > 0) { "resume-required" } else if (activeStreams == 0 && subscriptions.size() > 0) { "stream-open-recommended" } else { "healthy" }))
    audit.put("constraints", constraints)
    audit.put("actions", actions)
    audit
}

public func handleGatewayOpsFamily(method: String, user: GatewayUserSettings, request!: Option<GatewayRpcRequest> = None): Option<GatewayRpcResponse> {
    let requestValue = match (request) {
        case Some(v) => v
        case None => GatewayRpcRequest(method)
    }
    let (transportPreferred, transportGatewayUrl) = gatewayTransportContext(requestValue, user)
    let transportRuntime = gatewayTransportRuntimeSnapshotFor(transportPreferred, transportGatewayUrl)
    if (method == "nodes.status" || method == "devices.status" || method == "push.status" ||
        method == "usage-cost" || method == "secrets.status" || method == "canvas.status" || method == "talk.status") {
        let cfg = gatewayOpsConfig(user)
        let platform = gatewayOpsPlatform(cfg)
        let result = JsonObject()
        if (method == "nodes.status") { result.put("nodes", platform.get("nodes") ?? JsonObject()) }
        if (method == "devices.status") { result.put("devices", platform.get("devices") ?? JsonObject()) }
        if (method == "push.status") { result.put("push", platform.get("push") ?? JsonObject()) }
        if (method == "usage-cost") { result.put("usage", gatewayUsageStatusJson(user)) }
        if (method == "secrets.status") { result.put("secrets", gatewaySecretsSummaryJson(user)) }
        if (method == "canvas.status") { result.put("canvas", platform.get("canvas") ?? JsonObject()) }
        if (method == "talk.status") { result.put("talk", platform.get("talk") ?? JsonObject()) }
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "platform.runtime") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("platform", gatewayPlatformRuntimeSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "canvas.runtime") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("canvas", gatewayCanvasRuntimeSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "canvas.pipeline") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("pipeline", gatewayCanvasPipelineSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "canvas.audit") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("audit", gatewayCanvasAuditSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "canvas.actions") {
        let cfg = gatewayOpsConfig(user)
        let audit = gatewayCanvasAuditSummary(cfg)
        let result = JsonObject()
        result.put("actions", audit.get("actions") ?? JsonArray([]))
        result.put("auditState", audit.get("auditState") ?? JsonString("healthy"))
        result.put("actionsNeeded", audit.get("actionsNeeded") ?? 0.toJsonValue())
        result.put("constraints", audit.get("constraints") ?? JsonArray([]))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "talk.runtime") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("talk", gatewayTalkRuntimeSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "talk.pipeline") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("pipeline", gatewayTalkPipelineSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "talk.audit") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("audit", gatewayTalkAuditSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "talk.actions") {
        let cfg = gatewayOpsConfig(user)
        let audit = gatewayTalkAuditSummary(cfg)
        let result = JsonObject()
        result.put("actions", audit.get("actions") ?? JsonArray([]))
        result.put("auditState", audit.get("auditState") ?? JsonString("healthy"))
        result.put("actionsNeeded", audit.get("actionsNeeded") ?? 0.toJsonValue())
        result.put("constraints", audit.get("constraints") ?? JsonArray([]))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.runtime") {
        let result = JsonObject()
        let remote = match (transportRuntime.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let constraints = JsonArray([])
        let endpointPresent = JsonObject()
        endpointPresent.put("name", JsonString("transport-endpoint"))
        endpointPresent.put("satisfied", (!gatewayOpsJsonString(transportRuntime, "gatewayUrl", "").isEmpty()).toJsonValue())
        endpointPresent.put("detail", JsonString(gatewayOpsJsonString(transportRuntime, "gatewayUrl", "")))
        constraints.add(endpointPresent)
        let resumable = JsonObject()
        resumable.put("name", JsonString("persistent-session-runtime"))
        resumable.put("satisfied", (gatewayOpsJsonString(transportRuntime, "runtimeModel", "") == "persistent-session-lease").toJsonValue())
        resumable.put("detail", JsonString(gatewayOpsJsonString(transportRuntime, "runtimeModel", "local-rpc")))
        constraints.add(resumable)
        let actions = JsonArray([])
        let phase = gatewayOpsJsonString(remote, "phase", "idle")
        if (phase == "cooldown" || phase == "recovering" || phase == "degraded") {
            let row = JsonObject()
            row.put("action", JsonString("inspect-reconnect"))
            row.put("method", JsonString("transport.reconnect.audit"))
            actions.add(row)
        }
        if (phase == "connected" || phase == "stable") {
            let row = JsonObject()
            row.put("action", JsonString("inspect-stream-sessions"))
            row.put("method", JsonString("transport.stream.sessions"))
            actions.add(row)
        }
        result.put("transport", transportRuntime)
        result.put("policyState", remote.get("policyState") ?? JsonString("idle"))
        result.put("constraints", constraints)
        result.put("actions", actions)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.connections") {
        let result = JsonObject()
        let runtime = gatewayOpsServerRuntime()
        result.put("transport", transportRuntime)
        result.put("connections", gatewayOpsServerRuntimeArray(runtime, "clients"))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.subscriptions") {
        let result = JsonObject()
        let runtime = gatewayOpsServerRuntime()
        result.put("transport", transportRuntime)
        result.put("eventSubscriptions", gatewayOpsServerRuntimeArray(runtime, "eventSubscriptions"))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.streams") {
        let result = JsonObject()
        let runtime = gatewayOpsServerRuntime()
        result.put("transport", transportRuntime)
        result.put("eventStreams", gatewayOpsServerRuntimeArray(runtime, "eventStreams"))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.lifecycle") {
        let result = JsonObject()
        let transport = transportRuntime
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        result.put("lifecycle", remote.get("lifecycle") ?? JsonArray([]))
        result.put("lastProtocolVersion", remote.get("lastProtocolVersion") ?? JsonString(""))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.remote") {
        let result = JsonObject()
        let transport = transportRuntime
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        result.put("transport", transport)
        result.put("remote", remote)
        result.put("summary", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.reconnect.history") {
        let result = JsonObject()
        let transport = transportRuntime
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        result.put("reconnectState", remote.get("reconnectState") ?? JsonString(""))
        result.put("nextRetryAtMs", remote.get("nextRetryAtMs") ?? 0.toJsonValue())
        result.put("lastReconnectAtMs", remote.get("lastReconnectAtMs") ?? 0.toJsonValue())
        result.put("lifecycle", remote.get("lifecycle") ?? JsonArray([]))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.reconnect.state") {
        let result = JsonObject()
        let transport = transportRuntime
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let state = JsonObject()
        state.put("reconnectState", remote.get("reconnectState") ?? JsonString("idle"))
        state.put("nextRetryAtMs", remote.get("nextRetryAtMs") ?? 0.toJsonValue())
        state.put("cooldownRemainingMs", remote.get("cooldownRemainingMs") ?? 0.toJsonValue())
        state.put("eligibleForReconnect", remote.get("eligibleForReconnect") ?? true.toJsonValue())
        state.put("transitionCount", remote.get("transitionCount") ?? 0.toJsonValue())
        state.put("lastTransitionAtMs", remote.get("lastTransitionAtMs") ?? 0.toJsonValue())
        state.put("connected", remote.get("connected") ?? false.toJsonValue())
        let phase = gatewayOpsJsonString(remote, "phase", "idle")
        state.put("stable", (phase == "stable").toJsonValue())
        state.put("phase", JsonString(phase))
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        result.put("state", state)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.reconnect.window") {
        let result = JsonObject()
        let transport = transportRuntime
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let window = JsonObject()
        window.put("stableConnectedAtMs", remote.get("stableConnectedAtMs") ?? 0.toJsonValue())
        window.put("consecutiveFailureCount", remote.get("consecutiveFailureCount") ?? 0.toJsonValue())
        window.put("lastSuccessAtMs", remote.get("lastSuccessAtMs") ?? 0.toJsonValue())
        window.put("lastFailureAtMs", remote.get("lastFailureAtMs") ?? 0.toJsonValue())
        window.put("cooldownRemainingMs", remote.get("cooldownRemainingMs") ?? 0.toJsonValue())
        window.put("phase", remote.get("phase") ?? JsonString("idle"))
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        result.put("window", window)
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.reconnect.plan") {
        let result = JsonObject()
        let transport = transportRuntime
        let plan = gatewayTransportReconnectPlanFor(transportPreferred, transportGatewayUrl)
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        result.put("plan", plan)
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        result.put("phase", remote.get("phase") ?? JsonString("idle"))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.reconnect.audit") {
        let result = JsonObject()
        let transport = transportRuntime
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        result.put("transport", transport)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        result.put("audit", gatewayTransportReconnectAuditJson(transport, remote))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.reconnect.reset") {
        let result = JsonObject()
        result.put("transport", transportRuntime)
        result.put("plan", gatewayTransportResetReconnectPlanFor(transportPreferred, transportGatewayUrl))
        result.put("reset", true.toJsonValue())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.stream.health") {
        let result = JsonObject()
        let runtime = gatewayOpsServerRuntime()
        let streams = gatewayOpsServerRuntimeArray(runtime, "eventStreams")
        let subscriptions = gatewayOpsServerRuntimeArray(runtime, "eventSubscriptions")
        let health = JsonObject()
        health.put("eventStreams", streams)
        health.put("eventSubscriptions", subscriptions)
        health.put("streamCount", gatewayJsonArraySize(streams).toJsonValue())
        health.put("subscriptionCount", gatewayJsonArraySize(subscriptions).toJsonValue())
        result.put("transport", transportRuntime)
        result.put("health", health)
        result.put("streamSummary", gatewayConnectStreamSummary(streams))
        result.put("subscriptionSummary", gatewayConnectSubscriptionSummary(subscriptions))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.stream.audit") {
        let result = JsonObject()
        let runtime = gatewayOpsServerRuntime()
        let streams = gatewayOpsServerRuntimeArray(runtime, "eventStreams")
        let subscriptions = gatewayOpsServerRuntimeArray(runtime, "eventSubscriptions")
        result.put("transport", transportRuntime)
        result.put("streamSummary", gatewayConnectStreamSummary(streams))
        result.put("subscriptionSummary", gatewayConnectSubscriptionSummary(subscriptions))
        result.put("audit", gatewayTransportStreamAuditJson(runtime))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.stream.sessions") {
        let result = JsonObject()
        let runtime = gatewayOpsServerRuntime()
        let streams = gatewayOpsServerRuntimeArray(runtime, "eventStreams")
        let subscriptions = gatewayOpsServerRuntimeArray(runtime, "eventSubscriptions")
        result.put("transport", transportRuntime)
        result.put("sessions", streams)
        result.put("subscriptions", subscriptions)
        result.put("streamSummary", gatewayConnectStreamSummary(streams))
        result.put("subscriptionSummary", gatewayConnectSubscriptionSummary(subscriptions))
        result.put("audit", gatewayTransportStreamAuditJson(runtime))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.health") {
        let transport = transportRuntime
        let remote = match (transport.get("remote")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let result = JsonObject()
        result.put("transport", transport)
        let health = JsonObject()
        let preferred = transportPreferred
        let connected = match (remote.get("connected")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        let reconnectState = match (remote.get("reconnectState")) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_e: Exception) { "" }
            case None => ""
        }
        health.put("healthy", (preferred == "local" || connected).toJsonValue())
        health.put("preferred", JsonString(preferred))
        health.put("connected", connected.toJsonValue())
        health.put("reconnectState", JsonString(reconnectState))
        health.put("phase", remote.get("phase") ?? JsonString("idle"))
        health.put("policyState", remote.get("policyState") ?? JsonString("idle"))
        health.put("cooldownRemainingMs", remote.get("cooldownRemainingMs") ?? 0.toJsonValue())
        health.put("eligibleForReconnect", remote.get("eligibleForReconnect") ?? true.toJsonValue())
        health.put("runtimeModel", remote.get("runtimeModel") ?? JsonString(""))
        health.put("serverPushCapable", remote.get("serverPushCapable") ?? false.toJsonValue())
        health.put("attachable", remote.get("attachable") ?? false.toJsonValue())
        health.put("resumable", remote.get("resumable") ?? false.toJsonValue())
        result.put("health", health)
        result.put("remote", gatewayConnectRemoteSummary(transport))
        result.put("reconnect", gatewayConnectReconnectSummary(transport))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "transport.reconnect") {
        let targetTransport = transportPreferred
        let client = gatewayBuildClient(
            "gateway-transport-runtime",
            "transport-runtime",
            connectionId: "gateway-transport-runtime",
            capabilities: ["transport.reconnect"]
        )
        let stopped = client.stopAndWait(timeoutMs: 500)
        let connected = client.connect()
        let result = JsonObject()
        result.put("stopped", stopped.toJsonValue())
        result.put("connected", connected.toJsonValue())
        result.put("preferred", JsonString(targetTransport))
        result.put("transport", gatewayTransportRuntimeSnapshotFor(targetTransport, transportGatewayUrl))
        return Some(GatewayRpcResponse(connected || targetTransport == "local", method, result: result, error: if (connected || targetTransport == "local") { "" } else { "Transport reconnect failed." }))
    }
    if (method == "nodes.executor") {
        let result = JsonObject()
        result.put("executor", gatewayPendingWorkExecutorSummary())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "platform.executor") {
        let result = JsonObject()
        result.put("executor", gatewayPendingWorkExecutorSummary())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.list") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        let running = match (gatewayRuntimeSnapshot().get("running")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        result.put("nodes", gatewayNodeRegistrySnapshot(cfg, running))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.get") {
        let cfg = gatewayOpsConfig(user)
        let running = match (gatewayRuntimeSnapshot().get("running")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        let nodes = gatewayNodeRegistrySnapshot(cfg, running)
        let nodesRoot = match (nodes.get("nodes")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let items = match (nodesRoot.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let result = JsonObject()
        result.put("node", gatewaySelectById(items, gatewayOpsStringParam(requestValue, ["id", "node", "nodeId"], "local-gateway")))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.health") {
        let cfg = gatewayOpsConfig(user)
        let running = match (gatewayRuntimeSnapshot().get("running")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { false }
            case None => false
        }
        let nodes = gatewayNodeRegistrySnapshot(cfg, running)
        let nodesRoot = match (nodes.get("nodes")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let items = match (nodesRoot.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let node = gatewaySelectById(items, gatewayOpsStringParam(requestValue, ["id", "node", "nodeId"], "local-gateway"))
        let result = JsonObject()
        result.put("node", node)
        result.put("health", gatewayHealthFlag(node, ["status"], ["running"]))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.lifecycle") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("lifecycle", gatewayNodeLifecycleSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.scheduler") {
        let result = JsonObject()
        result.put("scheduler", gatewayPendingWorkExecutorSummary())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.policy") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("policy", gatewayNodeSchedulerPolicySummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.policy.audit") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("audit", gatewayNodeSchedulingAuditSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.policy.reconcile") {
        let cfg = gatewayOpsConfig(user)
        let nodeId = gatewayOpsStringParam(requestValue, ["id", "node", "nodeId"], "")
        let limit = match (requestValue.params.get("limit")) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 4 }
            case None => 4
        }
        let result = JsonObject()
        result.put("reconcile", gatewayReconcileNodeScheduling(cfg, nodeId: nodeId, limit: limit))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.start" || method == "nodes.stop" || method == "nodes.restart") {
        let cfg = gatewayOpsConfig(user)
        let targetId = gatewayOpsStringParam(requestValue, ["id", "node", "nodeId"], "local-gateway")
        let shouldRun = method != "nodes.stop"
        let result = JsonObject()
        if (method == "nodes.restart") {
            result.put(
                "before",
                gatewayRegisterOrHeartbeatNode(
                    cfg,
                    targetId,
                    running: false,
                    status: "offline",
                    lifecycleState: "restarting"
                )
            )
        }
        result.put(
            "nodes",
            gatewayRegisterOrHeartbeatNode(
                cfg,
                targetId,
                running: shouldRun,
                status: if (shouldRun) { "online" } else { "offline" },
                lifecycleState: if (shouldRun) { "running" } else { "stopped" }
            )
        )
        result.put("nodeId", JsonString(targetId))
        result.put("running", shouldRun.toJsonValue())
        if (method == "nodes.restart") {
            result.put("restarted", true.toJsonValue())
        }
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.heartbeat") {
        let cfg = gatewayOpsConfig(user)
        let targetId = gatewayOpsStringParam(requestValue, ["id", "node", "nodeId"], "local-gateway")
        let kind = gatewayOpsStringParam(requestValue, ["kind"], "local")
        let running = match (requestValue.params.get("running")) {
            case Some(v) =>
                try { v.asBool().getValue() } catch (_e: Exception) { true }
            case None => true
        }
        let result = JsonObject()
        result.put(
            "nodes",
            gatewayRegisterOrHeartbeatNode(
                cfg,
                targetId,
                running: running,
                kind: kind,
                status: if (running) { "online" } else { "offline" },
                lifecycleState: if (running) { "running" } else { "stopped" }
            )
        )
        result.put("nodeId", JsonString(targetId))
        result.put("running", running.toJsonValue())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.pending" || method == "nodes.pending_work") {
        let result = JsonObject()
        result.put("pendingWork", gatewayPendingWorkSnapshot())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.queue") {
        let kind = gatewayOpsStringParam(requestValue, ["kind"], "generic")
        let targetId = gatewayOpsStringParam(requestValue, ["targetId", "target", "node", "nodeId"], "local-gateway")
        let payload = JsonObject()
        payload.put("requestedBy", JsonString(gatewayOpsStringParam(requestValue, ["requestedBy", "requester"], "gateway-rpc")))
        payload.put("message", JsonString(gatewayOpsStringParam(requestValue, ["message", "detail"], "")))
        let result = JsonObject()
        result.put("pendingWork", gatewayQueuePendingWork(kind, targetId, payload: payload))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.claim") {
        let result = JsonObject()
        result.put("pendingWork", gatewayClaimPendingWork("local-gateway"))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.complete") {
        let pending = gatewayPendingWorkSnapshot()
        let items = match (pending.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        var workId = ""
        for (i in 0..items.size()) {
            let item = items[i]
            let obj = try {
                item.asObject()
            } catch (_e: Exception) {
                JsonObject()
            }
            let status = match (obj.get("status")) {
                case Some(v) =>
                    try { v.asString().getValue() } catch (_inner: Exception) { "" }
                case None => ""
            }
            if (status == "claimed") {
                workId = match (obj.get("id")) {
                    case Some(v) =>
                        try { v.asString().getValue() } catch (_inner: Exception) { "" }
                    case None => ""
                }
                break
            }
        }
        let result = JsonObject()
        result.put("pendingWork", gatewayCompletePendingWork(workId, "local-gateway"))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.retry") {
        let pending = gatewayPendingWorkSnapshot()
        let items = match (pending.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        var workId = gatewayOpsStringParam(requestValue, ["id", "workId"], "")
        if (workId.isEmpty()) {
            for (i in 0..items.size()) {
                let obj = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
                let status = gatewayOpsJsonString(obj, "status", "")
                if (status == "claimed" || status == "failed") {
                    workId = gatewayOpsJsonString(obj, "id", "")
                    break
                }
            }
        }
        let error = gatewayOpsStringParam(requestValue, ["error", "detail"], "retry-requested")
        let backoffMs = match (requestValue.params.get("backoffMs")) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 1000 }
            case None => 1000
        }
        let result = JsonObject()
        result.put("pendingWork", gatewayRetryPendingWork(workId, backoffMs: backoffMs, error: error))
        result.put("workId", JsonString(workId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.fail") {
        let pending = gatewayPendingWorkSnapshot()
        let items = match (pending.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        var workId = gatewayOpsStringParam(requestValue, ["id", "workId"], "")
        if (workId.isEmpty()) {
            for (i in 0..items.size()) {
                let obj = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
                let status = gatewayOpsJsonString(obj, "status", "")
                if (status == "claimed" || status == "queued") {
                    workId = gatewayOpsJsonString(obj, "id", "")
                    break
                }
            }
        }
        let error = gatewayOpsStringParam(requestValue, ["error", "detail"], "failed-by-rpc")
        let result = JsonObject()
        result.put("pendingWork", gatewayFailPendingWork(workId, "local-gateway", error: error))
        result.put("workId", JsonString(workId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.recover") {
        let pending = gatewayPendingWorkSnapshot()
        let items = match (pending.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        var workId = gatewayOpsStringParam(requestValue, ["id", "workId"], "")
        if (workId.isEmpty()) {
            for (i in 0..items.size()) {
                let obj = try { items[i].asObject() } catch (_e: Exception) { JsonObject() }
                let lifecycleState = gatewayOpsJsonString(obj, "lifecycleState", "")
                if (lifecycleState == "failed" || lifecycleState == "retrying") {
                    workId = gatewayOpsJsonString(obj, "id", "")
                    break
                }
            }
        }
        let result = JsonObject()
        result.put("pendingWork", gatewayRecoverPendingWork(workId))
        result.put("workId", JsonString(workId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.execute") {
        let cfg = gatewayOpsConfig(user)
        let pending = gatewayRunPendingWorkExecutor()
        let result = JsonObject()
        result.put("executor", pending)
        result.put("pendingWork", gatewayPendingWorkSnapshot())
        result.put("scheduler", gatewayPendingWorkExecutorSummary())
        result.put("backlog", gatewayPendingWorkBacklogSummary())
        result.put("platform", gatewayPlatformRuntimeSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.dispatch") {
        let nodeId = gatewayOpsStringParam(requestValue, ["id", "node", "nodeId"], "local-gateway")
        let result = JsonObject()
        result.put("executor", gatewayRunPendingWorkExecutor(nodeId: nodeId))
        result.put("nodeId", JsonString(nodeId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.backlog") {
        let result = JsonObject()
        result.put("pendingWork", gatewayPendingWorkSnapshot())
        result.put("scheduler", gatewayPendingWorkExecutorSummary())
        result.put("backlog", gatewayPendingWorkBacklogSummary())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "nodes.dispatch.batch") {
        let nodeId = gatewayOpsStringParam(requestValue, ["id", "node", "nodeId"], "local-gateway")
        let limit = match (requestValue.params.get("limit")) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 4 }
            case None => 4
        }
        let result = JsonObject()
        result.put("executor", gatewayDispatchPendingWorkBatch(nodeId: nodeId, limit: limit))
        result.put("nodeId", JsonString(nodeId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.list") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("devices", gatewayOpsPlatform(cfg).get("devices") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.get") {
        let cfg = gatewayOpsConfig(user)
        let devicesRoot = match (gatewayOpsPlatform(cfg).get("devices")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let items = match (devicesRoot.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let result = JsonObject()
        result.put("device", gatewaySelectById(items, gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.health") {
        let cfg = gatewayOpsConfig(user)
        let devicesRoot = match (gatewayOpsPlatform(cfg).get("devices")) {
            case Some(v) =>
                try { v.asObject() } catch (_e: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let items = match (devicesRoot.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let device = gatewaySelectById(items, gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui"))
        let result = JsonObject()
        result.put("device", device)
        result.put("health", gatewayHealthFlag(device, ["status"], []))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.auth") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("auth", gatewayDeviceAuthSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.lifecycle") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("lifecycle", gatewayDeviceAuthSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.runtime") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("runtime", gatewayDeviceRuntimeSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.policy") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("policy", gatewayDeviceApprovalPolicySummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.policy.audit") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("audit", gatewayDeviceApprovalAuditSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.presence") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("presence", gatewayDevicePresenceSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.register") {
        let deviceId = gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")
        let kind = gatewayOpsStringParam(requestValue, ["kind"], "browser")
        let authMode = gatewayOpsStringParam(requestValue, ["authMode"], "device-auth")
        let result = JsonObject()
        result.put("devices", gatewayRegisterDevice(deviceId, kind: kind, authMode: authMode))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.unregister") {
        let deviceId = gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")
        let result = JsonObject()
        result.put("devices", gatewayUnregisterDevice(deviceId))
        result.put("deviceId", JsonString(deviceId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.revalidate") {
        let deviceId = gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")
        let authState = gatewayOpsStringParam(requestValue, ["authState"], "validated")
        let result = JsonObject()
        result.put("devices", gatewayRevalidateDevice(deviceId, authState: authState))
        result.put("deviceId", JsonString(deviceId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.recover") {
        let deviceId = gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")
        let result = JsonObject()
        result.put("devices", gatewayRecoverDevice(deviceId))
        result.put("deviceId", JsonString(deviceId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.approve") {
        let deviceId = gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")
        let authState = gatewayOpsStringParam(requestValue, ["authState"], "validated")
        let result = JsonObject()
        result.put("devices", gatewayApproveDevice(deviceId, authState: authState))
        result.put("deviceId", JsonString(deviceId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.deny") {
        let deviceId = gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")
        let reason = gatewayOpsStringParam(requestValue, ["reason", "detail"], "denied-by-rpc")
        let result = JsonObject()
        result.put("devices", gatewayDenyDevice(deviceId, reason: reason))
        result.put("deviceId", JsonString(deviceId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "devices.touch") {
        let deviceId = gatewayOpsStringParam(requestValue, ["id", "device", "deviceId"], "browser-control-ui")
        let authState = gatewayOpsStringParam(requestValue, ["authState"], "validated")
        let status = gatewayOpsStringParam(requestValue, ["status"], "active")
        let result = JsonObject()
        result.put("devices", gatewayTouchDevice(deviceId, authState: authState, status: status))
        result.put("deviceId", JsonString(deviceId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.deliveries") {
        let result = JsonObject()
        result.put("push", gatewayPushDeliverySnapshot())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.summary") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("push", gatewayPlatformRuntimeSummary(cfg).get("push") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.lifecycle") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("lifecycle", gatewayPushLifecycleSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.dispatcher") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("dispatcher", gatewayPushDispatcherSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.orchestration") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("orchestration", gatewayPushOrchestrationSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.orchestration.audit") {
        let cfg = gatewayOpsConfig(user)
        let result = JsonObject()
        result.put("audit", gatewayPushOrchestrationAuditSummary(cfg))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.orchestration.actions") {
        let cfg = gatewayOpsConfig(user)
        let audit = gatewayPushOrchestrationAuditSummary(cfg)
        let result = JsonObject()
        result.put("actions", audit.get("actions") ?? JsonArray([]))
        result.put("auditState", audit.get("auditState") ?? JsonString("idle"))
        result.put("actionsNeeded", audit.get("actionsNeeded") ?? 0.toJsonValue())
        result.put("constraints", audit.get("constraints") ?? JsonArray([]))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.orchestrate") {
        let cfg = gatewayOpsConfig(user)
        let channel = gatewayOpsStringParam(requestValue, ["channel"], "local")
        let limit = match (requestValue.params.get("limit")) {
            case Some(v) =>
                try { Int64.parse(v.toJsonString()) } catch (_e: Exception) { 4 }
            case None => 4
        }
        let result = JsonObject()
        result.put("orchestrator", gatewayRunPushOrchestration(cfg, channel: channel, limit: limit))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.get") {
        let deliveries = gatewayPushDeliverySnapshot()
        let items = match (deliveries.get("items")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let push = gatewaySelectById(items, gatewayOpsStringParam(requestValue, ["id", "delivery", "deliveryId"], ""))
        let result = JsonObject()
        result.put("delivery", push)
        result.put("health", gatewayHealthFlag(push, ["status"], []))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.record") {
        let channel = gatewayOpsStringParam(requestValue, ["channel"], "local")
        let targetId = gatewayOpsStringParam(requestValue, ["targetId", "target"], "control-ui")
        let detail = gatewayOpsStringParam(requestValue, ["detail", "message"], "recorded")
        let result = JsonObject()
        result.put("push", gatewayRecordPushDelivery(channel, targetId, "recorded", detail: detail))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.send") {
        let channel = gatewayOpsStringParam(requestValue, ["channel"], "local")
        let targetId = gatewayOpsStringParam(requestValue, ["targetId", "target"], "control-ui")
        let body = gatewayOpsStringParam(requestValue, ["body", "message"], "gateway-rpc-send")
        let result = JsonObject()
        result.put("push", gatewaySendPush(channel, targetId, body))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.retry") {
        let deliveryId = gatewayOpsStringParam(requestValue, ["id", "delivery", "deliveryId"], "")
        let result = JsonObject()
        result.put("push", gatewayRetryPushDelivery(deliveryId))
        result.put("deliveryId", JsonString(deliveryId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.recover") {
        let deliveryId = gatewayOpsStringParam(requestValue, ["id", "delivery", "deliveryId"], "")
        let detail = gatewayOpsStringParam(requestValue, ["detail", "message"], "recovered")
        let result = JsonObject()
        result.put("push", gatewayRecoverPushDelivery(deliveryId, detail: detail))
        result.put("deliveryId", JsonString(deliveryId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.wake") {
        let channel = gatewayOpsStringParam(requestValue, ["channel"], "local")
        let targetId = gatewayOpsStringParam(requestValue, ["targetId", "target"], "browser-control-ui")
        let body = gatewayOpsStringParam(requestValue, ["body", "message"], "wake")
        let result = JsonObject()
        result.put("wake", gatewayWakePushTarget(channel, targetId, body: body))
        result.put("targetId", JsonString(targetId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "push.fail") {
        let deliveryId = gatewayOpsStringParam(requestValue, ["id", "delivery", "deliveryId"], "")
        let reason = gatewayOpsStringParam(requestValue, ["reason", "detail"], "failed-by-rpc")
        let result = JsonObject()
        result.put("push", gatewayFailPushDelivery(deliveryId, reason: reason))
        result.put("deliveryId", JsonString(deliveryId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "models.status" || method == "models.list" || method == "models.current") {
        let result = JsonObject()
        result.put("models", gatewayModelsStatusJson())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "models.get") {
        let modelId = gatewayOpsStringParam(requestValue, ["id", "model", "modelId"], CliConfig.model)
        let result = JsonObject()
        result.put("model", gatewayModelGetJson(modelId))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "logs.status" || method == "logs.list") {
        let result = JsonObject()
        result.put("logs", gatewayLogsStatusJson())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "logs.get") {
        let result = JsonObject()
        let requested = gatewayOpsStringParam(requestValue, ["file", "name", "id"], "")
        let latest = match (gatewayRecentLogFiles(1).get(0)) {
            case Some(v) =>
                try { v.asString().getValue() } catch (_e: Exception) { gatewayCurrentLogFileName() }
            case None => gatewayCurrentLogFileName()
        }
        result.put("logs", gatewayLogGetJson(if (requested.isEmpty()) { latest } else { requested }))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "logs.tail") {
        let result = JsonObject()
        result.put("logs", gatewayLogTailJson(80))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "usage.status") {
        let result = JsonObject()
        result.put("usage", gatewayUsageStatusJson(user))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "usage.summary") {
        let result = JsonObject()
        result.put("usage", gatewayUsageStatusJson(user))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "secrets.summary") {
        let result = JsonObject()
        result.put("secrets", gatewaySecretsSummaryJson(user))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "secrets.get") {
        let result = JsonObject()
        result.put("secrets", gatewaySecretsSummaryJson(user))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "probe") {
        let result = JsonObject()
        result.put("probe", gatewayProbeJson(user))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "probe.actions") {
        let probe = gatewayProbeJson(user)
        let actions = match (probe.get("actions")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let result = JsonObject()
        result.put("actions", actions)
        result.put("summary", probe.get("summary") ?? JsonObject())
        result.put("policyState", JsonString(if (actions.size() == 0) { "healthy" } else { "remediation-required" }))
        result.put("remediation", gatewayActionEnvelope(actions, if (actions.size() == 0) { "healthy" } else { "remediation-required" }, if (actions.size() == 0) { "ready" } else { "investigate" }))
        let context = gatewayOpsActionContextJson(user)
        result.put("transport", context.get("transport") ?? JsonObject())
        result.put("http", context.get("http") ?? JsonObject())
        result.put("platform", context.get("platform") ?? JsonObject())
        result.put("openclawCompatHost", context.get("openclawCompatHost") ?? JsonObject())
        result.put("controlUi", context.get("controlUi") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "probe.remediation") {
        let probe = gatewayProbeJson(user)
        let actions = match (probe.get("actions")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let result = JsonObject()
        result.put("remediation", gatewayActionEnvelope(actions, if (actions.size() == 0) { "healthy" } else { "remediation-required" }, if (actions.size() == 0) { "ready" } else { "investigate" }))
        result.put("summary", probe.get("summary") ?? JsonObject())
        let context = gatewayOpsActionContextJson(user)
        result.put("transport", context.get("transport") ?? JsonObject())
        result.put("http", context.get("http") ?? JsonObject())
        result.put("platform", context.get("platform") ?? JsonObject())
        result.put("openclawCompatHost", context.get("openclawCompatHost") ?? JsonObject())
        result.put("controlUi", context.get("controlUi") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "doctor") {
        let result = JsonObject()
        result.put("doctor", gatewayDoctorStatusJson(user))
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "doctor.actions") {
        let doctor = gatewayDoctorStatusJson(user)
        let actions = match (doctor.get("actions")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let result = JsonObject()
        result.put("actions", actions)
        result.put("summary", doctor.get("summary") ?? JsonObject())
        result.put("policyState", JsonString(if (actions.size() == 0) { "healthy" } else { "remediation-required" }))
        result.put("remediation", gatewayActionEnvelope(actions, if (actions.size() == 0) { "healthy" } else { "remediation-required" }, if (actions.size() == 0) { "ready" } else { "follow-up" }))
        let context = gatewayOpsActionContextJson(user, includeRuntime: true)
        result.put("runtime", context.get("runtime") ?? JsonObject())
        result.put("transport", context.get("transport") ?? JsonObject())
        result.put("http", context.get("http") ?? JsonObject())
        result.put("platform", context.get("platform") ?? JsonObject())
        result.put("openclawCompatHost", context.get("openclawCompatHost") ?? JsonObject())
        result.put("controlUi", context.get("controlUi") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    if (method == "doctor.remediation") {
        let doctor = gatewayDoctorStatusJson(user)
        let actions = match (doctor.get("actions")) {
            case Some(v) =>
                try { v.asArray() } catch (_e: Exception) { JsonArray([]) }
            case None => JsonArray([])
        }
        let result = JsonObject()
        result.put("remediation", gatewayActionEnvelope(actions, if (actions.size() == 0) { "healthy" } else { "remediation-required" }, if (actions.size() == 0) { "ready" } else { "follow-up" }))
        result.put("summary", doctor.get("summary") ?? JsonObject())
        let context = gatewayOpsActionContextJson(user, includeRuntime: true)
        result.put("runtime", context.get("runtime") ?? JsonObject())
        result.put("transport", context.get("transport") ?? JsonObject())
        result.put("http", context.get("http") ?? JsonObject())
        result.put("platform", context.get("platform") ?? JsonObject())
        result.put("openclawCompatHost", context.get("openclawCompatHost") ?? JsonObject())
        result.put("controlUi", context.get("controlUi") ?? JsonObject())
        return Some(GatewayRpcResponse(true, method, result: result))
    }
    None
}
