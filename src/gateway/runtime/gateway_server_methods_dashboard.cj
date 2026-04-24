package metis.gateway.runtime

import magic.prelude.*
import magic.jsonable.*

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager, skillEntryEnabled}
import metis.core.model.CliModelManager
import metis.core.skills.{SkillsPrompt, skillsSourceTagForLocation}
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.core.{
    gatewayBuildSessionConversationView,
    GatewaySessionCatalogRow,
    GatewaySessionConversationView,
    gatewayListSessionCatalogRowsForUser,
    gatewayListSessionConversationViewsForUser,
    gatewayProjectSessionCatalogRow,
    GatewaySessionStore,
    gatewaySessionStoreForUserWithAgentId
}
import metis.gateway.session.{GatewayIngressSource, gatewayBuildSessionRpcParams, gatewayIngressSourceFromString, gatewayResolveSessionContext, gatewaySessionRequestFromRpcParams}
import metis.cron.{cronDashboardSaveJob, cronLoadOrEmpty, cronSave, cronStorePath, readCronRunLogMergedFromStore}

import std.collection.{ArrayList, HashMap, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, FileInfo, exists, Path}
import std.sort.sort
import std.time.DateTime
import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}

private var gatewayDashboardChatHistoryCacheBySession = HashMap<String, String>()
private var gatewayDashboardChatHistoryMtimeBySession = HashMap<String, Int64>()

private func gatewayDashboardJsonRpcResponse(method: String, json: String): GatewayRpcResponse {
    let result = JsonValue.fromStr(json).asObject()
    GatewayRpcResponse(true, method, result: result)
}

private func gatewayDashboardChatSendRpcResponse(method: String, json: String): GatewayRpcResponse {
    let result = JsonValue.fromStr(json).asObject()
    match (result.get("error")) {
        case Some(v) =>
            let err = try { v.asString().getValue() } catch (_: Exception) { "dashboard chat send failed" }
            GatewayRpcResponse(false, method, result: result, error: err)
        case None =>
            GatewayRpcResponse(true, method, result: result)
    }
}

public func handleGatewayDashboardFamily(method: String, request: GatewayRpcRequest): Option<GatewayRpcResponse> {
    if (method == "dashboard.status") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardStatusJsonFromRpc(request.params)))
    }
    if (method == "dashboard.chat.history") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardChatHistoryJsonFromRpc(request.params)))
    }
    if (method == "dashboard.chat.send") {
        return Some(gatewayDashboardChatSendRpcResponse(method, gatewayDashboardChatSendJsonFromRpc(request.params)))
    }
    if (method == "dashboard.models") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardModelsJson()))
    }
    if (method == "dashboard.model.switch") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardModelSwitchJsonFromRpc(request.params)))
    }
    if (method == "dashboard.skills") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardSkillsJson()))
    }
    if (method == "dashboard.skills.compatibility") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardSkillsCompatibilityJson()))
    }
    if (method == "dashboard.agents.runtime") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardBuildAgentsRuntimeJson()))
    }
    if (method == "dashboard.agents.runtime.audit") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardBuildAgentsRuntimeAuditJson()))
    }
    if (method == "dashboard.channels.audit") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardChannelsAuditJsonFromRpc(request.params)))
    }
    if (method == "dashboard.skills.set") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardSkillSetJsonFromRpc(request.params)))
    }
    if (method == "dashboard.sessions.delete") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardSessionsDeleteJsonFromRpc(request.params)))
    }
    if (method == "dashboard.cron") {
        return Some(gatewayDashboardJsonRpcResponse(method, gatewayDashboardCronJsonFromRpc(request.params)))
    }
    None
}

private func rpcString(params: JsonObject, key: String): String {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_e: Exception) { "" }
        case None => ""
    }
}

private func rpcInt(params: JsonObject, key: String, fallback: Int64): Int64 {
    match (params.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.asString().getValue())
            } catch (_e: Exception) {
                try {
                    Int64.parse(v.toJsonString())
                } catch (_e2: Exception) {
                    fallback
                }
            }
        case None => fallback
    }
}

private func rpcBool(params: JsonObject, key: String, fallback: Bool): Bool {
    match (params.get(key)) {
        case Some(v) =>
            try { v.asBool().getValue() } catch (_e: Exception) {
                try {
                    let low = v.asString().getValue().trimAscii().toAsciiLower()
                    low == "true" || low == "1" || low == "yes" || low == "on"
                } catch (_e2: Exception) {
                    fallback
                }
            }
        case None => fallback
    }
}

