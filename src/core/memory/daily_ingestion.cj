package metis.core.memory

import magic.prelude.*
import magic.log.LogUtils

import metis.core.config.CliConfig

import std.collection.{ArrayList, HashSet}
import std.convert.*
import std.fs.{Path, Directory, File, FileInfo, exists}
import std.sort.sort
import std.time.*
import stdx.encoding.json.{JsonArray, JsonFloat, JsonObject, JsonString, JsonValue}

private let DAILY_INGESTION_SCORE: Float64 = 0.62
private let DAILY_INGESTION_MAX_SNIPPET_CHARS: Int64 = 280
private let DAILY_INGESTION_MIN_SNIPPET_CHARS: Int64 = 8
private let DAILY_INGESTION_MAX_CHUNK_LINES: Int64 = 4
private let ASCII_0 = UInt8(48)
private let ASCII_9 = UInt8(57)
private let ASCII_SPACE = UInt8(32)
private let ASCII_TAB = UInt8(9)
private let ASCII_NL = UInt8(10)
private let ASCII_CR = UInt8(13)
private let ASCII_DOT = UInt8(46)
private let ASCII_HASH = UInt8(35)
private let ASCII_DASH = UInt8(45)

private func dailyGetJsonInt64Value(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) =>
            try {
                Int64.parse(v.toString())
            } catch (_e: Exception) {
                fallback
            }
        case _ => fallback
    }
}

private func dailyGetJsonStringValue(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(s: JsonString) => s.getValue()
        case _ => fallback
    }
}

private func isAsciiDigit(ch: UInt8): Bool {
    ch >= ASCII_0 && ch <= ASCII_9
}

private func normalizeDailyListMarker(line: String): String {
    let trimmed = line.trimAscii()
    if (trimmed.startsWith("- ") || trimmed.startsWith("* ") || trimmed.startsWith("+ ")) {
        return trimmed[2..].trimAscii()
    }
    var idx: Int64 = 0
    let bytes = trimmed.toArray()
    while (idx < bytes.size && isAsciiDigit(bytes[idx])) {
        idx += 1
    }
    if (idx > 0 && idx + 1 < bytes.size && bytes[idx] == ASCII_DOT && bytes[idx + 1] == ASCII_SPACE) {
        return trimmed[(idx + 2)..].trimAscii()
    }
    trimmed
}

private func isSimpleDateHeading(text: String): Bool {
    let trimmed = text.trimAscii()
    if (trimmed.size == 10 &&
        isAsciiDigit(trimmed.toArray()[0]) &&
        isAsciiDigit(trimmed.toArray()[1]) &&
        isAsciiDigit(trimmed.toArray()[2]) &&
        isAsciiDigit(trimmed.toArray()[3]) &&
        trimmed.toArray()[4] == ASCII_DASH &&
        isAsciiDigit(trimmed.toArray()[5]) &&
        isAsciiDigit(trimmed.toArray()[6]) &&
        trimmed.toArray()[7] == ASCII_DASH &&
        isAsciiDigit(trimmed.toArray()[8]) &&
        isAsciiDigit(trimmed.toArray()[9])) {
        return true
    }
    false
}

private func isGenericDailyHeading(heading: String): Bool {
    let normalized = heading.trimAscii().toAsciiLower().replace("  ", " ")
    if (normalized.isEmpty()) {
        return true
    }
    normalized == "today" || normalized == "yesterday" || normalized == "tomorrow" ||
    normalized == "morning" || normalized == "afternoon" || normalized == "evening" ||
    normalized == "night" || isSimpleDateHeading(normalized)
}

private func normalizeDailyHeading(line: String): Option<String> {
    let trimmed = line.trimAscii()
    if (!trimmed.startsWith("#")) {
        return None
    }
    var idx: Int64 = 0
    while (idx < trimmed.size && trimmed.toArray()[idx] == ASCII_HASH) {
        idx += 1
    }
    if (idx >= trimmed.size) {
        return None
    }
    let heading = normalizeDailyListMarker(trimmed[idx..].trimAscii())
    if (heading.isEmpty() || isGenericDailyHeading(heading) || isDailyMemoryFileName(heading)) {
        return None
    }
    Some(compactSpaces(heading)[0..min(compactSpaces(heading).size, DAILY_INGESTION_MAX_SNIPPET_CHARS)])
}

private func compactSpaces(text: String): String {
    let out = StringBuilder()
    var lastSpace = false
    for (ch in text.toArray()) {
        let isSpace = ch == ASCII_SPACE || ch == ASCII_TAB || ch == ASCII_NL || ch == ASCII_CR
        if (isSpace) {
            if (!lastSpace) {
                out.append(" ")
            }
        } else {
            out.append(String.fromUtf8([ch]))
        }
        lastSpace = isSpace
    }
    out.toString().trimAscii()
}

