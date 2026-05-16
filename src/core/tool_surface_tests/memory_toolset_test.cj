package metis.core.tool_surface_tests

import metis.core.tools.*

import metis.core.config.CliConfig
import metis.core.memory.MemoryRuntimeRegistry

import std.fs.{Directory, File, remove, exists}
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonValue}

private func memoryToolsetTestString(obj: JsonObject, key: String): String {
    match (obj.get(key)) {
        case Some(v) =>
            try { v.asString().getValue() } catch (_: Exception) { "" }
        case None => ""
    }
}

@Test
public class MemoryToolsetTest {
    @TestCase
    public func cliSearchReturnsResolvedBackendConfigForAgentScopedSession(): Unit {
        MemoryRuntimeRegistry.activateBackend("local", startMaintenance: false)
        let memoryDir = CliConfig.cwd.join("memory")
        if (!exists(memoryDir)) {
            Directory.create(memoryDir, recursive: true)
        }
        let file = memoryDir.join("phase-c-memory-toolset-test.md")
        File.writeTo(
            file,
            "# Phase C\nremember phasecuniquetoken for runtime resolved backend config coverage\n".toArray()
        )
        try {
            let result = JsonValue.fromStr(
                MemoryToolset.runCliSearch(
                    "phasecuniquetoken",
                    maxResults: Some(3),
                    sessionKey: Some("agent:general:main")
                )
            ).asObject()
            @Expect(result.get("resolvedBackendConfig").isSome(), true)
            let resolved = result.get("resolvedBackendConfig").getOrThrow().asObject()
            @Expect(memoryToolsetTestString(resolved, "agentId"), "general")
            @Expect(memoryToolsetTestString(resolved, "purpose"), "tool-search")
            @Expect(memoryToolsetTestString(resolved, "configScope"), "global")
            @Expect(memoryToolsetTestString(resolved, "citations"), CliConfig.memoryCitations)
            @Expect(memoryToolsetTestString(result, "provider"), memoryToolsetTestString(resolved, "providerId"))
            @Expect(memoryToolsetTestString(result, "backend"), memoryToolsetTestString(resolved, "backend"))
            @Expect(memoryToolsetTestString(result, "mode").isEmpty(), false)
        } finally {
            if (exists(file)) {
                remove(file)
            }
        }
    }

    @TestCase
    public func cliSearchAllowsExplicitAgentIdWithoutSessionKey(): Unit {
        MemoryRuntimeRegistry.activateBackend("local", startMaintenance: false)
        let memoryDir = CliConfig.cwd.join("memory")
        if (!exists(memoryDir)) {
            Directory.create(memoryDir, recursive: true)
        }
        let file = memoryDir.join("phase-c-memory-toolset-agent-flag-test.md")
        File.writeTo(
            file,
            "# Phase C\nremember phasecagentflagtoken for explicit agent id coverage\n".toArray()
        )
        try {
            let result = JsonValue.fromStr(
                MemoryToolset.runCliSearch(
                    "phasecagentflagtoken",
                    maxResults: Some(3),
                    agentId: Some("general")
                )
            ).asObject()
            let resolved = result.get("resolvedBackendConfig").getOrThrow().asObject()
            @Expect(memoryToolsetTestString(resolved, "agentId"), "general")
            @Expect(memoryToolsetTestString(resolved, "purpose"), "tool-search")
        } finally {
            if (exists(file)) {
                remove(file)
            }
        }
    }

    @TestCase
    public func cliSearchCanRenderHumanTextWithoutRawJson(): Unit {
        MemoryRuntimeRegistry.activateBackend("local", startMaintenance: false)
        let memoryDir = CliConfig.cwd.join("memory")
        if (!exists(memoryDir)) {
            Directory.create(memoryDir, recursive: true)
        }
        let file = memoryDir.join("phase-c-memory-toolset-human-test.md")
        File.writeTo(
            file,
            "# Phase C\nremember phasechumanoutputtoken for human output coverage\n".toArray()
        )
        try {
            let out = MemoryToolset.runCliSearch(
                "phasechumanoutputtoken",
                maxResults: Some(3),
                agentId: Some("general"),
                json: false
            )
            @Expect(out.contains("Memory search"), true)
            @Expect(out.contains("Results:"), true)
            @Expect(out.contains("phasechumanoutputtoken"), true)
            @Expect(out.contains("\"results\""), false)
            @Expect(out.startsWith("{"), false)
        } finally {
            if (exists(file)) {
                remove(file)
            }
        }
    }
}