private func gatewayDashboardSessionStoreForRequest(user: GatewayUserSettings, sessionKey: String, agentId: String): GatewaySessionStore {
    gatewayRuntimeSessionStoreForRequest(user, sessionKey, agentId)
}

public func gatewayDashboardResolvedContextFromRpc(params: JsonObject, sessionOverride!: String = "") {
    let effectiveSession = if (!sessionOverride.trimAscii().isEmpty()) { sessionOverride.trimAscii() } else { rpcString(params, "session").trimAscii() }
    let requestParams = gatewayBuildSessionRpcParams(
        gatewayIngressSourceFromString(rpcString(params, "source").trimAscii(), fallback: GatewayIngressSource.DashboardRpc),
        session: effectiveSession,
        channel: rpcString(params, "channel").trimAscii(),
        agentId: rpcString(params, "agentId").trimAscii(),
        to: rpcString(params, "to").trimAscii(),
        lane: rpcString(params, "lane").trimAscii()
    )
    gatewayResolveSessionContext(gatewaySessionRequestFromRpcParams(requestParams, fallbackSource: GatewayIngressSource.DashboardRpc))
}

private func dashboardSessionTranscriptMtimeMillis(store: GatewaySessionStore, sessionKey: String): Int64 {
    let p = store.transcriptPath(sessionKey)
    if (!exists(p)) {
        return 0
    }
    try {
        FileInfo(p).lastModificationTime.toUnixTimeStamp().toMilliseconds()
    } catch (_: Exception) {
        0
    }
}

/** 按转录文件修改时间降序取前 n 个会话（避免对未排序的 listSessionKeys 误用 pickLast）。 */
private func dashboardTakeMostRecentSessions(store: GatewaySessionStore, keys: Array<String>, n: Int64): Array<String> {
    if (n <= 0 || keys.isEmpty()) {
        return []
    }
    let keysMut = ArrayList<String>()
    for (k in keys) {
        keysMut.add(k)
    }
    sort(
        keysMut,
        by: { a, b => dashboardSessionTranscriptMtimeMillis(store, b).compare(dashboardSessionTranscriptMtimeMillis(store, a)) },
        stable: true
    )
    let arr = keysMut.toArray()
    if (arr.size <= n) {
        return arr
    }
    arr[0..n]
}

public func dashboardTakeMostRecentSessionViews(user: GatewayUserSettings, n: Int64): Array<GatewaySessionConversationView> {
    if (n <= 0) {
        return []
    }
    let items = ArrayList<GatewaySessionConversationView>()
    for (entry in gatewayListSessionConversationViewsForUser(user)) {
        items.add(entry)
    }
    sort(
        items,
        by: { a, b => b.updatedAt.compare(a.updatedAt) },
        stable: true
    )
    let arr = items.toArray()
    if (arr.size <= n) {
        return arr
    }
    arr[0..n]
}

func dashboardBuildSessionsJson(user: GatewayUserSettings, limitN: Int64): JsonObject {
    let catalogRows = gatewayListSessionCatalogRowsForUser(user)
    let sessions = JsonObject()
    let storageRoots = gatewaySessionStorageRootsForUser(user)
    sessions.put("root", JsonString(storageRoots[0]))

    let roots = JsonArray([])
    for (root in storageRoots) {
        roots.add(JsonString(root))
    }
    sessions.put("storageRoots", roots)
    sessions.put("count", JsonValue.fromStr("${catalogRows.size}"))

    let recent = JsonArray([])
    let details = JsonArray([])
    let detailCount = min(limitN, Int64(catalogRows.size))
    for (i in 0..detailCount) {
        let entry: GatewaySessionCatalogRow = catalogRows[i]
        let view = gatewayBuildSessionConversationView(gatewayProjectSessionCatalogRow(entry))
        recent.add(JsonString(entry.sessionKey))
        let row = JsonObject()
        row.put("key", JsonString(view.key))
        row.put("displayName", JsonString(view.displayName))
        row.put("agentId", JsonString(view.agentId))
        row.put("sessionId", JsonString(view.sessionId))
        row.put("sessionFile", JsonString(view.sessionFile))
        row.put("root", JsonString(view.root.toString()))
        row.put("channel", JsonString(view.channel))
        row.put("chatType", JsonString(view.chatType))
        row.put("peer", JsonString(view.peer))
        row.put("origin", view.origin)
        row.put("delivery", view.delivery)
        row.put("binding", view.binding)
        row.put("messageCount", JsonValue.fromStr("0"))
        row.put("tokenApprox", entry.totalTokens.toJsonValue())
        row.put("updatedAt", view.updatedAt.toJsonValue())
        row.put("updatedTs", JsonString("${entry.updatedAt}"))
        row.put("lastRole", JsonString(""))
        if (!entry.lastChannel.isEmpty()) {
            row.put("lastChannel", JsonString(entry.lastChannel))
        }
        if (!entry.lastTo.isEmpty()) {
            row.put("lastTo", JsonString(entry.lastTo))
        }
        if (!entry.lastAccountId.isEmpty()) {
            row.put("lastAccountId", JsonString(entry.lastAccountId))
        }
        if (entry.lastThreadId > 0) {
            row.put("lastThreadId", entry.lastThreadId.toJsonValue())
        }
        details.add(row)
    }
    sessions.put("recent", recent)
    sessions.put("details", details)
    sessions
}

