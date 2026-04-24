package metis.program

import std.unittest.testmacro.*

private func findCommandDescription(command: String): String {
    for ((name, description, _, _, _) in cliRootCommandDescriptors()) {
        if (name == command) {
            return description
        }
    }
    ""
}

private func findExampleDescription(command: String, examplePrefix: String): String {
    for ((example, description) in cliRootCommandExamples(command)) {
        if (example == examplePrefix) {
            return description
        }
    }
    ""
}

@Test
public class ProgramCommandTreeTest {
    @TestCase
    public func interactiveCommandsDescribeGatewayDefaultPath(): Unit {
        @Expect(
            findCommandDescription("interactive"),
            "Start the interactive shell that routes turns through the unified Gateway main runtime"
        )
        @Expect(
            findCommandDescription("chat"),
            "Alias for interactive shell"
        )
        @Expect(
            findCommandDescription("mcp"),
            "Manage MCP servers and expose the unified Gateway main runtime over MCP stdio"
        )
    }

    @TestCase
    public func agentExamplesDescribeGatewayDefaultAndLocalFallback(): Unit {
        @Expect(
            findExampleDescription("agent", "metis agent --message \"Summarize this repo\""),
            "Run one formal agent turn via the unified Gateway main runtime."
        )
        @Expect(
            findExampleDescription("agent", "metis agents list"),
            "List managed agents through the unified Gateway main runtime."
        )
        @Expect(
            findExampleDescription("agent", "metis agent --local --message \"Summarize this repo\""),
            "Run one explicit embedded-only debug turn."
        )
        @Expect(
            findExampleDescription("mcp", "metis mcp serve --url ws://127.0.0.1:18788/ws"),
            "Expose the unified Gateway main runtime as an MCP stdio bridge."
        )
    }
}
