package metis.core.subagent_tests

import metis.core.*

import std.unittest.testmacro.*

@Test
public class SubagentIsolationTest {
    @TestCase
    public func isolationAliasesNormalizeToSupportedModes(): Unit {
        @Expect(gatewaySubagentNormalizeIsolationMode("shared"), "shared")
        @Expect(gatewaySubagentNormalizeIsolationMode("cwd"), "cwd")
        @Expect(gatewaySubagentNormalizeIsolationMode("directory"), "cwd")
        @Expect(gatewaySubagentNormalizeIsolationMode("git-worktree"), "worktree")
        @Expect(gatewaySubagentNormalizeIsolationMode("unknown"), "shared")
    }

    @TestCase
    public func cleanupAndSandboxNormalizeToPolicyValues(): Unit {
        @Expect(gatewaySubagentNormalizeCleanupMode("delete"), "delete")
        @Expect(gatewaySubagentNormalizeCleanupMode("remove"), "delete")
        @Expect(gatewaySubagentNormalizeCleanupMode("keep"), "keep")
        @Expect(gatewaySubagentNormalizeSandboxMode("require"), "require")
        @Expect(gatewaySubagentNormalizeSandboxMode("inherit"), "inherit")
    }
}
