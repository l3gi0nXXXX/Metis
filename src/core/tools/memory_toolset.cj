package metis.core.tools

import magic.dsl.{tool, toolset}
import magic.prelude.*

import metis.core.config.CliConfig
import metis.core.memory.{MemoryRuntime, ResolvedMemoryBackendConfig, LocalMemorySearchRow, LocalMemoryRecallResult, isQmdScopeAllowed, parseAgentSessionKey}
import metis.core.tools.fs_utils.catRange

import std.collection.ArrayList
import std.fs.{Path, File, exists, FileInfo}
import std.sort.sort
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonFloat}

private class MemorySearchHit {
    public let path: String
    public let startLine: Int64
    public let endLine: Int64
    public let score: Float64
    public let text: String

    public init(path: String, startLine: Int64, endLine: Int64, score: Float64, text: String) {
        this.path = path
        this.startLine = startLine
        this.endLine = endLine
        this.score = score
        this.text = text
    }
}

private func trimTrailingSlash(path: String): String {
    var value = path.replace("\\", "/")
    while (value.size > 1 && value.endsWith("/")) {
        value = value[0..value.size - 1]
    }
    value
}

private func normalizeSlashes(path: String): String {
    path.replace("\\", "/")
}

private func workspaceRelativePath(path: Path): String {
    let workspace = trimTrailingSlash(CliConfig.cwd.toString())
    let full = normalizeSlashes(path.toString())
    if (full == workspace) {
        return path.fileName
    }
    let prefix = workspace + "/"
    if (full.startsWith(prefix)) {
        return full[prefix.size..]
    }
    full
}

private func readUtf8File(path: Path): String {
    String.fromUtf8(File.readFrom(path))
}

private func isAllowedMemoryRelativePath(relPath: String): Bool {
    let normalized = normalizeSlashes(relPath.trimAscii())
    if (normalized.isEmpty()) {
        return false
    }
    if (normalized == "MEMORY.md" || normalized == "memory.md") {
        return true
    }
    normalized.startsWith("memory/")
}

private func tokenizeQuery(query: String): Array<String> {
    let tokens = ArrayList<String>()
    for (piece in query.toAsciiLower().split(" ")) {
        let token = piece.trimAscii()
        if (!token.isEmpty()) {
            tokens.add(token)
        }
    }
    if (tokens.isEmpty()) {
        let trimmed = query.trimAscii().toAsciiLower()
        if (!trimmed.isEmpty()) {
            tokens.add(trimmed)
        }
    }
    tokens.toArray()
}

private func countMatches(text: String, token: String): Int64 {
    if (token.isEmpty()) {
        return 0
    }
    var count: Int64 = 0
    var start: Int64 = 0
    while (start < text.size) {
        match (text.indexOf(token, start)) {
            case Some(found) =>
                count += 1
                start = found + token.size
            case None =>
                break
        }
    }
    count
}

private func computeLineScore(lineLower: String, tokens: Array<String>): Float64 {
    var score = 0.0
    for (token in tokens) {
        let matches = countMatches(lineLower, token)
        if (matches > 0) {
            score += Float64(matches)
        }
    }
    score
}

private func excerptLines(lines: Array<String>, startLine: Int64, endLine: Int64): String {
    let out = ArrayList<String>()
    for (lineNo in startLine..=endLine) {
        let idx = lineNo - 1
        if (idx < 0 || idx >= lines.size) {
            continue
        }
        out.add("${lineNo}: ${lines[idx]}")
    }
    String.join(out.toArray(), delimiter: "\n")
}

private func buildMemorySearchUnavailable(error: String): String {
    let result = JsonObject()
    result.put("disabled", true.toJsonValue())
    result.put("status", JsonString("unavailable"))
    result.put("error", JsonString(error))
    result.put("results", JsonArray([]))
    result.toJsonString()
}

private func searchModeForBackend(config: ResolvedMemoryBackendConfig): String {
    if (config.backend.contains("sqlite-fts")) {
        return "fts5+keyword-rerank"
    }
    if (config.backend == "qmd") {
        return "qmd-" + CliConfig.qmdSearchMode.trimAscii().toAsciiLower()
    }
    "keyword"
}