public func gatewayDashboardStatusJsonFromRpc(params: JsonObject): String {
    let limitN = rpcInt(params, "limit", 120)
    let model = CliConfig.modelOrEmpty()
    let skillsEnabled = CliSettingManager.readSkillsEnabled()
    let skillLines = SkillsPrompt.listSkillStatusLines()
    let gw = CliSettingManager.readGatewaySettings()
    let gatewayCfg = buildGatewayConfigFromUserSettings(gw)
    let binding = GatewayControlUiRuntime.controlUiBinding(gatewayCfg)
    let gatewayRunning = exists(CliConfig.dotDir.join("gateway-serve.lock"))
    let (latestLogFile, logTail) = dashboardReadLatestLogTail(80)
    let sessionsJson = dashboardBuildSessionsJson(gw, limitN)
    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"model\":\"${dashboardJsonEscape(model)}\",")
    sb.append("\"skillsEnabled\":${skillsEnabled},")
    sb.append("\"skills\":[")
    var first = true
    for (line in skillLines) {
        if (!first) { sb.append(",") }
        first = false
        sb.append("\"${dashboardJsonEscape(line)}\"")
    }
    sb.append("],")
    sb.append("\"gateway\":{")
    sb.append("\"enabled\":${gw.enabled},")
    sb.append("\"running\":${gatewayRunning},")
    sb.append("\"feishuEnabled\":${gw.feishu.enabled},")
    sb.append("\"qqEnabled\":${gw.qq.enabled},")
    sb.append("\"channelModels\":{")
    var firstCm = true
    for ((k, v) in gw.channelModels) {
        let kk = k.trimAscii()
        let vv = v.trimAscii()
        if (kk.isEmpty() || vv.isEmpty()) { continue }
        if (!firstCm) { sb.append(",") }
        firstCm = false
        sb.append("\"${dashboardJsonEscape(kk)}\":\"${dashboardJsonEscape(vv)}\"")
    }
    sb.append("}")
    sb.append("},")
    dashboardAppendGatewayChannelsJson(sb, gw)
    sb.append("\"dashboard\":{")
    sb.append("\"wsUrl\":\"${dashboardJsonEscape(binding.wsUrl)}\",")
    sb.append("\"httpUrl\":\"${dashboardJsonEscape(binding.httpUrl)}\"")
    sb.append("},")
    sb.append("\"sessions\":")
    sb.append(sessionsJson.toJsonString())
    sb.append(",")
    sb.append("\"chat\":{\"recentMessages\":[]},")
    dashboardAppendCronJson(sb)
    sb.append("\"logs\":{")
    sb.append("\"latestFile\":\"${dashboardJsonEscape(latestLogFile)}\",")
    sb.append("\"tail\":[")
    var firstLog = true
    for (line in logTail) {
        if (!firstLog) { sb.append(",") }
        firstLog = false
        sb.append("\"${dashboardJsonEscape(line)}\"")
    }
    sb.append("]")
    sb.append("}")
    sb.append("}")
    sb.toString()
}

