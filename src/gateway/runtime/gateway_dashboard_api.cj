package metis.gateway.runtime

import magic.config.Config
import magic.jsonable.*

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, skillEntryEnabled}
import metis.core.model.CliModelManager
import metis.core.memory.MemoryStateRegistry
import metis.core.skills.SkillsPrompt
import metis.gateway.core.{GatewaySessionConversationView, GatewaySessionStore, gatewayFindSessionConversationViewForUser, gatewaySessionStoreForSessionKey, gatewaySessionStoreForUserWithAgentId}
import metis.gateway.session.{GatewayIngressSource, gatewayBuildChatHistoryRpcParams, gatewayBuildChatSendRpcParams, gatewayBuildSessionRpcParams, gatewayBuildSessionsDeleteRpcParams}
import metis.cron.{
    CronJob,
    computeJobNextRun,
    conversationKeyForCronTarget,
    cronDashboardSaveJob,
    cronLoadOrEmpty,
    cronSave,
    cronStorePath
}

import std.collection.{ArrayList, HashMap, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, exists, Path}
import std.time.DateTime
import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}
import stdx.net.http.HttpContext

private func gatewayDashboardFormValue(ctx: HttpContext, key: String): String {
    ctx.request.form.get(key) ?? ""
}

private func gatewayDashboardFormParams(ctx: HttpContext, keys: Array<String>): JsonObject {
    let params = JsonObject()
    for (key in keys) {
        let value = gatewayDashboardFormValue(ctx, key)
        if (!value.isEmpty()) {
            params.put(key, JsonString(value))
        }
    }
    params
}

func gatewayDashboardRequestParamsFromForm(
    ctx: HttpContext,
    method: String,
    keys: Array<String>,
    source!: GatewayIngressSource = GatewayIngressSource.ControlUi
): JsonObject {
    gatewayDashboardRequestParams(
        method,
        gatewayDashboardFormParams(ctx, keys),
        source: source
    )
}

/**
 * Dashboard HTTP 与网关同进程，必须走本地 GatewayServer。
 * 不可使用 gatewayBuildClient 默认逻辑：用户开启 remote 时会误连远程；且 mode=control-ui 会要求设备令牌，
 * 而此处未携带 deviceId/deviceToken，会导致所有 dashboard.* RPC 鉴权失败、页面数据为空。
 */
private func dashboardClient(): GatewayClient {
    GatewayClient(
        clientName: "dashboard",
        mode: "local-cli",
        transport: "local",
        gatewayUrl: "local://gateway",
        timeoutMs: 12000
    )
}

private func dashboardGatewayRequest(method: String, params!: JsonObject = JsonObject()): String {
    let res = dashboardClient().request(method, params: params)
    if (!res.ok) {
        return "{\"ok\":false,\"error\":\"${gatewayDashboardJsonEscape(res.error)}\"}"
    }
    res.result.toJsonString()
}

private func dashboardGatewayRequestFromForm(
    ctx: HttpContext,
    method: String,
    keys: Array<String>,
    source!: GatewayIngressSource = GatewayIngressSource.ControlUi
): String {
    let params = gatewayDashboardRequestParamsFromForm(ctx, method, keys, source: source)
    dashboardGatewayRequest(method, params: params)
}

func gatewayDashboardBuildStatusParams(limit!: Int64): JsonObject {
    let params = JsonObject()
    params.put("limit", JsonString(limit.toString()))
    params
}

func gatewayDashboardBuildModelSwitchParams(modelName: String): JsonObject {
    let params = JsonObject()
    params.put("model", JsonString(modelName.trimAscii()))
    params
}

func gatewayDashboardBuildSkillSetParams(name: String, enabled: Bool): JsonObject {
    let params = JsonObject()
    params.put("skillKey", JsonString(name.trimAscii()))
    params.put("enabled", JsonBool(enabled))
    params
}

func gatewayDashboardBuildSkillSetRequestParams(name: String, enabled: Bool, apiKey!: String = ""): JsonObject {
    let params = gatewayDashboardBuildSkillSetParams(name, enabled)
    let normalizedApiKey = apiKey.trimAscii()
    if (!normalizedApiKey.isEmpty()) {
        params.put("apiKey", JsonString(normalizedApiKey))
    }
    params
}

func gatewayDashboardBuildChannelsStatusParams(probe: Bool, timeoutMs: Int64): JsonObject {
    let params = JsonObject()
    params.put("probe", probe.toJsonValue())
    params.put("timeoutMs", timeoutMs.toJsonValue())
    params
}

