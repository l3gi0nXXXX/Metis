package metis.core.prompting

import metis.core.memory.{MemoryPromptSectionBuilder, buildMemoryPromptSectionForToolNames, clearMemoryPluginState, getMemoryFlushPlanResolver, getMemoryPromptSectionBuilder, getMemoryRuntime, registerMemoryPromptSection, restoreMemoryPluginState}

import std.collection.ArrayList
import std.collection.HashSet
import std.unittest.testmacro.*

private class TestPromptSectionBuilder <: MemoryPromptSectionBuilder {
    public func build(availableTools: HashSet<String>, citationsMode: String): Array<String> {
        let lines = ArrayList<String>()
        lines.add("Use memory section.")
        lines.add("memory_search available=${availableTools.contains("memory_search")}")
        lines.add("citations=${citationsMode}")
        lines.toArray()
    }
}

private func repeatPromptText(text: String, count: Int64): String {
    var out = ""
    for (_ in 0..count) {
        out += text
    }
    out
}

private func promptIndex(prompt: String, needle: String): Int64 {
    match (prompt.indexOf(needle)) {
        case Some(index) => index
        case None => -1
    }
}

@Test
public class MetisSystemPromptBuilderTest {
    @TestCase
    public func silentReplyGuidanceUsesAsciiOnlyMarkers(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("❌ Wrong:"), false)
        @Expect(prompt.contains("✅ Right:"), false)
        @Expect(prompt.contains("❌"), false)
        @Expect(prompt.contains("✅"), false)
        @Expect(prompt.contains("Wrong: \"Here's help... <SILENT_REPLY>\""), true)
        @Expect(prompt.contains("Right: <SILENT_REPLY>"), true)
    }

    @TestCase
    public func buildIncludesRegisteredMemoryPromptSection(): Unit {
        let previousPrompt = getMemoryPromptSectionBuilder()
        let previousFlush = getMemoryFlushPlanResolver()
        let previousRuntime = getMemoryRuntime()
        try {
            clearMemoryPluginState()
            registerMemoryPromptSection(TestPromptSectionBuilder())
            let params = MetisSystemPromptParams()
            params.promptMode = PromptMode.FullMode
            params.toolNames = ["memory_search"]
            params.memoryPromptSectionLines = buildMemoryPromptSectionForToolNames(params.toolNames)
            let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
            @Expect(prompt.contains("## Memory"), true)
            @Expect(prompt.contains("Use memory section."), true)
            @Expect(prompt.contains("memory_search available=true"), true)
        } finally {
            restoreMemoryPluginState(
                promptBuilder: previousPrompt,
                flushPlanResolver: previousFlush,
                runtime: previousRuntime
            )
        }
    }

    @TestCase
    public func explicitNativeApprovalUiUsesNativeApprovalGuidance(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.runtimeInfo.nativeApprovalUiAvailable = true
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(
            prompt.contains("rely on native approval card/buttons when they appear"),
            true
        )
        @Expect(
            prompt.contains("include the concrete /approve command from tool output as plain chat text for the user"),
            false
        )
    }

    @TestCase
    public func runtimeCapabilityNativeApprovalUiUsesNativeApprovalGuidance(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.runtimeInfo.capabilities = ["native-approval-ui"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(
            prompt.contains("rely on native approval card/buttons when they appear"),
            true
        )
    }

    @TestCase
    public func manualApprovalGuidanceRemainsDefaultWithoutNativeApprovalSignals(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(
            prompt.contains("include the concrete /approve command from tool output as plain chat text for the user"),
            true
        )
        @Expect(
            prompt.contains("rely on native approval card/buttons when they appear"),
            false
        )
    }

    @TestCase
    public func sessionStatusGuidanceUsesNativeWording(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.userTimezone = "Asia/Shanghai"
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(
            prompt.contains("If you need the current date, time, or day of week, run session_status."),
            true
        )
        @Expect(prompt.contains("compatibility placeholder"), false)
    }

    @TestCase
    public func selfUpdateActionsDescribeRuntimeEffects(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.toolNames = ["gateway"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(
            prompt.contains("High-risk gateway actions stay visible on the unified Gateway main runtime, but require owner approval before execution."),
            true
        )
        @Expect(
            prompt.contains("Do not run config.patch, config.apply, or update.run unless the user explicitly requests an update or config change; if it's not explicit, ask first."),
            true
        )
        @Expect(
            prompt.contains("gateway.controlUi.allowInsecureAuth"),
            true
        )
        @Expect(
            prompt.contains("config.apply (validate + write full config, then restart)"),
            true
        )
        @Expect(
            prompt.contains("config.patch (partial update, merges with existing)"),
            true
        )
        @Expect(
            prompt.contains("update.run (update deps or git, then restart)"),
            true
        )
    }

    @TestCase
    public func selfUpdateSectionOnlyAppearsWhenGatewayToolIsAvailable(): Unit {
        let withGateway = MetisSystemPromptParams()
        withGateway.promptMode = PromptMode.FullMode
        withGateway.toolNames = ["gateway"]
        let withGatewayPrompt = MetisSystemPromptBuilder.build(withGateway, cangjieMode: false)
        @Expect(withGatewayPrompt.contains("## Metis Self-Update"), true)

        let withoutGateway = MetisSystemPromptParams()
        withoutGateway.promptMode = PromptMode.FullMode
        withoutGateway.toolNames = ["shellExecute"]
        let withoutGatewayPrompt = MetisSystemPromptBuilder.build(withoutGateway, cangjieMode: false)
        @Expect(withoutGatewayPrompt.contains("## Metis Self-Update"), false)
    }

    /*
    @TestCase
    public func messagingSectionUsesNativeWordingWithoutCompatibilityPlaceholder(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.toolNames = ["message"]
        params.runtimeInfo.channel = "qq"
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("### message tool"), true)
        @Expect(prompt.contains("- For `action=send`, include `to` and `message`."), true)
        @Expect(
            prompt.contains("Rewrite those in your normal assistant voice and send the update (do not forward raw internal metadata or default to <SILENT_REPLY>)."),
            true
        )
        @Expect(
            prompt.contains("- If you use `message` (`action=send`) to deliver your user-visible reply, respond with ONLY: <SILENT_REPLY> (avoid duplicate replies)."),
            true
        )
        @Expect(
            prompt.contains("- Inline buttons not enabled for qq. If you need them, ask to set qq.capabilities.inlineButtons (\"dm\"|\"group\"|\"all\"|\"allowlist\")."),
            true
        )
        @Expect(prompt.contains("Message-tool compatibility note"), false)
    }

    @TestCase
    public func messagingSectionReportsInlineButtonsWhenCapabilityIsPresent(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.toolNames = ["message"]
        params.runtimeInfo.channel = "webchat"
        params.runtimeInfo.capabilities = ["inlinebuttons"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(
            prompt.contains("- Inline buttons supported. Use `action=send` with `buttons=[[{text,callback_data,style?}]]`; `style` can be `primary`, `success`, or `danger`."),
            true
        )
        @Expect(prompt.contains("- Inline buttons not enabled for webchat."), false)
    }
    */

    @TestCase
    public func processGuidanceOnlyAppearsWhenProcessToolIsAvailable(): Unit {
        let withProcess = MetisSystemPromptParams()
        withProcess.promptMode = PromptMode.FullMode
        withProcess.toolNames = ["shellExecute", "process"]
        let withProcessPrompt = MetisSystemPromptBuilder.build(withProcess, cangjieMode: false)
        @Expect(withProcessPrompt.contains("process(action=poll, timeout=<ms>)"), true)
        @Expect(withProcessPrompt.contains("use process to confirm completion"), true)

        let withoutProcess = MetisSystemPromptParams()
        withoutProcess.promptMode = PromptMode.FullMode
        withoutProcess.toolNames = ["shellExecute"]
        let withoutProcessPrompt = MetisSystemPromptBuilder.build(withoutProcess, cangjieMode: false)
        @Expect(withoutProcessPrompt.contains("process(action=poll, timeout=<ms>)"), false)
        @Expect(withoutProcessPrompt.contains("use process to confirm completion"), false)
        @Expect(withoutProcessPrompt.contains("use shellExecute with enough yieldMs."), true)
    }

    @TestCase
    public func promptOmitsShellAndSubagentGuidanceWhenToolsAreUnavailable(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.toolNames = ["weather", "sessions_spawn"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("shellExecute"), false)
        @Expect(prompt.contains("subagents"), false)
        @Expect(prompt.contains("sessions_spawn"), true)
    }

    @TestCase
    public func subagentNaturalLanguageGuidanceAppearsWithSessionsSpawn(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.toolNames = ["sessions_spawn", "subagents"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("## Subagent Orchestration"), true)
        @Expect(prompt.contains("call `sessions_spawn` with `runtime: \"subagent\"`"), true)
        @Expect(prompt.contains("\"后台\""), true)
        @Expect(prompt.contains("\"并行\""), true)
        @Expect(prompt.contains("\"完成后通知\""), true)
        @Expect(prompt.contains("do not wait for the subagent to finish"), true)
        @Expect(prompt.contains("Completion notification is push-based"), true)
        @Expect(prompt.contains("use `effectiveState` and `isActive`"), true)
        @Expect(prompt.contains("multiple requested background agents"), true)
        @Expect(prompt.contains("one `sessions_spawn` call per role/task"), true)
        @Expect(prompt.contains("Do the work yourself for small, quick, single-focus tasks"), true)
        @Expect(prompt.contains("Use `subagents` only for on-demand list/status/logs/kill/steer/send control"), true)
    }

    @TestCase
    public func subagentNaturalLanguageGuidanceRequiresSessionsSpawnTool(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.toolNames = ["subagents"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("## Subagent Orchestration"), false)
        @Expect(prompt.contains("call `sessions_spawn` with `runtime: \"subagent\"`"), false)
    }

    @TestCase
    public func acpHarnessGuidanceStaysCapabilityGated(): Unit {
        let blocked = MetisSystemPromptParams()
        blocked.promptMode = PromptMode.FullMode
        blocked.toolNames = ["sessions_spawn"]
        blocked.acpEnabled = false
        let blockedPrompt = MetisSystemPromptBuilder.build(blocked, cangjieMode: false)
        @Expect(blockedPrompt.contains("For ACP harness requests like Codex/Claude Code/Cursor/Gemini"), false)

        let allowed = MetisSystemPromptParams()
        allowed.promptMode = PromptMode.FullMode
        allowed.toolNames = ["sessions_spawn"]
        allowed.acpEnabled = true
        let allowedPrompt = MetisSystemPromptBuilder.build(allowed, cangjieMode: false)
        @Expect(allowedPrompt.contains("For ACP harness requests like Codex/Claude Code/Cursor/Gemini"), true)
    }

    @TestCase
    public func sandboxLiteralFieldsAreSanitizedToSingleLine(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.workspaceDir = "/host/work\nspace"
        params.sandboxInfo.enabled = true
        params.sandboxInfo.containerWorkspaceDir = "/tmp/work\nspace"
        params.sandboxInfo.workspaceDir = "/host/root\r\nproject"
        params.sandboxInfo.agentWorkspaceMount = "/mnt/agent\nworkspace"
        params.sandboxInfo.workspaceAccess = "workspace-write"
        params.sandboxInfo.browserNoVncUrl = "http://localhost:6080/\nviewer"
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(
            prompt.contains("For read/write/edit/apply_patch, file paths resolve against host workspace: /host/work space. For bash/exec commands, use sandbox container paths under /tmp/work space"),
            true
        )
        @Expect(prompt.contains("Sandbox container workdir: /tmp/work space"), true)
        @Expect(prompt.contains("Sandbox host mount source (file tools bridge only; not valid inside sandbox exec): /host/root project"), true)
        @Expect(prompt.contains("Agent workspace access: workspace-write (mounted at /mnt/agent workspace)"), true)
        @Expect(prompt.contains("Sandbox browser observer (noVNC): http://localhost:6080/ viewer"), true)
    }

    @TestCase
    public func minimalModeUsesSubagentBoundariesWithoutFullOnlySections(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.MinimalMode
        params.docsPath = "/docs/local"
        params.heartbeatPrompt = "heartbeat"
        params.extraSystemPrompt = "extra context"
        params.toolNames = ["gateway", "sessions_spawn"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("## Subagent Context"), true)
        @Expect(prompt.contains("## Documentation"), false)
        @Expect(prompt.contains("## Metis Self-Update"), false)
        @Expect(prompt.contains("## Silent Replies"), false)
        @Expect(prompt.contains("## Heartbeats"), false)
        @Expect(prompt.contains("## Skills (mandatory)"), false)
        @Expect(prompt.contains("## Memory"), false)
        @Expect(prompt.contains("## Memory Recall"), false)
        @Expect(prompt.contains("## Runtime"), true)
        @Expect(prompt.contains("## Workspace"), true)
        @Expect(prompt.contains("## Workspace Files (injected)"), true)
        @Expect(prompt.contains("ACP harness compatibility note"), false)
    }

    @TestCase
    public func noneModeReturnsIdentityLineOnly(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.NoneMode
        params.docsPath = "/docs/local"
        params.extraSystemPrompt = "extra context"
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt == "You are an AI assistant.", true)
    }

    @TestCase
    public func fullModeDoesNotInjectLegacyBrandIdentity(): Unit {
        let params = MetisSystemPromptParams()
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("running inside Metis"), false)
        @Expect(
            prompt.contains("Do not describe yourself as Metis, Magic CLI, or a local app unless the user explicitly asks about the runtime or product identity."),
            true
        )
    }

    @TestCase
    public func projectContextUsesMetisStableOrderingAndDynamicBoundary(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.contextFiles = [
            MetisContextFile("zeta.md", "zeta"),
            MetisContextFile("sub/heartbeat.md", "heartbeat"),
            MetisContextFile("tools.md", "tools"),
            MetisContextFile("agents.md", "agents"),
            MetisContextFile("alpha.md", "alpha")
        ]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        let projectContextIndex = promptIndex(prompt, "# Project Context")
        let agentsIndex = promptIndex(prompt, "## agents.md")
        let toolsIndex = promptIndex(prompt, "## tools.md")
        let alphaIndex = promptIndex(prompt, "## alpha.md")
        let zetaIndex = promptIndex(prompt, "## zeta.md")
        let boundaryIndex = promptIndex(prompt, "<SYSTEM_PROMPT_CACHE_BOUNDARY>")
        let dynamicContextIndex = promptIndex(prompt, "# Dynamic Project Context")
        let heartbeatIndex = promptIndex(prompt, "## sub/heartbeat.md")
        @Expect(projectContextIndex >= 0, true)
        @Expect(agentsIndex > projectContextIndex, true)
        @Expect(toolsIndex > agentsIndex, true)
        @Expect(alphaIndex > toolsIndex, true)
        @Expect(zetaIndex > alphaIndex, true)
        @Expect(boundaryIndex > zetaIndex, true)
        @Expect(dynamicContextIndex > boundaryIndex, true)
        @Expect(heartbeatIndex > boundaryIndex, true)
    }

    @TestCase
    public func projectContextShowsSoulGuidanceAndOrdersSameBasenameByPath(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.contextFiles = [
            MetisContextFile("z/notes.md", "z"),
            MetisContextFile("a/notes.md", "a"),
            MetisContextFile("SOUL.md", "soul"),
            MetisContextFile("   ", "ignored")
        ]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        let soulGuidanceIndex = promptIndex(prompt, "If SOUL.md is present, embody its persona and tone.")
        let soulIndex = promptIndex(prompt, "## SOUL.md")
        let aNotesIndex = promptIndex(prompt, "## a/notes.md")
        let zNotesIndex = promptIndex(prompt, "## z/notes.md")
        @Expect(soulGuidanceIndex >= 0, true)
        @Expect(soulIndex > soulGuidanceIndex, true)
        @Expect(aNotesIndex > soulIndex, true)
        @Expect(zNotesIndex > aNotesIndex, true)
        @Expect(prompt.contains("##    "), false)
    }

    /*
    @TestCase
    public func fullModeRuntimeCombinationKeepsParityCriticalSectionsAligned(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.toolNames = ["gateway", "update_plan", "message", "memory_search", "cron"]
        params.docsPath = "/docs/local"
        params.userTimezone = "Asia/Shanghai"
        params.heartbeatPrompt = "ping"
        params.extraSystemPrompt = "chat context"
        params.workspaceDir = "/host/workspace"
        params.runtimeInfo.channel = "webchat"
        params.runtimeInfo.capabilities = ["native-approval-ui", "inlinebuttons", "thread-reply"]
        params.sandboxInfo.enabled = true
        params.sandboxInfo.containerWorkspaceDir = "/sandbox/workspace"
        params.sandboxInfo.workspaceDir = "/host/workspace"
        params.sandboxInfo.agentWorkspaceMount = "/mnt/workspace"
        params.sandboxInfo.workspaceAccess = "workspace-write"
        params.contextFiles = [
            MetisContextFile("agents.md", "agents"),
            MetisContextFile("heartbeat.md", "heartbeat"),
            MetisContextFile("tools.md", "tools")
        ]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        let toolCallIndex = promptIndex(prompt, "## Tool Call Style")
        let workspaceIndex = promptIndex(prompt, "## Workspace")
        let sandboxIndex = promptIndex(prompt, "## Sandbox")
        let workspaceFilesIndex = promptIndex(prompt, "## Workspace Files (injected)")
        let silentRepliesIndex = promptIndex(prompt, "## Silent Replies")
        let boundaryIndex = promptIndex(prompt, "<SYSTEM_PROMPT_CACHE_BOUNDARY>")
        let dynamicContextIndex = promptIndex(prompt, "# Dynamic Project Context")
        let groupContextIndex = promptIndex(prompt, "## Group Chat Context")
        let heartbeatsIndex = promptIndex(prompt, "## Heartbeats")
        let runtimeIndex = promptIndex(prompt, "## Runtime")
        @Expect(prompt.contains("compatibility placeholder"), false)
        @Expect(prompt.contains("ACP harness compatibility note"), false)
        @Expect(prompt.contains("Message-tool compatibility note"), false)
        @Expect(prompt.contains("rely on native approval card/buttons when they appear"), true)
        @Expect(
            prompt.contains("- If you use `message` (`action=send`) to deliver your user-visible reply, respond with ONLY: <SILENT_REPLY> (avoid duplicate replies)."),
            true
        )
        @Expect(
            prompt.contains("- Inline buttons supported. Use `action=send` with `buttons=[[{text,callback_data,style?}]]`; `style` can be `primary`, `success`, or `danger`."),
            true
        )
        @Expect(prompt.contains("Sandbox container workdir: /sandbox/workspace"), true)
        @Expect(prompt.contains("If you need the current date, time, or day of week, run session_status."), true)
        @Expect(toolCallIndex >= 0, true)
        @Expect(workspaceIndex > toolCallIndex, true)
        @Expect(sandboxIndex > workspaceIndex, true)
        @Expect(workspaceFilesIndex > sandboxIndex, true)
        @Expect(silentRepliesIndex > workspaceFilesIndex, true)
        @Expect(boundaryIndex > silentRepliesIndex, true)
        @Expect(dynamicContextIndex > boundaryIndex, true)
        @Expect(groupContextIndex > dynamicContextIndex, true)
        @Expect(heartbeatsIndex > groupContextIndex, true)
        @Expect(runtimeIndex > heartbeatsIndex, true)
    }
    */

    @TestCase
    public func fullModeRuntimeCombinationKeepsStableContextBeforeDynamicContext(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.contextFiles = [
            MetisContextFile("memory.md", "memory"),
            MetisContextFile("sub/heartbeat.md", "hb"),
            MetisContextFile("identity.md", "identity")
        ]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        let stableProjectContextIndex = promptIndex(prompt, "# Project Context")
        let identityIndex = promptIndex(prompt, "## identity.md")
        let memoryIndex = promptIndex(prompt, "## memory.md")
        let boundaryIndex = promptIndex(prompt, "<SYSTEM_PROMPT_CACHE_BOUNDARY>")
        let dynamicProjectContextIndex = promptIndex(prompt, "# Dynamic Project Context")
        let heartbeatIndex = promptIndex(prompt, "## sub/heartbeat.md")
        @Expect(stableProjectContextIndex >= 0, true)
        @Expect(identityIndex > stableProjectContextIndex, true)
        @Expect(memoryIndex > identityIndex, true)
        @Expect(boundaryIndex > memoryIndex, true)
        @Expect(dynamicProjectContextIndex > boundaryIndex, true)
        @Expect(heartbeatIndex > dynamicProjectContextIndex, true)
    }

    @TestCase
    public func phaseOneBudgetHelperDoesNotChangePromptInjectionYet(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        let largeContent = repeatPromptText("memory-line-", 2500)
        params.contextFiles = [MetisContextFile("memory.md", largeContent)]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains(largeContent), true)
        @Expect(prompt.contains("[...truncated, read memory.md for full content...]"), false)
    }

    @TestCase
    public func gatewayRuntimeChannelUsesCompactFixedSections(): Unit {
        let params = MetisSystemPromptParams()
        params.promptMode = PromptMode.FullMode
        params.runtimeInfo.channel = "telegram"
        params.toolNames = ["gateway", "message"]
        params.docsPath = "/docs/local"
        params.modelAliasLines = ["alias -> provider/model"]
        let prompt = MetisSystemPromptBuilder.build(params, cangjieMode: false)
        @Expect(prompt.contains("## Tooling"), true)
        @Expect(prompt.contains("## Safety"), true)
        @Expect(prompt.contains("## Metis CLI Quick Reference"), false)
        @Expect(prompt.contains("## Documentation"), false)
        @Expect(prompt.contains("## Metis Self-Update"), false)
        @Expect(prompt.contains("## Model Aliases"), false)
        @Expect(prompt.contains("### message tool"), false)
        @Expect(prompt.contains("## Silent Replies"), true)
    }
}