private func searchHitsFromSqliteRowsImpl(query: String, rows: Array<LocalMemorySearchRow>): Array<MemorySearchHit> {
    let tokens = tokenizeQuery(query)
    let hits = ArrayList<MemorySearchHit>()
    for (row in rows) {
        let score = computeLineScore(row.text.toAsciiLower(), tokens)
        if (score <= 0.0) {
            continue
        }
        hits.add(
            MemorySearchHit(
                row.path,
                row.startLine,
                row.endLine,
                score + 1.0,
                row.text
            )
        )
    }
    let ordered = hits.toArray()
    sort(ordered, by: { a, b =>
        if (a.score == b.score) {
            a.path.compare(b.path)
        } else {
            if (a.score > b.score) {
                Ordering.LT
            } else {
                Ordering.GT
            }
        }
    }, stable: true)
    ordered
}

private func searchHitsFromFilesImpl(query: String, agentId!: String = "", purpose!: String = "tool-resolve-files"): Array<MemorySearchHit> {
    let tokens = tokenizeQuery(query)
    let hits = ArrayList<MemorySearchHit>()
    for (filePath in MemoryRuntime.resolveMemoryFiles(agentId: agentId, purpose: purpose)) {
        let relPath = workspaceRelativePath(filePath)
        let content = readUtf8File(filePath).replace("\r\n", "\n").replace("\r", "\n")
        let lines = content.split("\n")
        for (i in 0..lines.size) {
            let line = lines[i]
            let score = computeLineScore(line.toAsciiLower(), tokens)
            if (score <= 0.0) {
                continue
            }
            let lineNo = i + 1
            let startLine = if (lineNo > 1) { lineNo - 1 } else { lineNo }
            let endLine = if (lineNo < lines.size) { lineNo + 1 } else { lineNo }
            hits.add(
                MemorySearchHit(
                    relPath,
                    startLine,
                    endLine,
                    score,
                    excerptLines(lines, startLine, endLine)
                )
            )
        }
    }
    let ordered = hits.toArray()
    sort(ordered, by: { a, b =>
        if (a.score == b.score) {
            a.path.compare(b.path)
        } else {
            if (a.score > b.score) {
                Ordering.LT
            } else {
                Ordering.GT
            }
        }
    }, stable: true)
    ordered
}

