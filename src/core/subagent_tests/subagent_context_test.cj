package metis.core.subagent_tests

import metis.core.*

import std.unittest.testmacro.*

@Test
public class SubagentContextTest {
    @TestCase
    public func contextModeAliasesNormalizeToStableValues(): Unit {
        @Expect(gatewaySubagentNormalizeContextMode("fresh"), "fresh")
        @Expect(gatewaySubagentNormalizeContextMode("with-context"), "with_context")
        @Expect(gatewaySubagentNormalizeContextMode("full"), "fork")
        @Expect(gatewaySubagentNormalizeContextMode("same_thread"), "thread")
        @Expect(gatewaySubagentNormalizeContextMode("unknown"), "fresh")
    }

    @TestCase
    public func freshPromptDoesNotIncludeParentHistory(): Unit {
        let prompt = gatewaySubagentBuildContextPrompt(
            "Base task prompt",
            "fresh",
            "parent-session",
            "child-session",
            "[user] secret parent context"
        )
        @Expect(prompt, "Base task prompt")
        @Expect(prompt.contains("secret parent context"), false)
    }

    @TestCase
    public func withContextPromptIncludesRecentParentConversation(): Unit {
        let prompt = gatewaySubagentBuildContextPrompt(
            "Base task prompt",
            "with_context",
            "parent-session",
            "child-session",
            "[user] gateway restart failed\n\n[assistant] inspect logs"
        )
        @Expect(prompt.contains("Context mode: with_context"), true)
        @Expect(prompt.contains("Parent session key: parent-session"), true)
        @Expect(prompt.contains("[user] gateway restart failed"), true)
    }

    @TestCase
    public func forkAndThreadPromptsCarryModeSpecificSemantics(): Unit {
        let forkPrompt = gatewaySubagentBuildContextPrompt("Base", "fork", "parent", "child", "[user] full history")
        @Expect(forkPrompt.contains("Context mode: fork"), true)
        @Expect(forkPrompt.contains("fork of the available parent conversation"), true)

        let threadPrompt = gatewaySubagentBuildContextPrompt("Base", "thread", "telegram:topic:42", "child", "[user] topic history")
        @Expect(threadPrompt.contains("Context mode: thread"), true)
        @Expect(threadPrompt.contains("same requester thread/session"), true)
        @Expect(threadPrompt.contains("telegram:topic:42"), true)
    }
}
