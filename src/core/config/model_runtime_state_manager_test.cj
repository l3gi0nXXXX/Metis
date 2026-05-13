package metis.core.config

import std.fs.{Directory, File, Path}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString, JsonValue}

private func runtimeStateTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

private func runtimeStateTestBool(obj: JsonObject, key: String): Bool {
    match (obj.get(key)) {
        case Some(value) =>
            try { value.asBool().getValue() } catch (_: Exception) { false }
        case None => false
    }
}

private func runtimeStateTestRead(path: Path): JsonObject {
    JsonValue.fromStr(String.fromUtf8(File.readFrom(path))).asObject()
}

private func runtimeStateTestRoot(agentId: String, modelRef: String): JsonObject {
    let root = JsonObject()
    let agents = JsonObject()
    let list = JsonArray([])
    let entry = JsonObject()
    entry.put("id", JsonString(agentId))
    let model = JsonObject()
    model.put("primary", JsonString(modelRef))
    entry.put("model", model)
    list.add(entry)
    agents.put("list", list)
    root.put("agents", agents)
    root
}

@Test
public class CliModelRuntimeStateManagerTest {
    @TestCase
    public func refreshAgentRuntimeStateUpdatesGeneratedModelsJsonForChangedScope(): Unit {
        withMetisConfigTestHome("agent-runtime-refresh-generated", { home: Path =>
            let agentDir = home.join("agents").join("writer").join("agent")
            let workspace = home.join("workspace")
            let initialScope = MetisAgentScope.resolve(runtimeStateTestRoot("writer", "openai:gpt-4o-mini"), agentId: "writer", homeRoot: home, defaultWorkspace: workspace)
            let path = CliModelRuntimeStateManager.ensureAgentRuntimeStateForScope(agentDir, initialScope)
            let initial = runtimeStateTestRead(path)

            @Expect(runtimeStateTestString(initial, "runtimePrimaryModelRef"), "openai:gpt-4o-mini")
            @Expect(runtimeStateTestBool(initial, "generated"), true)
            @Expect(runtimeStateTestString(initial, "materializedSource"), "agent-scope")

            let updatedScope = MetisAgentScope.resolve(runtimeStateTestRoot("writer", "anthropic:claude-3-5-sonnet"), agentId: "writer", homeRoot: home, defaultWorkspace: workspace)
            let refresh = CliModelRuntimeStateManager.refreshAgentRuntimeStateForScope(agentDir, updatedScope)
            let updated = runtimeStateTestRead(path)

            @Expect(refresh.status, "refreshed")
            @Expect(refresh.refreshed, true)
            @Expect(runtimeStateTestString(updated, "runtimePrimaryModelRef"), "anthropic:claude-3-5-sonnet")
            @Expect(runtimeStateTestString(updated, "scopeFingerprint").contains("writer"), true)
        })
    }

    @TestCase
    public func refreshAgentRuntimeStatePreservesManualModelsJson(): Unit {
        withMetisConfigTestHome("agent-runtime-refresh-manual", { home: Path =>
            let agentDir = home.join("agents").join("writer").join("agent")
            let path = CliModelRuntimeStateManager.agentRuntimePath(agentDir)
            Directory.create(agentDir, recursive: true)
            File.writeTo(path, "{\"primaryModelRef\":\"manual:model\",\"runtimePrimaryModelRef\":\"manual:model\",\"providers\":[]}".toArray())

            let scope = MetisAgentScope.resolve(runtimeStateTestRoot("writer", "qwen:qwen-plus"), agentId: "writer", homeRoot: home, defaultWorkspace: home.join("workspace"))
            let refresh = CliModelRuntimeStateManager.refreshAgentRuntimeStateForScope(agentDir, scope)
            let preserved = runtimeStateTestRead(path)

            @Expect(refresh.status, "skipped")
            @Expect(refresh.reason, "manual-runtime-state")
            @Expect(refresh.refreshed, false)
            @Expect(runtimeStateTestString(preserved, "runtimePrimaryModelRef"), "manual:model")
            @Expect(preserved.toJsonString().contains("qwen-plus"), false)
        })
    }
}
