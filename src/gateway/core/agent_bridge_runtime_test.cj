package metis.gateway.core

import metis.core.config.{CliConfig, CliSettingManager, MetisConfigManager, MetisProcessEnvironmentLock}
import metis.gateway.session.{GatewayIngressSource, GatewaySessionRequest, GatewayTurnContext, gatewayResolveSessionContext}

import std.collection.ArrayList
import std.env.{getVariable, setVariable}
import std.fs.{Directory, File, Path, exists, remove}
import std.time.DateTime
import std.unittest.testmacro.*
import stdx.encoding.json.{JsonArray, JsonObject, JsonString}

private func withAgentBridgeTempHome<T>(label: String, block: (Path) -> T): T {
    synchronized(MetisProcessEnvironmentLock) {
        let home = Path("/tmp/${label}-${DateTime.now().toUnixTimeStamp().toMilliseconds()}")
        try { remove(home, recursive: true) } catch (_: Exception) { () }
        Directory.create(home, recursive: true)
        let oldHome = getVariable("METIS_HOME")
        setVariable("METIS_HOME", home.toString())
        CliConfig.invalidatePathCache()
        MetisConfigManager.invalidate()
        CliSettingManager.invalidate()
        try {
            return block(home)
        } finally {
            match (oldHome) {
                case Some(value) => setVariable("METIS_HOME", value)
                case None => setVariable("METIS_HOME", "")
            }
            CliConfig.invalidatePathCache()
            MetisConfigManager.invalidate()
            CliSettingManager.invalidate()
            try { remove(home, recursive: true) } catch (_: Exception) { () }
        }
    }
}

private func agentBridgeAgentEntry(id: String, workspace: Path, agentDir: Path, modelRef: String): JsonObject {
    let entry = JsonObject()
    entry.put("id", JsonString(id))
    entry.put("workspace", JsonString(workspace.toString()))
    entry.put("agentDir", JsonString(agentDir.toString()))
    let model = JsonObject()
    model.put("primary", JsonString(modelRef))
    entry.put("model", model)
    entry
}

