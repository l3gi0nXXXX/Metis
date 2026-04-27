package metis.core

import std.unittest.testmacro.*

@Test
public class SubagentBuiltinTest {
    @TestCase
    public func builtinResolverNormalizesSupportedAgentAliases(): Unit {
        @Expect(gatewaySubagentNormalizeBuiltinAgentId(""), "explorer")
        @Expect(gatewaySubagentNormalizeBuiltinAgentId("explorer-agent"), "explorer")
        @Expect(gatewaySubagentNormalizeBuiltinAgentId("review"), "reviewer")
        @Expect(gatewaySubagentNormalizeBuiltinAgentId("test-generator"), "test_generator")
        @Expect(gatewaySubagentNormalizeBuiltinAgentId("refactor"), "refactoring")
        @Expect(gatewaySubagentNormalizeBuiltinAgentId("plannerAgent"), "planner")
    }

    @TestCase
    public func builtinResolverIdentifiesAllPhaseFourAgents(): Unit {
        @Expect(gatewaySubagentIsBuiltinAgent("explorer"), true)
        @Expect(gatewaySubagentIsBuiltinAgent("reviewer"), true)
        @Expect(gatewaySubagentIsBuiltinAgent("test_generator"), true)
        @Expect(gatewaySubagentIsBuiltinAgent("planner"), true)
        @Expect(gatewaySubagentIsBuiltinAgent("editor"), true)
        @Expect(gatewaySubagentIsBuiltinAgent("refactoring"), true)
        @Expect(gatewaySubagentIsBuiltinAgent("unknown-agent"), false)
    }

    @TestCase
    public func builtinWriteCapabilitySeparatesReadonlyAndWriteAgents(): Unit {
        @Expect(gatewaySubagentBuiltinAgentIsWriteCapable("explorer"), false)
        @Expect(gatewaySubagentBuiltinAgentIsWriteCapable("reviewer"), false)
        @Expect(gatewaySubagentBuiltinAgentIsWriteCapable("planner"), false)
        @Expect(gatewaySubagentBuiltinAgentIsWriteCapable("editor"), true)
        @Expect(gatewaySubagentBuiltinAgentIsWriteCapable("test-generator"), true)
        @Expect(gatewaySubagentBuiltinAgentIsWriteCapable("refactoring"), true)
    }

    @TestCase
    public func builtinPromptCarriesRoleProjectSessionAndTask(): Unit {
        let prompt = gatewaySubagentBuildBuiltinPrompt(
            "inspect the diff",
            "/tmp/project",
            "agent:general:child",
            "reviewer"
        )

        @Expect(prompt.contains("Subagent role: reviewer"), true)
        @Expect(prompt.contains("Project path: /tmp/project"), true)
        @Expect(prompt.contains("Session key: agent:general:child"), true)
        @Expect(prompt.contains("inspect the diff"), true)
    }
}
