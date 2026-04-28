package metis.core

import std.fs.{Directory, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonBool, JsonObject}

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

    @TestCase
    public func effectiveStateSeparatesPersistedStatusFromLiveRuntime(): Unit {
        let sessionsRoot = this.tempSessionsRoot("effective")
        Directory.create(sessionsRoot, recursive: true)
        let running = gatewaySubagentCreateRunRecord(sessionsRoot, "child-running", status: "running")
        let queued = gatewaySubagentCreateRunRecord(sessionsRoot, "child-queued", status: "queued")
        let done = gatewaySubagentCreateRunRecord(sessionsRoot, "child-done", status: "succeeded")

        let stale = gatewaySubagentResolveEffectiveState(running)
        @Expect(stale.persistedStatus, "running")
        @Expect(stale.processState, "idle")
        @Expect(stale.effectiveState, "stale")
        @Expect(stale.isStale, true)
        @Expect(stale.isActive, false)

        let liveRunning = gatewaySubagentResolveEffectiveState(running, hasLiveFuture: true)
        @Expect(liveRunning.effectiveState, "running")
        @Expect(liveRunning.isLive, true)
        @Expect(liveRunning.isActive, true)

        let liveQueued = gatewaySubagentResolveEffectiveState(queued, hasLiveProcess: true)
        @Expect(liveQueued.effectiveState, "queued")
        @Expect(liveQueued.isActive, true)

        let terminal = gatewaySubagentResolveEffectiveState(done)
        @Expect(terminal.effectiveState, "succeeded")
        @Expect(terminal.isTerminal, true)
        @Expect(terminal.shouldNotify, true)
    }

    @TestCase
    public func effectiveStateDetectsRecordedOnlyCustomAgentRuns(): Unit {
        let sessionsRoot = this.tempSessionsRoot("recorded")
        Directory.create(sessionsRoot, recursive: true)
        let record = gatewaySubagentCreateRunRecord(sessionsRoot, "child-recorded", status: "queued")
        let metadata = JsonObject()
        let agent = JsonObject()
        agent.put("background", JsonBool(false))
        metadata.put("agent", agent)
        record.put("metadata", metadata)

        let state = gatewaySubagentResolveEffectiveState(record)
        @Expect(state.launchState, "not_started_by_design")
        @Expect(state.effectiveState, "recorded")
        @Expect(state.isRecordedOnly, true)
        @Expect(state.isStale, false)
        @Expect(state.isActive, false)
        @Expect(state.canSteer, false)
    }
}
