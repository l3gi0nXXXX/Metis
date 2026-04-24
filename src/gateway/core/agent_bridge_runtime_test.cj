package metis.gateway.core

import metis.core.config.CliSettingManager

import std.collection.ArrayList
import std.unittest.testmacro.*

@Test
public class AgentBridgeRuntimeTest {
    @TestCase
    public func gatewaySkillSelectionUserNoticeStaysSilentWhenNoSkillMatches(): Unit {
        @Expect(gatewaySkillSelectionUserNotice(true, None<String>), "")
        @Expect(gatewaySkillSelectionUserNotice(false, None<String>), "")
    }

    @TestCase
    public func gatewayDefaultChatRuntimeExposesUnifiedCoreTools(): Unit {
        @Expect(gatewayDefaultChatRuntimeHasUnifiedCoreTools(), true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesCronTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        var found = false
        for (name in names) {
            if (name == "cron") {
                found = true
                break
            }
        }
        @Expect(found, true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesProcessTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        var found = false
        for (name in names) {
            if (name == "process") {
                found = true
                break
            }
        }
        @Expect(found, true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesGatewayTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        var found = false
        for (name in names) {
            if (name == "gateway") {
                found = true
                break
            }
        }
        @Expect(found, true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesMessageTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        var found = false
        for (name in names) {
            if (name == "message") {
                found = true
                break
            }
        }
        @Expect(found, true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesSessionsSpawnTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        var found = false
        for (name in names) {
            if (name == "sessions_spawn") {
                found = true
                break
            }
        }
        @Expect(found, true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesSubagentsTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        var found = false
        for (name in names) {
            if (name == "subagents") {
                found = true
                break
            }
        }
        @Expect(found, true)
    }

    @TestCase
    public func gatewayAuthorizedChatToolNamesRespectToolsDenyPolicy(): Unit {
        let original = CliSettingManager.setting.gateway
        try {
            var updated = original
            updated.tools.allow = []
            updated.tools.deny = ["shellExecute", "process", "gateway", "message", "subagents"]
            CliSettingManager.setting.gateway = updated
            let names = gatewayAuthorizedChatToolNames()
            @Expect(names.contains("weather"), true)
            @Expect(names.contains("shellExecute"), false)
            @Expect(names.contains("process"), false)
            @Expect(names.contains("gateway"), false)
            @Expect(names.contains("message"), false)
            @Expect(names.contains("subagents"), false)
        } finally {
            CliSettingManager.setting.gateway = original
        }
    }

    @TestCase
    public func gatewayPolicyFilteredChatToolNamesActuallyFiltersLiveToolManager(): Unit {
        let original = CliSettingManager.setting.gateway
        try {
            var updated = original
            updated.tools.allow = []
            updated.tools.deny = ["shellExecute", "process", "gateway", "message", "subagents"]
            CliSettingManager.setting.gateway = updated
            let names = gatewayPolicyFilteredChatToolNames()
            @Expect(names.contains("weather"), true)
            @Expect(names.contains("shellExecute"), false)
            @Expect(names.contains("process"), false)
            @Expect(names.contains("gateway"), false)
            @Expect(names.contains("message"), false)
            @Expect(names.contains("subagents"), false)
            @Expect(names.contains("sessions_spawn"), true)
        } finally {
            CliSettingManager.setting.gateway = original
        }
    }

    @TestCase
    public func gatewayAuthorizedAndPolicyFilteredChatToolNamesStayAligned(): Unit {
        let original = CliSettingManager.setting.gateway
        try {
            var updated = original
            updated.tools.allow = []
            updated.tools.deny = ["shellExecute", "process", "gateway", "message", "subagents"]
            CliSettingManager.setting.gateway = updated
            let authorized = gatewayAuthorizedChatToolNames()
            let filtered = gatewayPolicyFilteredChatToolNames()
            @Expect(authorized.size, filtered.size)
            for (i in 0..authorized.size) {
                @Expect(authorized[i], filtered[i])
            }
        } finally {
            CliSettingManager.setting.gateway = original
        }
    }

    @TestCase
    public func gatewayPolicyFilteredSystemPromptDoesNotInjectDeniedTools(): Unit {
        let original = CliSettingManager.setting.gateway
        try {
            var updated = original
            updated.tools.allow = []
            updated.tools.deny = ["shellExecute", "process", "gateway", "message", "subagents"]
            CliSettingManager.setting.gateway = updated
            let prompt = gatewayPolicyFilteredSystemPrompt()
            @Expect(prompt.contains("shellExecute"), false)
            @Expect(prompt.contains("process(action=poll"), false)
            @Expect(prompt.contains("shellExecute/process"), false)
            @Expect(prompt.contains("## Metis Self-Update"), false)
            @Expect(prompt.contains("### message tool"), false)
            @Expect(prompt.contains("subagents"), false)
            @Expect(prompt.contains("weather"), true)
            @Expect(prompt.contains("sessions_spawn"), true)
        } finally {
            CliSettingManager.setting.gateway = original
        }
    }

    // @TestCase
    // public func gatewayProviderTimingSummaryIncludesCoreFields(): Unit {
    //     let line = gatewayProviderTimingSummary(
    //         "telegram",
    //         "dashscope:qwen3.6-plus",
    //         1,
    //         39077,
    //         105,
    //         7204,
    //         "success",
    //         localPreCallMs: 11
    //     )
    //     @Expect(line.contains("channel=telegram"), true)
    //     @Expect(line.contains("provider=dashscope"), true)
    //     @Expect(line.contains("model=dashscope:qwen3.6-plus"), true)
    //     @Expect(line.contains("attempt=1"), true)
    //     @Expect(line.contains("status=success"), true)
    //     @Expect(line.contains("promptChars=39077"), true)
    //     @Expect(line.contains("answerChars=105"), true)
    //     @Expect(line.contains("elapsedMs=7204"), true)
    //     @Expect(line.contains("localPreCallMs=11"), true)
    // }

    // @TestCase
    // public func gatewayProviderTimingSummarySanitizesFailureError(): Unit {
    //     let line = gatewayProviderTimingSummary(
    //         "cli",
    //         "dashscope:qwen3.6-plus",
    //         1,
    //         0,
    //         0,
    //         3000,
    //         "failed",
    //         error: "timeout\nprovider unavailable"
    //     )
    //     @Expect(line.contains("status=failed"), true)
    //     @Expect(line.contains("error=timeout provider unavailable"), true)
    // }

    // @TestCase
    // public func buildGatewayModelInputUsesCompactHistoryShape(): Unit {
    //     let history = ArrayList<String>()
    //     history.add("user: hello")
    //     history.add("assistant: hi")
    //     history.add("user: summarize this")
    //     let input = buildGatewayModelInput(
    //         history.toArray(),
    //         "reply with ok",
    //         "<available_skills>\n<skill name=\"weather\" enabled=\"true\" location=\"/tmp/weather\">forecast lookup</skill>\n</available_skills>"
    //     )
    //     @Expect(input.contains("<history>"), true)
    //     @Expect(input.contains("以下是最近对话历史"), false)
    //     @Expect(input.contains("用户当前问题"), false)
    //     @Expect(input.contains("user: reply with ok"), true)
    //     @Expect(input.contains("Use <skills> only to decide"), true)
    // }
}