func gatewayDashboardBuildConfigGetParams(path: String): JsonObject {
    let params = JsonObject()
    params.put("path", JsonString(path.trimAscii()))
    params
}

func gatewayDashboardBuildConfigSchemaLookupParams(path: String): JsonObject {
    let normalized = path.trimAscii()
    gatewayDashboardBuildConfigGetParams(if (normalized.isEmpty()) { "gateway" } else { normalized })
}

func gatewayDashboardBuildConfigPatchParams(path: String, raw: String): JsonObject {
    let params = JsonObject()
    params.put("path", JsonString(path.trimAscii()))
    params.put("raw", JsonString(raw))
    params
}

func gatewayDashboardBuildCronPostParams(
    action!: String = "",
    name!: String = "",
    every!: String = "",
    session!: String = "",
    message!: String = "",
    deliveryChannel!: String = "",
    deliveryTo!: String = "",
    deliveryAnnounce!: String = "",
    systemEvent!: String = "",
    wakeMode!: String = "",
    at!: String = "",
    cronExpr!: String = "",
    timeZone!: String = "",
    id!: String = "",
    enabled!: String = "",
    scheduleKind!: String = ""
): JsonObject {
    let params = JsonObject()
    let entries = [
        ("action", action),
        ("name", name),
        ("every", every),
        ("session", session),
        ("message", message),
        ("delivery_channel", deliveryChannel),
        ("delivery_to", deliveryTo),
        ("delivery_announce", deliveryAnnounce),
        ("system_event", systemEvent),
        ("wake_mode", wakeMode),
        ("at", at),
        ("cron_expr", cronExpr),
        ("time_zone", timeZone),
        ("id", id),
        ("enabled", enabled),
        ("schedule_kind", scheduleKind)
    ]
    for ((key, value) in entries) {
        let normalized = value.trimAscii()
        if (!normalized.isEmpty()) {
            params.put(key, JsonString(value))
        }
    }
    params
}

public func gatewayDashboardBuildStatusJson(ctx: HttpContext): String {
    let params = gatewayDashboardBuildStatusParams(limit: gatewayDashboardParseSessionLimit(ctx))
    dashboardGatewayRequest("dashboard.status", params: params)
}

public func gatewayDashboardBuildChatHistoryJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "dashboard.chat.history", ["session"])
}

public func gatewayDashboardHandleChatSend(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(
        ctx,
        "dashboard.chat.send",
        ["session", "text", "message", "deliver", "thinking", "replyChannel", "replyTo", "replyAccount", "idempotencyKey"],
        source: GatewayIngressSource.ControlUi
    )
}

private struct GatewayDashboardModelPreset {
    GatewayDashboardModelPreset(
        let provider: String,
        let suggestedModels: Array<String>
    ) { }
}

private let GATEWAY_DASHBOARD_MODEL_PRESETS = [
    GatewayDashboardModelPreset("ark", ["ark-code-latest", "kimi-k2-250905"]),
    GatewayDashboardModelPreset("moonshot", ["kimi-for-coding", "kimi-k2-0711-preview"]),
    GatewayDashboardModelPreset("zhipuai", ["glm-4.7", "glm-4.5"]),
    GatewayDashboardModelPreset("openai", ["gpt-5", "gpt-5-mini", "gpt-4.1"]),
    GatewayDashboardModelPreset("anthropic", ["claude-sonnet-4-5", "claude-3-7-sonnet-latest"]),
    GatewayDashboardModelPreset("deepseek", ["deepseek-chat"]),
    GatewayDashboardModelPreset("maas", ["qwen2.5-vl-72b"])
]

public func gatewayDashboardBuildModelsJson(): String {
    dashboardGatewayRequest("dashboard.models")
}

public func gatewayDashboardHandleModelSwitch(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "dashboard.model.switch", ["model"])
}

public func gatewayDashboardBuildSkillsJson(): String {
    dashboardGatewayRequest("dashboard.skills")
}

public func gatewayDashboardBuildSkillsCompatibilityJson(): String {
    dashboardGatewayRequest("dashboard.skills.compatibility")
}

public func gatewayDashboardHandleSkillSet(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "dashboard.skills.set", ["name", "skillKey", "enabled", "apiKey"])
}

public func gatewayDashboardHandleSessionsDelete(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "dashboard.sessions.delete", ["keys"])
}

