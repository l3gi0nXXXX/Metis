package metis.gateway.runtime

import metis.core.config.{CliConfig, CliSettingManager, GatewayUserSettings, MetisConfigManager, skillEntryEnabled}
import metis.core.skills.SkillsPrompt
import metis.core.model.CliModelManager
import metis.gateway.{gatewayRuntimeEffectiveAuthPassword, gatewayRuntimeEffectiveAuthToken}
import metis.gateway.config.buildGatewayConfigFromUserSettings
import metis.gateway.core.{GatewaySessionConversationView, gatewayListSessionConversationViewsForUser, gatewaySessionStoreForSessionKey}
import metis.cron.{cronDashboardSaveJob, cronLoadOrEmpty, cronSave, cronStorePath, readCronRunLogMergedFromStore}
import metis.gateway.model.GatewayConfig
import metis.gateway.security.{gatewayAuthorizeDashboardRequest, gatewayDefaultControlUiDeviceId, gatewayDefaultControlUiDeviceToken}
import metis.gateway.session.gatewayBuildChatHistoryRpcParams

import std.collection.{ArrayList, HashSet}
import std.convert.Parsable
import std.fs.{Directory, File, exists, Path}
import stdx.encoding.json.{JsonBool, JsonObject, JsonString, JsonValue}
import stdx.net.http.*

public func gatewayControlUiContentHandleAuthedJson(ctx: HttpContext, requiredMethod: String, deliver: () -> String): String {
    let gw = CliSettingManager.readGatewaySettings()
    let authz = gatewayAuthorizeDashboardRequest(gw, ctx, requiredMethod)
    if (!authz.ok) {
        return "{\"ok\":false,\"error\":\"${gatewayControlUiJsonEscape(authz.error)}\"}"
    }
    deliver()
}

