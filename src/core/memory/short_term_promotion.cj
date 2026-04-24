package metis.core.memory

import magic.prelude.*
import magic.log.LogUtils

import metis.core.config.CliConfig

import std.collection.{ArrayList, HashSet}
import std.convert.*
import std.fs.{Path, Directory, File, exists, FileInfo, OpenMode, remove}
import std.sync.Mutex
import std.time.*
import stdx.encoding.json.{JsonArray, JsonFloat, JsonObject, JsonString, JsonValue}

private let shortTermPromotionLock = Mutex()
private let MAX_QUERY_HASHES: Int64 = 32
private let MAX_RECALL_DAYS: Int64 = 16
private let LIGHT_PHASE_BOOST_MAX: Float64 = 0.05
private let REM_PHASE_BOOST_MAX: Float64 = 0.08
private let DEFAULT_PROMOTION_MIN_SCORE: Float64 = 0.75
private let DEFAULT_PROMOTION_MIN_RECALL_COUNT: Int64 = 3
private let DEFAULT_PROMOTION_MIN_UNIQUE_QUERIES: Int64 = 2
private let DEFAULT_WEIGHT_FREQUENCY: Float64 = 0.24
private let DEFAULT_WEIGHT_RELEVANCE: Float64 = 0.30
private let DEFAULT_WEIGHT_DIVERSITY: Float64 = 0.15
private let DEFAULT_WEIGHT_RECENCY: Float64 = 0.15
private let DEFAULT_WEIGHT_CONSOLIDATION: Float64 = 0.10
private let DEFAULT_WEIGHT_CONCEPTUAL: Float64 = 0.06

private func promotionDir(): Path {
    let dir = CliConfig.dotDir.join("memory")
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    dir
}

private func phaseSignalPath(): Path {
    promotionDir().join("phase-signals.json")
}

private func lockPath(): Path {
    promotionDir().join("short-term-promotion.lock")
}

private func stpNormalizeRecallKey(text: String): String {
    text.trimAscii().toAsciiLower().replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
}