public func gatewayDashboardHandleCronPost(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(
        ctx,
        "dashboard.cron",
        ["action", "name", "every", "session", "message", "delivery_channel", "delivery_to",
         "delivery_announce", "system_event", "wake_mode", "at", "cron_expr", "time_zone",
         "id", "enabled", "schedule_kind"]
    )
}

public func gatewayDashboardBuildDoctorJson(): String {
    dashboardGatewayRequest("doctor")
}

public func gatewayDashboardBuildSessionsJson(): String {
    dashboardGatewayRequest("sessions.list")
}

public func gatewayDashboardBuildSubagentsJson(): String {
    dashboardGatewayRequest("subagents.list")
}

public func gatewayDashboardBuildSubagentStatusJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "subagents.status", ["target", "runId", "sessionKey"])
}

public func gatewayDashboardBuildSubagentLogsJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "subagents.logs", ["target", "runId", "sessionKey"])
}

public func gatewayDashboardHandleSubagentKill(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "subagents.kill", ["target", "runId", "sessionKey"])
}

public func gatewayDashboardBuildChannelsJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "channels.status", ["probe", "timeoutMs"])
}

public func gatewayDashboardBuildChannelsRuntimeJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "channels.runtime", ["channelId", "id", "channel"])
}

public func gatewayDashboardBuildChannelsHealthJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "channels.health", [])
}

func gatewayDashboardChannelsAuditJsonFromRpc(params: JsonObject): String {
    dashboardGatewayRequest("channels.audit", params: gatewayDashboardRequestParams("channels.audit", params))
}

public func gatewayDashboardBuildChannelsAuditJson(ctx!: Option<HttpContext> = None<HttpContext>): String {
    match (ctx) {
        case Some(v) =>
            dashboardGatewayRequestFromForm(v, "channels.audit", ["channelId", "id", "channel"])
        case None =>
            dashboardGatewayRequest("dashboard.channels.audit")
    }
}

public func gatewayDashboardBuildAgentsJson(): String {
    dashboardGatewayRequest("agents.status")
}

public func gatewayDashboardBuildAgentsRuntimeJson(): String {
    dashboardGatewayRequest("agents.runtime")
}

public func gatewayDashboardBuildAgentsRuntimeAuditJson(): String {
    dashboardGatewayRequest("agents.runtime.audit")
}

func gatewayDashboardBuildMemoryStatusParams(agentId: String, requestedBackend: String): JsonObject {
    let params = JsonObject()
    let normalizedAgentId = agentId.trimAscii()
    let normalizedRequestedBackend = requestedBackend.trimAscii()
    if (!normalizedAgentId.isEmpty()) {
        params.put("agentId", JsonString(normalizedAgentId))
    }
    if (!normalizedRequestedBackend.isEmpty()) {
        params.put("backend", JsonString(normalizedRequestedBackend))
    }
    params
}

public func gatewayDashboardBuildMemoryStatusJson(ctx!: Option<HttpContext> = None<HttpContext>): String {
    let agentId = match (ctx) {
        case Some(v) => gatewayDashboardFormValue(v, "agentId").trimAscii()
        case None => ""
    }
    let requestedBackend = match (ctx) {
        case Some(v) => gatewayDashboardFormValue(v, "backend").trimAscii()
        case None => ""
    }
    MemoryStateRegistry.statusJson(
        agentId: agentId,
        purpose: "dashboard-status",
        requestedBackend: requestedBackend,
        deep: true
    )
}

private func gatewayDashboardProbeBool(raw: String): Bool {
    let low = raw.trimAscii().toAsciiLower()
    (low == "true" || low == "1" || low == "yes" || low == "on")
}

public func gatewayDashboardBuildControlUiAssetsJson(): String {
    dashboardGatewayRequest("control_ui.assets")
}

public func gatewayDashboardBuildConfigGetJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "config.get", ["path"])
}

public func gatewayDashboardHandleConfigPatch(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "config.patch", ["path", "raw"])
}

public func gatewayDashboardBuildConfigSchemaJson(ctx: HttpContext): String {
    dashboardGatewayRequestFromForm(ctx, "config.schema.lookup", ["path"])
}