private func parseDashboardSessionLimit(ctx: HttpContext): Int64 {
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

private func appendCronJson(sb: StringBuilder): Unit {
    let cronPath = cronStorePath(CliConfig.dotDir)
    let jobs = cronLoadOrEmpty(cronPath)
    sb.append("\"cron\":{")
    sb.append("\"storePath\":\"${gatewayControlUiJsonEscape(cronPath.toString())}\",")
    sb.append("\"jobs\":[")
    var first = true
    for (j in jobs) {
        if (!first) {
            sb.append(",")
        }
        first = false
        sb.append("{")
        sb.append("\"id\":\"${gatewayControlUiJsonEscape(j.id)}\",")
        sb.append("\"enabled\":${j.enabled},")
        sb.append("\"prompt\":\"${gatewayControlUiJsonEscape(j.prompt)}\",")
        sb.append("\"sessionTarget\":\"${gatewayControlUiJsonEscape(j.sessionTarget)}\",")
        sb.append("\"schedule\":{")
        sb.append("\"kind\":\"${gatewayControlUiJsonEscape(j.schedule.kind)}\",")
        sb.append("\"everyMs\":${j.schedule.everyMs},")
        sb.append("\"anchorMs\":${j.schedule.anchorMs},")
        sb.append("\"atMs\":${j.schedule.atMs},")
        sb.append("\"cronExpr\":\"${gatewayControlUiJsonEscape(j.schedule.cronExpr)}\",")
        sb.append("\"timeZone\":\"${gatewayControlUiJsonEscape(j.schedule.timeZone)}\",")
        sb.append("\"staggerMs\":${j.schedule.staggerMs}")
        sb.append("},")
        sb.append("\"systemEvent\":\"${gatewayControlUiJsonEscape(j.systemEvent)}\",")
        sb.append("\"wakeMode\":\"${gatewayControlUiJsonEscape(j.wakeMode)}\",")
        sb.append("\"deliveryChannel\":\"${gatewayControlUiJsonEscape(j.deliveryChannel)}\",")
        sb.append("\"deliveryTo\":\"${gatewayControlUiJsonEscape(j.deliveryTo)}\",")
        sb.append("\"deliveryAnnounce\":${j.deliveryAnnounce},")
        sb.append("\"payloadKind\":\"${gatewayControlUiJsonEscape(j.payloadKind)}\",")
        sb.append("\"deliveryMode\":\"${gatewayControlUiJsonEscape(j.deliveryMode)}\",")
        sb.append("\"failureDestMode\":\"${gatewayControlUiJsonEscape(j.failureDestMode)}\",")
        sb.append("\"state\":{")
        sb.append("\"nextRunAtMs\":${j.state.nextRunAtMs},")
        sb.append("\"lastRunAtMs\":${j.state.lastRunAtMs},")
        sb.append("\"lastError\":\"${gatewayControlUiJsonEscape(j.state.lastError)}\",")
        sb.append("\"lastStatus\":\"${gatewayControlUiJsonEscape(j.state.lastStatus)}\"")
        sb.append("}")
        sb.append("}")
    }
    sb.append("]")
    let jobIdList = ArrayList<String>()
    for (j in jobs) {
        jobIdList.add(j.id)
    }
    let runHist = readCronRunLogMergedFromStore(cronPath, jobIdList.toArray(), resultLimit: 800)
    sb.append(",\"runHistory\":")
    sb.append(runHist.toJsonString())
    sb.append("},")
}

private func handleCronPost(ctx: HttpContext): String {
    let form = ctx.request.form
    let action = match (form.get("action")) {
        case Some(v) => v.trimAscii().toAsciiLower()
        case None => ""
    }
    if (action.isEmpty()) {
        return "{\"ok\":false,\"message\":\"action is empty\"}"
    }
    let parts = ArrayList<String>()
    parts.add("cron")

    if (action == "add_every") {
        let name = match (form.get("name")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let every = match (form.get("every")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let session = match (form.get("session")) {
            case Some(v) => v.trimAscii()
            case None => "main"
        }
        let message = match (form.get("message")) {
            case Some(v) => v
            case None => ""
        }
        if (name.isEmpty() || every.isEmpty() || message.trimAscii().isEmpty()) {
            return "{\"ok\":false,\"message\":\"name, every, message required\"}"
        }
        parts.add("add")
        parts.add("--name")
        parts.add(name)
        parts.add("--every")
        parts.add(every)
        parts.add("--session")
        parts.add(session)
        let dChEv = match (form.get("delivery_channel")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let dToEv = match (form.get("delivery_to")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let annEv = match (form.get("delivery_announce")) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => "false"
        }
        let sysEvEv = match (form.get("system_event")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let wakeEv = match (form.get("wake_mode")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (!sysEvEv.isEmpty()) {
            parts.add("--system-event")
            parts.add(sysEvEv)
        }
        if (!wakeEv.isEmpty()) {
            parts.add("--wake-mode")
            parts.add(wakeEv)
        }
        if (!dChEv.isEmpty()) {
            parts.add("--channel")
            parts.add(dChEv)
        }
        if (!dToEv.isEmpty()) {
            parts.add("--to")
            parts.add(dToEv)
        }
        if (annEv == "true" || annEv == "1" || annEv == "yes" || annEv == "on") {
            parts.add("--announce")
        }
        parts.add("--message")
        parts.add(message)
    } else if (action == "add_at") {
        let name = match (form.get("name")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let atRaw = match (form.get("at")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let session = match (form.get("session")) {
            case Some(v) => v.trimAscii()
            case None => "main"
        }
        let message = match (form.get("message")) {
            case Some(v) => v
            case None => ""
        }
        if (name.isEmpty() || atRaw.isEmpty() || message.trimAscii().isEmpty()) {
            return "{\"ok\":false,\"message\":\"name, at, message required\"}"
        }
        parts.add("add")
        parts.add("--name")
        parts.add(name)
        parts.add("--at")
        parts.add(atRaw)
        parts.add("--session")
        parts.add(session)
        let dChAt = match (form.get("delivery_channel")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let dToAt = match (form.get("delivery_to")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let annAt = match (form.get("delivery_announce")) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => "false"
        }
        let sysEvAt = match (form.get("system_event")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let wakeAt = match (form.get("wake_mode")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (!sysEvAt.isEmpty()) {
            parts.add("--system-event")
            parts.add(sysEvAt)
        }
        if (!wakeAt.isEmpty()) {
            parts.add("--wake-mode")
            parts.add(wakeAt)
        }
        if (!dChAt.isEmpty()) {
            parts.add("--channel")
            parts.add(dChAt)
        }
        if (!dToAt.isEmpty()) {
            parts.add("--to")
            parts.add(dToAt)
        }
        if (annAt == "true" || annAt == "1" || annAt == "yes" || annAt == "on") {
            parts.add("--announce")
        }
        parts.add("--message")
        parts.add(message)
    } else if (action == "add_cron") {
        let name = match (form.get("name")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let cronExpr = match (form.get("cron_expr")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let tz = match (form.get("time_zone")) {
            case Some(v) => v.trimAscii()
            case None => "UTC"
        }
        let session = match (form.get("session")) {
            case Some(v) => v.trimAscii()
            case None => "main"
        }
        let message = match (form.get("message")) {
            case Some(v) => v
            case None => ""
        }
        let dCh = match (form.get("delivery_channel")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let dTo = match (form.get("delivery_to")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let annStr = match (form.get("delivery_announce")) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => "false"
        }
        let sysEvAdd = match (form.get("system_event")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let wakeAdd = match (form.get("wake_mode")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (name.isEmpty() || cronExpr.isEmpty() || message.trimAscii().isEmpty()) {
            return "{\"ok\":false,\"message\":\"name, cron_expr, message required\"}"
        }
        parts.add("add")
        parts.add("--name")
        parts.add(name)
        parts.add("--cron")
        parts.add(cronExpr)
        parts.add("--tz")
        parts.add(tz)
        parts.add("--session")
        parts.add(session)
        if (!sysEvAdd.isEmpty()) {
            parts.add("--system-event")
            parts.add(sysEvAdd)
        }
        if (!wakeAdd.isEmpty()) {
            parts.add("--wake-mode")
            parts.add(wakeAdd)
        }
        if (!dCh.isEmpty()) {
            parts.add("--channel")
            parts.add(dCh)
        }
        if (!dTo.isEmpty()) {
            parts.add("--to")
            parts.add(dTo)
        }
        if (annStr == "true" || annStr == "1" || annStr == "yes" || annStr == "on") {
            parts.add("--announce")
        }
        parts.add("--message")
        parts.add(message)
    } else if (action == "remove") {
        let id = match (form.get("id")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (id.isEmpty()) {
            return "{\"ok\":false,\"message\":\"id is empty\"}"
        }
        parts.add("remove")
        parts.add(id)
    } else if (action == "enable") {
        let id = match (form.get("id")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (id.isEmpty()) {
            return "{\"ok\":false,\"message\":\"id is empty\"}"
        }
        parts.add("enable")
        parts.add(id)
    } else if (action == "disable") {
        let id = match (form.get("id")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (id.isEmpty()) {
            return "{\"ok\":false,\"message\":\"id is empty\"}"
        }
        parts.add("disable")
        parts.add(id)
    } else if (action == "edit_message") {
        let jobId = match (form.get("id")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let message = match (form.get("message")) {
            case Some(v) => v
            case None => ""
        }
        if (jobId.isEmpty() || message.trimAscii().isEmpty()) {
            return "{\"ok\":false,\"message\":\"id or message empty\"}"
        }
        parts.add("edit")
        parts.add(jobId)
        parts.add("--message")
        parts.add(message)
    } else if (action == "edit_enabled") {
        let jobId = match (form.get("id")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let en = match (form.get("enabled")) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => ""
        }
        if (jobId.isEmpty() || (en != "true" && en != "false")) {
            return "{\"ok\":false,\"message\":\"id or enabled invalid\"}"
        }
        parts.add("edit")
        parts.add(jobId)
        parts.add("--enabled")
        parts.add(en)
    } else if (action == "save_job") {
        let jobId = match (form.get("id")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let message = match (form.get("message")) {
            case Some(v) => v
            case None => ""
        }
        let session = match (form.get("session")) {
            case Some(v) => v.trimAscii()
            case None => "main"
        }
        let enStr = match (form.get("enabled")) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => "true"
        }
        let scheduleKind = match (form.get("schedule_kind")) {
            case Some(v) => v.trimAscii()
            case None => "every"
        }
        let everyRaw = match (form.get("every")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let atRaw = match (form.get("at")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (jobId.isEmpty() || message.trimAscii().isEmpty()) {
            return "{\"ok\":false,\"message\":\"id or message empty\"}"
        }
        let enabled = enStr == "true" || enStr == "1" || enStr == "yes"
        let cronEx = match (form.get("cron_expr")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let tz = match (form.get("time_zone")) {
            case Some(v) => v.trimAscii()
            case None => "UTC"
        }
        let sysEv = match (form.get("system_event")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let wake = match (form.get("wake_mode")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let dCh = match (form.get("delivery_channel")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let dTo = match (form.get("delivery_to")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let annStr = match (form.get("delivery_announce")) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => "false"
        }
        let dAnn = annStr == "true" || annStr == "1" || annStr == "yes" || annStr == "on"
        let path = cronStorePath(CliConfig.dotDir)
        let (out, code) = cronDashboardSaveJob(
            path,
            jobId,
            message,
            session,
            enabled,
            scheduleKind,
            everyRaw,
            atRaw,
            cronEx,
            tz,
            sysEv,
            wake,
            dCh,
            dTo,
            dAnn
        )
        let ok = code == 0
        let sbSave = StringBuilder()
        sbSave.append("{")
        sbSave.append("\"ok\":${ok},")
        sbSave.append("\"code\":${code},")
        sbSave.append("\"message\":\"${gatewayControlUiJsonEscape(out)}\"")
        sbSave.append("}")
        return sbSave.toString()
    } else if (action == "run_once") {
        let jobId = match (form.get("id")) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (jobId.isEmpty()) {
            return "{\"ok\":false,\"message\":\"id is empty\"}"
        }
        let (okNow, outNow) = runCronJobNow(jobId)
        let sbNow = StringBuilder()
        sbNow.append("{")
        sbNow.append("\"ok\":${okNow},")
        sbNow.append("\"code\":${if (okNow) { 0 } else { 1 }},")
        sbNow.append("\"message\":\"${gatewayControlUiJsonEscape(outNow)}\"")
        sbNow.append("}")
        return sbNow.toString()
    } else {
        return "{\"ok\":false,\"message\":\"unknown action\"}"
    }

    let (out, code) = gatewayExecuteCronWithUnifiedRun(parts.toArray())
    let ok = code == 0
    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"ok\":${ok},")
    sb.append("\"code\":${code},")
    sb.append("\"message\":\"${gatewayControlUiJsonEscape(out)}\"")
    sb.append("}")
    sb.toString()
}

private func runCronJobNow(jobId: String): (Bool, String) {
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

private func buildStatusJson(ctx: HttpContext): String {
    let limitN = parseDashboardSessionLimit(ctx)
    let model = CliConfig.model
    let skillsEnabled = CliSettingManager.readSkillsEnabled()
    let skillLines = SkillsPrompt.listSkillStatusLines()
    let gw = CliSettingManager.readGatewaySettings()
    let gatewayRunning = gatewayControlUiServeRunningNow()
    let sessionViews = gatewayListSessionConversationViewsForUser(gw)
    let storageRoots = gatewaySessionStorageRootsForUser(gw)
    let recentSessionViewsAll = ArrayList<GatewaySessionConversationView>()
    for (entry in sessionViews) {
        recentSessionViewsAll.add(entry)
    }
    let recentSessionViews = gatewayControlUiPickLastConversationViews(recentSessionViewsAll.toArray(), limitN)
    let recentSessions = ArrayList<String>()
    let recentConversationViews = ArrayList<GatewaySessionConversationView>()
    for (entry in recentSessionViews) {
        recentSessions.add(entry.key)
        recentConversationViews.add(entry)
    }
    let recentMessages = gatewayControlUiBuildRecentMessagesForConversations(
        gw,
        recentConversationViews.toArray(),
        20
    )
    let (latestLogFile, logTail) = gatewayControlUiReadLatestLogTail(80)

    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"model\":\"${gatewayControlUiJsonEscape(model)}\",")
    sb.append("\"skillsEnabled\":${skillsEnabled},")
    sb.append("\"skills\":[")
    var first = true
    for (line in skillLines) {
        if (!first) {
            sb.append(",")
        }
        first = false
        sb.append("\"${gatewayControlUiJsonEscape(line)}\"")
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
        if (kk.isEmpty() || vv.isEmpty()) {
            continue
        }
        if (!firstCm) {
            sb.append(",")
        }
        firstCm = false
        sb.append("\"${gatewayControlUiJsonEscape(kk)}\":\"${gatewayControlUiJsonEscape(vv)}\"")
    }
    sb.append("}")
    sb.append("},")
    gatewayControlUiAppendGatewayChannelsJson(sb, gw)
    let dashboardCfg = buildGatewayConfigFromUserSettings(gw)
    sb.append("\"dashboard\":")
    sb.append(gatewayControlUiDashboardBindingJson(dashboardCfg).toJsonString())
    sb.append(",")
    sb.append("\"sessions\":{")
    sb.append("\"root\":\"${gatewayControlUiJsonEscape(storageRoots[0])}\",")
    sb.append("\"count\":${sessionViews.size},")
    sb.append("\"recent\":[")
    var firstSess = true
    for (entry in recentSessionViews) {
        if (!firstSess) {
            sb.append(",")
        }
        firstSess = false
        sb.append("\"${gatewayControlUiJsonEscape(entry.key)}\"")
    }
    sb.append("],")
    sb.append("\"details\":[")
    var firstSd = true
    for (conv in recentSessionViews) {
        let k = conv.key
        let (msgCount, tokenApprox, tsRaw, lastRole) = gatewayControlUiSummarizeConversation(conv)
        let displayName = gatewayControlUiJsonEscape(conv.displayName)
        let agentId = gatewayControlUiJsonEscape(conv.agentId)
        let sessionId = gatewayControlUiJsonEscape(conv.sessionId)
        let sessionFile = gatewayControlUiJsonEscape(conv.sessionFile)
        let root = gatewayControlUiJsonEscape(conv.root.toString())
        let channel = gatewayControlUiJsonEscape(conv.channel)
        let chatType = gatewayControlUiJsonEscape(conv.chatType)
        let peer = gatewayControlUiJsonEscape(conv.peer)
        let origin = conv.origin.toJsonString()
        let delivery = conv.delivery.toJsonString()
        let binding = conv.binding.toJsonString()
        if (!firstSd) {
            sb.append(",")
        }
        firstSd = false
        sb.append("{")
        sb.append("\"key\":\"${gatewayControlUiJsonEscape(k)}\",")
        sb.append("\"displayName\":\"${displayName}\",")
        sb.append("\"agentId\":\"${agentId}\",")
        sb.append("\"sessionId\":\"${sessionId}\",")
        sb.append("\"sessionFile\":\"${sessionFile}\",")
        sb.append("\"root\":\"${root}\",")
        sb.append("\"channel\":\"${channel}\",")
        sb.append("\"chatType\":\"${chatType}\",")
        sb.append("\"peer\":\"${peer}\",")
        sb.append("\"origin\":${origin},")
        sb.append("\"delivery\":${delivery},")
        sb.append("\"binding\":${binding},")
        sb.append("\"updatedAt\":${conv.updatedAt},")
        sb.append("\"messageCount\":${msgCount},")
        sb.append("\"tokenApprox\":${tokenApprox},")
        sb.append("\"updatedTs\":\"${gatewayControlUiJsonEscape(tsRaw)}\",")
        sb.append("\"lastRole\":\"${gatewayControlUiJsonEscape(lastRole)}\"")
        sb.append("}")
    }
    sb.append("]")
    sb.append("},")
    sb.append("\"chat\":{")
    sb.append("\"recentMessages\":[")
    var firstMsg = true
    for (m in recentMessages) {
        if (!firstMsg) {
            sb.append(",")
        }
        firstMsg = false
        sb.append("\"${gatewayControlUiJsonEscape(m)}\"")
    }
    sb.append("]")
    sb.append("},")
    appendCronJson(sb)
    sb.append("\"logs\":{")
    sb.append("\"latestFile\":\"${gatewayControlUiJsonEscape(latestLogFile)}\",")
    sb.append("\"tail\":[")
    var firstLog = true
    for (line in logTail) {
        if (!firstLog) {
            sb.append(",")
        }
        firstLog = false
        sb.append("\"${gatewayControlUiJsonEscape(line)}\"")
    }
    sb.append("]")
    sb.append("}")
    sb.append("}")
    sb.toString()
}

private func buildChatHistoryJson(ctx: HttpContext): String {
    let sessionKey = match (ctx.request.form.get("session")) {
        case Some(v) => v.trimAscii()
        case None => ""
    }
    let params = gatewayBuildChatHistoryRpcParams(session: sessionKey)
    gatewayDashboardChatHistoryJsonFromRpc(params)
}

private func handleChatSend(ctx: HttpContext): String {
    gatewayDashboardHandleChatSend(ctx)
}

private struct DashboardModelPreset {
    DashboardModelPreset(
        let provider: String,
        let suggestedModels: Array<String>
    ) { }
}

// 与 /models 里的 PROVIDER_PRESETS 保持同源建议（这里只需要 provider + suggestedModels）。
private let DASHBOARD_MODEL_PRESETS = [
    DashboardModelPreset("ark", ["ark-code-latest", "kimi-k2-250905"]),
    DashboardModelPreset("moonshot", ["kimi-for-coding", "kimi-k2-0711-preview"]),
    DashboardModelPreset("zhipuai", ["glm-4.7", "glm-4.5"]),
    DashboardModelPreset("openai", ["gpt-5", "gpt-5-mini", "gpt-4.1"]),
    DashboardModelPreset("anthropic", ["claude-sonnet-4-5", "claude-3-7-sonnet-latest"]),
    DashboardModelPreset("deepseek", ["deepseek-chat"]),
    DashboardModelPreset("maas", ["qwen2.5-vl-72b"])
]

private func buildModelsJson(): String {
    let current = CliConfig.model
    let namesSet = HashSet<String>()
    let names = ArrayList<String>()

    for (preset in DASHBOARD_MODEL_PRESETS) {
        let key = MetisConfigManager.readProviderApiKey(preset.provider).trimAscii()
        if (key.isEmpty()) {
            continue
        }
        for (mid in preset.suggestedModels) {
            let id = mid.trimAscii()
            if (id.isEmpty()) {
                continue
            }
            let full = "${preset.provider}:${id}"
            if (!namesSet.contains(full)) {
                namesSet.add(full)
                names.add(full)
            }
        }
    }

    // 确保当前模型也在候选列表中
    if (!current.isEmpty() && !namesSet.contains(current)) {
        names.add(current)
    }

    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"current\":\"${gatewayControlUiJsonEscape(current)}\",")
    sb.append("\"candidates\":[")
    var first = true
    for (n in names) {
        if (!first) {
            sb.append(",")
        }
        first = false
        sb.append("\"${gatewayControlUiJsonEscape(n)}\"")
    }
    sb.append("]")
    sb.append("}")
    sb.toString()
}

private func handleModelSwitch(ctx: HttpContext): String {
    let form = ctx.request.form
    let modelName = match (form.get("model")) {
        case Some(v) => v.trimAscii()
        case None => ""
    }
    if (modelName.isEmpty()) {
        return "{\"ok\":false,\"message\":\"model is empty\"}"
    }
    let saved = !MetisConfigManager.setPrimaryModelRef(modelName).trimAscii().isEmpty()
    // 重置运行态模型缓存
    CliModelManager.resetRuntimeState()
    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"ok\":${saved},")
    sb.append("\"current\":\"${gatewayControlUiJsonEscape(CliConfig.model)}\"")
    sb.append("}")
    sb.toString()
}

private func buildSkillsJson(): String {
    let st = CliSettingManager.setting.skills
    let discovered = gatewayControlUiDiscoverSkills()
    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"skills\":[")
    var first = true
    for (item in discovered) {
        let name = item[0]
        let desc = item[1]
        if (!first) {
            sb.append(",")
        }
        first = false
        let enabled = skillEntryEnabled(st, name)
        sb.append("{")
        sb.append("\"name\":\"${gatewayControlUiJsonEscape(name)}\",")
        sb.append("\"description\":\"${gatewayControlUiJsonEscape(desc)}\",")
        sb.append("\"enabled\":${enabled}")
        sb.append("}")
    }
    sb.append("]")
    sb.append("}")
    sb.toString()
}

private func handleSkillSet(ctx: HttpContext): String {
    let form = ctx.request.form
    let name = match (form.get("name")) {
        case Some(v) => v.trimAscii()
        case None => ""
    }
    let enabledText = match (form.get("enabled")) {
        case Some(v) => v.trimAscii().toAsciiLower()
        case None => ""
    }
    if (name.isEmpty()) {
        return "{\"ok\":false,\"message\":\"name is empty\"}"
    }
    let enabled = (enabledText == "true" || enabledText == "1" || enabledText == "yes")
    var entries = match (CliSettingManager.setting.skills.entries) {
        case Some(v) => v
        case None => JsonObject()
    }
    let obj = JsonObject()
    obj.put("enabled", JsonBool(enabled))
    entries.put(name, obj)
    let ok = MetisConfigManager.setSkillsEntries(Some(entries)).isSome()
    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"ok\":${ok},")
    sb.append("\"name\":\"${gatewayControlUiJsonEscape(name)}\",")
    sb.append("\"enabled\":${enabled}")
    sb.append("}")
    sb.toString()
}

private func handleSessionsDelete(ctx: HttpContext): String {
    let form = ctx.request.form
    let keysRaw = match (form.get("keys")) {
        case Some(v) => v.trimAscii()
        case None => ""
    }
    if (keysRaw.isEmpty()) {
        return "{\"ok\":false,\"message\":\"keys is empty\"}"
    }
    let parts = keysRaw.split("\n")
    let deleted = ArrayList<String>()
    let failed = ArrayList<String>()
    for (p in parts) {
        let k = p.trimAscii()
        if (k.isEmpty()) {
            continue
        }
        let store = gatewaySessionStoreForSessionKey(CliSettingManager.readGatewaySettings(), k)
        if (store.deleteSession(k)) {
            deleted.add(k)
        } else {
            failed.add(k)
        }
    }

    let sb = StringBuilder()
    sb.append("{")
    sb.append("\"ok\":true,")
    sb.append("\"deleted\":[")
    var first = true
    for (k in deleted.toArray()) {
        if (!first) {
            sb.append(",")
        }
        first = false
        sb.append("\"${gatewayControlUiJsonEscape(k)}\"")
    }
    sb.append("],")
    sb.append("\"failed\":[")
    var first2 = true
    for (k in failed.toArray()) {
        if (!first2) {
            sb.append(",")
        }
        first2 = false
        sb.append("\"${gatewayControlUiJsonEscape(k)}\"")
    }
    sb.append("]")
    sb.append("}")
    sb.toString()
}

public func gatewayBuildControlUiContentHtml(cfg: GatewayConfig): String {
    // 若 gateway 未开启或未运行，则显示引导页（参考当前控制台登录风格）。
    let gw = CliSettingManager.readGatewaySettings()
    let dashboardDeviceId = gatewayDefaultControlUiDeviceId()
    let dashboardDeviceToken = gatewayDefaultControlUiDeviceToken()
    let dashboardAuthToken = gatewayRuntimeEffectiveAuthToken(gw).trimAscii()
    let dashboardAuthPassword = gatewayRuntimeEffectiveAuthPassword(gw).trimAscii()
    let binding = GatewayControlUiRuntime.controlUiBinding(cfg)
    let dashboardBasePath = binding.basePath
    if (!gw.enabled || !gatewayControlUiServeRunningNow()) {
        return gatewayBuildControlUiOfflineHtml(binding.wsUrl)
    }

    let headExtra = """
  <style>
    :root {
      --bg: #0f172a;
      --fg: #e2e8f0;
      --muted: #94a3b8;
      --card: #111827;
      --card-border: #334155;
      --panel: #020617;
      --panel-2: #0b1220;
      --accent: #0ea5e9;
      --accent-2: #0f766e;
      --btn-fg: #0f172a;
    }
    body[data-theme="emerald"] {
      --bg: #0b1f1a;
      --fg: #d1fae5;
      --muted: #6ee7b7;
      --card: #0f2a22;
      --card-border: #1f4d3d;
      --panel: #071610;
      --panel-2: #0b2018;
      --accent: #10b981;
      --accent-2: #047857;
      --btn-fg: #052e26;
    }
    body[data-theme="violet"] {
      --bg: #161126;
      --fg: #ede9fe;
      --muted: #c4b5fd;
      --card: #1f1834;
      --card-border: #4c3f73;
      --panel: #120d20;
      --panel-2: #19132a;
      --accent: #8b5cf6;
      --accent-2: #6d28d9;
      --btn-fg: #f5f3ff;
    }
    body[data-theme="slate"] {
      --bg: #0f172a;
      --fg: #e2e8f0;
      --muted: #94a3b8;
      --card: #111827;
      --card-border: #334155;
      --panel: #020617;
      --panel-2: #0b1220;
      --accent: #0ea5e9;
      --accent-2: #0f766e;
      --btn-fg: #0f172a;
    }
    body[data-theme="amber"] {
      --bg: #2b1f0e;
      --fg: #fef3c7;
      --muted: #fcd34d;
      --card: #3a2b16;
      --card-border: #6b4f1d;
      --panel: #241a0c;
      --panel-2: #332510;
      --accent: #f59e0b;
      --accent-2: #b45309;
      --btn-fg: #1f1307;
    }
    body { font-family: system-ui, Segoe UI, sans-serif; margin: 0; background: var(--bg); color: var(--fg); }
    * { box-sizing: border-box; }
    .shell { padding: 16px 20px 20px 20px; }
    h1 { margin: 0 0 12px 0; font-size: 22px; }
    .layout { display: flex; gap: 12px; align-items: stretch; }
    .col-left { width: 360px; display: flex; flex-direction: column; gap: 12px; }
    .col-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 8px; }
    .card { background: var(--card); border: 1px solid var(--card-border); border-radius: 10px; padding: 12px; }
    h2 { margin: 0 0 8px 0; font-size: 16px; }
    code { background: var(--panel-2); padding: 2px 6px; border-radius: 4px; }
    ul { margin: 6px 0 0 18px; padding: 0; }
    li { margin: 3px 0; }
    .muted { color: var(--muted); }
    .left-shell { display: flex; gap: 10px; }
    .tabs { width: 110px; display: flex; flex-direction: column; gap: 6px; }
    .tab-content { flex: 1; min-width: 0; }
    .tab-btn { border: 1px solid var(--card-border); background: var(--panel-2); color: var(--muted); border-radius: 8px; font-size: 14px; padding: 7px 9px; cursor: pointer; text-align: left; }
    .tab-btn.active { background: var(--accent); color: var(--btn-fg); border-color: var(--accent); font-weight: 700; }
    .tab-panel { display: none; }
    .tab-panel.active { display: block; }
    /* 除 Chat 外，页签内容字体整体放大 */
    .tab-panel.active:not([data-tab="chat"]) { font-size: 15px; }
    .tab-panel.active:not([data-tab="chat"]) h2 { font-size: 22px; }
    /* Sessions 右侧页签：整体字号在当前基础上再 +4 左右 */
    .tab-panel.active[data-tab="sessions"] { font-size: 19px; }
    .tab-panel.active[data-tab="sessions"] h2 { font-size: 26px; }
    .tab-panel.active[data-tab="sessions"] .session-title { font-size: 18px; }
    .tab-panel.active[data-tab="sessions"] .session-meta { font-size: 17px; }
    .tab-panel.active[data-tab="sessions"] .session-stat { font-size: 16px; }
    .tab-panel.active[data-tab="sessions"] .session-updated { font-size: 16px; }
    .tab-panel.active[data-tab="sessions"] code { font-size: 16px; }
    .session-list { max-height: 500px; overflow-y: auto; padding-right: 4px; border-top: 1px solid var(--card-border); margin-top: 8px; padding-top: 8px; }
    .session-item { cursor: pointer; padding: 8px 8px; border-radius: 8px; border: 1px solid var(--card-border); margin-bottom: 6px; background: var(--panel); }
    .session-item:hover { background: var(--panel-2); border-color: var(--accent); }
    .session-item-active { background: color-mix(in srgb, var(--accent-2) 75%, black 25%); border-color: var(--accent); color: #ecfeff; }
    .session-meta { font-size: 13px; color: var(--muted); margin-bottom: 4px; }
    .session-title { font-size: 14px; font-weight: 700; line-height: 1.4; word-break: break-all; }
    .session-kind { display: inline-block; margin-right: 6px; padding: 0 6px; border-radius: 999px; font-size: 10px; background: var(--panel-2); color: var(--fg); }
    .session-stats { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
    .session-stat { font-size: 12px; padding: 2px 8px; border-radius: 999px; border: 1px solid var(--card-border); background: var(--panel-2); color: var(--fg); }
    .session-updated { margin-top: 6px; font-size: 12px; color: var(--muted); }
    .badge { display: inline-block; padding: 1px 6px; border-radius: 999px; font-size: 11px; background: #0b1120; color: #e2e8f0; }
    .chat-box { flex: 1; min-height: 460px; max-height: 74vh; border-radius: 10px; border: 1px solid var(--card-border); background: var(--panel); padding: 10px; overflow-y: auto; }
    .chat-msg { margin-bottom: 8px; }
    .chat-role { font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 2px; }
    .chat-role-user { color: #38bdf8; }
    .chat-role-assistant { color: #a5b4fc; }
    .chat-time { font-size: 11px; color: var(--muted); margin-left: 8px; }
    .chat-bubble { padding: 6px 8px; border-radius: 6px; background: var(--panel); border: 1px solid var(--card-border); white-space: pre-wrap; word-break: break-word; }
    .chat-input-row { margin-top: 8px; display: flex; gap: 8px; }
    .chat-input-row textarea { flex: 1; resize: vertical; min-height: 52px; max-height: 140px; border-radius: 8px; border: 1px solid var(--card-border); background: var(--panel); color: var(--fg); padding: 6px 8px; font-family: inherit; font-size: 13px; }
    .chat-input-row button { width: 100px; border-radius: 8px; border: none; background: var(--accent); color: var(--btn-fg); font-weight: 600; cursor: pointer; font-size: 13px; }
    .chat-input-row button:disabled { background: var(--panel-2); color: var(--muted); cursor: default; }
    .model-select { width: 100%; margin-top: 4px; background: var(--panel); color: var(--fg); border-radius: 6px; border: 1px solid var(--card-border); padding: 4px 6px; font-size: 13px; }
    .model-actions { margin-top: 6px; display: flex; gap: 6px; align-items: center; justify-content: flex-end; }
    .btn-small { padding: 3px 8px; border-radius: 999px; border: none; font-size: 11px; cursor: pointer; background: var(--accent); color: var(--btn-fg); font-weight: 600; }
    .btn-small-muted { background: var(--panel-2); color: var(--fg); }
    .theme-palette { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; margin-top: 8px; }
    .theme-btn { border: 1px solid var(--card-border); border-radius: 8px; background: var(--panel); color: var(--fg); padding: 8px; cursor: pointer; text-align: left; font-size: 12px; }
    .theme-btn.active { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
    .theme-dot { display: inline-block; width: 10px; height: 10px; border-radius: 999px; margin-right: 6px; vertical-align: middle; }
    /* Skills: v3 使用 button 切换启用/禁用（不使用 checkbox） */
    .skill-item { border: 1px solid var(--card-border); background: var(--panel); border-radius: 10px; padding: 10px; margin-bottom: 10px; }
    .skill-title { font-size: 13px; font-weight: 800; }
    .skill-meta { margin-top: 6px; font-size: 12px; color: var(--muted); line-height: 1.5; white-space: pre-wrap; word-break: break-word; }
    .skill-actions { margin-top: 10px; display: flex; justify-content: flex-end; }
    .skill-toggle-btn { border-radius: 999px; border: 1px solid var(--card-border); background: var(--panel-2); color: #111111; padding: 6px 12px; font-size: 13px; font-weight: 800; cursor: pointer; }
    .skill-toggle-btn.on { background: var(--accent); border-color: var(--accent); color: var(--btn-fg); }
    .skill-toggle-btn:disabled { opacity: 0.65; cursor: default; }
    .logs-list { max-height: 220px; overflow-y: auto; padding-right: 4px; }
    .logs-list li { font-size: 11px; white-space: pre; }

    /* =========================
       Metis UI (v3) — scoped
       ========================= */
    body[data-ui="v3"] { background: #f8f9fa; color: #3c3c43; }
    body[data-ui="v3"] > .shell { padding: 0; }
    body[data-ui="v3"] > .shell > h1 { display: none; }
    body[data-ui="v3"] #root { padding: 0; }

    body[data-ui="v3"] .oc-root {
      /* tokens (from current UI base styles, light mode defaults) */
      --bg: #f8f9fa;
      --bg-accent: #f1f3f5;
      --bg-elevated: #ffffff;
      --bg-hover: #eceef0;
      --bg-muted: #eceef0;
      --bg-content: #f1f3f5;
      --card: #ffffff;
      --card-foreground: #1a1a1e;
      --card-highlight: rgba(0, 0, 0, 0.02);
      --popover: #ffffff;
      --popover-foreground: #1a1a1e;
      --panel: #f8f9fa;
      --panel-strong: #f1f3f5;
      --panel-hover: #e6e8eb;
      --chrome: rgba(248, 249, 250, 0.96);
      --chrome-strong: rgba(248, 249, 250, 0.98);
      --text: #3c3c43;
      --text-strong: #1a1a1e;
      --chat-text: #3c3c43;
      --muted: #8e8e93;
      --muted-strong: #636366;
      --muted-foreground: #8e8e93;
      --border: #e5e5ea;
      --border-strong: #d1d1d6;
      --border-hover: #aeaeb2;
      --input: #e5e5ea;
      --ring: #dc2626;
      --accent: #dc2626;
      --accent-hover: #ef4444;
      --accent-muted: #dc2626;
      --accent-subtle: rgba(220, 38, 38, 0.08);
      --accent-foreground: #ffffff;
      --accent-glow: rgba(220, 38, 38, 0.1);
      --primary: #dc2626;
      --primary-foreground: #ffffff;
      --secondary: #f1f3f5;
      --secondary-foreground: #3c3c43;
      --ok: #16a34a;
      --warn: #d97706;
      --danger: #dc2626;
      --info: #2563eb;
      --focus-ring: 0 0 0 2px var(--bg), 0 0 0 3px color-mix(in srgb, var(--ring) 50%, transparent);
      --mono: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      --font-body: "Inter", system-ui, "Segoe UI", Roboto, sans-serif;
      --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.04);
      --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.06);
      --shadow-lg: 0 12px 28px rgba(0, 0, 0, 0.08);
      --radius-sm: 6px;
      --radius-md: 10px;
      --radius-lg: 14px;
      --radius-xl: 20px;
      --radius-full: 9999px;
      --radius: 10px;
      --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
      --duration-fast: 100ms;

      font: 400 13.5px/1.55 var(--font-body);
      letter-spacing: -0.01em;
      background: var(--bg);
      color: var(--text);
      height: 100vh;
    }

    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] {
      --bg: #0e1015;
      --bg-accent: #13151b;
      --bg-elevated: #191c24;
      --bg-hover: #1f2330;
      --bg-muted: #1f2330;
      --bg-content: #13151b;
      --card: #161920;
      --card-foreground: #f0f0f2;
      --card-highlight: rgba(255, 255, 255, 0.04);
      --popover: #191c24;
      --popover-foreground: #f0f0f2;
      --panel: #0e1015;
      --panel-strong: #191c24;
      --panel-hover: #1f2330;
      --chrome: rgba(14, 16, 21, 0.96);
      --chrome-strong: rgba(14, 16, 21, 0.98);
      --text: #d4d4d8;
      --text-strong: #f4f4f5;
      --chat-text: #d4d4d8;
      --muted: #636370;
      --muted-strong: #4e4e5a;
      --muted-foreground: #636370;
      --border: #1e2028;
      --border-strong: #2e3040;
      --border-hover: #3e4050;
      --input: #1e2028;
      --ring: #ff5c5c;
      --accent: #ff5c5c;
      --accent-hover: #ff7070;
      --accent-muted: #ff5c5c;
      --accent-subtle: rgba(255, 92, 92, 0.1);
      --accent-foreground: #fafafa;
      --accent-glow: rgba(255, 92, 92, 0.2);
      --primary: #ff5c5c;
      --primary-foreground: #ffffff;
      --secondary: #161920;
      --secondary-foreground: #f0f0f2;
      --ok: #22c55e;
      --warn: #f59e0b;
      --danger: #ef4444;
      --info: #3b82f6;
      --focus-ring: 0 0 0 2px var(--bg), 0 0 0 3px color-mix(in srgb, var(--ring) 60%, transparent);
      --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.25);
      --shadow-md: 0 4px 16px rgba(0, 0, 0, 0.3);
      --shadow-lg: 0 12px 32px rgba(0, 0, 0, 0.4);
      color-scheme: dark;
    }

    body[data-ui="v3"][data-v3-effective-theme="dark"] { background: #0e1015; color: #d4d4d8; }
    body[data-ui="v3"][data-v3-effective-theme="light"] { background: #f8f9fa; color: #3c3c43; }

    body[data-ui="v3"] .oc-root * { box-sizing: border-box; }
    body[data-ui="v3"] .oc-root a { color: var(--accent); text-decoration: none; }
    body[data-ui="v3"] .oc-root a:hover { text-decoration: underline; }
    body[data-ui="v3"] .oc-root .mono { font-family: var(--mono); }
    body[data-ui="v3"] .oc-root .muted { color: var(--muted); }

    /* layout (current scoped subset) */
    body[data-ui="v3"] .oc-root .shell {
      --shell-nav-width: 258px;
      --shell-topbar-height: 52px;
      height: 100vh;
      display: grid;
      grid-template-columns: var(--shell-nav-width) minmax(0, 1fr);
      grid-template-rows: var(--shell-topbar-height) 1fr;
      grid-template-areas:
        "nav topbar"
        "nav content";
      overflow: hidden;
      background: var(--bg);
    }
    body[data-ui="v3"] .oc-root .topbar {
      grid-area: topbar;
      position: sticky;
      top: 0;
      z-index: 40;
      display: flex;
      align-items: center;
      padding: 0 24px;
      min-height: 58px;
      border-bottom: 1px solid color-mix(in srgb, var(--border) 74%, transparent);
      background: color-mix(in srgb, var(--bg) 82%, transparent);
      backdrop-filter: blur(12px) saturate(1.6);
      -webkit-backdrop-filter: blur(12px) saturate(1.6);
    }
    body[data-ui="v3"] .oc-root .topnav-shell { display:flex; align-items:center; gap:16px; width:100%; }
    body[data-ui="v3"] .oc-root .topnav-shell__content { flex: 1; min-width: 0; }
    body[data-ui="v3"] .oc-root .topnav-shell__actions { display:flex; align-items:center; gap:12px; flex-shrink:0; }
    body[data-ui="v3"] .oc-root .topbar-search {
      display: inline-flex; align-items:center; gap:12px;
      min-height: 38px; padding: 0 14px;
      border: 1px solid color-mix(in srgb, var(--border) 88%, transparent);
      border-radius: 999px;
      background: color-mix(in srgb, var(--bg-elevated) 84%, transparent);
      color: var(--muted);
      font-size: 13px;
      cursor: default;
      min-width: 220px;
    }
    body[data-ui="v3"] .oc-root .topbar-search__kbd {
      display:inline-flex; align-items:center; justify-content:center;
      padding: 2px 6px; border:1px solid var(--border); border-radius: var(--radius-sm);
      background: var(--bg); font-family: var(--mono); font-size: 11px; color: var(--muted);
    }
    body[data-ui="v3"] .oc-root .shell-nav {
      grid-area: nav;
      display: flex;
      min-height: 100%;
      overflow: hidden;
      border-right: 1px solid color-mix(in srgb, var(--border) 74%, transparent);
      background: color-mix(in srgb, var(--panel) 98%, white 2%);
    }
    body[data-ui="v3"] .oc-root .sidebar { flex:1; display:flex; flex-direction:column; min-height:0; overflow:hidden; }
    body[data-ui="v3"] .oc-root .sidebar-shell { flex:1; display:flex; flex-direction:column; padding: 14px 10px 12px; min-height: 0; }
    body[data-ui="v3"] .oc-root .sidebar-shell__header { display:flex; align-items:center; justify-content:space-between; gap:12px; padding: 0 8px 18px; }
    body[data-ui="v3"] .oc-root .sidebar-brand { display:flex; align-items:center; gap:10px; min-width:0; }
    body[data-ui="v3"] .oc-root .sidebar-brand__logo {
      width: 32px; height: 32px; border-radius: 10px; flex-shrink:0;
      background: var(--panel-strong);
      border: 1px solid var(--border);
    }
    body[data-ui="v3"] .oc-root .sidebar-brand__copy { display:flex; flex-direction:column; gap:2px; min-width:0; }
    body[data-ui="v3"] .oc-root .sidebar-brand__eyebrow { font-size: 10px; font-weight: 600; letter-spacing: 0.08em; color: var(--muted); text-transform: uppercase; }
    body[data-ui="v3"] .oc-root .sidebar-brand__title { font-size: 15px; font-weight: 700; letter-spacing: -0.03em; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .sidebar-shell__body { flex:1; min-height:0; }
    body[data-ui="v3"] .oc-root .sidebar-nav { flex:1; overflow-y:auto; padding:0; }
    body[data-ui="v3"] .oc-root .nav-section { display:grid; gap:6px; margin-bottom: 16px; }
    body[data-ui="v3"] .oc-root .nav-section__label { padding: 0 10px; min-height: 28px; border:none; background:transparent; color: var(--muted); text-align:left; font-weight:700; font-size:12px; letter-spacing:0.06em; text-transform: uppercase; }
    body[data-ui="v3"] .oc-root .nav-section__items { display:grid; gap:4px; }
    body[data-ui="v3"] .oc-root .nav-section--collapsible { margin-bottom: 12px; }
    body[data-ui="v3"] .oc-root .nav-section__head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      padding: 6px 10px 8px;
      border: none;
      background: transparent;
      color: var(--muted);
      text-align: left;
      font-weight: 700;
      font-size: 12px;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      cursor: pointer;
      border-radius: var(--radius-sm);
      gap: 8px;
    }
    body[data-ui="v3"] .oc-root .nav-section__head:hover {
      color: var(--text);
      background: color-mix(in srgb, var(--bg-hover) 55%, transparent);
    }
    body[data-ui="v3"] .oc-root .nav-section__headText { flex: 1; min-width: 0; }
    body[data-ui="v3"] .oc-root .nav-section__chevron {
      width: 14px;
      height: 14px;
      display: flex;
      align-items: center;
      justify-content: center;
      opacity: 0.7;
      flex-shrink: 0;
      transition: transform var(--duration-fast) var(--ease-out);
    }
    body[data-ui="v3"] .oc-root .nav-section__chevron svg { width: 14px; height: 14px; stroke: currentColor; fill: none; stroke-width: 2px; }
    body[data-ui="v3"] .oc-root .nav-section--collapsed .nav-section__chevron { transform: rotate(-90deg); }
    body[data-ui="v3"] .oc-root .nav-section--collapsed .nav-section__items { display: none; }
    body[data-ui="v3"] .oc-root .nav-item {
      position: relative;
      display:flex; align-items:center; gap:8px;
      min-height: 40px; padding: 0 9px;
      border-radius: 12px;
      border: 1px solid transparent;
      background: transparent;
      color: var(--muted);
      cursor: pointer;
      user-select: none;
    }
    body[data-ui="v3"] .oc-root .nav-item:hover { color: var(--text); background: color-mix(in srgb, var(--bg-hover) 84%, transparent); border-color: color-mix(in srgb, var(--border) 72%, transparent); }
    body[data-ui="v3"] .oc-root .nav-item--active {
      color: var(--text-strong);
      background: color-mix(in srgb, var(--accent-subtle) 88%, var(--bg-elevated) 12%);
      border-color: color-mix(in srgb, var(--accent) 18%, transparent);
    }
    body[data-ui="v3"] .oc-root .nav-item__icon { width: 16px; height: 16px; display:flex; align-items:center; justify-content:center; opacity: 0.72; }
    body[data-ui="v3"] .oc-root .nav-item__icon svg { width:16px; height:16px; stroke: currentColor; fill:none; stroke-width:1.5px; stroke-linecap:round; stroke-linejoin:round; }
    body[data-ui="v3"] .oc-root .nav-item--active .nav-item__icon { opacity: 1; color: var(--accent); }
    body[data-ui="v3"] .oc-root .nav-item__text { font-size: 14px; font-weight: 600; white-space: nowrap; }

    body[data-ui="v3"] .oc-root .sidebar-shell__footer {
      flex-shrink: 0;
      margin-top: auto;
      padding: 10px 8px 4px;
      border-top: 1px solid color-mix(in srgb, var(--border) 80%, transparent);
    }
    body[data-ui="v3"] .oc-root .sidebar-doc-link {
      display: flex;
      align-items: center;
      gap: 10px;
      width: 100%;
      padding: 8px 10px;
      border-radius: var(--radius-md);
      border: 1px solid transparent;
      background: transparent;
      color: var(--text-strong);
      text-decoration: none;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: background 120ms ease, border-color 120ms ease;
    }
    body[data-ui="v3"] .oc-root .sidebar-doc-link:hover {
      background: var(--bg-hover);
      border-color: var(--border);
    }
    body[data-ui="v3"] .oc-root .sidebar-doc-link .nav-item__icon { opacity: 0.72; }

    body[data-ui="v3"] .oc-root .content {
      grid-area: content;
      padding: 16px 20px 32px;
      min-height: 0;
      overflow: auto;
      scrollbar-width: none;
      -ms-overflow-style: none;
      background: var(--bg-content);
      display: flex;
      flex-direction: column;
    }
    body[data-ui="v3"] .oc-root .content::-webkit-scrollbar {
      display: none;
      width: 0;
      height: 0;
    }
    body[data-ui="v3"] .oc-root .content-header {
      display:flex;
      align-items:flex-start;
      justify-content:space-between;
      gap: 16px;
      padding: 4px 8px;
      flex-shrink: 0;
      position: sticky;
      top: 0;
      z-index: 10;
      background: var(--bg-content);
      flex-wrap: wrap;
    }
    /* 定时任务：页标题与下方摘要条一体，随主区域一起滚动（取消 sticky，避免标题钉顶、摘要单独动） */
    body[data-ui="v3"] .oc-root main.content.content--cron .content-header {
      position: static;
      z-index: auto;
    }
    body[data-ui="v3"] .oc-root .content-header .btn.primary {
      border-color: var(--accent); background: var(--accent); color: var(--accent-foreground);
    }
    body[data-ui="v3"] .oc-root .content-header .btn.primary:hover:not(:disabled) {
      background: var(--accent-hover); border-color: var(--accent-hover);
    }
    body[data-ui="v3"] .oc-root .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      border: 1px solid var(--border);
      background: var(--bg-elevated);
      padding: 8px 14px;
      border-radius: var(--radius-md);
      font-size: 13px;
      font-weight: 500;
      cursor: pointer;
      transition: border-color 120ms ease, background 120ms ease;
      user-select: none;
    }
    body[data-ui="v3"] .oc-root .btn:hover { background: var(--bg-hover); border-color: var(--border-strong); }
    body[data-ui="v3"] .oc-root .btn:disabled { opacity: 0.5; cursor: not-allowed; }
    body[data-ui="v3"] .oc-root .btn--sm { padding: 6px 10px; font-size: 12px; }

    /* sessions table (current scoped subset) */
    body[data-ui="v3"] .oc-root .sessions-head { display:flex; align-items:flex-start; justify-content:space-between; gap:12px; }
    body[data-ui="v3"] .oc-root .sessions-title { font-size: 14px; font-weight: 600; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .sessions-sub { margin-top: 2px; font-size: 12px; color: var(--muted); }
    body[data-ui="v3"] .oc-root .filters { display:flex; flex-wrap:wrap; gap: 8px; align-items:center; margin-top: 12px; }
    body[data-ui="v3"] .oc-root .field-inline { display:inline-flex; align-items:center; gap:6px; font-size: 13px; color: var(--text); }
    body[data-ui="v3"] .oc-root .field-inline span { color: var(--muted); font-weight: 500; white-space: nowrap; }
    body[data-ui="v3"] .oc-root .field-inline input[type="text"],
    body[data-ui="v3"] .oc-root .field-inline input:not([type]) {
      padding: 6px 10px;
      font-size: 13px;
      color: var(--text);
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      outline: none;
    }
    body[data-ui="v3"] .oc-root .field-inline input:focus { border-color: var(--border-strong); box-shadow: var(--focus-ring); }
    body[data-ui="v3"] .oc-root .field-inline.checkbox { gap: 4px; cursor: default; }
    body[data-ui="v3"] .oc-root .field-inline.checkbox input[type="checkbox"] { width: 14px; height: 14px; accent-color: var(--accent); }

    body[data-ui="v3"] .oc-root .data-table-wrapper { margin-top: 12px; border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; background: var(--card); }
    body[data-ui="v3"] .oc-root .data-table-toolbar { display:flex; align-items:center; gap:8px; padding: 10px 12px; border-bottom: 1px solid var(--border); background: var(--bg-elevated); }
    body[data-ui="v3"] .oc-root .data-table-selectionbar {
      display:none;
      align-items:center;
      gap: 10px;
      padding: 10px 12px;
      border-bottom: 1px solid var(--border);
      background: rgba(220, 38, 38, 0.08);
      color: var(--text);
    }
    body[data-ui="v3"] .oc-root .data-table-selectionbar.is-on { display:flex; }
    body[data-ui="v3"] .oc-root .data-table-search { flex:1; min-width:0; }
    body[data-ui="v3"] .oc-root .data-table-search input {
      width: 100%;
      padding: 6px 10px;
      font-size: 13px;
      color: var(--text);
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      outline: none;
    }
    body[data-ui="v3"] .oc-root .data-table-search input::placeholder { color: var(--muted); }
    body[data-ui="v3"] .oc-root .data-table-search input:focus { border-color: var(--border-strong); box-shadow: var(--focus-ring); }
    body[data-ui="v3"] .oc-root .btn-danger {
      border-color: rgba(220, 38, 38, 0.45);
      color: var(--danger);
      background: #ffffff;
    }
    body[data-ui="v3"] .oc-root .btn-danger:hover { background: rgba(220, 38, 38, 0.06); border-color: rgba(220, 38, 38, 0.7); }
    body[data-ui="v3"] .oc-root .data-table-container { overflow-x:auto; }
    body[data-ui="v3"] .oc-root .data-table tr.is-selected td { background: rgba(220, 38, 38, 0.03); }
    body[data-ui="v3"] .oc-root .cell-input {
      width: 100%;
      padding: 6px 10px;
      font-size: 13px;
      color: var(--text);
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      outline: none;
    }
    body[data-ui="v3"] .oc-root .cell-input:focus { border-color: var(--border-strong); box-shadow: var(--focus-ring); }
    body[data-ui="v3"] .oc-root .data-table { width: 100%; border-collapse: collapse; font-size: 13px; }
    body[data-ui="v3"] .oc-root .data-table th {
      padding: 10px 12px;
      text-align: left;
      font-weight: 600;
      font-size: 12px;
      color: var(--muted);
      background: var(--bg-elevated);
      border-bottom: 1px solid var(--border);
      white-space: nowrap;
      user-select: none;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    body[data-ui="v3"] .oc-root .data-table td { padding: 10px 12px; border-bottom: 1px solid var(--border); color: var(--text); vertical-align: middle; }
    body[data-ui="v3"] .oc-root .data-table tbody tr:hover { background: var(--bg-hover); }
    body[data-ui="v3"] .oc-root .data-table td.mono { font-family: var(--mono); font-size: 12px; }
    body[data-ui="v3"] .oc-root .data-table input[type="checkbox"] { width: 14px; height: 14px; accent-color: var(--accent); }
    body[data-ui="v3"] .oc-root .data-table-badge { display:inline-block; padding: 2px 8px; font-size: 11px; font-weight: 600; border-radius: var(--radius-full); letter-spacing: 0.02em; }
    body[data-ui="v3"] .oc-root .data-table-badge--direct { color: #0d9488; background: rgba(13, 148, 136, 0.08); }
    body[data-ui="v3"] .oc-root .data-table-badge--unknown { color: var(--muted); background: var(--bg-hover); }
    body[data-ui="v3"] .oc-root .session-link { color: var(--accent); font-weight: 500; text-decoration: none; }
    body[data-ui="v3"] .oc-root .session-link:hover { text-decoration: underline; }
    body[data-ui="v3"] .oc-root .session-key-display-name { font-size: 11px; color: var(--muted); margin-top: 2px; }
    body[data-ui="v3"] .oc-root .cell-optional { color: var(--muted); font-size: 12px; }
    body[data-ui="v3"] .oc-root .cell-updated { color: var(--muted); font-size: 12px; white-space: nowrap; }
    body[data-ui="v3"] .oc-root .cell-tokens { font-family: var(--mono); font-size: 12px; white-space: nowrap; }
    body[data-ui="v3"] .oc-root .cell-select {
      padding: 6px 28px 6px 10px;
      font-size: 12px;
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      background: var(--card);
      appearance: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='%238e8e93' stroke-width='2'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 8px center;
      color: var(--text);
    }
    body[data-ui="v3"] .oc-root .cell-select:disabled { opacity: 0.7; }
    body[data-ui="v3"] .oc-root .data-table-pagination {
      display:flex;
      align-items:center;
      justify-content: space-between;
      gap: 12px;
      padding: 10px 12px;
      border-top: 1px solid var(--border);
      background: var(--bg-elevated);
      font-size: 13px;
      color: var(--muted);
    }
    body[data-ui="v3"] .oc-root .data-table-pagination__controls { display:flex; align-items:center; gap: 8px; }
    body[data-ui="v3"] .oc-root .data-table-pagination__controls button {
      padding: 4px 12px;
      font-size: 13px;
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      background: var(--card);
      color: var(--text);
      cursor: pointer;
    }
    body[data-ui="v3"] .oc-root .data-table-pagination__controls button:disabled { opacity: 0.4; cursor: not-allowed; }

    /* skills page (Metis-like) */
    body[data-ui="v3"] .oc-root .skills-topbar { display:flex; align-items:flex-start; justify-content:space-between; gap:12px; }
    body[data-ui="v3"] .oc-root .skills-topbar-left { min-width:0; }
    body[data-ui="v3"] .oc-root .skills-topbar-title { font-size: 14px; font-weight: 600; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .skills-topbar-sub { margin-top: 2px; font-size: 12px; color: var(--muted); }
    body[data-ui="v3"] .oc-root .skills-actions-row { margin-top: 12px; display:flex; align-items:center; gap: 10px; }
    body[data-ui="v3"] .oc-root .skills-actions-row .btn { padding: 6px 10px; font-size: 12px; }
    body[data-ui="v3"] .oc-root .skills-search { flex: 1; min-width: 0; }
    body[data-ui="v3"] .oc-root .skills-search input { width: 100%; padding: 6px 10px; font-size: 13px; background: var(--card); border: 1px solid var(--border); border-radius: var(--radius-sm); outline:none; }
    body[data-ui="v3"] .oc-root .skills-search input:focus { border-color: var(--border-strong); box-shadow: var(--focus-ring); }
    body[data-ui="v3"] .oc-root .skills-shown { margin-left: auto; font-size: 12px; color: var(--muted); white-space: nowrap; }
    body[data-ui="v3"] .oc-root .skills-section-label { margin-top: 14px; font-size: 11px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: 0.04em; }
    body[data-ui="v3"] .oc-root .skills-section-head {
      margin-top: 14px;
      display:flex;
      align-items:center;
      justify-content:space-between;
      gap: 10px;
    }
    body[data-ui="v3"] .oc-root .skills-section-meta { display:flex; align-items:center; gap: 8px; color: var(--muted); font-size: 12px; }
    body[data-ui="v3"] .oc-root .skills-collapse-btn {
      width: 24px;
      height: 24px;
      display:inline-flex;
      align-items:center;
      justify-content:center;
      border: 1px solid transparent;
      border-radius: var(--radius-sm);
      background: transparent;
      cursor: pointer;
      color: var(--muted-strong);
      padding: 0;
    }
    body[data-ui="v3"] .oc-root .skills-collapse-btn:hover { background: var(--bg-hover); border-color: var(--border); }
    body[data-ui="v3"] .oc-root .skills-collapse-btn svg { width: 16px; height: 16px; stroke: currentColor; fill: none; stroke-width: 1.8px; stroke-linecap: round; stroke-linejoin: round; }
    body[data-ui="v3"] .oc-root .skills-list { margin-top: 8px; display: grid; gap: 10px; }
    body[data-ui="v3"] .oc-root .skill-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 12px;
      align-items: start;
      border: 1px solid var(--border);
      border-radius: var(--radius-md);
      background: var(--card);
      padding: 12px;
      transition: border-color 120ms ease, background 120ms ease;
    }
    body[data-ui="v3"] .oc-root .skill-row:hover { border-color: var(--border-strong); background: var(--bg-hover); }
    body[data-ui="v3"] .oc-root .skill-name { font-weight: 600; font-size: 13px; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .skill-desc { margin-top: 4px; font-size: 12px; color: var(--muted); line-height: 1.45; }
    body[data-ui="v3"] .oc-root .skill-tags { margin-top: 8px; display:flex; gap: 6px; flex-wrap: wrap; }
    body[data-ui="v3"] .oc-root .chip { font-size: 12px; font-weight: 500; border: 1px solid var(--border); border-radius: var(--radius-full); padding: 5px 12px; color: var(--muted); background: var(--secondary); }
    body[data-ui="v3"] .oc-root .chip-ok { color: var(--ok); border-color: rgba(22, 163, 74, 0.3); background: rgba(22, 163, 74, 0.08); }
    body[data-ui="v3"] .oc-root .chip-warn { color: #b45309; border-color: rgba(217, 119, 6, 0.35); background: rgba(217, 119, 6, 0.06); }
    body[data-ui="v3"] .oc-root .skill-action { display:flex; flex-direction:column; align-items:center; gap: 8px; padding-top: 2px; }
    body[data-ui="v3"] .oc-root .skill-action .btn { min-width: 84px; color: #111111; }
    body[data-ui="v3"] .oc-root .skill-action .btn.primary { border-color: var(--accent); background: var(--accent); color: var(--accent-foreground); }
    body[data-ui="v3"] .oc-root .skill-action .btn.primary:hover { background: var(--accent-hover); border-color: var(--accent-hover); }
    body[data-ui="v3"] .oc-root .skill-action .btn:disabled { opacity: 0.55; cursor: not-allowed; }
    body[data-ui="v3"] .oc-root .skill-state { font-size: 12px; color: #0f766e; }
    body[data-ui="v3"] .oc-root .skill-state:hover { text-decoration: none; }
    body[data-ui="v3"] .oc-root .skill-reason { margin-top: 10px; font-size: 12px; color: var(--muted-strong); }

    /* appearance page — aligned with current config styles */
    body[data-ui="v3"] .oc-root .appearance-header-actions { display:flex; flex-wrap:wrap; gap:8px; align-items:center; justify-content:flex-end; }
    body[data-ui="v3"] .oc-root .appearance-shell { flex:1; min-width:0; }
    body[data-ui="v3"] .oc-root .appearance-page { display:flex; flex-direction:column; gap:18px; margin-top:2px; }
    body[data-ui="v3"] .oc-root .appearance-subtabs { display:flex; gap:6px; flex-wrap:wrap; border-bottom:1px solid var(--border); padding-bottom:12px; }
    body[data-ui="v3"] .oc-root .appearance-subtab {
      border:1px solid transparent; background:transparent; color: var(--muted-strong);
      font-size:13px; font-weight:650; letter-spacing:-0.02em; padding:8px 12px; border-radius: var(--radius-md); cursor:pointer;
      transition: border-color var(--duration-fast) var(--ease-out), background var(--duration-fast) var(--ease-out);
    }
    body[data-ui="v3"] .oc-root .appearance-subtab:hover { background: var(--bg-hover); border-color: color-mix(in srgb, var(--border) 70%, transparent); }
    body[data-ui="v3"] .oc-root .appearance-subtab--active {
      border-color: var(--border); background: var(--card); color: var(--text-strong);
      box-shadow: 0 0 0 1px color-mix(in srgb, var(--border) 40%, transparent);
    }
    body[data-ui="v3"] .oc-root .appearance-panel { display:block; }
    body[data-ui="v3"] .oc-root .appearance-panel[hidden] { display:none !important; }
    body[data-ui="v3"] .oc-root .settings-appearance { display:grid; gap:18px; }
    body[data-ui="v3"] .oc-root .settings-appearance__section {
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      background: var(--bg-elevated);
      padding: 18px;
      display: grid;
      gap: 14px;
    }
    body[data-ui="v3"] .oc-root .settings-appearance__heading {
      margin: 0;
      font-size: 15px;
      font-weight: 650;
      letter-spacing: -0.02em;
      color: var(--text-strong);
    }
    body[data-ui="v3"] .oc-root .settings-appearance__hint {
      margin: -8px 0 0;
      font-size: 12.5px;
      color: var(--muted);
      line-height: 1.45;
    }
    body[data-ui="v3"] .oc-root .settings-theme-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 12px;
    }
    body[data-ui="v3"] .oc-root .settings-theme-card {
      position: relative;
      display: grid;
      grid-template-columns: auto 1fr auto;
      align-items: center;
      gap: 10px;
      min-height: 64px;
      padding: 14px 16px;
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      background: var(--bg);
      color: var(--text);
      text-align: left;
      cursor: pointer;
      transition:
        border-color var(--duration-fast) ease,
        background var(--duration-fast) ease,
        box-shadow var(--duration-fast) ease,
        transform var(--duration-fast) ease;
    }
    body[data-ui="v3"] .oc-root .settings-theme-card:hover {
      border-color: var(--border-strong);
      background: var(--bg-hover);
      transform: translateY(-1px);
    }
    body[data-ui="v3"] .oc-root .settings-theme-card--active {
      border-color: color-mix(in srgb, var(--accent) 35%, transparent);
      background: color-mix(in srgb, var(--accent) 10%, var(--bg-elevated));
      box-shadow: 0 0 0 1px color-mix(in srgb, var(--accent) 14%, transparent);
    }
    body[data-ui="v3"] .oc-root .settings-theme-card__icon,
    body[data-ui="v3"] .oc-root .settings-theme-card__check {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 18px;
      height: 18px;
      color: var(--accent);
    }
    body[data-ui="v3"] .oc-root .settings-theme-card__icon svg,
    body[data-ui="v3"] .oc-root .settings-theme-card__check svg {
      width: 18px;
      height: 18px;
      stroke: currentColor;
      fill: none;
    }
    body[data-ui="v3"] .oc-root .settings-theme-card__label {
      font-size: 13px;
      font-weight: 600;
      color: var(--text-strong);
    }
    body[data-ui="v3"] .oc-root .settings-info-grid { display: grid; gap: 10px; }
    body[data-ui="v3"] .oc-root .settings-info-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 12px 14px;
      border: 1px solid var(--border);
      border-radius: var(--radius-md);
      background: var(--bg);
    }
    body[data-ui="v3"] .oc-root .settings-info-row__label {
      font-size: 12px;
      font-weight: 600;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    body[data-ui="v3"] .oc-root .settings-info-row__value {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      min-width: 0;
      font-size: 13px;
      font-weight: 500;
      color: var(--text);
      text-align: right;
    }
    body[data-ui="v3"] .oc-root .settings-status-dot {
      width: 8px;
      height: 8px;
      border-radius: var(--radius-full);
      background: var(--muted);
      box-shadow: 0 0 0 4px color-mix(in srgb, var(--muted) 14%, transparent);
    }
    body[data-ui="v3"] .oc-root .settings-status-dot--ok {
      background: var(--ok);
      box-shadow: 0 0 0 4px color-mix(in srgb, var(--ok) 14%, transparent);
    }

    /* Communication page (Metis settings / 通信) */
    body[data-ui="v3"] .oc-root .comm-breadcrumb { font-size: 12px; margin-bottom: 4px; letter-spacing: -0.01em; }
    body[data-ui="v3"] .oc-root .comm-toolbar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: flex-end;
      gap: 10px;
      flex: 1;
      min-width: 0;
    }
    body[data-ui="v3"] .oc-root .comm-toolbar__search {
      min-width: 180px;
      max-width: 280px;
      flex: 1;
    }
    body[data-ui="v3"] .oc-root .comm-page { display: block; }
    body[data-ui="v3"] .oc-root .comm-subtabs {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-bottom: 16px;
      padding: 4px 0;
    }
    body[data-ui="v3"] .oc-root .comm-subtab {
      border: 1px solid var(--border);
      background: var(--bg);
      color: var(--muted-strong);
      font-size: 13px;
      font-weight: 600;
      padding: 8px 14px;
      border-radius: var(--radius-full);
      cursor: pointer;
      transition: background var(--duration-fast) ease, border-color var(--duration-fast) ease, color var(--duration-fast) ease;
    }
    body[data-ui="v3"] .oc-root .comm-subtab:hover {
      border-color: var(--border-strong);
      background: var(--bg-hover);
      color: var(--text);
    }
    body[data-ui="v3"] .oc-root .comm-subtab--active {
      border-color: color-mix(in srgb, var(--accent) 35%, transparent);
      background: var(--card);
      color: var(--text-strong);
      box-shadow: 0 1px 3px rgba(0,0,0,0.06);
    }
    body[data-ui="v3"] .oc-root .comm-body {
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      background: var(--bg-elevated);
      padding: 18px;
      min-height: 120px;
    }
    body[data-ui="v3"] .oc-root .comm-section-head {
      display: flex;
      align-items: flex-start;
      gap: 12px;
      margin-bottom: 16px;
    }
    body[data-ui="v3"] .oc-root .comm-section-head__icon {
      width: 36px;
      height: 36px;
      border-radius: var(--radius-md);
      border: 1px solid var(--border);
      background: var(--card);
      display: flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    body[data-ui="v3"] .oc-root .comm-section-head__icon svg { width: 18px; height: 18px; stroke: currentColor; fill: none; }
    body[data-ui="v3"] .oc-root .comm-section-head__title { font-size: 15px; font-weight: 650; color: var(--text-strong); letter-spacing: -0.02em; }
    body[data-ui="v3"] .oc-root .comm-section-head__sub { font-size: 12.5px; margin-top: 2px; line-height: 1.45; }
    body[data-ui="v3"] .oc-root .comm-channel-list { display: grid; gap: 14px; }
    body[data-ui="v3"] .oc-root .comm-channel-card {
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      background: var(--card);
      padding: 16px 18px;
    }
    body[data-ui="v3"] .oc-root .comm-channel-card__head {
      display: flex;
      align-items: flex-start;
      gap: 12px;
    }
    body[data-ui="v3"] .oc-root .comm-channel-card__headIcon {
      width: 32px;
      height: 32px;
      border-radius: var(--radius-md);
      border: 1px solid var(--border);
      display: flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
      background: var(--bg-elevated);
    }
    body[data-ui="v3"] .oc-root .comm-channel-card__headIcon svg { width: 16px; height: 16px; stroke: currentColor; fill: none; }
    body[data-ui="v3"] .oc-root .comm-channel-card__headText { flex: 1; min-width: 0; }
    body[data-ui="v3"] .oc-root .comm-channel-card__nameRow { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px; }
    body[data-ui="v3"] .oc-root .comm-channel-card__name { font-size: 15px; font-weight: 650; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .comm-channel-card__sub { font-size: 12px; }
    body[data-ui="v3"] .oc-root .comm-channel-card__tags { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
    body[data-ui="v3"] .oc-root .comm-tag {
      font-size: 11px;
      font-weight: 600;
      padding: 3px 8px;
      border-radius: var(--radius-sm);
      border: 1px solid var(--border);
      background: var(--secondary);
      color: var(--muted-strong);
      text-transform: lowercase;
    }
    body[data-ui="v3"] .oc-root .comm-channel-card__desc { margin: 8px 0 0; font-size: 12.5px; line-height: 1.45; }
    body[data-ui="v3"] .oc-root .comm-toggle {
      width: 44px;
      height: 24px;
      border-radius: 999px;
      background: var(--border-strong);
      position: relative;
      flex-shrink: 0;
      margin-top: 2px;
    }
    body[data-ui="v3"] .oc-root .comm-toggle__track {
      position: absolute;
      width: 18px;
      height: 18px;
      border-radius: 999px;
      background: #fff;
      top: 3px;
      left: 3px;
      box-shadow: 0 1px 2px rgba(0,0,0,0.15);
      transition: transform var(--duration-fast) ease;
    }
    body[data-ui="v3"] .oc-root .comm-toggle--on {
      background: color-mix(in srgb, var(--ok) 85%, #15803d);
    }
    body[data-ui="v3"] .oc-root .comm-toggle--on .comm-toggle__track { transform: translateX(20px); }
    body[data-ui="v3"] .oc-root .comm-bound {
      margin-top: 10px;
      font-size: 12px;
      padding: 8px 10px;
      border-radius: var(--radius-md);
      background: var(--bg-muted);
      border: 1px solid var(--border);
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 8px;
    }
    body[data-ui="v3"] .oc-root .comm-bound code.mono {
      background: var(--card) !important;
      color: var(--text-strong) !important;
      border: 1px solid var(--border);
      padding: 4px 10px;
      border-radius: var(--radius-sm);
      font-size: 12px;
      font-weight: 500;
    }
    body[data-ui="v3"] .oc-root .comm-channel-card__fields {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 12px 18px;
      margin-top: 14px;
      padding-top: 14px;
      border-top: 1px solid var(--border);
    }
    body[data-ui="v3"] .oc-root .comm-field__label {
      font-size: 11px;
      font-weight: 650;
      color: var(--muted);
      margin-bottom: 4px;
      letter-spacing: 0.02em;
    }
    body[data-ui="v3"] .oc-root .comm-field__value {
      font-size: 13px;
      color: var(--text-strong);
      word-break: break-word;
      padding: 8px 10px;
      border-radius: var(--radius-md);
      border: 1px solid var(--border);
      background: var(--bg);
    }
    body[data-ui="v3"] .oc-root .comm-placeholder,
    body[data-ui="v3"] .oc-root .comm-empty { padding: 12px 4px; font-size: 13px; }
    body[data-ui="v3"] .oc-root .comm-overview .settings-info-grid { margin-top: 0; }

    body[data-ui="v3"] .oc-root .appearance-wizard-meta { display:grid; gap:8px; margin-top:4px; font-size:12px; color: var(--muted); }
    body[data-ui="v3"] .oc-root .appearance-wizard-box {
      border:1px dashed var(--border); border-radius: var(--radius-md); padding:12px 14px; font-family: var(--mono); font-size:12px; color: var(--muted-strong);
      background: var(--bg);
    }
    body[data-ui="v3"] .oc-root.theme-family-knot {
      --accent: #4f46e5; --accent-hover: #6366f1; --accent-muted: #4f46e5; --ring: #4f46e5;
      --accent-subtle: rgba(79, 70, 229, 0.1); --accent-glow: rgba(79, 70, 229, 0.12);
    }
    body[data-ui="v3"] .oc-root.theme-family-dash {
      --accent: #059669; --accent-hover: #10b981; --accent-muted: #059669; --ring: #059669;
      --accent-subtle: rgba(5, 150, 105, 0.12); --accent-glow: rgba(5, 150, 105, 0.12);
    }
    body[data-ui="v3"] .oc-root.theme-family-claw {
      --accent: #dc2626; --accent-hover: #ef4444; --accent-muted: #dc2626; --ring: #dc2626;
      --accent-subtle: rgba(220, 38, 38, 0.08); --accent-glow: rgba(220, 38, 38, 0.1);
    }
    body[data-ui="v3"] .oc-root.appearance-radius-none { --radius-sm: 2px; --radius-md: 4px; --radius-lg: 6px; }
    body[data-ui="v3"] .oc-root.appearance-radius-slight { --radius-sm: 4px; --radius-md: 8px; --radius-lg: 12px; }
    body[data-ui="v3"] .oc-root.appearance-radius-default { --radius-sm: 6px; --radius-md: 10px; --radius-lg: 14px; }
    body[data-ui="v3"] .oc-root.appearance-radius-round { --radius-sm: 10px; --radius-md: 16px; --radius-lg: 20px; }
    body[data-ui="v3"] .oc-root.appearance-radius-full { --radius-sm: 12px; --radius-md: 18px; --radius-lg: 22px; }
    body[data-ui="v3"] .oc-root.appearance-radius-full .settings-theme-card { border-radius: 999px; }

    body[data-ui="v3"] .oc-root .chat-controls {
      display: flex;
      align-items: center;
      justify-content: flex-start;
      gap: 12px;
      flex-wrap: wrap;
    }
    body[data-ui="v3"] .oc-root .chat-controls__session { min-width: 240px; max-width: 520px; }
    body[data-ui="v3"] .oc-root .chat-controls__model { min-width: 220px; max-width: 520px; }
    body[data-ui="v3"] .oc-root .chat-controls select {
      width: 100%;
      border: 1px solid var(--input);
      background: var(--card);
      border-radius: var(--radius-md);
      padding: 8px 36px 8px 12px;
      outline: none;
      box-shadow: inset 0 1px 0 var(--card-highlight);
      appearance: none;
      cursor: pointer;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%238e8e93' stroke-width='2'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 10px center;
    }
    body[data-ui="v3"] .oc-root .chat-controls select:focus { border-color: var(--ring); box-shadow: var(--focus-ring); }
    body[data-ui="v3"] .oc-root .model-actions { display: none; }
    body[data-ui="v3"] .oc-root .page-title { font-size: 22px; font-weight: 650; letter-spacing: -0.03em; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .page-sub { color: var(--muted); font-size: 13px; margin-top: 4px; }
    body[data-ui="v3"] .oc-root .page-meta { display:flex; gap: 8px; align-items:center; }
    body[data-ui="v3"] .oc-root .card { border: 1px solid var(--border); background: var(--card); border-radius: var(--radius-lg); padding: 18px; }

    /* Chat view (current scoped subset) */
    body[data-ui="v3"] .oc-root .chat { flex: 1; min-height: 0; display:flex; flex-direction:column; }
    body[data-ui="v3"] .oc-root .chat-thread { flex:1; min-height:0; overflow-y:auto; overflow-x:hidden; padding: 0 12px 16px; }
    body[data-ui="v3"] .oc-root .chat-line { display:flex; }
    body[data-ui="v3"] .oc-root .chat-line.user { justify-content:flex-end; }
    body[data-ui="v3"] .oc-root .chat-line.assistant { justify-content:flex-start; }
    body[data-ui="v3"] .oc-root .chat-msg { display:grid; gap:6px; max-width: min(700px, 82%); }
    body[data-ui="v3"] .oc-root .chat-bubble { border: 1px solid var(--border); background: var(--bg); border-radius: var(--radius-lg); padding: 10px 14px; white-space: pre-wrap; overflow-wrap:anywhere; }
    body[data-ui="v3"] .oc-root .chat-line.user .chat-bubble { border-color: rgba(234, 88, 12, 0.2); background: rgba(251, 146, 60, 0.12); }
    body[data-ui="v3"] .oc-root .chat-line.assistant .chat-bubble { background: var(--bg-muted); }
    body[data-ui="v3"] .oc-root .chat-stamp { font-size: 11px; color: var(--muted); }
    body[data-ui="v3"] .oc-root .chat-bubble-wrap { position: relative; }
    body[data-ui="v3"] .oc-root .chat-copy-btn {
      position: absolute;
      top: 6px;
      right: 6px;
      width: 28px;
      height: 28px;
      border-radius: var(--radius-sm);
      border: none;
      background: transparent;
      color: var(--muted);
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 0;
      opacity: 0;
      transition: opacity 120ms ease, background 120ms ease, color 120ms ease;
    }
    body[data-ui="v3"] .oc-root .chat-bubble-wrap:hover .chat-copy-btn { opacity: 1; }
    body[data-ui="v3"] .oc-root .chat-copy-btn:hover { color: var(--text); background: var(--bg-hover); }
    body[data-ui="v3"] .oc-root .chat-copy-btn svg { width: 16px; height: 16px; stroke: currentColor; fill: none; stroke-width: 1.5px; stroke-linecap: round; stroke-linejoin: round; }
    body[data-ui="v3"] .oc-root .chat-copy-btn.copied { opacity: 1; color: var(--ok); background: rgba(22, 163, 74, 0.08); }
    body[data-ui="v3"] .oc-root .chat-del-btn {
      width: 28px;
      height: 28px;
      border-radius: var(--radius-sm);
      border: none;
      background: transparent;
      color: var(--muted-strong);
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 0;
      opacity: 0;
      transition: background 120ms ease, opacity 120ms ease, color 120ms ease;
    }
    body[data-ui="v3"] .oc-root .chat-line.assistant:hover .chat-del-btn { opacity: 0.9; }
    body[data-ui="v3"] .oc-root .chat-del-btn:hover { background: var(--danger-subtle); opacity: 1; color: var(--danger); }
    body[data-ui="v3"] .oc-root .chat-del-btn svg { width: 16px; height: 16px; stroke: currentColor; fill: none; stroke-width: 1.5px; stroke-linecap: round; stroke-linejoin: round; }
    body[data-ui="v3"] .oc-root .chat-line-inner { display:flex; align-items:flex-end; gap: 10px; width: 100%; }
    body[data-ui="v3"] .oc-root .chat-line.user .chat-line-inner { justify-content: flex-end; }
    body[data-ui="v3"] .oc-root .chat-line.assistant .chat-line-inner { justify-content: flex-start; }
    body[data-ui="v3"] .oc-root .chat-line.user .chat-msg { justify-items: end; }
    body[data-ui="v3"] .oc-root .chat-avatar {
      width: 26px;
      height: 26px;
      border-radius: 50%;
      border: 1px solid var(--border);
      background: var(--card);
      color: var(--muted);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
      overflow: hidden;
    }
    body[data-ui="v3"] .oc-root .chat-avatar svg { width: 16px; height: 16px; stroke: currentColor; fill: none; stroke-width: 1.5px; stroke-linecap: round; stroke-linejoin: round; }
    body[data-ui="v3"] .oc-root .agent-chat__input {
      margin: 0 18px 14px;
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      overflow: hidden;
      flex-shrink: 0;
    }
    body[data-ui="v3"] .oc-root .agent-chat__input > textarea {
      width:100%;
      min-height: 40px;
      max-height: 150px;
      resize: none;
      padding: 12px 14px 8px;
      border: none;
      background: transparent;
      color: var(--text);
      outline: none;
      font-size: 0.92rem;
      line-height: 1.4;
      font-family: inherit;
    }
    body[data-ui="v3"] .oc-root .agent-chat__toolbar {
      display:flex;
      align-items:center;
      justify-content: space-between;
      padding: 6px 10px;
      border-top: 1px solid color-mix(in srgb, var(--border) 50%, transparent);
    }
    body[data-ui="v3"] .oc-root .btn-ghost {
      display:inline-flex; align-items:center; justify-content:center;
      width: 30px; height: 30px;
      border-radius: var(--radius-sm);
      border: none;
      background: transparent;
      color: var(--muted);
      cursor: pointer;
      padding: 0;
    }
    body[data-ui="v3"] .oc-root .btn-ghost:hover { color: var(--text); background: var(--bg-hover); }
    body[data-ui="v3"] .oc-root .btn-ghost svg { width: 16px; height: 16px; stroke: currentColor; fill:none; stroke-width:1.5px; }
    body[data-ui="v3"] .oc-root .chat-send-btn {
      display:inline-flex; align-items:center; justify-content:center;
      width: 30px; height: 30px;
      border-radius: var(--radius-md);
      border: none;
      background: var(--accent);
      color: var(--accent-foreground);
      cursor:pointer;
      padding: 0;
    }
    body[data-ui="v3"] .oc-root .chat-send-btn:hover:not(:disabled) { background: var(--accent-hover); }
    body[data-ui="v3"] .oc-root .chat-send-btn:disabled { opacity: 0.3; cursor: not-allowed; }
    body[data-ui="v3"] .oc-root .chat-send-btn svg { width: 15px; height: 15px; stroke: currentColor; fill:none; stroke-width:1.5px; }

    /* Cron page — 对齐当前「定时任务」布局 */
    body[data-ui="v3"] .oc-root .cron-page { padding: 0; border: none; background: transparent; box-shadow: none; }
    body[data-ui="v3"] .oc-root .cron-page .card-title { display: none; }
    body[data-ui="v3"] .oc-root .cron-page__layout {
      display: grid;
      grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
      gap: 20px;
      align-items: start;
    }
    body[data-ui="v3"] .oc-root .cron-page__main { min-width: 0; }
    @media (max-width: 1100px) {
      body[data-ui="v3"] .oc-root .cron-page__layout { grid-template-columns: 1fr; }
    }
    body[data-ui="v3"] .oc-root .cron-summary {
      display: flex; flex-wrap: wrap; align-items: stretch; gap: 12px;
      margin-bottom: 18px;
    }
    body[data-ui="v3"] .oc-root .cron-summary__card {
      flex: 1 1 140px;
      min-width: 120px;
      padding: 12px 14px;
      border-radius: var(--radius-md);
      border: 1px solid var(--border);
      background: var(--card);
    }
    body[data-ui="v3"] .oc-root .cron-summary__label { font-size: 11px; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: var(--muted); }
    body[data-ui="v3"] .oc-root .cron-summary__value { margin-top: 6px; font-size: 15px; font-weight: 600; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .cron-badge--yes {
      display: inline-block; padding: 2px 6px; border-radius: 4px; font-size: 12px; font-weight: 600;
      background: rgba(34, 197, 94, 0.15); color: #15803d;
    }
    body[data-ui="v3"] .oc-root .cron-badge--no {
      display: inline-block; padding: 2px 6px; border-radius: 4px; font-size: 12px; font-weight: 600;
      background: rgba(148, 163, 184, 0.2); color: var(--muted);
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] .cron-badge--yes { background: rgba(34, 197, 94, 0.15); color: #86efac; }
    body[data-ui="v3"] .oc-root .cron-section {
      margin-bottom: 22px;
      padding: 14px 16px;
      border-radius: var(--radius-md);
      border: 1px solid var(--border);
      background: var(--card);
    }
    body[data-ui="v3"] .oc-root .cron-section__title { font-size: 15px; font-weight: 700; color: var(--text-strong); }
    body[data-ui="v3"] .oc-root .cron-section__sub { margin-top: 4px; font-size: 12px; color: var(--muted); }
    body[data-ui="v3"] .oc-root .cron-filters { display: flex; flex-wrap: wrap; gap: 8px; align-items: flex-end; margin-top: 12px; }
    body[data-ui="v3"] .oc-root .cron-filters label { display: flex; flex-direction: column; gap: 4px; font-size: 12px; color: var(--muted); font-weight: 500; }
    body[data-ui="v3"] .oc-root .cron-filters input,
    body[data-ui="v3"] .oc-root .cron-filters select {
      padding: 6px 10px; font-size: 13px; color: var(--text); background: var(--bg-elevated);
      border: 1px solid var(--border); border-radius: var(--radius-sm); min-width: 0;
    }
    body[data-ui="v3"] .oc-root .cron-section--run-history { width: 100%; }
    body[data-ui="v3"] .oc-root .cron-run-history__head {
      display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; flex-wrap: wrap;
      margin-bottom: 12px;
    }
    body[data-ui="v3"] .oc-root .cron-run-history__count { font-size: 12px; white-space: nowrap; align-self: center; }
    body[data-ui="v3"] .oc-root .cron-run-history__row--1 {
      display: grid;
      grid-template-columns: minmax(120px, 0.22fr) minmax(0, 1fr) minmax(120px, 0.2fr);
      gap: 12px; align-items: end; width: 100%;
    }
    body[data-ui="v3"] .oc-root .cron-run-history__row--2 {
      display: grid; grid-template-columns: 1fr 1fr; gap: 12px; align-items: end; width: 100%; margin-top: 10px;
    }
    body[data-ui="v3"] .oc-root .cron-run-history__field { min-width: 0; display: flex; flex-direction: column; gap: 4px; }
    body[data-ui="v3"] .oc-root .cron-run-history__lbl { font-size: 12px; font-weight: 600; color: var(--muted); }
    body[data-ui="v3"] .oc-root .cron-run-history__control {
      width: 100%; min-height: 36px; padding: 6px 10px; border-radius: var(--radius-sm);
      border: 1px solid var(--border); background: var(--bg-elevated); color: var(--text); font-size: 13px; box-sizing: border-box;
    }
    body[data-ui="v3"] .oc-root .cron-run-history__list { margin-top: 14px; display: flex; flex-direction: column; gap: 10px; }
    body[data-ui="v3"] .oc-root .cron-run-history__item {
      display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap;
      padding: 14px 16px; border-radius: var(--radius-md);
      border: 1px solid var(--border); background: var(--bg-elevated);
    }
    body[data-ui="v3"] .oc-root .cron-run-history__item-main { min-width: 0; flex: 1 1 220px; }
    body[data-ui="v3"] .oc-root .cron-run-history__item-title {
      font-size: 14px; font-weight: 600; color: var(--text-strong);
      display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
    }
    body[data-ui="v3"] .oc-root .cron-run-history__badge { font-weight: 600; font-size: 12px; }
    body[data-ui="v3"] .oc-root .cron-run-history__item-sum { margin-top: 6px; font-size: 13px; color: var(--text); line-height: 1.45; word-break: break-word; }
    body[data-ui="v3"] .oc-root .cron-run-history__deliv-pill {
      display: inline-block; margin-top: 8px; padding: 2px 8px; border-radius: 6px; font-size: 11px;
      background: color-mix(in srgb, var(--muted) 14%, transparent); color: var(--muted); font-weight: 600;
    }
    body[data-ui="v3"] .oc-root .cron-run-history__item-meta {
      flex: 0 0 auto; text-align: right; font-size: 12px; line-height: 1.5; color: var(--text);
    }
    body[data-ui="v3"] .oc-root .cron-run-history__empty { text-align: left; }
    @media (max-width: 720px) {
      body[data-ui="v3"] .oc-root .cron-run-history__row--1 { grid-template-columns: 1fr; }
      body[data-ui="v3"] .oc-root .cron-run-history__item-meta { text-align: left; width: 100%; }
    }
    body[data-ui="v3"] .oc-root .cron-aside {
      position: sticky; top: 12px;
      min-width: 0;
      max-height: none;
      overflow: visible;
      padding: 14px 16px;
      border-radius: var(--radius-md);
      border: 1px solid var(--border);
      background: var(--card);
    }
    body[data-ui="v3"] .oc-root .cron-aside__title { font-size: 14px; font-weight: 700; color: var(--text-strong); margin-bottom: 4px; }
    body[data-ui="v3"] .oc-root .cron-field { margin-bottom: 12px; }
    body[data-ui="v3"] .oc-root .cron-field label { display: block; font-size: 12px; font-weight: 600; color: var(--muted); margin-bottom: 4px; }
    body[data-ui="v3"] .oc-root .cron-field input[type="text"],
    body[data-ui="v3"] .oc-root .cron-field input[type="datetime-local"],
    body[data-ui="v3"] .oc-root .cron-field input[type="number"],
    body[data-ui="v3"] .oc-root .cron-field select,
    body[data-ui="v3"] .oc-root .cron-field textarea {
      width: 100%; padding: 8px 10px; font-size: 13px; color: var(--text);
      background: var(--bg-elevated); border: 1px solid var(--border); border-radius: var(--radius-sm);
      box-sizing: border-box;
    }
    body[data-ui="v3"] .oc-root .cron-field textarea { min-height: 72px; resize: vertical; }
    body[data-ui="v3"] .oc-root .cron-field-hint { font-size: 11px; color: var(--muted); margin-top: 4px; line-height: 1.4; }
    body[data-ui="v3"] .oc-root .cron-form-actions { display: flex; gap: 8px; margin-top: 14px; flex-wrap: wrap; }
    body[data-ui="v3"] .oc-root .cron-form-actions--footer {
      margin-top: 14px; align-items: center; justify-content: space-between; gap: 12px;
    }
    body[data-ui="v3"] .oc-root .cron-form-errors {
      display: none;
      margin-bottom: 12px;
      padding: 12px 14px;
      border-radius: var(--radius-md);
      border: 1px solid #fecaca;
      background: #fff1f2;
      color: #7f1d1d;
      font-size: 13px;
      line-height: 1.45;
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] .cron-form-errors {
      border-color: rgba(248, 113, 113, 0.35);
      background: rgba(127, 29, 29, 0.25);
      color: #fecaca;
    }
    body[data-ui="v3"] .oc-root .cron-form-errors__title { font-weight: 700; margin-bottom: 6px; }
    body[data-ui="v3"] .oc-root .cron-form-errors__intro { font-size: 12px; opacity: 0.92; margin-bottom: 8px; }
    body[data-ui="v3"] .oc-root .cron-form-errors__list { display: flex; flex-direction: column; gap: 4px; }
    body[data-ui="v3"] .oc-root .cron-form-error-link {
      color: inherit; text-decoration: underline; cursor: pointer; font-size: 12px;
    }
    body[data-ui="v3"] .oc-root .cron-form-errors-hint { font-size: 12px; flex: 1; min-width: 0; text-align: right; }
    body[data-ui="v3"] .oc-root .btn.primary:disabled {
      opacity: 0.45; cursor: not-allowed;
      filter: grayscale(0.15);
    }
    /* 定时任务：主按钮（添加任务 / 保存更改）— 红底白字、大圆角，对齐当前布局 */
    body[data-ui="v3"] .oc-root #cron-submit-btn.btn.primary {
      background: #e11d48;
      color: #fff;
      border: none;
      border-radius: 12px;
      padding: 10px 22px;
      font-weight: 600;
      box-shadow: none;
    }
    body[data-ui="v3"] .oc-root #cron-submit-btn.btn.primary:hover:not(:disabled) {
      background: #be123c;
      border-color: transparent;
    }
    body[data-ui="v3"] .oc-root #cron-submit-btn.btn.primary:disabled {
      background: #fda4af;
      color: rgba(255, 255, 255, 0.92);
      opacity: 1;
      filter: none;
      cursor: not-allowed;
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] #cron-submit-btn.btn.primary {
      background: #e11d48;
      color: #fff;
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] #cron-submit-btn.btn.primary:hover:not(:disabled) {
      background: #f43f5e;
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] #cron-submit-btn.btn.primary:disabled {
      background: #9f1239;
      color: rgba(255, 255, 255, 0.75);
    }
    body[data-ui="v3"] .oc-root .cron-form-footer-btns {
      display: inline-flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 10px;
    }
    body[data-ui="v3"] .oc-root #cron-form-footer-cancel.btn {
      background: var(--card);
      border: 1px solid var(--border);
      color: var(--text-strong);
      border-radius: 12px;
      padding: 10px 22px;
      font-weight: 600;
      box-shadow: none;
    }
    body[data-ui="v3"] .oc-root #cron-form-footer-cancel.btn:hover {
      background: var(--bg-hover);
      border-color: var(--border-strong);
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] #cron-form-footer-cancel.btn {
      background: var(--bg-elevated);
    }
    /* 定时任务列表：卡片布局（prompt + 底栏按钮，与当前布局一致） */
    body[data-ui="v3"] .oc-root .cron-task-list {
      margin-top: 12px;
      display: flex;
      flex-direction: column;
      gap: 12px;
      min-width: 0;
    }
    body[data-ui="v3"] .oc-root .cron-task-card {
      border-radius: var(--radius-md);
      padding: 14px 16px;
      min-width: 0;
      border: 1px solid color-mix(in srgb, var(--border) 85%, var(--muted) 15%);
      /* 整体使用与任务描述框一致的浅灰背景 */
      background: #f5f5f5;
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] .cron-task-card {
      background: color-mix(in srgb, var(--muted) 14%, var(--card));
      border-color: color-mix(in srgb, var(--border) 75%, var(--muted) 25%);
    }
    /* 选中态：仅改变描边颜色，背景保持不变；同一时间仅一条任务会带该类名 */
    body[data-ui="v3"] .oc-root .cron-task-card--selected {
      border-color: #dc2626;
      box-shadow: 0 0 0 1px rgba(220, 38, 38, 0.35);
    }
    body[data-ui="v3"] .oc-root .cron-task-card__head {
      display: flex;
      flex-wrap: wrap;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px 16px;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__title-block { min-width: 0; flex: 1 1 200px; }
    body[data-ui="v3"] .oc-root .cron-task-card__name {
      font-size: 15px;
      font-weight: 700;
      color: var(--text-strong);
      word-break: break-word;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__cron {
      margin-top: 4px;
      font-size: 12px;
      color: var(--muted);
      word-break: break-word;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__meta {
      display: flex;
      flex-wrap: wrap;
      gap: 10px 14px;
      justify-content: flex-end;
      flex: 0 1 auto;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__stat {
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      gap: 2px;
      min-width: 0;
    }
    body[data-ui="v3"] .oc-root .cron-task-stat__lbl {
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: var(--muted);
    }
    body[data-ui="v3"] .oc-root .cron-task-stat__mono { font-size: 12px; color: var(--text); }
    body[data-ui="v3"] .oc-root .cron-task-stat__val { font-size: 12px; font-weight: 600; }
    body[data-ui="v3"] .oc-root .cron-task-stat__val--ok { color: #15803d; }
    body[data-ui="v3"] .oc-root .cron-task-stat__val--bad { color: var(--danger); }
    body[data-ui="v3"] .oc-root .cron-task-stat__val--muted { color: var(--muted); }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] .cron-task-stat__val--ok { color: #86efac; }
    body[data-ui="v3"] .oc-root .cron-task-card__prompt {
      margin-top: 12px;
      padding: 10px 12px;
      border-radius: var(--radius-sm);
      /* 与外层卡片同色，仅保留轻微边框以形成内层块感 */
      background: #f5f5f5;
      border: 1px solid #e5e7eb;
      min-width: 0;
    }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] .cron-task-card__prompt {
      background: color-mix(in srgb, var(--muted) 14%, var(--card));
      border-color: color-mix(in srgb, var(--border) 75%, var(--muted) 25%);
    }
    body[data-ui="v3"] .oc-root .cron-task-card__prompt-label {
      font-size: 11px;
      font-weight: 700;
      color: var(--muted);
      margin-bottom: 6px;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__prompt-body {
      font-size: 13px;
      line-height: 1.5;
      color: var(--text);
      word-break: break-word;
      overflow-wrap: anywhere;
      white-space: pre-wrap;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__lasterr {
      margin-top: 8px;
      font-size: 11px;
      line-height: 1.4;
      word-break: break-word;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__footer {
      margin-top: 12px;
      padding-top: 12px;
      border-top: 1px solid var(--border);
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__badges {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 6px;
      min-width: 0;
    }
    body[data-ui="v3"] .oc-root .cron-pill {
      display: inline-block;
      padding: 2px 8px;
      font-size: 11px;
      font-weight: 600;
      border-radius: var(--radius-full);
      background: var(--bg-hover);
      color: var(--muted);
    }
    body[data-ui="v3"] .oc-root .cron-pill--ok {
      background: rgba(34, 197, 94, 0.15);
      color: #15803d;
    }
    body[data-ui="v3"] .oc-root .cron-pill--off {
      background: #fee2e2;
      color: #b91c1c;
    }
    body[data-ui="v3"] .oc-root .cron-pill--muted { opacity: 0.85; }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] .cron-pill--ok { color: #86efac; }
    body[data-ui="v3"] .oc-root[data-theme-mode="dark"] .cron-pill--off {
      background: rgba(127, 29, 29, 0.6);
      color: #fecaca;
    }
    body[data-ui="v3"] .oc-root .cron-task-card__actions {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 8px;
      max-width: 100%;
    }
    /* 方圆角（小圆角矩形），对齐当前定时任务操作条，非胶囊全圆角 */
    body[data-ui="v3"] .oc-root .cron-task-action {
      appearance: none;
      background: #ffffff;
      padding: 6px 14px;
      font-size: 12px;
      font-weight: 500;
      color: #111827;
      cursor: pointer;
      border-radius: 8px;
      font-family: inherit;
      border: 1px solid #dadce0;
    }
    body[data-ui="v3"] .oc-root .cron-task-action:hover:not(:disabled) {
      background: #f3f4f6;
    }
    body[data-ui="v3"] .oc-root .cron-task-action:disabled {
      opacity: 0.45;
      cursor: not-allowed;
    }
    body[data-ui="v3"] .oc-root .cron-task-action--danger {
      color: #b91c1c;
      border-color: rgba(220, 38, 38, 0.5);
      background: #fef2f2;
    }
    body[data-ui="v3"] .oc-root .cron-task-action--danger:hover:not(:disabled) {
      background: #fee2e2;
    }
    /* 启用 / 禁用按钮：启用为红描边，禁用为绿色实心 */
    body[data-ui="v3"] .oc-root .cron-task-action--toggle-on {
      color: #b91c1c;
      border-color: rgba(220, 38, 38, 0.55);
      background: #fef2f2;
    }
    body[data-ui="v3"] .oc-root .cron-task-action--toggle-on:hover:not(:disabled) {
      background: #fee2e2;
    }
    body[data-ui="v3"] .oc-root .cron-task-action--toggle-off {
      background: #16a34a;
      border-color: #16a34a;
      color: #fff;
    }
    body[data-ui="v3"] .oc-root .cron-task-action--toggle-off:hover:not(:disabled) {
      background: #15803d;
      border-color: #15803d;
    }
    body[data-ui="v3"] .oc-root .cron-task-action-sep {
      display: inline-block;
      width: 1px;
      height: 14px;
      margin: 0 2px;
      background: var(--border);
      align-self: center;
      flex-shrink: 0;
    }
    body[data-ui="v3"] .oc-root .cron-empty { padding: 24px; text-align: center; color: var(--muted); font-size: 13px; }
  </style>
"""

    let bodyHtml = """
  <div class="shell">
    <h1>Metis Dashboard</h1>
    <div id="root" class="muted">Loading...</div>
  </div>
"""

    let scriptPrefix = """
  let currentSession = '';
  let isSending = false;
  let historyFingerprint = '';
  let currentTab = 'chat';
  let uiVariant = 'v1';
  let skillsCache = [];
  let skillsCollapsed = { 'BUILT-IN SKILLS': false, 'EXTRA SKILLS': false, 'OTHER SKILLS': false };
  let v3SessionsPageSize = 20;
  let v3SessionsPageIndex = 0;
  let lastStatusData = null;
  let v3SessionsSelected = new Set();
  let v3SessionsFilterText = '';
  let v3CronFilterText = '';
  let v3CronEnableFilter = 'all';
  let v3CronScheduleFilter = 'all';
  let v3CronLastRunFilter = 'all';
  let v3CronSort = 'next';
  let v3CronSortDir = 'asc';
  let v3CronFormMode = 'create';
  let v3CronEditId = '';
  let v3CronCloneJob = null;
  let v3CronSelectedId = '';
  let v3CronRunScope = 'all';
  let v3CronRunSearch = '';
  let v3CronRunSort = 'newest';
  let v3CronRunStatusFilter = 'all';
  let v3CronRunDeliveryFilter = 'all';
  let v3SessionsActiveMin = '';
  let v3SessionsStatusLimit = (function() {
    try {
      var s = localStorage.getItem('cj_dashboard_sessions_limit');
      if (s && String(s).trim()) return String(s).trim();
    } catch (_e) {}
    return '120';
  })();

  let sessionsSourceFilter = 'all';
  let v3SessionOptionsHtml = '';
""" + gatewayBuildControlUiViewsScript() + """
""" + gatewayBuildControlUiCoreScript() + """

  // v3: 记录“用户在 UI 上删除的消息”，避免轮询/刷新时又出现
  let deletedMsgIds = new Set();

""" + gatewayBuildControlUiBootstrapScript(
    dashboardDeviceId,
    dashboardDeviceToken,
    dashboardAuthToken,
    dashboardAuthPassword,
    dashboardBasePath,
    binding.wsUrl
) + """

    """ + gatewayBuildControlUiLegacyShellsScript() + """
    """ + gatewayBuildControlUiCronScript() + """
    """ + gatewayBuildControlUiSessionsScript() + """
""" + gatewayBuildControlUiV3ChromeScript() + """
""" + gatewayBuildControlUiV3NavigationScript() + """
""" + gatewayBuildControlUiV3TemplatesScript() + """
""" + gatewayBuildControlUiV3PanelsScript() + """
""" + gatewayBuildControlUiV3InteractionsScript() + """
""" + gatewayBuildControlUiV3ShellScript() + """

"""

    let scriptBody = scriptPrefix + gatewayBuildControlUiAppScript()
    gatewayBuildControlUiPageHtml("Metis Dashboard", headExtra, bodyHtml, scriptBody)
}