public func gatewayDashboardChatHistoryJsonFromRpc(params: JsonObject): String {
    let context = gatewayDashboardResolvedContextFromRpc(params)
    let sessionKey = context.sessionKey
    let histStore = gatewayDashboardSessionStoreForRequest(
        CliSettingManager.readGatewaySettings(),
        context.sessionKey,
        context.agentId
    )
    let transcriptMtime = if (sessionKey.isEmpty()) { 0 } else { dashboardSessionTranscriptMtimeMillis(histStore, sessionKey) }
    if (!sessionKey.isEmpty()) {
        if (let Some(cachedMtime) <- gatewayDashboardChatHistoryMtimeBySession.get(sessionKey)) {
            if (cachedMtime == transcriptMtime) {
                if (let Some(cachedJson) <- gatewayDashboardChatHistoryCacheBySession.get(sessionKey)) {
                    return cachedJson
                }
            }
        }
    }
    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"session\":\"${dashboardJsonEscape(sessionKey)}\",")
    sb.append("\"messages\":[")
    if (!sessionKey.isEmpty()) {
        if (let Some(raw) <- histStore.readTranscriptRaw(sessionKey)) {
            let objs = dashboardParseJsonObjectsFromRaw(raw)
            var first = true
            for (o in objs) {
                let kind = match (o.get("kind")) { case Some(v) => v.asString().getValue() case None => "" }
                if (kind == "meta") { continue }
                let role = match (o.get("role")) { case Some(v) => v.asString().getValue() case None => "" }
                let text = match (o.get("text")) { case Some(v) => v.asString().getValue() case None => "" }
                let ts = match (o.get("ts")) { case Some(v) => v.asString().getValue() case None => "" }
                if (role.isEmpty() && text.isEmpty()) { continue }
                if (!first) { sb.append(",") }
                first = false
                sb.append("{")
                sb.append("\"role\":\"${dashboardJsonEscape(role)}\",")
                sb.append("\"text\":\"${dashboardJsonEscape(text)}\",")
                sb.append("\"ts\":\"${dashboardJsonEscape(ts)}\"")
                sb.append("}")
            }
        }
    }
    sb.append("]")
    sb.append("}")
    let json = sb.toString()
    if (!sessionKey.isEmpty()) {
        gatewayDashboardChatHistoryMtimeBySession[sessionKey] = transcriptMtime
        gatewayDashboardChatHistoryCacheBySession[sessionKey] = json
    }
    json
}

public func gatewayDashboardChatSendJsonFromRpc(params: JsonObject): String {
    gatewayExecuteChatTurnFromRpc(params, fallbackSource: GatewayIngressSource.DashboardRpc).toJsonString()
}

private struct DashboardModelPreset {
    DashboardModelPreset(let provider: String, let suggestedModels: Array<String>) { }
}

private let DASHBOARD_MODEL_PRESETS = [
    DashboardModelPreset("ark", ["ark-code-latest", "kimi-k2-250905"]),
    DashboardModelPreset("moonshot", ["kimi-for-coding", "kimi-k2-0711-preview"]),
    DashboardModelPreset("zhipuai", ["glm-4.7", "glm-4.5"]),
    DashboardModelPreset("openai", ["gpt-5", "gpt-5-mini", "gpt-4.1"]),
    DashboardModelPreset("anthropic", ["claude-sonnet-4-5", "claude-3-7-sonnet-latest"]),
    DashboardModelPreset("deepseek", ["deepseek-chat"]),
    DashboardModelPreset("maas", ["qwen2.5-vl-72b"])
]

private func gatewayDashboardModelsJson(): String {
    let current = CliConfig.modelOrEmpty()
    let namesSet = HashSet<String>()
    let names = ArrayList<String>()
    for (preset in DASHBOARD_MODEL_PRESETS) {
        let key = MetisConfigManager.readProviderApiKey(preset.provider).trimAscii()
        if (key.isEmpty()) { continue }
        for (mid in preset.suggestedModels) {
            let id = mid.trimAscii()
            if (id.isEmpty()) { continue }
            let full = "${preset.provider}:${id}"
            if (!namesSet.contains(full)) {
                namesSet.add(full)
                names.add(full)
            }
        }
    }
    if (!current.isEmpty() && !namesSet.contains(current)) {
        names.add(current)
    }
    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"current\":\"${dashboardJsonEscape(current)}\",")
    sb.append("\"candidates\":[")
    var first = true
    for (n in names) {
        if (!first) { sb.append(",") }
        first = false
        sb.append("\"${dashboardJsonEscape(n)}\"")
    }
    sb.append("]")
    sb.append("}")
    sb.toString()
}

