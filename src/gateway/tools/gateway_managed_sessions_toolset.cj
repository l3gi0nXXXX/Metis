package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.config.{CliConfig, CliSettingManager}
import metis.core.memory.{MemorySessionTranscriptStore, memorySessionStoreForGatewayUser}
import metis.core.{GatewaySubagentAgentSpec, gatewayCurrentToolRuntimeContext, gatewaySubagentBuildBuiltinPrompt, gatewaySubagentBuildContextPrompt, gatewaySubagentBuildCustomPrompt, gatewaySubagentControllerCanAccessRun, gatewaySubagentCreateRunRecord, gatewaySubagentEvaluateSpawnPolicy, gatewaySubagentFindRunBySessionKey, gatewaySubagentIsBuiltinAgent, gatewaySubagentListRunRecords, gatewaySubagentMarkRunCancelled, gatewaySubagentMarkRunState, gatewaySubagentMarkRunTimedOut, gatewaySubagentNormalizeBuiltinAgentId, gatewaySubagentNormalizeCleanupMode, gatewaySubagentNormalizeContextMode, gatewaySubagentNormalizeIsolationMode, gatewaySubagentNormalizeSandboxMode, gatewaySubagentNoticeShouldDeliver, gatewaySubagentNoticeTargetSession, gatewaySubagentPolicyDecisionToJson, gatewaySubagentPolicyRejectionJson, gatewaySubagentRenderNotice, gatewaySubagentResolveAgent, gatewaySubagentResolveRunRecord, gatewaySubagentRunMatchesControlFilter, gatewaySubagentRunRecordInt, gatewaySubagentRunRecordString, gatewaySubagentRunStatusIsTerminal, gatewaySubagentUpdateNoticeStatus, gatewaySubagentWriteRunRecord}
import metis.io.PrintUtils

import std.collection.{ArrayList, HashMap}
import std.convert.Parsable
import std.core.Duration
import std.fs.{Directory, File, OpenMode, Path, exists, remove}
import std.io.StringReader
import std.process.*
import std.sync.Mutex

import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString, JsonValue}

private let gatewayManagedSessionLock = Mutex()
private var gatewayManagedAgentIds = HashMap<String, String>()
private var gatewayManagedStates = HashMap<String, String>()
private var gatewayManagedFutures = HashMap<String, Future<Unit>>()
private var gatewayManagedProcesses = HashMap<String, SubProcess>()

private class GatewayManagedWorkspaceSpec {
    public var ok: Bool = true
    public var isolationMode: String = "shared"
    public var cwd: String = ""
    public var worktreePath: String = ""
    public var sandbox: String = "inherit"
    public var cleanupMode: String = "keep"
    public var error: String = ""

    public init() {}
}

@toolset
public class GatewayManagedSessionsToolset {
    private func gwStore(): MemorySessionTranscriptStore {
        memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
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
        String.join(parts.toArray(), delimiter: "-")
    }

    private func normalizeManagedAgentId(agentId: String): String {
        gatewaySubagentNormalizeBuiltinAgentId(agentId)
    }

    private func safeWorkspaceStem(raw: String): String {
        var s = raw.trimAscii()
        let bad = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*", "\r", "\n", "\t", " "]
        for (b in bad) {
            s = s.replace(b, "_")
        }
        if (s.size > 80) {
            s = s[0..80]
        }
        if (s.isEmpty()) {
            return "subagent"
        }
        s
    }

    private func ensureManagedDir(path: Path): Unit {
        if (!exists(path)) {
            Directory.create(path, recursive: true)
        }
    }

    private func createManagedWorktree(sessionKey: String, sourceDir: Path): (Bool, String, String) {
        let root = CliConfig.dotDir.join("subagents").join("worktrees")
        this.ensureManagedDir(root)
        let worktree = root.join(this.safeWorkspaceStem(sessionKey))
        if (exists(worktree)) {
            return (true, worktree.toString(), "")
        }
        try {
            let process = launch(
                "git",
                ["-C", sourceDir.toString(), "worktree", "add", "--detach", worktree.toString(), "HEAD"],
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe,
                workingDirectory: Some(sourceDir)
            )
            let stdoutFuture = spawn {
                let reader = StringReader(process.stdOutPipe)
                try { reader.readToEnd() } catch (_: Exception) { "" }
            }
            let stderrFuture = spawn {
                let reader = StringReader(process.stdErrPipe)
                try { reader.readToEnd() } catch (_: Exception) { "" }
            }
            let exitCode = process.wait(timeout: Duration.second * 60)
            let stdout = try { stdoutFuture.get() } catch (_: Exception) { "" }
            let stderr = try { stderrFuture.get() } catch (_: Exception) { "" }
            if (exitCode == 0) {
                return (true, worktree.toString(), "")
            }
            return (false, worktree.toString(), "git worktree add failed: exitCode=${exitCode}; ${stderr.trimAscii()} ${stdout.trimAscii()}".trimAscii())
        } catch (e: Exception) {
            return (false, worktree.toString(), "git worktree add failed: ${e.message}")
        }
    }

    private func prepareManagedWorkspace(
        sessionKey: String,
        cwdHint: String,
        isolation: String,
        cleanup: String,
        sandbox: String
    ): GatewayManagedWorkspaceSpec {
        let spec = GatewayManagedWorkspaceSpec()
        spec.isolationMode = gatewaySubagentNormalizeIsolationMode(isolation)
        spec.cleanupMode = gatewaySubagentNormalizeCleanupMode(cleanup)
        spec.sandbox = gatewaySubagentNormalizeSandboxMode(sandbox)
        let hinted = cwdHint.trimAscii()
        let source = if (hinted.isEmpty()) { CliConfig.cwd } else { Path(hinted) }

        if (spec.isolationMode == "shared") {
            spec.cwd = CliConfig.cwd.toString()
            return spec
        }
        if (spec.isolationMode == "cwd") {
            if (!exists(source)) {
                spec.ok = false
                spec.error = "cwd isolation path does not exist: ${source.toString()}"
                return spec
            }
            spec.cwd = source.toString()
            return spec
        }

        if (!exists(source)) {
            spec.ok = false
            spec.error = "worktree source path does not exist: ${source.toString()}"
            return spec
        }
        let created = this.createManagedWorktree(sessionKey, source)
        if (!created[0]) {
            spec.ok = false
            spec.worktreePath = created[1]
            spec.error = created[2]
            return spec
        }
        spec.worktreePath = created[1]
        spec.cwd = created[1]
        spec
    }

    private func cleanupManagedWorkspace(spec: GatewayManagedWorkspaceSpec): Unit {
        if (spec.isolationMode != "worktree" || spec.cleanupMode != "delete" || spec.worktreePath.trimAscii().isEmpty()) {
            return
        }
        try {
            let process = launch(
                "git",
                ["worktree", "remove", "--force", spec.worktreePath],
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe,
                workingDirectory: Some(CliConfig.cwd)
            )
            let exitCode = process.wait(timeout: Duration.second * 60)
            if (exitCode != 0 && exists(Path(spec.worktreePath))) {
                try { remove(Path(spec.worktreePath), recursive: true) } catch (_inner: Exception) { () }
            }
        } catch (_: Exception) {
            try { remove(Path(spec.worktreePath), recursive: true) } catch (_inner: Exception) { () }
        }
    }

