package metis.gateway.tools

import metis.core.{GatewayToolRuntimeContext, gatewaySubagentCreateRunRecord, gatewaySubagentResolveRunRecord, gatewaySubagentRunRecordString, gatewayWithToolRuntimeContext}
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}
import metis.core.memory.memorySessionStoreForGatewayUser

import std.env.{getVariable, setVariable}
import std.fs.{Directory, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonValue}

private func withManagedSessionsToolsetTestHome<T>(home: String, block: () -> T): T {
    let actualHome = "${home}-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
    try {
        remove(Path(actualHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(actualHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", actualHome)
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
    try {
        return block()
    } finally {
        match (oldHome) {
            case Some(value) => setVariable("METIS_HOME", value)
            case None => setVariable("METIS_HOME", "")
        }
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try {
            remove(Path(actualHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
    }
}

private func managedSubagentsJson(raw: String): JsonObject {
    JsonValue.fromStr(raw).asObject()
}

private func managedSubagentsSome(v: String): Option<String> {
    Some<String>(v)
}

private func managedSubagentsString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewayManagedSessionsToolsetTest {
    @TestCase
    public func subagentsListStatusAndLogsReturnRunStoreData(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-list-status-logs") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let sessionKey = "child-session-a"
            store.appendTranscriptEntry(sessionKey, "assistant", "analysis ready")
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                sessionKey,
                parentSessionKey: "cli:main",
                requesterSessionKey: "cli:main",
                agentId: "explorer",
                runtime: "subagent",
                status: "running",
                transcriptPath: store.transcriptPath(sessionKey).toString()
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:main")) {
                let listed = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("list"), managedSubagentsSome("agent:explorer"), None<String>, None<Int64>))
                @Expect(managedSubagentsString(listed, "action"), "list")
                @Expect(managedSubagentsString(listed, "filter"), "agent:explorer")
                @Expect(listed.get("sessions").getOrThrow().asArray().size(), 1)
                @Expect(managedSubagentsString(listed.get("sessions").getOrThrow().asArray()[0].asObject(), "runId"), runId)

                let status = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(status, "action"), "status")
                @Expect(managedSubagentsString(status, "runId"), runId)
                @Expect(status.get("run").getOrThrow().asObject().get("runId").getOrThrow().asString().getValue(), runId)

                let logs = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("logs"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(logs, "action"), "logs")
                @Expect(managedSubagentsString(logs, "logs").contains("analysis ready"), true)
                @Expect(managedSubagentsString(logs, "transcriptPath").isEmpty(), false)
            }
        }
    }

    @TestCase
    public func subagentsKillCancelsStaleNonTerminalRunWithoutDeletingTranscript(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-kill-running") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let sessionKey = "child-session-kill"
            store.appendTranscriptEntry(sessionKey, "assistant", "work in progress")
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                sessionKey,
                requesterSessionKey: "cli:main",
                agentId: "reviewer",
                status: "running",
                transcriptPath: store.transcriptPath(sessionKey).toString()
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:main")) {
                let killed = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("kill"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(killed, "status"), "cancelled")
                @Expect(killed.get("deleted").getOrThrow().asBool().getValue(), false)
                @Expect(exists(store.transcriptPath(sessionKey)), true)
                match (gatewaySubagentResolveRunRecord(store.sessionsRoot(), runId)) {
                    case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "status"), "cancelled")
                    case None => @Expect("missing", "record")
                }
            }
        }
    }

    @TestCase
    public func subagentsKillCompletedRunIsIdempotent(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-kill-completed") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let sessionKey = "child-session-completed"
            store.appendTranscriptEntry(sessionKey, "assistant", "done")
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                sessionKey,
                requesterSessionKey: "cli:main",
                agentId: "planner",
                status: "succeeded",
                transcriptPath: store.transcriptPath(sessionKey).toString()
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("cli", sessionKey: "cli:main")) {
                let killed = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("kill"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(killed, "status"), "noop")
                @Expect(killed.get("deleted").getOrThrow().asBool().getValue(), false)
                match (gatewaySubagentResolveRunRecord(store.sessionsRoot(), runId)) {
                    case Some(found) => @Expect(gatewaySubagentRunRecordString(found, "status"), "succeeded")
                    case None => @Expect("missing", "record")
                }
            }
        }
    }

    @TestCase
    public func subagentsStatusDeniesDifferentRequesterSessionOnChannelSurface(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-toolset-scope-deny") {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                "child-session-owned",
                requesterSessionKey: "telegram:chat:owner",
                agentId: "explorer",
                status: "running"
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")
            let toolset = GatewayManagedSessionsToolset()

            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("telegram", sessionKey: "telegram:chat:other")) {
                let denied = managedSubagentsJson(toolset.subagentsForTest(managedSubagentsSome("status"), managedSubagentsSome(runId), None<String>, None<Int64>))
                @Expect(managedSubagentsString(denied, "status"), "denied")
                @Expect(managedSubagentsString(denied, "action"), "status")
            }
        }
    }

    @TestCase
    public func subagentsCommandSpawnRecordsRunAndStatusInRequesterSession(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-command-spawn-record") {
            gatewayWithToolRuntimeContext(GatewayToolRuntimeContext("telegram", sessionKey: "telegram:chat:phase7")) {
                let spawned = managedSubagentsJson(gatewayHandleSubagentsCommandLine("/subagents spawn observer \"inspect unicode 任务\"").getOrThrow())
                @Expect(managedSubagentsString(spawned, "status"), "accepted")
                @Expect(managedSubagentsString(spawned, "agentId"), "observer")
                @Expect(managedSubagentsString(spawned, "task"), "inspect unicode 任务")
                @Expect(spawned.get("liveRunStarted").getOrThrow().asBool().getValue(), false)

                let runId = managedSubagentsString(spawned, "runId")
                let status = managedSubagentsJson(gatewayHandleSubagentsCommandLine("/subagents status ${runId}").getOrThrow())
                @Expect(managedSubagentsString(status, "status"), "ok")
                @Expect(managedSubagentsString(status, "runId"), runId)
                let run = status.get("run").getOrThrow().asObject()
                @Expect(managedSubagentsString(run, "status"), "queued")
                @Expect(managedSubagentsString(run, "requesterSessionKey"), "telegram:chat:phase7")
                @Expect(managedSubagentsString(run, "requesterChannel"), "telegram")
            }
        }
    }

    @TestCase
    public func subagentsCommandErrorsUseStructuredJson(): Unit {
        withManagedSessionsToolsetTestHome("/tmp/metis-managed-subagents-command-error") {
            let failed = managedSubagentsJson(gatewayHandleSubagentsCommandLine("/subagents steer subrun_123").getOrThrow())
            @Expect(failed.get("ok").getOrThrow().asBool().getValue(), false)
            @Expect(managedSubagentsString(failed, "status"), "error")
            @Expect(managedSubagentsString(failed, "action"), "steer")
            @Expect(managedSubagentsString(failed, "usage").contains("/subagents spawn"), true)
        }
    }
}