private func gatewayDashboardModelSwitchJsonFromRpc(params: JsonObject): String {
    let modelName = rpcString(params, "model").trimAscii()
    if (modelName.isEmpty()) {
        return "{\"ok\":false,\"message\":\"model is empty\"}"
    }
    let saved = !MetisConfigManager.setPrimaryModelRef(modelName).trimAscii().isEmpty()
    CliModelManager.resetRuntimeState()
    "{\"ok\":${saved},\"current\":\"${dashboardJsonEscape(CliConfig.modelOrEmpty())}\"}"
}

private func gatewayDashboardSkillsJson(): String {
    match (handleGatewaySkillsFamily("skills.status")) {
        case Some(response) =>
            response.result.toJsonString()
        case None =>
            "{\"skills\":[]}"
    }
}

private func gatewayDashboardSkillsCompatibilityJson(): String {
    match (handleGatewaySkillsFamily("skills.compatibilityMatrix")) {
        case Some(response) =>
            response.result.toJsonString()
        case None =>
            "{\"kind\":\"skills-compatibility-matrix\",\"summary\":{},\"rows\":[]}"
    }
}

private func gatewayDashboardSkillSourceLabel(location: String): String {
    skillsSourceTagForLocation(location)
}

private func gatewayDashboardSkillCategoryFromSource(source: String): String {
    match (source) {
        case "metis-bundled" => "built-in"
        case "metis-managed" => "managed"
        case "agents-skills-project" => "agent"
        case "agents-skills-personal" => "agent"
        case "metis-workspace" => "workspace"
        case "metis-extra" => "extra"
        case _ => "other"
    }
}

private func gatewayDashboardSkillSetJsonFromRpc(params: JsonObject): String {
    match (handleGatewaySkillsFamily("skills.update", request: Some(GatewayRpcRequest("skills.update", params: params)))) {
        case Some(response) => response.result.toJsonString()
        case None => "{\"ok\":false,\"message\":\"skills.update unavailable\"}"
    }
}

public func gatewayDashboardSessionsDeleteJsonFromRpc(params: JsonObject): String {
    let keysRaw = rpcString(params, "keys").trimAscii()
    if (keysRaw.isEmpty()) {
        return "{\"ok\":false,\"message\":\"keys is empty\"}"
    }
    let parts = keysRaw.split("\n")
    let deleted = ArrayList<String>()
    let failed = ArrayList<String>()
    for (p in parts) {
        let k = p.trimAscii()
        if (k.isEmpty()) { continue }
        let context = gatewayDashboardResolvedContextFromRpc(params, sessionOverride: k)
        let delStore = gatewayDashboardSessionStoreForRequest(
            CliSettingManager.readGatewaySettings(),
            context.sessionKey,
            context.agentId
        )
        if (delStore.deleteSession(context.sessionKey)) { deleted.add(context.sessionKey) } else { failed.add(context.sessionKey) }
    }
    let sb = StringBuilder()
    sb.append("{\"ok\":true,\"deleted\":[")
    var first = true
    for (k in deleted.toArray()) {
        if (!first) { sb.append(",") }
        first = false
        sb.append("\"${dashboardJsonEscape(k)}\"")
    }
    sb.append("],\"failed\":[")
    var first2 = true
    for (k in failed.toArray()) {
        if (!first2) { sb.append(",") }
        first2 = false
        sb.append("\"${dashboardJsonEscape(k)}\"")
    }
    sb.append("]}")
    sb.toString()
}

