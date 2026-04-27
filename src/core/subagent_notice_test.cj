package metis.core

import std.fs.{Directory, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*

@Test
public class SubagentNoticeTest {
    private func tempSessionsRoot(label: String): Path {
        let root = Path("/tmp/metis-subagent-notice-${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        if (exists(root)) {
            remove(root, recursive: true)
        }
        Directory.create(root, recursive: true)
        root.join("agents").join("main").join("sessions")
    }

    @TestCase
    public func noticeTargetPrefersRequesterSession(): Unit {
        let sessionsRoot = this.tempSessionsRoot("target")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(
            sessionsRoot,
            "child-target",
            parentSessionKey: "agent:main:main",
            requesterSessionKey: "telegram:group:group:-100123:topic:42",
            requesterChannel: "telegram",
            requesterThreadId: "42",
            agentId: "reviewer"
        )

        @Expect(gatewaySubagentNoticeTargetSession(record), "telegram:group:group:-100123:topic:42")
        @Expect(gatewaySubagentRunRecordString(record, "requesterChannel"), "telegram")
        @Expect(gatewaySubagentRunRecordString(record, "requesterThreadId"), "42")
    }

    @TestCase
    public func renderSucceededNoticeContainsRunIdentitySummaryAndLogsHint(): Unit {
        let sessionsRoot = this.tempSessionsRoot("render")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(
            sessionsRoot,
            "child-render",
            agentId: "explorer",
            transcriptPath: "/tmp/child-render.jsonl"
        )
        let runId = gatewaySubagentRunRecordString(record, "runId")
        @Expect(gatewaySubagentMarkRunSucceeded(sessionsRoot, runId, resultSummary: "analysis done"), true)

        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                let notice = gatewaySubagentRenderNotice(found)
                @Expect(notice.contains("[Subagent succeeded] explorer ${runId}"), true)
                @Expect(notice.contains("Summary:\nanalysis done"), true)
                @Expect(notice.contains("Logs: /subagents logs ${runId}"), true)
                @Expect(gatewaySubagentNoticeShouldDeliver(found), true)
            case None => @Expect("missing", "record")
        }
    }

    @TestCase
    public func noticeStatusUpdatesAttemptsAndBlocksDuplicateDelivery(): Unit {
        let sessionsRoot = this.tempSessionsRoot("status")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-status", agentId: "planner")
        let runId = gatewaySubagentRunRecordString(record, "runId")

        @Expect(gatewaySubagentMarkRunTimedOut(sessionsRoot, runId, 5), true)
        @Expect(gatewaySubagentUpdateNoticeStatus(sessionsRoot, runId, "failed", error: "no target"), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "noticeStatus"), "failed")
                @Expect(gatewaySubagentRunRecordString(found, "lastNoticeError"), "no target")
                @Expect(gatewaySubagentRunRecordInt(found, "noticeAttempts"), 1)
                @Expect(gatewaySubagentNoticeShouldDeliver(found), true)
            case None => @Expect("missing", "failed")
        }

        @Expect(gatewaySubagentUpdateNoticeStatus(sessionsRoot, runId, "delivered"), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "noticeStatus"), "delivered")
                @Expect(gatewaySubagentRunRecordInt(found, "noticeAttempts"), 2)
                @Expect(gatewaySubagentNoticeShouldDeliver(found), false)
            case None => @Expect("missing", "delivered")
        }
    }
}
