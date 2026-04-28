package metis.core

import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.JsonObject

private func withSubagentFileCoordinationRoot<T>(label: String, block: (Path) -> T): T {
    let root = Path("/tmp/metis-subagent-file-coordination-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
    try {
        remove(root, recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(root, recursive: true)
    try {
        return block(root)
    } finally {
        try {
            remove(root, recursive: true)
        } catch (_: Exception) {
            ()
        }
    }
}

private func subagentFileTestSessionsRoot(root: Path): Path {
    let sessionsRoot = root.join("agents").join("main").join("sessions")
    Directory.create(sessionsRoot, recursive: true)
    sessionsRoot
}

private func subagentFileTestArraySize(record: JsonObject, key: String): Int64 {
    match (record.get(key)) {
        case Some(value) => try { Int64(value.asArray().size()) } catch (_: Exception) { 0 }
        case None => 0
    }
}

private func subagentFileTestString(record: JsonObject, key: String): String {
    match (record.get(key)) {
        case Some(value) => try { value.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class SubagentFileCoordinationTest {
    @TestCase
    public func recordReadAndWriteUpdatesRunRecord(): Unit {
        withSubagentFileCoordinationRoot("record") { root =>
            let sessionsRoot = subagentFileTestSessionsRoot(root)
            let file = root.join("tracked.txt")
            File.writeTo(file, "one\n".toArray())
            let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-record", status: "running")
            let runId = gatewaySubagentRunRecordString(record, "runId")

            @Expect(gatewaySubagentRecordFileRead(sessionsRoot, runId, file.toString()), true)
            @Expect(gatewaySubagentRecordFileWrite(sessionsRoot, runId, file.toString(), operation: "write"), true)

            match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
                case Some(updated) =>
                    @Expect(subagentFileTestArraySize(updated, "fileReads"), 1)
                    @Expect(subagentFileTestArraySize(updated, "fileWrites"), 1)
                case None => @Expect(true, false)
            }
        }
    }

    @TestCase
    public func staleWarningIsPersistedWhenFileChangedAfterRead(): Unit {
        withSubagentFileCoordinationRoot("stale") { root =>
            let sessionsRoot = subagentFileTestSessionsRoot(root)
            let file = root.join("stale.txt")
            File.writeTo(file, "before\n".toArray())
            let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-stale", status: "running")
            let runId = gatewaySubagentRunRecordString(record, "runId")

            @Expect(gatewaySubagentRecordFileRead(sessionsRoot, runId, file.toString()), true)
            File.writeTo(file, "changed by another run\n".toArray())
            let warning = gatewaySubagentCheckStaleBeforeWrite(sessionsRoot, runId, file.toString())
            @Expect(warning.contains("stale file warning"), true)

            match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
                case Some(updated) =>
                    @Expect(subagentFileTestArraySize(updated, "warnings"), 1)
                    @Expect(subagentFileTestArraySize(updated, "coordinationLogs"), 1)
                case None => @Expect(true, false)
            }
        }
    }

    @TestCase
    public func pathLockBlocksSecondActiveRun(): Unit {
        withSubagentFileCoordinationRoot("lock") { root =>
            let sessionsRoot = subagentFileTestSessionsRoot(root)
            let file = root.join("locked.txt")
            File.writeTo(file, "content\n".toArray())
            let first = gatewaySubagentCreateRunRecord(sessionsRoot, "child-lock-a", status: "running")
            let second = gatewaySubagentCreateRunRecord(sessionsRoot, "child-lock-b", status: "running")
            let firstRunId = gatewaySubagentRunRecordString(first, "runId")
            let secondRunId = gatewaySubagentRunRecordString(second, "runId")

            let firstLock = gatewaySubagentTryLockPath(sessionsRoot, firstRunId, file.toString())
            @Expect(firstLock[0], true)
            let secondLock = gatewaySubagentTryLockPath(sessionsRoot, secondRunId, file.toString())
            @Expect(secondLock[0], false)
            @Expect(secondLock[1].contains("path locked by subagent run"), true)

            @Expect(gatewaySubagentUnlockPath(sessionsRoot, firstRunId, file.toString()), true)
            let secondRetry = gatewaySubagentTryLockPath(sessionsRoot, secondRunId, file.toString())
            @Expect(secondRetry[0], true)
        }
    }

    @TestCase
    public func writeCoordinationRecordsWarningAndReleasesLock(): Unit {
        withSubagentFileCoordinationRoot("write") { root =>
            let sessionsRoot = subagentFileTestSessionsRoot(root)
            let file = root.join("write.txt")
            File.writeTo(file, "initial\n".toArray())
            let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-write", status: "running")
            let runId = gatewaySubagentRunRecordString(record, "runId")

            @Expect(gatewaySubagentRecordFileRead(sessionsRoot, runId, file.toString()), true)
            File.writeTo(file, "external change\n".toArray())
            let lock = gatewaySubagentTryLockPath(sessionsRoot, runId, file.toString())
            @Expect(lock[0], true)
            let warning = gatewaySubagentCheckStaleBeforeWrite(sessionsRoot, runId, file.toString())
            @Expect(warning.contains("stale file warning"), true)
            File.writeTo(file, "subagent write\n".toArray())
            @Expect(gatewaySubagentRecordFileWrite(sessionsRoot, runId, file.toString(), operation: "write", warning: warning), true)
            @Expect(gatewaySubagentUnlockPath(sessionsRoot, runId, file.toString()), true)

            match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
                case Some(updated) =>
                    @Expect(subagentFileTestArraySize(updated, "fileReads"), 1)
                    @Expect(subagentFileTestArraySize(updated, "fileWrites"), 1)
                    @Expect(subagentFileTestArraySize(updated, "warnings"), 1)
                case None => @Expect(true, false)
            }
        }
    }
}
