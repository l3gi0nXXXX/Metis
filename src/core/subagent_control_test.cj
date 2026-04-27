package metis.core

import std.unittest.testmacro.*
import stdx.encoding.json.{JsonObject, JsonString}

@Test
public class SubagentControlTest {
    private func record(sessionKey: String, requesterSessionKey: String, parentSessionKey: String, agentId: String): JsonObject {
        let r = JsonObject()
        r.put("sessionKey", JsonString(sessionKey))
        r.put("requesterSessionKey", JsonString(requesterSessionKey))
        r.put("parentSessionKey", JsonString(parentSessionKey))
        r.put("agentId", JsonString(agentId))
        r
    }

    @TestCase
    public func controllerAccessAllowsRequesterParentChildAndPrivileged(): Unit {
        let r = this.record("child-session", "telegram:chat:1", "parent-session", "reviewer")

        @Expect(gatewaySubagentControllerCanAccessRun(r, "telegram:chat:1", false), true)
        @Expect(gatewaySubagentControllerCanAccessRun(r, "parent-session", false), true)
        @Expect(gatewaySubagentControllerCanAccessRun(r, "child-session", false), true)
        @Expect(gatewaySubagentControllerCanAccessRun(r, "other-session", false), false)
        @Expect(gatewaySubagentControllerCanAccessRun(r, "other-session", true), true)
    }

    @TestCase
    public func listFilterSupportsCurrentAllAndAgentIdWithScope(): Unit {
        let r = this.record("child-session", "cli:main", "parent-session", "explorer")

        @Expect(gatewaySubagentRunMatchesControlFilter(r, "current", "cli:main", false), true)
        @Expect(gatewaySubagentRunMatchesControlFilter(r, "all", "other-session", false), false)
        @Expect(gatewaySubagentRunMatchesControlFilter(r, "all", "other-session", true), true)
        @Expect(gatewaySubagentRunMatchesControlFilter(r, "agent:explorer", "cli:main", false), true)
        @Expect(gatewaySubagentRunMatchesControlFilter(r, "explorer", "cli:main", false), true)
        @Expect(gatewaySubagentRunMatchesControlFilter(r, "agent:reviewer", "cli:main", false), false)
    }
}
