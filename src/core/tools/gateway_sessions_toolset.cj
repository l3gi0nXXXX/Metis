package metis.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.{gatewayCurrentToolRuntimeContext, gatewayMessagePayloadPreview, gatewaySubagentCreateRunRecord, gatewaySubagentEvaluateSpawnPolicy, gatewaySubagentFindRunBySessionKey, gatewaySubagentMarkRunCancelled, gatewaySubagentMarkRunFailed, gatewaySubagentMarkRunRunning, gatewaySubagentMarkRunState, gatewaySubagentMarkRunSucceeded, gatewaySubagentPolicyDecisionToJson, gatewaySubagentPolicyRejectionJson, gatewaySubagentResolveRunRecord, gatewaySubagentRunRecordInt, gatewaySubagentRunRecordString, gatewaySubagentWriteRunRecord, parseGatewayPollParts, renderGatewayAudioText, renderGatewayDeleteText, renderGatewayDocumentText, renderGatewayEditText, renderGatewayPhotoText, renderGatewayPinText, renderGatewayPollTextAdvanced, renderGatewayReactionText, renderGatewayTopicCreateText, renderGatewayTopicEditText, renderGatewayUnpinText, renderGatewayVideoNoteText, renderGatewayVideoText, renderGatewayVoiceText, resolveRuntimeToolPolicyFromRoot, runtimeSubagentBoundaryDecision, runtimeToolPolicyReportToJson}
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}
import metis.core.config.GatewayUserSettings
import metis.core.plan.Plan
import metis.gateway.config.mergeGatewayUserSettings
import metis.gateway.core.{AgentBridge, GatewaySessionStore, gatewaySessionStoreForUser}
import metis.cron.{CronJob, cronLoadOrEmpty, cronSave, cronStorePath}
import metis.gateway.runtime.{buildGatewayServiceFromUserSettings, gatewayExecuteCronWithUnifiedRun, gatewayHasAnyEnabledChannel, gatewayLaunchDedicatedConsole, gatewayExecuteStopServe, gatewayExecuteRestartServe, gatewayAnotherServeInstanceSeemsRunning, GatewayClient, gatewayBuildClient}
import metis.io.PrintUtils
import metis.utils.ShellUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.core.Duration
import std.fs.{exists, Path, Directory, File, OpenMode}
import std.io.*
import std.process.*
import std.sync.Mutex
import std.time.*

import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let managedSubagentLock = Mutex()
private var managedSubagentAgentIds = HashMap<String, String>()
private var managedSubagentStates = HashMap<String, String>()
private var managedSubagentFutures = HashMap<String, Future<Unit>>()
private var managedSubagentProcesses = HashMap<String, SubProcess>()

/**
 * 对齐参考实现的 Agent 侧网关会话工具：操作本地 `~/.metis/agents/<agentId>/sessions` 转录。
 * 说明：不经过 IM 渠道 API；sessionsSend 仅追加转录行。若 gateway serve 已加载该 sessionKey，需重启网关后内存与磁盘才一致。
 */
@toolset
public class GatewaySessionsToolset {
    private func gatewayToolClient(): GatewayClient {
        gatewayBuildClient("tool", "agent-tool")
    }

    private func gwStore(): GatewaySessionStore {
        gatewaySessionStoreForUser(CliSettingManager.readGatewaySettings())
    }

    private func stringArrayJson(values: Array<String>): JsonArray {
        let arr = JsonArray([])
        for (value in values) {
            arr.add(JsonString(value))
        }
        arr
    }

    private func runtimePolicyRootForSpawn(): JsonObject {
        let root = match (MetisConfigManager.rawConfig()) {
            case Some(raw) =>
                try { JsonValue.fromStr(raw.toJsonString()).asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let user = CliSettingManager.readGatewaySettings()
        let gatewayObj = match (root.get("gateway")) {
            case Some(value) =>
                try { value.asObject() } catch (_: Exception) { JsonObject() }
            case None => JsonObject()
        }
        let toolsObj = JsonObject()
        if (user.tools.allow.size > 0) {
            toolsObj.put("allow", this.stringArrayJson(user.tools.allow))
        }
        if (user.tools.deny.size > 0) {
            toolsObj.put("deny", this.stringArrayJson(user.tools.deny))
        }
        if (toolsObj.size() > 0) {
            gatewayObj.put("tools", toolsObj)
            root.put("gateway", gatewayObj)
        }
        root
    }

    private func subagentBoundaryInventory(settingsTools: Array<String>): Array<String> {
        let values = ArrayList<String>()
        for (name in ["fileRead", "listDirectory", "shellExecute", "sessions_spawn", "sessions_batch_delegate", "subagents"]) {
            values.add(name)
        }
        for (name in settingsTools) {
            let clean = name.trimAscii()
            if (!clean.isEmpty()) {
                values.add(clean)
            }
        }
        values.toArray()
    }

    private func normalizeSessionKinds(kinds: Option<Array<String>>): Array<String> {
        let normalized = ArrayList<String>()
        match (kinds) {
            case Some(items) =>
                for (item in items) {
                    let kind = item.trimAscii().toAsciiLower()
                    if (kind == "main" || kind == "group" || kind == "cron" || kind == "hook" || kind == "node" || kind == "other") {
                        var seen = false
                        for (existing in normalized) {
                            if (existing == kind) {
                                seen = true
                                break
                            }
                        }
                        if (!seen) {
                            normalized.add(kind)
                        }
                    }
                }
            case None => ()
        }
        normalized.toArray()
    }

    private func classifySessionKind(sessionKey: String): String {
        let normalized = sessionKey.trimAscii().toAsciiLower()
        if (normalized.isEmpty()) {
            return "other"
        }
        if (normalized.contains(":group:")) {
            return "group"
        }
        if (normalized.contains(":cron:") || normalized.startsWith("cron:")) {
            return "cron"
        }
        if (normalized.contains(":hook:") || normalized.startsWith("hook:")) {
            return "hook"
        }
        if (normalized.contains(":node:") || normalized.startsWith("node:")) {
            return "node"
        }
        if (normalized == "main" || normalized.endsWith(":main") || normalized.startsWith("main:")) {
            return "main"
        }
        return "other"
    }

    private func kindAllowed(kind: String, allowedKinds: Array<String>): Bool {
        if (allowedKinds.isEmpty()) {
            return true
        }
        for (value in allowedKinds) {
            if (value == kind) {
                return true
            }
        }
        return false
    }

    private func normalizeTranscriptRole(role: Option<String>): String {
        match (role) {
            case Some(x) =>
                let t = x.trimAscii().toAsciiLower()
                if (t == "user" || t == "assistant" || t == "system") {
                    t
                } else {
                    "assistant"
                }
            case None => "assistant"
        }
    }

    private func resolveSessionKeyByLabel(label: String, agentId: Option<String>): String {
        let normalizedLabel = label.trimAscii().toAsciiLower()
        if (normalizedLabel.isEmpty()) {
            return ""
        }
        let agentNeedle = match (agentId) {
            case Some(v) => v.trimAscii().toAsciiLower()
            case None => ""
        }
        for (sessionKey in this.gwStore().listSessionKeys()) {
            let keyLower = sessionKey.toAsciiLower()
            if (!keyLower.contains(":${normalizedLabel}:")) {
                continue
            }
            if (!agentNeedle.isEmpty() && !keyLower.contains(agentNeedle)) {
                continue
            }
            return sessionKey
        }
        return ""
    }

    private func buildSpawnLabel(label: String, runtime: String, agentId: String): String {
        let parts = ArrayList<String>()
        if (!runtime.isEmpty()) {
            parts.add(runtime)
        }
        if (!agentId.isEmpty()) {
            parts.add(agentId)
        }
        if (!label.isEmpty()) {
            parts.add(label)
        }
        if (parts.isEmpty()) {
            return ""
        }
        return String.join(parts.toArray(), delimiter: "-")
    }

    private func countOpenPlanTasks(plan: Plan): Int64 {
        let text = plan.toString().trimAscii()
        if (text.isEmpty()) {
            return 0
        }
        var count: Int64 = 0
        for (line in text.split("\n")) {
            let trimmed = line.trimAscii()
            if (trimmed.startsWith("- [ ] ")) {
                count += 1
            }
        }
        return count
    }

    private func buildGatewayStatusJson(user: GatewayUserSettings): JsonObject {
        let (fCfg, qCfg, tCfg) = mergeGatewayUserSettings(user)
        let result = JsonObject()
        result.put("enabled", user.enabled.toJsonValue())

        let session = JsonObject()
        session.put("dmScope", JsonString(user.session.dmScope))
        session.put("persistenceEnabled", user.session.persistenceEnabled.toJsonValue())
        result.put("session", session)

        let feishu = JsonObject()
        feishu.put("enabled", user.feishu.enabled.toJsonValue())
        feishu.put("appId", JsonString(user.feishu.appId))
        feishu.put("effectiveEnabled", fCfg.enabled.toJsonValue())
        result.put("feishu", feishu)

        let qq = JsonObject()
        qq.put("enabled", user.qq.enabled.toJsonValue())
        qq.put("mode", JsonString(user.qq.mode))
        qq.put("appId", JsonString(user.qq.appId))
        qq.put("effectiveEnabled", qCfg.enabled.toJsonValue())
        result.put("qq", qq)

        let plugins = JsonArray([])
        for (p in user.gatewayPlugins) {
            let row = JsonObject()
            row.put("id", JsonString(p.id))
            row.put("enabled", p.enabled.toJsonValue())
            plugins.add(row)
        }
        result.put("gatewayPlugins", plugins)
        result.put("hasAnyEnabledChannel", gatewayHasAnyEnabledChannel(user).toJsonValue())
        return result
    }

    private func gatewayConfigValueAtPath(user: GatewayUserSettings, path: String): Option<JsonValue> {
        let normalized = path.trimAscii().toAsciiLower()
        if (normalized.isEmpty() || normalized == "gateway") {
            return Some(user.toJsonValue())
        }
        match (normalized) {
            case "enabled" | "gateway.enabled" => Some(user.enabled.toJsonValue())
            case "session" | "gateway.session" => Some(user.session.toJsonValue())
            case "session.dmscope" | "gateway.session.dmscope" => Some(JsonString(user.session.dmScope))
            case "session.persistenceenabled" | "gateway.session.persistenceenabled" => Some(user.session.persistenceEnabled.toJsonValue())
            case "feishu" | "gateway.feishu" => Some(user.feishu.toJsonValue())
            case "feishu.enabled" | "gateway.feishu.enabled" => Some(user.feishu.enabled.toJsonValue())
            case "feishu.appid" | "gateway.feishu.appid" => Some(JsonString(user.feishu.appId))
            case "feishu.receivemode" | "gateway.feishu.receivemode" => Some(JsonString(user.feishu.receiveMode))
            case "qq" | "gateway.qq" => Some(user.qq.toJsonValue())
            case "qq.enabled" | "gateway.qq.enabled" => Some(user.qq.enabled.toJsonValue())
            case "qq.mode" | "gateway.qq.mode" => Some(JsonString(user.qq.mode))
            case "qq.appid" | "gateway.qq.appid" => Some(JsonString(user.qq.appId))
            case "telegram" | "gateway.telegram" => Some(user.telegram.toJsonValue())
            case "telegram.enabled" | "gateway.telegram.enabled" => Some(user.telegram.enabled.toJsonValue())
            case "telegram.bottoken" | "gateway.telegram.bottoken" => Some(JsonString(user.telegram.botToken))
            case "telegram.webhookurl" | "gateway.telegram.webhookurl" => Some(JsonString(user.telegram.webhookUrl))
            case "tools" | "gateway.tools" => Some(user.tools.toJsonValue())
            case "tools.allow" | "gateway.tools.allow" => Some(user.tools.allow.toJsonValue())
            case "tools.deny" | "gateway.tools.deny" => Some(user.tools.deny.toJsonValue())
            case "gatewayplugins" | "gateway.gatewayplugins" => Some(user.gatewayPlugins.toJsonValue())
            case "channelmodels" | "gateway.channelmodels" => Some(user.channelModels.toJsonValue())
            case "channelsextra" | "gateway.channelsextra" =>
                match (user.channelsExtra) {
                    case Some(v) => Some(v)
                    case None => Some(JsonObject())
                }
            case _ => None
        }
    }

    private func gatewaySchemaLookup(path: String): String {
        let normalized = path.trimAscii().toAsciiLower()
        match (normalized) {
            case "" | "gateway" =>
                "gateway: root object. Keys: enabled, session, feishu, qq, telegram, channelModels, tools, gatewayPlugins, channelsExtra."
            case "enabled" | "gateway.enabled" =>
                "gateway.enabled: Bool. Master switch for the gateway runtime."
            case "session" | "gateway.session" =>
                "gateway.session: object. Keys: dmScope (String), persistenceEnabled (Bool)."
            case "session.dmscope" | "gateway.session.dmscope" =>
                "gateway.session.dmScope: String. Supported values: per-chat, main, per-peer, per-channel-peer."
            case "session.persistenceenabled" | "gateway.session.persistenceenabled" =>
                "gateway.session.persistenceEnabled: Bool. Controls whether gateway transcripts persist under ~/.metis/agents/<agentId>/sessions (gateway.session.agentId, default main)."
            case "feishu" | "gateway.feishu" =>
                "gateway.feishu: object. Common keys: enabled, appId, appSecret, receiveMode, domain, botOpenId, webhookHost, webhookPort, webhookPath, verificationToken, encryptKey, groupSessionScope, replyInThread."
            case "qq" | "gateway.qq" =>
                "gateway.qq: object. Common keys: enabled, mode, appId, appSecret, officialIntents, officialTokenUrl, officialGatewayUrl, officialWebsocketUrl."
            case "telegram" | "gateway.telegram" =>
                "gateway.telegram: object. Common keys: enabled, botToken, tokenFile, dmPolicy, allowFrom, groupPolicy, groupAllowFrom, groups, groupHistoryEnabled, groupHistoryLimit, replyToMode, textChunkLimit, streaming, webhookUrl, webhookSecret, webhookPath, webhookHost, webhookPort, apiRoot, proxy, actions, media, network, threadBindings."
            case "channelmodels" | "gateway.channelmodels" =>
                "gateway.channelModels: map<string,string>. Per-channel primary model binding, e.g. feishu -> provider:model."
            case "tools" | "gateway.tools" =>
                "gateway.tools: object. Keys: allow, deny. deny has priority; allow empty means allow all built-in gateway tools."
            case "gatewayplugins" | "gateway.gatewayplugins" =>
                "gateway.gatewayPlugins: array<object>. Each item has id and enabled."
            case "channelsextra" | "gateway.channelsextra" =>
                "gateway.channelsExtra: arbitrary JSON object for plugin-specific channel config."
            case _ =>
                "Unknown gateway config path: ${path.trimAscii()}"
        }
    }

    private func normalizeCronAction(action: String): String {
        let act = action.trimAscii().toAsciiLower()
        if (act.isEmpty()) {
            return ""
        }
        return act
    }

    private func findCronJob(path: Path, jobId: String): Option<CronJob> {
        let target = jobId.trimAscii()
        if (target.isEmpty()) {
            return None
        }
        for (j in cronLoadOrEmpty(path)) {
            if (j.id.trimAscii() == target) {
                return Some(j)
            }
        }
        None
    }

    private func saveCronJob(path: Path, job: CronJob): Unit {
        let list = ArrayList<CronJob>()
        var replaced = false
        for (j in cronLoadOrEmpty(path)) {
            if (j.id.trimAscii() == job.id.trimAscii()) {
                list.add(job)
                replaced = true
            } else {
                list.add(j)
            }
        }
        if (!replaced) {
            list.add(job)
        }
        cronSave(path, list.toArray())
    }

    private func parseCronBoolWord(raw: String): Option<Bool> {
        let t = raw.trimAscii().toAsciiLower()
        if (t == "true" || t == "1" || t == "yes" || t == "on") {
            return Some(true)
        }
        if (t == "false" || t == "0" || t == "no" || t == "off") {
            return Some(false)
        }
        None
    }

    private func sendGatewayText(channel: String, target: String, message: String, replyToMessageId!: Option<String> = None): Bool {
        let user = CliSettingManager.readGatewaySettings()
        let (gateway, _feishu) = buildGatewayServiceFromUserSettings(user)
        gateway.sendTextToPeer(channel, target, message, replyToMessageId: replyToMessageId)
        return true
    }

    private func isManagedSpawnSession(sessionKey: String): Bool {
        match (this.gwStore().readTranscriptRaw(sessionKey)) {
            case Some(raw) => raw.contains("sessions_spawn metadata:")
            case None => false
        }
    }

    private func listManagedSpawnSessions(): Array<String> {
        let managed = ArrayList<String>()
        for (sessionKey in this.gwStore().listSessionKeys()) {
            if (this.isManagedSpawnSession(sessionKey)) {
                managed.add(sessionKey)
            }
        }
        managed.toArray()
    }

    private func resolveManagedSpawnTarget(target: String): String {
        let trimmed = target.trimAscii()
        if (trimmed.isEmpty()) {
            return ""
        }
        for (sessionKey in this.listManagedSpawnSessions()) {
            if (sessionKey == trimmed || sessionKey.toAsciiLower().contains(trimmed.toAsciiLower())) {
                return sessionKey
            }
        }
        return ""
    }

    private func normalizeManagedAgentId(agentId: String): String {
        let normalized = agentId.trimAscii().toAsciiLower().replace("-", "_")
        if (normalized.isEmpty()) {
            return "explorer"
        }
        if (normalized == "explorer" || normalized == "exploreragent") {
            return "explorer"
        }
        if (normalized == "editor" || normalized == "edit" || normalized == "editoragent") {
            return "editor"
        }
        if (normalized == "reviewer" || normalized == "review" || normalized == "revieweragent") {
            return "reviewer"
        }
        if (normalized == "test_generator" || normalized == "testgenerator" || normalized == "testgeneratoragent") {
            return "test_generator"
        }
        if (normalized == "refactoring" || normalized == "refactor" || normalized == "refactoringagent") {
            return "refactoring"
        }
        if (normalized == "planner" || normalized == "planneragent") {
            return "planner"
        }
        return normalized
    }

    private func supportsRealManagedSubagent(agentId: String): Bool {
        let normalized = this.normalizeManagedAgentId(agentId)
        normalized == "explorer" ||
            normalized == "editor" ||
            normalized == "reviewer" ||
            normalized == "test_generator" ||
            normalized == "refactoring" ||
            normalized == "planner"
    }

    private func extractManagedSpawnMetadataField(sessionKey: String, field: String): String {
        match (this.gwStore().readTranscriptRaw(sessionKey)) {
            case Some(raw) =>
                let needle = "${field}="
                if (let Some(start) <- raw.indexOf(needle)) {
                    let from = start + needle.size
                    let rest = raw[from..]
                    var end = rest.size
                    match (rest.indexOf(",")) {
                        case Some(v) => end = min(end, v)
                        case None => ()
                    }
                    match (rest.indexOf("\"")) {
                        case Some(v) => end = min(end, v)
                        case None => ()
                    }
                    match (rest.indexOf("\n")) {
                        case Some(v) => end = min(end, v)
                        case None => ()
                    }
                    return rest[0..end].trimAscii()
                }
                return ""
            case None => return ""
        }
    }

    private func managedSubagentAgentId(sessionKey: String): String {
        synchronized(managedSubagentLock) {
            if (let Some(v) <- managedSubagentAgentIds.get(sessionKey)) {
                return v
            }
        }
        return this.normalizeManagedAgentId(this.extractManagedSpawnMetadataField(sessionKey, "agentId"))
    }

    private func managedSubagentRuntime(sessionKey: String): String {
        let runtime = this.extractManagedSpawnMetadataField(sessionKey, "runtime").trimAscii().toAsciiLower()
        if (runtime.isEmpty()) {
            return "subagent"
        }
        return runtime
    }

    private func managedSubagentCwd(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "cwd")
    }

    private func managedSpawnModel(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "model")
    }

