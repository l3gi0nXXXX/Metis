package metis.core

import std.unittest.testmacro.*

@Test
public class SubagentCommandTest {
    @TestCase
    public func parsesSpawnWithQuotedTask(): Unit {
        let req = parseGatewaySubagentCommandLine("/subagents spawn reviewer \"review current diff\"")
        @Expect(req.recognized, true)
        @Expect(req.ok, true)
        @Expect(req.action, "spawn")
        @Expect(req.agentId, "reviewer")
        @Expect(req.message, "review current diff")
    }

    @TestCase
    public func parsesSpawnWithUnicodeTask(): Unit {
        let req = parseGatewaySubagentCommandLine("/subagents spawn explorer \"检查当前实现\"")
        @Expect(req.recognized, true)
        @Expect(req.ok, true)
        @Expect(req.agentId, "explorer")
        @Expect(req.message, "检查当前实现")
    }

    @TestCase
    public func parsesControlActionsAndDefaultsListToCurrent(): Unit {
        let list = parseGatewaySubagentCommandLine("/subagents")
        @Expect(list.ok, true)
        @Expect(list.action, "list")
        @Expect(list.target, "current")

        let logs = parseGatewaySubagentCommandLine("/subagents logs subrun_123")
        @Expect(logs.ok, true)
        @Expect(logs.action, "logs")
        @Expect(logs.target, "subrun_123")

        let send = parseGatewaySubagentCommandLine("/subagents send subrun_123 \"continue with tests\"")
        @Expect(send.ok, true)
        @Expect(send.action, "send")
        @Expect(send.target, "subrun_123")
        @Expect(send.message, "continue with tests")
    }

    @TestCase
    public func invalidCommandReportsUsageReadyError(): Unit {
        let req = parseGatewaySubagentCommandLine("/subagents steer subrun_123")
        @Expect(req.recognized, true)
        @Expect(req.ok, false)
        @Expect(req.error.contains("requires"), true)
        @Expect(gatewaySubagentCommandUsage().contains("/subagents spawn"), true)
    }
}
