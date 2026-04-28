package metis.gateway.runtime

import metis.core.{gatewaySubagentCreateRunRecord, gatewaySubagentResolveRunRecord, gatewaySubagentRunRecordString}
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}
import metis.core.memory.memorySessionStoreForGatewayUser

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*

import stdx.encoding.json.{JsonObject, JsonString}

private func withGatewaySubagentsRpcTestHome<T>(block: () -> T): T {
    let testHome = "/tmp/metis-gateway-subagents-rpc-test-home-${DateTime.now().toUnixTimeStamp().toNanoseconds()}"
    try {
        remove(Path(testHome), recursive: true)
    } catch (_: Exception) {
        ()
    }
    Directory.create(testHome, recursive: true)
    let oldHome = getVariable("METIS_HOME")
    setVariable("METIS_HOME", testHome)
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
            remove(Path(testHome), recursive: true)
        } catch (_: Exception) {
            ()
        }
    }
}

private func subagentRpcParam(key: String, value: String): JsonObject {
    let params = JsonObject()
    params.put(key, JsonString(value))
    params
}

@Test
public class GatewayServerMethodsSubagentsTest {
    @TestCase
    public func subagentsRpcListStatusLogsAndKillUseRunStore(): Unit {
        withGatewaySubagentsRpcTestHome {
            let store = memorySessionStoreForGatewayUser(CliSettingManager.readGatewaySettings())
            let sessionKey = "phase14-subagent-session"
            store.appendTranscriptEntry(sessionKey, "assistant", "phase 14 log line")
            let record = gatewaySubagentCreateRunRecord(
                store.sessionsRoot(),
                sessionKey,
                parentSessionKey: "cli:phase14",
                requesterSessionKey: "cli:phase14",
                requesterChannel: "cli",
                agentId: "explorer",
                runtime: "subagent",
                task: "inspect ui",
                status: "queued",
                transcriptPath: store.transcriptPath(sessionKey).toString()
            )
            let runId = gatewaySubagentRunRecordString(record, "runId")

            let listed = gatewayDispatchLocalMethod(GatewayRpcRequest("subagents.list"))
            @Expect(listed.ok, true)
            @Expect(listed.result.asObject().get("sessions").getOrThrow().asArray().size(), 1)

            let status = gatewayDispatchLocalMethod(GatewayRpcRequest("subagents.status", params: subagentRpcParam("target", runId)))
            @Expect(status.ok, true)
            @Expect(status.result.asObject().get("runId").getOrThrow().asString().getValue(), runId)

            let logs = gatewayDispatchLocalMethod(GatewayRpcRequest("subagents.logs", params: subagentRpcParam("target", runId)))
            @Expect(logs.ok, true)
            @Expect(logs.result.asObject().get("logs").getOrThrow().asString().getValue().contains("phase 14 log line"), true)

            let killed = gatewayDispatchLocalMethod(GatewayRpcRequest("subagents.kill", params: subagentRpcParam("target", runId)))
            @Expect(killed.ok, true)
            @Expect(killed.result.asObject().get("status").getOrThrow().asString().getValue(), "cancelled")
            match (gatewaySubagentResolveRunRecord(store.sessionsRoot(), runId)) {
                case Some(updated) => @Expect(gatewaySubagentRunRecordString(updated, "status"), "cancelled")
                case None => @Expect(false, true)
            }
        }
    }

    @TestCase
    public func subagentsUserDocExistsAndCoversUiAndTriggers(): Unit {
        let path = Path("docs/user/subagents.md")
        @Expect(exists(path), true)
        let text = String.fromUtf8(File.readFrom(path))
        @Expect(text.contains("/subagents spawn"), true)
        @Expect(text.contains("Telegram"), true)
        @Expect(text.contains("Natural Language"), true)
        @Expect(text.contains("Control UI"), true)
        @Expect(text.contains("/api/subagents/kill"), true)
    }
}