private func runMemorySearchImpl(
    query: String,
    maxResults: Option<Int64>,
    minScore: Option<Float64>,
    sessionKey!: Option<String> = None,
    agentId!: Option<String> = None
): String {
    let trimmed = query.trimAscii()
    if (trimmed.isEmpty()) {
        return buildMemorySearchUnavailable("query is required")
    }
    let resolvedAgentId = match (parseAgentSessionKey(sessionKey)) {
        case Some(parsed) => parsed.agentId
        case None =>
            match (agentId) {
                case Some(value) => value.trimAscii()
                case None => ""
            }
    }
    let backendConfig = MemoryRuntime.resolveResolvedBackendConfig(agentId: resolvedAgentId, purpose: "tool-search")
    let defaultLimit = if (backendConfig.providerId == "qmd") { max(1, CliConfig.qmdLimitsMaxResults) } else { 6 }
    let limit = max(1, maxResults ?? defaultLimit)
    let threshold = minScore ?? 0.35
    let managerResult = MemoryRuntime.getMemorySearchManager(agentId: resolvedAgentId, purpose: "tool-search")
    match (managerResult.manager) {
        case None =>
            return buildMemorySearchUnavailable(
                if (managerResult.error.trimAscii().isEmpty()) {
                    "Memory search manager is unavailable."
                } else {
                    managerResult.error
                }
            )
        case Some(_) => ()
    }
    let files = MemoryRuntime.resolveMemoryFiles(agentId: resolvedAgentId, purpose: "tool-resolve-files")
    if (files.isEmpty() && backendConfig.providerId != "external") {
        return buildMemorySearchUnavailable("No MEMORY.md or memory/*.md files found in the current workspace.")
    }
    let rows = JsonArray([])
    let recallRows = ArrayList<LocalMemoryRecallResult>()
    let searchRows = MemoryRuntime.searchRows(
        trimmed,
        limit * 4,
        sessionKey: sessionKey,
        agentId: resolvedAgentId,
        purpose: "tool-search"
    )
    let usingManagerRows = !searchRows.isEmpty()
    let qmdScopeDenied = backendConfig.providerId == "qmd" && !isQmdScopeAllowed(sessionKey)
    var count: Int64 = 0
    let hits = if (usingManagerRows) {
        searchHitsFromSqliteRowsImpl(trimmed, searchRows)
    } else if (qmdScopeDenied) {
        Array<MemorySearchHit>()
    } else {
        searchHitsFromFilesImpl(trimmed, agentId: resolvedAgentId, purpose: "tool-resolve-files")
    }
    let snippetLimit = if (backendConfig.providerId == "qmd") { max(1, CliConfig.qmdLimitsMaxSnippetChars) } else { 1000000 }
    let injectedLimit = if (backendConfig.providerId == "qmd") { max(1, CliConfig.qmdLimitsMaxInjectedChars) } else { 1000000000 }
    var injectedChars: Int64 = 0
    for (hit in hits) {
        if (hit.score < threshold) {
            continue
        }
        if (count >= limit) {
            break
        }
        var snippet = hit.text
        if (snippet.size > snippetLimit) {
            snippet = snippet[0..snippetLimit] + "..."
        }
        if (injectedChars + snippet.size > injectedLimit) {
            if (count > 0) {
                break
            }
            if (snippet.size > injectedLimit) {
                snippet = snippet[0..injectedLimit] + "..."
            }
        }
        let row = JsonObject()
        row.put("source", JsonString("memory"))
        row.put("path", JsonString(hit.path))
        row.put("startLine", hit.startLine.toJsonValue())
        row.put("endLine", hit.endLine.toJsonValue())
        row.put("score", JsonFloat(hit.score))
        row.put("text", JsonString(snippet))
        rows.add(row)
        recallRows.add(LocalMemoryRecallResult(hit.path, hit.startLine, hit.endLine, hit.score, snippet))
        injectedChars += snippet.size
        count += 1
    }
    MemoryRuntime.recordShortTermRecall(
        trimmed,
        recallRows.toArray(),
        agentId: resolvedAgentId,
        purpose: "tool-record-recall"
    )

    let result = JsonObject()
    result.put("disabled", false.toJsonValue())
    result.put("status", JsonString("ok"))
    result.put("query", JsonString(trimmed))
    result.put("results", rows)
    result.put("provider", JsonString(backendConfig.providerId))
    result.put("backend", JsonString(backendConfig.backend))
    result.put("mode", JsonString(if (usingManagerRows) { searchModeForBackend(backendConfig) } else { "keyword-fallback" }))
    result.put("resolvedBackendConfig", backendConfig.toJsonObject())
    match (sessionKey) {
        case Some(value) => result.put("sessionKey", JsonString(value))
        case None => ()
    }
    result.put("citations", JsonString(if (backendConfig.citations == "off") { "off" } else { "path+lines" }))
    if (backendConfig.providerId == "qmd") {
        result.put("maxResults", limit.toJsonValue())
        result.put("maxSnippetChars", snippetLimit.toJsonValue())
        result.put("maxInjectedChars", injectedLimit.toJsonValue())
    }
    if (count == 0) {
        result.put("compatNote", JsonString(if (qmdScopeDenied) { "QMD search was denied by memory.qmd.scope for the supplied session context." } else { "No local memory snippets passed the current score threshold." }))
    } else {
        result.put("compatNote", JsonString(if (usingManagerRows) { "Active memory backend handled search and returned local path+line citations. Remote/vector citation modes are not wired yet." } else { "The active memory backend returned no ranked hits, so the search fell back to direct local file scanning." }))
    }
    result.toJsonString()
}

@toolset
public class MemoryToolset {
    public static let _memorySearch = "memory_search"
    public static let _memoryGet = "memory_get"

    public static func runCliSearch(
        query: String,
        maxResults!: Option<Int64> = None,
        minScore!: Option<Float64> = None,
        sessionKey!: Option<String> = None,
        agentId!: Option<String> = None
    ): String {
        runMemorySearchImpl(query, maxResults, minScore, sessionKey: sessionKey, agentId: agentId)
    }

