package metis.core.tool_surface_tests

import metis.core.tools.*

import metis.core.{GatewayToolRuntimeContext, gatewayWithToolRuntimeContext}
import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager}

import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func withGatewaySessionsToolsetTestHome<T>(home: String, block: () -> T): T {
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

private func writeGatewaySessionsAgentToolDeny(agentId: String, deny: Array<String>): Unit {
    let root = JsonObject()
    let agents = JsonObject()
    agents.put("defaults", JsonObject())
    let entries = JsonArray([])
    let entry = JsonObject()
    entry.put("id", JsonString(agentId))
    let tools = JsonObject()
    let denied = JsonArray([])
    for (name in deny) {
        denied.add(JsonString(name))
    }
    tools.put("deny", denied)
    entry.put("tools", tools)
    entries.add(entry)
    agents.put("list", entries)
    root.put("agents", agents)
    let configDir = MetisConfigManager.configPath().parent
    if (!exists(configDir)) {
        Directory.create(configDir, recursive: true)
    }
    File.writeTo(MetisConfigManager.configPath(), root.toJsonString().toArray())
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
}

private func gatewaySessionsJson(raw: String): JsonObject {
    JsonValue.fromStr(raw).asObject()
}

private func gatewaySessionsString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) => try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class GatewaySessionsToolsetTest {
    @TestCase
    public func sessionsSpawnRejectsChildToolsBeyondParentAgentPolicy(): Unit {
        withGatewaySessionsToolsetTestHome("/tmp/metis-gateway-sessions-phase6-parent-boundary") {
            writeGatewaySessionsAgentToolDeny("agent-a", ["exec"])
            var settings = CliSettingManager.readGatewaySettings()
            settings.subagents.requireAgentId = true
            settings.subagents.allowAgents = ["reviewer"]
            settings.subagents.childAllowedTools = ["shellExecute"]
            let _ = MetisConfigManager.setGatewaySettings(settings)
            CliSettingManager.invalidate()

            let toolset = GatewaySessionsToolset()
            let out = gatewayWithToolRuntimeContext(
                GatewayToolRuntimeContext("cli", channelName: "cli", sessionKey: "agent:agent-a:main", agentId: "agent-a"),
                { => gatewaySessionsJson(toolset.sessionsSpawnForCommand(
                    "attempt denied child shell",
                    Some<String>("phase6-parent-boundary"),
                    Some<String>("subagent"),
                    Some<String>("reviewer"),
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<Int64>,
                    None<Int64>,
                    None<Bool>,
                    None<String>,
                    None<String>,
                    None<String>,
                    None<String>
                )) }
            )

            @Expect(gatewaySessionsString(out, "status"), "rejected")
            @Expect(gatewaySessionsString(out, "reason").contains("parent tool policy denied"), true)
        }
    }
}
