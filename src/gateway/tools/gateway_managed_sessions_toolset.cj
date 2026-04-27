package metis.gateway.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.config.{CliConfig, CliSettingManager}
import metis.core.memory.{MemorySessionTranscriptStore, memorySessionStoreForGatewayUser}
import metis.core.{gatewayCurrentToolRuntimeContext, gatewaySubagentCreateRunRecord, gatewaySubagentEvaluateSpawnPolicy, gatewaySubagentFindRunBySessionKey, gatewaySubagentPolicyDecisionToJson, gatewaySubagentPolicyRejectionJson, gatewaySubagentResolveRunRecord, gatewaySubagentRunRecordInt, gatewaySubagentRunRecordString, gatewaySubagentUpdateRunStatus, gatewaySubagentWriteRunRecord}
import metis.io.PrintUtils

import std.collection.{ArrayList, HashMap}
import std.core.Duration
import std.fs.{Directory, File, OpenMode, Path, exists}
import std.io.StringReader
import std.process.*
import std.sync.Mutex

import stdx.encoding.json.{JsonArray, JsonBool, JsonInt, JsonObject, JsonString}

private let gatewayManagedSessionLock = Mutex()
private var gatewayManagedAgentIds = HashMap<String, String>()
private var gatewayManagedStates = HashMap<String, String>()
private var gatewayManagedFutures = HashMap<String, Future<Unit>>()
private var gatewayManagedProcesses = HashMap<String, SubProcess>()

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
        normalized
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
            let _ = gatewaySubagentUpdateRunStatus(this.gwStore().sessionsRoot(), sessionKey, "queued")
        }
        queued
    }

    private func setManagedState(sessionKey: String, state: String): Unit {
        synchronized(gatewayManagedSessionLock) {
            gatewayManagedStates.add(sessionKey, state)
        }
        let _ = gatewaySubagentUpdateRunStatus(this.gwStore().sessionsRoot(), sessionKey, state)
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

    private func internalSubagentCommandSpec(sessionKey: String, agentId: String, task: String, cwdHint: String): (String, Array<String>, Path) {
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
        if (this.managedCleanup(sessionKey).trimAscii().toAsciiLower() == "delete") {
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
                return true
            }
            if (cancelled) {
                gatewayManagedStates.add(sessionKey, "cancelling")
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
                let exitCode = process.wait(timeout: timeout)
                let stdout = try { stdoutFuture.get() } catch (_: Exception) { "" }
                let stderr = try { stderrFuture.get() } catch (_: Exception) { "" }
                if (!stdout.trimAscii().isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "assistant", stdout.trimAscii())
                }
                if (!stderr.trimAscii().isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp stderr: ${stderr.trimAscii()}")
                }
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp cancelled")
                    this.setManagedState(sessionKey, "cancelled")
                } else if (exitCode == 0) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp completed: harness=${resolvedHarness} exitCode=${exitCode}")
                    this.setManagedState(sessionKey, "completed")
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "acp failed: harness=${resolvedHarness} exitCode=${exitCode}")
                    this.setManagedState(sessionKey, "failed")
                }
            } catch (e: Exception) {
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "acp cancelled")
                    this.setManagedState(sessionKey, "cancelled")
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "acp failed: ${e.message}")
                    this.setManagedState(sessionKey, "failed")
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

    private func launchManagedSubagentRun(sessionKey: String, agentId: String, task: String, cwdHint: String): Bool {
        let normalized = this.normalizeManagedAgentId(agentId)
        if (!this.supportsRealManagedSubagent(normalized)) {
            return false
        }
        if (!this.tryQueueManagedRun(sessionKey, normalized)) {
            return false
        }
        let spec = this.internalSubagentCommandSpec(sessionKey, normalized, task, cwdHint)
        let command = spec[0]
        let args = spec[1]
        let workDir = spec[2]
        let st = this.gwStore()
        st.appendTranscriptEntry(sessionKey, "system", "subagent dispatch accepted: agentId=${normalized}")
        let future = spawn {
            this.setManagedState(sessionKey, "running")
            st.appendTranscriptEntry(sessionKey, "system", "subagent started: agentId=${normalized}")
            try {
                let process = launch(
                    command,
                    args,
                    stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe,
                    workingDirectory: Some(workDir)
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
                let exitCode = process.wait()
                let content = (try { stdoutFuture.get() } catch (_: Exception) { "" }).trimAscii()
                let stderr = (try { stderrFuture.get() } catch (_: Exception) { "" }).trimAscii()
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent cancelled")
                    this.setManagedState(sessionKey, "cancelled")
                    return
                }
                if (!stderr.isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent stderr: ${stderr}")
                }
                if (exitCode == 0 && !content.isEmpty()) {
                    st.appendTranscriptEntry(sessionKey, "assistant", content)
                    st.appendTranscriptEntry(sessionKey, "system", "subagent completed: agentId=${normalized}")
                    this.setManagedState(sessionKey, "completed")
                } else if (exitCode == 0) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent completed with empty response")
                    this.setManagedState(sessionKey, "completed")
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent failed: agentId=${normalized} exitCode=${exitCode}")
                    this.setManagedState(sessionKey, "failed")
                }
            } catch (e: Exception) {
                if (Thread.currentThread.hasPendingCancellation) {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent cancelled")
                    this.setManagedState(sessionKey, "cancelled")
                } else {
                    st.appendTranscriptEntry(sessionKey, "system", "subagent failed: ${e.message}")
                    this.setManagedState(sessionKey, "failed")
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
        this.launchManagedSubagentRun(sessionKey, agentId, task, cwdHint)
    }

    @tool[
        description: "Gateway main-runtime sessions_spawn tool. Creates a managed session, records spawn metadata, and can launch a background subagent or ACP harness run inside the Gateway process.",
        parameters: {
            task: "Task or prompt for the spawned session.",
            label: "Optional label for the spawned session.",
            runtime: "Optional runtime hint: subagent or acp.",
            agentId: "Optional target agent identifier hint. For runtime=acp this can be codex, claude, gemini, cursor-agent, or cmd:<shell-command-with-{task}>.",
            resumeSessionId: "Optional ACP resume session id hint forwarded to supported harnesses.",
            model: "Optional model override hint forwarded to ACP harnesses and stored in session metadata.",
            thinking: "Optional thinking override hint forwarded to supported ACP harnesses when available.",
            cwd: "Optional working directory hint used when launching the background run.",
            runTimeoutSeconds: "Optional run timeout hint.",
            timeoutSeconds: "Optional legacy timeout hint. Used only when runTimeoutSeconds is omitted.",
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
        let agentIdText = if (runtimeText == "acp") {
            if (requestedAgentId.isEmpty()) { "codex" } else { requestedAgentId }
        } else {
            this.normalizeManagedAgentId(requestedAgentId)
        }
        let st = this.gwStore()
        var effectiveTimeout = if (let Some(v) <- runTimeoutSeconds) { v } else { timeoutSeconds ?? -1 }
        let requesterSessionKey = match (gatewayCurrentToolRuntimeContext()) {
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
        let policyDecision = gatewaySubagentEvaluateSpawnPolicy(
            CliSettingManager.readGatewaySettings().subagents,
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

        let metadata = ArrayList<String>()
        metadata.add("runtime=${runtimeText}")
        if (!labelText.isEmpty()) { metadata.add("label=${labelText}") }
        if (!agentIdText.isEmpty()) { metadata.add("agentId=${agentIdText}") }
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
        result.put("ok", JsonBool(true))
        result.put("status", JsonString("accepted"))
        result.put("runId", JsonString(sessionKey))
        result.put("sessionKey", JsonString(sessionKey))
        result.put("runtime", JsonString(runtimeText))
        result.put("agentId", JsonString(agentIdText))
        result.put("task", JsonString(trimmedTask))
        result.put("cwd", JsonString(if (cwdHint.isEmpty()) { CliConfig.cwd.toString() } else { cwdHint }))
        if (!labelText.isEmpty()) { result.put("label", JsonString(labelText)) }
        if (!modeText.isEmpty()) { result.put("mode", JsonString(modeText)) }
        if (!cleanupText.isEmpty()) { result.put("cleanup", JsonString(cleanupText)) }
        if (!sandboxText.isEmpty()) { result.put("sandbox", JsonString(sandboxText)) }
        if (!streamToText.isEmpty()) { result.put("streamTo", JsonString(streamToText)) }
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
            requesterChannel: "gateway",
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
        if (!streamToText.isEmpty()) {
            result.put("compatNote", JsonString("streamTo is recorded, but this Gateway-managed toolset currently only streams output back into the managed session transcript."))
        }
        if (runtimeText == "subagent" && this.supportsRealManagedSubagent(agentIdText)) {
            result.put("liveRunStarted", this.launchManagedSubagentRun(sessionKey, agentIdText, trimmedTask, cwdHint).toJsonValue())
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
        description: "Gateway main-runtime subagents tool. Lists managed spawned sessions or steers/kills them inside the Gateway process.",
        parameters: {
            action: "Subagent action. Supported now: list, steer, kill.",
            target: "Optional session key or substring when steering/killing one spawned subagent. Use all or * to target every managed spawned session for kill.",
            message: "Required for steer. Appended as a new user message to the target spawned session transcript.",
            recentMinutes: "Optional recency hint. Current implementation does not filter by recency."
        }
    ]
    public func subagents(action: Option<String>, target: Option<String>, message: Option<String>, recentMinutes: Option<Int64>): String {
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
                        if (!runId.isEmpty()) { row.put("runId", JsonString(runId)) }
                        let persistedStatus = gatewaySubagentRunRecordString(record, "status")
                        if (!persistedStatus.isEmpty()) { row.put("status", JsonString(persistedStatus)) }
                    case None => row.put("runId", JsonString(sessionKey))
                }
                row.put("sessionKey", JsonString(sessionKey))
                row.put("transcriptPath", JsonString(this.gwStore().transcriptPath(sessionKey).toString()))
                row.put("runtime", JsonString(this.managedRuntime(sessionKey)))
                let agentIdText = this.managedAgentId(sessionKey)
                let state = this.managedState(sessionKey)
                if (!agentIdText.isEmpty()) { row.put("agentId", JsonString(agentIdText)) }
                if (!state.isEmpty()) { row.put("state", JsonString(state)) }
                row.put("hasLiveFuture", this.managedHasLiveFuture(sessionKey).toJsonValue())
                row.put("hasLiveProcess", this.managedHasLiveProcess(sessionKey).toJsonValue())
                let cwdHint = this.managedCwd(sessionKey)
                if (!cwdHint.isEmpty()) { row.put("cwd", JsonString(cwdHint)) }
                let modelText = this.managedModel(sessionKey)
                if (!modelText.isEmpty()) { row.put("model", JsonString(modelText)) }
                let thinkingText = this.managedThinking(sessionKey)
                if (!thinkingText.isEmpty()) { row.put("thinking", JsonString(thinkingText)) }
                let resumeText = this.managedResumeSessionId(sessionKey)
                if (!resumeText.isEmpty()) { row.put("resumeSessionId", JsonString(resumeText)) }
                let modeText = this.managedMode(sessionKey)
                if (!modeText.isEmpty()) { row.put("mode", JsonString(modeText)) }
                let cleanupText = this.managedCleanup(sessionKey)
                if (!cleanupText.isEmpty()) { row.put("cleanup", JsonString(cleanupText)) }
                let sandboxText = this.managedSandbox(sessionKey)
                if (!sandboxText.isEmpty()) { row.put("sandbox", JsonString(sandboxText)) }
                let streamText = this.managedStreamTo(sessionKey)
                if (!streamText.isEmpty()) { row.put("streamTo", JsonString(streamText)) }
                let threadText = this.managedThread(sessionKey)
                if (!threadText.isEmpty()) { row.put("thread", JsonString(threadText)) }
                let timeoutText = this.managedTimeoutSeconds(sessionKey)
                if (!timeoutText.isEmpty()) { row.put("timeoutSeconds", JsonString(timeoutText)) }
                if (this.managedRuntime(sessionKey) == "acp") {
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
                err.put("ok", JsonBool(false))
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
                result.put("ok", JsonBool(true))
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
            result.put("ok", JsonBool(true))
            result.put("status", JsonString("ok"))
            result.put("action", JsonString(act))
            if (!gatewaySubagentRunRecordString(record, "runId").isEmpty()) {
                result.put("run", record)
                result.put("runId", JsonString(gatewaySubagentRunRecordString(record, "runId")))
            }
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
                err.put("ok", JsonBool(false))
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
                err.put("ok", JsonBool(false))
                err.put("status", JsonString("error"))
                err.put("action", JsonString("steer"))
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
            result.put("ok", JsonBool(launched))
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
                    let snapshot = this.managedKillSnapshot(sessionKey)
                    let priorState = snapshot[0]
                    let hadFuture = snapshot[1]
                    let hadProcess = snapshot[2]
                    this.markManagedSessionKillRequested(sessionKey, "all")
                    let _ = this.cancelManagedSession(sessionKey)
                    if (this.gwStore().deleteSession(sessionKey)) {
                        this.forgetManagedSession(sessionKey)
                        let row = JsonObject()
                        row.put("sessionKey", JsonString(sessionKey))
                        if (!priorState.isEmpty()) { row.put("priorState", JsonString(priorState)) }
                        row.put("hadLiveFuture", hadFuture.toJsonValue())
                        row.put("hadLiveProcess", hadProcess.toJsonValue())
                        killed.add(row)
                        count += 1
                    }
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
            let resolved = this.resolveManagedSpawnTarget(tgt)
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
            this.markManagedSessionKillRequested(resolved, tgt)
            let _ = this.cancelManagedSession(resolved)
            let deleted = this.gwStore().deleteSession(resolved)
            if (deleted) {
                this.forgetManagedSession(resolved)
            }
            let result = JsonObject()
            result.put("ok", JsonBool(deleted))
            result.put("status", JsonString(if (deleted) { "ok" } else { "error" }))
            result.put("action", JsonString("kill"))
            result.put("target", JsonString(tgt))
            result.put("sessionKey", JsonString(resolved))
            if (!priorState.isEmpty()) { result.put("priorState", JsonString(priorState)) }
            result.put("hadLiveFuture", hadFuture.toJsonValue())
            result.put("hadLiveProcess", hadProcess.toJsonValue())
            result.put("deleted", JsonBool(deleted))
            if (!deleted) {
                result.put("error", JsonString("Failed to delete managed session transcript."))
            }
            let out = result.toJsonString()
            PrintUtils.printToolResult(out)
            return out
        }

        let unsupported = JsonObject()
        unsupported.put("ok", JsonBool(false))
        unsupported.put("status", JsonString("unsupported"))
        unsupported.put("action", JsonString(act))
        unsupported.put("error", JsonString("Supported actions are list, steer, and kill."))
        let out = unsupported.toJsonString()
        PrintUtils.printToolResult(out)
        return out
    }
}