private func stpReadJsonStringArray(obj: JsonObject, key: String): Array<String> {
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

private func stpParseInt64Or(text: String, fallback: Int64): Int64 {
    try {
        Int64.parse(text)
    } catch (_e: Exception) {
        fallback
    }
}

private func stpParseFloat64Or(text: String, fallback: Float64): Float64 {
    try {
        Float64.parse(text)
    } catch (_e: Exception) {
        fallback
    }
}

private func stpGetJsonStringValue(obj: JsonObject, key: String, fallback: String): String {
    match (obj.get(key)) {
        case Some(s: JsonString) => s.getValue()
        case _ => fallback
    }
}

private func stpGetJsonInt64Value(obj: JsonObject, key: String, fallback: Int64): Int64 {
    match (obj.get(key)) {
        case Some(v) => stpParseInt64Or(v.toString(), fallback)
        case _ => fallback
    }
}

private func stpGetJsonFloat64Value(obj: JsonObject, key: String, fallback: Float64): Float64 {
    match (obj.get(key)) {
        case Some(v) => stpParseFloat64Or(v.toString(), fallback)
        case _ => fallback
    }
}

private func stpAppendUniqueRecent(values: Array<String>, nextValue: String, limit: Int64): Array<String> {
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

private func djb2Hash(text: String): UInt64 {
    var h: UInt64 = 5381
    let bytes = text.toArray()
    var i: Int64 = 0
    let n = Int64(bytes.size)
    while (i < n) {
        h = ((h << 5) + h) + UInt64(UInt8(bytes[i]))
        i += 1
    }
    h
}

private func toLowerHex(value: UInt64): String {
    let chars = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
    let out = StringBuilder()
    var shift: Int64 = 60
    while (shift >= 0) {
        let nibble = (value >> shift) & UInt64(15)
        out.append(chars[Int64(nibble)])
        shift -= 4
    }
    out.toString()
}

private func hashQuery(query: String): String {
    toLowerHex(djb2Hash(stpNormalizeRecallKey(query)))
}

private func stpClampScore(value: Float64): Float64 {
    if (value < 0.0) {
        return 0.0
    }
    if (value > 1.0) {
        return 1.0
    }
    value
}

private func stpComputeRecencyBoost(lastRecalledAt: String): Float64 {
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

private func stpHasCueWords(text: String): Bool {
    let lower = text.toAsciiLower()
    lower.contains("always") || lower.contains("never") || lower.contains("must") ||
    lower.contains("remember") || lower.contains("prefer") || lower.contains("important")
}

private func stpPromotionComponents(
    text: String,
    recallCount: Int64,
    uniqueQueries: Int64,
    recallDays: Int64,
    avgScore: Float64,
    recencyBoost: Float64,
    conceptTagCount: Int64
): (Float64, Float64, Float64, Float64, Float64, Float64) {
    let signalCount = recallCount
    let frequency = stpClampScore(Float64(signalCount) / 8.0)
    let relevance = stpClampScore(avgScore)
    let diversity = stpClampScore(Float64(max(uniqueQueries, recallDays)) / 5.0)
    let recency = stpClampScore(recencyBoost)
    let consolidation = stpClampScore(Float64(recallDays) / 5.0)
    let conceptual = stpClampScore(Float64(conceptTagCount) / 6.0)
    (frequency, relevance, diversity, recency, consolidation, conceptual)
}

private func stpPromotionScore(
    line: String,
    relPath: String,
    recallCount: Int64,
    uniqueQueries: Int64,
    recallDays: Int64,
    recencyBoost: Float64,
    conceptTagCount: Int64,
    avgScore: Float64,
    phaseBoost: Float64
): Float64 {
    let components = stpPromotionComponents(
        line,
        recallCount,
        uniqueQueries,
        recallDays,
        avgScore,
        recencyBoost,
        conceptTagCount
    )
    var score = components[0] * DEFAULT_WEIGHT_FREQUENCY +
        components[1] * DEFAULT_WEIGHT_RELEVANCE +
        components[2] * DEFAULT_WEIGHT_DIVERSITY +
        components[3] * DEFAULT_WEIGHT_RECENCY +
        components[4] * DEFAULT_WEIGHT_CONSOLIDATION +
        components[5] * DEFAULT_WEIGHT_CONCEPTUAL +
        phaseBoost
    if (stpHasCueWords(line)) {
        score += 0.08
    }
    if (relPath.contains("clear") || relPath.contains("compaction")) {
        score += 0.04
    }
    stpClampScore(score)
}

private func stpDeriveConceptTags(text: String, limit!: Int64 = 6): Array<String> {
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
        if (token.size < 4 || seen.contains(token)) {
            continue
        }
        seen.add(token)
        tags.add(token)
        if (tags.size >= limit) {
            break
        }
    }
    tags.toArray()
}

private func initRecallStore(): JsonObject {
    let root = JsonObject()
    root.put("version", 1.toJsonValue())
    root.put("updatedAt", JsonString(""))
    root.put("entries", JsonObject())
    root.put("entryCount", 0.toJsonValue())
    root.put("promotedCount", 0.toJsonValue())
    root.put("maxRecallCount", 0.toJsonValue())
    root.put("conceptTaggedCount", 0.toJsonValue())
    root
}

private func initPhaseSignalStore(): JsonObject {
    let root = JsonObject()
    root.put("version", 1.toJsonValue())
    root.put("updatedAt", JsonString(""))
    root.put("entries", JsonObject())
    root
}

private func readJsonObjectOr(path: Path, fallback: JsonObject): JsonObject {
    if (!exists(path)) {
        return fallback
    }
    try {
        match (JsonValue.fromStr(String.fromUtf8(File.readFrom(path)))) {
            case obj: JsonObject => obj
            case _ => fallback
        }
    } catch (_e: Exception) {
        fallback
    }
}

private func staleLockRemoved(fixes: ArrayList<String>): Unit {
    let path = lockPath()
    if (!exists(path)) {
        return
    }
    let content = try {
        String.fromUtf8(File.readFrom(path))
    } catch (_e: Exception) {
        ""
    }
    let nowMs = DateTime.now().toUnixTimeStamp().toMilliseconds()
    let startedAtMs = if (content.trimAscii().isEmpty()) {
        0
    } else {
        stpParseInt64Or(content.trimAscii(), 0)
    }
    if (startedAtMs <= 0 || nowMs - startedAtMs > 60000) {
        try {
            remove(path)
            fixes.add("removed stale short-term promotion lock: ${path}")
        } catch (_e: Exception) {
            ()
        }
    }
}

private func beginLock(): Unit {
    let path = lockPath()
    try {
        File.writeTo(path, DateTime.now().toUnixTimeStamp().toMilliseconds().toString().toArray())
    } catch (e: Exception) {
        LogUtils.error("Failed to write short-term promotion lock: ${e.message}")
    }
}

private func endLock(): Unit {
    let path = lockPath()
    if (exists(path)) {
        try {
            remove(path)
        } catch (_e: Exception) {
            ()
        }
    }
}

private func buildAuditIssue(
    code: String,
    message: String,
    severity!: String = "warn",
    fixable!: Bool = true
): JsonObject {
    let issue = JsonObject()
    issue.put("severity", JsonString(severity))
    issue.put("code", JsonString(code))
    issue.put("message", JsonString(message))
    issue.put("fixable", fixable.toJsonValue())
    issue
}

private func recallEntryInvalid(entry: JsonObject): Bool {
    let path = stpGetJsonStringValue(entry, "path", "")
    let snippet = stpGetJsonStringValue(entry, "snippet", "")
    let startLine = stpGetJsonInt64Value(entry, "startLine", -1)
    let endLine = stpGetJsonInt64Value(entry, "endLine", -1)
    path.trimAscii().isEmpty() ||
        snippet.trimAscii().isEmpty() ||
        startLine <= 0 ||
        endLine <= 0 ||
        endLine < startLine
}

public class ShortTermPromotionRuntime {
    public static func defaultPromotionMinScore(): Float64 {
        DEFAULT_PROMOTION_MIN_SCORE
    }

    public static func defaultPromotionMinRecallCount(): Int64 {
        DEFAULT_PROMOTION_MIN_RECALL_COUNT
    }

    public static func defaultPromotionMinUniqueQueries(): Int64 {
        DEFAULT_PROMOTION_MIN_UNIQUE_QUERIES
    }

    public static func storePath(): Path {
        MemoryPaths.shortTermRecallPath()
    }

    public static func phaseSignalsPath(): Path {
        phaseSignalPath()
    }

    public static func auditPath(): Path {
        MemoryPaths.promotedAuditPath()
    }

    public static func runtimeLockPath(): Path {
        lockPath()
    }

    public static func loadPromotedAuditKeys(): HashSet<String> {
        let keys = HashSet<String>()
        let path = auditPath()
        if (!exists(path)) {
            return keys
        }
        let content = try {
            String.fromUtf8(File.readFrom(path))
        } catch (_e: Exception) {
            return keys
        }
        for (line in content.replace("\r\n", "\n").replace("\r", "\n").split("\n")) {
            let key = stpNormalizeRecallKey(line)
            if (!key.isEmpty()) {
                keys.add(key)
            }
        }
        keys
    }

    public static func readRecallStore(): JsonObject {
        readJsonObjectOr(storePath(), initRecallStore())
    }

    public static func readPhaseSignalStore(): JsonObject {
        readJsonObjectOr(phaseSignalsPath(), initPhaseSignalStore())
    }

    public static func recordRecall(
        query: String,
        results: Array<LocalMemoryRecallResult>,
        signalType!: String = "recall",
        dedupeByQueryPerDay!: Bool = false,
        dayBucket!: String = ""
    ): Unit {
        if (results.isEmpty()) {
            return
        }
        synchronized(shortTermPromotionLock) {
            beginLock()
            try {
                let root = readRecallStore()
                let entries = match (root.get("entries")) {
                    case Some(obj: JsonObject) => obj
                    case _ => JsonObject()
                }
                let now = DateTime.now().format("yyyy-MM-dd HH:mm:ss")
                let recallDay = if (dayBucket.trimAscii().isEmpty()) {
                    DateTime.now().format("yyyy-MM-dd")
                } else {
                    dayBucket.trimAscii()
                }
                let normalizedSignalType = signalType.trimAscii().toAsciiLower()
                let queryKey = hashQuery(query)
                var entryCount = stpGetJsonInt64Value(root, "entryCount", 0)
                let promotedCount = stpGetJsonInt64Value(root, "promotedCount", 0)
                var maxRecallCount = stpGetJsonInt64Value(root, "maxRecallCount", 0)
                var conceptTaggedCount = stpGetJsonInt64Value(root, "conceptTaggedCount", 0)
                for (result in results) {
                    let entryKey = "memory:${result.path}:${result.startLine}:${result.endLine}"
                    let existing = match (entries.get(entryKey)) {
                        case Some(obj: JsonObject) => obj
                        case _ => JsonObject()
                    }
                    let existed = !stpGetJsonStringValue(existing, "path", "").isEmpty()
                    let existingRecallDays = stpReadJsonStringArray(existing, "recallDays")
                    let nextRecallDays = stpAppendUniqueRecent(existingRecallDays, recallDay, MAX_RECALL_DAYS)
                    let existingQueryHashes = stpReadJsonStringArray(existing, "queryHashes")
                    let nextQueryHashes = stpAppendUniqueRecent(existingQueryHashes, queryKey, MAX_QUERY_HASHES)
                    let previousLastAt = stpGetJsonStringValue(existing, "lastRecalledAt", "")
                    let previousDay = if (previousLastAt.size >= 10) { previousLastAt[0..10] } else { "" }
                    let sameQuerySameDay = dedupeByQueryPerDay &&
                        previousDay == recallDay &&
                        !existingQueryHashes.isEmpty() &&
                        existingQueryHashes.contains(queryKey)
                    let recallCount = if (sameQuerySameDay) {
                        stpGetJsonInt64Value(existing, "recallCount", 0)
                    } else {
                        stpGetJsonInt64Value(existing, "recallCount", 0) + 1
                    }
                    let dailyCount = if (previousDay == recallDay) {
                        stpGetJsonInt64Value(existing, "dailyCount", 0) + 1
                    } else {
                        1
                    }
                    let totalScore = if (sameQuerySameDay) {
                        stpGetJsonFloat64Value(existing, "totalScore", 0.0)
                    } else {
                        stpGetJsonFloat64Value(existing, "totalScore", 0.0) + result.score
                    }
                    let maxScore = max(stpGetJsonFloat64Value(existing, "maxScore", result.score), result.score)
                    let conceptTags = stpDeriveConceptTags(result.snippet)
                    let entry = JsonObject()
                    entry.put("key", JsonString(entryKey))
                    entry.put("path", JsonString(result.path))
                    entry.put("startLine", result.startLine.toJsonValue())
                    entry.put("endLine", result.endLine.toJsonValue())
                    entry.put("snippet", JsonString(result.snippet))
                    entry.put("source", JsonString("memory"))
                    entry.put("recallCount", recallCount.toJsonValue())
                    entry.put("dailyCount", dailyCount.toJsonValue())
                    entry.put("totalScore", JsonFloat(totalScore))
                    entry.put("maxScore", JsonFloat(maxScore))
                    entry.put("firstRecalledAt", JsonString(stpGetJsonStringValue(existing, "firstRecalledAt", now)))
                    entry.put("lastRecalledAt", JsonString(now))
                    entry.put("lastQuery", JsonString(queryKey))
                    entry.put("lastSignalType", JsonString(normalizedSignalType))
                    let queryHashRows = JsonArray([])
                    for (value in nextQueryHashes) {
                        queryHashRows.add(JsonString(value))
                    }
                    entry.put("queryHashes", queryHashRows)
                    let recallDayRows = JsonArray([])
                    for (value in nextRecallDays) {
                        recallDayRows.add(JsonString(value))
                    }
                    entry.put("recallDays", recallDayRows)
                    let conceptTagRows = JsonArray([])
                    for (value in conceptTags) {
                        conceptTagRows.add(JsonString(value))
                    }
                    entry.put("conceptTags", conceptTagRows)
                    entry.put(
                        "dailySignalCount",
                        (if (normalizedSignalType == "daily") {
                            stpGetJsonInt64Value(existing, "dailySignalCount", 0) + 1
                        } else {
                            stpGetJsonInt64Value(existing, "dailySignalCount", 0)
                        }).toJsonValue()
                    )
                    entry.put(
                        "recallSignalCount",
                        (if (normalizedSignalType == "daily") {
                            stpGetJsonInt64Value(existing, "recallSignalCount", 0)
                        } else {
                            stpGetJsonInt64Value(existing, "recallSignalCount", 0) + 1
                        }).toJsonValue()
                    )
                    let promotedAt = stpGetJsonStringValue(existing, "promotedAt", "")
                    if (!promotedAt.isEmpty()) {
                        entry.put("promotedAt", JsonString(promotedAt))
                    }
                    entries.put(entryKey, entry)
                    if (!existed) {
                        entryCount += 1
                    }
                    if (recallCount > maxRecallCount) {
                        maxRecallCount = recallCount
                    }
                    if (!conceptTags.isEmpty() && (!existed || stpReadJsonStringArray(existing, "conceptTags").isEmpty())) {
                        conceptTaggedCount += 1
                    }
                }
                root.put("updatedAt", JsonString(now))
                root.put("entries", entries)
                root.put("entryCount", entryCount.toJsonValue())
                root.put("promotedCount", promotedCount.toJsonValue())
                root.put("maxRecallCount", maxRecallCount.toJsonValue())
                root.put("conceptTaggedCount", conceptTaggedCount.toJsonValue())
                File.writeTo(storePath(), root.toJsonString().toArray())
            } catch (e: Exception) {
                LogUtils.error("Failed to record short-term memory recall: ${e.message}")
            } finally {
                endLock()
            }
        }
    }

    public static func markPromoted(candidates: Array<LocalMemoryPromoteCandidate>): Unit {
        if (candidates.isEmpty()) {
            return
        }
        synchronized(shortTermPromotionLock) {
            beginLock()
            try {
                let root = readRecallStore()
                let entries = match (root.get("entries")) {
                    case Some(obj: JsonObject) => obj
                    case _ => JsonObject()
                }
                let promotedAt = DateTime.now().format("yyyy-MM-dd HH:mm:ss")
                var promotedCount = stpGetJsonInt64Value(root, "promotedCount", 0)
                for (candidate in candidates) {
                    let entryKey = "memory:${candidate.sourcePath}:${candidate.line}:${candidate.line}"
                    match (entries.get(entryKey)) {
                        case Some(obj: JsonObject) =>
                            let alreadyPromoted = !stpGetJsonStringValue(obj, "promotedAt", "").isEmpty()
                            obj.put("promotedAt", JsonString(promotedAt))
                            entries.put(entryKey, obj)
                            if (!alreadyPromoted) {
                                promotedCount += 1
                            }
                        case _ => ()
                    }
                }
                root.put("updatedAt", JsonString(promotedAt))
                root.put("entries", entries)
                root.put("promotedCount", promotedCount.toJsonValue())
                File.writeTo(storePath(), root.toJsonString().toArray())
            } catch (e: Exception) {
                LogUtils.error("Failed to mark promotedAt for short-term recall store: ${e.message}")
            } finally {
                endLock()
            }
        }
    }

    public static func recordDreamingPhaseSignals(phase: String, keys: Array<String>): Unit {
        let normalizedPhase = phase.trimAscii().toAsciiLower()
        if (keys.isEmpty() || (normalizedPhase != "light" && normalizedPhase != "rem")) {
            return
        }
        synchronized(shortTermPromotionLock) {
            beginLock()
            try {
                let recallStore = readRecallStore()
                let recallEntries = match (recallStore.get("entries")) {
                    case Some(obj: JsonObject) => obj
                    case _ => JsonObject()
                }
                let root = readPhaseSignalStore()
                let entries = match (root.get("entries")) {
                    case Some(obj: JsonObject) => obj
                    case _ => JsonObject()
                }
                let now = DateTime.now().format("yyyy-MM-dd HH:mm:ss")
                let uniqueKeys = HashSet<String>()
                for (key in keys) {
                    let trimmed = key.trimAscii()
                    if (!trimmed.isEmpty()) {
                        uniqueKeys.add(trimmed)
                    }
                }
                for (key in uniqueKeys) {
                    match (recallEntries.get(key)) {
                        case Some(_) => ()
                        case None => continue
                    }
                    let existing = match (entries.get(key)) {
                        case Some(obj: JsonObject) => obj
                        case _ => JsonObject()
                    }
                    let next = JsonObject()
                    next.put("key", JsonString(key))
                    let lightHits = if (normalizedPhase == "light") {
                        stpGetJsonInt64Value(existing, "lightHits", 0) + 1
                    } else {
                        stpGetJsonInt64Value(existing, "lightHits", 0)
                    }
                    let remHits = if (normalizedPhase == "rem") {
                        stpGetJsonInt64Value(existing, "remHits", 0) + 1
                    } else {
                        stpGetJsonInt64Value(existing, "remHits", 0)
                    }
                    next.put("lightHits", lightHits.toJsonValue())
                    next.put("remHits", remHits.toJsonValue())
                    let lastLightAt = if (normalizedPhase == "light") { now } else { stpGetJsonStringValue(existing, "lastLightAt", "") }
                    let lastRemAt = if (normalizedPhase == "rem") { now } else { stpGetJsonStringValue(existing, "lastRemAt", "") }
                    if (!lastLightAt.isEmpty()) {
                        next.put("lastLightAt", JsonString(lastLightAt))
                    }
                    if (!lastRemAt.isEmpty()) {
                        next.put("lastRemAt", JsonString(lastRemAt))
                    }
                    entries.put(key, next)
                }
                root.put("updatedAt", JsonString(now))
                root.put("entries", entries)
                File.writeTo(phaseSignalsPath(), root.toJsonString().toArray())
            } catch (e: Exception) {
                LogUtils.error("Failed to record dreaming phase signals: ${e.message}")
            } finally {
                endLock()
            }
        }
    }

    public static func phaseSignalBoost(key: String): Float64 {
        let root = readPhaseSignalStore()
        let entries = match (root.get("entries")) {
            case Some(obj: JsonObject) => obj
            case _ => JsonObject()
        }
        match (entries.get(key.trimAscii())) {
            case Some(obj: JsonObject) =>
                let lightHits = stpGetJsonInt64Value(obj, "lightHits", 0)
                let remHits = stpGetJsonInt64Value(obj, "remHits", 0)
                min(Float64(lightHits) * 0.01, LIGHT_PHASE_BOOST_MAX) + min(Float64(remHits) * 0.02, REM_PHASE_BOOST_MAX)
            case _ => 0.0
        }
    }

    public static func buildPromotionCandidate(
        text: String,
        sourcePath: String,
        line: Int64,
        durableContent: String,
        includePromoted: Bool,
        promotedAudit: HashSet<String>
    ): Option<LocalMemoryPromoteCandidate> {
        let trimmed = text.trimAscii()
        if (trimmed.isEmpty()) {
            return None
        }
        let candidateKey = stpNormalizeRecallKey(trimmed)
        let recallKey = "memory:${sourcePath}:${line}:${line}"
        let recallStore = readRecallStore()
        let recallEntries = match (recallStore.get("entries")) {
            case Some(obj: JsonObject) => obj
            case _ => JsonObject()
        }
        let recallEntry = match (recallEntries.get(recallKey)) {
            case Some(obj: JsonObject) => Some(obj)
            case _ => None<JsonObject>
        }
        let promotedAt = match (recallEntry) {
            case Some(obj) => stpGetJsonStringValue(obj, "promotedAt", "")
            case None => ""
        }
        if (!includePromoted && (durableContent.contains(trimmed) || promotedAudit.contains(candidateKey) || !promotedAt.isEmpty())) {
            return None
        }
        let conceptTags = stpDeriveConceptTags(trimmed)
        let recallCount = match (recallEntry) {
            case Some(obj) => stpGetJsonInt64Value(obj, "recallCount", 0)
            case None => 0
        }
        let uniqueQueries = match (recallEntry) {
            case Some(obj) => Int64(stpReadJsonStringArray(obj, "queryHashes").size)
            case None => 0
        }
        let recallDays = match (recallEntry) {
            case Some(obj) => Int64(stpReadJsonStringArray(obj, "recallDays").size)
            case None => 0
        }
        let recencyBoost = match (recallEntry) {
            case Some(obj) => stpComputeRecencyBoost(stpGetJsonStringValue(obj, "lastRecalledAt", ""))
            case None => 0.0
        }
        let avgScore = match (recallEntry) {
            case Some(obj) =>
                let totalScore = stpGetJsonFloat64Value(obj, "totalScore", 0.0)
                let recallCountF = Float64(max(recallCount, 1))
                totalScore / recallCountF
            case None => 0.0
        }
        let phaseBoost = phaseSignalBoost(recallKey)
        if (!stpHasCueWords(trimmed) && recallCount < DEFAULT_PROMOTION_MIN_RECALL_COUNT) {
            return None
        }
        if (!stpHasCueWords(trimmed) && uniqueQueries < DEFAULT_PROMOTION_MIN_UNIQUE_QUERIES) {
            return None
        }
        let score = stpPromotionScore(
            trimmed,
            sourcePath,
            recallCount,
            uniqueQueries,
            recallDays,
            recencyBoost,
            Int64(conceptTags.size),
            avgScore,
            phaseBoost
        )
        if (!stpHasCueWords(trimmed) && score < DEFAULT_PROMOTION_MIN_SCORE) {
            return None
        }
        Some(
            LocalMemoryPromoteCandidate(
                trimmed,
                sourcePath,
                line,
                score,
                conceptTags,
                recallCount,
                uniqueQueries,
                recallDays,
                recencyBoost + phaseBoost,
                avgScore
            )
        )
    }

    public static func buildAuditSummaryJson(): String {
        let root = JsonObject()
        let store = readRecallStore()
        let entryCount = stpGetJsonInt64Value(store, "entryCount", 0)
        let promotedCount = stpGetJsonInt64Value(store, "promotedCount", 0)
        let conceptTaggedCount = stpGetJsonInt64Value(store, "conceptTaggedCount", 0)
        let spacedEntryCount = max(0, entryCount - conceptTaggedCount)
        let invalidEntryCount: Int64 = 0
        let issues = JsonArray([])
        if (!exists(storePath())) {
            issues.add(
                buildAuditIssue(
                    "recall-store-empty",
                    "Short-term recall store is missing and will be created on demand."
                )
            )
        }
        if (exists(runtimeLockPath())) {
            issues.add(
                buildAuditIssue(
                    "recall-lock-stale",
                    "Short-term promotion lock is present; stale locks are removed during repair/fix."
                )
            )
        }
        if (!exists(phaseSignalsPath())) {
            issues.add(
                buildAuditIssue(
                    "phase-signal-store-missing",
                    "Short-term phase signal store is missing and will be created on demand."
                )
            )
        }
        if (!exists(auditPath())) {
            issues.add(
                buildAuditIssue(
                    "promoted-audit-missing",
                    "Promoted audit store is missing and will be created on demand."
                )
            )
        }
        if (invalidEntryCount > 0) {
            issues.add(
                buildAuditIssue(
                    "recall-store-invalid",
                    "${invalidEntryCount} short-term recall entries are incomplete and can be normalized during repair."
                )
            )
        }
        root.put("status", JsonString("ok"))
        root.put("action", JsonString("memory_short_term_audit"))
        root.put("storePath", JsonString(storePath().toString()))
        root.put("phaseSignalPath", JsonString(phaseSignalsPath().toString()))
        root.put("lockPath", JsonString(runtimeLockPath().toString()))
        root.put("auditPath", JsonString(auditPath().toString()))
        root.put("recallStorePresent", exists(storePath()).toJsonValue())
        root.put("phaseSignalPresent", exists(phaseSignalsPath()).toJsonValue())
        root.put("lockPresent", exists(runtimeLockPath()).toJsonValue())
        root.put("auditPresent", exists(auditPath()).toJsonValue())
        root.put("entryCount", entryCount.toJsonValue())
        root.put("promotedCount", promotedCount.toJsonValue())
        root.put("spacedEntryCount", spacedEntryCount.toJsonValue())
        root.put("conceptTaggedEntryCount", conceptTaggedCount.toJsonValue())
        root.put("invalidEntryCount", invalidEntryCount.toJsonValue())
        root.put("updatedAt", JsonString(stpGetJsonStringValue(store, "updatedAt", "")))
        let thresholds = JsonObject()
        thresholds.put("minScore", JsonFloat(DEFAULT_PROMOTION_MIN_SCORE))
        thresholds.put("minRecallCount", DEFAULT_PROMOTION_MIN_RECALL_COUNT.toJsonValue())
        thresholds.put("minUniqueQueries", DEFAULT_PROMOTION_MIN_UNIQUE_QUERIES.toJsonValue())
        root.put("defaultThresholds", thresholds)
        let weights = JsonObject()
        weights.put("frequency", JsonFloat(DEFAULT_WEIGHT_FREQUENCY))
        weights.put("relevance", JsonFloat(DEFAULT_WEIGHT_RELEVANCE))
        weights.put("diversity", JsonFloat(DEFAULT_WEIGHT_DIVERSITY))
        weights.put("recency", JsonFloat(DEFAULT_WEIGHT_RECENCY))
        weights.put("consolidation", JsonFloat(DEFAULT_WEIGHT_CONSOLIDATION))
        weights.put("conceptual", JsonFloat(DEFAULT_WEIGHT_CONCEPTUAL))
        root.put("defaultWeights", weights)
        root.put("issues", issues)
        root.toJsonString()
    }

    public static func fixArtifacts(): Array<String> {
        let fixes = ArrayList<String>()
        let recallPath = storePath()
        if (!exists(recallPath)) {
            File.writeTo(recallPath, initRecallStore().toJsonString().toArray())
            fixes.add("created short-term recall store: ${recallPath}")
        } else {
            File.writeTo(recallPath, readRecallStore().toJsonString().toArray())
            fixes.add("normalized short-term recall store: ${recallPath}")
        }

        let signalPath = phaseSignalsPath()
        if (!exists(signalPath)) {
            File.writeTo(signalPath, initPhaseSignalStore().toJsonString().toArray())
            fixes.add("created phase signal store: ${signalPath}")
        } else {
            File.writeTo(signalPath, readPhaseSignalStore().toJsonString().toArray())
            fixes.add("normalized phase signal store: ${signalPath}")
        }

        staleLockRemoved(fixes)
        let auditPath = auditPath()
        if (!exists(auditPath)) {
            File.writeTo(auditPath, "".toArray())
            fixes.add("created promoted audit store: ${auditPath}")
        }
        fixes.toArray()
    }
}