private func gatewayDashboardAppendDeliveryArgs(parts: ArrayList<String>, ctx: HttpContext): Unit {
    let form = ctx.request.form
    let sysEv = match (form.get("system_event")) { case Some(v) => v.trimAscii() case None => "" }
    let wake = match (form.get("wake_mode")) { case Some(v) => v.trimAscii() case None => "" }
    let dCh = match (form.get("delivery_channel")) { case Some(v) => v.trimAscii() case None => "" }
    let dTo = match (form.get("delivery_to")) { case Some(v) => v.trimAscii() case None => "" }
    let ann = match (form.get("delivery_announce")) { case Some(v) => v.trimAscii().toAsciiLower() case None => "false" }
    if (!sysEv.isEmpty()) {
        parts.add("--system-event"); parts.add(sysEv)
    }
    if (!wake.isEmpty()) {
        parts.add("--wake-mode"); parts.add(wake)
    }
    if (!dCh.isEmpty()) {
        parts.add("--channel"); parts.add(dCh)
    }
    if (!dTo.isEmpty()) {
        parts.add("--to"); parts.add(dTo)
    }
    if (ann == "true" || ann == "1" || ann == "yes" || ann == "on") {
        parts.add("--announce")
    }
}

private func gatewayDashboardRunCronJobNow(jobId: String): (Bool, String) {
    let path = cronStorePath(CliConfig.dotDir)
    let list = ArrayList<CronJob>()
    var found = false
    var foundJob = None<CronJob>
    for (j in cronLoadOrEmpty(path)) {
        if (!found && j.id == jobId) {
            found = true
            foundJob = Some(j)
        }
        list.add(j)
    }
    if (!found) {
        return (false, "未找到任务 id=${jobId}")
    }
    let startedAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
    try {
        let params = gatewayDashboardBuildCronRunNowParams(foundJob.getOrThrow())
        let result = gatewayExecuteChatTurnFromRpc(params, fallbackSource: GatewayIngressSource.Cron)
        if (let Some(error) <- result.get("error")) {
            return (false, "运行失败: ${error.asString().getValue()}")
        }
    } catch (ex: Exception) {
        for (jx in list) {
            if (jx.id == jobId) {
                jx.state.lastError = ex.message
                jx.state.lastRunAtMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
                break
            }
        }
        cronSave(path, list.toArray())
        return (false, "运行失败: ${ex.message}")
    }
    for (jx in list) {
        if (jx.id != jobId) {
            continue
        }
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        jx.state.lastError = ""
        jx.state.lastRunAtMs = startedAtMs
        let sk = jx.schedule.kind.trimAscii().toAsciiLower()
        if (sk == "at") {
            jx.enabled = false
            jx.state.nextRunAtMs = 0
        } else {
            match (computeJobNextRun(jx, nowMs)) {
                case Some(nxt) =>
                    var nn = nxt
                    if (sk == "cron") {
                        let minNext = nowMs + 2000
                        if (nn < minNext) {
                            nn = minNext
                        }
                    }
                    jx.state.nextRunAtMs = nn
                case None => jx.state.nextRunAtMs = 0
            }
        }
        break
    }
    cronSave(path, list.toArray())
    (true, "已立即运行任务 id=${jobId}")
}

func gatewayDashboardBuildCronRunNowParams(job: CronJob): JsonObject {
    let resolvedSessionKey = match (job.sessionKey.trimAscii()) {
        case "" => conversationKeyForCronTarget(job.id, job.sessionTarget)
        case key => key
    }
    let deliver = !job.deliveryChannel.trimAscii().isEmpty() && !job.deliveryTo.trimAscii().isEmpty()
    gatewayBuildSessionRpcParams(
        GatewayIngressSource.Cron,
        session: resolvedSessionKey,
        text: job.prompt,
        channel: "cron",
        agentId: job.agentId,
        deliver: deliver,
        thinking: job.thinkingLevel,
        timeoutSeconds: if (job.timeoutMs > 0) { job.timeoutMs / 1000 } else { 0 },
        bestEffortDeliver: job.bestEffortDeliver,
        replyChannel: job.deliveryChannel,
        replyTo: job.deliveryTo,
        replyAccount: job.deliveryAccountId
    )
}

private func gatewayDashboardParseSessionLimit(ctx: HttpContext): Int64 {
    let raw = match (ctx.request.form.get("limit")) {
        case Some(v) => v.trimAscii()
        case None => ""
    }
    if (raw.isEmpty()) {
        return 120
    }
    try {
        let n = Int64.parse(raw)
        if (n > 0 && n <= 5000) {
            return n
        }
    } catch (_e: Exception) {
        ()
    }
    120
}

