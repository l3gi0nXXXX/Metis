package metis.cliapp

import magic.log.LogUtils
import magic.core.agent.Agent
import magic.core.model.ChatModel

import metis.core.mcp.MCPConfigManager
import metis.core.conversation.ConversationManager
import metis.core.commands.CustomCommandManager
import metis.core.model.TokenStatusManager
import metis.core.config.CliConfig
import metis.core.agents.*
import metis.core.agents.subagents.*
import metis.io.*
import metis.gateway.runtime.{gatewayLaunchDedicatedConsole, gatewayAnotherServeInstanceSeemsRunning}

import std.collection.ArrayList
import std.fs.{Path, exists, Directory, canonicalize}
import std.collection.HashMap
import std.sync.{Mutex, AtomicOptionReference}

private func resolveInternalBuiltinSubagent(): Option<Agent> {
    let name = CliConfig.internalSubagent.trimAscii().toAsciiLower().replace("-", "_")
    if (name.isEmpty()) {
        return None
    }
    match (name) {
        case "explorer" | "exploreragent" => Some(ExplorerAgent())
        case "editor" | "edit" | "editoragent" => Some(EditorAgent())
        case "reviewer" | "review" | "revieweragent" => Some(ReviewerAgent())
        case "test_generator" | "testgenerator" | "testgeneratoragent" => Some(TestGeneratorAgent())
        case "refactoring" | "refactor" | "refactoringagent" => Some(RefactoringAgent())
        case "planner" | "planneragent" => Some(PlannerAgent())
        case _ => None
    }
}

protected class CliApp {
    private let mutex = Mutex()
    protected let agent: Agent
    protected let thinkIndicator = AtomicOptionReference<StatusIndicator>()
    protected let conversationManager: ConversationManager
    protected let customCommandManager: CustomCommandManager
    protected let customAgentManager: CustomAgentManager
    protected let mcpManager: MCPConfigManager
    protected let tokenStatusManager: TokenStatusManager

    protected init() {
        this.agent = if (let Some(internalSubagent) <- resolveInternalBuiltinSubagent()) {
            if (!CliConfig.internalSubagentSystemPrompt.trimAscii().isEmpty()) {
                internalSubagent.systemPrompt =
                    CliConfig.internalSubagentSystemPrompt.trimAscii() + "\n\n" + internalSubagent.systemPrompt
            }
            internalSubagent
        } else {
            let lang = CliConfig.language.toAsciiLower()
            if (lang == 'cangjie') {
                CangjieCodeAgent()
            } else if (lang.startsWith("agent:")) {
                // Currently, this is an internal experimental feature
                // Customized agent: --language agent:<agent_dir>
                let agentDir = lang["agent:".size..]
                CustomAgent(canonicalize(agentDir))
            } else {
                GeneralCodeAgent()
            }
        }
        // Load MCP servers and add their tools to the agent
        this.mcpManager = MCPConfigManager()
        try {
            agent.toolManager.addTools(mcpManager.loadMCPServers())
        } catch (ex: Exception) {
            LogUtils.error("Failed to load MCP servers: ${ex.message}")
            PrintUtils.printProcedureFailure("MCP Loading", failure: "Failed to load MCP servers, continuing without MCP tools")
        }

        this.conversationManager = ConversationManager(FileContextCompactor())
        this.customCommandManager = CustomCommandManager()
        this.customAgentManager = CustomAgentManager()
        this.tokenStatusManager = TokenStatusManager()

        // Initialize event handlers and callbacks
        registerHooks(this)
    }

    func startThinkIndicator(message: String) {
        this.thinkIndicator.store(PrintUtils.printStatusIndicator(message: message))
    }

    func stopThinkIndicator() {
        // Multiple threads may stop the thinkIndicator at the same time:
        // 1. stopped in ChatModelEndEvent by one thread
        // 2. stopped by the main thread when canceling the execution.
        synchronized(this.mutex) {
            if (let Some(i) <- this.thinkIndicator.swap(None)) {
                i.stop()
            }
        }
    }

