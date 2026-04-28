package metis.core

import magic.prelude.*

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private func subagentNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func subagentSafeFileStem(raw: String): String {
    var s = raw.trimAscii()
    let bad = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*", "\r", "\n", "\t", " "]
    for (b in bad) {
        s = s.replace(b, "_")
    }
    if (s.size > 64) {
        s = s[0..64]
    }
    if (s.isEmpty()) {
        return "empty"
    }
    s
}

private func subagentJsonString(record: JsonObject, key: String): String {
    match (record.get(key)) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func subagentJsonInt(record: JsonObject, key: String): Int64 {
    match (record.get(key)) {
        case Some(value) =>
            try { Int64.parse(value.toJsonString()) } catch (_: Exception) {
                try { Int64.parse(value.asString().getValue().trimAscii()) } catch (_inner: Exception) { 0 }
            }
        case None => 0
    }
}

private func normalizeSubagentStatus(status: String): String {
    match (status.trimAscii().toAsciiLower()) {
        case "completed" | "complete" | "success" | "ok" | "succeeded" => "succeeded"
        case "cancelling" | "canceling" | "cancelled" | "canceled" => "cancelled"
        case "timeout" | "timedout" | "timed_out" => "timed_out"
        case "running" => "running"
        case "queued" => "queued"
        case "failed" | "error" => "failed"
        case _ => "queued"
    }
}

public func gatewaySubagentRunsRoot(sessionsRoot: Path): Path {
    sessionsRoot.parent.join("subagents").join("runs")
}

public func gatewaySubagentRunRecordPath(sessionsRoot: Path, runId: String): Path {
    gatewaySubagentRunsRoot(sessionsRoot).join("${subagentSafeFileStem(runId)}.json")
}

public func gatewaySubagentRunIndexPath(sessionsRoot: Path): Path {
    gatewaySubagentRunsRoot(sessionsRoot).join("index.json")
}

public func gatewaySubagentRunRecordString(record: JsonObject, key: String): String {
    subagentJsonString(record, key)
}

public func gatewaySubagentRunRecordInt(record: JsonObject, key: String): Int64 {
    subagentJsonInt(record, key)
}

public func gatewaySubagentNewRunId(sessionsRoot: Path, sessionKey: String): String {
    let root = gatewaySubagentRunsRoot(sessionsRoot)
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    let now = subagentNowMs()
    let stem = subagentSafeFileStem(sessionKey)
    let base = "subrun_${now}_${stem}"
    var runId = base
    var n: Int64 = 0
    while (exists(gatewaySubagentRunRecordPath(sessionsRoot, runId))) {
        n += 1
        runId = "${base}_${n}"
    }
    runId
}

public func gatewaySubagentReadRunRecord(sessionsRoot: Path, runId: String): Option<JsonObject> {
    let path = gatewaySubagentRunRecordPath(sessionsRoot, runId)
    if (!exists(path)) {
        return None
    }
    try {
        Some(JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject())
    } catch (_: Exception) {
        None
    }
}

private func writeSubagentRunIndex(sessionsRoot: Path, records: Array<JsonObject>): Unit {
    let root = gatewaySubagentRunsRoot(sessionsRoot)
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    let runs = JsonArray([])
    for (record in records) {
        let row = JsonObject()
        row.put("runId", JsonString(subagentJsonString(record, "runId")))
        row.put("sessionKey", JsonString(subagentJsonString(record, "sessionKey")))
        row.put("parentSessionKey", JsonString(subagentJsonString(record, "parentSessionKey")))
        row.put("agentId", JsonString(subagentJsonString(record, "agentId")))
        row.put("runtime", JsonString(subagentJsonString(record, "runtime")))
        row.put("status", JsonString(subagentJsonString(record, "status")))
        row.put("createdAtMs", subagentJsonInt(record, "createdAtMs").toJsonValue())
        row.put("lastUpdatedAtMs", subagentJsonInt(record, "lastUpdatedAtMs").toJsonValue())
        runs.add(row)
    }
    let index = JsonObject()
    index.put("schemaVersion", 1.toJsonValue())
    index.put("runs", runs)
    File.writeTo(gatewaySubagentRunIndexPath(sessionsRoot), index.toJsonString().toArray())
}

public func gatewaySubagentListRunRecords(sessionsRoot: Path): Array<JsonObject> {
    let out = ArrayList<JsonObject>()
    let root = gatewaySubagentRunsRoot(sessionsRoot)
    if (!exists(root)) {
        return out.toArray()
    }
    try {
        for (entry in Directory.readFrom(root)) {
            if (!entry.isRegular()) {
                continue
            }
            let name = entry.name
            if (name == "index.json" || !name.endsWith(".json")) {
                continue
            }
            let path = root.join(name)
            try {
                let record = JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
                if (!subagentJsonString(record, "runId").isEmpty()) {
                    out.add(record)
                }
            } catch (_inner: Exception) {
                ()
            }
        }
    } catch (_: Exception) {
        ()
    }
    out.toArray()
}

public func gatewaySubagentWriteRunRecord(sessionsRoot: Path, record: JsonObject): Bool {
    let runId = subagentJsonString(record, "runId")
    if (runId.isEmpty()) {
        return false
    }
    let root = gatewaySubagentRunsRoot(sessionsRoot)
    if (!exists(root)) {
        Directory.create(root, recursive: true)
    }
    try {
        File.writeTo(gatewaySubagentRunRecordPath(sessionsRoot, runId), record.toJsonString().toArray())
        writeSubagentRunIndex(sessionsRoot, gatewaySubagentListRunRecords(sessionsRoot))
        true
    } catch (_: Exception) {
        false
    }
}

public func gatewaySubagentCreateRunRecord(
    sessionsRoot: Path,
    sessionKey: String,
    parentSessionKey!: String = "",
    requesterSessionKey!: String = "",
    requesterChannel!: String = "cli",
    requesterThreadId!: String = "",
    agentId!: String = "",
    agentSource!: String = "builtin",
    runtime!: String = "subagent",
    task!: String = "",
    label!: String = "",
    status!: String = "queued",
    cwd!: String = "",
    model!: String = "",
    thinking!: String = "",
    timeoutSeconds!: Int64 = -1,
    contextMode!: String = "fresh",
    transcriptPath!: String = ""
): JsonObject {
    let now = subagentNowMs()
    let runId = gatewaySubagentNewRunId(sessionsRoot, sessionKey)
    let record = JsonObject()
    record.put("schemaVersion", 1.toJsonValue())
    record.put("runId", JsonString(runId))
    record.put("sessionKey", JsonString(sessionKey.trimAscii()))
    record.put("parentSessionKey", JsonString(parentSessionKey.trimAscii()))
    record.put("requesterSessionKey", JsonString(requesterSessionKey.trimAscii()))
    record.put("requesterChannel", JsonString(requesterChannel.trimAscii()))
    record.put("requesterThreadId", JsonString(requesterThreadId.trimAscii()))
    record.put("requesterClientId", JsonString(""))
    record.put("requesterAccountId", JsonString(""))
    record.put("requesterPeerId", JsonString(""))
    record.put("requesterConversationId", JsonString(""))
    record.put("requesterReplyToMessageId", JsonString(""))
    record.put("requesterReplyInThread", JsonBool(false))
    record.put("agentId", JsonString(agentId.trimAscii()))
    record.put("agentSource", JsonString(agentSource.trimAscii()))
    record.put("runtime", JsonString(runtime.trimAscii()))
    record.put("task", JsonString(task))
    record.put("label", JsonString(label.trimAscii()))
    record.put("status", JsonString(normalizeSubagentStatus(status)))
    record.put("role", JsonString("leaf"))
    record.put("depth", 1.toJsonValue())
    record.put("parentRunId", JsonString(""))
    record.put("children", JsonArray([]))
    record.put("contextMode", JsonString(gatewaySubagentNormalizeContextMode(contextMode)))
    record.put("isolationMode", JsonString("shared"))
    record.put("cwd", JsonString(cwd.trimAscii()))
    record.put("worktreePath", JsonString(""))
    record.put("sandbox", JsonString("inherit"))
    record.put("model", JsonString(model.trimAscii()))
    record.put("thinking", JsonString(thinking.trimAscii()))
    record.put("timeoutSeconds", timeoutSeconds.toJsonValue())
    record.put("createdAtMs", now.toJsonValue())
    record.put("startedAtMs", 0.toJsonValue())
    record.put("completedAtMs", 0.toJsonValue())
    record.put("lastUpdatedAtMs", now.toJsonValue())
    record.put("resultSummary", JsonString(""))
    record.put("outputPath", JsonString(""))
    record.put("transcriptPath", JsonString(transcriptPath.trimAscii()))
    record.put("error", JsonString(""))
    record.put("exitCode", 0.toJsonValue())
    record.put("cancelRequested", JsonBool(false))
    record.put("noticeStatus", JsonString("none"))
    record.put("noticeAttempts", 0.toJsonValue())
    record.put("lastNoticeError", JsonString(""))
    record.put("cleanupMode", JsonString("keep"))
    record.put("fileReads", JsonArray([]))
    record.put("fileWrites", JsonArray([]))
    record.put("locks", JsonArray([]))
    record.put("metadata", JsonObject())
    let _ = gatewaySubagentWriteRunRecord(sessionsRoot, record)
    record
}

public func gatewaySubagentFindRunBySessionKey(sessionsRoot: Path, sessionKey: String): Option<JsonObject> {
    let target = sessionKey.trimAscii()
    if (target.isEmpty()) {
        return None
    }
    for (record in gatewaySubagentListRunRecords(sessionsRoot)) {
        if (subagentJsonString(record, "sessionKey") == target) {
            return Some(record)
        }
    }
    None
}

public func gatewaySubagentResolveRunRecord(sessionsRoot: Path, target: String): Option<JsonObject> {
    let trimmed = target.trimAscii()
    if (trimmed.isEmpty()) {
        return None
    }
    match (gatewaySubagentReadRunRecord(sessionsRoot, trimmed)) {
        case Some(record) => return Some(record)
        case None => ()
    }
    for (record in gatewaySubagentListRunRecords(sessionsRoot)) {
        let runId = subagentJsonString(record, "runId")
        let sessionKey = subagentJsonString(record, "sessionKey")
        let lower = trimmed.toAsciiLower()
        if (runId == trimmed || sessionKey == trimmed ||
            runId.toAsciiLower().contains(lower) ||
            sessionKey.toAsciiLower().contains(lower)) {
            return Some(record)
        }
    }
    None
}

public func gatewaySubagentUpdateRunStatus(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    status: String,
    resultSummary!: String = "",
    error!: String = "",
    exitCode!: Int64 = 0,
    outputPath!: String = ""
): Bool {
    let resolved = match (gatewaySubagentResolveRunRecord(sessionsRoot, runIdOrSessionKey)) {
        case Some(record) => record
        case None =>
            match (gatewaySubagentFindRunBySessionKey(sessionsRoot, runIdOrSessionKey)) {
                case Some(record) => record
                case None => return false
            }
    }
    let now = subagentNowMs()
    let normalized = normalizeSubagentStatus(status)
    resolved.put("status", JsonString(normalized))
    resolved.put("lastUpdatedAtMs", now.toJsonValue())
    if (normalized == "running" && subagentJsonInt(resolved, "startedAtMs") == 0) {
        resolved.put("startedAtMs", now.toJsonValue())
    }
    if (normalized == "succeeded" || normalized == "failed" || normalized == "cancelled" || normalized == "timed_out") {
        resolved.put("completedAtMs", now.toJsonValue())
    }
    if (!resultSummary.trimAscii().isEmpty()) {
        resolved.put("resultSummary", JsonString(resultSummary.trimAscii()))
    }
    if (!error.trimAscii().isEmpty()) {
        resolved.put("error", JsonString(error.trimAscii()))
    }
    if (!outputPath.trimAscii().isEmpty()) {
        resolved.put("outputPath", JsonString(outputPath.trimAscii()))
    }
    resolved.put("exitCode", exitCode.toJsonValue())
    gatewaySubagentWriteRunRecord(sessionsRoot, resolved)
}
