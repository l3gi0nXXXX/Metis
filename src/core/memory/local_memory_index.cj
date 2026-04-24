package metis.core.memory

import magic.prelude.*
import magic.log.LogUtils

import metis.core.config.CliConfig
import metis.utils.ShellUtils

import std.collection.{ArrayList, HashSet}
import std.convert.*
import std.fs.{Path, Directory, File, exists, FileInfo, OpenMode}
import std.io.*
import std.sort.sort
import std.time.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonFloat, JsonValue}

private func isMarkdownFile(path: Path): Bool {
    path.extensionName.toAsciiLower() == "md"
}

private func normalizePath(path: String): String {
    path.replace("\\", "/")
}

private func workspaceRelativePath(path: Path): String {
    let workspace = normalizePath(CliConfig.cwd.toString())
    let full = normalizePath(path.toString())
    let prefix = workspace + "/"
    if (full.startsWith(prefix)) {
        return full[prefix.size..]
    }
    if (full == workspace) {
        return path.fileName
    }
    full
}

private func normalizeSnippetLine(lineNo: Int64, line: String): String {
    let cleaned = line
        .replace("\r\n", " ")
        .replace("\n", " ")
        .replace("\r", " ")
        .replace("\t", "    ")
        .trimAscii()
    if (cleaned.isEmpty()) {
        return ""
    }
    "${lineNo}: ${cleaned}"
}

private func sqlQuote(text: String): String {
    text.replace("'", "''")
}

func buildSqliteInsertSqlForContent(path: String, content: String): String {
    let relPath = normalizePath(path)
    let statements = ArrayList<String>()
    let lines = content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    for (i in 0..lines.size) {
        let lineNo = i + 1
        let snippet = normalizeSnippetLine(lineNo, lines[i])
        if (snippet.isEmpty()) {
            continue
        }
        statements.add(
            "INSERT INTO memory_fts(path, start_line, end_line, text) VALUES ('${sqlQuote(relPath)}', ${lineNo}, ${lineNo}, '${sqlQuote(snippet)}');"
        )
    }
    String.join(statements.toArray(), delimiter: "\n")
}

private func parseInt64Or(text: String, fallback: Int64): Int64 {
    try {
        Int64.parse(text)
    } catch (_e: Exception) {
        fallback
    }
}

private func parseFloat64Or(text: String, fallback: Float64): Float64 {
    try {
        Float64.parse(text)
    } catch (_e: Exception) {
        fallback
    }
}

private func getJsonStringValue(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(s: JsonString) => s.getValue()
        case _ => fallback
    }
}

private func getJsonInt64Value(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) => parseInt64Or(v.toString(), fallback)
        case _ => fallback
    }
}

private func getJsonFloat64Value(obj: JsonObject, key: String, fallback: Float64): Float64 {
    match (obj.get(key)) {
        case Some(v) => parseFloat64Or(v.toString(), fallback)
        case _ => fallback
    }
}

private func getJsonBoolValue(obj: JsonObject, key: String, fallback: Bool): Bool {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                v.asBool().getValue()
            } catch (_e: Exception) {
                fallback
            }
        case _ => fallback
    }
}

private func shouldPromoteLine(line: String): Bool {
    let trimmed = line.trimAscii()
    if (trimmed.size < 24) {
        return false
    }
    if (trimmed.startsWith("#") || trimmed.startsWith(">")) {
        return false
    }
    if (trimmed.startsWith("- **") || trimmed.startsWith("* **")) {
        return false
    }
    if (trimmed.startsWith("```")) {
        return false
    }
    if (trimmed.startsWith("User:") || trimmed.startsWith("Assistant:") || trimmed.startsWith("System:")) {
        return false
    }
    true
}

private func normalizePromotedKey(text: String): String {
    text.trimAscii().toAsciiLower().replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
}

private func isConceptStopWord(token: String): Bool {
    token == "the" || token == "and" || token == "that" || token == "with" ||
    token == "from" || token == "this" || token == "have" || token == "will" ||
    token == "into" || token == "memory" || token == "notes" || token == "about" ||
    token == "your" || token == "their" || token == "there" || token == "where"
}

private func deriveConceptTags(text: String, limit!: Int64 = 6): Array<String> {
    let normalized = text
        .toAsciiLower()
        .replace("(", " ")
        .replace(")", " ")
        .replace("[", " ")
        .replace("]", " ")
        .replace("{", " ")
        .replace("}", " ")
        .replace(",", " ")
        .replace(".", " ")
        .replace(":", " ")
        .replace(";", " ")
        .replace("/", " ")
        .replace("\\", " ")
        .replace("\"", " ")
        .replace("'", " ")
        .replace("`", " ")
        .replace("-", " ")
    let tags = ArrayList<String>()
    let seen = HashSet<String>()
    for (piece in normalized.split(" ")) {
        let token = piece.trimAscii()
        if (token.size < 4 || isConceptStopWord(token) || seen.contains(token)) {
            continue
        }
        if (token.contains("api") || token.contains("sql") || token.contains("tool") ||
            token.contains("agent") || token.contains("prompt") || token.contains("gateway") ||
            token.contains("memory") || token.contains("index") || token.contains("search") ||
            token.contains("cron") || token.contains("session") || token.contains("model") ||
            token.contains("token") || token.contains("skill") || token.contains("sandbox")) {
            seen.add(token)
            tags.add(token)
        } else if (token.size >= 6) {
            seen.add(token)
            tags.add(token)
        }
        if (tags.size >= limit) {
            break
        }
    }
    tags.toArray()
}

private func computeRecencyBoost(lastRecalledAt: String): Float64 {
    let trimmed = lastRecalledAt.trimAscii()
    if (trimmed.isEmpty()) {
        return 0.0
    }
    try {
        let recalledAt = DateTime.parse(trimmed, "yyyy-MM-dd HH:mm:ss")
        let ageMs = (DateTime.now() - recalledAt).toMilliseconds()
        if (ageMs < 0) {
            return 0.0
        }
        let ageDays = Float64(ageMs) / 86400000.0
        if (ageDays <= 1.0) {
            return 1.0
        }
        if (ageDays <= 3.0) {
            return 0.7
        }
        if (ageDays <= 7.0) {
            return 0.4
        }
        if (ageDays <= 14.0) {
            return 0.2
        }
        0.0
    } catch (_e: Exception) {
        0.0
    }
}

private func joinTopTags(candidates: Array<LocalMemoryPromoteCandidate>, limit: Int64): Array<String> {
    let out = ArrayList<String>()
    let seen = HashSet<String>()
    for (candidate in candidates) {
        for (tag in candidate.conceptTags) {
            if (seen.contains(tag)) {
                continue
            }
            seen.add(tag)
            out.add(tag)
            if (out.size >= limit) {
                return out.toArray()
            }
        }
    }
    out.toArray()
}

private func readTextFileOrEmpty(path: Path): String {
    try {
        String.fromUtf8(readToEnd(File(path, OpenMode.Read)))
    } catch (_e: Exception) {
        ""
    }
}

private func withTrailingNewline(text: String): String {
    if (text.endsWith("\n")) {
        return text
    }
    text + "\n"
}

private func replaceManagedBlock(
    original: String,
    heading: String,
    startMarker: String,
    endMarker: String,
    body: String
): String {
    let managed = "${heading}\n${startMarker}\n${body}\n${endMarker}"
    let startIdx = original.indexOf(startMarker)
    let endIdx = original.indexOf(endMarker)
    if (let Some(start) <- startIdx) {
        if (let Some(end) <- endIdx) {
            let lineStart = match (original[..start].lastIndexOf(heading)) {
                case Some(idx) => idx
                case None => start
            }
            let suffixStart = end + endMarker.size
            let prefix = original[..lineStart].trimAscii()
            let suffix = if (suffixStart < original.size) { original[suffixStart..].trimAscii() } else { "" }
            if (prefix.isEmpty() && suffix.isEmpty()) {
                return managed + "\n"
            }
            if (suffix.isEmpty()) {
                return prefix + "\n\n" + managed + "\n"
            }
            if (prefix.isEmpty()) {
                return managed + "\n\n" + suffix + "\n"
            }
            return prefix + "\n\n" + managed + "\n\n" + suffix + "\n"
        }
    }
    let trimmed = original.trimAscii()
    if (trimmed.isEmpty()) {
        return managed + "\n"
    }
    trimmed + "\n\n" + managed + "\n"
}