    private func managedSpawnThinking(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "thinking")
    }

    private func managedSpawnResumeSessionId(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "resumeSessionId")
    }

    private func managedSpawnMode(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "mode")
    }

    private func managedSpawnCleanup(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "cleanup")
    }

    private func managedSpawnSandbox(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "sandbox")
    }

    private func managedSpawnStreamTo(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "streamTo")
    }

    private func managedSpawnThread(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "thread")
    }

    private func managedSpawnTimeoutSeconds(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "timeoutSeconds")
    }

    private func acpEffectiveMode(mode: String): String {
        if (mode.trimAscii().toAsciiLower() == "session") { "session" } else { "run" }
    }

    private func acpEffectiveSandbox(sandbox: String): String {
        match (sandbox.trimAscii().toAsciiLower()) {
            case "danger" | "danger-full-access" => "danger-full-access"
            case "require" | "read-only" => "read-only"
            case _ => "workspace-write"
        }
    }

    private func acpEffectiveSessionPersistence(mode: String, thread: Bool): String {
        if (this.acpEffectiveMode(mode) == "session" || thread) { "persistent" } else { "ephemeral" }
    }

    private func managedSubagentState(sessionKey: String): String {
        synchronized(managedSubagentLock) {
            if (let Some(v) <- managedSubagentStates.get(sessionKey)) {
                return v
            }
        }
        return ""
    }

    private func managedSubagentHasLiveFuture(sessionKey: String): Bool {
        synchronized(managedSubagentLock) {
            managedSubagentFutures.contains(sessionKey)
        }
    }

    private func setManagedSubagentState(
        sessionKey: String,
        state: String,
        resultSummary!: String = "",
        error!: String = "",
        exitCode!: Int64 = 0
    ): Unit {
        synchronized(managedSubagentLock) {
            managedSubagentStates.add(sessionKey, state)
        }
        let _ = gatewaySubagentMarkRunState(
            this.gwStore().sessionsRoot(),
            sessionKey,
            state,
            resultSummary: resultSummary,
            error: error,
            exitCode: exitCode
        )
    }

    private func tryQueueManagedSubagent(sessionKey: String, agentId: String): Bool {
        let queued = synchronized(managedSubagentLock) {
            if (let Some(state) <- managedSubagentStates.get(sessionKey)) {
                if (state == "queued" || state == "running") {
                    return false
                }
            }
            managedSubagentAgentIds.add(sessionKey, agentId)
            managedSubagentStates.add(sessionKey, "queued")
            true
        }
        if (queued) {
            let _ = gatewaySubagentMarkRunState(this.gwStore().sessionsRoot(), sessionKey, "queued")
        }
        queued
    }

    private func forgetManagedSubagent(sessionKey: String): Unit {
        synchronized(managedSubagentLock) {
            managedSubagentAgentIds.remove(sessionKey)
            managedSubagentStates.remove(sessionKey)
            managedSubagentFutures.remove(sessionKey)
            managedSubagentProcesses.remove(sessionKey)
        }
    }

    private func setManagedSubagentFuture(sessionKey: String, future: Future<Unit>): Unit {
        synchronized(managedSubagentLock) {
            managedSubagentFutures.add(sessionKey, future)
        }
    }

    private func clearManagedSubagentFuture(sessionKey: String): Unit {
        synchronized(managedSubagentLock) {
            managedSubagentFutures.remove(sessionKey)
        }
    }

    private func setManagedSubagentProcess(sessionKey: String, process: SubProcess): Unit {
        synchronized(managedSubagentLock) {
            managedSubagentProcesses.add(sessionKey, process)
        }
    }

    private func clearManagedSubagentProcess(sessionKey: String): Unit {
        synchronized(managedSubagentLock) {
            managedSubagentProcesses.remove(sessionKey)
        }
    }

    private func managedSubagentHasLiveProcess(sessionKey: String): Bool {
        synchronized(managedSubagentLock) {
            managedSubagentProcesses.contains(sessionKey)
        }
    }

    private func managedSubagentKillSnapshot(sessionKey: String): (String, Bool, Bool) {
        synchronized(managedSubagentLock) {
            let state = match (managedSubagentStates.get(sessionKey)) {
                case Some(v) => v
                case None => ""
            }
            let hasFuture = managedSubagentFutures.contains(sessionKey)
            let hasProcess = managedSubagentProcesses.contains(sessionKey)
            (state, hasFuture, hasProcess)
        }
    }

    private func postManagedOutput(streamTo: String, sessionKey: String, role: String, text: String): Unit {
        let payload = text.trimAscii()
        if (payload.isEmpty()) {
            return
        }
        let target = streamTo.trimAscii()
        if (target.isEmpty()) {
            return
        }
        if (target.startsWith("session:")) {
            let otherSession = target["session:".size..].trimAscii()
            if (!otherSession.isEmpty()) {
                this.gwStore().appendTranscriptEntry(otherSession, role, payload)
            }
            return
        }
        let raw = if (target.startsWith("gateway:")) {
            target["gateway:".size..]
        } else {
            target
        }
        if (let Some(pivot) <- raw.indexOf(":")) {
            let channel = raw[0..pivot].trimAscii().toAsciiLower()
            let peer = raw[pivot + 1..].trimAscii()
            if (!channel.isEmpty() && !peer.isEmpty()) {
                let body = "[${sessionKey}] ${payload}"
                let _ = this.sendGatewayText(channel, peer, body)
            }
        }
    }

    private func shouldDeleteManagedSessionAfterRun(sessionKey: String): Bool {
        this.managedSpawnCleanup(sessionKey).trimAscii().toAsciiLower() == "delete"
    }

    private func maybeDeleteManagedSessionAfterRun(sessionKey: String): Unit {
        if (this.shouldDeleteManagedSessionAfterRun(sessionKey)) {
            let _ = this.gwStore().deleteSession(sessionKey)
            this.forgetManagedSubagent(sessionKey)
        }
    }

    private func cancelManagedSubagent(sessionKey: String): Bool {
        synchronized(managedSubagentLock) {
            var cancelled = false
            if (let Some(process) <- managedSubagentProcesses.get(sessionKey)) {
                try {
                    process.terminate(force: true)
                    cancelled = true
                } catch (_: Exception) {
                }
            }
            if (let Some(future) <- managedSubagentFutures.get(sessionKey)) {
                future.cancel()
                managedSubagentStates.add(sessionKey, "cancelling")
                let _ = gatewaySubagentMarkRunCancelled(this.gwStore().sessionsRoot(), sessionKey, reason: "cancel requested")
                return true
            }
            if (cancelled) {
                managedSubagentStates.add(sessionKey, "cancelling")
                let _ = gatewaySubagentMarkRunCancelled(this.gwStore().sessionsRoot(), sessionKey, reason: "process terminated")
            }
            return cancelled
        }
    }

    private func markManagedSessionKillRequested(sessionKey: String, target: String): Unit {
        let transcriptPath = this.gwStore().transcriptPath(sessionKey)
        if (exists(transcriptPath)) {
            this.gwStore().appendTranscriptEntry(
                sessionKey,
                "system",
                "subagent kill requested by subagents tool: target=${target.trimAscii()}"
            )
        }
    }

    private func buildManagedSubagentPrompt(task: String, cwdHint: String, sessionKey: String, agentId: String): String {
        let effectiveCwd = if (cwdHint.trimAscii().isEmpty()) {
            CliConfig.cwd.toString()
        } else {
            cwdHint.trimAscii()
        }
        let normalized = this.normalizeManagedAgentId(agentId)
        let roleInstruction = match (normalized) {
            case "editor" => "Subagent role: editor. Make precise code changes and focus on concrete edits."
            case "reviewer" => "Subagent role: reviewer. Focus on bugs, risks, regressions, and validation."
            case "test_generator" => "Subagent role: test_generator. Focus on creating or improving tests."
            case "refactoring" => "Subagent role: refactoring. Focus on structural cleanup without changing behavior."
            case "planner" => "Subagent role: planner. Focus on breaking the task into a concrete plan."
            case _ => "Subagent role: explorer. Focus on exploring the codebase and reporting findings."
        }
        return "${roleInstruction}\nProject path: ${effectiveCwd}\nSession key: ${sessionKey}\n\nTask:\n${task.trimAscii()}"
    }

    private func acpCommandSpec(
        agentId: String,
        task: String,
        cwdHint: String,
        model: Option<String>,
        thinking: Option<String>,
        resumeSessionId: Option<String>,
        mode: String,
        sandbox: String,
        thread: Bool
    ): (Array<String>, Bool, String) {
        let normalized = agentId.trimAscii().toAsciiLower()
        let trimmedTask = task.trimAscii()
        let effectiveCwd = if (cwdHint.trimAscii().isEmpty()) {
            CliConfig.cwd.toString()
        } else {
            cwdHint.trimAscii()
        }
        let modelText = match (model) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let thinkingText = match (thinking) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let resumeText = match (resumeSessionId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let normalizedMode = if (mode.trimAscii().toAsciiLower() == "session") { "session" } else { "run" }
        let normalizedSandbox = match (sandbox.trimAscii().toAsciiLower()) {
            case "danger" | "danger-full-access" => "danger-full-access"
            case "require" | "read-only" => "read-only"
            case _ => "workspace-write"
        }
        let args = ArrayList<String>()
        if (normalized.isEmpty() || normalized == "codex" || normalized == "codex-cli") {
            args.add("codex")
            args.add("exec")
            if (!modelText.isEmpty()) {
                args.add("--model")
                args.add(modelText)
            }
            if (!thinkingText.isEmpty()) {
                args.add("--reasoning-effort")
                args.add(thinkingText)
            }
            args.add("--cd")
            args.add(effectiveCwd)
            args.add("--sandbox")
            args.add(normalizedSandbox)
            if (normalizedMode != "session" && !thread) {
                args.add("--ephemeral")
            }
            if (!resumeText.isEmpty()) {
                args.add("resume")
                args.add(resumeText)
                args.add(trimmedTask)
            } else {
                args.add(trimmedTask)
            }
            return (args.toArray(), false, "codex")
        }
        if (normalized == "claude" || normalized == "claude-code") {
            args.add("claude")
            args.add("-p")
            args.add("--output-format")
            args.add("text")
            if (!modelText.isEmpty()) {
                args.add("--model")
                args.add(modelText)
            }
            if (!effectiveCwd.isEmpty()) {
                args.add("--add-dir")
                args.add(effectiveCwd)
            }
            if (normalizedSandbox == "read-only") {
                args.add("--permission-mode")
                args.add("plan")
            } else if (normalizedSandbox == "danger-full-access") {
                args.add("--dangerously-skip-permissions")
            }
            if (normalizedMode != "session" && !thread) {
                args.add("--no-session-persistence")
            }
            if (!resumeText.isEmpty()) {
                args.add("--resume")
                args.add(resumeText)
            }
            args.add(trimmedTask)
            return (args.toArray(), false, "claude")
        }
        if (normalized == "gemini" || normalized == "gemini-cli") {
            args.add("gemini")
            if (!modelText.isEmpty()) {
                args.add("--model")
                args.add(modelText)
            }
            args.add("-p")
            args.add(trimmedTask)
            return (args.toArray(), false, "gemini")
        }
        if (normalized == "cursor" || normalized == "cursor-agent" || normalized == "cursor_cli") {
            args.add("cursor-agent")
            args.add("--print")
            args.add("--output-format")
            args.add("text")
            args.add("--workspace")
            args.add(effectiveCwd)
            if (!modelText.isEmpty()) {
                args.add("--model")
                args.add(modelText)
            }
            if (!resumeText.isEmpty()) {
                args.add("--resume")
                args.add(resumeText)
            }
            args.add("--sandbox")
            args.add(if (normalizedSandbox == "danger-full-access") { "disabled" } else { "enabled" })
            args.add(trimmedTask)
            return (args.toArray(), false, "cursor-agent")
        }
        if (normalized.startsWith("cmd:")) {
            let cmdline = normalized["cmd:".size..].trimAscii()
            return ([cmdline.replace("{task}", trimmedTask)], true, "custom-cmd")
        }
        if (agentId.trimAscii().contains(" ")) {
            return ([agentId.trimAscii().replace("{task}", trimmedTask)], true, "custom-shell")
        }
        args.add(agentId.trimAscii())
        args.add(trimmedTask)
        return (args.toArray(), false, agentId.trimAscii())
    }

    private func internalSubagentPromptFile(sessionKey: String, task: String): Path {
        let dir = CliConfig.dotDir.join("gateway-subagent-prompts")
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        let safeName = sessionKey.replace(":", "_")
        let path = dir.join("${safeName}.txt")
        try (file = File(path, OpenMode.Write)) {
            file.write(task.toArray())
        }
        return path
    }

    private func internalSubagentCommandSpec(
        sessionKey: String,
        agentId: String,
        task: String,
        cwdHint: String
    ): (String, Array<String>, Path) {
        let effectiveCwd = if (cwdHint.trimAscii().isEmpty()) { CliConfig.cwd } else { Path(cwdHint.trimAscii()) }
        let promptFile = this.internalSubagentPromptFile(sessionKey, task)
        let args = ArrayList<String>()
        args.add("run")
        args.add("--skip-build")
        args.add("--name")
        args.add("metis")
        let runArgs = ArrayList<String>()
        runArgs.add("--internal-subagent")
        runArgs.add(agentId)
        runArgs.add("--prompt-file")
        runArgs.add(promptFile.toString())
        runArgs.add("--output-format")
        runArgs.add("plain")
        if (!CliConfig.language.trimAscii().isEmpty()) {
            runArgs.add("--language")
            runArgs.add(CliConfig.language)
        }
        if (!CliConfig.model.trimAscii().isEmpty()) {
            runArgs.add("--model")
            runArgs.add(CliConfig.model)
        }
        args.add("--run-args")
        args.add(String.join(runArgs.toArray(), delimiter: " "))
        return ("cjpm", args.toArray(), effectiveCwd)
    }

    private func launchManagedAcpRun(
        sessionKey: String,
        harnessId: String,
        task: String,
        cwdHint: String,
        model: Option<String>,
        thinking: Option<String>,
        resumeSessionId: Option<String>,
        runTimeoutSeconds: Int64,
        streamTo: String,
        mode: String,
        sandbox: String,
        thread: Bool
    ): Bool {
        let normalizedHarness = if (harnessId.trimAscii().isEmpty()) { "codex" } else { harnessId.trimAscii() }
        if (!this.tryQueueManagedSubagent(sessionKey, "acp:${normalizedHarness}")) {
            return false
        }
        let spec = this.acpCommandSpec(normalizedHarness, task, cwdHint, model, thinking, resumeSessionId, mode, sandbox, thread)
        let command = spec[0]
        let withWrap = spec[1]
        let resolvedHarness = spec[2]
        let effectiveCwd = if (cwdHint.trimAscii().isEmpty()) { CliConfig.cwd } else { Path(cwdHint.trimAscii()) }
        let effectiveMode = this.acpEffectiveMode(mode)
        let effectiveSandbox = this.acpEffectiveSandbox(sandbox)
        let effectiveSessionPersistence = this.acpEffectiveSessionPersistence(mode, thread)
        let timeout: Option<Duration> = if (runTimeoutSeconds > 0) {
            Some(Duration.second * runTimeoutSeconds)
        } else {
            None<Duration>
        }
        let st = this.gwStore()
        st.appendTranscriptEntry(
            sessionKey,
            "system",
            "acp dispatch accepted: harness=${resolvedHarness}, mode=${effectiveMode}, sandbox=${effectiveSandbox}, sessionPersistence=${effectiveSessionPersistence}"
        )
        let future = spawn {
            let _ = gatewaySubagentMarkRunRunning(st.sessionsRoot(), sessionKey)
            this.setManagedSubagentState(sessionKey, "running")
            st.appendTranscriptEntry(
                sessionKey,
                "system",
                "acp started: harness=${resolvedHarness}, mode=${effectiveMode}, sandbox=${effectiveSandbox}, sessionPersistence=${effectiveSessionPersistence}"
            )
            try {
                let process = launch(
                    if (withWrap) { "sh" } else { command[0] },
                    if (withWrap) { ["-c", String.join(command, delimiter: " ")] } else { if (command.size > 1) { command[1..] } else { [] } },
                    stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe,
                    workingDirectory: Some(effectiveCwd)
                )
                this.setManagedSubagentProcess(sessionKey, process)
                let stdoutFuture = spawn {
                    let reader = StringReader(process.stdOutPipe)
                    try { reader.readToEnd() } catch (_: Exception) { "" }
                }
                let stderrFuture = spawn {
                    let reader = StringReader(process.stdErrPipe)
                    try { reader.readToEnd() } catch (_: Exception) { "" }
                }
                var exitCode: Int64 = 0
                var timedOut = false
                try {
                    exitCode = process.wait(timeout: timeout)
                } catch (_timeout: TimeoutException) {
                    timedOut = true
                    try { process.terminate(force: true) } catch (_terminateErr: Exception) { () }
                }
                let stdout = try { stdoutFuture.get() } catch (_: Exception) { "" }
                let stderr = try { stderrFuture.get() } catch (_: Exception) { "" }
                if (!stdout.trimAscii().isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "assistant", stdout.trimAscii())
                    this.postManagedOutput(streamTo, sessionKey, "assistant", stdout)
                }
                if (!stderr.trimAscii().isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp stderr: ${stderr.trimAscii()}")
                    this.postManagedOutput(streamTo, sessionKey, "system", "acp stderr: ${stderr.trimAscii()}")
                }
                if (timedOut) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp timed out: harness=${resolvedHarness} timeoutSeconds=${runTimeoutSeconds}")
                    this.setManagedSubagentState(sessionKey, "timed_out", error: "subagent timed out after ${runTimeoutSeconds}s", exitCode: -1)
                } else if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp cancelled")
                    this.setManagedSubagentState(sessionKey, "cancelled", error: "cancelled")
                } else if (exitCode == 0) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp completed: harness=${resolvedHarness} exitCode=${exitCode}")
                    this.setManagedSubagentState(sessionKey, "succeeded", resultSummary: if (stdout.trimAscii().isEmpty()) { "acp completed" } else { stdout.trimAscii() }, exitCode: exitCode)
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "acp failed: harness=${resolvedHarness} exitCode=${exitCode}")
                    this.setManagedSubagentState(sessionKey, "failed", error: "acp failed: harness=${resolvedHarness} exitCode=${exitCode}", exitCode: exitCode)
                }
            } catch (e: Exception) {
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp cancelled")
                    this.setManagedSubagentState(sessionKey, "cancelled", error: "cancelled")
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "acp failed: ${e.message}")
                    this.setManagedSubagentState(sessionKey, "failed", error: "acp failed: ${e.message}", exitCode: 1)
                }
            } finally {
                this.clearManagedSubagentProcess(sessionKey)
                this.clearManagedSubagentFuture(sessionKey)
                this.maybeDeleteManagedSessionAfterRun(sessionKey)
            }
        }
        this.setManagedSubagentFuture(sessionKey, future)
        return true
    }

    private func launchManagedSubagentRun(
        sessionKey: String,
        agentId: String,
        task: String,
        cwdHint: String,
        runTimeoutSeconds!: Int64 = -1
    ): Bool {
        let normalized = this.normalizeManagedAgentId(agentId)
        if (!this.supportsRealManagedSubagent(normalized)) {
            return false
        }
        if (!this.tryQueueManagedSubagent(sessionKey, normalized)) {
            return false
        }
        let prompt = this.buildManagedSubagentPrompt(task, cwdHint, sessionKey, normalized)
        let st = this.gwStore()
        st.appendTranscriptEntry(sessionKey, "system", "subagent dispatch accepted: agentId=${normalized}")
        let future = spawn {
            this.setManagedSubagentState(sessionKey, "running")
            st.appendTranscriptEntry(sessionKey, "system", "subagent started: agentId=${normalized}")
            try {
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent cancelled before start")
                    this.setManagedSubagentState(sessionKey, "cancelled")
                    return
                }
                let (cmd, args, workDir) = this.internalSubagentCommandSpec(sessionKey, normalized, prompt, cwdHint)
                let process = launch(
                    cmd,
                    args,
                    stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe,
                    workingDirectory: Some(workDir)
                )
                this.setManagedSubagentProcess(sessionKey, process)
                let timeout: Option<Duration> = if (runTimeoutSeconds > 0) {
                    Some(Duration.second * runTimeoutSeconds)
                } else {
                    None<Duration>
                }
                let stdoutFuture = spawn {
                    let reader = StringReader(process.stdOutPipe)
                    try { reader.readToEnd() } catch (_: Exception) { "" }
                }
                let stderrFuture = spawn {
                    let reader = StringReader(process.stdErrPipe)
                    try { reader.readToEnd() } catch (_: Exception) { "" }
                }
                var exitCode: Int64 = 0
                var timedOut = false
                try {
                    exitCode = process.wait(timeout: timeout)
                } catch (_timeout: TimeoutException) {
                    timedOut = true
                    try { process.terminate(force: true) } catch (_terminateErr: Exception) { () }
                }
                let content = (try { stdoutFuture.get() } catch (_: Exception) { "" }).trimAscii()
                let stderr = (try { stderrFuture.get() } catch (_: Exception) { "" }).trimAscii()
                if (timedOut) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent timed out: agentId=${normalized} timeoutSeconds=${runTimeoutSeconds}")
                    this.setManagedSubagentState(sessionKey, "timed_out", error: "subagent timed out after ${runTimeoutSeconds}s", exitCode: -1)
                    return
                }
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent cancelled")
                    this.setManagedSubagentState(sessionKey, "cancelled", error: "cancelled")
                    return
                }
                if (!stderr.isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent stderr: ${stderr}")
                    this.postManagedOutput(this.managedSpawnStreamTo(sessionKey), sessionKey, "system", "subagent stderr: ${stderr}")
                }
                if (exitCode == 0 && !content.isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "assistant", content)
                    this.postManagedOutput(this.managedSpawnStreamTo(sessionKey), sessionKey, "assistant", content)
                    st.appendTranscriptEntry(sessionKey, "system", "subagent completed: agentId=${normalized}")
                    this.setManagedSubagentState(sessionKey, "succeeded", resultSummary: content, exitCode: exitCode)
                } else if (exitCode == 0) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent completed with empty response")
                    this.setManagedSubagentState(sessionKey, "succeeded", resultSummary: "subagent completed with empty response", exitCode: exitCode)
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent failed: agentId=${normalized} exitCode=${exitCode}")
                    this.setManagedSubagentState(sessionKey, "failed", error: "subagent failed: agentId=${normalized} exitCode=${exitCode}", exitCode: exitCode)
                }
            } catch (e: Exception) {
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent cancelled")
                    this.setManagedSubagentState(sessionKey, "cancelled", error: "cancelled")
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent failed: ${e.message}")
                    this.setManagedSubagentState(sessionKey, "failed", error: "subagent failed: ${e.message}", exitCode: 1)
                }
            } finally {
                this.clearManagedSubagentProcess(sessionKey)
                this.clearManagedSubagentFuture(sessionKey)
                this.maybeDeleteManagedSessionAfterRun(sessionKey)
            }
        }
        this.setManagedSubagentFuture(sessionKey, future)
        return true
    }

    private func launchManagedSessionTurn(sessionKey: String, task: String): Bool {
        let runtime = this.managedSubagentRuntime(sessionKey)
        let cwdHint = this.managedSubagentCwd(sessionKey)
        if (runtime == "acp") {
            let harnessId = this.managedSubagentAgentId(sessionKey)
            let modelText = this.managedSpawnModel(sessionKey)
            let thinkingText = this.managedSpawnThinking(sessionKey)
            let resumeText = this.managedSpawnResumeSessionId(sessionKey)
            return this.launchManagedAcpRun(
                sessionKey,
                if (harnessId.isEmpty()) { "codex" } else { harnessId },
                task,
                cwdHint,
                if (modelText.isEmpty()) { None } else { Some(modelText) },
                if (thinkingText.isEmpty()) { None } else { Some(thinkingText) },
                if (resumeText.isEmpty()) { None } else { Some(resumeText) },
                -1,
                this.managedSpawnStreamTo(sessionKey),
                this.managedSpawnMode(sessionKey),
                this.managedSpawnSandbox(sessionKey),
                this.managedSpawnThread(sessionKey).trimAscii().toAsciiLower() == "true"
            )
        }
        let agentId = this.managedSubagentAgentId(sessionKey)
        let timeoutText = this.managedSpawnTimeoutSeconds(sessionKey)
        let runTimeoutSeconds = try { Int64.parse(timeoutText) } catch (_: Exception) { -1 }
        return this.launchManagedSubagentRun(sessionKey, agentId, task, cwdHint, runTimeoutSeconds: runTimeoutSeconds)
    }

    @tool[
        description: "Lists locally persisted gateway session keys under ~/.metis/agents/<agentId>/sessions. Optional containsFilter narrows keys by case-insensitive substring. Reads local session storage only.",
        parameters: {
            containsFilter: "Optional substring to filter session keys; omit or empty to list all."
        }
    ]
    public func sessionsList(containsFilter: Option<String>): String {
        PrintUtils.printTool("sessionsList", shortMessage: "gateway-sessions")
        let st = this.gwStore()
        let keys = st.listSessionKeys()
        let needle = match (containsFilter) {
            case Some(s) => s.trimAscii().toAsciiLower()
            case None => ""
        }
        let lines = ArrayList<String>()
        for (k in keys) {
            if (needle.isEmpty() || k.toAsciiLower().contains(needle)) {
                lines.add("- ${k}")
            }
        }
        let root = st.sessionsRoot().toString()
        let sessions = JsonArray([])
        for (line in lines) {
            sessions.add(JsonString(line["- ".size..]))
        }
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("action", JsonString("sessionsList"))
        result.put("path", JsonString(root))
        result.put("count", lines.size.toJsonValue())
        result.put("sessions", sessions)
        if (!needle.isEmpty()) {
            result.put("containsFilter", JsonString(needle))
        }
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Lists locally persisted gateway sessions using the Metis-compatible sessions_list name. Supports kinds, limit, activeMinutes, and messageLimit parameters. activeMinutes is currently advisory only because local session files do not store indexed last-active metadata.",
        parameters: {
            kinds: "Optional array of allowed kinds: main, group, cron, hook, node, other.",
            limit: "Optional maximum number of sessions to return; minimum 1.",
            activeMinutes: "Optional last-active filter in minutes. Current implementation acknowledges it but does not filter by it because local session files do not store indexed last-active metadata.",
            messageLimit: "Optional number of recent transcript entries to include per session; clamped to 20."
        }
    ]
    public func sessions_list(
        kinds: Option<Array<String>>,
        limit: Option<Int64>,
        activeMinutes: Option<Int64>,
        messageLimit: Option<Int64>
    ): String {
        PrintUtils.printTool("sessions_list", shortMessage: "gateway-sessions")

        let allowedKinds = this.normalizeSessionKinds(kinds)
        let cappedLimit = if (let Some(v) <- limit) {
            if (v < 1) { 1 } else { v }
        } else {
            Int64.Max
        }
        let transcriptLimit = if (let Some(v) <- messageLimit) {
            if (v < 0) {
                0
            } else if (v > 20) {
                20
            } else {
                v
            }
        } else {
            0
        }

        let st = this.gwStore()
        let sessions = JsonArray([])
        var added: Int64 = 0
        for (sessionKey in st.listSessionKeys()) {
            if (added >= cappedLimit) {
                break
            }
            let kind = this.classifySessionKind(sessionKey)
            if (!this.kindAllowed(kind, allowedKinds)) {
                continue
            }
            let transcriptPath = st.transcriptPath(sessionKey)
            let row = JsonObject()
            row.put("key", JsonString(sessionKey))
            row.put("kind", JsonString(kind))
            row.put("transcriptPath", JsonString(transcriptPath.toString()))
            row.put("exists", exists(transcriptPath).toJsonValue())
            if (transcriptLimit > 0) {
                row.put("recentMessages", JsonString(st.formatHistoryAsText(sessionKey, transcriptLimit)))
            }
            sessions.add(row)
            added += 1
        }

        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("action", JsonString("sessions_list"))
        result.put("path", JsonString(st.sessionsRoot().toString()))
        result.put("sessions", sessions)
        if (let Some(v) <- activeMinutes) {
            if (v > 0) {
                result.put("compatNote", JsonString("activeMinutes=${v} was requested, but local session files do not expose indexed last-active metadata, so no active-time filtering was applied."))
            }
        }

        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Returns recent transcript for a gateway sessionKey as labeled lines [user]/[assistant]/[system]. maxEntries defaults to 40. Reads local jsonl only.",
        parameters: {
            sessionKey: "Full session key as shown by sessionsList (e.g. qq:direct:user:...).",
            maxEntries: "Optional max message rows from end of transcript; default 40."
        }
    ]
    public func sessionsHistory(sessionKey: String, maxEntries: Option<Int64>): String {
        let sk = sessionKey.trimAscii()
        PrintUtils.printTool("sessionsHistory", shortMessage: sk)
        if (sk.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessionsHistory"))
            err.put("error", JsonString("sessionKey must be non-empty"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }
        let cap = maxEntries ?? 40
        let text = this.gwStore().formatHistoryAsText(sk, cap)
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("action", JsonString("sessionsHistory"))
        result.put("sessionKey", JsonString(sk))
        result.put("maxEntries", cap.toJsonValue())
        result.put("history", JsonString(text))
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Appends one transcript line to a gateway session jsonl (local file only). role optional: assistant (default), user, or system. Does not send IM; running gateway may need restart to reload disk. Use for cross-session notes or injected context.",
        parameters: {
            sessionKey: "Target session key.",
            message: "Text to append.",
            role: "Optional one of assistant, user, system; default assistant."
        }
    ]
    public func sessionsSend(sessionKey: String, message: String, role: Option<String>): String {
        let sk = sessionKey.trimAscii()
        let msg = message.trimAscii()
        PrintUtils.printTool("sessionsSend", shortMessage: sk)
        if (sk.isEmpty() || msg.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessionsSend"))
            err.put("error", JsonString("sessionKey and message must be non-empty"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }
        let r = this.normalizeTranscriptRole(role)
        this.gwStore().appendTranscriptEntry(sk, r, msg)
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("action", JsonString("sessionsSend"))
        result.put("sessionKey", JsonString(sk))
        result.put("role", JsonString(r))
        result.put("message", JsonString(msg))
        result.put("compatNote", JsonString("If gateway serve holds this key in memory, restart gateway to pick up disk changes."))
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Metis-compatible cross-session send tool. Accepts either sessionKey or label plus message, appends the message to the local gateway session transcript, and returns a structured JSON result. timeoutSeconds is accepted for compatibility but does not block on a remote run.",
        parameters: {
            sessionKey: "Optional target session key. Provide either sessionKey or label.",
            label: "Optional spawned-session label. Provide either label or sessionKey.",
            agentId: "Optional agent id hint used during label lookup.",
            message: "Message text to append to the target session.",
            timeoutSeconds: "Optional compatibility timeout hint. Current implementation acknowledges it but does not wait for a remote reply."
        }
    ]
    public func sessions_send(
        sessionKey: Option<String>,
        label: Option<String>,
        agentId: Option<String>,
        message: String,
        timeoutSeconds: Option<Int64>
    ): String {
        PrintUtils.printTool("sessions_send", shortMessage: "gateway-sessions")
        let msg = message.trimAscii()
        if (msg.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("error", JsonString("message must be non-empty"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let sessionKeyText = match (sessionKey) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let labelText = match (label) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        if (!sessionKeyText.isEmpty() && !labelText.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("error", JsonString("Provide either sessionKey or label (not both)."))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        var resolvedSessionKey = sessionKeyText
        if (resolvedSessionKey.isEmpty() && !labelText.isEmpty()) {
            resolvedSessionKey = this.resolveSessionKeyByLabel(labelText, agentId)
            if (resolvedSessionKey.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString("sessions_send"))
                err.put("error", JsonString("No session found with label: ${labelText}"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
        }

        if (resolvedSessionKey.isEmpty()) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("error", JsonString("Either sessionKey or label is required"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let st = this.gwStore()
        if (!exists(st.transcriptPath(resolvedSessionKey))) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessions_send"))
            err.put("sessionKey", JsonString(resolvedSessionKey))
            err.put("error", JsonString("Session not found: ${resolvedSessionKey} (use the full sessionKey from sessions_list)"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        st.appendTranscriptEntry(resolvedSessionKey, "user", msg)
        let now = DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("action", JsonString("sessions_send"))
        result.put("runId", JsonString("local-${now}"))
        result.put("status", JsonString("completed"))
        result.put("sessionKey", JsonString(resolvedSessionKey))
        result.put("message", JsonString(msg))
        if (let Some(v) <- timeoutSeconds) {
            if (v >= 0) {
                result.put("compatNote", JsonString("timeoutSeconds=${v} was accepted, but sessions_send only appends to the target transcript and does not wait for a remote reply."))
            }
        }
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Creates a new empty gateway session file (meta only) and returns the new sessionKey. shortLabel optional tag embedded in key. Local only; use with gateway session routing if you align dmScope manually.",
        parameters: { shortLabel: "Optional short label for the key; may be empty." }
    ]
    public func sessionsSpawn(shortLabel: Option<String>): String {
        PrintUtils.printTool("sessionsSpawn", shortMessage: "new session")
        let lab = shortLabel ?? ""
        let key = this.gwStore().spawnSession(lab)
        if (key.startsWith("error:")) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("action", JsonString("sessionsSpawn"))
            err.put("error", JsonString(key))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("action", JsonString("sessionsSpawn"))
        result.put("sessionKey", JsonString(key))
        if (!lab.trimAscii().isEmpty()) {
            result.put("label", JsonString(lab.trimAscii()))
        }
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    @tool[
        description: "Metis-compatible session spawn tool. Creates a local managed session, records spawn metadata, and returns structured JSON. runtime=subagent can launch a background dedicated subagent CLI turn; runtime=acp can launch a background external harness process such as codex, claude, gemini, or a custom command. Use this when the user naturally asks to start a subagent, run work in the background or in parallel, or notify the current session when finished. Return after the accepted response; completion is reported later by runtime notification.",
        parameters: {
            task: "Task or prompt for the spawned session. Include enough context for the background run to complete without blocking the current session.",
            label: "Optional label for the spawned session.",
            runtime: "Optional runtime hint: subagent or acp. Use subagent for Metis built-in/background agents.",
            agentId: "Optional target agent identifier hint. For runtime=acp this can be codex, claude, gemini, cursor-agent, or cmd:<shell-command-with-{task}>.",
            resumeSessionId: "Optional ACP resume session id hint forwarded to supported harnesses such as codex.",
            model: "Optional model override hint forwarded to supported ACP harnesses and stored in session metadata.",
            thinking: "Optional thinking override hint forwarded to supported ACP harnesses when available.",
            cwd: "Optional working directory hint used when launching the background run.",
            runTimeoutSeconds: "Optional run timeout hint.",
            timeoutSeconds: "Optional legacy timeout hint. Used only when runTimeoutSeconds is omitted.",
            thread: "Optional thread mode hint.",
            mode: "Optional spawn mode hint: run or session.",
            cleanup: "Optional cleanup hint: delete or keep.",
            sandbox: "Optional sandbox hint: inherit or require.",
            streamTo: "Optional ACP stream target hint."
        }
    ]
    public func sessions_spawn(
        task: String,
        label: Option<String>,
        runtime: Option<String>,
        agentId: Option<String>,
        resumeSessionId: Option<String>,
        model: Option<String>,
        thinking: Option<String>,
        cwd: Option<String>,
        runTimeoutSeconds: Option<Int64>,
        timeoutSeconds: Option<Int64>,
        thread: Option<Bool>,
        mode: Option<String>,
        cleanup: Option<String>,
        sandbox: Option<String>,
        streamTo: Option<String>
    ): String {
        this.sessionsSpawnForCommand(
            task,
            label,
            runtime,
            agentId,
            resumeSessionId,
            model,
            thinking,
            cwd,
            runTimeoutSeconds,
            timeoutSeconds,
            thread,
            mode,
            cleanup,
            sandbox,
            streamTo
        )
    }

    public func sessionsSpawnForCommand(
        task: String,
        label: Option<String>,
        runtime: Option<String>,
        agentId: Option<String>,
        resumeSessionId: Option<String>,
        model: Option<String>,
        thinking: Option<String>,
        cwd: Option<String>,
        runTimeoutSeconds: Option<Int64>,
        timeoutSeconds: Option<Int64>,
        thread: Option<Bool>,
        mode: Option<String>,
        cleanup: Option<String>,
        sandbox: Option<String>,
        streamTo: Option<String>
    ): String {
        PrintUtils.printTool("sessions_spawn", shortMessage: "gateway-sessions")
        let trimmedTask = task.trimAscii()
        if (trimmedTask.isEmpty()) {
            let err = JsonObject()
            err.put("status", JsonString("error"))
            err.put("error", JsonString("task must be non-empty"))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let runtimeText = match (runtime) {
            case Some(v) =>
                let t = v.trimAscii().toAsciiLower()
                if (t == "acp") { "acp" } else { "subagent" }
            case None => "subagent"
        }
        let labelText = match (label) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let requestedAgentId = match (agentId) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let agentIdText = if (runtimeText == "acp") {
            if (requestedAgentId.isEmpty()) { "codex" } else { requestedAgentId }
        } else {
            this.normalizeManagedAgentId(requestedAgentId)
        }
        let spawnLabel = this.buildSpawnLabel(labelText, runtimeText, agentIdText)
        let st = this.gwStore()
        var effectiveTimeout = if (let Some(v) <- runTimeoutSeconds) {
            v
        } else {
            timeoutSeconds ?? -1
        }
        let runtimeContext = gatewayCurrentToolRuntimeContext()
        let requesterSessionKey = match (runtimeContext) {
            case Some(ctx) => ctx.sessionKey
            case None => ""
        }
        var currentDepth: Int64 = 0
        if (!requesterSessionKey.trimAscii().isEmpty()) {
            match (gatewaySubagentFindRunBySessionKey(st.sessionsRoot(), requesterSessionKey)) {
                case Some(parentRun) => currentDepth = gatewaySubagentRunRecordInt(parentRun, "depth")
                case None => ()
            }
        }
        let requestedSandboxText = match (sandbox) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let agentSourceText = if (runtimeText == "acp") { "acp" } else { "builtin" }
        let subagentSettings = CliSettingManager.readGatewaySettings().subagents
        let policyDecision = gatewaySubagentEvaluateSpawnPolicy(
            subagentSettings,
            st.sessionsRoot(),
            requesterSessionKey,
            agentIdText,
            agentSourceText,
            runtimeText,
            effectiveTimeout,
            currentDepth,
            requestedSandboxText
        )
        effectiveTimeout = policyDecision.effectiveTimeoutSeconds
        if (!policyDecision.allowed) {
            let err = gatewaySubagentPolicyRejectionJson(policyDecision, agentIdText, runtimeText)
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }
        let parentAgentId = match (runtimeContext) {
            case Some(ctx) => ctx.agentId
            case None => ""
        }
        let parentToolPolicy = resolveRuntimeToolPolicyFromRoot(
            this.runtimePolicyRootForSpawn(),
            this.subagentBoundaryInventory(subagentSettings.childAllowedTools),
            agentId: parentAgentId
        )
        let boundaryDecision = runtimeSubagentBoundaryDecision(
            parentToolPolicy,
            requestedAgentId: agentIdText,
            requireAgentId: subagentSettings.requireAgentId,
            allowAgents: subagentSettings.allowAgents,
            requestedTools: subagentSettings.childAllowedTools
        )
        if (!boundaryDecision.allowed) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("rejected"))
            err.put("error", JsonString("subagent policy rejected: ${boundaryDecision.reason}"))
            err.put("reason", JsonString(boundaryDecision.reason))
            err.put("agentId", JsonString(agentIdText))
            err.put("runtime", JsonString(runtimeText))
            err.put("parentAgentId", JsonString(parentAgentId))
            err.put("parentToolPolicy", runtimeToolPolicyReportToJson(parentToolPolicy))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let sessionKey = st.spawnSession(spawnLabel)
        if (sessionKey.startsWith("error:")) {
            let err = JsonObject()
            err.put("ok", false.toJsonValue())
            err.put("status", JsonString("error"))
            err.put("error", JsonString(sessionKey))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let metadata = ArrayList<String>()
        metadata.add("runtime=${runtimeText}")
        if (!labelText.isEmpty()) {
            metadata.add("label=${labelText}")
        }
        if (!agentIdText.isEmpty()) {
            metadata.add("agentId=${agentIdText}")
        }
        match (resumeSessionId) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("resumeSessionId=${t}") }
            case None => ()
        }
        match (model) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("model=${t}") }
            case None => ()
        }
        match (thinking) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("thinking=${t}") }
            case None => ()
        }
        match (cwd) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("cwd=${t}") }
            case None => ()
        }
        match (mode) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("mode=${t}") }
            case None => ()
        }
        match (cleanup) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("cleanup=${t}") }
            case None => ()
        }
        match (sandbox) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("sandbox=${t}") }
            case None => ()
        }
        match (streamTo) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { metadata.add("streamTo=${t}") }
            case None => ()
        }
        match (thread) {
            case Some(v) => metadata.add("thread=${v}")
            case None => ()
        }
        if (effectiveTimeout >= 0) {
            metadata.add("timeoutSeconds=${effectiveTimeout}")
        }

        st.appendTranscriptEntry(sessionKey, "system", "sessions_spawn metadata: ${String.join(metadata.toArray(), delimiter: ", ")}")

        let cwdHint = match (cwd) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let modeText = match (mode) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let cleanupText = match (cleanup) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let sandboxText = match (sandbox) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let streamToText = match (streamTo) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let threadValue = match (thread) {
            case Some(v) => v
            case None => false
        }
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("accepted"))
        result.put("runId", JsonString(sessionKey))
        result.put("sessionKey", JsonString(sessionKey))
        result.put("runtime", JsonString(runtimeText))
        result.put("agentId", JsonString(agentIdText))
        result.put("task", JsonString(trimmedTask))
        result.put("cwd", JsonString(if (cwdHint.isEmpty()) { CliConfig.cwd.toString() } else { cwdHint }))
        if (!labelText.isEmpty()) {
            result.put("label", JsonString(labelText))
        }
        if (!modeText.isEmpty()) {
            result.put("mode", JsonString(modeText))
        }
        if (!cleanupText.isEmpty()) {
            result.put("cleanup", JsonString(cleanupText))
        }
        if (!sandboxText.isEmpty()) {
            result.put("sandbox", JsonString(sandboxText))
        }
        if (!streamToText.isEmpty()) {
            result.put("streamTo", JsonString(streamToText))
        }
        match (thread) {
            case Some(v) => result.put("thread", v.toJsonValue())
            case None => ()
        }
        if (effectiveTimeout >= 0) {
            result.put("timeoutSeconds", effectiveTimeout.toJsonValue())
        }
        let runRecord = gatewaySubagentCreateRunRecord(
            st.sessionsRoot(),
            sessionKey,
            parentSessionKey: "",
            requesterSessionKey: "",
            requesterChannel: "cli",
            agentId: agentIdText,
            agentSource: if (runtimeText == "acp") { "acp" } else { "builtin" },
            runtime: runtimeText,
            task: trimmedTask,
            label: labelText,
            status: "queued",
            cwd: if (cwdHint.isEmpty()) { CliConfig.cwd.toString() } else { cwdHint },
            model: match (model) { case Some(v) => v.trimAscii() case None => "" },
            thinking: match (thinking) { case Some(v) => v.trimAscii() case None => "" },
            timeoutSeconds: effectiveTimeout,
            transcriptPath: st.transcriptPath(sessionKey).toString()
        )
        let runMetadata = JsonObject()
        runMetadata.put("policy", gatewaySubagentPolicyDecisionToJson(policyDecision))
        runRecord.put("metadata", runMetadata)
        let _ = gatewaySubagentWriteRunRecord(st.sessionsRoot(), runRecord)
        let runId = gatewaySubagentRunRecordString(runRecord, "runId")
        result.put("runId", JsonString(runId))
        result.put("policy", gatewaySubagentPolicyDecisionToJson(policyDecision))
        if (runtimeText == "subagent" && this.supportsRealManagedSubagent(agentIdText)) {
            let launched = this.launchManagedSubagentRun(sessionKey, agentIdText, trimmedTask, cwdHint, runTimeoutSeconds: effectiveTimeout)
            result.put("liveRunStarted", launched.toJsonValue())
            if (!launched) {
                result.put("compatNote", JsonString("The subagent runtime rejected the launch because this session already has a queued or running turn."))
            }
        } else if (runtimeText == "acp") {
            let requestedHarness = if (agentIdText.trimAscii().isEmpty()) { "codex" } else { agentIdText.trimAscii() }
            let effectiveHarness = match (requestedHarness.toAsciiLower()) {
                case "" | "codex" | "codex-cli" => "codex"
                case "claude" | "claude-code" => "claude"
                case "gemini" | "gemini-cli" => "gemini"
                case "cursor" | "cursor-agent" | "cursor_cli" => "cursor-agent"
                case _ => if (requestedHarness.toAsciiLower().startsWith("cmd:")) { "custom-cmd" } else if (requestedHarness.contains(" ")) { "custom-shell" } else { requestedHarness }
            }
            let effectiveMode = this.acpEffectiveMode(modeText)
            let effectiveSandbox = this.acpEffectiveSandbox(sandboxText)
            let effectiveSessionPersistence = this.acpEffectiveSessionPersistence(modeText, threadValue)
            let launched = this.launchManagedAcpRun(
                sessionKey,
                agentIdText,
                trimmedTask,
                cwdHint,
                model,
                thinking,
                resumeSessionId,
                effectiveTimeout,
                streamToText,
                modeText,
                sandboxText,
                threadValue
            )
            result.put("liveRunStarted", launched.toJsonValue())
            result.put("runtime", JsonString("acp"))
            result.put("effectiveHarness", JsonString(effectiveHarness))
            result.put("effectiveMode", JsonString(effectiveMode))
            result.put("effectiveSandbox", JsonString(effectiveSandbox))
            result.put("effectiveSessionPersistence", JsonString(effectiveSessionPersistence))
            if (!launched) {
                result.put("compatNote", JsonString("The ACP runtime rejected the launch because this session already has a queued or running turn."))
            }
        } else {
            st.appendTranscriptEntry(sessionKey, "user", trimmedTask)
            result.put("compatNote", JsonString("This sessions_spawn call recorded the task, but only runtime=subagent or runtime=acp launches a background turn in this build."))
        }
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Metis-compatible session_status tool. Returns a structured snapshot of current local runtime and session state, including cwd, language, configured model, todo-plan status, gateway session store path, and optional session transcript details for a requested sessionKey.",
        parameters: {
            sessionKey: "Optional session key to inspect. If provided and the transcript exists locally, the response includes transcriptPath and a recent transcript excerpt.",
            model: "Optional model override hint. Current implementation reports it as a compatibility note and does not mutate session state."
        }
    ]
    public func session_status(sessionKey: Option<String>, model: Option<String>): String {
        PrintUtils.printTool("session_status", shortMessage: "local runtime")

        let st = this.gwStore()
        let result = JsonObject()
        result.put("ok", true.toJsonValue())
        result.put("status", JsonString("ok"))
        result.put("cwd", JsonString(CliConfig.cwd.toString()))
        result.put("language", JsonString(CliConfig.language))
        result.put("model", JsonString(CliConfig.model))
        result.put("todoFile", JsonString(CliConfig.todoFile.toString()))
        result.put("todoFileExists", exists(CliConfig.todoFile).toJsonValue())
        result.put("gatewaySessionsPath", JsonString(st.sessionsRoot().toString()))
        result.put("gatewaySessionCount", st.listSessionKeys().size.toJsonValue())

        let plan = Plan.load()
        result.put("planOpenTaskCount", this.countOpenPlanTasks(plan).toJsonValue())
        let planText = plan.toString().trimAscii()
        if (!planText.isEmpty()) {
            result.put("plan", JsonString(planText))
        }

        match (sessionKey) {
            case Some(v) =>
                let sk = v.trimAscii()
                if (!sk.isEmpty()) {
                    let transcriptPath = st.transcriptPath(sk)
                    let session = JsonObject()
                    session.put("sessionKey", JsonString(sk))
                    session.put("transcriptPath", JsonString(transcriptPath.toString()))
                    session.put("transcriptExists", exists(transcriptPath).toJsonValue())
                    session.put("runtime", JsonString(this.managedSubagentRuntime(sk)))
                    result.put("sessionKey", JsonString(sk))
                    result.put("transcriptPath", JsonString(transcriptPath.toString()))
                    result.put("transcriptExists", exists(transcriptPath).toJsonValue())
                    result.put("runtime", JsonString(this.managedSubagentRuntime(sk)))
                    let subagentId = this.managedSubagentAgentId(sk)
                    let subagentState = this.managedSubagentState(sk)
                    if (!subagentId.isEmpty()) {
                        result.put("subagentAgentId", JsonString(subagentId))
                        session.put("agentId", JsonString(subagentId))
                    }
                    if (!subagentState.isEmpty()) {
                        result.put("subagentState", JsonString(subagentState))
                        session.put("state", JsonString(subagentState))
                    }
                    result.put("subagentHasLiveFuture", this.managedSubagentHasLiveFuture(sk).toJsonValue())
                    result.put("subagentHasLiveProcess", this.managedSubagentHasLiveProcess(sk).toJsonValue())
                    session.put("hasLiveFuture", this.managedSubagentHasLiveFuture(sk).toJsonValue())
                    session.put("hasLiveProcess", this.managedSubagentHasLiveProcess(sk).toJsonValue())
                    let cwdHint = this.managedSubagentCwd(sk)
                    if (!cwdHint.isEmpty()) {
                        result.put("subagentCwd", JsonString(cwdHint))
                        session.put("cwd", JsonString(cwdHint))
                    }
                    let modelText = this.managedSpawnModel(sk)
                    if (!modelText.isEmpty()) {
                        result.put("sessionModel", JsonString(modelText))
                        session.put("model", JsonString(modelText))
                    }
                    let thinkingText = this.managedSpawnThinking(sk)
                    if (!thinkingText.isEmpty()) {
                        result.put("sessionThinking", JsonString(thinkingText))
                        session.put("thinking", JsonString(thinkingText))
                    }
                    let resumeText = this.managedSpawnResumeSessionId(sk)
                    if (!resumeText.isEmpty()) {
                        result.put("resumeSessionId", JsonString(resumeText))
                        session.put("resumeSessionId", JsonString(resumeText))
                    }
                    let modeText = this.managedSpawnMode(sk)
                    if (!modeText.isEmpty()) {
                        result.put("sessionMode", JsonString(modeText))
                        session.put("mode", JsonString(modeText))
                    }
                    let cleanupText = this.managedSpawnCleanup(sk)
                    if (!cleanupText.isEmpty()) {
                        result.put("sessionCleanup", JsonString(cleanupText))
                        session.put("cleanup", JsonString(cleanupText))
                    }
                    let sandboxText = this.managedSpawnSandbox(sk)
                    if (!sandboxText.isEmpty()) {
                        result.put("sessionSandbox", JsonString(sandboxText))
                        session.put("sandbox", JsonString(sandboxText))
                    }
                    let streamText = this.managedSpawnStreamTo(sk)
                    if (!streamText.isEmpty()) {
                        result.put("streamTo", JsonString(streamText))
                        session.put("streamTo", JsonString(streamText))
                    }
                    let threadText = this.managedSpawnThread(sk)
                    if (!threadText.isEmpty()) {
                        result.put("sessionThread", JsonString(threadText))
                        session.put("thread", JsonString(threadText))
                    }
                    let timeoutText = this.managedSpawnTimeoutSeconds(sk)
                    if (!timeoutText.isEmpty()) {
                        result.put("sessionTimeoutSeconds", JsonString(timeoutText))
                        session.put("timeoutSeconds", JsonString(timeoutText))
                    }
                    if (this.managedSubagentRuntime(sk) == "acp") {
                        let requestedHarness = if (subagentId.isEmpty()) { "codex" } else { subagentId }
                        let effectiveHarness = match (requestedHarness.trimAscii().toAsciiLower()) {
                            case "" | "codex" | "codex-cli" => "codex"
                            case "claude" | "claude-code" => "claude"
                            case "gemini" | "gemini-cli" => "gemini"
                            case "cursor" | "cursor-agent" | "cursor_cli" => "cursor-agent"
                            case _ => if (requestedHarness.trimAscii().toAsciiLower().startsWith("cmd:")) { "custom-cmd" } else if (requestedHarness.contains(" ")) { "custom-shell" } else { requestedHarness }
                        }
                        let effectiveMode = this.acpEffectiveMode(modeText)
                        let effectiveSandbox = this.acpEffectiveSandbox(sandboxText)
                        let effectiveSessionPersistence = this.acpEffectiveSessionPersistence(modeText, threadText.trimAscii().toAsciiLower() == "true")
                        result.put("effectiveHarness", JsonString(effectiveHarness))
                        result.put("effectiveMode", JsonString(effectiveMode))
                        result.put("effectiveSandbox", JsonString(effectiveSandbox))
                        result.put("effectiveSessionPersistence", JsonString(effectiveSessionPersistence))
                        session.put("effectiveHarness", JsonString(effectiveHarness))
                        session.put("effectiveMode", JsonString(effectiveMode))
                        session.put("effectiveSandbox", JsonString(effectiveSandbox))
                        session.put("effectiveSessionPersistence", JsonString(effectiveSessionPersistence))
                    }
                    if (exists(transcriptPath)) {
                        result.put("recentMessages", JsonString(st.formatHistoryAsText(sk, 10)))
                        session.put("recentMessages", JsonString(st.formatHistoryAsText(sk, 10)))
                    } else {
                        result.put("sessionNote", JsonString("Session not found locally: ${sk}"))
                        session.put("note", JsonString("Session not found locally: ${sk}"))
                    }
                    result.put("session", session)
                }
            case None => ()
        }

        match (model) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) {
                    result.put("compatNote", JsonString("model=${t} was provided, but session_status is read-only and does not mutate session model overrides."))
                }
            case None => ()
        }

        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Metis-compatible gateway control tool. Supports status, start, stop, restart, master on/off, config.get, config.schema.lookup, config.patch, config.apply, and update.run using the project's gateway runtime and persisted settings.",
        parameters: {
            action: "Gateway action. Supported now: status, start, stop, restart, master_on, master_off, config.get, config.schema.lookup, config.patch, config.apply, update.run.",
            note: "Optional note echoed in unsupported responses.",
            raw: "For config.patch/config.apply, the raw value to assign to the path. For config.get, ignored.",
            path: "Optional config path for config.get, config.schema.lookup, config.patch, or config.apply, such as gateway, gateway.feishu, or gateway.session.dmScope.",
            sessionKey: "Reserved for future restart/update routing."
        }
    ]
    public func gateway(
        action: String,
        note: Option<String>,
        raw: Option<String>,
        path: Option<String>,
        sessionKey: Option<String>
    ): String {
        let act = action.trimAscii().toAsciiLower()
        PrintUtils.printTool("gateway", shortMessage: act)

        if (act == "status") {
            let res = this.gatewayToolClient().request("status")
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "start") {
            let res = this.gatewayToolClient().request("start")
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "stop") {
            let res = this.gatewayToolClient().request("stop")
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "restart") {
            let res = this.gatewayToolClient().request("restart")
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "master_on" || act == "master_off") {
            let res = this.gatewayToolClient().request(act)
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "update.run") {
            let res = this.gatewayToolClient().request("update.run")
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "config.get") {
            let lookupPath = match (path) {
                case Some(v) => v.trimAscii()
                case None => "gateway"
            }
            let params = JsonObject()
            params.put("path", JsonString(if (lookupPath.isEmpty()) { "gateway" } else { lookupPath }))
            let res = this.gatewayToolClient().request("config.get", params: params)
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "config.schema.lookup") {
            let lookupPath = match (path) {
                case Some(v) => v.trimAscii()
                case None => "gateway"
            }
            let params = JsonObject()
            params.put("path", JsonString(if (lookupPath.isEmpty()) { "gateway" } else { lookupPath }))
            let res = this.gatewayToolClient().request("config.schema.lookup", params: params)
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "config.patch" || act == "config.apply") {
            let patchPath = match (path) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            let patchRaw = match (raw) {
                case Some(v) => v
                case None => ""
            }
            let params = JsonObject()
            params.put("path", JsonString(patchPath))
            params.put("raw", JsonString(patchRaw))
            let res = this.gatewayToolClient().request(act, params: params)
            let out = res.toJson().toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let unsupported = JsonObject()
        unsupported.put("ok", false.toJsonValue())
        unsupported.put("status", JsonString("unsupported"))
        unsupported.put("action", JsonString(act))
        unsupported.put("error", JsonString("Unsupported gateway action in current local implementation: ${act}"))
        match (note) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("note", JsonString(t)) }
            case None => ()
        }
        match (raw) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("raw", JsonString(t)) }
            case None => ()
        }
        match (path) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("path", JsonString(t)) }
            case None => ()
        }
        match (sessionKey) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("sessionKey", JsonString(t)) }
            case None => ()
        }
        unsupported.put("compatNote", JsonString("Supported actions right now are status, start, stop, restart, master_on, master_off, config.get, config.schema.lookup, config.patch, config.apply, and update.run."))
        let out = unsupported.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Metis-compatible cron tool. Maps status, list, add, update, remove, path, help, run, runs, and wake to the project's local cron backend and runner.",
        parameters: {
            action: "Cron action. Supported now: status, list, add, update, remove, path, help, run, runs, wake.",
            jobId: "Optional job id for update/remove/run/runs.",
            id: "Optional backward-compatible job id alias.",
            name: "Optional job id when creating a job.",
            every: "Optional interval such as 30s, 5m, or raw milliseconds.",
            at: "Optional one-shot time in ISO8601, Unix timestamp, or relative format like 20m.",
            cronExpr: "Optional cron expression for recurring jobs.",
            tz: "Optional timezone such as UTC or UTC+8.",
            sessionTarget: "Optional session target such as main, isolated, current, or session:xxx.",
            message: "Optional message/prompt for add or update.",
            includeDisabled: "Optional includeDisabled flag for list responses.",
            enabled: "Optional enabled flag for update.",
            timeoutMs: "Optional execution timeout in milliseconds.",
            maxRetries: "Optional maximum retries after the first failure.",
            retryBackoffMs: "Optional retry backoff milliseconds.",
            failureChannel: "Optional failure alert channel.",
            failureTo: "Optional failure alert target peer id.",
            failureAnnounce: "Optional failure announce flag.",
            text: "Optional text hint echoed in wake responses.",
            mode: "Optional mode hint echoed in run/wake responses."
        }
    ]
    public func cron(
        action: String,
        jobId: Option<String>,
        id: Option<String>,
        name: Option<String>,
        every: Option<String>,
        at: Option<String>,
        cronExpr: Option<String>,
        tz: Option<String>,
        sessionTarget: Option<String>,
        message: Option<String>,
        includeDisabled: Option<Bool>,
        enabled: Option<Bool>,
        timeoutMs: Option<Int64>,
        maxRetries: Option<Int64>,
        retryBackoffMs: Option<Int64>,
        failureChannel: Option<String>,
        failureTo: Option<String>,
        failureAnnounce: Option<Bool>,
        text: Option<String>,
        mode: Option<String>
    ): String {
        let act = this.normalizeCronAction(action)
        PrintUtils.printTool("cron", shortMessage: act)

        let args = ArrayList<String>(["cron"])
        if (act == "help" || act.isEmpty()) {
            args.add("help")
        } else if (act == "path") {
            args.add("path")
        } else if (act == "status") {
            // Local backend has no dedicated status verb; use list semantics and report the cron store path.
            let result = JsonObject()
            result.put("ok", true.toJsonValue())
            result.put("action", JsonString("status"))
            result.put("status", JsonString("ok"))
            let pathRes = gatewayExecuteCronWithUnifiedRun(["cron", "path"])
            let listRes = gatewayExecuteCronWithUnifiedRun(["cron", "list"])
            result.put("path", JsonString(pathRes[0]))
            result.put("list", JsonString(listRes[0]))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        } else if (act == "list") {
            args.add("list")
            if ((includeDisabled ?? false)) {
                // Current local list already shows enabled state for all jobs.
            }
        } else if (act == "add") {
            args.add("add")
            let jobName = match (name) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            let msg = match (message) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            if (jobName.isEmpty() || msg.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("action", JsonString("add"))
                err.put("status", JsonString("error"))
                err.put("error", JsonString("add requires name and message"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            args.add("--name")
            args.add(jobName)
            match (every) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--every")
                        args.add(t)
                    }
                case None => ()
            }
            match (at) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--at")
                        args.add(t)
                    }
                case None => ()
            }
            match (cronExpr) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--cron")
                        args.add(t)
                    }
                case None => ()
            }
            match (tz) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) {
                        args.add("--tz")
                        args.add(t)
                    }
                case None => ()
            }
            args.add("--session")
            args.add(match (sessionTarget) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (t.isEmpty()) { "main" } else { t }
                case None => "main"
            })
            args.add("--message")
            args.add(msg)
            match (timeoutMs) { case Some(v) => if (v > 0) { args.add("--timeout-ms"); args.add("${v}") } case None => () }
            match (maxRetries) { case Some(v) => if (v >= 0) { args.add("--max-retries"); args.add("${v}") } case None => () }
            match (retryBackoffMs) { case Some(v) => if (v > 0) { args.add("--retry-backoff-ms"); args.add("${v}") } case None => () }
            match (failureChannel) { case Some(v) => let t = v.trimAscii(); if (!t.isEmpty()) { args.add("--failure-channel"); args.add(t) } case None => () }
            match (failureTo) { case Some(v) => let t = v.trimAscii(); if (!t.isEmpty()) { args.add("--failure-to"); args.add(t) } case None => () }
            match (failureAnnounce) { case Some(v) => args.add(if (v) { "--failure-announce" } else { "--no-failure-announce" }) case None => () }
        } else if (act == "update") {
            let resolvedId = match (jobId) {
                case Some(v) => v.trimAscii()
                case None => match (id) {
                    case Some(v2) => v2.trimAscii()
                    case None => ""
                }
            }
            if (resolvedId.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("action", JsonString("update"))
                err.put("status", JsonString("error"))
                err.put("error", JsonString("update requires jobId"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            args.add("edit")
            args.add(resolvedId)
            match (enabled) {
                case Some(v) =>
                    args.add("--enabled")
                    args.add(if (v) { "true" } else { "false" })
                case None =>
                    match (message) {
                        case Some(m) =>
                            let t = m.trimAscii()
                            if (!t.isEmpty()) {
                                args.add("--message")
                                args.add(t)
                            }
                        case None => ()
                    }
            }
            match (timeoutMs) { case Some(v) => if (v > 0) { args.add("--timeout-ms"); args.add("${v}") } case None => () }
            match (maxRetries) { case Some(v) => if (v >= 0) { args.add("--max-retries"); args.add("${v}") } case None => () }
            match (retryBackoffMs) { case Some(v) => if (v > 0) { args.add("--retry-backoff-ms"); args.add("${v}") } case None => () }
            match (failureChannel) { case Some(v) => let t = v.trimAscii(); if (!t.isEmpty()) { args.add("--failure-channel"); args.add(t) } case None => () }
            match (failureTo) { case Some(v) => let t = v.trimAscii(); if (!t.isEmpty()) { args.add("--failure-to"); args.add(t) } case None => () }
            match (failureAnnounce) { case Some(v) => args.add(if (v) { "--failure-announce" } else { "--no-failure-announce" }) case None => () }
        } else if (act == "remove") {
            let resolvedId = match (jobId) {
                case Some(v) => v.trimAscii()
                case None => match (id) {
                    case Some(v2) => v2.trimAscii()
                    case None => ""
                }
            }
            if (resolvedId.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("action", JsonString("remove"))
                err.put("status", JsonString("error"))
                err.put("error", JsonString("remove requires jobId"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            args.add("remove")
            args.add(resolvedId)
        } else if (act == "run") {
            let resolvedId = match (jobId) {
                case Some(v) => v.trimAscii()
                case None => match (id) {
                    case Some(v2) => v2.trimAscii()
                    case None => ""
                }
            }
            if (resolvedId.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("action", JsonString("run"))
                err.put("status", JsonString("error"))
                err.put("error", JsonString("run requires jobId"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            args.add("run")
            args.add("--job-id")
            args.add(resolvedId)
        } else if (act == "runs") {
            let resolvedId = match (jobId) {
                case Some(v) => v.trimAscii()
                case None => match (id) {
                    case Some(v2) => v2.trimAscii()
                    case None => ""
                }
            }
            args.add("runs")
            if (!resolvedId.isEmpty()) {
                args.add("--job-id")
                args.add(resolvedId)
            }
        } else if (act == "wake") {
            let resolvedId = match (jobId) {
                case Some(v) => v.trimAscii()
                case None => match (id) {
                    case Some(v2) => v2.trimAscii()
                    case None => ""
                }
            }
            args.add("wake")
            if (!resolvedId.isEmpty()) {
                args.add("--job-id")
                args.add(resolvedId)
            }
            if (let Some(v) <- mode) {
                let t = v.trimAscii()
                if (!t.isEmpty()) {
                    args.add("--mode")
                    args.add(t)
                }
            }
            if (let Some(v) <- text) {
                let t = v.trimAscii()
                if (!t.isEmpty()) {
                    args.add("--text")
                    args.add(t)
                }
            }
        } else {
            let unsupported = JsonObject()
            unsupported.put("ok", false.toJsonValue())
            unsupported.put("status", JsonString("unsupported"))
            unsupported.put("action", JsonString(act))
            unsupported.put("error", JsonString("Unsupported cron action in current local implementation: ${act}"))
            match (text) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) { unsupported.put("text", JsonString(t)) }
                case None => ()
            }
            match (mode) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (!t.isEmpty()) { unsupported.put("mode", JsonString(t)) }
                case None => ()
            }
            unsupported.put("compatNote", JsonString("Supported actions are status, list, add, update, remove, path, help, run, runs, and wake."))
            let out = unsupported.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let (msg, code) = gatewayExecuteCronWithUnifiedRun(args.toArray())
        let result = JsonObject()
        result.put("ok", (code == 0).toJsonValue())
        result.put("action", JsonString(act))
        result.put("status", JsonString(if (code == 0) { "ok" } else { "error" }))
        result.put("exitCode", code.toJsonValue())
        result.put("output", JsonString(msg))
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Metis-compatible message tool. Supports action=send, reply, thread, reaction, poll, delete, edit, pin, unpin, topic-create, topic-edit, photo, document, audio, voice, video, and video-note for Gateway-backed channels.",
        parameters: {
            action: "Message action. Supported now: send, reply, thread, reaction, poll, delete, edit, pin, unpin, topic-create, topic-edit, photo, document, audio, voice, video, video-note.",
            channel: "Gateway channel id, such as feishu or qq.",
            to: "Target peer/chat id.",
            message: "Message text to send.",
            replyTo: "Reply target message id for action=reply.",
            threadId: "Thread root or anchor message id for action=thread.",
            reaction: "For action=reaction, the reaction token or short text to send, such as +1, thumbs_up, or acknowledged.",
            poll: "For action=poll, a pipe-delimited poll payload such as 'Lunch?|Rice|Noodles|Salad'. It is encoded into a structured text payload.",
            caption: "Optional caption for media actions.",
            forceDocument: "When true for Telegram media, route image/GIF media through document payload.",
            durationSeconds: "Optional Telegram poll duration in seconds, 5-600.",
            allowMultiselect: "Optional Telegram poll multi-select flag.",
            isAnonymous: "Optional Telegram poll anonymous flag."
        }
    ]
    public func message(
        action: String,
        channel: Option<String>,
        to: Option<String>,
        message: Option<String>,
        replyTo: Option<String>,
        threadId: Option<String>,
        reaction: Option<String>,
        poll: Option<String>,
        caption: Option<String>,
        forceDocument: Option<Bool>,
        durationSeconds: Option<Int64>,
        allowMultiselect: Option<Bool>,
        isAnonymous: Option<Bool>
    ): String {
        let act = action.trimAscii().toAsciiLower()
        PrintUtils.printTool("message", shortMessage: act)

        if (act == "send" || act == "reply" || act == "thread" || act == "reaction" || act == "poll" || act == "delete" || act == "edit" || act == "pin" || act == "unpin" || act == "topic-create" || act == "topic-edit" || act == "photo" || act == "document" || act == "audio" || act == "voice" || act == "video" || act == "video-note") {
            let ch = match (channel) {
                case Some(v) => v.trimAscii().toAsciiLower()
                case None => ""
            }
            let target = match (to) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            var text = match (message) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            var payloadKind = "text"
            if (act == "reaction") {
                payloadKind = "reaction"
                text = match (reaction) {
                    case Some(v) =>
                        let t = v.trimAscii()
                        if (t.isEmpty()) { "" } else { renderGatewayReactionText(t) }
                    case None => ""
                }
            } else if (act == "poll") {
                payloadKind = "poll"
                text = renderGatewayPollTextAdvanced(match (poll) {
                    case Some(v) => v
                    case None => ""
                }, durationSeconds: durationSeconds, allowMultiselect: allowMultiselect, isAnonymous: isAnonymous)
            } else if (act == "delete") {
                payloadKind = "delete"
                text = renderGatewayDeleteText()
            } else if (act == "pin") {
                payloadKind = "pin"
                text = renderGatewayPinText()
            } else if (act == "unpin") {
                payloadKind = "unpin"
                text = renderGatewayUnpinText()
            } else if (act == "edit") {
                payloadKind = "edit"
                text = renderGatewayEditText(text)
            } else if (act == "topic-create") {
                payloadKind = "topic-create"
                text = renderGatewayTopicCreateText(text)
            } else if (act == "topic-edit") {
                payloadKind = "topic-edit"
                text = renderGatewayTopicEditText(text)
            } else if (act == "photo") {
                payloadKind = "photo"
                text = if (match (forceDocument) { case Some(v) => v case None => false }) {
                    renderGatewayDocumentText(text, caption: match (caption) { case Some(v) => v case None => "" })
                } else {
                    renderGatewayPhotoText(text, caption: match (caption) { case Some(v) => v case None => "" })
                }
            } else if (act == "document") {
                payloadKind = "document"
                text = renderGatewayDocumentText(text, caption: match (caption) { case Some(v) => v case None => "" })
            } else if (act == "audio") {
                payloadKind = "audio"
                text = renderGatewayAudioText(text, caption: match (caption) { case Some(v) => v case None => "" })
            } else if (act == "voice") {
                payloadKind = "voice"
                text = renderGatewayVoiceText(text, caption: match (caption) { case Some(v) => v case None => "" })
            } else if (act == "video") {
                payloadKind = "video"
                text = renderGatewayVideoText(text, caption: match (caption) { case Some(v) => v case None => "" })
            } else if (act == "video-note") {
                payloadKind = "video-note"
                text = renderGatewayVideoNoteText(text)
            } else if (act == "reply" || act == "thread") {
                payloadKind = "threaded-text"
            }
            if (ch.isEmpty() || target.isEmpty() || text.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString(act))
                err.put("error", JsonString(if (act == "reaction") {
                    "reaction requires channel, to, and reaction"
                } else if (act == "poll") {
                    "poll requires channel, to, and poll"
                } else if (act == "delete" || act == "pin" || act == "unpin") {
                    "${act} requires channel and to"
                } else {
                    "${act} requires channel, to, and message"
                }))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }

            let replyAnchor = if (act == "reply" || act == "edit" || act == "delete" || act == "pin" || act == "unpin" || act == "topic-edit") {
                match (replyTo) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
            } else if (act == "thread") {
                match (threadId) {
                    case Some(v) => v.trimAscii()
                    case None => ""
                }
            } else {
                ""
            }
            if ((act == "reply" || act == "thread" || act == "edit" || act == "delete" || act == "pin" || act == "unpin" || act == "topic-edit") && replyAnchor.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString(act))
                err.put("error", JsonString(
                    if (act == "reply") {
                        "reply requires replyTo"
                    } else if (act == "thread") {
                        "thread requires threadId"
                    } else if (act == "edit") {
                        "edit requires replyTo"
                    } else if (act == "topic-edit") {
                        "topic-edit requires replyTo"
                    } else if (act == "pin" || act == "unpin") {
                        "${act} requires replyTo"
                    } else {
                        "delete requires replyTo"
                    }
                ))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }

            let sent = this.sendGatewayText(
                ch,
                target,
                text,
                replyToMessageId: if (replyAnchor.isEmpty()) { None } else { Some(replyAnchor) }
            )
            let result = JsonObject()
            result.put("ok", sent.toJsonValue())
            result.put("status", JsonString(if (sent) { "accepted" } else { "error" }))
            result.put("action", JsonString(act))
            result.put("channel", JsonString(ch))
            result.put("to", JsonString(target))
            result.put("message", JsonString(text))
            result.put("payloadKind", JsonString(payloadKind))
            result.put("payloadPreview", JsonString(gatewayMessagePayloadPreview(text)))
            if (!replyAnchor.isEmpty()) {
                if (act == "reply") {
                    result.put("replyTo", JsonString(replyAnchor))
                } else {
                    result.put("threadId", JsonString(replyAnchor))
                }
            }
            if (act == "reaction") {
                match (reaction) {
                    case Some(v) =>
                        let t = v.trimAscii()
                        if (!t.isEmpty()) { result.put("reaction", JsonString(t)) }
                    case None => ()
                }
            }
            if (act == "poll") {
                match (poll) {
                    case Some(v) =>
                        let t = v.trimAscii()
                        if (!t.isEmpty()) {
                            result.put("poll", JsonString(t))
                            let parsed = parseGatewayPollParts(t)
                            if (!parsed[0].isEmpty()) {
                                result.put("pollTitle", JsonString(parsed[0]))
                            }
                            let options = JsonArray([])
                            for (option in parsed[1]) {
                                options.add(JsonString(option))
                            }
                            result.put("pollOptions", options)
                        }
                    case None => ()
                }
            }
            result.put("compatNote", JsonString("The message tool sends text through the project's GatewayService. reply/thread reuse the gateway replyToMessageId path; reaction/poll are encoded as structured text payloads for channels without native rich interaction support."))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let unsupported = JsonObject()
        unsupported.put("ok", false.toJsonValue())
        unsupported.put("status", JsonString("unsupported"))
        unsupported.put("action", JsonString(act))
        unsupported.put("error", JsonString("Unsupported message action in current local implementation: ${act}"))
        match (replyTo) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("replyTo", JsonString(t)) }
            case None => ()
        }
        match (threadId) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("threadId", JsonString(t)) }
            case None => ()
        }
        match (reaction) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("reaction", JsonString(t)) }
            case None => ()
        }
        match (poll) {
            case Some(v) =>
                let t = v.trimAscii()
                if (!t.isEmpty()) { unsupported.put("poll", JsonString(t)) }
            case None => ()
        }
        unsupported.put("compatNote", JsonString("Supported actions are send, reply, thread, reaction, poll, edit, delete, and telegram inline-keyboard payloads."))
        let out = unsupported.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Metis-compatible subagents tool. Manages spawned local sessions created by sessions_spawn: list them, steer them by launching a new background turn using the recorded runtime, or kill them by requesting cancellation and deleting the persisted session transcript.",
        parameters: {
            action: "Subagent action. Supported now: list, steer, kill.",
            target: "Optional session key or substring when steering/killing one spawned subagent. Use all or * to target every managed spawned session for kill.",
            message: "Required for steer. Appended as a new user message to the target spawned session transcript.",
            recentMinutes: "Optional recency hint. Current implementation does not filter by recency."
        }
    ]
    public func subagents(
        action: Option<String>,
        target: Option<String>,
        message: Option<String>,
        recentMinutes: Option<Int64>
    ): String {
        let act = match (action) {
            case Some(v) =>
                let t = v.trimAscii().toAsciiLower()
                if (t.isEmpty()) { "list" } else { t }
            case None => "list"
        }
        PrintUtils.printTool("subagents", shortMessage: act)

        if (act == "list") {
            let sessions = JsonArray([])
            var count: Int64 = 0
            for (sessionKey in this.listManagedSpawnSessions()) {
                let row = JsonObject()
                match (gatewaySubagentFindRunBySessionKey(this.gwStore().sessionsRoot(), sessionKey)) {
                    case Some(record) =>
                        let runId = gatewaySubagentRunRecordString(record, "runId")
                        if (!runId.isEmpty()) {
                            row.put("runId", JsonString(runId))
                        }
                        let persistedStatus = gatewaySubagentRunRecordString(record, "status")
                        if (!persistedStatus.isEmpty()) {
                            row.put("status", JsonString(persistedStatus))
                        }
                    case None => row.put("runId", JsonString(sessionKey))
                }
                row.put("sessionKey", JsonString(sessionKey))
                row.put("transcriptPath", JsonString(this.gwStore().transcriptPath(sessionKey).toString()))
                row.put("runtime", JsonString(this.managedSubagentRuntime(sessionKey)))
                let subagentId = this.managedSubagentAgentId(sessionKey)
                let subagentState = this.managedSubagentState(sessionKey)
                if (!subagentId.isEmpty()) {
                    row.put("agentId", JsonString(subagentId))
                }
                if (!subagentState.isEmpty()) {
                    row.put("state", JsonString(subagentState))
                }
                row.put("hasLiveFuture", this.managedSubagentHasLiveFuture(sessionKey).toJsonValue())
                row.put("hasLiveProcess", this.managedSubagentHasLiveProcess(sessionKey).toJsonValue())
                let cwdHint = this.managedSubagentCwd(sessionKey)
                if (!cwdHint.isEmpty()) {
                    row.put("cwd", JsonString(cwdHint))
                }
                let modelText = this.managedSpawnModel(sessionKey)
                if (!modelText.isEmpty()) {
                    row.put("model", JsonString(modelText))
                }
                let thinkingText = this.managedSpawnThinking(sessionKey)
                if (!thinkingText.isEmpty()) {
                    row.put("thinking", JsonString(thinkingText))
                }
                let resumeText = this.managedSpawnResumeSessionId(sessionKey)
                if (!resumeText.isEmpty()) {
                    row.put("resumeSessionId", JsonString(resumeText))
                }
                let modeText = this.managedSpawnMode(sessionKey)
                if (!modeText.isEmpty()) {
                    row.put("mode", JsonString(modeText))
                }
                let cleanupText = this.managedSpawnCleanup(sessionKey)
                if (!cleanupText.isEmpty()) {
                    row.put("cleanup", JsonString(cleanupText))
                }
                let sandboxText = this.managedSpawnSandbox(sessionKey)
                if (!sandboxText.isEmpty()) {
                    row.put("sandbox", JsonString(sandboxText))
                }
                let streamText = this.managedSpawnStreamTo(sessionKey)
                if (!streamText.isEmpty()) {
                    row.put("streamTo", JsonString(streamText))
                }
                let threadText = this.managedSpawnThread(sessionKey)
                if (!threadText.isEmpty()) {
                    row.put("thread", JsonString(threadText))
                }
                let timeoutText = this.managedSpawnTimeoutSeconds(sessionKey)
                if (!timeoutText.isEmpty()) {
                    row.put("timeoutSeconds", JsonString(timeoutText))
                }
                if (this.managedSubagentRuntime(sessionKey) == "acp") {
                    let requestedHarness = if (subagentId.isEmpty()) { "codex" } else { subagentId }
                    let effectiveHarness = match (requestedHarness.trimAscii().toAsciiLower()) {
                        case "" | "codex" | "codex-cli" => "codex"
                        case "claude" | "claude-code" => "claude"
                        case "gemini" | "gemini-cli" => "gemini"
                        case "cursor" | "cursor-agent" | "cursor_cli" => "cursor-agent"
                        case _ => if (requestedHarness.trimAscii().toAsciiLower().startsWith("cmd:")) { "custom-cmd" } else if (requestedHarness.contains(" ")) { "custom-shell" } else { requestedHarness }
                    }
                    row.put("effectiveHarness", JsonString(effectiveHarness))
                    row.put("effectiveMode", JsonString(this.acpEffectiveMode(modeText)))
                    row.put("effectiveSandbox", JsonString(this.acpEffectiveSandbox(sandboxText)))
                    row.put(
                        "effectiveSessionPersistence",
                        JsonString(this.acpEffectiveSessionPersistence(modeText, threadText.trimAscii().toAsciiLower() == "true"))
                    )
                }
                sessions.add(row)
                count += 1
            }
            let result = JsonObject()
            result.put("ok", true.toJsonValue())
            result.put("status", JsonString("ok"))
            result.put("action", JsonString("list"))
            result.put("total", count.toJsonValue())
            result.put("activeCount", count.toJsonValue())
            result.put("active", sessions)
            result.put("sessions", sessions)
            if (let Some(v) <- recentMinutes) {
                if (v > 0) {
                    result.put("compatNote", JsonString("recentMinutes=${v} was provided, but subagents list does not currently filter by recency."))
                }
            }
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "status" || act == "poll" || act == "logs") {
            let tgt = match (target) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            let recordOpt = gatewaySubagentResolveRunRecord(this.gwStore().sessionsRoot(), tgt)
            let resolved = match (recordOpt) {
                case Some(record) => gatewaySubagentRunRecordString(record, "sessionKey")
                case None => this.resolveManagedSpawnTarget(tgt)
            }
            if (resolved.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString(act))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("Unknown subagent target."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let record = match (recordOpt) {
                case Some(value) => value
                case None =>
                    match (gatewaySubagentFindRunBySessionKey(this.gwStore().sessionsRoot(), resolved)) {
                        case Some(value) => value
                        case None => JsonObject()
                    }
            }
            if (act == "logs") {
                let result = JsonObject()
                result.put("ok", true.toJsonValue())
                result.put("status", JsonString("ok"))
                result.put("action", JsonString("logs"))
                result.put("runId", JsonString(if (gatewaySubagentRunRecordString(record, "runId").isEmpty()) { resolved } else { gatewaySubagentRunRecordString(record, "runId") }))
                result.put("sessionKey", JsonString(resolved))
                result.put("logs", JsonString(this.gwStore().formatHistoryAsText(resolved, 40)))
                let out = result.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let result = JsonObject()
            result.put("ok", true.toJsonValue())
            result.put("status", JsonString("ok"))
            result.put("action", JsonString(act))
            if (!gatewaySubagentRunRecordString(record, "runId").isEmpty()) {
                result.put("run", record)
                result.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
            }
            result.put("sessionKey", JsonString(resolved))
            result.put("runtime", JsonString(this.managedSubagentRuntime(resolved)))
            result.put("agentId", JsonString(this.managedSubagentAgentId(resolved)))
            result.put("state", JsonString(this.managedSubagentState(resolved)))
            result.put("hasLiveFuture", this.managedSubagentHasLiveFuture(resolved).toJsonValue())
            result.put("hasLiveProcess", this.managedSubagentHasLiveProcess(resolved).toJsonValue())
            result.put("transcriptPath", JsonString(this.gwStore().transcriptPath(resolved).toString()))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "steer") {
            let tgt = match (target) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            let msg = match (message) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            if (tgt.isEmpty() || msg.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString("steer"))
                err.put("error", JsonString("steer requires target and message"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let resolved = this.resolveManagedSpawnTarget(tgt)
            if (resolved.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString("steer"))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("Unknown subagent target."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let agentIdText = this.managedSubagentAgentId(resolved)
            let runtimeText = this.managedSubagentRuntime(resolved)
            if (agentIdText.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString("steer"))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("The target subagent has no recorded agentId and cannot be steered yet."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            this.gwStore().appendTranscriptEntry(resolved, "user", msg)
            let launched = this.launchManagedSessionTurn(resolved, msg)
            let result = JsonObject()
            result.put("ok", launched.toJsonValue())
            result.put("status", JsonString(if (launched) { "accepted" } else { "busy" }))
            result.put("action", JsonString("steer"))
            result.put("runId", JsonString(resolved))
            result.put("target", JsonString(tgt))
            result.put("sessionKey", JsonString(resolved))
            result.put("runtime", JsonString(runtimeText))
            result.put("agentId", JsonString(agentIdText))
            result.put("message", JsonString(msg))
            result.put("text", JsonString(if (launched) { "steered ${resolved}" } else { "subagent ${resolved} is already queued or running" }))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "kill") {
            let tgt = match (target) {
                case Some(v) => v.trimAscii()
                case None => ""
            }
            if (tgt == "all" || tgt == "*") {
                let killed = JsonArray([])
                var count: Int64 = 0
                for (sessionKey in this.listManagedSpawnSessions()) {
                    let snapshot = this.managedSubagentKillSnapshot(sessionKey)
                    let priorState = snapshot[0]
                    let hadFuture = snapshot[1]
                    let hadProcess = snapshot[2]
                    this.markManagedSessionKillRequested(sessionKey, "all")
                    let _cancelled = this.cancelManagedSubagent(sessionKey)
                    if (this.gwStore().deleteSession(sessionKey)) {
                        this.forgetManagedSubagent(sessionKey)
                        let row = JsonObject()
                        row.put("sessionKey", JsonString(sessionKey))
                        if (!priorState.isEmpty()) {
                            row.put("priorState", JsonString(priorState))
                        }
                        row.put("hadLiveFuture", hadFuture.toJsonValue())
                        row.put("hadLiveProcess", hadProcess.toJsonValue())
                        killed.add(row)
                        count += 1
                    }
                }
                let result = JsonObject()
                result.put("ok", true.toJsonValue())
                result.put("status", JsonString("ok"))
                result.put("action", JsonString("kill"))
                result.put("target", JsonString("all"))
                result.put("killed", count.toJsonValue())
                result.put("sessions", killed)
                let out = result.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }

            let resolved = this.resolveManagedSpawnTarget(tgt)
            if (resolved.isEmpty()) {
                let err = JsonObject()
                err.put("ok", false.toJsonValue())
                err.put("status", JsonString("error"))
                err.put("action", JsonString("kill"))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("Unknown subagent target."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let snapshot = this.managedSubagentKillSnapshot(resolved)
            let priorState = snapshot[0]
            let hadFuture = snapshot[1]
            let hadProcess = snapshot[2]
            this.markManagedSessionKillRequested(resolved, tgt)
            let cancelled = this.cancelManagedSubagent(resolved)
            let deleted = this.gwStore().deleteSession(resolved)
            if (deleted) {
                this.forgetManagedSubagent(resolved)
            }
            let result = JsonObject()
            result.put("ok", deleted.toJsonValue())
            result.put("status", JsonString(if (deleted) { "ok" } else { "error" }))
            result.put("action", JsonString("kill"))
            result.put("target", JsonString(tgt))
            result.put("runId", JsonString(resolved))
            result.put("sessionKey", JsonString(resolved))
            result.put("cancelRequested", cancelled.toJsonValue())
            if (!priorState.isEmpty()) {
                result.put("priorState", JsonString(priorState))
            }
            result.put("hadLiveFuture", hadFuture.toJsonValue())
            result.put("hadLiveProcess", hadProcess.toJsonValue())
            result.put("text", JsonString(if (deleted) { "killed ${resolved}" } else { "failed to kill ${resolved}" }))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let unsupported = JsonObject()
        unsupported.put("ok", false.toJsonValue())
        unsupported.put("action", JsonString(act))
        unsupported.put("status", JsonString("error"))
        unsupported.put("error", JsonString("Unsupported action."))
        let out = unsupported.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }
}
