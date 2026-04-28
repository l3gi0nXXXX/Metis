package metis.core

import magic.prelude.*

import metis.core.config.CliConfig

import std.collection.ArrayList
import std.convert.Parsable
import std.fs.{Directory, File, Path, exists}
import std.sync.Mutex
import std.time.DateTime
import stdx.encoding.json.{JsonArray, JsonBool, JsonObject, JsonString, JsonValue}

private let subagentFileCoordinationLock = Mutex()

private func subagentFileNowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toNanoseconds() / 1000000
}

private func subagentFileJsonString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue().trimAscii() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func subagentFileJsonInt(obj: JsonObject, key: String): Int64 {
    match (obj.get(key)) {
        case Some(value) =>
            try { Int64.parse(value.toJsonString()) } catch (_: Exception) {
                try { Int64.parse(value.asString().getValue().trimAscii()) } catch (_inner: Exception) { 0 }
            }
        case None => 0
    }
}

private func subagentFileJsonArray(obj: JsonObject, key: String): JsonArray {
    match (obj.get(key)) {
        case Some(value) => try { value.asArray() } catch (_: Exception) { JsonArray([]) }
        case None => JsonArray([])
    }
}

private func subagentFileStatusIsTerminal(status: String): Bool {
    match (status.trimAscii().toAsciiLower()) {
        case "succeeded" | "failed" | "cancelled" | "canceled" | "timed_out" | "timeout" => true
        case _ => false
    }
}

private func subagentFileFingerprint(path: String): String {
    let p = Path(path)
    if (!exists(p)) {
        return "missing"
    }
    try {
        let bytes = File.readFrom(p)
        var h: UInt64 = 5381
        var i: Int64 = 0
        let n = Int64(bytes.size)
        while (i < n) {
            h = ((h << 5) + h) + UInt64(UInt8(bytes[i]))
            i += 1
        }
        "bytes=${n};hash=${h}"
    } catch (_: Exception) {
        "unreadable"
    }
}

private func subagentFileSessionsRoots(): Array<Path> {
    let roots = ArrayList<Path>()
    let agentsRoot = CliConfig.dotDir.join("agents")
    if (!exists(agentsRoot)) {
        return roots.toArray()
    }
    try {
        for (entry in Directory.readFrom(agentsRoot)) {
            if (entry.isDirectory()) {
                roots.add(agentsRoot.join(entry.name).join("sessions"))
            }
        }
    } catch (_: Exception) {
        ()
    }
    roots.toArray()
}

private func subagentFileResolveRunLocation(target: String): Option<(Path, JsonObject)> {
    let trimmed = target.trimAscii()
    if (trimmed.isEmpty()) {
        return None<(Path, JsonObject)>
    }
    for (sessionsRoot in subagentFileSessionsRoots()) {
        match (gatewaySubagentResolveRunRecord(sessionsRoot, trimmed)) {
            case Some(record) => return Some((sessionsRoot, record))
            case None => ()
        }
    }
    None<(Path, JsonObject)>
}

private func subagentFileCurrentRunLocation(): Option<(Path, JsonObject)> {
    match (gatewayCurrentToolRuntimeContext()) {
        case Some(context) => subagentFileResolveRunLocation(context.sessionKey)
        case None => None<(Path, JsonObject)>
    }
}

private func subagentFileAppendLog(record: JsonObject, level: String, message: String): Unit {
    let logs = subagentFileJsonArray(record, "coordinationLogs")
    let row = JsonObject()
    row.put("ts", subagentFileNowMs().toJsonValue())
    row.put("level", JsonString(level.trimAscii()))
    row.put("message", JsonString(message.trimAscii()))
    logs.add(row)
    record.put("coordinationLogs", logs)
}

private func subagentFileAppendWarning(record: JsonObject, path: String, message: String): Unit {
    let warnings = subagentFileJsonArray(record, "warnings")
    let row = JsonObject()
    row.put("kind", JsonString("stale"))
    row.put("path", JsonString(path.trimAscii()))
    row.put("message", JsonString(message.trimAscii()))
    row.put("observedAtMs", subagentFileNowMs().toJsonValue())
    warnings.add(row)
    record.put("warnings", warnings)
    subagentFileAppendLog(record, "warning", message)
}

