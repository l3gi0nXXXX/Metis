package metis.gateway.openclaw_memory

import std.unittest.testmacro.*

@Test
public class OpenClawMemoryRuntimeTest {
    @TestCase
    public func memoryMockSeparatesProjectAndSessionScopedFacts(): Unit {
        let runtime = OpenClawMemoryRuntime()
        runtime.write("project", "metis", "compatibility", "gap08")
        runtime.write("session", "thread-3", "compatibility", "gap09")

        @Expect(runtime.read("project", "metis", "compatibility").getOrThrow(), "gap08")
        @Expect(runtime.read("session", "thread-3", "compatibility").getOrThrow(), "gap09")
        @Expect(runtime.read("session", "other", "compatibility").isNone(), true)
    }

    @TestCase
    public func memoryRuntimeExposesMetisContextBackendContractAndPluginMocks(): Unit {
        let runtime = OpenClawMemoryRuntime()
        let core = runtime.registerBackend("memory-core", "local", searchEnabled: true, indexPath: "/tmp/memory-core")
        let lancedb = runtime.registerBackend("memory-lancedb", "lancedb", searchEnabled: true, indexPath: "/tmp/lancedb")
        runtime.write("project", "metis", "provider", "memory-core stores durable context")
        runtime.write("project", "metis", "vector", "memory-lancedb stores vector context")

        let coreHits = runtime.search("durable", limit: 4, backendId: "memory-core")
        let vectorHits = runtime.search("vector", limit: 4, backendId: "memory-lancedb")
        let metis = runtime.metisBackendSnapshot(agentId: "general", purpose: "openclaw-gap09")

        @Expect(core.contract, "metis.memory-context-backend.v1")
        @Expect(core.providerId, "memory-core")
        @Expect(lancedb.backend, "lancedb")
        @Expect(coreHits[0].backendId, "memory-core")
        @Expect(coreHits[0].text.contains("durable context"), true)
        @Expect(vectorHits[0].backendId, "memory-lancedb")
        @Expect(metis.contract, "metis.memory-context-backend.v1")
        @Expect(metis.purpose, "openclaw-gap09")
    }
}