    protected func startNonInteractive(input: String): Unit {
        processInput(this, input)
        return
    }

    private func printInteractiveModePreamble(mode: String): Unit {
        let low = mode.trimAscii().toAsciiLower()
        if (low == "setup") {
            PrintUtils.printLine("[setup] First-run setup mode. Recommended next steps: configure model credentials, verify gateway status, then start chatting.")
            PrintUtils.printLine("[setup] Inside the shell, use /models, /plugin, /channel, /memory, or /dashboard as needed. Prefer static Control UI assets (bundled by default, or gateway.controlUi.root); inline dashboard fallback is legacy-only.")
            PrintUtils.printLine("[setup] Interactive chat requires the unified Gateway main runtime. Start it with `metis gateway run`, or use `metis agent --local --message \"...\"` for explicit embedded-only debugging.")
            return
        }
        if (low == "onboard") {
            PrintUtils.printLine("[onboard] Onboarding mode. Recommended flow: review status, connect channels/plugins, verify tools, then run a first prompt.")
            PrintUtils.printLine("[onboard] Inside the shell, use /models, /plugin, /channel, /memory, or /dashboard as needed. Prefer root commands such as 'metis status'; production Control UI should come from bundled static assets or gateway.controlUi.root.")
            PrintUtils.printLine("[onboard] CLI chat uses the unified Gateway main runtime by default. `--local` is reserved for explicit embedded-only debugging.")
            return
        }
        if (low == "configure") {
            PrintUtils.printLine("[configure] Configuration mode. Use this shell to update model credentials, plugin settings, channel bindings, and defaults.")
            PrintUtils.printLine("[configure] Recommended commands: /models, /plugin set, /channel set, /memory status.")
            return
        }
        if (low == "tui" || low == "chat") {
            PrintUtils.printLine("[interactive] Entering the interactive shell through '${low}'.")
        }
    }

    protected func startInteractive(mode!: String = "interactive"): Unit {
        let low = mode.trimAscii().toAsciiLower()
        if (low != "onboard") {
            PrintUtils.printWelcome()
        }
        printInteractiveModePreamble(mode)
        if (CliConfig.autoStartGatewayWindow) {
            if (gatewayAnotherServeInstanceSeemsRunning()) {
                PrintUtils.printLine(
                    "[网关] 已跳过自动打开：检测到网关可能仍在运行（~/.metis/gateway-serve.lock）。请先关闭旧网关窗口，再使用 --start-gateway-window 或执行显式 gateway 命令。"
                )
            } else {
                // 显式 --start-gateway-window：须给出可见错误（总开关/渠道/cjpm 目录），勿用静默早退的 autoLaunch 变体
                let _ = gatewayLaunchDedicatedConsole()
            }
        }
        // Simplified event loop
        while (true) {
            // Update the context usage footnote after each input processing
            this.setContextUsageFootnote()

            let input = InputUtils.getUserInput()
            if (input.trimAscii().isEmpty()) {
                continue
            }
            // Process input and check whether to continue
            if (!processInput(this, input)) {
                break
            }
        }
    }

    /**
    * Display the context usage percentage as the footnote of the readline prompt
    */
    private func setContextUsageFootnote(): Unit {
        // Get the last available model or the default model
        try {
            let percentage = this.tokenStatusManager.contextUsagePercentage
            let remaining = max(0, 100 - percentage)
            let footnote = padString(
                "Context: ${remaining}% remaining".withColor(Theme.current.muted),
                align: Align.Right
            )
            InputUtils.getReadline().setFootnote(footnote)
        } catch (ex: Exception) {
            LogUtils.error("Failed to compute context usage ${ex.message}")
            InputUtils.getReadline().setFootnote("")
        }
    }
}