private func dreamingPhaseHeading(phase: String): String {
    match (phase.trimAscii().toAsciiLower()) {
        case "light" => "## Light Sleep"
        case "rem" => "## REM Sleep"
        case "deep" => "## Deep Sleep"
        case _ => "## Dreaming"
    }
}

private func dreamingPhaseStartMarker(phase: String): String {
    "<!-- metis:dreaming:${phase.trimAscii().toAsciiLower()}:start -->"
}

private func dreamingPhaseEndMarker(phase: String): String {
    "<!-- metis:dreaming:${phase.trimAscii().toAsciiLower()}:end -->"
}

private func dreamingReportPath(phase: String, now: DateTime): Path {
    let dir = CliConfig.cwd.join("memory").join("dreaming").join(phase.trimAscii().toAsciiLower())
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir.join("${now.format("yyyy-MM-dd")}.md")
}

private func writeDreamingPhaseArtifacts(
    phase: String,
    bodyLines: Array<String>,
    now: DateTime
): (Path, Path) {
    if (phase.trimAscii().toAsciiLower() == "deep") {
        let result = DreamingMarkdownRuntime.writeDeepDreamingReport(bodyLines, now: now)
        return (
            Path(if (result.inlinePath.trimAscii().isEmpty()) { MemoryPaths.dreamsMarkdownPath().toString() } else { result.inlinePath }),
            Path(if (result.reportPath.trimAscii().isEmpty()) { dreamingReportPath(phase, now).toString() } else { result.reportPath })
        )
    }
    let result = DreamingMarkdownRuntime.writeDailyDreamingPhaseBlock(phase, bodyLines, now: now)
    (
        Path(if (result.inlinePath.trimAscii().isEmpty()) { MemoryPaths.dreamsMarkdownPath().toString() } else { result.inlinePath }),
        Path(if (result.reportPath.trimAscii().isEmpty()) { dreamingReportPath(phase, now).toString() } else { result.reportPath })
    )
}

private func buildDreamNarrative(
    themes: Array<String>,
    candidates: Array<LocalMemoryPromoteCandidate>
): String {
    DreamingNarrativeRuntime.generateNarrative("rem", themes, candidates)
}

private func readJsonStringArray(obj: JsonObject, key: String): Array<String> {
    let values = ArrayList<String>()
    match (obj.get(key)) {
        case Some(v) =>
            let arr = v.asArray()
            for (item in arr.getItems()) {
                match (item) {
                    case s: JsonString =>
                        let text = s.getValue().trimAscii()
                        if (!text.isEmpty()) {
                            values.add(text)
                        }
                    case _ => ()
                }
            }
        case _ => ()
    }
    values.toArray()
}

private func appendUniqueRecent(values: Array<String>, nextValue: String, limit: Int64): Array<String> {
    let normalized = nextValue.trimAscii()
    if (normalized.isEmpty()) {
        return values
    }
    let out = ArrayList<String>()
    let seen = HashSet<String>()
    for (value in values) {
        let trimmed = value.trimAscii()
        if (trimmed.isEmpty() || seen.contains(trimmed)) {
            continue
        }
        seen.add(trimmed)
        out.add(trimmed)
    }
    if (!seen.contains(normalized)) {
        out.add(normalized)
    }
    while (out.size > limit) {
        out.remove(at: 0)
    }
    out.toArray()
}

private func collectMemoryMarkdownFiles(root: Path, files: ArrayList<Path>): Unit {
    if (!exists(root)) {
        return
    }
    if (FileInfo(root).isRegular()) {
        if (isMarkdownFile(root)) {
            files.add(root)
        }
        return
    }
    for (entry in Directory.readFrom(root)) {
        let p = entry.path
        if (FileInfo(p).isDirectory()) {
            if (p.fileName == ".dreams" || p.fileName == "dreaming") {
                continue
            }
            collectMemoryMarkdownFiles(p, files)
        } else if (FileInfo(p).isRegular() && isMarkdownFile(p)) {
            files.add(p)
        }
    }
}

public class LocalMemorySearchRow {
    public let path: String
    public let startLine: Int64
    public let endLine: Int64
    public let text: String

    public init(path: String, startLine: Int64, endLine: Int64, text: String) {
        this.path = path
        this.startLine = startLine
        this.endLine = endLine
        this.text = text
    }
}

public class LocalMemoryPromoteCandidate {
    public let text: String
    public let sourcePath: String
    public let line: Int64
    public let score: Float64
    public let conceptTags: Array<String>
    public let recallCount: Int64
    public let uniqueQueries: Int64
    public let recallDays: Int64
    public let recencyBoost: Float64
    public let avgScore: Float64

    public init(
        text: String,
        sourcePath: String,
        line: Int64,
        score: Float64,
        conceptTags: Array<String>,
        recallCount: Int64,
        uniqueQueries: Int64,
        recallDays: Int64,
        recencyBoost: Float64,
        avgScore: Float64
    ) {
        this.text = text
        this.sourcePath = sourcePath
        this.line = line
        this.score = score
        this.conceptTags = conceptTags
        this.recallCount = recallCount
        this.uniqueQueries = uniqueQueries
        this.recallDays = recallDays
        this.recencyBoost = recencyBoost
        this.avgScore = avgScore
    }
}

public class LocalMemoryRecallResult {
    public let path: String
    public let startLine: Int64
    public let endLine: Int64
    public let score: Float64
    public let snippet: String

    public init(path: String, startLine: Int64, endLine: Int64, score: Float64, snippet: String) {
        this.path = path
        this.startLine = startLine
        this.endLine = endLine
        this.score = score
        this.snippet = snippet
    }
}

protected class LocalMemoryIndexManager {
    public static func resolveMemoryFiles(): Array<Path> {
        let files = ArrayList<Path>()
        let workspace = CliConfig.cwd
        let memoryRoot = workspace.join("MEMORY.md")
        let memoryAlt = workspace.join("memory.md")
        let dailyDir = workspace.join("memory")

        if (exists(memoryRoot)) {
            files.add(memoryRoot)
        } else if (exists(memoryAlt)) {
            files.add(memoryAlt)
        }
        collectMemoryMarkdownFiles(dailyDir, files)

        let out = files.toArray()
        sort(out, by: { a, b => a.toString().compare(b.toString()) }, stable: true)
        out
    }

    private static func loadPromotedAuditKeys(): HashSet<String> {
        let keys = HashSet<String>()
        let path = MemoryPaths.promotedAuditPath()
        if (!exists(path)) {
            return keys
        }
        let content = try {
            String.fromUtf8(File.readFrom(path))
        } catch (_e: Exception) {
            return keys
        }
        for (line in content.replace("\r\n", "\n").replace("\r", "\n").split("\n")) {
            let key = normalizePromotedKey(line)
            if (!key.isEmpty()) {
                keys.add(key)
            }
        }
        keys
    }

    private static func readShortTermRecallStore(): JsonObject {
        ShortTermPromotionRuntime.readRecallStore()
    }

    public static func recordShortTermRecall(query: String, results: Array<LocalMemoryRecallResult>): Unit {
        ShortTermPromotionRuntime.recordRecall(query, results)
    }

    private static func markPromotedAt(candidates: Array<LocalMemoryPromoteCandidate>): Unit {
        ShortTermPromotionRuntime.markPromoted(candidates)
    }