private func gatewayDashboardCronJsonFromRpc(params: JsonObject): String {
    let action = rpcString(params, "action").trimAscii().toAsciiLower()
    if (action.isEmpty()) {
        return "{\"ok\":false,\"message\":\"action is empty\"}"
    }
    if (action == "save_job") {
        let jobId = rpcString(params, "id").trimAscii()
        let message = rpcString(params, "message")
        let session = if (rpcString(params, "session").trimAscii().isEmpty()) { "main" } else { rpcString(params, "session").trimAscii() }
        let enStr = if (rpcString(params, "enabled").trimAscii().isEmpty()) { "true" } else { rpcString(params, "enabled").trimAscii().toAsciiLower() }
        let scheduleKind = if (rpcString(params, "schedule_kind").trimAscii().isEmpty()) { "every" } else { rpcString(params, "schedule_kind").trimAscii() }
        let everyRaw = rpcString(params, "every").trimAscii()
        let atRaw = rpcString(params, "at").trimAscii()
        if (jobId.isEmpty() || message.trimAscii().isEmpty()) {
            return "{\"ok\":false,\"message\":\"id or message empty\"}"
        }
        let enabled = enStr == "true" || enStr == "1" || enStr == "yes"
        let cronEx = rpcString(params, "cron_expr").trimAscii()
        let tz = if (rpcString(params, "time_zone").trimAscii().isEmpty()) { "UTC" } else { rpcString(params, "time_zone").trimAscii() }
        let sysEv = rpcString(params, "system_event").trimAscii()
        let wake = rpcString(params, "wake_mode").trimAscii()
        let dCh = rpcString(params, "delivery_channel").trimAscii()
        let dTo = rpcString(params, "delivery_to").trimAscii()
        let annStr = if (rpcString(params, "delivery_announce").trimAscii().isEmpty()) { "false" } else { rpcString(params, "delivery_announce").trimAscii().toAsciiLower() }
        let dAnn = annStr == "true" || annStr == "1" || annStr == "yes" || annStr == "on"
        let path = cronStorePath(CliConfig.dotDir)
        let (out, code) = cronDashboardSaveJob(path, jobId, message, session, enabled, scheduleKind, everyRaw, atRaw, cronEx, tz, sysEv, wake, dCh, dTo, dAnn)
        return "{\"ok\":${code == 0},\"code\":${code},\"message\":\"${dashboardJsonEscape(out)}\"}"
    } else if (action == "run_once") {
        let jobId = rpcString(params, "id").trimAscii()
        if (jobId.isEmpty()) {
            return "{\"ok\":false,\"message\":\"id is empty\"}"
        }
        let (okNow, outNow) = dashboardRunCronJobNow(jobId)
        return "{\"ok\":${okNow},\"code\":${if (okNow) { 0 } else { 1 }},\"message\":\"${dashboardJsonEscape(outNow)}\"}"
    }
    let parts = ArrayList<String>()
    parts.add("cron")
    match (gatewayCronFillArgvForDashboardAction(parts, action, params)) {
        case Some(err) => return "{\"ok\":false,\"message\":\"${dashboardJsonEscape(err)}\"}"
        case None => ()
    }
    let pair = gatewayExecuteCronWithUnifiedRun(parts.toArray())
    return "{\"ok\":${pair[1] == 0},\"code\":${pair[1]},\"message\":\"${dashboardJsonEscape(pair[0])}\"}"
}

private func dashboardRunCronJobNow(jobId: String): (Bool, String) {
    var found = false
    for (j in cronLoadOrEmpty(cronStorePath(CliConfig.dotDir))) {
        if (j.id == jobId) {
            found = true
            break
        }
    }
    if (!found) {
        return (false, "未找到任务 id=${jobId}")
    }
    gatewayCronRunOnceOutcome(jobId, true)
}

private func dashboardPickLast(items: Array<String>, n: Int64): Array<String> {
    if (n <= 0 || items.isEmpty()) { return [] }
    if (items.size <= n) { return items }
    let start = items.size - n
    items[start..items.size]
}

private func dashboardSummarizeSession(store: GatewaySessionStore, sessionKey: String): (Int64, Int64, String, String) {
    if (let Some(raw) <- store.readTranscriptRaw(sessionKey)) {
        let objs = dashboardParseJsonObjectsFromRaw(raw)
        var msgCount: Int64 = 0
        var tokenApprox: Int64 = 0
        var updatedTs = ""
        var lastRole = ""
        for (o in objs) {
            let kind = match (o.get("kind")) { case Some(v) => v.asString().getValue() case None => "" }
            if (kind == "meta") { continue }
            let role = match (o.get("role")) { case Some(v) => v.asString().getValue() case None => "" }
            let text = match (o.get("text")) { case Some(v) => v.asString().getValue() case None => "" }
            let ts = match (o.get("ts")) { case Some(v) => v.asString().getValue() case None => "" }
            if (!role.isEmpty() || !text.isEmpty()) { msgCount += 1 }
            if (!text.isEmpty()) { tokenApprox += max(1, text.size / 4) }
            if (!ts.isEmpty()) { updatedTs = ts }
            if (!role.isEmpty()) { lastRole = role }
        }
        return (msgCount, tokenApprox, updatedTs, lastRole)
    }
    (0, 0, "", "")
}