    private func supportsRealManagedSubagent(agentId: String): Bool {
        gatewaySubagentIsBuiltinAgent(agentId)
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
        ""
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
                ""
            case None => ""
        }
    }

    private func managedRuntime(sessionKey: String): String {
        let runtime = this.extractManagedSpawnMetadataField(sessionKey, "runtime").trimAscii().toAsciiLower()
        if (runtime.isEmpty()) {
            return "subagent"
        }
        runtime
    }

    private func managedAgentId(sessionKey: String): String {
        synchronized(gatewayManagedSessionLock) {
            if (let Some(v) <- gatewayManagedAgentIds.get(sessionKey)) {
                return v
            }
        }
        let runtime = this.managedRuntime(sessionKey)
        let agentId = this.extractManagedSpawnMetadataField(sessionKey, "agentId")
        if (runtime == "acp") {
            return agentId.trimAscii()
        }
        this.normalizeManagedAgentId(agentId)
    }

    private func managedCwd(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "cwd")
    }

    private func managedModel(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "model")
    }

    private func managedThinking(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "thinking")
    }

    private func managedResumeSessionId(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "resumeSessionId")
    }

    private func managedMode(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "mode")
    }

    private func managedCleanup(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "cleanup")
    }

    private func managedSandbox(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "sandbox")
    }

    private func managedStreamTo(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "streamTo")
    }

    private func managedThread(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "thread")
    }

    private func managedTimeoutSeconds(sessionKey: String): String {
        this.extractManagedSpawnMetadataField(sessionKey, "timeoutSeconds")
    }

    private func requesterThreadIdFromSessionKey(sessionKey: String): String {
        let marker = ":topic:"
        match (sessionKey.indexOf(marker)) {
            case Some(idx) => sessionKey[idx + marker.size..].trimAscii()
            case None => ""
        }
    }

    private func currentControllerSessionKey(): String {
        match (gatewayCurrentToolRuntimeContext()) {
            case Some(ctx) => ctx.sessionKey.trimAscii()
            case None => ""
        }
    }

    private func currentControllerIsPrivileged(): Bool {
        match (gatewayCurrentToolRuntimeContext()) {
            case Some(ctx) =>
                match (ctx.sourceLabel) {
                    case "cli" | "control-ui" | "dashboard" | "cron" => return true
                    case _ => ()
                }
                for (scope in ctx.operatorScopes) {
                    match (scope.trimAscii().toAsciiLower()) {
                        case "operator.admin" | "subagents.admin" | "gateway.admin" => return true
                        case _ => ()
                    }
                }
                false
            case None => true
        }
    }

    private func controllerCanAccessRun(record: JsonObject): Bool {
        gatewaySubagentControllerCanAccessRun(record, this.currentControllerSessionKey(), this.currentControllerIsPrivileged())
    }

    private func subagentControlDeniedJson(action: String, target: String): String {
        let err = JsonObject()
        err.put("ok", JsonBool(false))
        err.put("status", JsonString("denied"))
        err.put("action", JsonString(action))
        err.put("target", JsonString(target.trimAscii()))
        err.put("error", JsonString("Current session is not authorized to control this subagent run."))
        let out = err.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    private func resolveManagedRunForControl(target: String): Option<JsonObject> {
        let tgt = target.trimAscii()
        match (gatewaySubagentResolveRunRecord(this.gwStore().sessionsRoot(), tgt)) {
            case Some(record) => return Some(record)
            case None => ()
        }
        let resolved = this.resolveManagedSpawnTarget(tgt)
        if (resolved.isEmpty()) {
            return None<JsonObject>
        }
        gatewaySubagentFindRunBySessionKey(this.gwStore().sessionsRoot(), resolved)
    }

    private func managedRunMatchesListFilter(record: JsonObject, filter: String): Bool {
        gatewaySubagentRunMatchesControlFilter(record, filter, this.currentControllerSessionKey(), this.currentControllerIsPrivileged())
    }

    private func runRecordToManagedRow(record: JsonObject): JsonObject {
        let row = JsonObject()
        let sessionKey = gatewaySubagentRunRecordString(record, "sessionKey")
        row.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
        row.put("sessionKey", JsonString(sessionKey))
        row.put("status", JsonString(gatewaySubagentRunRecordString(record, "status")))
        row.put("runtime", JsonString(gatewaySubagentRunRecordString(record, "runtime")))
        row.put("agentId", JsonString(gatewaySubagentRunRecordString(record, "agentId")))
        row.put("requesterSessionKey", JsonString(gatewaySubagentRunRecordString(record, "requesterSessionKey")))
        row.put("noticeStatus", JsonString(gatewaySubagentRunRecordString(record, "noticeStatus")))
        row.put("hasLiveFuture", this.managedHasLiveFuture(sessionKey).toJsonValue())
        row.put("hasLiveProcess", this.managedHasLiveProcess(sessionKey).toJsonValue())
        row.put("transcriptPath", JsonString(this.gwStore().transcriptPath(sessionKey).toString()))
        row
    }

    private func managedState(sessionKey: String): String {
        synchronized(gatewayManagedSessionLock) {
            if (let Some(v) <- gatewayManagedStates.get(sessionKey)) {
                return v
            }
        }
        ""
    }

    private func managedHasLiveFuture(sessionKey: String): Bool {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedFutures.contains(sessionKey)
        }
    }

    private func managedHasLiveProcess(sessionKey: String): Bool {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedProcesses.contains(sessionKey)
        }
    }

    private func tryQueueManagedRun(sessionKey: String, agentId: String): Bool {
        let queued = synchronized(gatewayManagedSessionLock) {
            if (let Some(state) <- gatewayManagedStates.get(sessionKey)) {
                if (state == "queued" || state == "running") {
                    return false
                }
            }
            gatewayManagedAgentIds.add(sessionKey, agentId)
            gatewayManagedStates.add(sessionKey, "queued")
            true
        }
        if (queued) {
            let _ = gatewaySubagentMarkRunState(this.gwStore().sessionsRoot(), sessionKey, "queued")
        }
        queued
    }

    private func setManagedState(
        sessionKey: String,
        state: String,
        resultSummary!: String = "",
        error!: String = "",
        exitCode!: Int64 = 0,
        outputPath!: String = ""
    ): Unit {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedStates.add(sessionKey, state)
        }
        let _ = gatewaySubagentMarkRunState(
            this.gwStore().sessionsRoot(),
            sessionKey,
            state,
            resultSummary: resultSummary,
            error: error,
            exitCode: exitCode,
            outputPath: outputPath
        )
        if (gatewaySubagentRunStatusIsTerminal(state)) {
            this.deliverManagedTerminalNotice(sessionKey)
        }
    }

    private func deliverManagedTerminalNotice(sessionKey: String): Unit {
        let st = this.gwStore()
        let record = match (gatewaySubagentResolveRunRecord(st.sessionsRoot(), sessionKey)) {
            case Some(v) => v
            case None => return
        }
        if (!gatewaySubagentNoticeShouldDeliver(record)) {
            return
        }
        let notice = gatewaySubagentRenderNotice(record)
        let target = gatewaySubagentNoticeTargetSession(record)
        let effectiveTarget = if (target.trimAscii().isEmpty()) { sessionKey } else { target.trimAscii() }
        try {
            st.appendTranscriptEntry(effectiveTarget, "system", notice)
            let _ = gatewaySubagentUpdateNoticeStatus(st.sessionsRoot(), sessionKey, "delivered")
        } catch (e: Exception) {
            let _ = gatewaySubagentUpdateNoticeStatus(st.sessionsRoot(), sessionKey, "failed", error: e.message)
        }
    }

    private func buildManagedSubagentPrompt(
        task: String,
        cwdHint: String,
        sessionKey: String,
        agentId: String,
        agentSpec!: Option<GatewaySubagentAgentSpec> = None,
        contextMode!: String = "fresh",
        parentSessionKey!: String = "",
        parentHistory!: String = ""
    ): String {
        let effectiveCwd = if (cwdHint.trimAscii().isEmpty()) {
            CliConfig.cwd.toString()
        } else {
            cwdHint.trimAscii()
        }
        var basePrompt = ""
        match (agentSpec) {
            case Some(spec) =>
                if (spec.source == "custom") {
                    basePrompt = gatewaySubagentBuildCustomPrompt(task, effectiveCwd, sessionKey, spec)
                } else {
                    basePrompt = gatewaySubagentBuildBuiltinPrompt(task, effectiveCwd, sessionKey, agentId)
                }
            case None => basePrompt = gatewaySubagentBuildBuiltinPrompt(task, effectiveCwd, sessionKey, agentId)
        }
        gatewaySubagentBuildContextPrompt(basePrompt, contextMode, parentSessionKey, sessionKey, parentHistory)
    }

    private func managedParentContextHistory(contextMode: String, parentSessionKey: String): String {
        let mode = gatewaySubagentNormalizeContextMode(contextMode)
        let parent = parentSessionKey.trimAscii()
        if (mode == "fresh" || parent.isEmpty()) {
            return ""
        }
        let maxEntries: Int64 = if (mode == "fork") { 200 } else { 30 }
        this.gwStore().formatHistoryAsText(parent, maxEntries)
    }

    private func setManagedFuture(sessionKey: String, future: Future<Unit>): Unit {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedFutures.add(sessionKey, future)
        }
    }

    private func clearManagedFuture(sessionKey: String): Unit {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedFutures.remove(sessionKey)
        }
    }

    private func setManagedProcess(sessionKey: String, process: SubProcess): Unit {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedProcesses.add(sessionKey, process)
        }
    }

    private func clearManagedProcess(sessionKey: String): Unit {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedProcesses.remove(sessionKey)
        }
    }

    private func forgetManagedSession(sessionKey: String): Unit {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedAgentIds.remove(sessionKey)
            gatewayManagedStates.remove(sessionKey)
            gatewayManagedFutures.remove(sessionKey)
            gatewayManagedProcesses.remove(sessionKey)
        }
    }

    private func managedKillSnapshot(sessionKey: String): (String, Bool, Bool) {
        synchronized(gatewayManagedSessionLock) {
            let state = match (gatewayManagedStates.get(sessionKey)) {
                case Some(v) => v
                case None => ""
            }
            let hasFuture = gatewayManagedFutures.contains(sessionKey)
            let hasProcess = gatewayManagedProcesses.contains(sessionKey)
            (state, hasFuture, hasProcess)
        }
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
        path
    }

    private func internalSubagentCommandSpec(
        sessionKey: String,
        agentId: String,
        task: String,
        cwdHint: String,
        agentDir!: String = "",
        modelHint!: String = ""
    ): (String, Array<String>, Path) {
        let effectiveCwd = if (cwdHint.trimAscii().isEmpty()) { CliConfig.cwd } else { Path(cwdHint.trimAscii()) }
        let promptFile = this.internalSubagentPromptFile(sessionKey, task)
        let args = ArrayList<String>()
        args.add("run")
        args.add("--skip-build")
        args.add("--name")
        args.add("metis")
        let runArgs = ArrayList<String>()
        if (!agentDir.trimAscii().isEmpty()) {
            runArgs.add("--language")
            runArgs.add("agent:${agentDir.trimAscii()}")
        } else {
            runArgs.add("--internal-subagent")
            runArgs.add(agentId)
        }
        runArgs.add("--prompt-file")
        runArgs.add(promptFile.toString())
        runArgs.add("--output-format")
        runArgs.add("plain")
        if (agentDir.trimAscii().isEmpty() && !CliConfig.language.trimAscii().isEmpty()) {
            runArgs.add("--language")
            runArgs.add(CliConfig.language)
        }
        let effectiveModel = if (!modelHint.trimAscii().isEmpty()) { modelHint.trimAscii() } else { CliConfig.model.trimAscii() }
        if (!effectiveModel.isEmpty()) {
            runArgs.add("--model")
            runArgs.add(effectiveModel)
        }
        args.add("--run-args")
        args.add(String.join(runArgs.toArray(), delimiter: " "))
        ("cjpm", args.toArray(), effectiveCwd)
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
        let effectiveCwd = if (cwdHint.trimAscii().isEmpty()) { CliConfig.cwd.toString() } else { cwdHint.trimAscii() }
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
        let normalizedSandbox = this.acpEffectiveSandbox(sandbox)
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
        (args.toArray(), false, agentId.trimAscii())
    }

    private func maybeDeleteManagedSessionAfterRun(sessionKey: String): Unit {
        if (this.managedCleanup(sessionKey).trimAscii().toAsciiLower() == "delete-session") {
            let _ = this.gwStore().deleteSession(sessionKey)
            this.forgetManagedSession(sessionKey)
        }
    }

    private func cancelManagedSession(sessionKey: String): Bool {
        synchronized(gatewayManagedSessionLock) {
            var cancelled = false
            if (let Some(process) <- gatewayManagedProcesses.get(sessionKey)) {
                try {
                    process.terminate(force: true)
                    cancelled = true
                } catch (_: Exception) {
                    ()
                }
            }
            if (let Some(future) <- gatewayManagedFutures.get(sessionKey)) {
                future.cancel()
                gatewayManagedStates.add(sessionKey, "cancelling")
                let _ = gatewaySubagentMarkRunCancelled(this.gwStore().sessionsRoot(), sessionKey, reason: "cancel requested")
                return true
            }
            if (cancelled) {
                gatewayManagedStates.add(sessionKey, "cancelling")
                let _ = gatewaySubagentMarkRunCancelled(this.gwStore().sessionsRoot(), sessionKey, reason: "process terminated")
            }
            cancelled
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

    private func launchManagedAcpRun(
        sessionKey: String,
        harnessId: String,
        task: String,
        cwdHint: String,
        model: Option<String>,
        thinking: Option<String>,
        resumeSessionId: Option<String>,
        runTimeoutSeconds: Int64,
        mode: String,
        sandbox: String,
        thread: Bool
    ): Bool {
        let normalizedHarness = if (harnessId.trimAscii().isEmpty()) { "codex" } else { harnessId.trimAscii() }
        if (!this.tryQueueManagedRun(sessionKey, "acp:${normalizedHarness}")) {
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
        let timeout = if (runTimeoutSeconds > 0) { Some(Duration.second * runTimeoutSeconds) } else { None<Duration> }
        let st = this.gwStore()
        st.appendTranscriptEntry(
            sessionKey,
            "system",
            "acp dispatch accepted: harness=${resolvedHarness}, mode=${effectiveMode}, sandbox=${effectiveSandbox}, sessionPersistence=${effectiveSessionPersistence}"
        )
        let future = spawn {
            this.setManagedState(sessionKey, "running")
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
                this.setManagedProcess(sessionKey, process)
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
                }
                if (!stderr.trimAscii().isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp stderr: ${stderr.trimAscii()}")
                }
                let outputPath = st.transcriptPath(sessionKey).toString()
                if (timedOut) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp timed out: harness=${resolvedHarness} timeoutSeconds=${runTimeoutSeconds}")
                    this.setManagedState(sessionKey, "timed_out", error: "subagent timed out after ${runTimeoutSeconds}s", exitCode: -1, outputPath: outputPath)
                } else if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp cancelled")
                    this.setManagedState(sessionKey, "cancelled", error: "cancelled", outputPath: outputPath)
                } else if (exitCode == 0) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp completed: harness=${resolvedHarness} exitCode=${exitCode}")
                    this.setManagedState(sessionKey, "succeeded", resultSummary: if (stdout.trimAscii().isEmpty()) { "acp completed" } else { stdout.trimAscii() }, exitCode: exitCode, outputPath: outputPath)
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "acp failed: harness=${resolvedHarness} exitCode=${exitCode}")
                    this.setManagedState(sessionKey, "failed", error: "acp failed: harness=${resolvedHarness} exitCode=${exitCode}", exitCode: exitCode, outputPath: outputPath)
                }
            } catch (e: Exception) {
                let outputPath = st.transcriptPath(sessionKey).toString()
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp cancelled")
                    this.setManagedState(sessionKey, "cancelled", error: "cancelled", outputPath: outputPath)
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "acp failed: ${e.message}")
                    this.setManagedState(sessionKey, "failed", error: "acp failed: ${e.message}", exitCode: 1, outputPath: outputPath)
                }
            } finally {
                this.clearManagedProcess(sessionKey)
                this.clearManagedFuture(sessionKey)
                this.maybeDeleteManagedSessionAfterRun(sessionKey)
            }
        }
        this.setManagedFuture(sessionKey, future)
        true
    }

    private func launchManagedSubagentRun(
        sessionKey: String,
        agentId: String,
        task: String,
        cwdHint: String,
        runTimeoutSeconds!: Int64 = -1,
        agentSpec!: Option<GatewaySubagentAgentSpec> = None,
        contextMode!: String = "fresh",
        parentSessionKey!: String = "",
        parentHistory!: String = "",
        workspaceSpec!: Option<GatewayManagedWorkspaceSpec> = None
    ): Bool {
        let resolvedSpec = match (agentSpec) {
            case Some(spec) => spec
            case None => gatewaySubagentResolveAgent(agentId)
        }
        if (!resolvedSpec.found) {
            return false
        }
        let resolvedAgentId = resolvedSpec.agentId.trimAscii()
        if (!this.tryQueueManagedRun(sessionKey, resolvedAgentId)) {
            return false
        }
        let effectiveCwdHint = match (workspaceSpec) {
            case Some(spec) => if (spec.cwd.trimAscii().isEmpty()) { cwdHint } else { spec.cwd }
            case None => cwdHint
        }
        let prompt = this.buildManagedSubagentPrompt(
            task,
            effectiveCwdHint,
            sessionKey,
            resolvedAgentId,
            agentSpec: Some(resolvedSpec),
            contextMode: contextMode,
            parentSessionKey: parentSessionKey,
            parentHistory: parentHistory
        )
        let spec = this.internalSubagentCommandSpec(
            sessionKey,
            resolvedAgentId,
            prompt,
            effectiveCwdHint,
            agentDir: resolvedSpec.agentDir,
            modelHint: resolvedSpec.model
        )
        let command = spec[0]
        let args = spec[1]
        let workDir = spec[2]
        let st = this.gwStore()
        st.appendTranscriptEntry(sessionKey, "system", "subagent dispatch accepted: agentId=${resolvedAgentId}, source=${resolvedSpec.source}")
        let future = spawn {
            this.setManagedState(sessionKey, "running")
            st.appendTranscriptEntry(sessionKey, "system", "subagent started: agentId=${resolvedAgentId}, source=${resolvedSpec.source}")
            try {
                let process = launch(
                    command,
                    args,
                    stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe,
                    workingDirectory: Some(workDir)
                )
                this.setManagedProcess(sessionKey, process)
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
                let outputPath = st.transcriptPath(sessionKey).toString()
                if (timedOut) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent timed out: agentId=${resolvedAgentId} timeoutSeconds=${runTimeoutSeconds}")
                    this.setManagedState(sessionKey, "timed_out", error: "subagent timed out after ${runTimeoutSeconds}s", exitCode: -1, outputPath: outputPath)
                    return
                }
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent cancelled")
                    this.setManagedState(sessionKey, "cancelled", error: "cancelled", outputPath: outputPath)
                    return
                }
                if (!stderr.isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent stderr: ${stderr}")
                }
                if (exitCode == 0 && !content.isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "assistant", content)
                    st.appendTranscriptEntry(sessionKey, "system", "subagent completed: agentId=${resolvedAgentId}")
                    this.setManagedState(sessionKey, "succeeded", resultSummary: content, exitCode: exitCode, outputPath: outputPath)
                } else if (exitCode == 0) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent completed with empty response")
                    this.setManagedState(sessionKey, "succeeded", resultSummary: "subagent completed with empty response", exitCode: exitCode, outputPath: outputPath)
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent failed: agentId=${resolvedAgentId} exitCode=${exitCode}")
                    this.setManagedState(sessionKey, "failed", error: "subagent failed: agentId=${resolvedAgentId} exitCode=${exitCode}", exitCode: exitCode, outputPath: outputPath)
                }
            } catch (e: Exception) {
                let outputPath = st.transcriptPath(sessionKey).toString()
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent cancelled")
                    this.setManagedState(sessionKey, "cancelled", error: "cancelled", outputPath: outputPath)
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent failed: ${e.message}")
                    this.setManagedState(sessionKey, "failed", error: "subagent failed: ${e.message}", exitCode: 1, outputPath: outputPath)
                }
            } finally {
                match (workspaceSpec) {
                    case Some(ws) => this.cleanupManagedWorkspace(ws)
                    case None => ()
                }
                this.clearManagedProcess(sessionKey)
                this.clearManagedFuture(sessionKey)
                this.maybeDeleteManagedSessionAfterRun(sessionKey)
            }
        }
        this.setManagedFuture(sessionKey, future)
        true
    }

    private func launchManagedSessionTurn(sessionKey: String, task: String): Bool {
        let runtime = this.managedRuntime(sessionKey)
        let cwdHint = this.managedCwd(sessionKey)
        if (runtime == "acp") {
            let harnessId = this.managedAgentId(sessionKey)
            let modelText = this.managedModel(sessionKey)
            let thinkingText = this.managedThinking(sessionKey)
            let resumeText = this.managedResumeSessionId(sessionKey)
            return this.launchManagedAcpRun(
                sessionKey,
                if (harnessId.isEmpty()) { "codex" } else { harnessId },
                task,
                cwdHint,
                if (modelText.isEmpty()) { None } else { Some(modelText) },
                if (thinkingText.isEmpty()) { None } else { Some(thinkingText) },
                if (resumeText.isEmpty()) { None } else { Some(resumeText) },
                -1,
                this.managedMode(sessionKey),
                this.managedSandbox(sessionKey),
                this.managedThread(sessionKey).trimAscii().toAsciiLower() == "true"
            )
        }
        let agentId = this.managedAgentId(sessionKey)
        let timeoutText = this.managedTimeoutSeconds(sessionKey)
        let runTimeoutSeconds = try { Int64.parse(timeoutText) } catch (_: Exception) { -1 }
        this.launchManagedSubagentRun(sessionKey, agentId, task, cwdHint, runTimeoutSeconds: runTimeoutSeconds)
    }

    @tool[
        description: "Gateway main-runtime sessions_spawn tool. Creates a managed session, records spawn metadata, and can launch a background subagent or ACP harness run inside the Gateway process. Use this when the user naturally asks to start a subagent, run work in the background or in parallel, or notify the current session when finished. Return after the accepted response; completion is reported later by runtime notification.",
        parameters: {
            task: "Task or prompt for the spawned session. Include enough context for the background run to complete without blocking the current session.",
            label: "Optional label for the spawned session.",
            runtime: "Optional runtime hint: subagent or acp. Use subagent for Metis built-in/background agents.",
            agentId: "Optional target agent identifier hint. For runtime=acp this can be codex, claude, gemini, cursor-agent, or cmd:<shell-command-with-{task}>.",
            resumeSessionId: "Optional ACP resume session id hint forwarded to supported harnesses.",
            model: "Optional model override hint forwarded to ACP harnesses and stored in session metadata.",
            thinking: "Optional thinking override hint forwarded to supported ACP harnesses when available.",
            cwd: "Optional working directory hint used when launching the background run.",
            runTimeoutSeconds: "Optional run timeout hint.",
            timeoutSeconds: "Optional legacy timeout hint. Used only when runTimeoutSeconds is omitted.",
            contextMode: "Optional context inheritance mode for runtime=subagent: fresh, with_context, fork, or thread. Defaults to fresh.",
            isolation: "Optional workspace isolation mode for runtime=subagent: shared, cwd, or worktree. Defaults to shared.",
            thread: "Optional thread mode hint.",
            mode: "Optional spawn mode hint: run or session.",
            cleanup: "Optional cleanup hint: delete or keep.",
            sandbox: "Optional sandbox hint: inherit or require.",
            streamTo: "Optional stream target hint. Current gateway-managed implementation records it but does not fan out to external channels."
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
        contextMode: Option<String>,
        isolation: Option<String>,
        thread: Option<Bool>,
        mode: Option<String>,
        cleanup: Option<String>,
        sandbox: Option<String>,
        streamTo: Option<String>
    ): String {
        this.sessionsSpawnImpl(
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
            contextMode,
            isolation,
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
        contextMode: Option<String>,
        isolation: Option<String>,
        thread: Option<Bool>,
        mode: Option<String>,
        cleanup: Option<String>,
        sandbox: Option<String>,
        streamTo: Option<String>
    ): String {
        this.sessionsSpawnImpl(
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
            contextMode,
            isolation,
            thread,
            mode,
            cleanup,
            sandbox,
            streamTo
        )
    }

    @tool[
        description: "Gateway main-runtime sessions_batch_delegate tool. Delegates several tasks through sessions_spawn, returns one structured summary for the current turn, and keeps each accepted child as an independently trackable subagent run.",
        parameters: {
            tasks: "Task list to delegate. Empty task entries are reported as per-task failures and do not stop other tasks.",
            agentId: "Optional target agent identifier hint passed to each child spawn.",
            label: "Optional label prefix. Each child receives a stable numbered label derived from it.",
            maxWorkers: "Optional maximum number of child runs accepted from this batch. Extra valid tasks are returned as deferred.",
            perTaskTimeout: "Optional timeout in seconds applied to each child run. A value of 0 means immediate timeout for the child record.",
            runtime: "Optional runtime hint: subagent or acp. Defaults to subagent.",
            cwd: "Optional working directory hint passed to each child spawn.",
            contextMode: "Optional context inheritance mode for runtime=subagent: fresh, with_context, fork, or thread.",
            isolation: "Optional workspace isolation mode for runtime=subagent: shared, cwd, or worktree.",
            cleanup: "Optional cleanup hint: delete or keep.",
            sandbox: "Optional sandbox hint: inherit or require."
        }
    ]
    public func sessions_batch_delegate(
        tasks: Array<String>,
        agentId: Option<String>,
        label: Option<String>,
        maxWorkers: Option<Int64>,
        perTaskTimeout: Option<Int64>,
        runtime: Option<String>,
        cwd: Option<String>,
        contextMode: Option<String>,
        isolation: Option<String>,
        cleanup: Option<String>,
        sandbox: Option<String>
    ): String {
        this.sessionsBatchDelegateImpl(
            tasks,
            agentId,
            label,
            maxWorkers,
            perTaskTimeout,
            runtime,
            cwd,
            contextMode,
            isolation,
            cleanup,
            sandbox
        )
    }

    public func sessionsBatchDelegateForTest(
        tasks: Array<String>,
        agentId: Option<String>,
        label: Option<String>,
        maxWorkers: Option<Int64>,
        perTaskTimeout: Option<Int64>
    ): String {
        this.sessionsBatchDelegateImpl(
            tasks,
            agentId,
            label,
            maxWorkers,
            perTaskTimeout,
            Some<String>("subagent"),
            None<String>,
            None<String>,
            None<String>,
            None<String>,
            None<String>
        )
    }

    private func batchJsonString(obj: JsonObject, key: String): String {
        match (obj.get(key)) {
            case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
            case None => ""
        }
    }

    private func batchJsonBool(obj: JsonObject, key: String): Bool {
        match (obj.get(key)) {
            case Some(v) => try { v.asBool().getValue() } catch (_: Exception) { false }
            case None => false
        }
    }

    private func normalizeBatchWorkerLimit(maxWorkers: Option<Int64>, total: Int64): Int64 {
        if (total <= 0) {
            return 0
        }
        match (maxWorkers) {
            case Some(v) =>
                if (v <= 0) {
                    return 1
                }
                if (v < total) {
                    return v
                }
                total
            case None => total
        }
    }

    private func batchChildLabel(label: Option<String>, index: Int64): Option<String> {
        let prefix = match (label) {
            case Some(v) =>
                let t = v.trimAscii()
                if (t.isEmpty()) { "batch" } else { t }
            case None => "batch"
        }
        Some<String>("${prefix}-${index}")
    }

    private func batchErrorRow(index: Int64, task: String, status: String, error: String): JsonObject {
        let row = JsonObject()
        row.put("index", index.toJsonValue())
        row.put("task", JsonString(task))
        row.put("ok", JsonBool(false))
        row.put("status", JsonString(status))
        row.put("error", JsonString(error))
        row
    }

    private func sessionsBatchDelegateImpl(
        tasks: Array<String>,
        agentId: Option<String>,
        label: Option<String>,
        maxWorkers: Option<Int64>,
        perTaskTimeout: Option<Int64>,
        runtime: Option<String>,
        cwd: Option<String>,
        contextMode: Option<String>,
        isolation: Option<String>,
        cleanup: Option<String>,
        sandbox: Option<String>
    ): String {
        PrintUtils.printTool("sessions_batch_delegate", shortMessage: "gateway-managed")
        let total = Int64(tasks.size)
        if (total == 0) {
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("error", JsonString("tasks must be non-empty"))
            err.put("total", 0.toJsonValue())
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let workerLimit = this.normalizeBatchWorkerLimit(maxWorkers, total)
        let rows = JsonArray([])
        let runIds = JsonArray([])
        var acceptedCount: Int64 = 0
        var failedCount: Int64 = 0
        var timedOutCount: Int64 = 0
        var deferredCount: Int64 = 0
        var launchedCount: Int64 = 0

        for (i in 0..tasks.size) {
            let index = Int64(i) + 1
            let trimmedTask = tasks[i].trimAscii()
            if (trimmedTask.isEmpty()) {
                failedCount += 1
                rows.add(this.batchErrorRow(index, trimmedTask, "error", "task must be non-empty"))
                continue
            }
            if (launchedCount >= workerLimit) {
                deferredCount += 1
                rows.add(this.batchErrorRow(index, trimmedTask, "deferred", "maxWorkers limit reached"))
                continue
            }
            launchedCount += 1

            let raw = this.sessionsSpawnImpl(
                trimmedTask,
                this.batchChildLabel(label, index),
                runtime,
                agentId,
                None<String>,
                None<String>,
                None<String>,
                cwd,
                perTaskTimeout,
                None<Int64>,
                contextMode,
                isolation,
                None<Bool>,
                None<String>,
                cleanup,
                sandbox,
                None<String>
            )
            let child = try {
                JsonValue.fromStr(raw).asObject()
            } catch (_: Exception) {
                let obj = JsonObject()
                obj.put("ok", JsonBool(false))
                obj.put("status", JsonString("error"))
                obj.put("error", JsonString("child spawn returned invalid json"))
                obj
            }
            let row = JsonObject()
            row.put("index", index.toJsonValue())
            row.put("task", JsonString(trimmedTask))
            row.put("ok", this.batchJsonBool(child, "ok").toJsonValue())
            row.put("status", JsonString(this.batchJsonString(child, "status")))
            row.put("runId", JsonString(this.batchJsonString(child, "runId")))
            row.put("sessionKey", JsonString(this.batchJsonString(child, "sessionKey")))
            row.put("runtime", JsonString(this.batchJsonString(child, "runtime")))
            row.put("agentId", JsonString(this.batchJsonString(child, "agentId")))
            row.put("liveRunStarted", this.batchJsonBool(child, "liveRunStarted").toJsonValue())
            let childError = this.batchJsonString(child, "error")
            if (!childError.isEmpty()) {
                row.put("error", JsonString(childError))
            }
            let childRunId = this.batchJsonString(child, "runId")
            if (!childRunId.isEmpty()) {
                runIds.add(JsonString(childRunId))
            }

            let immediateTimeout = match (perTaskTimeout) {
                case Some(v) => v == 0
                case None => false
            }
            if (immediateTimeout && !childRunId.isEmpty()) {
                let _ = gatewaySubagentMarkRunTimedOut(this.gwStore().sessionsRoot(), childRunId, 0)
                row.put("ok", JsonBool(false))
                row.put("status", JsonString("timed_out"))
                row.put("error", JsonString("subagent timed out"))
                timedOutCount += 1
            } else if (this.batchJsonBool(child, "ok")) {
                acceptedCount += 1
            } else {
                failedCount += 1
            }
            rows.add(row)
        }

        let status = if (acceptedCount > 0 && failedCount == 0 && timedOutCount == 0 && deferredCount == 0) {
            "accepted"
        } else if (acceptedCount > 0 || timedOutCount > 0 || deferredCount > 0) {
            "partial"
        } else {
            "error"
        }
        let summaryText = "accepted=${acceptedCount} failed=${failedCount} timedOut=${timedOutCount} deferred=${deferredCount}"
        let result = JsonObject()
        result.put("ok", (acceptedCount > 0 || timedOutCount > 0 || deferredCount > 0).toJsonValue())
        result.put("status", JsonString(status))
        result.put("summary", JsonString(summaryText))
        result.put("total", total.toJsonValue())
        result.put("maxWorkers", workerLimit.toJsonValue())
        result.put("acceptedCount", acceptedCount.toJsonValue())
        result.put("failedCount", failedCount.toJsonValue())
        result.put("timedOutCount", timedOutCount.toJsonValue())
        result.put("deferredCount", deferredCount.toJsonValue())
        result.put("runIds", runIds)
        result.put("children", rows)
        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        out
    }

    private func sessionsSpawnImpl(
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
        contextMode: Option<String>,
        isolation: Option<String>,
        thread: Option<Bool>,
        mode: Option<String>,
        cleanup: Option<String>,
        sandbox: Option<String>,
        streamTo: Option<String>
    ): String {
        PrintUtils.printTool("sessions_spawn", shortMessage: "gateway-managed")
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
        let resolvedAgentSpec = if (runtimeText == "subagent") {
            gatewaySubagentResolveAgent(requestedAgentId)
        } else {
            GatewaySubagentAgentSpec()
        }
        if (runtimeText == "subagent" && !resolvedAgentSpec.found) {
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("error", JsonString(resolvedAgentSpec.error))
            err.put("agentId", JsonString(resolvedAgentSpec.agentId))
            err.put("runtime", JsonString(runtimeText))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }
        let agentIdText = if (runtimeText == "acp") {
            if (requestedAgentId.isEmpty()) { "codex" } else { requestedAgentId }
        } else {
            resolvedAgentSpec.agentId
        }
        let st = this.gwStore()
        var effectiveTimeout = if (let Some(v) <- runTimeoutSeconds) { v } else { timeoutSeconds ?? -1 }
        let runtimeContext = gatewayCurrentToolRuntimeContext()
        let requesterSessionKey = match (runtimeContext) {
            case Some(ctx) => ctx.sessionKey
            case None => ""
        }
        let requesterChannelText = match (runtimeContext) {
            case Some(ctx) =>
                if (!ctx.channelName.trimAscii().isEmpty()) {
                    ctx.channelName
                } else {
                    ctx.sourceLabel
                }
            case None => "gateway"
        }
        let requesterThreadIdText = this.requesterThreadIdFromSessionKey(requesterSessionKey)
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
        let isolationText = gatewaySubagentNormalizeIsolationMode(match (isolation) {
            case Some(v) => v
            case None => "shared"
        })
        let cleanupModeText = gatewaySubagentNormalizeCleanupMode(match (cleanup) {
            case Some(v) => v
            case None => "keep"
        })
        let sandboxModeText = gatewaySubagentNormalizeSandboxMode(requestedSandboxText)
        let contextModeText = gatewaySubagentNormalizeContextMode(match (contextMode) {
            case Some(v) => v
            case None => "fresh"
        })
        let agentSourceText = if (runtimeText == "acp") { "acp" } else { resolvedAgentSpec.source }
        let policyDecision = gatewaySubagentEvaluateSpawnPolicy(
            CliSettingManager.readGatewaySettings().subagents,
            st.sessionsRoot(),
            requesterSessionKey,
            agentIdText,
            agentSourceText,
            runtimeText,
            effectiveTimeout,
            currentDepth,
            isolationText
        )
        effectiveTimeout = policyDecision.effectiveTimeoutSeconds
        if (!policyDecision.allowed) {
            let err = gatewaySubagentPolicyRejectionJson(policyDecision, agentIdText, runtimeText)
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let sessionKey = st.spawnSession(this.buildSpawnLabel(labelText, runtimeText, agentIdText))
        if (sessionKey.startsWith("error:")) {
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("error", JsonString(sessionKey))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let cwdHint = match (cwd) {
            case Some(v) => v.trimAscii()
            case None => ""
        }
        let workspaceSpec = if (runtimeText == "subagent") {
            this.prepareManagedWorkspace(sessionKey, cwdHint, isolationText, cleanupModeText, sandboxModeText)
        } else {
            let ws = GatewayManagedWorkspaceSpec()
            ws.cwd = if (cwdHint.isEmpty()) { CliConfig.cwd.toString() } else { cwdHint }
            ws.isolationMode = "shared"
            ws.cleanupMode = cleanupModeText
            ws.sandbox = sandboxModeText
            ws
        }
        if (!workspaceSpec.ok) {
            st.appendTranscriptEntry(sessionKey, "system", "subagent workspace preparation failed: ${workspaceSpec.error}")
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("error", JsonString(workspaceSpec.error))
            err.put("sessionKey", JsonString(sessionKey))
            err.put("runtime", JsonString(runtimeText))
            err.put("agentId", JsonString(agentIdText))
            err.put("isolationMode", JsonString(workspaceSpec.isolationMode))
            err.put("worktreePath", JsonString(workspaceSpec.worktreePath))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let metadata = ArrayList<String>()
        metadata.add("runtime=${runtimeText}")
        if (!labelText.isEmpty()) { metadata.add("label=${labelText}") }
        if (!agentIdText.isEmpty()) { metadata.add("agentId=${agentIdText}") }
        if (!agentSourceText.isEmpty()) { metadata.add("agentSource=${agentSourceText}") }
        if (runtimeText == "subagent" && !resolvedAgentSpec.agentDir.trimAscii().isEmpty()) {
            metadata.add("agentDir=${resolvedAgentSpec.agentDir.trimAscii()}")
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
        metadata.add("contextMode=${contextModeText}")
        metadata.add("isolationMode=${workspaceSpec.isolationMode}")
        metadata.add("cleanupMode=${workspaceSpec.cleanupMode}")
        metadata.add("sandbox=${workspaceSpec.sandbox}")
        if (!workspaceSpec.worktreePath.trimAscii().isEmpty()) {
            metadata.add("worktreePath=${workspaceSpec.worktreePath}")
        }

        st.appendTranscriptEntry(sessionKey, "system", "sessions_spawn metadata: ${String.join(metadata.toArray(), delimiter: ", ")}")

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
        result.put("ok", JsonBool(true))
        result.put("status", JsonString("accepted"))
        result.put("runId", JsonString(sessionKey))
        result.put("sessionKey", JsonString(sessionKey))
        result.put("runtime", JsonString(runtimeText))
        result.put("agentId", JsonString(agentIdText))
        result.put("agentSource", JsonString(agentSourceText))
        result.put("task", JsonString(trimmedTask))
        result.put("cwd", JsonString(workspaceSpec.cwd))
        result.put("isolationMode", JsonString(workspaceSpec.isolationMode))
        result.put("cleanupMode", JsonString(workspaceSpec.cleanupMode))
        result.put("sandbox", JsonString(workspaceSpec.sandbox))
        if (!workspaceSpec.worktreePath.trimAscii().isEmpty()) {
            result.put("worktreePath", JsonString(workspaceSpec.worktreePath))
        }
        if (!labelText.isEmpty()) { result.put("label", JsonString(labelText)) }
        if (!modeText.isEmpty()) { result.put("mode", JsonString(modeText)) }
        if (!cleanupText.isEmpty()) { result.put("cleanup", JsonString(cleanupText)) }
        if (!streamToText.isEmpty()) { result.put("streamTo", JsonString(streamToText)) }
        match (thread) {
            case Some(v) => result.put("thread", v.toJsonValue())
            case None => ()
        }
        if (effectiveTimeout >= 0) {
            result.put("timeoutSeconds", effectiveTimeout.toJsonValue())
        }
        result.put("contextMode", JsonString(contextModeText))
        let runRecord = gatewaySubagentCreateRunRecord(
            st.sessionsRoot(),
            sessionKey,
            parentSessionKey: requesterSessionKey,
            requesterSessionKey: requesterSessionKey,
            requesterChannel: requesterChannelText,
            requesterThreadId: requesterThreadIdText,
            agentId: agentIdText,
            agentSource: agentSourceText,
            runtime: runtimeText,
            task: trimmedTask,
            label: labelText,
            status: "queued",
            cwd: workspaceSpec.cwd,
            model: match (model) { case Some(v) => v.trimAscii() case None => "" },
            thinking: match (thinking) { case Some(v) => v.trimAscii() case None => "" },
            timeoutSeconds: effectiveTimeout,
            contextMode: contextModeText,
            isolationMode: workspaceSpec.isolationMode,
            worktreePath: workspaceSpec.worktreePath,
            sandbox: workspaceSpec.sandbox,
            cleanupMode: workspaceSpec.cleanupMode,
            transcriptPath: st.transcriptPath(sessionKey).toString()
        )
        let runMetadata = JsonObject()
        runMetadata.put("policy", gatewaySubagentPolicyDecisionToJson(policyDecision))
        if (runtimeText == "subagent") {
            let agentJson = JsonObject()
            agentJson.put("source", JsonString(resolvedAgentSpec.source))
            agentJson.put("name", JsonString(resolvedAgentSpec.name))
            agentJson.put("description", JsonString(resolvedAgentSpec.description))
            agentJson.put("agentDir", JsonString(resolvedAgentSpec.agentDir))
            agentJson.put("model", JsonString(resolvedAgentSpec.model))
            agentJson.put("background", resolvedAgentSpec.background.toJsonValue())
            agentJson.put("isolation", JsonString(resolvedAgentSpec.isolation))
            agentJson.put("maxTurns", resolvedAgentSpec.maxTurns.toJsonValue())
            let toolsJson = JsonArray([])
            for (tool in resolvedAgentSpec.tools) {
                toolsJson.add(JsonString(tool))
            }
            agentJson.put("tools", toolsJson)
            runMetadata.put("agent", agentJson)
            if (!resolvedAgentSpec.model.trimAscii().isEmpty()) {
                result.put("model", JsonString(resolvedAgentSpec.model.trimAscii()))
            }
            if (!resolvedAgentSpec.agentDir.trimAscii().isEmpty()) {
                result.put("agentDir", JsonString(resolvedAgentSpec.agentDir.trimAscii()))
            }
        }
        runRecord.put("metadata", runMetadata)
        let _ = gatewaySubagentWriteRunRecord(st.sessionsRoot(), runRecord)
        let runId = gatewaySubagentRunRecordString(runRecord, "runId")
        result.put("runId", JsonString(runId))
        result.put("policy", gatewaySubagentPolicyDecisionToJson(policyDecision))
        if (!streamToText.isEmpty()) {
            result.put("compatNote", JsonString("streamTo is recorded, but this Gateway-managed toolset currently only streams output back into the managed session transcript."))
        }
        let parentHistory = this.managedParentContextHistory(contextModeText, requesterSessionKey)
        if (runtimeText == "subagent" && resolvedAgentSpec.background) {
            result.put("liveRunStarted", this.launchManagedSubagentRun(
                sessionKey,
                agentIdText,
                trimmedTask,
                workspaceSpec.cwd,
                runTimeoutSeconds: effectiveTimeout,
                agentSpec: Some(resolvedAgentSpec),
                contextMode: contextModeText,
                parentSessionKey: requesterSessionKey,
                parentHistory: parentHistory,
                workspaceSpec: Some(workspaceSpec)
            ).toJsonValue())
        } else if (runtimeText == "subagent") {
            st.appendTranscriptEntry(sessionKey, "user", trimmedTask)
            this.cleanupManagedWorkspace(workspaceSpec)
            result.put("liveRunStarted", JsonBool(false))
            result.put("compatNote", JsonString("The resolved subagent has background=false, so the task was recorded without launching a background turn."))
        } else if (runtimeText == "acp") {
            let effectiveHarness = match (agentIdText.trimAscii().toAsciiLower()) {
                case "" | "codex" | "codex-cli" => "codex"
                case "claude" | "claude-code" => "claude"
                case "gemini" | "gemini-cli" => "gemini"
                case "cursor" | "cursor-agent" | "cursor_cli" => "cursor-agent"
                case _ => if (agentIdText.trimAscii().toAsciiLower().startsWith("cmd:")) { "custom-cmd" } else if (agentIdText.contains(" ")) { "custom-shell" } else { agentIdText }
            }
            let launched = this.launchManagedAcpRun(
                sessionKey,
                agentIdText,
                trimmedTask,
                cwdHint,
                model,
                thinking,
                resumeSessionId,
                effectiveTimeout,
                modeText,
                sandboxText,
                threadValue
            )
            result.put("liveRunStarted", launched.toJsonValue())
            result.put("runtime", JsonString("acp"))
            result.put("effectiveHarness", JsonString(effectiveHarness))
            result.put("effectiveMode", JsonString(this.acpEffectiveMode(modeText)))
            result.put("effectiveSandbox", JsonString(this.acpEffectiveSandbox(sandboxText)))
            result.put("effectiveSessionPersistence", JsonString(this.acpEffectiveSessionPersistence(modeText, threadValue)))
        } else {
            st.appendTranscriptEntry(sessionKey, "user", trimmedTask)
            result.put("liveRunStarted", JsonBool(false))
            result.put("compatNote", JsonString("This sessions_spawn call recorded the task, but only runtime=subagent or runtime=acp launches a background turn in this build."))
        }

        let out = result.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Gateway main-runtime process tool. Manages background spawned sessions/processes created by sessions_spawn. Supported actions: list, status, poll, logs, kill.",
        parameters: {
            action: "Process action. Supported now: list, status, poll, logs, kill.",
            target: "Optional session key or substring when inspecting or killing one managed process/session.",
            timeout: "Optional timeout in milliseconds for poll. Current implementation is advisory and returns a fresh status snapshot.",
            lines: "Optional number of transcript lines to return for action=logs. Defaults to 20."
        }
    ]
    public func process(action: Option<String>, target: Option<String>, timeout: Option<Int64>, lines: Option<Int64>): String {
        let act = match (action) {
            case Some(v) =>
                let t = v.trimAscii().toAsciiLower()
                if (t.isEmpty()) { "list" } else { t }
            case None => "list"
        }
        PrintUtils.printTool("process", shortMessage: act)

        if (act == "list") {
            let rows = JsonArray([])
            for (sessionKey in this.listManagedSpawnSessions()) {
                let row = JsonObject()
                row.put("sessionKey", JsonString(sessionKey))
                row.put("runtime", JsonString(this.managedRuntime(sessionKey)))
                row.put("agentId", JsonString(this.managedAgentId(sessionKey)))
                row.put("state", JsonString(this.managedState(sessionKey)))
                row.put("hasLiveFuture", JsonBool(this.managedHasLiveFuture(sessionKey)))
                row.put("hasLiveProcess", JsonBool(this.managedHasLiveProcess(sessionKey)))
                row.put("transcriptPath", JsonString(this.gwStore().transcriptPath(sessionKey).toString()))
                rows.add(row)
            }
            let result = JsonObject()
            result.put("ok", JsonBool(true))
            result.put("action", JsonString("list"))
            result.put("count", JsonInt(Int64(rows.size())))
            result.put("processes", rows)
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let resolved = this.resolveManagedSpawnTarget(match (target) {
            case Some(v) => v
            case None => ""
        })
        if (resolved.isEmpty()) {
            let err = JsonObject()
            err.put("ok", JsonBool(false))
            err.put("status", JsonString("error"))
            err.put("action", JsonString(act))
            err.put("error", JsonString("Managed process target not found. Use action=list to inspect available spawned sessions."))
            let out = err.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "status" || act == "poll") {
            let result = JsonObject()
            result.put("ok", JsonBool(true))
            result.put("action", JsonString(act))
            result.put("sessionKey", JsonString(resolved))
            result.put("runtime", JsonString(this.managedRuntime(resolved)))
            result.put("agentId", JsonString(this.managedAgentId(resolved)))
            result.put("state", JsonString(this.managedState(resolved)))
            result.put("hasLiveFuture", JsonBool(this.managedHasLiveFuture(resolved)))
            result.put("hasLiveProcess", JsonBool(this.managedHasLiveProcess(resolved)))
            result.put("transcriptPath", JsonString(this.gwStore().transcriptPath(resolved).toString()))
            if (act == "poll") {
                result.put("timeoutMs", (timeout ?? 0).toJsonValue())
                result.put("compatNote", JsonString("poll currently returns a fresh managed-session/process snapshot without blocking; use logs or status again when you need another checkpoint."))
            }
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "logs") {
            let maxLines = if ((lines ?? 0) > 0) { lines ?? 20 } else { 20 }
            let result = JsonObject()
            result.put("ok", JsonBool(true))
            result.put("action", JsonString("logs"))
            result.put("sessionKey", JsonString(resolved))
            result.put("state", JsonString(this.managedState(resolved)))
            result.put("lines", maxLines.toJsonValue())
            result.put("logs", JsonString(this.gwStore().formatHistoryAsText(resolved, maxLines)))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "kill") {
            var killed = false
            synchronized(gatewayManagedSessionLock) {
                if (let Some(process) <- gatewayManagedProcesses.get(resolved)) {
                    try {
                        process.terminate(force: true)
                        killed = true
                    } catch (_: Exception) {
                        ()
                    }
                }
            }
            if (killed) {
                this.setManagedState(resolved, "cancelled")
                this.gwStore().appendTranscriptEntry(resolved, "system", "process killed via process(action=kill)")
            }
            let result = JsonObject()
            result.put("ok", JsonBool(killed))
            result.put("action", JsonString("kill"))
            result.put("sessionKey", JsonString(resolved))
            result.put("status", JsonString(if (killed) { "killed" } else { "not-running" }))
            result.put("state", JsonString(this.managedState(resolved)))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let unsupported = JsonObject()
        unsupported.put("ok", JsonBool(false))
        unsupported.put("status", JsonString("unsupported"))
        unsupported.put("action", JsonString(act))
        unsupported.put("error", JsonString("Unsupported process action in current Gateway main-runtime implementation: ${act}"))
        unsupported.put("compatNote", JsonString("Supported actions are list, status, poll, logs, and kill."))
        let out = unsupported.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }

    @tool[
        description: "Gateway main-runtime subagents tool. Lists, inspects, steers, sends follow-up messages to, polls logs for, or cancels managed subagent runs inside the Gateway process.",
        parameters: {
            action: "Subagent action. Supported now: list, status, poll, logs, steer, send, kill.",
            target: "For list: current, all, *, agent:<id>, or a plain agent id. For other actions: run id, session key, or substring. Use all or * with kill to cancel every accessible non-terminal managed subagent run.",
            message: "Required for steer/send. Appended as a new user message to the target spawned session transcript and dispatched as another background turn when the run is not terminal.",
            recentMinutes: "Optional recency hint. Current implementation does not filter by recency."
        }
    ]
    public func subagents(action: Option<String>, target: Option<String>, message: Option<String>, recentMinutes: Option<Int64>): String {
        this.subagentsImpl(action, target, message, recentMinutes)
    }

    public func subagentsForTest(action: Option<String>, target: Option<String>, message: Option<String>, recentMinutes: Option<Int64>): String {
        this.subagentsImpl(action, target, message, recentMinutes)
    }

    public func subagentsForCommand(action: Option<String>, target: Option<String>, message: Option<String>, recentMinutes: Option<Int64>): String {
        this.subagentsImpl(action, target, message, recentMinutes)
    }

    private func subagentsImpl(action: Option<String>, target: Option<String>, message: Option<String>, recentMinutes: Option<Int64>): String {
        let act = match (action) {
            case Some(v) =>
                let t = v.trimAscii().toAsciiLower()
                if (t.isEmpty()) { "list" } else { t }
            case None => "list"
        }
        PrintUtils.printTool("subagents", shortMessage: act)

        if (act == "list") {
            let filter = match (target) {
                case Some(v) =>
                    let t = v.trimAscii()
                    if (t.isEmpty()) { "current" } else { t }
                case None => "current"
            }
            let sessions = JsonArray([])
            var count: Int64 = 0
            for (record in gatewaySubagentListRunRecords(this.gwStore().sessionsRoot())) {
                if (!this.managedRunMatchesListFilter(record, filter)) {
                    continue
                }
                let row = this.runRecordToManagedRow(record)
                let sessionKey = gatewaySubagentRunRecordString(record, "sessionKey")
                let runtimeText = gatewaySubagentRunRecordString(record, "runtime")
                let state = this.managedState(sessionKey)
                if (!state.isEmpty()) { row.put("state", JsonString(state)) }
                if (runtimeText == "acp") {
                    let modeText = this.managedMode(sessionKey)
                    let sandboxText = this.managedSandbox(sessionKey)
                    let threadText = this.managedThread(sessionKey)
                    row.put("effectiveMode", JsonString(this.acpEffectiveMode(modeText)))
                    row.put("effectiveSandbox", JsonString(this.acpEffectiveSandbox(sandboxText)))
                    row.put("effectiveSessionPersistence", JsonString(this.acpEffectiveSessionPersistence(modeText, threadText.trimAscii().toAsciiLower() == "true")))
                }
                sessions.add(row)
                count += 1
            }
            let result = JsonObject()
            result.put("ok", JsonBool(true))
            result.put("status", JsonString("ok"))
            result.put("action", JsonString("list"))
            result.put("filter", JsonString(filter))
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
            let record = match (this.resolveManagedRunForControl(tgt)) {
                case Some(value) => value
                case None =>
                    let err = JsonObject()
                    err.put("ok", JsonBool(false))
                    err.put("status", JsonString("error"))
                    err.put("action", JsonString(act))
                    err.put("target", JsonString(tgt))
                    err.put("error", JsonString("Unknown subagent target."))
                    let out = err.toJsonString()
                    PrintUtils.printToolResult(out)
                    return out
            }
            if (!this.controllerCanAccessRun(record)) {
                return this.subagentControlDeniedJson(act, tgt)
            }
            let resolved = gatewaySubagentRunRecordString(record, "sessionKey")
            if (resolved.isEmpty()) {
                let err = JsonObject()
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("action", JsonString(act))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("Unknown subagent target."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            if (act == "logs") {
                let result = JsonObject()
                result.put("ok", JsonBool(true))
                result.put("status", JsonString("ok"))
                result.put("action", JsonString("logs"))
                result.put("run", record)
                result.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
                result.put("sessionKey", JsonString(resolved))
                result.put("transcriptPath", JsonString(this.gwStore().transcriptPath(resolved).toString()))
                result.put("outputPath", JsonString(gatewaySubagentRunRecordString(record, "outputPath")))
                result.put("logs", JsonString(this.gwStore().formatHistoryAsText(resolved, 40)))
                let out = result.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let result = JsonObject()
            result.put("ok", JsonBool(true))
            result.put("status", JsonString("ok"))
            result.put("action", JsonString(act))
            result.put("run", record)
            result.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
            result.put("sessionKey", JsonString(resolved))
            result.put("runtime", JsonString(this.managedRuntime(resolved)))
            result.put("agentId", JsonString(this.managedAgentId(resolved)))
            result.put("state", JsonString(this.managedState(resolved)))
            result.put("hasLiveFuture", JsonBool(this.managedHasLiveFuture(resolved)))
            result.put("hasLiveProcess", JsonBool(this.managedHasLiveProcess(resolved)))
            result.put("transcriptPath", JsonString(this.gwStore().transcriptPath(resolved).toString()))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        if (act == "steer" || act == "send") {
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
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("action", JsonString(act))
                err.put("error", JsonString("${act} requires target and message"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let record = match (this.resolveManagedRunForControl(tgt)) {
                case Some(value) => value
                case None =>
                    let err = JsonObject()
                    err.put("ok", JsonBool(false))
                    err.put("status", JsonString("error"))
                    err.put("action", JsonString(act))
                    err.put("target", JsonString(tgt))
                    err.put("error", JsonString("Unknown subagent target."))
                    let out = err.toJsonString()
                    PrintUtils.printToolResult(out)
                    return out
            }
            if (!this.controllerCanAccessRun(record)) {
                return this.subagentControlDeniedJson(act, tgt)
            }
            let resolved = gatewaySubagentRunRecordString(record, "sessionKey")
            if (resolved.isEmpty()) {
                let err = JsonObject()
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("action", JsonString(act))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("Unknown subagent target."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let agentIdText = this.managedAgentId(resolved)
            let runtimeText = this.managedRuntime(resolved)
            if (agentIdText.isEmpty()) {
                let err = JsonObject()
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("action", JsonString(act))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("The target subagent has no recorded agentId and cannot be steered yet."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let persistedStatus = gatewaySubagentRunRecordString(record, "status")
            if (gatewaySubagentRunStatusIsTerminal(persistedStatus)) {
                let err = JsonObject()
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("terminal"))
                err.put("action", JsonString(act))
                err.put("target", JsonString(tgt))
                err.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
                err.put("sessionKey", JsonString(resolved))
                err.put("error", JsonString("Cannot ${act} a terminal subagent run. Spawn a new subagent for follow-up work."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            this.gwStore().appendTranscriptEntry(resolved, "user", msg)
            let launched = this.launchManagedSessionTurn(resolved, msg)
            let result = JsonObject()
            result.put("ok", JsonBool(launched))
            result.put("status", JsonString(if (launched) { "accepted" } else { "busy" }))
            result.put("action", JsonString(act))
            result.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
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
                for (record in gatewaySubagentListRunRecords(this.gwStore().sessionsRoot())) {
                    if (!this.controllerCanAccessRun(record)) {
                        continue
                    }
                    if (gatewaySubagentRunStatusIsTerminal(gatewaySubagentRunRecordString(record, "status"))) {
                        continue
                    }
                    let sessionKey = gatewaySubagentRunRecordString(record, "sessionKey")
                    if (sessionKey.isEmpty()) {
                        continue
                    }
                    let snapshot = this.managedKillSnapshot(sessionKey)
                    let priorState = snapshot[0]
                    let hadFuture = snapshot[1]
                    let hadProcess = snapshot[2]
                    this.markManagedSessionKillRequested(sessionKey, "all")
                    let cancelRequested = this.cancelManagedSession(sessionKey)
                    if (!cancelRequested && !hadFuture && !hadProcess) {
                        this.setManagedState(sessionKey, "cancelled", error: "cancel requested")
                    }
                    let row = JsonObject()
                    row.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
                    row.put("sessionKey", JsonString(sessionKey))
                    if (!priorState.isEmpty()) { row.put("priorState", JsonString(priorState)) }
                    row.put("hadLiveFuture", hadFuture.toJsonValue())
                    row.put("hadLiveProcess", hadProcess.toJsonValue())
                    row.put("cancelRequested", cancelRequested.toJsonValue())
                    killed.add(row)
                    count += 1
                }
                let result = JsonObject()
                result.put("ok", JsonBool(true))
                result.put("status", JsonString("ok"))
                result.put("action", JsonString("kill"))
                result.put("target", JsonString("all"))
                result.put("count", count.toJsonValue())
                result.put("killed", killed)
                let out = result.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }

            if (tgt.isEmpty()) {
                let err = JsonObject()
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("action", JsonString("kill"))
                err.put("error", JsonString("kill requires target"))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let record = match (this.resolveManagedRunForControl(tgt)) {
                case Some(value) => value
                case None =>
                    let err = JsonObject()
                    err.put("ok", JsonBool(false))
                    err.put("status", JsonString("error"))
                    err.put("action", JsonString("kill"))
                    err.put("target", JsonString(tgt))
                    err.put("error", JsonString("Unknown subagent target."))
                    let out = err.toJsonString()
                    PrintUtils.printToolResult(out)
                    return out
            }
            if (!this.controllerCanAccessRun(record)) {
                return this.subagentControlDeniedJson("kill", tgt)
            }
            let resolved = gatewaySubagentRunRecordString(record, "sessionKey")
            if (resolved.isEmpty()) {
                let err = JsonObject()
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("action", JsonString("kill"))
                err.put("target", JsonString(tgt))
                err.put("error", JsonString("Unknown subagent target."))
                let out = err.toJsonString()
                PrintUtils.printToolResult(out)
                return out
            }
            let snapshot = this.managedKillSnapshot(resolved)
            let priorState = snapshot[0]
            let hadFuture = snapshot[1]
            let hadProcess = snapshot[2]
            let persistedStatus = gatewaySubagentRunRecordString(record, "status")
            var cancelRequested = false
            var resultStatus = "noop"
            if (!gatewaySubagentRunStatusIsTerminal(persistedStatus)) {
                this.markManagedSessionKillRequested(resolved, tgt)
                cancelRequested = this.cancelManagedSession(resolved)
                if (!cancelRequested && !hadFuture && !hadProcess) {
                    this.setManagedState(resolved, "cancelled", error: "cancel requested")
                }
                resultStatus = "cancelled"
            }
            let result = JsonObject()
            result.put("ok", JsonBool(true))
            result.put("status", JsonString(resultStatus))
            result.put("action", JsonString("kill"))
            result.put("target", JsonString(tgt))
            result.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
            result.put("sessionKey", JsonString(resolved))
            result.put("persistedStatus", JsonString(persistedStatus))
            if (!priorState.isEmpty()) { result.put("priorState", JsonString(priorState)) }
            result.put("hadLiveFuture", hadFuture.toJsonValue())
            result.put("hadLiveProcess", hadProcess.toJsonValue())
            result.put("cancelRequested", cancelRequested.toJsonValue())
            result.put("deleted", JsonBool(false))
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let unsupported = JsonObject()
        unsupported.put("ok", JsonBool(false))
        unsupported.put("status", JsonString("unsupported"))
        unsupported.put("action", JsonString(act))
        unsupported.put("error", JsonString("Supported actions are list, status, poll, logs, steer, send, and kill."))
        let out = unsupported.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }
}