private func writeAgentBridgeAgentConfig(home: Path): Unit {
    let root = JsonObject()
    let agents = JsonObject()
    let defaults = JsonObject()
    defaults.put("workspace", JsonString(home.join("workspaces").toString()))
    agents.put("defaults", defaults)
    let list = JsonArray([])
    list.add(agentBridgeAgentEntry("writer", home.join("workspaces").join("writer"), home.join("agents").join("writer").join("agent"), "openai:gpt-4o-mini"))
    list.add(agentBridgeAgentEntry("ops", home.join("workspaces").join("ops"), home.join("agents").join("ops").join("agent"), "dashscope:qwen-plus"))
    agents.put("list", list)
    root.put("agents", agents)
    File.writeTo(MetisConfigManager.configPath(), root.toJsonString().toArray())
    CliConfig.invalidatePathCache()
    MetisConfigManager.invalidate()
    CliSettingManager.invalidate()
}

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
    public func gatewayDefaultChatRuntimeNowIncludesVideoGenerationTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        @Expect(names.contains("gateway_video_generate"), true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesImageGenerationTool(): Unit {
        let names = gatewayDefaultChatToolNames()
        @Expect(names.contains("gateway_image_generate"), true)
    }

    @TestCase
    public func gatewayDefaultChatRuntimeNowIncludesTelegramMediaTools(): Unit {
        let names = gatewayDefaultChatToolNames()
        @Expect(names.contains("telegram_media_list"), true)
        @Expect(names.contains("telegram_media_get"), true)
        @Expect(names.contains("telegram_media_save"), true)
        @Expect(names.contains("telegram_media_read"), true)
        @Expect(names.contains("telegram_image_analyze"), true)
        @Expect(names.contains("telegram_audio_transcribe"), true)
        @Expect(names.contains("telegram_sticker_search"), true)
        @Expect(names.contains("telegram_sticker_get"), true)
        @Expect(names.contains("telegram_sticker_cache_stats"), true)
        @Expect(names.contains("telegram_media_send"), true)
        @Expect(names.contains("telegram_target_list"), true)
        @Expect(names.contains("telegram_doctor"), true)
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

    @TestCase
    public func gatewayTurnRouteToolPolicyNarrowsLiveToolManager(): Unit {
        let route = JsonObject()
        let tools = JsonObject()
        tools.put("allow", JsonArray([JsonString("weather")]))
        route.put("tools", tools)
        let context = GatewayTurnContext(
            "writer",
            sessionKey: "agent:writer:telegram:group:-100",
            channelName: "telegram",
            accountId: "bot-a",
            peerId: "group:-100",
            route: route
        )

        let names = gatewayPolicyFilteredChatToolNamesForTurnContext(context)

        @Expect(names.contains("weather"), true)
        @Expect(names.contains("shellExecute"), false)
        @Expect(names.contains("sessions_spawn"), false)
    }

    @TestCase
    public func gatewaySystemPromptUsesTurnWorkspaceBootstrap(): Unit {
        withAgentBridgeTempHome("metis-phase4-agent-bridge-prompt", { home: Path =>
            writeAgentBridgeAgentConfig(home)
            let writerWorkspace = home.join("workspaces").join("writer")
            let opsWorkspace = home.join("workspaces").join("ops")
            Directory.create(writerWorkspace, recursive: true)
            Directory.create(opsWorkspace, recursive: true)
            File.writeTo(writerWorkspace.join("SOUL.md"), "# Soul\n\nwriter-only-soul\n".toArray())
            File.writeTo(opsWorkspace.join("SOUL.md"), "# Soul\n\nops-only-soul\n".toArray())

            let writerContext = gatewayResolveSessionContext(
                GatewaySessionRequest(
                    GatewayIngressSource.DashboardRpc,
                    sessionHint: "main",
                    agentId: "writer"
                )
            )
            let opsContext = gatewayResolveSessionContext(
                GatewaySessionRequest(
                    GatewayIngressSource.DashboardRpc,
                    sessionHint: "main",
                    agentId: "ops"
                )
            )

            let writerPrompt = gatewayPolicyFilteredSystemPromptForTurnContext(
                writerContext.turnContext,
                channelName: "dashboard",
                modelName: "openai:gpt-4o-mini"
            )
            let opsPrompt = gatewayPolicyFilteredSystemPromptForTurnContext(
                opsContext.turnContext,
                channelName: "dashboard",
                modelName: "dashscope:qwen-plus"
            )

            @Expect(writerPrompt.contains("writer-only-soul"), true)
            @Expect(writerPrompt.contains("ops-only-soul"), false)
            @Expect(opsPrompt.contains("ops-only-soul"), true)
            @Expect(opsPrompt.contains("writer-only-soul"), false)
        })
    }

    @TestCase
    public func gatewayModelOrderAndRuntimeFilesUseTurnAgentDir(): Unit {
        withAgentBridgeTempHome("metis-phase4-agent-bridge-models", { home: Path =>
            writeAgentBridgeAgentConfig(home)
            let writerContext = gatewayResolveSessionContext(
                GatewaySessionRequest(
                    GatewayIngressSource.DashboardRpc,
                    sessionHint: "main",
                    agentId: "writer"
                )
            )
            let opsContext = gatewayResolveSessionContext(
                GatewaySessionRequest(
                    GatewayIngressSource.DashboardRpc,
                    sessionHint: "main",
                    agentId: "ops"
                )
            )

            let writerModels = gatewayDebugModelOrderForTurnContext(writerContext.turnContext)
            let opsModels = gatewayDebugModelOrderForTurnContext(opsContext.turnContext)

            @Expect(writerModels.size > 0, true)
            @Expect(opsModels.size > 0, true)
            @Expect(writerModels[0], "openai:gpt-4o-mini")
            @Expect(opsModels[0], "dashscope:qwen-plus")
            @Expect(exists(home.join("agents").join("writer").join("agent").join("models.json")), true)
            @Expect(exists(home.join("agents").join("ops").join("agent").join("models.json")), true)
            @Expect(exists(home.join("models.json")), false)
        })
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