private func dashboardParseJsonObjectsFromRaw(raw: String): ArrayList<JsonObject> {
    let out = ArrayList<JsonObject>()
    let lines = raw.split("\n")
    var buffer = ""
    for (line in lines) {
        if (buffer.isEmpty() && line.trimAscii().isEmpty()) { continue }
        buffer = if (buffer.isEmpty()) { line } else { buffer + "\n" + line }
        let cand = buffer.trimAscii()
        try {
            out.add(JsonValue.fromStr(cand).asObject())
            buffer = ""
        } catch (_e: Exception) {
            ()
        }
    }
    out
}

public func dashboardBuildRecentMessagesForViews(
    user: GatewayUserSettings,
    sessions: Array<GatewaySessionConversationView>,
    maxLines: Int64
): Array<String> {
    let out = ArrayList<String>()
    for (entry in sessions) {
        let store = gatewaySessionStoreForUserWithAgentId(user, entry.agentId)
        if (let Some(raw) <- store.readTranscriptRaw(entry.key)) {
            let lines = raw.split("\n")
            for (line in lines) {
                let t = line.trimAscii()
                if (t.isEmpty()) { continue }
                try {
                    let o = JsonValue.fromStr(t).asObject()
                    if (let Some(kind) <- o.get("kind")) {
                        if (kind.asString().getValue() == "meta") { continue }
                    }
                    let role = match (o.get("role")) { case Some(v) => v.asString().getValue() case None => "" }
                    let text = match (o.get("text")) { case Some(v) => v.asString().getValue() case None => "" }
                    let label = if (!entry.displayName.isEmpty()) { entry.displayName } else { entry.key }
                    if (!role.isEmpty() && !text.isEmpty()) {
                        out.add("${label} [${role}] ${text}")
                    }
                } catch (_e: Exception) {
                    ()
                }
            }
        }
    }
    dashboardPickLast(out.toArray(), maxLines)
}

private func dashboardReadLatestLogTail(maxLines: Int64): (String, Array<String>) {
    let dir = CliConfig.logsDir
    if (!exists(dir)) { return ("", []) }
    var latestName = ""
    try {
        for (entry in Directory.readFrom(dir)) {
            if (!entry.isRegular()) { continue }
            let n = entry.name
            if (!n.endsWith(".log")) { continue }
            if (latestName.isEmpty() || n > latestName) { latestName = n }
        }
    } catch (_e: Exception) {
        return ("", [])
    }
    if (latestName.isEmpty()) { return ("", []) }
    let p = dir.join(latestName)
    try {
        let text = String.fromUtf8(File.readFrom(p))
        let lines = text.split("\n")
        return (latestName, dashboardPickLast(lines, maxLines))
    } catch (_e: Exception) {
        return (latestName, [])
    }
}

private func dashboardJsonEscape(raw: String): String {
    raw.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
}

private func dashboardAppendGatewayChannelsJson(sb: StringBuilder, gw: GatewayUserSettings): Unit {
    sb.append("\"channels\":[")
    var first = true
    var fsModel = ""
    var qqModel = ""
    for ((ck, cv) in gw.channelModels) {
        let kk = ck.trimAscii()
        if (kk == "feishu") { fsModel = cv }
        if (kk == "qq") { qqModel = cv }
    }
    if (gw.feishu.enabled) {
        if (!first) { sb.append(",") }
        first = false
        sb.append("{\"id\":\"feishu\",\"enabled\":true,\"tenantKey\":\"${dashboardJsonEscape(gw.feishu.appId)}\",\"model\":\"${dashboardJsonEscape(fsModel)}\",\"mode\":\"${dashboardJsonEscape(gw.feishu.receiveMode)}\",\"groupSessionScope\":\"${dashboardJsonEscape(gw.feishu.groupSessionScope)}\",\"replyInThread\":\"${dashboardJsonEscape(gw.feishu.replyInThread)}\",\"webhookBase\":\"http://${dashboardJsonEscape(gw.feishu.webhookHost)}:${gw.feishu.webhookPort}\"}")
    }
    if (gw.qq.enabled) {
        if (!first) { sb.append(",") }
        first = false
        sb.append("{\"id\":\"qq\",\"enabled\":true,\"appId\":\"${dashboardJsonEscape(gw.qq.appId)}\",\"mode\":\"${dashboardJsonEscape(gw.qq.mode)}\",\"model\":\"${dashboardJsonEscape(qqModel)}\",\"webhookBase\":\"http://${dashboardJsonEscape(gw.qq.webhookHost)}:${gw.qq.webhookPort}\"}")
    }
    sb.append("],")
}