private func subagentFileLastReadFingerprint(record: JsonObject, path: String): String {
    var fingerprint = ""
    for (item in subagentFileJsonArray(record, "fileReads").getItems()) {
        try {
            let row = item.asObject()
            if (subagentFileJsonString(row, "path") == path) {
                fingerprint = subagentFileJsonString(row, "fingerprint")
            }
        } catch (_: Exception) {
            ()
        }
    }
    fingerprint
}

public func gatewaySubagentRecordFileRead(sessionsRoot: Path, runIdOrSessionKey: String, filePath: String): Bool {
    synchronized(subagentFileCoordinationLock) {
        let record = match (gatewaySubagentResolveRunRecord(sessionsRoot, runIdOrSessionKey)) {
            case Some(value) => value
            case None => return false
        }
        let path = filePath.trimAscii()
        if (path.isEmpty()) {
            return false
        }
        let reads = subagentFileJsonArray(record, "fileReads")
        let row = JsonObject()
        row.put("path", JsonString(path))
        row.put("fingerprint", JsonString(subagentFileFingerprint(path)))
        row.put("observedAtMs", subagentFileNowMs().toJsonValue())
        reads.add(row)
        record.put("fileReads", reads)
        record.put("lastUpdatedAtMs", subagentFileNowMs().toJsonValue())
        gatewaySubagentWriteRunRecord(sessionsRoot, record)
    }
}

public func gatewaySubagentRecordCurrentFileRead(filePath: String): Bool {
    match (subagentFileCurrentRunLocation()) {
        case Some(location) => gatewaySubagentRecordFileRead(location[0], gatewaySubagentRunRecordString(location[1], "runId"), filePath)
        case None => false
    }
}

public func gatewaySubagentTryLockPath(sessionsRoot: Path, runIdOrSessionKey: String, filePath: String): (Bool, String) {
    synchronized(subagentFileCoordinationLock) {
        let target = match (gatewaySubagentResolveRunRecord(sessionsRoot, runIdOrSessionKey)) {
            case Some(value) => value
            case None => return (false, "subagent run not found")
        }
        let targetRunId = gatewaySubagentRunRecordString(target, "runId")
        let path = filePath.trimAscii()
        if (path.isEmpty()) {
            return (false, "file path is empty")
        }
        for (record in gatewaySubagentListRunRecords(sessionsRoot)) {
            let ownerRunId = gatewaySubagentRunRecordString(record, "runId")
            if (ownerRunId == targetRunId || subagentFileStatusIsTerminal(gatewaySubagentRunRecordString(record, "status"))) {
                continue
            }
            for (item in subagentFileJsonArray(record, "locks").getItems()) {
                try {
                    let lock = item.asObject()
                    if (subagentFileJsonString(lock, "path") == path && subagentFileJsonInt(lock, "releasedAtMs") == 0) {
                        let message = "path locked by subagent run ${ownerRunId}: ${path}"
                        subagentFileAppendLog(target, "warning", message)
                        let _ = gatewaySubagentWriteRunRecord(sessionsRoot, target)
                        return (false, message)
                    }
                } catch (_: Exception) {
                    ()
                }
            }
        }
        let locks = subagentFileJsonArray(target, "locks")
        let lock = JsonObject()
        lock.put("path", JsonString(path))
        lock.put("lockedAtMs", subagentFileNowMs().toJsonValue())
        lock.put("releasedAtMs", 0.toJsonValue())
        locks.add(lock)
        target.put("locks", locks)
        target.put("lastUpdatedAtMs", subagentFileNowMs().toJsonValue())
        let _ = gatewaySubagentWriteRunRecord(sessionsRoot, target)
        (true, "")
    }
}