    private func searchHits(query: String): Array<MemorySearchHit> {
        let managerRows = MemoryRuntime.searchRows(query, 24, sessionKey: None, agentId: "", purpose: "tool-search")
        if (!managerRows.isEmpty()) {
            return searchHitsFromSqliteRowsImpl(query, managerRows)
        }
        return searchHitsFromFilesImpl(query, agentId: "", purpose: "tool-resolve-files")
    }

    private func searchHitsFromSqliteRows(query: String, rows: Array<LocalMemorySearchRow>): Array<MemorySearchHit> {
        searchHitsFromSqliteRowsImpl(query, rows)
    }

    private func searchHitsFromFiles(query: String): Array<MemorySearchHit> {
        searchHitsFromFilesImpl(query)
    }

    private func resolveMemoryFilePath(relPath: String): Path {
        let trimmed = relPath.trimAscii()
        if (trimmed.isEmpty()) {
            return Path("")
        }
        let candidate = Path(trimmed)
        let absolute = if (candidate.isAbsolute()) {
            candidate
        } else {
            CliConfig.cwd.join(trimmed)
        }
        absolute
    }

    @tool[
        description: "Semantically-adjacent local recall over MEMORY.md and memory/*.md. Current implementation uses file-backed keyword scoring and returns top snippets with path and line ranges.",
        parameters: {
            query: "Search query describing the memory to recall.",
            maxResults: "Optional maximum number of matches to return. Default 6.",
            minScore: "Optional minimum score threshold. Default 0.35.",
            sessionKey: "Optional session key used for QMD scope evaluation when the active memory backend is qmd."
        }
    ]
    public func memory_search(query: String, maxResults: Option<Int64>, minScore: Option<Float64>, sessionKey: Option<String>): String {
        runMemorySearchImpl(query, maxResults, minScore, sessionKey: sessionKey)
    }

    @tool[
        description: "Read a specific snippet from MEMORY.md or memory/*.md with optional from/lines arguments.",
        parameters: {
            path: "Relative or absolute path to MEMORY.md or a file under memory/.",
            from: "Optional 1-based start line.",
            lines: "Optional number of lines to read from the start line."
        }
    ]
    public func memory_get(path: String, from: Option<Int64>, lines: Option<Int64>): String {
        let trimmed = path.trimAscii()
        if (trimmed.isEmpty()) {
            let err = JsonObject()
            err.put("path", JsonString(trimmed))
            err.put("text", JsonString(""))
            err.put("disabled", true.toJsonValue())
            err.put("error", JsonString("path is required"))
            return err.toJsonString()
        }
        let filePath = this.resolveMemoryFilePath(trimmed)
        let relPath = workspaceRelativePath(filePath)
        if (!isAllowedMemoryRelativePath(relPath)) {
            let err = JsonObject()
            err.put("path", JsonString(trimmed))
            err.put("text", JsonString(""))
            err.put("disabled", true.toJsonValue())
            err.put("error", JsonString("memory_get only allows MEMORY.md, memory.md, or files under memory/."))
            return err.toJsonString()
        }
        if (!exists(filePath) || !FileInfo(filePath).isRegular()) {
            let err = JsonObject()
            err.put("path", JsonString(relPath))
            err.put("text", JsonString(""))
            err.put("disabled", true.toJsonValue())
            err.put("error", JsonString("Memory file not found: ${relPath}"))
            return err.toJsonString()
        }

        let startLine = max(1, from ?? 1)
        let lineCount = max(1, lines ?? 40)
        let endLine = startLine + lineCount - 1
        let text = catRange(filePath.toString(), startLine, endLine: endLine)

        let result = JsonObject()
        result.put("path", JsonString(relPath))
        result.put("text", JsonString(text))
        result.put("disabled", false.toJsonValue())
        result.put("from", startLine.toJsonValue())
        result.put("lines", lineCount.toJsonValue())
        result.put("startLine", startLine.toJsonValue())
        result.put("endLine", endLine.toJsonValue())
        result.put("compatNote", JsonString("This first-pass implementation reads directly from local memory files."))
        result.toJsonString()
    }
}