private func normalizeDailySnippet(line: String): Option<String> {
    let trimmed = line.trimAscii()
    if (trimmed.isEmpty() || trimmed.startsWith("#") || trimmed.startsWith("<!--")) {
        return None
    }
    let normalized = compactSpaces(normalizeDailyListMarker(trimmed))
    if (normalized.size < DAILY_INGESTION_MIN_SNIPPET_CHARS) {
        return None
    }
    Some(normalized[0..min(normalized.size, DAILY_INGESTION_MAX_SNIPPET_CHARS)])
}

private func buildDailyChunkSnippet(heading: Option<String>, chunkLines: Array<String>, chunkKind: String): String {
    let joiner = if (chunkKind == "list") { "; " } else { " " }
    let body = compactSpaces(String.join(chunkLines, delimiter: joiner))
    let prefixed = match (heading) {
        case Some(text) => compactSpaces("${text}: ${body}")
        case None => body
    }
    prefixed[0..min(prefixed.size, DAILY_INGESTION_MAX_SNIPPET_CHARS)].trimAscii()
}

public class DailyIngestionChunk {
    public let startLine: Int64
    public let endLine: Int64
    public let snippet: String

    public init(startLine: Int64, endLine: Int64, snippet: String) {
        this.startLine = startLine
        this.endLine = endLine
        this.snippet = snippet
    }
}

private class DailyChunkBuildState {
    public var activeHeading: Option<String> = None
    public let chunkLines = ArrayList<String>()
    public var chunkKind: String = ""
    public var chunkStartLine: Int64 = 0
    public var chunkEndLine: Int64 = 0
}

private func flushDailyChunk(state: DailyChunkBuildState, chunks: ArrayList<DailyIngestionChunk>): Unit {
    if (state.chunkLines.isEmpty()) {
        state.chunkKind = ""
        state.chunkStartLine = 0
        state.chunkEndLine = 0
        return
    }
    let snippet = buildDailyChunkSnippet(state.activeHeading, state.chunkLines.toArray(), state.chunkKind)
    if (snippet.size >= DAILY_INGESTION_MIN_SNIPPET_CHARS) {
        chunks.add(DailyIngestionChunk(state.chunkStartLine, state.chunkEndLine, snippet))
    }
    state.chunkLines.clear()
    state.chunkKind = ""
    state.chunkStartLine = 0
    state.chunkEndLine = 0
}

private func buildDailySnippetChunks(lines: Array<String>, limit: Int64): Array<DailyIngestionChunk> {
    let chunks = ArrayList<DailyIngestionChunk>()
    let state = DailyChunkBuildState()

    for (idx in 0..lines.size) {
        let line = lines[idx]
        match (normalizeDailyHeading(line)) {
            case Some(heading) =>
                flushDailyChunk(state, chunks)
                state.activeHeading = Some(heading)
                continue
            case None => ()
        }
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty() || trimmed.startsWith("<!--")) {
            flushDailyChunk(state, chunks)
            continue
        }
        let snippet = match (normalizeDailySnippet(line)) {
            case Some(text) => text
            case None =>
                flushDailyChunk(state, chunks)
                continue
        }
        let nextKind = if (trimmed.startsWith("- ") || trimmed.startsWith("* ") || trimmed.startsWith("+ ")) {
            "list"
        } else {
            "paragraph"
        }
        let candidate = ArrayList<String>()
        for (item in state.chunkLines) {
            candidate.add(item)
        }
        candidate.add(snippet)
        let candidateSnippet = buildDailyChunkSnippet(state.activeHeading, candidate.toArray(), nextKind)
        let shouldSplit = !state.chunkLines.isEmpty() &&
            (state.chunkKind != nextKind || state.chunkLines.size >= DAILY_INGESTION_MAX_CHUNK_LINES || candidateSnippet.size > DAILY_INGESTION_MAX_SNIPPET_CHARS)
        if (shouldSplit) {
            flushDailyChunk(state, chunks)
        }
        if (state.chunkLines.isEmpty()) {
            state.chunkStartLine = idx + 1
            state.chunkKind = nextKind
        }
        state.chunkLines.add(snippet)
        state.chunkEndLine = idx + 1
        if (chunks.size >= limit) {
            break
        }
    }
    flushDailyChunk(state, chunks)
    chunks.toArray()[0..min(chunks.size, limit)]
}

private func isDailyMemoryFileName(name: String): Bool {
    let normalized = name.trimAscii()
    if (normalized.size != 13 || !normalized.endsWith(".md")) {
        return false
    }
    let bytes = normalized.toArray()
    isAsciiDigit(bytes[0]) && isAsciiDigit(bytes[1]) && isAsciiDigit(bytes[2]) && isAsciiDigit(bytes[3]) &&
    bytes[4] == ASCII_DASH &&
    isAsciiDigit(bytes[5]) && isAsciiDigit(bytes[6]) &&
    bytes[7] == ASCII_DASH &&
    isAsciiDigit(bytes[8]) && isAsciiDigit(bytes[9])
}

