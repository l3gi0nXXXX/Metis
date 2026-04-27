package metis.core

import std.fs.{Directory, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*

@Test
public class SubagentStateTest {
    private func tempSessionsRoot(label: String): Path {
        let root = Path("/tmp/metis-subagent-state-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        if (exists(root)) {
            remove(root, recursive: true)
        }
        Directory.create(root, recursive: true)
        root.join("agents").join("main").join("sessions")
    }

    @TestCase
    public func runtimeStateNormalizesKnownTerminalAliases(): Unit {
        @Expect(gatewaySubagentRuntimeState("completed"), "succeeded")
        @Expect(gatewaySubagentRuntimeState("timeout"), "timed_out")
        @Expect(gatewaySubagentRuntimeState("cancelling"), "cancelled")
        @Expect(gatewaySubagentRunStatusIsTerminal("running"), false)
        @Expect(gatewaySubagentRunStatusIsTerminal("timed_out"), true)
    }

    @TestCase
    public func stateHelpersUpdateRunRecordLifecycleFields(): Unit {
        let sessionsRoot = this.tempSessionsRoot("lifecycle")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(
            sessionsRoot,
            "child-state-1",
            status: "queued",
            agentId: "reviewer"
        )
        let runId = gatewaySubagentRunRecordString(record, "runId")

        @Expect(gatewaySubagentMarkRunRunning(sessionsRoot, runId), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "status"), "running")
                @Expect(gatewaySubagentRunRecordInt(found, "startedAtMs") > 0, true)
            case None => @Expect("missing", "record")
        }

        @Expect(gatewaySubagentMarkRunSucceeded(sessionsRoot, runId, resultSummary: "done"), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "status"), "succeeded")
                @Expect(gatewaySubagentRunRecordString(found, "resultSummary"), "done")
                @Expect(gatewaySubagentRunRecordInt(found, "completedAtMs") > 0, true)
            case None => @Expect("missing", "record")
        }
    }

    @TestCase
    public func timeoutAndCancelHelpersPersistExpectedStatusAndError(): Unit {
        let sessionsRoot = this.tempSessionsRoot("terminal")
        Directory.create(sessionsRoot, recursive: true)
        let timeoutRecord = gatewaySubagentCreateRunRecord(sessionsRoot, "child-timeout", status: "running")
        let cancelRecord = gatewaySubagentCreateRunRecord(sessionsRoot, "child-cancel", status: "running")

        @Expect(gatewaySubagentMarkRunTimedOut(sessionsRoot, gatewaySubagentRunRecordString(timeoutRecord, "runId"), 3), true)
        @Expect(gatewaySubagentMarkRunCancelled(sessionsRoot, gatewaySubagentRunRecordString(cancelRecord, "runId"), reason: "killed"), true)

        match (gatewaySubagentResolveRunRecord(sessionsRoot, gatewaySubagentRunRecordString(timeoutRecord, "runId"))) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "status"), "timed_out")
                @Expect(gatewaySubagentRunRecordString(found, "error"), "subagent timed out after 3s")
            case None => @Expect("missing", "timeout")
        }
        match (gatewaySubagentResolveRunRecord(sessionsRoot, gatewaySubagentRunRecordString(cancelRecord, "runId"))) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "status"), "cancelled")
                @Expect(gatewaySubagentRunRecordString(found, "error"), "killed")
            case None => @Expect("missing", "cancel")
        }
    }
}
