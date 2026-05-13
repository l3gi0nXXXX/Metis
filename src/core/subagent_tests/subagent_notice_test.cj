package metis.core.subagent_tests

import metis.core.*

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

    private func longRuneText(r: Rune, count: Int64): String {
        let sb = StringBuilder()
        for (_ in 0..count) {
            sb.append(r)
        }
        sb.toString()
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
    public func renderSucceededNoticeTruncatesUnicodeSummaryWithoutInvalidUtf8(): Unit {
        let sessionsRoot = this.tempSessionsRoot("render-unicode")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(
            sessionsRoot,
            "child-render-unicode",
            agentId: "explorer",
            transcriptPath: "/tmp/child-render-unicode.jsonl"
        )
        let runId = gatewaySubagentRunRecordString(record, "runId")
        let longSummary = this.longRuneText(r'词', 1300)
        @Expect(gatewaySubagentMarkRunSucceeded(sessionsRoot, runId, resultSummary: longSummary), true)

        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                let notice = gatewaySubagentRenderNotice(found)
                @Expect(notice.contains("[Subagent succeeded] explorer ${runId}"), true)
                @Expect(notice.contains("... (truncated)"), true)
                @Expect(notice.contains("Logs: /subagents logs ${runId}"), true)
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

    @TestCase
    public func laterSucceededStateCanDeliverAfterEarlierCancelledNotice(): Unit {
        let sessionsRoot = this.tempSessionsRoot("terminal-transition")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-terminal-transition", agentId: "explorer")
        let runId = gatewaySubagentRunRecordString(record, "runId")

        @Expect(gatewaySubagentMarkRunCancelled(sessionsRoot, runId, reason: "cancel requested"), true)
        @Expect(gatewaySubagentUpdateNoticeStatus(sessionsRoot, runId, "delivered"), true)
        @Expect(gatewaySubagentUpdateChannelNoticeStatus(sessionsRoot, runId, "failed", error: "subagent notice delivery hook is unavailable"), true)
        @Expect(gatewaySubagentMarkRunSucceeded(sessionsRoot, runId, resultSummary: "finished after child process completed"), true)

        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "status"), "succeeded")
                @Expect(gatewaySubagentRunRecordString(found, "error"), "")
                @Expect(gatewaySubagentRunRecordString(found, "noticeStatus"), "none")
                @Expect(gatewaySubagentRunRecordString(found, "channelNoticeStatus"), "none")
                @Expect(gatewaySubagentRunRecordString(found, "lastChannelNoticeError"), "")
                @Expect(gatewaySubagentNoticeShouldDeliver(found), true)
            case None => @Expect("missing", "record")
        }
    }

    @TestCase
    public func realtimeNoticeStatusIsTrackedSeparatelyFromTranscriptNotice(): Unit {
        let sessionsRoot = this.tempSessionsRoot("realtime-status")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-realtime", agentId: "reviewer")
        let runId = gatewaySubagentRunRecordString(record, "runId")

        @Expect(gatewaySubagentUpdateNoticeStatus(sessionsRoot, runId, "delivered"), true)
        @Expect(gatewaySubagentUpdateRealtimeNoticeStatus(sessionsRoot, runId, "delivered"), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "noticeStatus"), "delivered")
                @Expect(gatewaySubagentRunRecordString(found, "realtimeNoticeStatus"), "delivered")
                @Expect(gatewaySubagentRunRecordInt(found, "realtimeNoticeAttempts"), 1)
            case None => @Expect("missing", "realtime")
        }
    }

    @TestCase
    public func channelNoticeStatusIsTrackedSeparatelyFromTranscriptAndRealtimeNotice(): Unit {
        let sessionsRoot = this.tempSessionsRoot("channel-status")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-channel", agentId: "reviewer")
        let runId = gatewaySubagentRunRecordString(record, "runId")

        @Expect(gatewaySubagentUpdateNoticeStatus(sessionsRoot, runId, "delivered"), true)
        @Expect(gatewaySubagentUpdateChannelNoticeStatus(sessionsRoot, runId, "failed", error: "telegram adapter is not running"), true)
        match (gatewaySubagentResolveRunRecord(sessionsRoot, runId)) {
            case Some(found) =>
                @Expect(gatewaySubagentRunRecordString(found, "noticeStatus"), "delivered")
                @Expect(gatewaySubagentRunRecordString(found, "channelNoticeStatus"), "failed")
                @Expect(gatewaySubagentRunRecordString(found, "lastChannelNoticeError"), "telegram adapter is not running")
                @Expect(gatewaySubagentRunRecordInt(found, "channelNoticeAttempts"), 1)
            case None => @Expect("missing", "channel")
        }
    }

    @TestCase
    public func noticeDeliveryHookSendsThroughRegisteredGatewayHook(): Unit {
        gatewayRegisterSubagentNoticeDeliveryHook({ channelName, accountId, peerId, notice, replyToMessageId, replyInThread =>
            "${channelName}|${accountId}|${peerId}|${replyToMessageId}|${replyInThread}|${notice}"
        })
        try {
            let messageId = gatewaySubagentDeliverNoticeToChannel(
                "telegram",
                "telegram:bot",
                "group:-100123:topic:42",
                "[Subagent succeeded] reviewer run-1",
                replyToMessageId: "88",
                replyInThread: true
            )
            @Expect(messageId, "telegram|telegram:bot|group:-100123:topic:42|88|true|[Subagent succeeded] reviewer run-1")
        } finally {
            gatewayClearSubagentNoticeDeliveryHook()
        }
    }

    @TestCase
    public func noticeEventHookPublishesThroughRegisteredGatewayHook(): Unit {
        gatewayRegisterSubagentNoticeEventHook({ sessionKey, runId, status, notice =>
            if (sessionKey == "main" && runId == "run-1" && status == "succeeded" && notice.contains("[Subagent succeeded]")) {
                1
            } else {
                0
            }
        })
        try {
            @Expect(gatewaySubagentPublishNoticeEvent("main", "run-1", "succeeded", "[Subagent succeeded] reviewer run-1"), 1)
        } finally {
            gatewayClearSubagentNoticeEventHook()
        }
        @Expect(gatewaySubagentPublishNoticeEvent("main", "run-1", "succeeded", "[Subagent succeeded] reviewer run-1"), 0)
    }
}