    public static func buildStatusJson(deep!: Bool = false): String {
        buildStatusJson(agentId: "", purpose: if (deep) { "status-deep" } else { "status" }, deep: deep)
    }

    public static func buildStatusJson(
        agentId!: String = "",
        purpose!: String = "status",
        deep!: Bool = false
    ): String {
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) {
            if (deep) { "status-deep" } else { "status" }
        } else {
            purpose.trimAscii()
        }
        let resolved = MemoryRuntimeRegistry.resolveBackendConfig(
            agentId: agentId.trimAscii(),
            purpose: resolvedPurpose
        )
        let files = MemoryRuntime.resolveMemoryFiles(agentId: resolved.agentId, purpose: "status-resolve-files")
        let store = readShortTermRecallStore()
        let root = JsonObject()
        root.put("status", JsonString("ok"))
        root.put("action", JsonString("memory_status"))
        root.put("deep", deep.toJsonValue())
        root.put("provider", JsonString(resolved.providerId))
        root.put("backend", JsonString(resolved.backend))
        root.put("resolvedBackendConfig", resolved.toJsonObject())
        root.put("workspace", JsonString(CliConfig.cwd.toString()))
        root.put("indexStorePath", JsonString(MemoryPaths.indexStorePath().toString()))
        root.put("sqliteStorePath", JsonString(MemoryPaths.sqliteStorePath().toString()))
        root.put("shortTermRecallPath", JsonString(MemoryPaths.shortTermRecallPath().toString()))
        root.put("phaseSignalPath", JsonString(ShortTermPromotionRuntime.phaseSignalsPath().toString()))
        root.put("shortTermLockPath", JsonString(ShortTermPromotionRuntime.runtimeLockPath().toString()))
        root.put("dailyIngestionStatePath", JsonString(DailyIngestionRuntime.statePath().toString()))
        root.put("dreamingMarkdownConfigPath", JsonString(DreamingMarkdownRuntime.configPath().toString()))
        root.put("dreamingPhaseConfigPath", JsonString(DreamingPhaseRuntime.configPath().toString()))
        root.put("dreamingNarrativeRunsPath", JsonString(DreamingNarrativeRuntime.runsPath().toString()))
        root.put("dreamingNarrativeSessionsPath", JsonString(DreamingNarrativeRuntime.sessionStorePath().toString()))
        root.put("promotedAuditPath", JsonString(MemoryPaths.promotedAuditPath().toString()))
        root.put("durableMemoryPath", JsonString(MemoryPaths.durableMemoryPath().toString()))
        root.put("fileCount", files.size.toJsonValue())
        root.put("sqliteReady", exists(MemoryPaths.sqliteStorePath()).toJsonValue())
        root.put("indexSnapshotPresent", (!readIndexSnapshot().isEmpty()).toJsonValue())
        let summary = JsonObject()
        summary.put("updatedAt", JsonString(getJsonStringValue(store, "updatedAt", "")))
        summary.put("entryCount", getJsonInt64Value(store, "entryCount", 0).toJsonValue())
        summary.put("promotedCount", getJsonInt64Value(store, "promotedCount", 0).toJsonValue())
        summary.put("maxRecallCount", getJsonInt64Value(store, "maxRecallCount", 0).toJsonValue())
        summary.put("conceptTaggedCount", getJsonInt64Value(store, "conceptTaggedCount", 0).toJsonValue())
        root.put("shortTermRecall", summary)
        match (JsonValue.fromStr(ShortTermPromotionRuntime.buildAuditSummaryJson())) {
            case obj: JsonObject => root.put("shortTermAudit", obj)
            case _ => ()
        }
        match (JsonValue.fromStr(DailyIngestionRuntime.buildStatusSummaryJson())) {
            case obj: JsonObject => root.put("dailyIngestion", obj)
            case _ => ()
        }
        match (JsonValue.fromStr(DreamingMarkdownRuntime.buildStatusJson())) {
            case obj: JsonObject => root.put("dreamingMarkdown", obj)
            case _ => ()
        }
        match (JsonValue.fromStr(DreamingPhaseRuntime.buildStatusJson())) {
            case obj: JsonObject => root.put("dreamingPhases", obj)
            case _ => ()
        }
        let fileRows = JsonArray([])
        for (path in files) {
            fileRows.add(JsonString(workspaceRelativePath(path)))
        }
        root.put("files", fileRows)
        let providers = JsonArray([])
        for (providerId in MemoryRuntimeRegistry.registeredProviderIds()) {
            providers.add(JsonString(providerId))
        }
        root.put("availableProviders", providers)
        if (deep) {
            let probe = JsonObject()
            probe.put("workspaceMemoryDirPresent", exists(CliConfig.cwd.join("memory")).toJsonValue())
            probe.put("durableMemoryPresent", exists(MemoryPaths.durableMemoryPath()).toJsonValue())
            probe.put("sqliteStorePresent", exists(MemoryPaths.sqliteStorePath()).toJsonValue())
            probe.put("recallStorePresent", exists(MemoryPaths.shortTermRecallPath()).toJsonValue())
            probe.put("phaseSignalPresent", exists(ShortTermPromotionRuntime.phaseSignalsPath()).toJsonValue())
            probe.put("shortTermLockPresent", exists(ShortTermPromotionRuntime.runtimeLockPath()).toJsonValue())
            probe.put("dailyIngestionStatePresent", exists(DailyIngestionRuntime.statePath()).toJsonValue())
            probe.put("dreamingMarkdownConfigPresent", exists(DreamingMarkdownRuntime.configPath()).toJsonValue())
            probe.put("dreamingPhaseConfigPresent", exists(DreamingPhaseRuntime.configPath()).toJsonValue())
            probe.put("dreamingNarrativeRunsPresent", exists(DreamingNarrativeRuntime.runsPath()).toJsonValue())
            probe.put("dreamingNarrativeSessionsPresent", exists(DreamingNarrativeRuntime.sessionStorePath()).toJsonValue())
            probe.put("promotedAuditPresent", exists(MemoryPaths.promotedAuditPath()).toJsonValue())
            probe.put("indexSnapshotBytes", if (exists(MemoryPaths.indexStorePath())) { FileInfo(MemoryPaths.indexStorePath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("sqliteStoreBytes", if (exists(MemoryPaths.sqliteStorePath())) { FileInfo(MemoryPaths.sqliteStorePath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("recallStoreBytes", if (exists(MemoryPaths.shortTermRecallPath())) { FileInfo(MemoryPaths.shortTermRecallPath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("phaseSignalBytes", if (exists(ShortTermPromotionRuntime.phaseSignalsPath())) { FileInfo(ShortTermPromotionRuntime.phaseSignalsPath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("shortTermLockBytes", if (exists(ShortTermPromotionRuntime.runtimeLockPath())) { FileInfo(ShortTermPromotionRuntime.runtimeLockPath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("dailyIngestionStateBytes", if (exists(DailyIngestionRuntime.statePath())) { FileInfo(DailyIngestionRuntime.statePath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("dreamingMarkdownConfigBytes", if (exists(DreamingMarkdownRuntime.configPath())) { FileInfo(DreamingMarkdownRuntime.configPath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("dreamingPhaseConfigBytes", if (exists(DreamingPhaseRuntime.configPath())) { FileInfo(DreamingPhaseRuntime.configPath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("dreamingNarrativeRunsBytes", if (exists(DreamingNarrativeRuntime.runsPath())) { FileInfo(DreamingNarrativeRuntime.runsPath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("dreamingNarrativeSessionsBytes", if (exists(DreamingNarrativeRuntime.sessionStorePath())) { FileInfo(DreamingNarrativeRuntime.sessionStorePath()).size.toJsonValue() } else { 0.toJsonValue() })
            probe.put("promotedAuditBytes", if (exists(MemoryPaths.promotedAuditPath())) { FileInfo(MemoryPaths.promotedAuditPath()).size.toJsonValue() } else { 0.toJsonValue() })
            root.put("probe", probe)
        }
        root.toJsonString()
    }

    private static func appendPromotedAuditKeys(candidates: Array<LocalMemoryPromoteCandidate>): Unit {
        let path = MemoryPaths.promotedAuditPath()
        try (file = File(path, OpenMode.Append)) {
            for (candidate in candidates) {
                file.write((normalizePromotedKey(candidate.text) + "\n").toArray())
            }
        }
    }

    private static func promoteScore(
        line: String,
        relPath: String,
        recallCount!: Int64 = 0,
        uniqueQueries!: Int64 = 0,
        recallDays!: Int64 = 0,
        recencyBoost!: Float64 = 0.0
    ): Float64 {
        var score = Float64(line.size)
        let lower = line.toAsciiLower()
        let conceptTags = deriveConceptTags(line)
        if (lower.contains("always") || lower.contains("never") || lower.contains("must")) {
            score += 12.0
        }
        if (lower.contains("remember") || lower.contains("prefer") || lower.contains("important")) {
            score += 8.0
        }
        if (relPath.contains("clear") || relPath.contains("compaction")) {
            score += 4.0
        }
        score += Float64(conceptTags.size) * 1.5
        score += Float64(recallCount) * 2.0
        score += Float64(uniqueQueries) * 1.5
        score += Float64(recallDays) * 1.0
        score += recencyBoost * 6.0
        score / 10.0
    }

    private static func collectPromoteCandidates(limit: Int64, includePromoted!: Bool = false): Array<LocalMemoryPromoteCandidate> {
        let out = ArrayList<LocalMemoryPromoteCandidate>()
        let seen = HashSet<String>()
        let promotedAudit = ShortTermPromotionRuntime.loadPromotedAuditKeys()
        let durablePath = MemoryPaths.durableMemoryPath()
        let durableContent = if (exists(durablePath)) {
            try {
                String.fromUtf8(File.readFrom(durablePath))
            } catch (_e: Exception) {
                ""
            }
        } else {
            ""
        }

        for (path in resolveMemoryFiles()) {
            let relPath = workspaceRelativePath(path)
            if (relPath == "MEMORY.md" || relPath == "memory.md") {
                continue
            }
            let content = try {
                String.fromUtf8(File.readFrom(path))
            } catch (_e: Exception) {
                ""
            }
            let lines = content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
            for (i in 0..lines.size) {
                let candidate = lines[i].trimAscii()
                if (!shouldPromoteLine(candidate)) {
                    continue
                }
                if (seen.contains(candidate)) {
                    continue
                }
                match (ShortTermPromotionRuntime.buildPromotionCandidate(
                    candidate,
                    relPath,
                    i + 1,
                    durableContent,
                    includePromoted,
                    promotedAudit
                )) {
                    case Some(decorated) =>
                        seen.add(candidate)
                        out.add(decorated)
                    case None => ()
                }
            }
        }
        let ordered = out.toArray()
        sort(ordered, by: { a, b =>
            if (a.score == b.score) {
                if (a.sourcePath == b.sourcePath) {
                    a.line.compare(b.line)
                } else {
                    a.sourcePath.compare(b.sourcePath)
                }
            } else {
                if (a.score > b.score) {
                    Ordering.LT
                } else {
                    Ordering.GT
                }
            }
        }, stable: true)
        if (ordered.size <= limit) {
            return ordered
        }
        ordered[0..limit]
    }

    private static func filterPromoteCandidates(
        candidates: Array<LocalMemoryPromoteCandidate>,
        limit: Int64,
        minScore!: Float64 = 0.0,
        minRecallCount!: Int64 = 0,
        minUniqueQueries!: Int64 = 0
    ): Array<LocalMemoryPromoteCandidate> {
        let out = ArrayList<LocalMemoryPromoteCandidate>()
        for (candidate in candidates) {
            if (candidate.score < minScore) {
                continue
            }
            if (candidate.recallCount < minRecallCount) {
                continue
            }
            if (candidate.uniqueQueries < minUniqueQueries) {
                continue
            }
            out.add(candidate)
            if (out.size >= max(1, limit)) {
                break
            }
        }
        out.toArray()
    }

    public static func previewPromote(
        limit!: Int64 = 8,
        includePromoted!: Bool = false,
        minScore!: Float64 = ShortTermPromotionRuntime.defaultPromotionMinScore(),
        minRecallCount!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinRecallCount(),
        minUniqueQueries!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()
    ): String {
        let candidates = filterPromoteCandidates(
            collectPromoteCandidates(max(1, limit * 2), includePromoted: includePromoted),
            max(1, limit),
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
        if (candidates.isEmpty()) {
            return "No promote candidates found in memory/*.md."
        }
        let lines = ArrayList<String>()
        lines.add("Promote candidates:")
        var index: Int64 = 1
        for (candidate in candidates) {
            lines.add("${index}. [score=${candidate.score}] ${candidate.text}")
            lines.add("   from ${candidate.sourcePath}:${candidate.line}")
            lines.add("   recall=${candidate.recallCount}, avg=${candidate.avgScore}, queries=${candidate.uniqueQueries}, days=${candidate.recallDays}, recency=${candidate.recencyBoost}")
            if (!candidate.conceptTags.isEmpty()) {
                lines.add("   tags: ${String.join(candidate.conceptTags, delimiter: ", ")}")
            }
            index += 1
        }
        String.join(lines.toArray(), delimiter: "\n")
    }

    public static func previewPromoteJson(
        limit!: Int64 = 8,
        includePromoted!: Bool = false,
        minScore!: Float64 = ShortTermPromotionRuntime.defaultPromotionMinScore(),
        minRecallCount!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinRecallCount(),
        minUniqueQueries!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()
    ): String {
        let candidates = filterPromoteCandidates(
            collectPromoteCandidates(max(1, limit * 2), includePromoted: includePromoted),
            max(1, limit),
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
        let rows = JsonArray([])
        for (candidate in candidates) {
            let row = JsonObject()
            row.put("text", JsonString(candidate.text))
            row.put("sourcePath", JsonString(candidate.sourcePath))
            row.put("line", candidate.line.toJsonValue())
            row.put("score", JsonFloat(candidate.score))
            row.put("recallCount", candidate.recallCount.toJsonValue())
            row.put("avgScore", JsonFloat(candidate.avgScore))
            row.put("uniqueQueries", candidate.uniqueQueries.toJsonValue())
            row.put("recallDays", candidate.recallDays.toJsonValue())
            row.put("recencyBoost", JsonFloat(candidate.recencyBoost))
            let tagRows = JsonArray([])
            for (tag in candidate.conceptTags) {
                tagRows.add(JsonString(tag))
            }
            row.put("conceptTags", tagRows)
            rows.add(row)
        }
        let root = JsonObject()
        root.put("status", JsonString("ok"))
        root.put("action", JsonString("memory_promote_preview"))
        root.put("limit", limit.toJsonValue())
        root.put("includePromoted", includePromoted.toJsonValue())
        root.put("minScore", JsonFloat(minScore))
        root.put("minRecallCount", minRecallCount.toJsonValue())
        root.put("minUniqueQueries", minUniqueQueries.toJsonValue())
        root.put("candidateCount", candidates.size.toJsonValue())
        root.put("candidates", rows)
        root.toJsonString()
    }

    public static func explainPromote(
        selector: String,
        json!: Bool = false,
        limit!: Int64 = 12,
        includePromoted!: Bool = false,
        minScore!: Float64 = ShortTermPromotionRuntime.defaultPromotionMinScore(),
        minRecallCount!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinRecallCount(),
        minUniqueQueries!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()
    ): String {
        let trimmed = selector.trimAscii()
        if (trimmed.isEmpty()) {
            return if (json) {
                let root = JsonObject()
                root.put("status", JsonString("error"))
                root.put("action", JsonString("memory_promote_explain"))
                root.put("error", JsonString("selector is required"))
                root.toJsonString()
            } else {
                "Memory promote-explain requires a non-empty selector."
            }
        }

        let lower = trimmed.toAsciiLower()
        var matched: Option<LocalMemoryPromoteCandidate> = None
        for (candidate in filterPromoteCandidates(
            collectPromoteCandidates(max(1, limit * 2), includePromoted: includePromoted),
            max(1, limit),
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )) {
            if (candidate.text.toAsciiLower().contains(lower) || candidate.sourcePath.toAsciiLower().contains(lower)) {
                matched = Some(candidate)
                break
            }
        }
        if (let Some(candidate) <- matched) {
            let reasons = ArrayList<String>()
            reasons.add("Candidate is present in short-term memory notes but not yet in durable memory.")
            reasons.add("Source: ${candidate.sourcePath}:${candidate.line}")
            reasons.add("Score: ${candidate.score}")
            reasons.add("Recall count: ${candidate.recallCount}, avg score: ${candidate.avgScore}, unique queries: ${candidate.uniqueQueries}, recall days: ${candidate.recallDays}, recency boost: ${candidate.recencyBoost}")
            reasons.add("Components: frequency=${Float64(candidate.recallCount) / 10.0}, relevance=${candidate.avgScore}, diversity=${Float64(candidate.uniqueQueries) / 10.0}, recency=${candidate.recencyBoost}, consolidation=${Float64(candidate.recallDays) / 10.0}, conceptual=${Float64(candidate.conceptTags.size) / 10.0}")
            let lowerText = candidate.text.toAsciiLower()
            if (lowerText.contains("always") || lowerText.contains("never") || lowerText.contains("must")) {
                reasons.add("Contains policy-like language, which raises promotion priority.")
            }
            if (lowerText.contains("remember") || lowerText.contains("prefer") || lowerText.contains("important")) {
                reasons.add("Contains durable-memory cue words such as remember/prefer/important.")
            }
            if (json) {
                let root = JsonObject()
                root.put("status", JsonString("ok"))
                root.put("action", JsonString("memory_promote_explain"))
                root.put("selector", JsonString(trimmed))
                root.put("includePromoted", includePromoted.toJsonValue())
                root.put("minScore", JsonFloat(minScore))
                root.put("minRecallCount", minRecallCount.toJsonValue())
                root.put("minUniqueQueries", minUniqueQueries.toJsonValue())
                let candidateObj = JsonObject()
                candidateObj.put("text", JsonString(candidate.text))
                candidateObj.put("sourcePath", JsonString(candidate.sourcePath))
                candidateObj.put("line", candidate.line.toJsonValue())
                candidateObj.put("score", JsonFloat(candidate.score))
                candidateObj.put("recallCount", candidate.recallCount.toJsonValue())
                candidateObj.put("avgScore", JsonFloat(candidate.avgScore))
                candidateObj.put("uniqueQueries", candidate.uniqueQueries.toJsonValue())
                candidateObj.put("recallDays", candidate.recallDays.toJsonValue())
                candidateObj.put("recencyBoost", JsonFloat(candidate.recencyBoost))
                let components = JsonObject()
                components.put("frequency", JsonFloat(Float64(candidate.recallCount) / 10.0))
                components.put("relevance", JsonFloat(candidate.avgScore))
                components.put("diversity", JsonFloat(Float64(candidate.uniqueQueries) / 10.0))
                components.put("recency", JsonFloat(candidate.recencyBoost))
                components.put("consolidation", JsonFloat(Float64(candidate.recallDays) / 10.0))
                components.put("conceptual", JsonFloat(Float64(candidate.conceptTags.size) / 10.0))
                candidateObj.put("components", components)
                let tagRows = JsonArray([])
                for (tag in candidate.conceptTags) {
                    tagRows.add(JsonString(tag))
                }
                candidateObj.put("conceptTags", tagRows)
                root.put("candidate", candidateObj)
                let reasonRows = JsonArray([])
                for (reason in reasons) {
                    reasonRows.add(JsonString(reason))
                }
                root.put("reasons", reasonRows)
                return root.toJsonString()
            }

            let lines = ArrayList<String>()
            lines.add("Promote explain:")
            lines.add("- Text: ${candidate.text}")
            for (reason in reasons) {
                lines.add("- ${reason}")
            }
            return String.join(lines.toArray(), delimiter: "\n")
        }

        if (json) {
            let root = JsonObject()
            root.put("status", JsonString("not_found"))
            root.put("action", JsonString("memory_promote_explain"))
            root.put("selector", JsonString(trimmed))
            root.put("includePromoted", includePromoted.toJsonValue())
            root.put("minScore", JsonFloat(minScore))
            root.put("minRecallCount", minRecallCount.toJsonValue())
            root.put("minUniqueQueries", minUniqueQueries.toJsonValue())
            root.put("error", JsonString("No promote candidate matched the selector."))
            return root.toJsonString()
        }
        "No promote candidate matched '${trimmed}'."
    }

    public static func applyPromote(
        limit!: Int64 = 8,
        includePromoted!: Bool = false,
        minScore!: Float64 = ShortTermPromotionRuntime.defaultPromotionMinScore(),
        minRecallCount!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinRecallCount(),
        minUniqueQueries!: Int64 = ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()
    ): String {
        let candidates = filterPromoteCandidates(
            collectPromoteCandidates(max(1, limit * 2), includePromoted: includePromoted),
            max(1, limit),
            minScore: minScore,
            minRecallCount: minRecallCount,
            minUniqueQueries: minUniqueQueries
        )
        if (candidates.isEmpty()) {
            return "No promote candidates found in memory/*.md."
        }
        let durablePath = MemoryPaths.durableMemoryPath()
        try {
            if (!exists(durablePath)) {
                File.writeTo(durablePath, "# Durable Memory\n\n".toArray())
            }
            try (file = File(durablePath, OpenMode.Append)) {
                file.write("\n## Promoted on ${DateTime.now().format("yyyy-MM-dd HH:mm:ss")}\n".toArray())
                for (candidate in candidates) {
                    file.write("- ${candidate.text}\n".toArray())
                }
            }
            appendPromotedAuditKeys(candidates)
            markPromotedAt(candidates)
            let _ = writeIndexSnapshot()
            return "Promoted ${candidates.size} candidate(s) into ${durablePath} (audit: ${MemoryPaths.promotedAuditPath()})"
        } catch (e: Exception) {
            LogUtils.error("Failed to promote memory candidates: ${e.message}")
            return "Memory promote failed: ${e.message}"
        }
    }

    public static func previewRemHarness(json!: Bool = false, includePromoted!: Bool = false, limit!: Int64 = 6): String {
        let candidates = collectPromoteCandidates(max(1, limit), includePromoted: includePromoted)
        let themes = joinTopTags(candidates, 8)
        let promotions = ArrayList<String>()
        let snippets = ArrayList<String>()
        for (candidate in candidates) {
            snippets.add(candidate.text)
            promotions.add(candidate.text)
        }

        if (json) {
            let root = JsonObject()
            root.put("status", JsonString("ok"))
            root.put("action", JsonString("memory_rem_harness"))
            root.put("includePromoted", includePromoted.toJsonValue())
            root.put("candidateCount", candidates.size.toJsonValue())
            let themeRows = JsonArray([])
            for (theme in themes) {
                themeRows.add(JsonString(theme))
            }
            root.put("themes", themeRows)
            let snippetRows = JsonArray([])
            for (snippet in snippets) {
                snippetRows.add(JsonString(snippet))
            }
            root.put("snippets", snippetRows)
            let promotionRows = JsonArray([])
            for (promotion in promotions) {
                promotionRows.add(JsonString(promotion))
            }
            root.put("promotions", promotionRows)
            let diaryPrompt = JsonObject()
            diaryPrompt.put("phase", JsonString("rem"))
            diaryPrompt.put("narrativeHint", JsonString("Weave recurring themes and crystallized memories into a short reflective diary entry."))
            diaryPrompt.put("themeCount", themes.size.toJsonValue())
            diaryPrompt.put("promotionCount", promotions.size.toJsonValue())
            diaryPrompt.put("narrative", JsonString(buildDreamNarrative(themes, candidates)))
            root.put("diaryPreview", diaryPrompt)
            return root.toJsonString()
        }

        let lines = ArrayList<String>()
        lines.add("REM Harness Preview:")
        lines.add("Candidates: ${candidates.size}")
        if (!themes.isEmpty()) {
            lines.add("Themes: ${String.join(themes, delimiter: ", ")}")
        }
        if (!promotions.isEmpty()) {
            lines.add("Promotions:")
            for (promotion in promotions) {
                lines.add("- ${promotion}")
            }
        }
        lines.add("")
        lines.add("Diary preview:")
        lines.add(buildDreamNarrative(themes, candidates))
        String.join(lines.toArray(), delimiter: "\n")
    }

    public static func applyRemHarness(includePromoted!: Bool = false, limit!: Int64 = 6, lookbackDays!: Int64 = 14): String {
        let ingestion = DailyIngestionRuntime.ingestForDreaming("rem", lookbackDays: lookbackDays, limit: max(6, limit))
        let candidates = collectPromoteCandidates(max(1, limit), includePromoted: includePromoted)
        let themes = joinTopTags(candidates, 8)
        let now = DateTime.now()
        let ts = now.format("yyyy_MM_dd-HH_mm_ss")
        let reportPath = MemoryPaths.dreamsDirPath().join("rem-harness-${ts}.md")
        let reportLines = ArrayList<String>()
        reportLines.add("# REM Harness Preview")
        reportLines.add("")
        reportLines.add("- Generated: ${now.format("yyyy-MM-dd HH:mm:ss")}")
        reportLines.add("- Candidate count: ${candidates.size}")
        reportLines.add("- Include promoted: ${includePromoted}")
        if (!themes.isEmpty()) {
            reportLines.add("- Themes: ${String.join(themes, delimiter: ", ")}")
        }
        reportLines.add("")
        reportLines.add("## Promotions")
        reportLines.add("")
        for (candidate in candidates) {
            reportLines.add("- ${candidate.text}")
        }
        reportLines.add("")
        reportLines.add("## Diary Preview")
        reportLines.add("")
        let narrative = buildDreamNarrative(themes, candidates)
        reportLines.add(narrative)

        let phaseBody = ArrayList<String>()
        phaseBody.add("### Reflections")
        if (!themes.isEmpty()) {
            for (theme in themes) {
                phaseBody.add("- Theme: `${theme}`")
            }
        } else {
            phaseBody.add("- No strong patterns surfaced.")
        }
        phaseBody.add("")
        phaseBody.add("### Possible Lasting Truths")
        if (!candidates.isEmpty()) {
            for (candidate in candidates[0..min(candidates.size, 3)]) {
                phaseBody.add("- ${candidate.text} [confidence=${candidate.avgScore}]")
            }
        } else {
            phaseBody.add("- No strong candidate truths surfaced.")
        }

        try {
            let remSignalKeys = ArrayList<String>()
            for (candidate in candidates[0..min(candidates.size, 3)]) {
                remSignalKeys.add("memory:${candidate.sourcePath}:${candidate.line}:${candidate.line}")
            }
            ShortTermPromotionRuntime.recordDreamingPhaseSignals("rem", remSignalKeys.toArray())
            let (_inlinePath, phaseReportPath) = writeDreamingPhaseArtifacts("rem", phaseBody.toArray(), now)
            File.writeTo(reportPath, String.join(reportLines.toArray(), delimiter: "\n").toArray())
            let dreamsPath = DreamingNarrativeRuntime.appendNarrativeEntry(narrative, now: now)
            return "${ingestion.summaryLine()}\nREM harness report written: ${reportPath}\nREM phase report written: ${phaseReportPath}\nDream diary updated: ${dreamsPath}"
        } catch (e: Exception) {
            LogUtils.error("Failed to apply REM harness preview: ${e.message}")
            return "${ingestion.summaryLine()}\nMemory rem-harness apply failed: ${e.message}"
        }
    }

    public static func applyLightDreaming(includePromoted!: Bool = false, limit!: Int64 = 6, lookbackDays!: Int64 = 14): String {
        let ingestion = DailyIngestionRuntime.ingestForDreaming("light", lookbackDays: lookbackDays, limit: max(6, limit))
        let candidates = collectPromoteCandidates(max(1, limit), includePromoted: includePromoted)
        let themes = joinTopTags(candidates, 8)
        let now = DateTime.now()
        let ts = now.format("yyyy_MM_dd-HH_mm_ss")
        let reportPath = MemoryPaths.dreamsDirPath().join("light-dreaming-${ts}.md")

        let reportLines = ArrayList<String>()
        reportLines.add("# Light Dreaming")
        reportLines.add("")
        reportLines.add("- Generated: ${now.format("yyyy-MM-dd HH:mm:ss")}")
        reportLines.add("- Candidate count: ${candidates.size}")
        reportLines.add("- Include promoted: ${includePromoted}")
        if (!themes.isEmpty()) {
            reportLines.add("- Themes: ${String.join(themes, delimiter: ", ")}")
        }
        reportLines.add("")
        reportLines.add("## Staged Memories")
        reportLines.add("")
        for (candidate in candidates) {
            reportLines.add("- ${candidate.text}")
        }
        reportLines.add("")
        reportLines.add("## Narrative")
        reportLines.add("")
        let narrative = buildDreamNarrative(themes, candidates)
        reportLines.add(narrative)

        let phaseBody = ArrayList<String>()
        if (candidates.isEmpty()) {
            phaseBody.add("- No notable updates.")
        } else {
            for (candidate in candidates) {
                phaseBody.add("- Candidate: ${candidate.text}")
                phaseBody.add("  - confidence: ${candidate.avgScore}")
                phaseBody.add("  - evidence: ${candidate.sourcePath}:${candidate.line}")
                phaseBody.add("  - recalls: ${candidate.recallCount}")
                phaseBody.add("  - status: staged")
            }
        }

        try {
            let lightSignalKeys = ArrayList<String>()
            for (candidate in candidates) {
                lightSignalKeys.add("memory:${candidate.sourcePath}:${candidate.line}:${candidate.line}")
            }
            ShortTermPromotionRuntime.recordDreamingPhaseSignals("light", lightSignalKeys.toArray())
            let (_inlinePath, phaseReportPath) = writeDreamingPhaseArtifacts("light", phaseBody.toArray(), now)
            File.writeTo(reportPath, String.join(reportLines.toArray(), delimiter: "\n").toArray())
            return "${ingestion.summaryLine()}\nLight dreaming report written: ${reportPath}\nLight phase report written: ${phaseReportPath}\nDeep phase is responsible for durable promotion into ${MemoryPaths.durableMemoryPath()}."
        } catch (e: Exception) {
            LogUtils.error("Failed to write light dreaming report: ${e.message}")
            return "${ingestion.summaryLine()}\nMemory light dreaming failed: ${e.message}"
        }
    }

    public static func applyDeepDreaming(includePromoted!: Bool = false, limit!: Int64 = 6, lookbackDays!: Int64 = 21): String {
        let ingestion = DailyIngestionRuntime.ingestForDreaming("deep", lookbackDays: lookbackDays, limit: max(6, limit))
        let candidates = collectPromoteCandidates(max(1, limit), includePromoted: includePromoted)
        let now = DateTime.now()
        let body = ArrayList<String>()
        body.add("### Durable Memory Consolidation")
        body.add("- policy: score>=${ShortTermPromotionRuntime.defaultPromotionMinScore()}, recalls>=${ShortTermPromotionRuntime.defaultPromotionMinRecallCount()}, uniqueQueries>=${ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()}")
        if (candidates.isEmpty()) {
            body.add("- No durable changes.")
        } else {
            for (candidate in candidates) {
                body.add("- ${candidate.text} [score=${candidate.score}, source=${candidate.sourcePath}:${candidate.line}, recalls=${candidate.recallCount}, queries=${candidate.uniqueQueries}]")
            }
        }
        let promoteResult = applyPromote(
            limit: limit,
            includePromoted: includePromoted,
            minScore: ShortTermPromotionRuntime.defaultPromotionMinScore(),
            minRecallCount: ShortTermPromotionRuntime.defaultPromotionMinRecallCount(),
            minUniqueQueries: ShortTermPromotionRuntime.defaultPromotionMinUniqueQueries()
        )
        try {
            let (inlinePath, reportPath) = writeDreamingPhaseArtifacts("deep", body.toArray(), now)
            return "${ingestion.summaryLine()}\nDeep dreaming inline report written: ${inlinePath}\nDeep dreaming report written: ${reportPath}\n${promoteResult}"
        } catch (e: Exception) {
            LogUtils.error("Failed to write deep dreaming report: ${e.message}")
            return "${ingestion.summaryLine()}\nMemory deep dreaming failed: ${e.message}\n${promoteResult}"
        }
    }

    public static func applyDreamingPhase(phase: String, includePromoted!: Bool = false): String {
        let normalized = phase.trimAscii().toAsciiLower()
        if (normalized == "light") {
            return applyLightDreaming(includePromoted: includePromoted, limit: 6)
        }
        if (normalized == "rem") {
            return applyRemHarness(includePromoted: includePromoted, limit: 6)
        }
        if (normalized == "deep") {
            return applyDeepDreaming(includePromoted: includePromoted, limit: 6)
        }
        if (normalized == "all" || normalized.isEmpty() || normalized == "sweep") {
            return applyDreamingSweep(includePromoted: includePromoted)
        }
        "Unknown dreaming phase '${phase}'. Expected: light, rem, deep, all."
    }

    public static func applyDreamingSweep(includePromoted!: Bool = false): String {
        let lightResult = applyLightDreaming(includePromoted: includePromoted, limit: 6)
        let remResult = applyRemHarness(includePromoted: includePromoted, limit: 6)
        let deepResult = applyDeepDreaming(includePromoted: includePromoted, limit: 6)
        "Memory dreaming sweep completed.\n${lightResult}\n${remResult}\n${deepResult}"
    }

    private static func ensureSqliteSchema(): Bool {
        let sql = "CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(path UNINDEXED, start_line UNINDEXED, end_line UNINDEXED, text); DELETE FROM memory_fts;"
        let (ec, _out, err) = ShellUtils.execute(["sqlite3", MemoryPaths.sqliteStorePath().toString(), sql], withWrap: false, workDir: CliConfig.cwd)
        if (ec != 0) {
            LogUtils.error("Failed to initialize sqlite memory schema: ${err}")
            return false
        }
        true
    }

    private static func appendFileToSqliteIndex(path: Path): Bool {
        let relPath = workspaceRelativePath(path)
        let content = try {
            String.fromUtf8(File.readFrom(path))
        } catch (e: Exception) {
            LogUtils.error("Failed to read memory file for sqlite index: ${path}, error: ${e.message}")
            return false
        }
        let sql = buildSqliteInsertSqlForContent(relPath, content)
        if (sql.isEmpty()) {
            return true
        }
        let (ec, _out, err) = ShellUtils.execute(
            ["sqlite3", MemoryPaths.sqliteStorePath().toString(), sql],
            withWrap: false,
            workDir: CliConfig.cwd
        )
        if (ec != 0) {
            LogUtils.error("Failed to append sqlite memory rows for ${relPath}: ${err}")
            return false
        }
        true
    }

    public static func rebuildSqliteIndex(): Bool {
        if (!ensureSqliteSchema()) {
            return false
        }
        for (path in resolveMemoryFiles()) {
            if (!appendFileToSqliteIndex(path)) {
                return false
            }
        }
        true
    }

    public static func searchSqlite(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        if (!exists(MemoryPaths.sqliteStorePath())) {
            let _ = rebuildSqliteIndex()
        }
        let safeLimit = max(1, limit)
        let sql = "SELECT path, start_line, end_line, text FROM memory_fts WHERE memory_fts MATCH '${sqlQuote(query.trimAscii())}' ORDER BY rank LIMIT ${safeLimit};"
        let (ec, out, err) = ShellUtils.execute(["sqlite3", "-tabs", MemoryPaths.sqliteStorePath().toString(), sql], withWrap: false, workDir: CliConfig.cwd)
        if (ec != 0) {
            LogUtils.error("Failed to query sqlite memory index: ${err}")
            return []
        }

        let rows = ArrayList<LocalMemorySearchRow>()
        for (line in out.replace("\r\n", "\n").replace("\r", "\n").split("\n")) {
            let trimmed = line.trimAscii()
            if (trimmed.isEmpty()) {
                continue
            }
            let parts = trimmed.split("\t")
            if (parts.size < 4) {
                continue
            }
            rows.add(
                LocalMemorySearchRow(
                    parts[0],
                    parseInt64Or(parts[1], 1),
                    parseInt64Or(parts[2], parseInt64Or(parts[1], 1)),
                    parts[3]
                )
            )
        }
        rows.toArray()
    }

    public static func writeIndexSnapshot(): String {
        try {
            let files = resolveMemoryFiles()
            let rows = JsonArray([])
            var totalBytes: Int64 = 0
            for (path in files) {
                let fileInfo = FileInfo(path)
                totalBytes += fileInfo.size
                let row = JsonObject()
                row.put("path", JsonString(workspaceRelativePath(path)))
                row.put("absolutePath", JsonString(path.toString()))
                row.put("sizeBytes", fileInfo.size.toJsonValue())
                rows.add(row)
            }

            let root = JsonObject()
            root.put("status", JsonString("ok"))
            let sqliteReady = rebuildSqliteIndex()
            root.put("backend", JsonString(if (sqliteReady) { "sqlite-fts+local-file" } else { "local-file" }))
            root.put("workspace", JsonString(CliConfig.cwd.toString()))
            root.put("indexedAt", JsonString(DateTime.now().format("yyyy-MM-dd HH:mm:ss")))
            root.put("fileCount", files.size.toJsonValue())
            root.put("totalBytes", totalBytes.toJsonValue())
            root.put("sqliteIndexPath", JsonString(MemoryPaths.sqliteStorePath().toString()))
            root.put("shortTermRecallPath", JsonString(MemoryPaths.shortTermRecallPath().toString()))
            root.put("sqliteReady", sqliteReady.toJsonValue())
            root.put("files", rows)

            File.writeTo(MemoryPaths.indexStorePath(), root.toJsonString().toArray())
            return MemoryPaths.indexStorePath().toString()
        } catch (e: Exception) {
            LogUtils.error("Failed to write local memory index snapshot: ${e.message}")
            return ""
        }
    }

    public static func forceReindex(): String {
        writeIndexSnapshot()
    }

    public static func fixArtifacts(): String {
        let fixes = ArrayList<String>()
        let createdMemoryDir = MemoryPaths.ensureWorkspaceMemoryDir()
        if (!createdMemoryDir.isEmpty()) {
            fixes.add("created workspace memory dir: ${createdMemoryDir}")
        }

        let indexText = readIndexSnapshot()
        if (indexText.isEmpty()) {
            let indexPath = writeIndexSnapshot()
            if (!indexPath.isEmpty()) {
                fixes.add("rebuilt memory index: ${indexPath}")
            }
        }

        let promotionFixes = ShortTermPromotionRuntime.fixArtifacts()
        for (fix in promotionFixes) {
            fixes.add(fix)
        }
        let dailyFixes = DailyIngestionRuntime.fixArtifacts()
        for (fix in dailyFixes) {
            fixes.add(fix)
        }
        let markdownFixes = DreamingMarkdownRuntime.fixArtifacts()
        for (fix in markdownFixes) {
            fixes.add(fix)
        }
        let phaseFixes = DreamingPhaseRuntime.fixArtifacts()
        for (fix in phaseFixes) {
            fixes.add(fix)
        }
        if (!exists(DreamingNarrativeRuntime.runsPath())) {
            Directory.create(DreamingNarrativeRuntime.runsPath(), recursive: true)
            fixes.add("created dreaming narrative runs dir: ${DreamingNarrativeRuntime.runsPath()}")
        }
        if (!exists(DreamingNarrativeRuntime.sessionStorePath())) {
            Directory.create(DreamingNarrativeRuntime.sessionStorePath(), recursive: true)
            fixes.add("created dreaming narrative sessions dir: ${DreamingNarrativeRuntime.sessionStorePath()}")
        }

        let promotedPath = MemoryPaths.promotedAuditPath()
        if (!exists(promotedPath)) {
            File.writeTo(promotedPath, "".toArray())
            fixes.add("created promoted audit store: ${promotedPath}")
        }

        if (fixes.isEmpty()) {
            return "Memory fix: nothing changed."
        }
        "Memory fix:\n" + String.join(fixes.toArray(), delimiter: "\n")
    }

    public static func readIndexSnapshot(): String {
        let path = MemoryPaths.indexStorePath()
        if (!exists(path)) {
            return ""
        }
        try {
            String.fromUtf8(File.readFrom(path))
        } catch (e: Exception) {
            LogUtils.error("Failed to read local memory index snapshot: ${e.message}")
            ""
        }
    }

    public static func buildStatusText(deep!: Bool = false): String {
        buildStatusText(agentId: "", purpose: if (deep) { "status-deep" } else { "status" }, deep: deep)
    }

    public static func buildStatusText(
        agentId!: String = "",
        purpose!: String = "status",
        deep!: Bool = false
    ): String {
        let resolvedPurpose = if (purpose.trimAscii().isEmpty()) {
            if (deep) { "status-deep" } else { "status" }
        } else {
            purpose.trimAscii()
        }
        let resolved = MemoryRuntimeRegistry.resolveBackendConfig(
            agentId: agentId.trimAscii(),
            purpose: resolvedPurpose
        )
        let files = MemoryRuntime.resolveMemoryFiles(agentId: resolved.agentId, purpose: "status-resolve-files")
        let store = readShortTermRecallStore()
        let lines = ArrayList<String>()
        lines.add("Memory backend: ${resolved.backend}")
        lines.add("Memory provider: ${resolved.providerId}")
        lines.add("Memory citations: ${resolved.citations}")
        if (!resolved.searchMode.trimAscii().isEmpty()) {
            lines.add("Memory search mode: ${resolved.searchMode}")
        }
        lines.add("Memory config scope: ${resolved.configScope}")
        lines.add("Workspace: ${CliConfig.cwd}")
        lines.add("Index store: ${MemoryPaths.indexStorePath()}")
        lines.add("SQLite store: ${MemoryPaths.sqliteStorePath()}")
        lines.add("Short-term recall: ${MemoryPaths.shortTermRecallPath()}")
        lines.add("Phase signals: ${ShortTermPromotionRuntime.phaseSignalsPath()}")
        lines.add("Short-term lock: ${ShortTermPromotionRuntime.runtimeLockPath()}")
        lines.add("Daily ingestion state: ${DailyIngestionRuntime.statePath()}")
        lines.add("Dreaming markdown config: ${DreamingMarkdownRuntime.configPath()}")
        lines.add("Dreaming phase config: ${DreamingPhaseRuntime.configPath()}")
        lines.add("Dreaming narrative runs: ${DreamingNarrativeRuntime.runsPath()}")
        lines.add("Dreaming narrative sessions: ${DreamingNarrativeRuntime.sessionStorePath()}")
        lines.add("Promoted audit: ${MemoryPaths.promotedAuditPath()}")
        lines.add("Memory files: ${files.size}")
        lines.add("Short-term recall entries: ${getJsonInt64Value(store, "entryCount", 0)}")
        lines.add("Promoted count: ${getJsonInt64Value(store, "promotedCount", 0)}")
        lines.add("Max recall count: ${getJsonInt64Value(store, "maxRecallCount", 0)}")
        lines.add("Short-term audit: ${ShortTermPromotionRuntime.buildAuditSummaryJson()}")
        lines.add("Daily ingestion: ${DailyIngestionRuntime.buildStatusSummaryJson()}")
        lines.add("Dreaming markdown: ${DreamingMarkdownRuntime.buildStatusJson()}")
        lines.add("Dreaming phases: ${DreamingPhaseRuntime.buildStatusJson()}")
        for (path in files) {
            lines.add("- ${workspaceRelativePath(path)}")
        }
        let snapshot = readIndexSnapshot()
        if (!snapshot.isEmpty()) {
            lines.add("")
            lines.add("Existing index snapshot: present")
        } else {
            lines.add("")
            lines.add("Existing index snapshot: absent")
        }
        lines.add("SQLite index present: ${exists(MemoryPaths.sqliteStorePath())}")
        if (deep) {
            lines.add("")
            lines.add("Deep probe:")
            lines.add("- workspace memory dir: ${exists(CliConfig.cwd.join("memory"))}")
            lines.add("- durable memory present: ${exists(MemoryPaths.durableMemoryPath())}")
            lines.add("- sqlite bytes: ${if (exists(MemoryPaths.sqliteStorePath())) { FileInfo(MemoryPaths.sqliteStorePath()).size } else { 0 }}")
            lines.add("- recall store bytes: ${if (exists(MemoryPaths.shortTermRecallPath())) { FileInfo(MemoryPaths.shortTermRecallPath()).size } else { 0 }}")
            lines.add("- phase signal bytes: ${if (exists(ShortTermPromotionRuntime.phaseSignalsPath())) { FileInfo(ShortTermPromotionRuntime.phaseSignalsPath()).size } else { 0 }}")
            lines.add("- short-term lock bytes: ${if (exists(ShortTermPromotionRuntime.runtimeLockPath())) { FileInfo(ShortTermPromotionRuntime.runtimeLockPath()).size } else { 0 }}")
            lines.add("- daily ingestion state bytes: ${if (exists(DailyIngestionRuntime.statePath())) { FileInfo(DailyIngestionRuntime.statePath()).size } else { 0 }}")
            lines.add("- dreaming markdown config bytes: ${if (exists(DreamingMarkdownRuntime.configPath())) { FileInfo(DreamingMarkdownRuntime.configPath()).size } else { 0 }}")
            lines.add("- dreaming phase config bytes: ${if (exists(DreamingPhaseRuntime.configPath())) { FileInfo(DreamingPhaseRuntime.configPath()).size } else { 0 }}")
            lines.add("- dreaming narrative runs bytes: ${if (exists(DreamingNarrativeRuntime.runsPath())) { FileInfo(DreamingNarrativeRuntime.runsPath()).size } else { 0 }}")
            lines.add("- dreaming narrative sessions bytes: ${if (exists(DreamingNarrativeRuntime.sessionStorePath())) { FileInfo(DreamingNarrativeRuntime.sessionStorePath()).size } else { 0 }}")
            lines.add("- promoted audit bytes: ${if (exists(MemoryPaths.promotedAuditPath())) { FileInfo(MemoryPaths.promotedAuditPath()).size } else { 0 }}")
        }
        String.join(lines.toArray(), delimiter: "\n")
    }
}