private func extractDay(fileName: String): String {
    fileName[0..10]
}

private func calculateLookbackCutoffMs(nowMs: Int64, lookbackDays: Int64): Int64 {
    nowMs - max(0, lookbackDays) * 24 * 60 * 60 * 1000
}

private func isDayWithinLookback(day: String, cutoffMs: Int64): Bool {
    try {
        let endOfDay = DateTime.parse("${day} 23:59:59", "yyyy-MM-dd HH:mm:ss")
        endOfDay.toUnixTimeStamp().toMilliseconds() >= cutoffMs
    } catch (_e: Exception) {
        false
    }
}

private func initDailyIngestionState(): JsonObject {
    let root = JsonObject()
    root.put("version", 1.toJsonValue())
    root.put("updatedAt", JsonString(""))
    root.put("files", JsonObject())
    root.put("trackedFileCount", 0.toJsonValue())
    root
}

private func normalizeState(raw: JsonObject): JsonObject {
    let root = initDailyIngestionState()
    root.put("updatedAt", JsonString(dailyGetJsonStringValue(raw, "updatedAt", "")))
    root.put("trackedFileCount", dailyGetJsonInt64Value(raw, "trackedFileCount", 0).toJsonValue())
    match (raw.get("files")) {
        case Some(obj: JsonObject) => root.put("files", obj)
        case _ => root.put("files", JsonObject())
    }
    root
}

public class DailyIngestionBatch {
    public let day: String
    public let results: Array<LocalMemoryRecallResult>

    public init(day: String, results: Array<LocalMemoryRecallResult>) {
        this.day = day
        this.results = results
    }
}

public class DailyIngestionSummary {
    public let phase: String
    public let changed: Bool
    public let batchCount: Int64
    public let resultCount: Int64
    public let trackedFileCount: Int64

    public init(phase: String, changed: Bool, batchCount: Int64, resultCount: Int64, trackedFileCount: Int64) {
        this.phase = phase
        this.changed = changed
        this.batchCount = batchCount
        this.resultCount = resultCount
        this.trackedFileCount = trackedFileCount
    }

    public func summaryLine(): String {
        "daily-ingestion phase=${phase}, batches=${batchCount}, snippets=${resultCount}, changed=${changed}, trackedFiles=${trackedFileCount}"
    }
}

public class DailyIngestionRuntime {
    public static func workspaceMemoryDir(): Path {
        let ensured = MemoryPaths.ensureWorkspaceMemoryDir()
        if (!ensured.isEmpty()) {
            return Path(ensured)
        }
        CliConfig.cwd.join("memory")
    }

    public static func ensureWorkspaceMemoryDir(): String {
        MemoryPaths.ensureWorkspaceMemoryDir()
    }

    public static func statePath(): Path {
        let dir = MemoryPaths.dreamsDirPath()
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
        dir.join("daily-ingestion.json")
    }

    public static func readState(): JsonObject {
        let path = statePath()
        if (!exists(path)) {
            return initDailyIngestionState()
        }
        try {
            match (JsonValue.fromStr(String.fromUtf8(File.readFrom(path)))) {
                case obj: JsonObject => normalizeState(obj)
                case _ => initDailyIngestionState()
            }
        } catch (_e: Exception) {
            initDailyIngestionState()
        }
    }

    public static func writeState(state: JsonObject): Unit {
        try {
            let normalized = normalizeState(state)
            normalized.put("updatedAt", JsonString(DateTime.now().format("yyyy-MM-dd HH:mm:ss")))
            File.writeTo(statePath(), normalized.toJsonString().toArray())
        } catch (e: Exception) {
            LogUtils.error("Failed to write daily ingestion state: ${e.message}")
        }
    }

    public static func fixArtifacts(): Array<String> {
        let fixes = ArrayList<String>()
        let path = statePath()
        if (!exists(path)) {
            File.writeTo(path, initDailyIngestionState().toJsonString().toArray())
            fixes.add("created daily ingestion state: ${path}")
        } else {
            File.writeTo(path, readState().toJsonString().toArray())
            fixes.add("normalized daily ingestion state: ${path}")
        }
        fixes.toArray()
    }

    public static func trackedFileCount(): Int64 {
        dailyGetJsonInt64Value(readState(), "trackedFileCount", 0)
    }

    public static func buildStatusSummaryJson(): String {
        let state = readState()
        let root = JsonObject()
        root.put("status", JsonString("ok"))
        root.put("action", JsonString("memory_daily_ingestion_status"))
        root.put("statePath", JsonString(statePath().toString()))
        root.put("present", exists(statePath()).toJsonValue())
        root.put("trackedFileCount", trackedFileCount().toJsonValue())
        root.put("updatedAt", JsonString(dailyGetJsonStringValue(state, "updatedAt", "")))
        root.toJsonString()
    }

