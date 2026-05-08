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
}