public func gatewaySubagentUnlockPath(sessionsRoot: Path, runIdOrSessionKey: String, filePath: String): Bool {
    synchronized(subagentFileCoordinationLock) {
        let record = match (gatewaySubagentResolveRunRecord(sessionsRoot, runIdOrSessionKey)) {
            case Some(value) => value
            case None => return false
        }
        let path = filePath.trimAscii()
        var changed = false
        let locks = subagentFileJsonArray(record, "locks")
        for (item in locks.getItems()) {
            try {
                let lock = item.asObject()
                if (subagentFileJsonString(lock, "path") == path && subagentFileJsonInt(lock, "releasedAtMs") == 0) {
                    lock.put("releasedAtMs", subagentFileNowMs().toJsonValue())
                    changed = true
                }
            } catch (_: Exception) {
                ()
            }
        }
        if (changed) {
            record.put("locks", locks)
            record.put("lastUpdatedAtMs", subagentFileNowMs().toJsonValue())
            return gatewaySubagentWriteRunRecord(sessionsRoot, record)
        }
        false
    }
}

public func gatewaySubagentCheckStaleBeforeWrite(sessionsRoot: Path, runIdOrSessionKey: String, filePath: String): String {
    synchronized(subagentFileCoordinationLock) {
        let record = match (gatewaySubagentResolveRunRecord(sessionsRoot, runIdOrSessionKey)) {
            case Some(value) => value
            case None => return ""
        }
        let path = filePath.trimAscii()
        let readFingerprint = subagentFileLastReadFingerprint(record, path)
        if (readFingerprint.isEmpty()) {
            return ""
        }
        let currentFingerprint = subagentFileFingerprint(path)
        if (readFingerprint == currentFingerprint) {
            return ""
        }
        let message = "stale file warning: ${path} changed since this subagent last read it"
        subagentFileAppendWarning(record, path, message)
        record.put("lastUpdatedAtMs", subagentFileNowMs().toJsonValue())
        let _ = gatewaySubagentWriteRunRecord(sessionsRoot, record)
        message
    }
}

public func gatewaySubagentRecordFileWrite(
    sessionsRoot: Path,
    runIdOrSessionKey: String,
    filePath: String,
    operation!: String = "write",
    warning!: String = ""
): Bool {
    synchronized(subagentFileCoordinationLock) {
        let record = match (gatewaySubagentResolveRunRecord(sessionsRoot, runIdOrSessionKey)) {
            case Some(value) => value
            case None => return false
        }
        let writes = subagentFileJsonArray(record, "fileWrites")
        let row = JsonObject()
        row.put("path", JsonString(filePath.trimAscii()))
        row.put("operation", JsonString(operation.trimAscii()))
        row.put("fingerprint", JsonString(subagentFileFingerprint(filePath)))
        row.put("stale", JsonBool(!warning.trimAscii().isEmpty()))
        row.put("warning", JsonString(warning.trimAscii()))
        row.put("observedAtMs", subagentFileNowMs().toJsonValue())
        writes.add(row)
        record.put("fileWrites", writes)
        if (!warning.trimAscii().isEmpty()) {
            subagentFileAppendLog(record, "warning", warning)
        }
        record.put("lastUpdatedAtMs", subagentFileNowMs().toJsonValue())
        gatewaySubagentWriteRunRecord(sessionsRoot, record)
    }
}

public func gatewaySubagentBeforeCurrentFileWrite(filePath: String, operation!: String = "write"): (Bool, String) {
    match (subagentFileCurrentRunLocation()) {
        case Some(location) =>
            let runId = gatewaySubagentRunRecordString(location[1], "runId")
            let locked = gatewaySubagentTryLockPath(location[0], runId, filePath)
            if (!locked[0]) {
                return locked
            }
            let warning = gatewaySubagentCheckStaleBeforeWrite(location[0], runId, filePath)
            (true, warning)
        case None => (true, "")
    }
}

public func gatewaySubagentAfterCurrentFileWrite(filePath: String, operation!: String = "write", warning!: String = ""): Bool {
    match (subagentFileCurrentRunLocation()) {
        case Some(location) =>
            let runId = gatewaySubagentRunRecordString(location[1], "runId")
            let wrote = gatewaySubagentRecordFileWrite(location[0], runId, filePath, operation: operation, warning: warning)
            let _ = gatewaySubagentUnlockPath(location[0], runId, filePath)
            wrote
        case None => false
    }
}

public func gatewaySubagentCancelCurrentFileWrite(filePath: String): Bool {
    match (subagentFileCurrentRunLocation()) {
        case Some(location) => gatewaySubagentUnlockPath(location[0], gatewaySubagentRunRecordString(location[1], "runId"), filePath)
        case None => false
    }
}
