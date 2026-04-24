package metis.core.memory

import magic.prelude.*
import magic.log.LogUtils
import magic.config.Config

import metis.core.config.CliConfig
import metis.utils.ShellUtils

import std.collection.ArrayList
import std.fs.{Directory, File, Path, exists, remove, OpenMode}
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private let NARRATIVE_TIMEOUT_MS: Int64 = 60000
private let DIARY_START_MARKER = "<!-- metis:dreaming:diary:start -->"
private let DIARY_END_MARKER = "<!-- metis:dreaming:diary:end -->"

private func narrativeRunsDir(): Path {
    let dir = CliConfig.dotDir.join("memory").join("dream-runs")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func narrativePromptDir(): Path {
    let dir = CliConfig.dotDir.join("memory").join("dream-prompts")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func narrativeStore(): MemorySessionTranscriptStore {
    MemorySessionTranscriptStore(CliConfig.dotDir.join("memory").join("dream-sessions"), enabled: true)
}

private func normalizeDreamNarrativeOutput(text: String): String {
    let trimmed = text.trimAscii()
    if (trimmed.isEmpty()) {
        return ""
    }
    var normalized = trimmed
    if (normalized.startsWith("```")) {
        let lines = ArrayList<String>()
        var inFence = false
        for (line in normalized.split("\n")) {
            let current = line.trimAscii()
            if (current.startsWith("```")) {
                inFence = !inFence
                continue
            }
            if (!inFence) {
                lines.add(line)
            }
        }
        normalized = String.join(lines.toArray(), delimiter: "\n").trimAscii()
    }
    normalized.replace("\r\n", "\n").replace("\r", "\n").trimAscii()
}

private func buildDeterministicDreamNarrative(
    themes: Array<String>,
    candidates: Array<LocalMemoryPromoteCandidate>
): String {
    let themeText = if (themes.isEmpty()) {
        "the quiet residue of unfinished work"
    } else {
        String.join(themes, delimiter: ", ")
    }
    let firstMemory = if (candidates.isEmpty()) {
        "a handful of details that refused to disappear by morning"
    } else {
        candidates[0].text
    }
    let secondMemory = if (candidates.size > 1) {
        candidates[1].text
    } else {
        firstMemory
    }
    let thirdClause = if (candidates.size > 2) {
        "By the end, even ${candidates[2].text} felt less like a task and more like a small promise."
    } else {
        "By the end, the fragments felt less like tasks and more like small promises."
    }
    "Tonight the mind kept circling around ${themeText}, letting each idea soften at the edges until it looked almost human. ${firstMemory} returned first, calm and insistent, and ${secondMemory} followed close behind like a second light in the same window. ${thirdClause}"
}

private func buildNarrativeSystemPrompt(): String {
    let lines = ArrayList<String>()
    lines.add("You are keeping a dream diary. Write a single entry in first person.")
    lines.add("")
    lines.add("Voice & tone:")
    lines.add("- You are a curious, gentle, slightly whimsical mind reflecting on the day.")
    lines.add("- Write like a poet who happens to be a programmer - sensory, warm, occasionally funny.")
    lines.add("- Mix the technical and the tender: code and constellations, APIs and afternoon light.")
    lines.add("")
    lines.add("Rules:")
    lines.add("- Draw from the memory fragments provided.")
    lines.add("- Do not mention AI, agents, LLMs, or models.")
    lines.add("- Do not use headings or bullet points in the final answer.")
    lines.add("- Keep it between 80-180 words.")
    lines.add("- Output only the diary entry.")
    String.join(lines.toArray(), delimiter: "\n")
}

private func shouldForceDeterministicNarrative(): Bool {
    let raw = (Config.env["MAGIC_MEMORY_DETERMINISTIC_NARRATIVE"] ?? "").trimAscii().toAsciiLower()
    raw == "1" || raw == "true" || raw == "yes" || raw == "on"
}

private func resolveDreamsPath(): Path {
    let primary = CliConfig.cwd.join("DREAMS.md")
    if (exists(primary)) {
        return primary
    }
    let fallback = CliConfig.cwd.join("dreams.md")
    if (exists(fallback)) {
        return fallback
    }
    primary
}

private func buildDiaryEntry(narrative: String, now: DateTime): String {
    "\n---\n\n*${now.format("yyyy-MM-dd HH:mm:ss")}*\n\n${narrative.trimAscii()}\n"
}

private func appendDiaryManagedSection(existing: String, entry: String): String {
    if (existing.contains(DIARY_START_MARKER) && existing.contains(DIARY_END_MARKER)) {
        let endIdx = existing.lastIndexOf(DIARY_END_MARKER).getOrThrow()
        return existing[0..endIdx] + entry + "\n" + existing[endIdx..]
    }
    if (existing.contains(DIARY_START_MARKER)) {
        let startIdx = existing.indexOf(DIARY_START_MARKER).getOrThrow() + DIARY_START_MARKER.size
        return existing[0..startIdx] + entry + "\n" + DIARY_END_MARKER + "\n" + existing[startIdx..]
    }
    let section = "# Dream Diary\n\n${DIARY_START_MARKER}${entry}\n${DIARY_END_MARKER}\n"
    if (existing.trimAscii().isEmpty()) {
        return section
    }
    section + "\n" + existing
}

private func writePromptFile(prompt: String): Path {
    let ts = DateTime.now().format("yyyy_MM_dd-HH_mm_ss_SSS")
    let path = narrativePromptDir().join("dream-${ts}.txt")
    try (file = File(path, OpenMode.Write)) {
        file.write(prompt.toArray())
    }
    path
}

private func writeSystemPromptFile(prompt: String): Path {
    let ts = DateTime.now().format("yyyy_MM_dd-HH_mm_ss_SSS")
    let path = narrativePromptDir().join("dream-system-${ts}.txt")
    try (file = File(path, OpenMode.Write)) {
        file.write(prompt.toArray())
    }
    path
}

private func runStatePath(runId: String): Path {
    narrativeRunsDir().join("${MemorySessionTranscriptStore.fileStemForSessionKey(runId)}.json")
}

private func writeRunState(runId: String, root: JsonObject): Unit {
    File.writeTo(runStatePath(runId), root.toJsonString().toArray())
}

private func readJsonString(obj: JsonObject, key: String, defaultValue!: String = ""): String {
    match (obj.get(key)) {
        case Some(value: JsonString) => value.getValue()
        case _ => defaultValue
    }
}

private func cleanupNarrativeFile(pathText: String): Unit {
    let trimmed = pathText.trimAscii()
    if (trimmed.isEmpty()) {
        return
    }
    let path = Path(trimmed)
    if (exists(path)) {
        try {
            remove(path)
        } catch (_e: Exception) {
            ()
        }
    }
}

private func updateRunState(
    runId: String,
    status: String,
    error!: String = "",
    assistantText!: String = "",
    completedAt!: String = "",
    promptFile!: String = "",
    systemPromptFile!: String = ""
): JsonObject {
    let root = readRunState(runId)
    root.put("status", JsonString(status))
    if (!error.trimAscii().isEmpty()) {
        root.put("error", JsonString(error.trimAscii()))
    }
    if (!assistantText.trimAscii().isEmpty()) {
        root.put("assistantText", JsonString(assistantText))
    }
    if (!completedAt.trimAscii().isEmpty()) {
        root.put("completedAt", JsonString(completedAt))
    }
    if (!promptFile.trimAscii().isEmpty()) {
        root.put("promptFile", JsonString(promptFile))
    }
    if (!systemPromptFile.trimAscii().isEmpty()) {
        root.put("systemPromptFile", JsonString(systemPromptFile))
    }
    writeRunState(runId, root)
    root
}

private func readRunState(runId: String): JsonObject {
    let path = runStatePath(runId)
    if (!exists(path)) {
        let root = JsonObject()
        root.put("status", JsonString("missing"))
        return root
    }
    try {
        match (JsonValue.fromStr(String.fromUtf8(File.readFrom(path)))) {
            case obj: JsonObject => obj
            case _ =>
                let root = JsonObject()
                root.put("status", JsonString("invalid"))
                root
        }
    } catch (_e: Exception) {
        let root = JsonObject()
        root.put("status", JsonString("invalid"))
        root
    }
}

public class DreamingNarrativeRunHandle {
    public let runId: String
    public let sessionKey: String

    public init(runId: String, sessionKey: String) {
        this.runId = runId
        this.sessionKey = sessionKey
    }
}

public class DreamingNarrativeRunResult {
    public let status: String
    public let error: String
    public let narrative: String

    public init(status: String, error!: String = "", narrative!: String = "") {
        this.status = status
        this.error = error
        this.narrative = narrative
    }
}

public class NarrativePhaseData {
    public let phase: String
    public let snippets: Array<String>
    public let themes: Array<String>
    public let promotions: Array<String>

    public init(
        phase: String,
        snippets: Array<String>,
        themes!: Array<String> = Array<String>(),
        promotions!: Array<String> = Array<String>()
    ) {
        this.phase = phase
        this.snippets = snippets
        this.themes = themes
        this.promotions = promotions
    }
}

public class DreamingNarrativeRunParams {
    public let sessionKey: String
    public let message: String
    public let extraSystemPrompt: String
    public let deliver: Bool

    public init(
        sessionKey: String,
        message: String,
        extraSystemPrompt!: String = "",
        deliver!: Bool = false
    ) {
        this.sessionKey = sessionKey
        this.message = message
        this.extraSystemPrompt = extraSystemPrompt
        this.deliver = deliver
    }
}

public class DreamingNarrativeWaitParams {
    public let runId: String
    public let timeoutMs: Int64

    public init(runId: String, timeoutMs!: Int64 = NARRATIVE_TIMEOUT_MS) {
        this.runId = runId
        this.timeoutMs = timeoutMs
    }
}

public class DreamingNarrativeMessagesParams {
    public let sessionKey: String
    public let limit: Int64

    public init(sessionKey: String, limit!: Int64 = 5) {
        this.sessionKey = sessionKey
        this.limit = limit
    }
}

public class DreamingNarrativeDeleteParams {
    public let sessionKey: String

    public init(sessionKey: String) {
        this.sessionKey = sessionKey
    }
}

public class DreamingNarrativeMessagesResult {
    public let messages: Array<JsonObject>

    public init(messages: Array<JsonObject>) {
        this.messages = messages
    }
}

public interface DreamingNarrativeSubagentSurface {
    func run(params: DreamingNarrativeRunParams): DreamingNarrativeRunHandle
    func waitForRun(params: DreamingNarrativeWaitParams): DreamingNarrativeRunResult
    func getSessionMessages(params: DreamingNarrativeMessagesParams): DreamingNarrativeMessagesResult
    func deleteSession(params: DreamingNarrativeDeleteParams): Unit
}

private class LocalDreamingNarrativeSubagentSurface <: DreamingNarrativeSubagentSurface {
    public func run(params: DreamingNarrativeRunParams): DreamingNarrativeRunHandle {
        DreamingNarrativeRuntime.run(
            params.sessionKey,
            params.message,
            extraSystemPrompt: params.extraSystemPrompt,
            deliver: params.deliver
        )
    }

    public func waitForRun(params: DreamingNarrativeWaitParams): DreamingNarrativeRunResult {
        DreamingNarrativeRuntime.waitForRun(params.runId, timeoutMs: params.timeoutMs)
    }

    public func getSessionMessages(params: DreamingNarrativeMessagesParams): DreamingNarrativeMessagesResult {
        DreamingNarrativeMessagesResult(
            DreamingNarrativeRuntime.getSessionMessages(params.sessionKey, limit: params.limit)
        )
    }

    public func deleteSession(params: DreamingNarrativeDeleteParams): Unit {
        DreamingNarrativeRuntime.deleteSession(params.sessionKey)
    }
}

public class DreamingNarrativeRuntime {
    public static func subagentSurface(): DreamingNarrativeSubagentSurface {
        LocalDreamingNarrativeSubagentSurface()
    }

    public static func sessionStorePath(): Path {
        CliConfig.dotDir.join("memory").join("dream-sessions")
    }

    public static func runsPath(): Path {
        narrativeRunsDir()
    }

    public static func buildNarrativePrompt(
        phase: String,
        snippets: Array<String>,
        themes!: Array<String> = Array<String>(),
        promotions!: Array<String> = Array<String>()
    ): String {
        let lines = ArrayList<String>()
        lines.add("Write a dream diary entry from these memory fragments:")
        lines.add("")
        for (snippet in snippets[0..min(snippets.size, 12)]) {
            lines.add("- ${snippet}")
        }
        if (!themes.isEmpty()) {
            lines.add("")
            lines.add("Recurring themes:")
            for (theme in themes[0..min(themes.size, 6)]) {
                lines.add("- ${theme}")
            }
        }
        if (!promotions.isEmpty()) {
            lines.add("")
            lines.add("Memories that crystallized into something lasting:")
            for (promotion in promotions[0..min(promotions.size, 5)]) {
                lines.add("- ${promotion}")
            }
        }
        lines.add("")
        lines.add("Phase: ${phase.trimAscii().toAsciiLower()}")
        String.join(lines.toArray(), delimiter: "\n")
    }

    public static func run(
        sessionKey: String,
        message: String,
        extraSystemPrompt!: String = "",
        deliver!: Bool = false
    ): DreamingNarrativeRunHandle {
        let runId = "dream-run-${DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000}"
        let store = narrativeStore()
        let systemPrompt = if (extraSystemPrompt.trimAscii().isEmpty()) {
            buildNarrativeSystemPrompt()
        } else {
            extraSystemPrompt
        }
        store.appendTranscriptEntry(sessionKey, "system", systemPrompt)
        store.appendTranscriptEntry(sessionKey, "user", message)

        let promptFile = writePromptFile(message)
        let systemPromptFile = writeSystemPromptFile(systemPrompt)
        let command = ArrayList<String>()
        command.add("cjpm")
        command.add("run")
        command.add("--skip-script")
        command.add("--skip-build")
        command.add("--name")
        command.add("cli")
        let runArgs = ArrayList<String>()
        runArgs.add("--internal-subagent")
        runArgs.add("planner")
        runArgs.add("--internal-system-prompt-file")
        runArgs.add(systemPromptFile.toString())
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
        command.add("--run-args")
        command.add(String.join(runArgs.toArray(), delimiter: " "))

        let root = JsonObject()
        root.put("runId", JsonString(runId))
        root.put("sessionKey", JsonString(sessionKey))
        root.put("backend", JsonString("internal-subagent"))
        root.put("agent", JsonString("planner"))
        root.put("deliver", deliver.toJsonValue())
        root.put("promptFile", JsonString(promptFile.toString()))
        root.put("systemPromptFile", JsonString(systemPromptFile.toString()))
        root.put("startedAt", JsonString(DateTime.now().format("yyyy-MM-dd HH:mm:ss")))
        root.put("status", JsonString("running"))
        root.put("messageCount", 2.toJsonValue())
        try {
            writeRunState(runId, root)
            let timeout = Some(Duration.millisecond * NARRATIVE_TIMEOUT_MS)
            let (exitCode, stdout, stderr) = ShellUtils.execute(
                command.toArray(),
                timeout: timeout,
                workDir: Some(CliConfig.cwd),
                withWrap: false
            )
            if (exitCode != 0) {
                let _ = updateRunState(
                    runId,
                    "error",
                    error: stderr.trimAscii(),
                    completedAt: DateTime.now().format("yyyy-MM-dd HH:mm:ss")
                )
                return DreamingNarrativeRunHandle(runId, sessionKey)
            }
            let normalized = normalizeDreamNarrativeOutput(stdout)
            if (normalized.isEmpty()) {
                let _ = updateRunState(
                    runId,
                    "empty",
                    error: "narrative output empty",
                    completedAt: DateTime.now().format("yyyy-MM-dd HH:mm:ss")
                )
                return DreamingNarrativeRunHandle(runId, sessionKey)
            }
            store.appendTranscriptEntry(sessionKey, "assistant", normalized)
            let _ = updateRunState(
                runId,
                "ok",
                assistantText: normalized,
                completedAt: DateTime.now().format("yyyy-MM-dd HH:mm:ss")
            )
        } catch (e: Exception) {
            LogUtils.error("Dream narrative run failed: ${e.message}")
            let _ = updateRunState(
                runId,
                "error",
                error: e.message,
                completedAt: DateTime.now().format("yyyy-MM-dd HH:mm:ss")
            )
        }
        DreamingNarrativeRunHandle(runId, sessionKey)
    }

    public static func waitForRun(runId: String, timeoutMs!: Int64 = NARRATIVE_TIMEOUT_MS): DreamingNarrativeRunResult {
        let _ = timeoutMs
        let state = readRunState(runId)
        let status = readJsonString(state, "status", defaultValue: "missing")
        let error = readJsonString(state, "error")
        let narrative = readJsonString(state, "assistantText")
        DreamingNarrativeRunResult(status, error: error, narrative: narrative)
    }

    public static func getSessionMessages(sessionKey: String, limit!: Int64 = 5): Array<JsonObject> {
        let out = ArrayList<JsonObject>()
        let raw = narrativeStore().readTranscriptRaw(sessionKey)
        match (raw) {
            case Some(text) =>
                let lines = text.split("\n")
                let rows = ArrayList<JsonObject>()
                for (line in lines) {
                    let trimmed = line.trimAscii()
                    if (trimmed.isEmpty()) {
                        continue
                    }
                    try {
                        let obj = JsonValue.fromStr(trimmed).asObject()
                        rows.add(obj)
                    } catch (_e: Exception) {
                        ()
                    }
                }
                let start = max(0, rows.size - max(1, limit))
                for (idx in start..rows.size) {
                    let msg = rows[idx]
                    match (msg.get("text")) {
                        case Some(text: JsonString) =>
                            match (msg.get("content")) {
                                case Some(_: JsonString) => ()
                                case _ => msg.put("content", JsonString(text.getValue()))
                            }
                        case _ => ()
                    }
                    out.add(msg)
                }
            case None => ()
        }
        out.toArray()
    }

    public static func extractNarrativeText(messages: Array<JsonObject>): Option<String> {
        var idx = messages.size - 1
        while (idx >= 0) {
            let msg = messages[idx]
            match (msg.get("role")) {
                case Some(r: JsonString) =>
                    if (r.getValue() == "assistant") {
                        match (msg.get("content")) {
                            case Some(t: JsonString) =>
                                let value = t.getValue().trimAscii()
                                if (!value.isEmpty()) {
                                    return Some(value)
                                }
                            case _ =>
                                match (msg.get("text")) {
                                    case Some(t: JsonString) =>
                                        let value = t.getValue().trimAscii()
                                        if (!value.isEmpty()) {
                                            return Some(value)
                                        }
                                    case _ => ()
                                }
                        }
                    }
                case _ => ()
            }
            idx -= 1
        }
        None
    }

    public static func deleteSession(sessionKey: String): Unit {
        let _ = narrativeStore().deleteSession(sessionKey)
        Directory.walk(narrativeRunsDir()) {
            currentFile =>
            let path = currentFile.path
            if (currentFile.isDirectory() || !path.toString().endsWith(".json")) {
                return true
            }
            try {
                let state = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
                if (readJsonString(state, "sessionKey") != sessionKey) {
                    return true
                }
                cleanupNarrativeFile(readJsonString(state, "promptFile"))
                cleanupNarrativeFile(readJsonString(state, "systemPromptFile"))
                try {
                    remove(path)
                } catch (_e: Exception) {
                    ()
                }
            } catch (_e: Exception) {
                ()
            }
            true
        }
    }

    public static func appendNarrativeEntry(narrative: String, now!: DateTime = DateTime.now()): Path {
        let dreamsPath = resolveDreamsPath()
        let existing = if (exists(dreamsPath)) {
            String.fromUtf8(File.readFrom(dreamsPath))
        } else {
            ""
        }
        let updated = appendDiaryManagedSection(existing, buildDiaryEntry(narrative, now))
        File.writeTo(dreamsPath, if (updated.endsWith("\n")) { updated.toArray() } else { (updated + "\n").toArray() })
        dreamsPath
    }

    public static func generateAndAppendDreamNarrative(data: NarrativePhaseData): String {
        generateAndAppendDreamNarrativeWithSurface(subagentSurface(), data)
    }

    public static func generateAndAppendDreamNarrativeWithSurface(
        subagent: DreamingNarrativeSubagentSurface,
        data: NarrativePhaseData
    ): String {
        let themes = data.themes
        let candidateTexts = data.promotions
        let candidates = ArrayList<LocalMemoryPromoteCandidate>()
        for (text in candidateTexts) {
            candidates.add(LocalMemoryPromoteCandidate(text, "memory/dreaming", 0, 0.0, Array<String>(), 0, 0, 0, 0.0, 0.0))
        }
        let narrative = if (shouldForceDeterministicNarrative()) {
            buildDeterministicDreamNarrative(themes, candidates.toArray())
        } else if (!data.snippets.isEmpty() || !data.promotions.isEmpty()) {
            let sessionKey = "dreaming-narrative-${data.phase.trimAscii().toAsciiLower()}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
            let handle = subagent.run(
                DreamingNarrativeRunParams(
                    sessionKey,
                    buildNarrativePrompt(data.phase, data.snippets, themes: data.themes, promotions: data.promotions),
                    extraSystemPrompt: buildNarrativeSystemPrompt(),
                    deliver: false
                )
            )
            try {
                let result = subagent.waitForRun(DreamingNarrativeWaitParams(handle.runId))
                if (result.status == "ok") {
                    match (extractNarrativeText(subagent.getSessionMessages(DreamingNarrativeMessagesParams(sessionKey, limit: 5)).messages)) {
                        case Some(text) => text
                        case None => buildDeterministicDreamNarrative(themes, candidates.toArray())
                    }
                } else {
                    buildDeterministicDreamNarrative(themes, candidates.toArray())
                }
            } finally {
                subagent.deleteSession(DreamingNarrativeDeleteParams(sessionKey))
            }
        } else {
            buildDeterministicDreamNarrative(themes, candidates.toArray())
        }
        appendNarrativeEntry(narrative)
        narrative
    }

    public static func generateNarrative(
        phase: String,
        themes: Array<String>,
        candidates: Array<LocalMemoryPromoteCandidate>
    ): String {
        generateNarrativeWithSurface(subagentSurface(), phase, themes, candidates)
    }

    public static func generateNarrativeWithSurface(
        subagent: DreamingNarrativeSubagentSurface,
        phase: String,
        themes: Array<String>,
        candidates: Array<LocalMemoryPromoteCandidate>
    ): String {
        if (shouldForceDeterministicNarrative()) {
            return buildDeterministicDreamNarrative(themes, candidates)
        }
        let snippets = ArrayList<String>()
        for (candidate in candidates[0..min(candidates.size, 6)]) {
            snippets.add(candidate.text)
        }
        if (snippets.isEmpty()) {
            return buildDeterministicDreamNarrative(themes, candidates)
        }
        let promotions = ArrayList<String>()
        if (phase.trimAscii().toAsciiLower() == "deep") {
            for (candidate in candidates[0..min(candidates.size, 5)]) {
                promotions.add(candidate.text)
            }
        }
        let sessionKey = "dreaming-narrative-${phase.trimAscii().toAsciiLower()}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}"
        let handle = subagent.run(
            DreamingNarrativeRunParams(
                sessionKey,
                buildNarrativePrompt(phase, snippets.toArray(), themes: themes, promotions: promotions.toArray()),
                extraSystemPrompt: buildNarrativeSystemPrompt(),
                deliver: false
            )
        )
        try {
            let result = subagent.waitForRun(DreamingNarrativeWaitParams(handle.runId))
            if (result.status != "ok") {
                return buildDeterministicDreamNarrative(themes, candidates)
            }
            match (extractNarrativeText(subagent.getSessionMessages(DreamingNarrativeMessagesParams(sessionKey, limit: 5)).messages)) {
                case Some(text) => return text
                case None => return buildDeterministicDreamNarrative(themes, candidates)
            }
        } finally {
            subagent.deleteSession(DreamingNarrativeDeleteParams(sessionKey))
        }
    }
}
