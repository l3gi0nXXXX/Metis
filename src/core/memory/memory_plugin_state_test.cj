package metis.core.memory

import std.fs.Path
import std.collection.HashSet
import std.unittest.testmacro.*

private class TestMemoryProvider <: MemoryProvider {
    public func providerId(): String { "runtime-provider" }
    public func backendId(): String { "runtime-backend" }
    public func manualReindexSupported(): Bool { true }
    public func searchEnabled(): Bool { true }
    public func indexPath(): String { "/tmp/runtime-provider.json" }
    public func resolveMemoryFiles(): Array<Path> { Array<Path>() }
    public func searchRows(query: String, limit: Int64): Array<LocalMemorySearchRow> {
        let _ = query
        let _ = limit
        Array<LocalMemorySearchRow>()
    }
    public func searchRows(query: String, limit: Int64, sessionKey!: Option<String>): Array<LocalMemorySearchRow> {
        let _ = sessionKey
        searchRows(query, limit)
    }
    public func recordShortTermRecall(query: String, rows: Array<LocalMemoryRecallResult>): Unit {
        let _ = query
        let _ = rows
    }
    public func statusJson(deep!: Bool): String {
        let _ = deep
        "{\"status\":\"runtime-manager\"}"
    }
    public func statusText(deep!: Bool): String {
        let _ = deep
        "Memory status: runtime-manager"
    }
    public func fixArtifacts(): String { "runtime-fix" }
    public func writeIndexSnapshot(): String { "runtime-index" }
    public func forceReindex(): String { "runtime-reindex" }
}

private class TestMemoryPluginRuntime <: MemoryPluginRuntime {
    public var closeCalls: Int64 = 0

    public func getMemorySearchManager(agentId: String, purpose: String): MemorySearchManagerResult {
        if (purpose == "status" || purpose == "fix-artifacts" || purpose == "write-index-snapshot" || purpose == "force-reindex") {
            let manager = MemorySearchManager(
                TestMemoryProvider(),
                MemoryBackendConfig(
                    "runtime-${agentId}",
                    "runtime-backend",
                    true,
                    true,
                    "/tmp/runtime-${agentId}.json"
                )
            )
            return MemorySearchManagerResult(manager: Some(manager))
        }
        MemorySearchManagerResult(error: "runtime:${agentId}:${purpose}")
    }

    public func resolveMemoryBackendConfig(agentId: String): Option<MemoryBackendConfig> {
        Some(
            MemoryBackendConfig(
                "runtime-${agentId}",
                "runtime-backend",
                true,
                false,
                "/tmp/runtime-${agentId}.json"
            )
        )
    }

    public func closeAllMemorySearchManagers(): Unit {
        closeCalls++
    }
}

@Test
public class MemoryPluginStateTest {
    @TestCase
    public func initializeBuiltinMemoryPluginStateRegistersAllBuiltinBridges(): Unit {
        clearMemoryPluginState()
        @Expect(getMemoryPromptSectionBuilder().isSome(), false)
        @Expect(getMemoryFlushPlanResolver().isSome(), false)
        @Expect(getMemoryRuntime().isSome(), false)

        initializeBuiltinMemoryPluginState()

        @Expect(getMemoryPromptSectionBuilder().isSome(), true)
        @Expect(getMemoryFlushPlanResolver().isSome(), true)
        @Expect(hasMemoryRuntime(), true)
        @Expect(getMemoryRuntime().isSome(), true)
        let lines = buildMemoryPromptSection(HashSet<String>(), citationsMode: "inline")
        @Expect(lines.size, 0)
        let flushPlan = resolveMemoryFlushPlan(nowMs: 123)
        @Expect(flushPlan.isSome(), false)
    }

    @TestCase
    public func clearAndRestoreMemoryPluginStateRoundTripsRegistrationState(): Unit {
        initializeBuiltinMemoryPluginState()
        let previousPrompt = getMemoryPromptSectionBuilder()
        let previousFlush = getMemoryFlushPlanResolver()
        let previousRuntime = getMemoryRuntime()
        try {
            clearMemoryPluginState()
            @Expect(getMemoryPromptSectionBuilder().isSome(), false)
            @Expect(getMemoryFlushPlanResolver().isSome(), false)
            @Expect(hasMemoryRuntime(), false)

            restoreMemoryPluginState(
                promptBuilder: previousPrompt,
                flushPlanResolver: previousFlush,
                runtime: previousRuntime
            )
            @Expect(getMemoryPromptSectionBuilder().isSome(), true)
            @Expect(getMemoryFlushPlanResolver().isSome(), true)
            @Expect(hasMemoryRuntime(), true)
        } finally {
            restoreMemoryPluginState(
                promptBuilder: previousPrompt,
                flushPlanResolver: previousFlush,
                runtime: previousRuntime
            )
        }
    }

    /*
    @TestCase
    public func memoryRuntimePrefersRegisteredPluginRuntime(): Unit {
        initializeBuiltinMemoryPluginState()
        let previousPrompt = getMemoryPromptSectionBuilder()
        let previousFlush = getMemoryFlushPlanResolver()
        let previousRuntime = getMemoryRuntime()
        let runtime = TestMemoryPluginRuntime()
        try {
            registerMemoryRuntime(runtime)

            let cfg = MemoryRuntime.resolveMemoryBackendConfig(agentId: "reviewer", purpose: "status")
            @Expect(cfg.providerId, "runtime-reviewer")
            @Expect(cfg.backend, "runtime-backend")
            @Expect(cfg.indexPath, "/tmp/runtime-reviewer.json")

            let manager = MemoryRuntime.getMemorySearchManager(agentId: "reviewer", purpose: "status")
            @Expect(manager.manager.isSome(), false)
            @Expect(manager.error, "runtime:reviewer:status")

            MemoryRuntime.closeAllMemorySearchManagers()
            @Expect(runtime.closeCalls, 1)
        } finally {
            restoreMemoryPluginState(
                promptBuilder: previousPrompt,
                flushPlanResolver: previousFlush,
                runtime: previousRuntime
            )
        }
    }
    */

    @TestCase
    public func memoryStatePrefersRegisteredPluginRuntimeManager(): Unit {
        initializeBuiltinMemoryPluginState()
        let previousPrompt = getMemoryPromptSectionBuilder()
        let previousFlush = getMemoryFlushPlanResolver()
        let previousRuntime = getMemoryRuntime()
        let runtime = TestMemoryPluginRuntime()
        try {
            registerMemoryRuntime(runtime)

            let statusJson = MemoryStateRegistry.statusJson(agentId: "reviewer", purpose: "status")
            @Expect(statusJson.contains("runtime-manager"), true)

            let statusText = MemoryStateRegistry.statusText(agentId: "reviewer", purpose: "status")
            @Expect(statusText.contains("runtime-manager"), true)

            @Expect(MemoryStateRegistry.fixArtifacts(agentId: "reviewer", purpose: "fix-artifacts"), "runtime-fix")
            @Expect(MemoryStateRegistry.writeIndexSnapshot(agentId: "reviewer", purpose: "write-index-snapshot"), "runtime-index")
            @Expect(MemoryStateRegistry.forceReindex(agentId: "reviewer", purpose: "force-reindex"), "runtime-reindex")
        } finally {
            restoreMemoryPluginState(
                promptBuilder: previousPrompt,
                flushPlanResolver: previousFlush,
                runtime: previousRuntime
            )
        }
    }
}