private func gatewayDashboardAppendCronJson(sb: StringBuilder): Unit {
    let cronPath = cronStorePath(CliConfig.dotDir)
    let jobs = cronLoadOrEmpty(cronPath)
    sb.append("\"cron\":{")
    sb.append("\"storePath\":\"${gatewayDashboardJsonEscape(cronPath.toString())}\",")
    sb.append("\"jobs\":[")
    var first = true
    for (j in jobs) {
        if (!first) { sb.append(",") }
        first = false
        sb.append("{")
        sb.append("\"id\":\"${gatewayDashboardJsonEscape(j.id)}\",")
        sb.append("\"enabled\":${j.enabled},")
        sb.append("\"prompt\":\"${gatewayDashboardJsonEscape(j.prompt)}\",")
        sb.append("\"sessionTarget\":\"${gatewayDashboardJsonEscape(j.sessionTarget)}\",")
        sb.append("\"schedule\":{")
        sb.append("\"kind\":\"${gatewayDashboardJsonEscape(j.schedule.kind)}\",")
        sb.append("\"everyMs\":${j.schedule.everyMs},")
        sb.append("\"anchorMs\":${j.schedule.anchorMs},")
        sb.append("\"atMs\":${j.schedule.atMs},")
        sb.append("\"cronExpr\":\"${gatewayDashboardJsonEscape(j.schedule.cronExpr)}\",")
        sb.append("\"timeZone\":\"${gatewayDashboardJsonEscape(j.schedule.timeZone)}\",")
        sb.append("\"staggerMs\":${j.schedule.staggerMs}")
        sb.append("},")
        sb.append("\"systemEvent\":\"${gatewayDashboardJsonEscape(j.systemEvent)}\",")
        sb.append("\"wakeMode\":\"${gatewayDashboardJsonEscape(j.wakeMode)}\",")
        sb.append("\"deliveryChannel\":\"${gatewayDashboardJsonEscape(j.deliveryChannel)}\",")
        sb.append("\"deliveryTo\":\"${gatewayDashboardJsonEscape(j.deliveryTo)}\",")
        sb.append("\"deliveryAnnounce\":${j.deliveryAnnounce},")
        sb.append("\"payloadKind\":\"${gatewayDashboardJsonEscape(j.payloadKind)}\",")
        sb.append("\"deliveryMode\":\"${gatewayDashboardJsonEscape(j.deliveryMode)}\",")
        sb.append("\"failureDestMode\":\"${gatewayDashboardJsonEscape(j.failureDestMode)}\",")
        sb.append("\"state\":{")
        sb.append("\"nextRunAtMs\":${j.state.nextRunAtMs},")
        sb.append("\"lastRunAtMs\":${j.state.lastRunAtMs},")
        sb.append("\"lastError\":\"${gatewayDashboardJsonEscape(j.state.lastError)}\"")
        sb.append("}")
        sb.append("}")
    }
    sb.append("]")
    sb.append("},")
}

private func gatewayDashboardPickLast(items: Array<String>, maxItems: Int64): Array<String> {
    if (items.size <= maxItems) {
        return items
    }
    items[(items.size - maxItems)..items.size]
}