    private static func collectDailyIngestionBatches(
        lookbackDays: Int64,
        limit: Int64,
        nowMs: Int64,
        state: JsonObject
    ): (Array<DailyIngestionBatch>, JsonObject, Bool) {
        let memoryDir = workspaceMemoryDir()
        let cutoffMs = calculateLookbackCutoffMs(nowMs, lookbackDays)
        let dailyFiles = ArrayList<(String, Path)>()
        if (exists(memoryDir)) {
            for (entry in Directory.readFrom(memoryDir)) {
                let path = entry.path
                if (!FileInfo(path).isRegular()) {
                    continue
                }
                let fileName = path.fileName
                if (!isDailyMemoryFileName(fileName)) {
                    continue
                }
                let day = extractDay(fileName)
                if (!isDayWithinLookback(day, cutoffMs)) {
                    continue
                }
                dailyFiles.add((day, path))
            }
        }
        let fileRows = dailyFiles.toArray()
        sort(fileRows, by: { a, b => b[0].compare(a[0]) }, stable: true)

        let priorFiles = match (state.get("files")) {
            case Some(obj: JsonObject) => obj
            case _ => JsonObject()
        }
        let nextFiles = JsonObject()
        let batches = ArrayList<DailyIngestionBatch>()
        var changed = false
        let totalCap = max(20, limit * 4)
        let perFileCap = max(6, totalCap / max(1, Int64(fileRows.size)))
        var totalSnippets: Int64 = 0

        for ((day, path) in fileRows) {
            let relPath = "memory/${path.fileName}"
            let info = FileInfo(path)
            let mtimeMs = info.lastModificationTime.toUnixTimeStamp().toMilliseconds()
            let size = info.size
            let fingerprint = JsonObject()
            fingerprint.put("mtimeMs", mtimeMs.toJsonValue())
            fingerprint.put("size", size.toJsonValue())
            nextFiles.put(relPath, fingerprint)

            var unchanged = false
            match (priorFiles.get(relPath)) {
                case Some(old: JsonObject) =>
                    unchanged = dailyGetJsonInt64Value(old, "mtimeMs", -1) == mtimeMs &&
                        dailyGetJsonInt64Value(old, "size", -1) == size
                case _ => ()
            }
            if (unchanged) {
                continue
            }
            changed = true
            let raw = try {
                String.fromUtf8(File.readFrom(path))
            } catch (_e: Exception) {
                ""
            }
            if (raw.isEmpty()) {
                continue
            }
            let lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
            let chunks = buildDailySnippetChunks(lines, perFileCap)
            let results = ArrayList<LocalMemoryRecallResult>()
            for (chunk in chunks) {
                results.add(LocalMemoryRecallResult(relPath, chunk.startLine, chunk.endLine, DAILY_INGESTION_SCORE, chunk.snippet))
                if (results.size >= perFileCap || totalSnippets + Int64(results.size) >= totalCap) {
                    break
                }
            }
            if (!results.isEmpty()) {
                batches.add(DailyIngestionBatch(day, results.toArray()))
                totalSnippets += Int64(results.size)
            }
            if (totalSnippets >= totalCap) {
                break
            }
        }

        let priorCount = dailyGetJsonInt64Value(state, "trackedFileCount", 0)
        let nextCount = Int64(fileRows.size)
        if (!changed && priorCount != nextCount) {
            changed = true
        }

        let nextState = JsonObject()
        nextState.put("version", 1.toJsonValue())
        nextState.put("updatedAt", JsonString(DateTime.now().format("yyyy-MM-dd HH:mm:ss")))
        nextState.put("files", nextFiles)
        nextState.put("trackedFileCount", nextCount.toJsonValue())
        (batches.toArray(), nextState, changed)
    }

    public static func ingestForDreaming(phase: String, lookbackDays!: Int64 = 14, limit!: Int64 = 6): DailyIngestionSummary {
        let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
        let state = readState()
        let (batches, nextState, changed) = collectDailyIngestionBatches(
            lookbackDays,
            max(1, limit),
            nowMs,
            state
        )
        var resultCount: Int64 = 0
        for (batch in batches) {
            resultCount += Int64(batch.results.size)
            ShortTermPromotionRuntime.recordRecall(
                "__dreaming_daily__:${batch.day}",
                batch.results,
                signalType: "daily",
                dedupeByQueryPerDay: true,
                dayBucket: batch.day
            )
        }
        if (changed) {
            writeState(nextState)
        }
        DailyIngestionSummary(
            phase.trimAscii().toAsciiLower(),
            changed,
            Int64(batches.size),
            resultCount,
            trackedFileCount()
        )
    }
}
