package metis.core

import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*

@Test
public class SubagentRunStoreTest {
    private func tempSessionsRoot(label: String): Path {
        let root = Path("/tmp/metis-subagent-run-store-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        if (exists(root)) {
            remove(root, recursive: true)
        }
        Directory.create(root, recursive: true)
        root.join("agents").join("main").join("sessions")
    }

    @TestCase
    public func createListResolveAndUpdateRunRecord(): Unit {
        let sessionsRoot = this.tempSessionsRoot("basic")
        Directory.create(sessionsRoot, recursive: true)

        let record = gatewaySubagentCreateRunRecord(
            sessionsRoot,
            "gateway:spawn:subagent-reviewer:1",
            parentSessionKey: "agent:main:main",
            requesterSessionKey: "agent:main:main",
            requesterChannel: "cli",
            agentId: "reviewer",
            runtime: "subagent",
            task: "review current diff",
            label: "review",
            cwd: "/tmp/project",
            timeoutSeconds: 120,
            transcriptPath: sessionsRoot.join("gateway_spawn_subagent-reviewer_1.jsonl").toString()
        )

        let runId = gatewaySubagentRunRecordString(record, "runId")
        @Expect(runId.startsWith("subrun_"), true)
        @Expect(runId == "gateway:spawn:subagent-reviewer:1", false)
        @Expect(gatewaySubagentRunRecordString(record, "sessionKey"), "gateway:spawn:subagent-reviewer:1")
        @Expect(gatewaySubagentRunRecordString(record, "status"), "queued")

        let listed = gatewaySubagentListRunRecords(sessionsRoot)
        @Expect(listed.size, 1)
        @Expect(gatewaySubagentRunRecordString(listed[0], "runId"), runId)
        @Expect(exists(gatewaySubagentRunIndexPath(sessionsRoot)), true)

        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "agentId"), "reviewer")
            case None => @Expect("missing", "record")
        }
        match (gatewaySubagentFindRunBySessionKey(sessionsRoot, "gateway:spawn:subagent-reviewer:1")) {
            case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "runId"), runId)
            case None => @Expect("missing", "record")
        }

        @Expect(gatewaySubagentUpdateRunStatus(sessionsRoot, runId, "running"), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "status"), "running")
                @Expect(gatewaySubagentRunRecordInt(found, "startedAtMs") > 0, true)
            case None => @Expect("missing", "record")
        }

        @Expect(
            gatewaySubagentUpdateRunStatus(
                sessionsRoot,
                "gateway:spawn:subagent-reviewer:1",
                "completed",
                resultSummary: "done",
                outputPath: "/tmp/subagent-output.txt"
            ),
            true
        )
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "status"), "succeeded")
                @Expect(gatewaySubagentRunRecordString(found, "resultSummary"), "done")
                @Expect(gatewaySubagentRunRecordString(found, "outputPath"), "/tmp/subagent-output.txt")
                @Expect(gatewaySubagentRunRecordInt(found, "completedAtMs") > 0, true)
            case None => @Expect("missing", "record")
        }
    }

    @TestCase
    public func sessionKeyResolutionPrefersLatestAndFuzzyAmbiguityReturnsNone(): Unit {
        let sessionsRoot = this.tempSessionsRoot("resolve")
        Directory.create(sessionsRoot, recursive: true)
        let older = gatewaySubagentCreateRunRecord(sessionsRoot, "child-dup", status: "running")
        let newer = gatewaySubagentCreateRunRecord(sessionsRoot, "child-dup", status: "queued")
        let other = gatewaySubagentCreateRunRecord(sessionsRoot, "child-dup-other", status: "queued")
        let newerRunId = gatewaySubagentRunRecordString(newer, "runId")

        @Expect(gatewaySubagentUpdateRunStatus(sessionsRoot, gatewaySubagentRunRecordString(older, "runId"), "running"), true)
        @Expect(gatewaySubagentUpdateRunStatus(sessionsRoot, newerRunId, "failed", error: "latest"), true)

        match (gatewaySubagentFindRunBySessionKey(sessionsRoot, "child-dup")) {
            case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "runId"), newerRunId)
            case None => @Expect("missing", "latest")
        }
        match (gatewaySubagentResolveRunRecord(sessionsRoot, "child-dup")) {
            case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "runId"), newerRunId)
            case None => @Expect("missing", "exact")
        }
        @Expect(gatewaySubagentResolveRunRecord(sessionsRoot, "dup").isNone(), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, gatewaySubagentRunRecordString(other, "runId"))) {
            case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "sessionKey"), "child-dup-other")
            case None => @Expect("missing", "runId")
        }
    }

    @TestCase
    public func newRunIdWithLongSessionKeyKeepsUniqueSuffixVisible(): Unit {
        let sessionsRoot = this.tempSessionsRoot("long-run-id")
        Directory.create(sessionsRoot, recursive: true)
        let longSessionKey = "cli:phase13-workers:child-session-name-that-is-long-enough-to-exceed-file-stem-limit"
        let first = gatewaySubagentNewRunId(sessionsRoot, longSessionKey)
        File.writeTo(gatewaySubagentRunRecordPath(sessionsRoot, first), "{}".toArray())
        let second = gatewaySubagentNewRunId(sessionsRoot, longSessionKey)

        @Expect(first == second, false)
        @Expect(gatewaySubagentRunRecordPath(sessionsRoot, first).toString() == gatewaySubagentRunRecordPath(sessionsRoot, second).toString(), false)
    }
}