private func gatewayDashboardSummarizeRawTranscript(raw: String): (Int64, Int64, String, String) {
    let objs = gatewayDashboardParseJsonObjectsFromRaw(raw)
    var count: Int64 = 0
    var approx: Int64 = 0
    var lastTs = ""
    var lastRole = ""
    for (o in objs) {
        let kind = match (o.get("kind")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        if (kind == "meta") {
            continue
        }
        let role = match (o.get("role")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        let text = match (o.get("text")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        let ts = match (o.get("ts")) {
            case Some(v) => v.asString().getValue()
            case None => ""
        }
        if (!role.isEmpty() || !text.isEmpty()) {
            count += 1
            approx += text.size / 4
            if (!ts.isEmpty()) {
                lastTs = ts
            }
            if (!role.isEmpty()) {
                lastRole = role
            }
        }
    }
    (count, approx, lastTs, lastRole)
}

func gatewayDashboardSummarizeConversation(user: GatewayUserSettings, view: GatewaySessionConversationView): (Int64, Int64, String, String) {
    let store = gatewaySessionStoreForUserWithAgentId(user, view.agentId)
    match (store.readTranscriptRaw(view.key)) {
        case Some(raw) => gatewayDashboardSummarizeRawTranscript(raw)
        case None => (0, 0, "", "")
    }
}

func gatewayDashboardSummarizeSession(sessionKey: String): (Int64, Int64, String, String) {
    let user = CliSettingManager.readGatewaySettings()
    match (gatewayFindSessionConversationViewForUser(user, sessionKey)) {
        case Some(view) => return gatewayDashboardSummarizeConversation(user, view)
        case None => ()
    }
    let store = gatewaySessionStoreForSessionKey(user, sessionKey)
    match (store.readTranscriptRaw(sessionKey)) {
        case Some(raw) => gatewayDashboardSummarizeRawTranscript(raw)
        case None => (0, 0, "", "")
    }
}

private func gatewayDashboardParseJsonObjectsFromRaw(raw: String): ArrayList<JsonObject> {
    let out = ArrayList<JsonObject>()
    let lines = raw.split("\n")
    var buffer = ""
    for (line in lines) {
        if (buffer.isEmpty() && line.trimAscii().isEmpty()) {
            continue
        }
        buffer = if (buffer.isEmpty()) { line } else { buffer + "\n" + line }
        let s = buffer.trimAscii()
        try {
            out.add(JsonValue.fromStr(s).asObject())
            buffer = ""
        } catch (_e: Exception) {
            ()
        }
    }
    out
}

private func gatewayDashboardReadLatestLogTail(maxLines: Int64): (String, Array<String>) {
    let dir = CliConfig.logsDir
    if (!exists(dir)) {
        return ("", [])
    }
    var latestName = ""
    try {
        for (entry in Directory.readFrom(dir)) {
            if (!entry.isRegular()) {
                continue
            }
            let n = entry.name
            if (!n.endsWith(".log")) {
                continue
            }
            if (latestName.isEmpty() || n > latestName) {
                latestName = n
            }
        }
    } catch (_e: Exception) {
        return ("", [])
    }
    if (latestName.isEmpty()) {
        return ("", [])
    }
    let p = dir.join(latestName)
    try {
        let text = String.fromUtf8(File.readFrom(p))
        let lines = text.split("\n")
        return (latestName, gatewayDashboardPickLast(lines, maxLines))
    } catch (_e: Exception) {
        return (latestName, [])
    }
}

private func gatewayDashboardJsonEscape(raw: String): String {
    raw
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}

private func gatewayDashboardAppendGatewayChannelsJson(sb: StringBuilder, gw: GatewayUserSettings): Unit {
    sb.append("\"channels\":[")
    var first = true
    var fsModel = ""
    var qqModel = ""
    for ((ck, cv) in gw.channelModels) {
        let kk = ck.trimAscii()
        if (kk == "feishu") {
            fsModel = cv
        }
        if (kk == "qq") {
            qqModel = cv
        }
    }
    if (gw.feishu.enabled) {
        if (!first) {
            sb.append(",")
        }
        first = false
        sb.append("{")
        sb.append("\"id\":\"feishu\",")
        sb.append("\"enabled\":true,")
        sb.append("\"tenantKey\":\"${gatewayDashboardJsonEscape(gw.feishu.appId)}\",")
        sb.append("\"model\":\"${gatewayDashboardJsonEscape(fsModel)}\",")
        sb.append("\"mode\":\"${gatewayDashboardJsonEscape(gw.feishu.receiveMode)}\",")
        sb.append("\"groupSessionScope\":\"${gatewayDashboardJsonEscape(gw.feishu.groupSessionScope)}\",")
        sb.append("\"replyInThread\":\"${gatewayDashboardJsonEscape(gw.feishu.replyInThread)}\",")
        sb.append("\"webhookBase\":\"http://${gatewayDashboardJsonEscape(gw.feishu.webhookHost)}:${gw.feishu.webhookPort}\"")
        sb.append("}")
    }
    if (gw.qq.enabled) {
        if (!first) {
            sb.append(",")
        }
        first = false
        sb.append("{")
        sb.append("\"id\":\"qq\",")
        sb.append("\"enabled\":true,")
        sb.append("\"appId\":\"${gatewayDashboardJsonEscape(gw.qq.appId)}\",")
        sb.append("\"mode\":\"${gatewayDashboardJsonEscape(gw.qq.mode)}\",")
        sb.append("\"model\":\"${gatewayDashboardJsonEscape(qqModel)}\",")
        sb.append("\"webhookBase\":\"http://${gatewayDashboardJsonEscape(gw.qq.webhookHost)}:${gw.qq.webhookPort}\"")
        sb.append("}")
    }
    sb.append("],")
}

private func gatewayDashboardIsGatewayServeRunningNow(): Bool {
    exists(CliConfig.dotDir.join("gateway-serve.lock"))
}