private func dashboardAppendCronJson(sb: StringBuilder): Unit {
    let cronPath = cronStorePath(CliConfig.dotDir)
    let jobs = cronLoadOrEmpty(cronPath)
    sb.append("\"cron\":{")
    sb.append("\"storePath\":\"${dashboardJsonEscape(cronPath.toString())}\",")
    sb.append("\"jobs\":[")
    var first = true
    for (j in jobs) {
        if (!first) { sb.append(",") }
        first = false
        sb.append("{")
        sb.append("\"id\":\"${dashboardJsonEscape(j.id)}\",")
        sb.append("\"enabled\":${j.enabled},")
        sb.append("\"prompt\":\"${dashboardJsonEscape(j.prompt)}\",")
        sb.append("\"sessionTarget\":\"${dashboardJsonEscape(j.sessionTarget)}\",")
        sb.append("\"schedule\":{")
        sb.append("\"kind\":\"${dashboardJsonEscape(j.schedule.kind)}\",")
        sb.append("\"everyMs\":${j.schedule.everyMs},")
        sb.append("\"anchorMs\":${j.schedule.anchorMs},")
        sb.append("\"atMs\":${j.schedule.atMs},")
        sb.append("\"cronExpr\":\"${dashboardJsonEscape(j.schedule.cronExpr)}\",")
        sb.append("\"timeZone\":\"${dashboardJsonEscape(j.schedule.timeZone)}\",")
        sb.append("\"staggerMs\":${j.schedule.staggerMs}")
        sb.append("},")
        sb.append("\"systemEvent\":\"${dashboardJsonEscape(j.systemEvent)}\",")
        sb.append("\"wakeMode\":\"${dashboardJsonEscape(j.wakeMode)}\",")
        sb.append("\"deliveryChannel\":\"${dashboardJsonEscape(j.deliveryChannel)}\",")
        sb.append("\"deliveryTo\":\"${dashboardJsonEscape(j.deliveryTo)}\",")
        sb.append("\"deliveryAnnounce\":${j.deliveryAnnounce},")
        sb.append("\"timeoutMs\":${j.timeoutMs},")
        sb.append("\"maxRetries\":${j.maxRetries},")
        sb.append("\"retryBackoffMs\":${j.retryBackoffMs},")
        sb.append("\"failureChannel\":\"${dashboardJsonEscape(j.failureChannel)}\",")
        sb.append("\"failureTo\":\"${dashboardJsonEscape(j.failureTo)}\",")
        sb.append("\"failureAnnounce\":${j.failureAnnounce},")
        sb.append("\"payloadKind\":\"${dashboardJsonEscape(j.payloadKind)}\",")
        sb.append("\"deliveryMode\":\"${dashboardJsonEscape(j.deliveryMode)}\",")
        sb.append("\"failureDestMode\":\"${dashboardJsonEscape(j.failureDestMode)}\",")
        sb.append("\"state\":{")
        sb.append("\"nextRunAtMs\":${j.state.nextRunAtMs},")
        sb.append("\"lastRunAtMs\":${j.state.lastRunAtMs},")
        sb.append("\"lastError\":\"${dashboardJsonEscape(j.state.lastError)}\",")
        sb.append("\"lastStatus\":\"${dashboardJsonEscape(j.state.lastStatus)}\",")
        sb.append("\"consecutiveErrors\":${j.state.consecutiveErrors}")
        sb.append("}")
        sb.append("}")
    }
    sb.append("]")
    let dashJobIds = ArrayList<String>()
    for (j in jobs) {
        dashJobIds.add(j.id)
    }
    let dashRuns = readCronRunLogMergedFromStore(cronPath, dashJobIds.toArray(), resultLimit: 800)
    sb.append(",\"runHistory\":")
    sb.append(dashRuns.toJsonString())
    sb.append("},")
}
